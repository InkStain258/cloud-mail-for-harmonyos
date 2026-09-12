// A request belongs to the session captured before its first network attempt.
// The revision distinguishes switching away and back, even if the token is unchanged.
export class RequestScope {
  readonly instanceId: string
  readonly apiBaseUrl: string
  readonly token: string
  readonly email: string
  readonly revision: number

  constructor(instanceId: string, apiBaseUrl: string, token: string, email: string, revision: number) {
    this.instanceId = instanceId
    this.apiBaseUrl = apiBaseUrl
    this.token = token
    this.email = email
    this.revision = revision
  }

  static matches(owner: RequestScope, current: RequestScope): boolean {
    return owner.instanceId === current.instanceId && owner.apiBaseUrl === current.apiBaseUrl &&
      owner.token === current.token && owner.email === current.email && owner.revision === current.revision
  }

  static canClearSession(owner: RequestScope, current: RequestScope, requiresAuthorization: boolean,
    requestToken: string): boolean {
    return requiresAuthorization && requestToken !== '' && requestToken === owner.token &&
      RequestScope.matches(owner, current)
  }
}
