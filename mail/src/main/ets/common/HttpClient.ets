import { http } from '@kit.NetworkKit'
import { SessionService } from './SessionService'
import { RequestScope } from './RequestScope'

export class ApiResponse {
  code: number = -1
  message: string = ''
  data: Object | null = null
}

export class ApiException extends Error {
  code: number
  message: string
  retryable: boolean

  constructor(code: number, message: string, retryable: boolean) {
    super(message)
    this.code = code
    this.message = message
    this.retryable = retryable
  }
}

export class QueryParameter {
  key: string
  value: string

  constructor(key: string, value: string) {
    this.key = key
    this.value = value
  }
}

export class HttpClient {
  static async get(path: string, requiresAuthorization: boolean = true): Promise<ApiResponse> {
    return HttpClient.request(path, http.RequestMethod.GET, '', requiresAuthorization, '')
  }

  static async post(path: string, body: string, requiresAuthorization: boolean = true): Promise<ApiResponse> {
    return HttpClient.request(path, http.RequestMethod.POST, body, requiresAuthorization, '')
  }

  static async put(path: string, body: string, requiresAuthorization: boolean = true): Promise<ApiResponse> {
    return HttpClient.request(path, http.RequestMethod.PUT, body, requiresAuthorization, '')
  }

  static async delete(path: string, requiresAuthorization: boolean = true, tokenOverride: string = ''): Promise<ApiResponse> {
    return HttpClient.request(path, http.RequestMethod.DELETE, '', requiresAuthorization, tokenOverride)
  }

  static appendQuery(path: string, parameters: QueryParameter[]): string {
    if (parameters.length === 0) {
      return path
    }
    let result: string = path + '?'
    for (let i = 0; i < parameters.length; i++) {
      if (i > 0) {
        result += '&'
      }
      result += encodeURIComponent(parameters[i].key) + '=' + encodeURIComponent(parameters[i].value)
    }
    return result
  }

  private static async request(path: string, method: http.RequestMethod, body: string, requiresAuthorization: boolean,
    tokenOverride: string): Promise<ApiResponse> {
    const scope: RequestScope = HttpClient.captureScope()
    const token: string = tokenOverride === '' ? scope.token : tokenOverride
    const url: string = HttpClient.createUrl(scope.apiBaseUrl, path)
    let lastError: ApiException = new ApiException(-1, '网络连接失败，请检查网络后重试', true)
    const retryTimes: number = method === http.RequestMethod.GET ? 2 : 1
    for (let attempt = 0; attempt < retryTimes; attempt++) {
      HttpClient.ensureCurrentScope(scope)
      try {
        const result: ApiResponse = await HttpClient.requestOnce(url, method, body, requiresAuthorization, token, scope)
        HttpClient.ensureCurrentScope(scope)
        return result
      } catch (err) {
        if (err instanceof ApiException) {
          lastError = err
          if (!err.retryable) {
            throw err
          }
        } else {
          lastError = new ApiException(-1, '网络连接失败，请检查网络后重试', true)
        }
      }
    }
    throw lastError
  }

  private static async requestOnce(url: string, method: http.RequestMethod, body: string, requiresAuthorization: boolean,
    token: string, scope: RequestScope): Promise<ApiResponse> {
    const request: http.HttpRequest = http.createHttp()
    try {
      let response: http.HttpResponse
      if (requiresAuthorization && token !== '') {
        if (body === '') {
          response = await request.request(url, {
            method: method,
            expectDataType: http.HttpDataType.STRING,
            usingCache: false,
            connectTimeout: 10000,
            readTimeout: 20000,
            header: { 'Accept': 'application/json', 'Authorization': token }
          })
        } else {
          response = await request.request(url, {
            method: method,
            extraData: body,
            expectDataType: http.HttpDataType.STRING,
            usingCache: false,
            connectTimeout: 10000,
            readTimeout: 20000,
            header: { 'Accept': 'application/json', 'Content-Type': 'application/json', 'Authorization': token }
          })
        }
      } else {
        if (body === '') {
          response = await request.request(url, {
            method: method,
            expectDataType: http.HttpDataType.STRING,
            usingCache: false,
            connectTimeout: 10000,
            readTimeout: 20000,
            header: { 'Accept': 'application/json' }
          })
        } else {
          response = await request.request(url, {
            method: method,
            extraData: body,
            expectDataType: http.HttpDataType.STRING,
            usingCache: false,
            connectTimeout: 10000,
            readTimeout: 20000,
            header: { 'Accept': 'application/json', 'Content-Type': 'application/json' }
          })
        }
      }
      // A late response must never update or log out a different instance/account.
      HttpClient.ensureCurrentScope(scope)
      if (response.responseCode === 401) {
        HttpClient.clearOwnedSession(scope, requiresAuthorization, token)
        throw new ApiException(401, requiresAuthorization ? '登录已过期，请重新登录' :
          '身份验证失败，请检查登录信息后重试', false)
      }
      if (typeof response.result !== 'string') {
        throw new ApiException(-3, '邮箱服务返回了非 API 内容，请检查服务地址', false)
      }
      const apiResponse: ApiResponse = HttpClient.parseResponse(response.result as string)
      if (response.responseCode < 200 || response.responseCode >= 300) {
        const message: string = apiResponse.message === '' ?
          '邮箱服务请求失败（HTTP ' + response.responseCode.toString() + '）' : apiResponse.message
        throw new ApiException(response.responseCode, message, response.responseCode >= 500)
      }
      if (apiResponse.code === 401) {
        HttpClient.clearOwnedSession(scope, requiresAuthorization, token)
        throw new ApiException(401, apiResponse.message === '' ? '登录已过期，请重新登录' : apiResponse.message, false)
      }
      if (apiResponse.code !== 200) {
        throw new ApiException(apiResponse.code, apiResponse.message === '' ? '请求失败，请稍后重试' : apiResponse.message,
          apiResponse.code >= 500)
      }
      return apiResponse
    } catch (err) {
      if (err instanceof ApiException) {
        throw err
      }
      HttpClient.ensureCurrentScope(scope)
      console.error('http request failed')
      throw new ApiException(-1, '网络连接失败，请检查网络后重试', true)
    } finally {
      request.destroy()
    }
  }

  private static captureScope(): RequestScope {
    const email: string | undefined = AppStorage.get('authEmail') as string | undefined
    const revision: number | undefined = AppStorage.get('sessionRevision') as number | undefined
    return new RequestScope(SessionService.getActiveInstanceId(), SessionService.getApiBaseUrl(),
      SessionService.getToken(), email === undefined ? '' : email, revision === undefined ? 0 : revision)
  }

  private static ensureCurrentScope(scope: RequestScope): void {
    if (!RequestScope.matches(scope, HttpClient.captureScope())) {
      throw new ApiException(-2, '邮箱服务或登录账号已切换，已取消原请求', false)
    }
  }

  private static clearOwnedSession(scope: RequestScope, requiresAuthorization: boolean, token: string): void {
    if (RequestScope.canClearSession(scope, HttpClient.captureScope(), requiresAuthorization, token)) {
      SessionService.clearSession()
    }
  }

  private static parseResponse(content: string): ApiResponse {
    const trimmed: string = content.trim()
    if (!trimmed.startsWith('{')) {
      throw new ApiException(-3, '邮箱服务返回了网页或非 API 内容，请检查服务地址及访问限制', false)
    }
    let parsed: ApiResponse
    try {
      parsed = JSON.parse(trimmed) as ApiResponse
    } catch (parseError) {
      throw new ApiException(-3, '邮箱服务返回了无效的 JSON 数据，请稍后重试', false)
    }
    if (parsed === null || typeof parsed.code !== 'number' || !Number.isFinite(parsed.code)) {
      throw new ApiException(-3, '邮箱服务返回的数据格式不兼容，请检查服务地址', false)
    }
    const response: ApiResponse = new ApiResponse()
    response.code = parsed.code
    response.message = typeof parsed.message === 'string' ? parsed.message : ''
    response.data = parsed.data === undefined ? null : parsed.data
    return response
  }

  private static createUrl(apiBaseUrl: string, path: string): string {
    if (path.indexOf('http://') === 0 || path.indexOf('https://') === 0) {
      return path
    }
    if (path.indexOf('/') === 0) {
      return apiBaseUrl + path
    }
    return apiBaseUrl + '/' + path
  }
}
