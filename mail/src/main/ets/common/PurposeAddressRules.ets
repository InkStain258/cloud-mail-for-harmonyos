export class PurposeAddressEntry {
  label: string = ''
  tag: string = ''
  address: string = ''
}

// Purpose addresses are receive-only aliases routed to an existing mailbox.
// They are not server accounts and deleting a label does not disable delivery.
export class PurposeAddressRules {
  static readonly LIMIT: number = 30

  static isBaseMailbox(email: string): boolean {
    const parts: string[] = email.split('@')
    if (parts.length !== 2 || parts[0].length === 0 || parts[0].length > 64 || email.length > 254) {
      return false
    }
    return /^[A-Za-z0-9.!#$%&'*\-/=?^_`{|}~]+$/.test(parts[0]) &&
      parts[0].charAt(0) !== '.' && parts[0].charAt(parts[0].length - 1) !== '.' &&
      parts[0].indexOf('..') < 0 && /^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$/.test(parts[1]) &&
      parts[1].indexOf('..') < 0
  }

  static create(baseEmail: string, tag: string, label: string): PurposeAddressEntry {
    if (!PurposeAddressRules.isBaseMailbox(baseEmail)) {
      throw new Error('purpose_invalid_mailbox')
    }
    const cleanTag: string = tag.trim().toLowerCase()
    const cleanLabel: string = label.trim()
    if (!/^[a-z0-9][a-z0-9_-]{0,31}$/.test(cleanTag)) {
      throw new Error('purpose_invalid_tag')
    }
    if (cleanLabel.length === 0 || cleanLabel.length > 30 || /[\u0000-\u001f\u007f]/.test(cleanLabel)) {
      throw new Error('purpose_invalid_label')
    }
    const separator: number = baseEmail.lastIndexOf('@')
    const local: string = baseEmail.substring(0, separator) + '+' + cleanTag
    const address: string = local + baseEmail.substring(separator)
    if (local.length > 64 || address.length > 254) {
      throw new Error('purpose_address_too_long')
    }
    const entry: PurposeAddressEntry = new PurposeAddressEntry()
    entry.label = cleanLabel
    entry.tag = cleanTag
    entry.address = address
    return entry
  }

  static parse(raw: string, baseEmail: string): PurposeAddressEntry[] {
    const parsed: PurposeAddressEntry[] = JSON.parse(raw) as PurposeAddressEntry[]
    if (!Array.isArray(parsed) || parsed.length > PurposeAddressRules.LIMIT) {
      throw new Error('purpose_storage_failed')
    }
    const result: PurposeAddressEntry[] = []
    for (let index = 0; index < parsed.length; index++) {
      const item: PurposeAddressEntry = parsed[index]
      if (item === null || typeof item.tag !== 'string' || typeof item.label !== 'string' ||
        typeof item.address !== 'string') {
        throw new Error('purpose_storage_failed')
      }
      const entry: PurposeAddressEntry = PurposeAddressRules.create(baseEmail, item.tag, item.label)
      if (entry.address !== item.address || result.some((saved: PurposeAddressEntry): boolean => saved.tag === entry.tag)) {
        throw new Error('purpose_storage_failed')
      }
      result.push(entry)
    }
    return result
  }
}
