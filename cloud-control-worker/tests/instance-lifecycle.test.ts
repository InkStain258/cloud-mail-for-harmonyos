import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { DatabaseSync } from 'node:sqlite'
import test from 'node:test'

import worker from '../src/index.ts'

const PLATFORM_SECRET = 'test-platform-secret-with-sufficient-entropy'
const SUPER_ADMIN_ID = 910001
const MEMBER_ID = 910002
const ANCHOR_INSTANCE_ID = 'riordon-cloud-mail'
const EXTERNAL_INSTANCE_ID = 'external-instance'
const DISABLED_INSTANCE_ID = 'disabled-instance'

class TestD1Statement {
  constructor(statement) {
    this.statement = statement
    this.values = []
  }

  bind(...values) {
    this.values = values
    return this
  }

  first() {
    return this.statement.get(...this.values) ?? null
  }

  all() {
    return { results: this.statement.all(...this.values) }
  }

  run() {
    const result = this.statement.run(...this.values)
    return { success: true, meta: { changes: Number(result.changes) } }
  }
}

class TestD1Database {
  constructor(database) {
    this.database = database
  }

  prepare(sql) {
    return new TestD1Statement(this.database.prepare(sql))
  }

  async batch(statements) {
    this.database.exec('BEGIN')
    try {
      const results = statements.map((statement) => statement.run())
      this.database.exec('COMMIT')
      return results
    } catch (error) {
      this.database.exec('ROLLBACK')
      throw error
    }
  }
}

function createHarness() {
  const database = new DatabaseSync(':memory:')
  database.exec(readFileSync(new URL('../migrations/0001_platform_identity.sql', import.meta.url), 'utf8'))
  database.exec(readFileSync(new URL('../migrations/0003_legacy_anchor_import_and_owner_guard.sql', import.meta.url), 'utf8'))
  database.exec(
    "INSERT INTO platform_user " +
    "(platform_user_id, huawei_user_id, open_id, nick_name, platform_role) VALUES " +
    `(${SUPER_ADMIN_ID}, 'test-super-admin', 'test-super-admin', 'Test Admin', 'SUPER_ADMIN'), ` +
    `(${MEMBER_ID}, 'test-member', 'test-member', 'Test Member', 'MEMBER')`
  )
  database.exec(
    "INSERT INTO mail_instance " +
    "(instance_id, display_name, api_base_url, origin_host, status, created_by) VALUES " +
    `('${ANCHOR_INSTANCE_ID}', 'Anchor', 'https://anchor.test/api', 'anchor.test', 'ACTIVE', ${SUPER_ADMIN_ID}), ` +
    `('${EXTERNAL_INSTANCE_ID}', 'External', 'https://external.test/api', 'external.test', 'ACTIVE', ` +
    `${SUPER_ADMIN_ID}), ` +
    `('${DISABLED_INSTANCE_ID}', 'Disabled', 'https://disabled.test/api', 'disabled.test', 'DISABLED', ` +
    `${SUPER_ADMIN_ID})`
  )
  database.exec(
    "INSERT INTO instance_binding " +
    "(platform_user_id, instance_id, local_user_key, local_email, local_role_name, instance_role, status) VALUES " +
    `(${SUPER_ADMIN_ID}, '${EXTERNAL_INSTANCE_ID}', 'admin', 'admin@external.test', 'admin', ` +
    "'INSTANCE_OWNER', 'ACTIVE'), " +
    `(${SUPER_ADMIN_ID}, '${DISABLED_INSTANCE_ID}', 'old-admin', 'admin@disabled.test', 'admin', ` +
    "'INSTANCE_OWNER', 'DISABLED')"
  )
  return {
    database,
    env: {
      DB: new TestD1Database(database),
      HUAWEI_CLIENT_ID: 'unused-client-id',
      HUAWEI_CLIENT_SECRET: 'unused-client-secret',
      PLATFORM_JWT_SECRET: PLATFORM_SECRET,
      ANCHOR_INSTANCE_API_BASE_URL: 'https://anchor.test/api',
      SUPER_ADMIN_HUAWEI_IDS: 'test-super-admin',
      ALLOWED_ORIGINS: 'https://app.test'
    }
  }
}

function base64Url(value) {
  return Buffer.from(value).toString('base64url')
}

async function platformToken(userId, huaweiUserId, role) {
  const now = Math.floor(Date.now() / 1000)
  const header = base64Url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }))
  const payload = base64Url(JSON.stringify({
    sub: userId,
    huaweiUserId,
    role,
    iat: now,
    exp: now + 600
  }))
  const signingInput = header + '.' + payload
  const key = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(PLATFORM_SECRET), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
  const signature = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(signingInput))
  return signingInput + '.' + base64Url(new Uint8Array(signature))
}

async function callApi(env, token, method, path, body = null, origin = '') {
  const headers = new Headers({ Authorization: 'Bearer ' + token })
  if (body !== null) {
    headers.set('Content-Type', 'application/json')
  }
  if (origin !== '') {
    headers.set('Origin', origin)
  }
  const request = new Request('https://control.test' + path, {
    method,
    headers,
    body: body === null ? undefined : JSON.stringify(body)
  })
  return worker.fetch(request, env)
}

test('super admin can rename an active instance and the operation is audited', async () => {
  const harness = createHarness()
  try {
    const token = await platformToken(SUPER_ADMIN_ID, 'test-super-admin', 'SUPER_ADMIN')
    const response = await callApi(
      harness.env, token, 'PUT', '/api/platform/admin/instances/' + EXTERNAL_INSTANCE_ID,
      { displayName: '  Renamed Service  ' })
    assert.equal(response.status, 200)
    const row = harness.database.prepare(
      'SELECT display_name FROM mail_instance WHERE instance_id = ?').get(EXTERNAL_INSTANCE_ID)
    assert.equal(row.display_name, 'Renamed Service')
    const audit = harness.database.prepare(
      "SELECT action FROM platform_audit_log WHERE instance_id = ? AND action = 'INSTANCE_RENAME'")
      .get(EXTERNAL_INSTANCE_ID)
    assert.equal(audit.action, 'INSTANCE_RENAME')
  } finally {
    harness.database.close()
  }
})

test('ordinary platform members cannot rename instances', async () => {
  const harness = createHarness()
  try {
    const token = await platformToken(MEMBER_ID, 'test-member', 'MEMBER')
    const response = await callApi(
      harness.env, token, 'PUT', '/api/platform/admin/instances/' + EXTERNAL_INSTANCE_ID,
      { displayName: 'Forbidden Rename' })
    assert.equal(response.status, 403)
    const row = harness.database.prepare(
      'SELECT display_name FROM mail_instance WHERE instance_id = ?').get(EXTERNAL_INSTANCE_ID)
    assert.equal(row.display_name, 'External')
  } finally {
    harness.database.close()
  }
})

test('deleting an external instance soft-disables the instance and its active bindings', async () => {
  const harness = createHarness()
  try {
    const token = await platformToken(SUPER_ADMIN_ID, 'test-super-admin', 'SUPER_ADMIN')
    const response = await callApi(
      harness.env, token, 'DELETE', '/api/platform/admin/instances/' + EXTERNAL_INSTANCE_ID)
    assert.equal(response.status, 200)
    const instance = harness.database.prepare(
      'SELECT status FROM mail_instance WHERE instance_id = ?').get(EXTERNAL_INSTANCE_ID)
    const binding = harness.database.prepare(
      'SELECT status FROM instance_binding WHERE instance_id = ?').get(EXTERNAL_INSTANCE_ID)
    assert.equal(instance.status, 'DISABLED')
    assert.equal(binding.status, 'DISABLED')
    const audit = harness.database.prepare(
      "SELECT action FROM platform_audit_log WHERE instance_id = ? AND action = 'INSTANCE_DISABLE'")
      .get(EXTERNAL_INSTANCE_ID)
    assert.equal(audit.action, 'INSTANCE_DISABLE')
  } finally {
    harness.database.close()
  }
})

test('the anchor instance cannot be deleted', async () => {
  const harness = createHarness()
  try {
    const token = await platformToken(SUPER_ADMIN_ID, 'test-super-admin', 'SUPER_ADMIN')
    const response = await callApi(
      harness.env, token, 'DELETE', '/api/platform/admin/instances/' + ANCHOR_INSTANCE_ID)
    assert.equal(response.status, 409)
    const instance = harness.database.prepare(
      'SELECT status FROM mail_instance WHERE instance_id = ?').get(ANCHOR_INSTANCE_ID)
    assert.equal(instance.status, 'ACTIVE')
  } finally {
    harness.database.close()
  }
})

test('adding a disabled service reuses its instance id without reviving old bindings', async () => {
  const harness = createHarness()
  const originalFetch = globalThis.fetch
  globalThis.fetch = async (input) => {
    const url = String(input)
    if (url === 'https://disabled.test/api/setting/websiteConfig') {
      return Response.json({ code: 200, data: { title: 'Recovered Service' } })
    }
    throw new Error('unexpected fetch: ' + url)
  }
  try {
    const token = await platformToken(SUPER_ADMIN_ID, 'test-super-admin', 'SUPER_ADMIN')
    const response = await callApi(
      harness.env, token, 'POST', '/api/platform/admin/instances',
      { apiBaseUrl: 'https://disabled.test/', displayName: '' })
    assert.equal(response.status, 200)
    const envelope = await response.json()
    assert.equal(envelope.data.instanceId, DISABLED_INSTANCE_ID)
    const instance = harness.database.prepare(
      'SELECT display_name, status FROM mail_instance WHERE instance_id = ?').get(DISABLED_INSTANCE_ID)
    const binding = harness.database.prepare(
      'SELECT status FROM instance_binding WHERE instance_id = ?').get(DISABLED_INSTANCE_ID)
    assert.equal(instance.display_name, 'Recovered Service')
    assert.equal(instance.status, 'ACTIVE')
    assert.equal(envelope.data.apiBaseUrl, 'https://disabled.test/api')
    assert.equal(binding.status, 'DISABLED')
    const audit = harness.database.prepare(
      "SELECT action FROM platform_audit_log WHERE instance_id = ? AND action = 'INSTANCE_REACTIVATE'")
      .get(DISABLED_INSTANCE_ID)
    assert.equal(audit.action, 'INSTANCE_REACTIVATE')
  } finally {
    globalThis.fetch = originalFetch
    harness.database.close()
  }
})

test('CORS preflight advertises the instance update method', async () => {
  const harness = createHarness()
  try {
    const request = new Request('https://control.test/api/platform/admin/instances/' + EXTERNAL_INSTANCE_ID, {
      method: 'OPTIONS',
      headers: { Origin: 'https://app.test' }
    })
    const response = await worker.fetch(request, harness.env)
    assert.equal(response.status, 204)
    assert.match(response.headers.get('Access-Control-Allow-Methods') || '', /\bPUT\b/)
  } finally {
    harness.database.close()
  }
})
