export class MailResourceUrl {
  static attachmentBase(apiBaseUrl: string): string {
    return MailResourceUrl.normalizeBase(apiBaseUrl) + 'oss/'
  }

  static mediaBase(domain: string, apiBaseUrl: string): string {
    const value: string = domain.trim()
    if (value === '') { return MailResourceUrl.attachmentBase(apiBaseUrl) }
    const withScheme: string = /^https?:\/\//i.test(value) ? value : 'https://' + value
    return MailResourceUrl.normalizeBase(withScheme)
  }

  static attachmentUrl(apiBaseUrl: string, key: string): string {
    if (key === '' || key.indexOf('://') >= 0 || key.startsWith('/') || key.indexOf('\\') >= 0) {
      throw new Error('Invalid attachment key')
    }
    const segments: string[] = key.split('/')
    const encoded: string[] = []
    for (let index = 0; index < segments.length; index++) {
      if (segments[index] === '.' || segments[index] === '..' || segments[index] === '') {
        throw new Error('Invalid attachment key')
      }
      encoded.push(encodeURIComponent(segments[index]))
    }
    return MailResourceUrl.attachmentBase(apiBaseUrl) + encoded.join('/')
  }

  private static normalizeBase(value: string): string {
    const base: string = value.trim().replace(/\/+$/, '')
    // Resource URLs never inherit credentials, query parameters or a fragment from a server config.
    if (!/^https?:\/\/[^\s/?#@]+(?:\/[^\s?#]*)?$/i.test(base)) {
      throw new Error('Invalid resource base URL')
    }
    return base + '/'
  }
}
