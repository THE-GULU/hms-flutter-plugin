import {
  FlutterPlugin,
  FlutterPluginBinding,
  Log,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import { hiAppEvent, hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'HmsAnalyticsOhosPlugin';
const METHOD_CHANNEL = 'com.huawei.hms.flutter.analytics';
const EVENT_DOMAIN = 'ha_analytics';
const USER_ID_KEY = 'userId';
const DOMAIN = 0x0000;

class AnalyticsEventParams {
  pageName?: string;
  pageClassOverride?: string;
}

/**
 * OHOS bridge for huawei_analytics.
 *
 * HarmonyOS NEXT HMS SDK currently has no @kit.AnalyticsKit. This plugin maps
 * the existing Flutter MethodChannel contract onto hiAppEvent APIs, which cover
 * custom events, user id, and user properties. AGC Analytics collector config
 * in agconnect-services.json remains required for Huawei-side analytics projects.
 */
export default class HmsAnalyticsOhosPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private initialized: boolean = false;
  private analyticsEnabled: boolean = true;
  private loggingEnabled: boolean = false;

  getUniqueClassName(): string {
    return TAG;
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), METHOD_CHANNEL);
    this.channel.setMethodCallHandler(this);
    Log.i(TAG, 'OHOS Huawei analytics plugin registered');
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    try {
      switch (call.method) {
        case 'getInstance':
          this.handleGetInstance(result);
          break;
        case 'enableLog':
          this.handleEnableLog(result);
          break;
        case 'enableLogWithLevel':
          this.handleEnableLog(result);
          break;
        case 'setAnalyticsEnabled':
          this.handleSetAnalyticsEnabled(call, result);
          break;
        case 'onEvent':
          this.handleOnEvent(call, result);
          break;
        case 'pageStart':
          this.handlePageStart(call, result);
          break;
        case 'pageEnd':
          this.handlePageEnd(call, result);
          break;
        case 'setUserId':
          this.handleSetUserId(call, result);
          break;
        case 'deleteUserId':
          this.handleDeleteUserId(result);
          break;
        case 'setUserProfile':
          this.handleSetUserProfile(call, result);
          break;
        case 'deleteUserProfile':
          this.handleDeleteUserProfile(call, result);
          break;
        default:
          result.notImplemented();
          break;
      }
    } catch (error) {
      const message = `${error}`;
      this.logError(`Method ${call.method} failed: ${message}`);
      result.error(TAG, message, null);
    }
  }

  private handleGetInstance(result: MethodResult): void {
    if (!this.initialized) {
      try {
        const config: hiAppEvent.ConfigOption = { disable: false };
        hiAppEvent.configure(config);
        this.initialized = true;
        this.logInfo('Analytics initialized via hiAppEvent');
      } catch (error) {
        this.logError(`Analytics init failed: ${error}`);
      }
    }
    result.success(null);
  }

  private handleEnableLog(result: MethodResult): void {
    this.loggingEnabled = true;
    this.logInfo('Analytics logging enabled');
    result.success(null);
  }

  private handleSetAnalyticsEnabled(call: MethodCall, result: MethodResult): void {
    const enabled = this.readBoolean(call, 'enabled', true);
    this.analyticsEnabled = enabled;
    try {
      const config: hiAppEvent.ConfigOption = { disable: !enabled };
      hiAppEvent.configure(config);
    } catch (error) {
      this.logError(`setAnalyticsEnabled failed: ${error}`);
    }
    result.success(null);
  }

  private handleOnEvent(call: MethodCall, result: MethodResult): void {
    if (!this.analyticsEnabled) {
      result.success(null);
      return;
    }
    const eventId = this.readString(call, 'eventId');
    if (eventId.length === 0) {
      result.error('NULL_PARAM', 'eventId was null or empty.', null);
      return;
    }
    const rawParams: Object | null | undefined = call.argument('params') as Object | null | undefined;
    const params = this.readParams(rawParams);
    this.writeEvent(this.sanitizeEventName(eventId), params);
    result.success(null);
  }

  private handlePageStart(call: MethodCall, result: MethodResult): void {
    if (!this.analyticsEnabled) {
      result.success(null);
      return;
    }
    const pageName = this.readString(call, 'pageName');
    const pageClassOverride = this.readString(call, 'pageClassOverride');
    const params = new AnalyticsEventParams();
    params.pageName = pageName;
    params.pageClassOverride = pageClassOverride;
    this.writeEvent('page_start', params);
    result.success(null);
  }

  private handlePageEnd(call: MethodCall, result: MethodResult): void {
    if (!this.analyticsEnabled) {
      result.success(null);
      return;
    }
    const pageName = this.readString(call, 'pageName');
    const params = new AnalyticsEventParams();
    params.pageName = pageName;
    this.writeEvent('page_end', params);
    result.success(null);
  }

  private handleSetUserId(call: MethodCall, result: MethodResult): void {
    const userId: Object | null | undefined = call.argument('userId') as Object | null | undefined;
    try {
      if (userId === null || userId === undefined) {
        hiAppEvent.setUserId(USER_ID_KEY, '');
      } else {
        hiAppEvent.setUserId(USER_ID_KEY, `${userId}`);
      }
    } catch (error) {
      this.logError(`setUserId failed: ${error}`);
    }
    result.success(null);
  }

  private handleDeleteUserId(result: MethodResult): void {
    try {
      hiAppEvent.setUserId(USER_ID_KEY, '');
    } catch (error) {
      this.logError(`deleteUserId failed: ${error}`);
    }
    result.success(null);
  }

  private handleSetUserProfile(call: MethodCall, result: MethodResult): void {
    const key = this.readString(call, 'key');
    const valueArg: Object | null | undefined = call.argument('value') as Object | null | undefined;
    if (key.length === 0) {
      result.error('NULL_PARAM', 'key was null or empty.', null);
      return;
    }
    try {
      const value = valueArg === null || valueArg === undefined ? '' : `${valueArg}`;
      hiAppEvent.setUserProperty(this.sanitizeParamName(key), value);
    } catch (error) {
      this.logError(`setUserProfile failed: ${error}`);
    }
    result.success(null);
  }

  private handleDeleteUserProfile(call: MethodCall, result: MethodResult): void {
    const key = this.readString(call, 'key');
    if (key.length === 0) {
      result.error('NULL_PARAM', 'key was null or empty.', null);
      return;
    }
    try {
      hiAppEvent.setUserProperty(this.sanitizeParamName(key), '');
    } catch (error) {
      this.logError(`deleteUserProfile failed: ${error}`);
    }
    result.success(null);
  }

  private writeEvent(eventName: string, params: Object): void {
    const info: hiAppEvent.AppEventInfo = {
      domain: EVENT_DOMAIN,
      name: eventName,
      eventType: hiAppEvent.EventType.BEHAVIOR,
      params: params,
    };
    hiAppEvent.write(info).then(() => {
      this.logInfo(`onEvent ok name=${eventName}`);
    }).catch((error: BusinessError) => {
      this.logError(`onEvent failed name=${eventName} code=${error.code} msg=${error.message}`);
    });
  }

  private readParams(raw: Object | null | undefined): Object {
    if (raw === null || raw === undefined) {
      return new AnalyticsEventParams();
    }
    try {
      // Rebuild as a plain object accepted by hiAppEvent / ArkTS.
      return JSON.parse(JSON.stringify(raw)) as Object;
    } catch (_error) {
      return new AnalyticsEventParams();
    }
  }

  private readString(call: MethodCall, key: string): string {
    const value: Object | null | undefined = call.argument(key) as Object | null | undefined;
    if (value === null || value === undefined) {
      return '';
    }
    return `${value}`;
  }

  private readBoolean(call: MethodCall, key: string, fallback: boolean): boolean {
    const value: Object | null | undefined = call.argument(key) as Object | null | undefined;
    if (typeof value === 'boolean') {
      return value;
    }
    return fallback;
  }

  private sanitizeEventName(name: string): string {
    let sanitized = name.replace(/[^A-Za-z0-9_$]/g, '_');
    if (sanitized.length === 0) {
      return 'custom_event';
    }
    if (!/^[A-Za-z$]/.test(sanitized)) {
      sanitized = `e_${sanitized}`;
    }
    if (sanitized.length > 48) {
      sanitized = sanitized.substring(0, 48);
    }
    return sanitized;
  }

  private sanitizeParamName(name: string): string {
    let sanitized = name.replace(/[^A-Za-z0-9_$]/g, '_');
    if (sanitized.length === 0) {
      return '';
    }
    if (!/^[A-Za-z$]/.test(sanitized)) {
      sanitized = `p_${sanitized}`;
    }
    if (sanitized.length > 32) {
      sanitized = sanitized.substring(0, 32);
    }
    return sanitized;
  }

  private logInfo(message: string): void {
    if (this.loggingEnabled) {
      hilog.info(DOMAIN, TAG, '%{public}s', message);
    }
    Log.i(TAG, message);
  }

  private logError(message: string): void {
    hilog.error(DOMAIN, TAG, '%{public}s', message);
    Log.e(TAG, message);
  }
}
