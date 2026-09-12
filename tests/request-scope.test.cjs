const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const test = require('node:test')

// Run the production .ets implementation with only NetworkKit and session storage mocked.
// Set TYPESCRIPT_PATH when DevEco Studio is installed in a different directory.
const ts = require(process.env.TYPESCRIPT_PATH ||
  'D:/DevEco Studio/tools/hvigor/hvigor/node_modules/typescript')
const sourceRoot = path.resolve(__dirname, '../mail/src/main/ets/common')

function loadSource(name, imports, storage) {
  const source = fs.readFileSync(path.join(sourceRoot, name + '.ets'), 'utf8')
  const compiled = ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
  }).outputText
  const module = { exports: {} }
  new Function('require', 'module', 'exports', 'AppStorage', compiled)(
    (specifier) => {
      assert.ok(Object.hasOwn(imports, specifier), 'Unexpected import: ' + specifier)
      return imports[specifier]
    }, module, module.exports, storage)
  return module.exports
}

const { RequestScope } = loadSource('RequestScope', {})

function response(code = 200, data = { items: ['mail-a'] }, httpCode = 200) {
  return { responseCode: httpCode, result: JSON.stringify({ code, data, message: '' }) }
}

function runtime(handlers) {
  const session = {
    instanceId: 'instance-a', apiBaseUrl: 'https://a.example/api', token: 'test-token-a',
    authEmail: 'member@a.example', sessionRevision: 1
  }
  const calls = []
  let destroyed = 0
  let cleared = 0
  const mocks = {
    '@kit.NetworkKit': {
      http: {
        RequestMethod: { GET: 'GET', POST: 'POST', PUT: 'PUT', DELETE: 'DELETE' },
        HttpDataType: { STRING: 'string' },
        createHttp: () => ({
          request: async (url, options) => {
            const index = calls.length
            calls.push({ url, options })
            assert.ok(handlers[index], 'Unexpected extra network attempt')
            return handlers[index](session)
          },
          destroy: () => { destroyed++ }
        })
      }
    },
    './SessionService': {
      SessionService: {
        getActiveInstanceId: () => session.instanceId,
        getApiBaseUrl: () => session.apiBaseUrl,
        getToken: () => session.token,
        clearSession: () => {
          cleared++
          session.token = ''
          session.authEmail = ''
          session.sessionRevision++
        }
      }
    },
    './RequestScope': { RequestScope }
  }
  const source = loadSource('HttpClient', mocks, { get: (key) => session[key] })
  return {
    ...source, session, calls,
    get destroyed() { return destroyed },
    get cleared() { return cleared }
  }
}

function assertApiError(code, retryable) {
  return (error) => {
    assert.equal(error.code, code)
    assert.equal(error.retryable, retryable)
    return true
  }
}

test('scope comparison includes instance, address, token, email, and session generation', () => {
  const values = ['a', 'https://a.example/api', 'test-token', 'member@a.example', 3]
  const owner = new RequestScope(...values)
  assert.equal(RequestScope.matches(owner, new RequestScope(...values)), true)
  for (let index = 0; index < values.length; index++) {
    const changed = [...values]
    changed[index] = index === 4 ? 4 : 'different'
    assert.equal(RequestScope.matches(owner, new RequestScope(...changed)), false)
  }
  assert.equal(RequestScope.canClearSession(owner, owner, true, 'test-token'), true)
  assert.equal(RequestScope.canClearSession(owner, owner, false, 'test-token'), false)
  assert.equal(RequestScope.canClearSession(owner, owner, true, 'test-other'), false)
})

test('GET retries transient network error against the original URL and credentials', async () => {
  const app = runtime([() => { throw new Error('network failure') }, () => response()])
  assert.deepEqual((await app.HttpClient.get('/email/list')).data.items, ['mail-a'])
  assert.equal(app.calls.length, 2)
  assert.equal(app.destroyed, 2)
  for (const call of app.calls) {
    assert.equal(call.url, 'https://a.example/api/email/list')
    assert.equal(call.options.header.Authorization, 'test-token-a')
    assert.equal(call.options.usingCache, false)
  }
})

for (const field of ['instanceId', 'apiBaseUrl', 'token', 'authEmail', 'sessionRevision']) {
  test('late success is cancelled after ' + field + ' changes', async () => {
    const app = runtime([(session) => {
      session[field] = field === 'sessionRevision' ? session[field] + 1 : 'changed'
      return response()
    }])
    await assert.rejects(app.HttpClient.get('/email/list'), assertApiError(-2, false))
    assert.equal(app.calls.length, 1)
    assert.equal(app.destroyed, 1)
    assert.equal(app.cleared, 0)
  })
}

test('network failure after instance switch does not retry in the new instance', async () => {
  const app = runtime([(session) => {
    session.instanceId = 'instance-b'
    session.apiBaseUrl = 'https://b.example/api'
    session.token = 'test-token-b'
    session.sessionRevision++
    throw new Error('old request failed')
  }])
  await assert.rejects(app.HttpClient.get('/email/list'), assertApiError(-2, false))
  assert.equal(app.calls.length, 1)
  assert.equal(app.destroyed, 1)
  assert.equal(app.cleared, 0)
})

test('switching away and back cancels the old request even when owner and token match', async () => {
  const app = runtime([(session) => {
    session.sessionRevision += 2
    return response()
  }])
  await assert.rejects(app.HttpClient.get('/email/list'), assertApiError(-2, false))
  assert.equal(app.cleared, 0)
})

for (const httpCode of [200, 401]) {
  test('late 401 cannot clear the newly active session (HTTP ' + httpCode + ')', async () => {
    const app = runtime([(session) => {
      session.instanceId = 'instance-b'
      session.token = 'test-token-b'
      session.sessionRevision++
      return response(401, null, httpCode)
    }])
    await assert.rejects(app.HttpClient.get('/my/loginUserInfo'), assertApiError(-2, false))
    assert.equal(app.cleared, 0)
    assert.equal(app.session.token, 'test-token-b')
    assert.equal(app.destroyed, 1)
  })

  test('matching authorized 401 clears only its own session (HTTP ' + httpCode + ')', async () => {
    const app = runtime([() => response(401, null, httpCode)])
    await assert.rejects(app.HttpClient.get('/my/loginUserInfo'), assertApiError(401, false))
    assert.equal(app.cleared, 1)
    assert.equal(app.destroyed, 1)
  })

  test('public login 401 does not clear a logged-in session (HTTP ' + httpCode + ')', async () => {
    const app = runtime([() => response(401, null, httpCode)])
    await assert.rejects(app.HttpClient.post('/login', '{}', false), assertApiError(401, false))
    assert.equal(app.cleared, 0)
    assert.equal(app.calls[0].options.header.Authorization, undefined)
  })

  test('logout with an old override token cannot clear current credentials (HTTP ' + httpCode + ')', async () => {
    const app = runtime([() => response(401, null, httpCode)])
    await assert.rejects(app.HttpClient.delete('/logout', true, 'old-test-token'), assertApiError(401, false))
    assert.equal(app.cleared, 0)
    assert.equal(app.session.token, 'test-token-a')
  })
}

for (const method of ['post', 'put', 'delete']) {
  test(method + ' never retries an uncertain network failure', async () => {
    const app = runtime([() => { throw new Error('network failure') }])
    const promise = method === 'delete' ? app.HttpClient.delete('/resource') : app.HttpClient[method]('/resource', '{}')
    await assert.rejects(promise, assertApiError(-1, true))
    assert.equal(app.calls.length, 1)
    assert.equal(app.destroyed, 1)
  })
  test(method + ' never retries an HTTP 503 response', async () => {
    const app = runtime([() => response(503, null, 503)])
    const promise = method === 'delete' ? app.HttpClient.delete('/resource') : app.HttpClient[method]('/resource', '{}')
    await assert.rejects(promise, assertApiError(503, true))
    assert.equal(app.calls.length, 1)
    assert.equal(app.destroyed, 1)
  })
}

test('GET may retry a server failure without changing its request owner', async () => {
  const app = runtime([() => response(503, null, 503), () => response()])
  await app.HttpClient.get('/email/list')
  assert.equal(app.calls.length, 2)
  assert.equal(app.destroyed, 2)
})

for (const content of ['<!doctype html><title>Sign in</title>', 'null', '[]', '{', '{}', '{"code":"200"}']) {
  test('invalid API content is classified separately from network errors: ' + content, async () => {
    const app = runtime([() => ({ responseCode: 200, result: content })])
    await assert.rejects(app.HttpClient.get('/email/list'), assertApiError(-3, false))
    assert.equal(app.calls.length, 1)
    assert.equal(app.destroyed, 1)
    assert.equal(app.cleared, 0)
  })
}

test('HTML gateway responses expose no response body or login secrets in the message', async () => {
  const app = runtime([() => ({ responseCode: 502, result: '<html>DO_NOT_EXPOSE_BODY</html>' })])
  await assert.rejects(app.HttpClient.get('/email/list'), (error) => {
    assertApiError(-3, false)(error)
    assert.match(error.message, /非 API/)
    assert.equal(error.message.includes('DO_NOT_EXPOSE_BODY'), false)
    return true
  })
  assert.equal(app.calls.length, 1)
})
