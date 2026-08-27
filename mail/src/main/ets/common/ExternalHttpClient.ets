import { http } from '@kit.NetworkKit'

import { ApiException, ApiResponse } from './HttpClient'

export class ExternalHttpClient {
  static async get(baseUrl: string, path: string, token: string = ''): Promise<ApiResponse> {
    return ExternalHttpClient.request(baseUrl, path, http.RequestMethod.GET, '', token)
  }

  static async post(baseUrl: string, path: string, body: string, token: string = ''): Promise<ApiResponse> {
    return ExternalHttpClient.request(baseUrl, path, http.RequestMethod.POST, body, token)
  }

  static async put(baseUrl: string, path: string, body: string, token: string = ''): Promise<ApiResponse> {
    return ExternalHttpClient.request(baseUrl, path, http.RequestMethod.PUT, body, token)
  }

  static async delete(baseUrl: string, path: string, token: string = ''): Promise<ApiResponse> {
    return ExternalHttpClient.request(baseUrl, path, http.RequestMethod.DELETE, '', token)
  }

  private static async request(baseUrl: string, path: string, method: http.RequestMethod, body: string,
    token: string): Promise<ApiResponse> {
    const request: http.HttpRequest = http.createHttp()
    const url: string = ExternalHttpClient.createUrl(baseUrl, path)
    try {
      let response: http.HttpResponse
      if (token !== '') {
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
      const content: string = response.result as string
      const headerText: string = JSON.stringify(response.header).toLowerCase()
      const isJsonResponse: boolean = headerText.includes('application/json') || headerText.includes('+json') ||
        ExternalHttpClient.looksLikeJson(content)
      if (response.responseCode < 200 || response.responseCode >= 300) {
        const parsedError: ApiResponse | null = isJsonResponse ? ExternalHttpClient.tryParseResponse(content) : null
        const apiError: ApiResponse | null = parsedError === null ? null :
          ExternalHttpClient.normalizeResponse(parsedError, response.responseCode)
        const message: string = apiError === null || apiError.message === '' ?
          '邮箱服务请求失败（HTTP ' + response.responseCode.toString() + '）' : apiError.message
        const code: number = apiError === null || apiError.code === -1 ? response.responseCode : apiError.code
        throw new ApiException(code, message, response.responseCode >= 500)
      }
      if (!isJsonResponse) {
        throw new ApiException(response.responseCode, '邮箱服务未返回 JSON 数据', false)
      }
      const parsedResponse: ApiResponse | null = ExternalHttpClient.tryParseResponse(content)
      if (parsedResponse === null) {
        throw new ApiException(response.responseCode, '服务器返回了无法识别的内容', false)
      }
      const apiResponse: ApiResponse = ExternalHttpClient.normalizeResponse(parsedResponse, response.responseCode)
      if (apiResponse.code !== 200) {
        const message: string = apiResponse.message === '' ? '服务器请求失败，请稍后重试' : apiResponse.message
        throw new ApiException(apiResponse.code, message, apiResponse.code >= 500)
      }
      return apiResponse
    } catch (err) {
      if (err instanceof ApiException) {
        throw err
      }
      throw new ApiException(-1, '无法连接邮箱服务，请检查地址和网络', true)
    } finally {
      request.destroy()
    }
  }

  private static looksLikeJson(content: string): boolean {
    const trimmed: string = content.trim()
    return trimmed.startsWith('{') || trimmed.startsWith('[')
  }

  private static tryParseResponse(content: string): ApiResponse | null {
    try {
      return JSON.parse(content) as ApiResponse
    } catch (parseError) {
      return null
    }
  }

  private static normalizeResponse(source: ApiResponse, httpCode: number): ApiResponse {
    if (source.code !== undefined) {
      source.message = source.message === undefined ? '' : source.message
      source.data = source.data === undefined ? null : source.data
      return source
    }
    const response: ApiResponse = new ApiResponse()
    response.code = httpCode
    response.message = source.message === undefined ? '' : source.message
    response.data = source as Object
    return response
  }

  private static createUrl(baseUrl: string, path: string): string {
    let normalizedBase: string = baseUrl.trim()
    const schemeIndex: number = normalizedBase.indexOf('://')
    if (schemeIndex >= 0) {
      const prefix: string = normalizedBase.substring(0, schemeIndex + 3)
      let remainder: string = normalizedBase.substring(schemeIndex + 3)
      while (remainder.includes('//')) {
        remainder = remainder.replace('//', '/')
      }
      normalizedBase = prefix + remainder
    }
    while (normalizedBase.endsWith('/')) {
      normalizedBase = normalizedBase.substring(0, normalizedBase.length - 1)
    }
    return path.startsWith('/') ? normalizedBase + path : normalizedBase + '/' + path
  }
}
