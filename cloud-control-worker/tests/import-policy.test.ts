import assert from 'node:assert/strict'
import test from 'node:test'
import {
  isAnchorImportAuthority,
  isProtectedInstance,
  loadLegacyAnchorBindings,
  normalizeInstanceDisplayName
} from '../src/index.ts'

test('instance names are normalized and bounded', () => {
  assert.equal(normalizeInstanceDisplayName('  Team Mail  '), 'Team Mail')
  assert.equal(normalizeInstanceDisplayName('', 'Fallback'), 'Fallback')
  assert.throws(() => normalizeInstanceDisplayName(''), /服务名称不能为空/)
  assert.throws(() => normalizeInstanceDisplayName('x'.repeat(61)), /不能超过 60 个字符/)
})

test('the anchor instance is protected from deletion', () => {
  assert.equal(isProtectedInstance('riordon-cloud-mail'), true)
  assert.equal(isProtectedInstance('external-instance'), false)
})

test('anchor import requires both platform super admin and matching instance admin', () => {
  const admin = { email: 'admin@example.com', role: { name: 'admin' } }
  assert.equal(isAnchorImportAuthority('SUPER_ADMIN', admin, 'admin@example.com'), true)
  assert.equal(isAnchorImportAuthority('MEMBER', admin, 'admin@example.com'), false)
  assert.equal(isAnchorImportAuthority('SUPER_ADMIN', { ...admin, role: { name: 'user' } },
    'admin@example.com'), false)
  assert.equal(isAnchorImportAuthority('SUPER_ADMIN', admin, 'other@example.com'), false)
})

test('legacy import reads bounded pagination beyond one page', async () => {
  const originalFetch = globalThis.fetch
  const items = Array.from({ length: 113 }, (_, index) => ({
    huaweiAccountId: index + 1,
    huaweiUserId: 'masked-' + (index + 1),
    nickName: 'user-' + (index + 1),
    primaryEmail: 'user-' + (index + 1) + '@example.com'
  }))
  const requestedPages: number[] = []
  globalThis.fetch = (async (input: string | URL | Request) => {
    const url = new URL(String(input))
    const page = Number(url.searchParams.get('page'))
    requestedPages.push(page)
    const start = (page - 1) * 100
    return Response.json({
      code: 200,
      data: { list: items.slice(start, start + 100), total: items.length, page, size: 100 }
    })
  }) as typeof fetch
  try {
    const result = await loadLegacyAnchorBindings('https://mail.example.com/api', 'temporary-token')
    assert.equal(result.sourceTotal, 113)
    assert.equal(result.list.length, 113)
    assert.deepEqual(requestedPages, [1, 2])
  } finally {
    globalThis.fetch = originalFetch
  }
})

test('a later-page failure rejects instead of accepting a truncated snapshot', async () => {
  const originalFetch = globalThis.fetch
  globalThis.fetch = (async (input: string | URL | Request) => {
    const page = Number(new URL(String(input)).searchParams.get('page'))
    if (page === 2) {
      return new Response('upstream failure', { status: 500 })
    }
    return Response.json({
      code: 200,
      data: {
        list: Array.from({ length: 100 }, (_, index) => ({
          huaweiAccountId: index + 1,
          primaryEmail: 'user-' + index + '@example.com'
        })),
        total: 101,
        page: 1,
        size: 100
      }
    })
  }) as typeof fetch
  try {
    await assert.rejects(loadLegacyAnchorBindings('https://mail.example.com/api', 'temporary-token'))
  } finally {
    globalThis.fetch = originalFetch
  }
})
