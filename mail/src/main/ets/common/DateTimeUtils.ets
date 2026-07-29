export class DateTimeUtils {
  private static readonly localDateTimeFormatter: Intl.DateTimeFormat = new Intl.DateTimeFormat('zh-CN', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23'
  })

  static formatUtcDateTime(value: string | undefined | null, emptyText: string = ''): string {
    if (value === undefined || value === null) {
      return emptyText
    }
    const source: string = value.trim()
    if (source === '') {
      return emptyText
    }

    const utcText: string = DateTimeUtils.normalizeUtcDateTime(source)
    const date: Date = new Date(utcText)
    if (Number.isNaN(date.getTime())) {
      return DateTimeUtils.formatFallback(source)
    }

    let formatted: string = DateTimeUtils.localDateTimeFormatter.format(date)
    formatted = formatted.replace('/', '-')
    formatted = formatted.replace('/', '-')
    return formatted.replace(',', '')
  }

  private static normalizeUtcDateTime(value: string): string {
    let normalized: string = value.replace(' ', 'T')
    if (normalized.length === 10) {
      return normalized + 'T00:00:00Z'
    }
    if (!DateTimeUtils.hasTimeZone(normalized)) {
      normalized += 'Z'
    }
    return normalized
  }

  private static hasTimeZone(value: string): boolean {
    if (value.endsWith('Z') || value.endsWith('z')) {
      return true
    }
    const timeIndex: number = value.indexOf('T')
    if (timeIndex < 0) {
      return false
    }
    return value.lastIndexOf('+') > timeIndex || value.lastIndexOf('-') > timeIndex
  }

  private static formatFallback(value: string): string {
    const normalized: string = value.replace('T', ' ')
    return normalized.substring(0, Math.min(normalized.length, 16))
  }
}
