import {
  AbilityAware,
  AbilityPluginBinding,
  FlutterPlugin,
  FlutterPluginBinding,
  Log,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import common from '@ohos.app.ability.common';
import { authentication } from '@kit.AccountKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'HmsAccountOhosPlugin';

const AUTH_SERVICE_CHANNEL = 'com.huawei.hms.flutter.account/acc';
const AUTH_MANAGER_CHANNEL = 'com.huawei.hms.flutter.account/acc/manager';
const AUTH_TOOL_CHANNEL = 'com.huawei.hms.flutter.account/hwid/auth';
const NETWORK_TOOL_CHANNEL = 'com.huawei.hms.flutter.account/hwid/network';
const SMS_MANAGER_CHANNEL = 'com.huawei.hms.flutter.account/hwid/sms';

class ChannelInfoResult {
  description: string = '';
  describeContents: number = 0;
}

interface ScopeLike {
  mScopeUri?: string;
}

class AccountKitResponseData {
  accessToken?: string = undefined;
  serviceCountryCode?: string = undefined;
  displayName?: string = undefined;
  nickName?: string = undefined;
  email?: string = undefined;
  familyName?: string = undefined;
  givenName?: string = undefined;
  gender?: number = undefined;
  grantedScopes?: Array<Object> = undefined;
  authorizedScopes?: Array<Object> = undefined;
  idToken?: string = undefined;
  avatarUri?: string = undefined;
  photoUriString?: string = undefined;
  authorizationCode?: string = undefined;
  unionId?: string = undefined;
  unionID?: string = undefined;
  openId?: string = undefined;
  openID?: string = undefined;
  accountFlag?: number = undefined;
  carrierId?: number = undefined;
}

class AccountAuthPayload {
  accessToken: string | null = null;
  serviceCountryCode: string | null = null;
  displayName: string | null = null;
  email: string | null = null;
  familyName: string | null = null;
  givenName: string | null = null;
  gender: number | null = null;
  authorizedScopes: Array<string> = [];
  idToken: string | null = null;
  avatarUri: string | null = null;
  authorizationCode: string | null = null;
  unionId: string | null = null;
  openId: string | null = null;
  accountFlag: number | null = null;
  carrierId: number | null = null;
  account: Object | null = null;
}

export default class HmsAccountOhosPlugin
  implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private authServiceChannel: MethodChannel | null = null;
  private authManagerChannel: MethodChannel | null = null;
  private authToolChannel: MethodChannel | null = null;
  private networkToolChannel: MethodChannel | null = null;
  private smsManagerChannel: MethodChannel | null = null;

  private appContext: common.Context | null = null;
  private uiContext: common.UIAbilityContext | null = null;

  private lastAuthAccount: AccountAuthPayload = this.createEmptyAuthPayload();

  getUniqueClassName(): string {
    return TAG;
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.appContext = binding.getApplicationContext();
    this.authServiceChannel = new MethodChannel(
      binding.getBinaryMessenger(),
      AUTH_SERVICE_CHANNEL,
    );
    this.authManagerChannel = new MethodChannel(
      binding.getBinaryMessenger(),
      AUTH_MANAGER_CHANNEL,
    );
    this.authToolChannel = new MethodChannel(
      binding.getBinaryMessenger(),
      AUTH_TOOL_CHANNEL,
    );
    this.networkToolChannel = new MethodChannel(
      binding.getBinaryMessenger(),
      NETWORK_TOOL_CHANNEL,
    );
    this.smsManagerChannel = new MethodChannel(
      binding.getBinaryMessenger(),
      SMS_MANAGER_CHANNEL,
    );

    this.authServiceChannel.setMethodCallHandler(this);
    this.authManagerChannel.setMethodCallHandler(this);
    this.authToolChannel.setMethodCallHandler(this);
    this.networkToolChannel.setMethodCallHandler(this);
    this.smsManagerChannel.setMethodCallHandler(this);
    Log.i(TAG, 'OHOS Huawei account plugin registered');
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.authServiceChannel?.setMethodCallHandler(null);
    this.authManagerChannel?.setMethodCallHandler(null);
    this.authToolChannel?.setMethodCallHandler(null);
    this.networkToolChannel?.setMethodCallHandler(null);
    this.smsManagerChannel?.setMethodCallHandler(null);

    this.authServiceChannel = null;
    this.authManagerChannel = null;
    this.authToolChannel = null;
    this.networkToolChannel = null;
    this.smsManagerChannel = null;
    this.appContext = null;
    this.uiContext = null;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.uiContext = binding.getAbility().context;
  }

  onReattachedToAbilityForConfigChanges(binding: AbilityPluginBinding): void {
    this.onAttachedToAbility(binding);
  }

  onDetachedFromAbilityForConfigChanges(): void {
    this.onDetachedFromAbility();
  }

  onDetachedFromAbility(): void {
    this.uiContext = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    this.handleMethodCall(call, result);
  }

  private async handleMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      Log.d(TAG, `Method: ${call.method}`);
      switch (call.method) {
        // AccountAuthService
        case 'signIn':
          await this.signIn(call, result);
          return;
        case 'silentSignIn':
          await this.silentSignIn(call, result);
          return;
        case 'independentSignIn':
          await this.signIn(call, result);
          return;
        case 'signOut':
          await this.signOut(result);
          return;
        case 'cancelAuthorization':
          await this.cancelAuthorization(result);
          return;
        case 'getChannel': {
          const channelInfo = new ChannelInfoResult();
          result.success(channelInfo);
          return;
        }

        // AccountAuthManager
        case 'enableLogger':
        case 'disableLogger':
        case 'addAuthScopes':
        case 'addAuthScopesExt':
          result.success(null);
          return;
        case 'getAuthResult':
        case 'getAuthResultWithScopes':
        case 'getExtendedAuthResult':
          result.success(this.lastAuthAccount);
          return;
        case 'containScopes':
        case 'containScopesExt':
          result.success(false);
          return;

        // NetworkTool
        case 'buildNetworkCookie':
          result.success(this.buildCookie(call));
          return;
        case 'buildNetworkUrl':
          result.success(this.buildUrl(call));
          return;

        // HuaweiIdAuthTool
        case 'deleteAuthInfo':
          result.success(true);
          return;
        case 'requestUnionId':
        case 'requestAccessToken':
          result.success('');
          return;

        // ReadSmsManager
        case 'requestVerificationCode':
        case 'startConsent':
          result.success(null);
          return;

        default:
          result.notImplemented();
          return;
      }
    } catch (e) {
      const errorMessage = this.errorToMessage(e as Object);
      Log.e(TAG, `AccountKit call failed. method=${call.method}, error=${errorMessage}`);
      result.error('account_ohos_error', errorMessage, null);
    }
  }

  private async signIn(call: MethodCall, result: MethodResult): Promise<void> {
    const context = this.uiContext;
    if (context == null) {
      result.error('account_ohos_no_context', 'UI context is not available.', null);
      return;
    }

    const request = this.buildAuthorizationRequest(call);
    const controller = new authentication.AuthenticationController(context);
    const responseObject = (await controller.executeRequest(request)) as Object;
    const responseData = this.extractResponseData(responseObject);
    const accountMap = this.toAuthAccountMap(responseData);
    this.ensureAuthPayload(responseObject, accountMap, false);
    this.lastAuthAccount = accountMap;
    result.success(accountMap);
  }

  private async silentSignIn(call: MethodCall, result: MethodResult): Promise<void> {
    const context = this.uiContext;
    if (context == null) {
      result.error('account_ohos_no_context', 'UI context is not available.', null);
      return;
    }

    const request = this.buildAuthorizationRequest(call);
    const controller = new authentication.AuthenticationController(context);
    const responseObject = (await controller.executeRequest(request)) as Object;
    const responseData = this.extractResponseData(responseObject);
    const accountMap = this.toAuthAccountMap(responseData);
    this.ensureAuthPayload(responseObject, accountMap, true);
    this.lastAuthAccount = accountMap;
    result.success(accountMap);
  }

  private async signOut(result: MethodResult): Promise<void> {
    this.lastAuthAccount = this.createEmptyAuthPayload();
    result.success(true);
  }

  private async cancelAuthorization(result: MethodResult): Promise<void> {
    result.success(true);
  }

  private buildAuthorizationRequest(call: MethodCall): authentication.AuthorizationWithHuaweiIDRequest {
    const provider = new authentication.HuaweiIDProvider();
    const request = provider.createAuthorizationWithHuaweiIDRequest();

    const permissions = this.toPermissionList(call);
    if (permissions.length > 0) {
      request.permissions = permissions;
    } else {
      request.permissions = ['idtoken'];
    }

    const scopes = this.toScopeList(call.argument('scopeList'));
    if (scopes.length > 0) {
      request.scopes = scopes;
    } else {
      request.scopes = ['openid', 'profile'];
    }

    if (Boolean(call.argument('setForceLogout'))) {
      request.forceAuthorization = true;
    }
    request.state = `${Date.now()}`;
    return request;
  }

  private toPermissionList(call: MethodCall): Array<string> {
    const permissions: Array<string> = [];
    if (Boolean(call.argument('setAccessToken'))) {
      permissions.push('accesstoken');
    }
    if (Boolean(call.argument('setIdToken'))) {
      permissions.push('idtoken');
    }
    if (Boolean(call.argument('setAuthorizationCode'))) {
      permissions.push('serviceauthcode');
    }
    if (Boolean(call.argument('setEmail'))) {
      permissions.push('email');
    }
    return permissions;
  }

  private toScopeList(rawScopeList: Object | undefined): Array<string> {
    if (rawScopeList == undefined) {
      return [];
    }
    const scopeItems = rawScopeList as Array<Object>;
    const scopes: Array<string> = [];
    for (const item of scopeItems) {
      const scope = `${item}`;
      if (scope.length > 0) {
        scopes.push(scope);
      }
    }
    return scopes;
  }

  private extractResponseData(response: Object): AccountKitResponseData {
    const responseMap = this.toMapLike(response);
    if (responseMap == undefined) {
      return this.createEmptyResponseData();
    }
    const dataMap = this.resolveResponseDataMap(responseMap);
    if (dataMap == undefined) {
      return this.createEmptyResponseData();
    }
    return this.responseDataFromMap(dataMap);
  }

  private resolveResponseDataMap(
    responseMap: Map<string, Object>,
  ): Map<string, Object> | undefined {
    const dataValue = responseMap.get('data');
    const dataMap = this.toMapLike(dataValue as Object);
    if (dataMap != undefined) {
      return dataMap;
    }

    const resultValue = responseMap.get('result');
    const resultMap = this.toMapLike(resultValue as Object);
    if (resultMap != undefined) {
      return resultMap;
    }

    const authDataValue = responseMap.get('authData');
    const authDataMap = this.toMapLike(authDataValue as Object);
    if (authDataMap != undefined) {
      return authDataMap;
    }

    // Some AccountKit builds return payload directly on top-level map.
    return responseMap;
  }

  private ensureAuthPayload(
    rawResponse: Object,
    payload: AccountAuthPayload,
    isSilent: boolean,
  ): void {
    if (payload.idToken != null || payload.authorizationCode != null || payload.openId != null) {
      return;
    }

    if (isSilent) {
      // silentSignIn may legitimately return no account state.
      return;
    }

    const responseMap = this.toMapLike(rawResponse);
    if (responseMap == undefined) {
      const rawType = typeof rawResponse;
      const rawJson = this.tryStringify(rawResponse);
      throw new Error(
        `AccountKit returned empty auth payload and non-map response. ` +
          `silent=${isSilent}, rawType=${rawType}, ` +
          `raw=${rawJson ?? `${rawResponse}`}`,
      );
    }
    const hasErrorCode = responseMap.get('code') != undefined ||
      responseMap.get('status') != undefined ||
      responseMap.get('errorCode') != undefined ||
      responseMap.get('resultCode') != undefined;
    const hasErrorMessage = responseMap.get('message') != undefined ||
      responseMap.get('errorMessage') != undefined ||
      responseMap.get('errorMsg') != undefined;

    const debugPayload = this.mapToDebugString(responseMap);
    if (hasErrorCode || hasErrorMessage) {
      throw new Error(
        `AccountKit returned empty auth payload with error fields. ` +
          `silent=${isSilent}. ${debugPayload}`,
      );
    }

    throw new Error(
      `AccountKit returned empty auth payload without tokens. ` +
        `silent=${isSilent}. ${debugPayload}`,
    );
  }

  private toAuthAccountMap(data: AccountKitResponseData): AccountAuthPayload {
    const grantedScopes = this.normalizeScopes(
      data.grantedScopes ?? data.authorizedScopes,
    );
    const payload = new AccountAuthPayload();
    payload.accessToken = data.accessToken ?? null;
    payload.serviceCountryCode = data.serviceCountryCode ?? null;
    payload.displayName = data.displayName ?? data.nickName ?? null;
    payload.email = data.email ?? null;
    payload.familyName = data.familyName ?? null;
    payload.givenName = data.givenName ?? null;
    payload.gender = data.gender ?? null;
    payload.authorizedScopes = grantedScopes;
    payload.idToken = data.idToken ?? null;
    payload.avatarUri = data.avatarUri ?? data.photoUriString ?? null;
    payload.authorizationCode = data.authorizationCode ?? null;
    payload.unionId = data.unionId ?? data.unionID ?? null;
    payload.openId = data.openId ?? data.openID ?? null;
    payload.accountFlag = data.accountFlag ?? null;
    payload.carrierId = data.carrierId ?? null;
    payload.account = null;
    return payload;
  }

  private normalizeScopes(scopes: Array<Object> | undefined): Array<string> {
    if (scopes == undefined) {
      return [];
    }
    const result: Array<string> = [];
    for (const item of scopes) {
      if (typeof item === 'string') {
        result.push(item);
      } else {
        const scopeLike = item as ScopeLike;
        if (scopeLike.mScopeUri != undefined) {
          result.push(`${scopeLike.mScopeUri}`);
        } else {
          result.push(`${item}`);
        }
      }
    }
    return result;
  }

  private createEmptyAuthPayload(): AccountAuthPayload {
    return new AccountAuthPayload();
  }

  private createEmptyResponseData(): AccountKitResponseData {
    return new AccountKitResponseData();
  }

  private responseDataFromMap(dataMap: Map<string, Object>): AccountKitResponseData {
    const data = this.createEmptyResponseData();
    data.accessToken = this.readString(dataMap, 'accessToken');
    data.serviceCountryCode = this.readString(dataMap, 'serviceCountryCode');
    data.displayName = this.readString(dataMap, 'displayName');
    data.nickName = this.readString(dataMap, 'nickName');
    data.email = this.readString(dataMap, 'email');
    data.familyName = this.readString(dataMap, 'familyName');
    data.givenName = this.readString(dataMap, 'givenName');
    data.idToken = this.readString(dataMap, 'idToken');
    data.avatarUri = this.readString(dataMap, 'avatarUri');
    data.photoUriString = this.readString(dataMap, 'photoUriString');
    data.authorizationCode = this.readString(dataMap, 'authorizationCode');
    data.unionId = this.readString(dataMap, 'unionId');
    data.unionID = this.readString(dataMap, 'unionID');
    data.openId = this.readString(dataMap, 'openId');
    data.openID = this.readString(dataMap, 'openID');
    data.gender = this.readNumber(dataMap, 'gender');
    data.accountFlag = this.readNumber(dataMap, 'accountFlag');
    data.carrierId = this.readNumber(dataMap, 'carrierId');

    const grantedScopes = dataMap.get('grantedScopes');
    if (grantedScopes != undefined && Array.isArray(grantedScopes)) {
      data.grantedScopes = grantedScopes as Array<Object>;
    }
    const authorizedScopes = dataMap.get('authorizedScopes');
    if (authorizedScopes != undefined && Array.isArray(authorizedScopes)) {
      data.authorizedScopes = authorizedScopes as Array<Object>;
    }
    return data;
  }

  private readString(dataMap: Map<string, Object>, key: string): string | undefined {
    const value = dataMap.get(key);
    if (value == undefined) {
      return undefined;
    }
    return `${value}`;
  }

  private readNumber(dataMap: Map<string, Object>, key: string): number | undefined {
    const value = dataMap.get(key);
    if (value == undefined) {
      return undefined;
    }
    return Number(`${value}`);
  }

  private buildCookie(call: MethodCall): string {
    const cookieName = `${call.argument('cookieName') ?? ''}`;
    const cookieValue = `${call.argument('cookieValue') ?? ''}`;
    const domain = `${call.argument('domain') ?? ''}`;
    const path = `${call.argument('path') ?? '/'}`;
    const isHttpOnly = Boolean(call.argument('isHttpOnly'));
    const isSecure = Boolean(call.argument('isSecure'));
    const maxAgeValue: Object | undefined = call.argument('maxAge');

    let cookie = `${cookieName}=${cookieValue}`;
    if (domain.length > 0) {
      cookie += `; Domain=${domain}`;
    }
    if (path.length > 0) {
      cookie += `; Path=${path}`;
    }
    if (isHttpOnly) {
      cookie += '; HttpOnly';
    }
    if (isSecure) {
      cookie += '; Secure';
    }
    if (maxAgeValue != undefined) {
      cookie += `; Max-Age=${maxAgeValue}`;
    }
    return cookie;
  }

  private buildUrl(call: MethodCall): string {
    const domain = `${call.argument('domainName') ?? ''}`;
    const isHttps = Boolean(call.argument('isHttps'));
    if (domain.length == 0) {
      return '';
    }
    return `${isHttps ? 'https' : 'http'}://${domain}`;
  }

  private errorToMessage(error: Object): string {
    const businessError = error as BusinessError;
    const errorCode = businessError.code;
    const errorMessage = businessError.message;

    if (errorCode != undefined || errorMessage != undefined) {
      return `BusinessError(code=${errorCode}, message=${errorMessage})`;
    }

    if (error instanceof Map) {
      const mapPayload = this.mapToDebugString(error as Map<string, Object>);
      return `MapError(${mapPayload})`;
    }

    const jsonPayload = this.tryStringify(error);
    if (jsonPayload != undefined && jsonPayload.length > 0 && jsonPayload != '{}') {
      return jsonPayload;
    }
    return `${error}`;
  }

  private mapToDebugString(mapValue: Map<string, Object>): string {
    const keys = Array.from(mapValue.keys());
    let result = '';
    for (const key of keys) {
      const value = mapValue.get(key);
      const segment = `${key}=${value}`;
      result = result.length == 0 ? segment : `${result}, ${segment}`;
    }
    return result;
  }

  private tryStringify(value: Object): string | undefined {
    try {
      return JSON.stringify(value);
    } catch (_) {
      return undefined;
    }
  }

  private toMapLike(value: Object | undefined): Map<string, Object> | undefined {
    if (value == undefined) {
      return undefined;
    }
    if (value instanceof Map) {
      return value as Map<string, Object>;
    }

    if (typeof value !== 'object' || value == null || Array.isArray(value)) {
      return undefined;
    }

    const objectValue = value as Record<string, Object>;
    const mapValue = new Map<string, Object>();
    const keys = Object.keys(objectValue);
    for (const key of keys) {
      mapValue.set(key, objectValue[key]);
    }
    return mapValue;
  }
}
