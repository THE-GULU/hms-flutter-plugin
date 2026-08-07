import {
  AbilityAware,
  AbilityPluginBinding,
  EventChannel,
  EventSink,
  FlutterPlugin,
  FlutterPluginBinding,
  Log,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  NewWantListener,
  StreamHandler,
} from '@ohos/flutter_ohos';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import Want from '@ohos.app.ability.Want';
import UIAbility from '@ohos.app.ability.UIAbility';
import common from '@ohos.app.ability.common';
import { BusinessError } from '@kit.BasicServicesKit';
import { notificationManager } from '@kit.NotificationKit';
import { pushService } from '@kit.PushKit';

const TAG = 'HmsPushOhosPlugin';

const METHOD_CHANNEL = 'com.huawei.flutter.push/method';
const TOKEN_CHANNEL = 'com.huawei.flutter.push/token';
const MULTI_SENDER_TOKEN_CHANNEL = 'com.huawei.flutter.push/multi_sender_token';
const REMOTE_MESSAGE_RECEIVE_CHANNEL = 'com.huawei.flutter.push/remote_message_receive';
const REMOTE_MESSAGE_SEND_STATUS_CHANNEL = 'com.huawei.flutter.push/remote_message_send_status';
const REMOTE_MESSAGE_NOTIFICATION_INTENT_CHANNEL =
  'com.huawei.flutter.push/remote_message_notification_intent';
const NOTIFICATION_OPEN_CHANNEL = 'com.huawei.flutter.push/notification_open';
const LOCAL_NOTIFICATION_CLICK_CHANNEL = 'com.huawei.flutter.push/local_notification_click';

interface WantLike {
  parameters?: Object;
  uri?: string;
}

interface PushPayloadLike {
  data?: string;
  messageId?: string;
  msgId?: string;
  from?: string;
  to?: string;
  sentTime?: number;
  ttl?: number;
  urgency?: number;
  originalUrgency?: number;
  messageType?: string;
  collapseKey?: string;
}

interface NotificationLike {
  title?: string;
  body?: string;
  notifyId?: number;
}

interface PayloadDataLike {
  notification?: NotificationLike;
  data?: Object;
  title?: string;
  body?: string;
  content?: string;
}

class RemoteMessageNotificationPayload {
  title: string = '';
  body: string = '';
  NotifyId: number = 0;
  ClickAction: string = '';
  intentUri: string = '';
  ImageUrl: string = '';
  Link: string = '';
}

class RemoteMessagePayload {
  to: string = '';
  from: string = '';
  messageId: string = '';
  token: string = '';
  sentTime: number = 0;
  urgency: number = 0;
  originalUrgency: number = 0;
  ttl: number = 0;
  messageType: string = '';
  collapseKey: string = '';
  data: string = '';
  dataOfMap: string = '{}';
  notification: RemoteMessageNotificationPayload = new RemoteMessageNotificationPayload();
  sendMode: number = 0;
  receiptMode: number = 0;
  analyticInfo: string = '';
}

class NotificationOpenPayload {
  uriPage: string = '';
  extras: Object = JSON.parse('{}') as Object;
  remoteMessage: RemoteMessagePayload = new RemoteMessagePayload();
}

class NoOpStreamHandler implements StreamHandler {
  onListen(args: Object, events: EventSink): void {}
  onCancel(args: Object): void {}
}

class TokenStreamHandler implements StreamHandler {
  private owner: HmsPushOhosPlugin;

  constructor(owner: HmsPushOhosPlugin) {
    this.owner = owner;
  }

  onListen(args: Object, events: EventSink): void {
    this.owner.handleTokenStreamListen(events);
  }

  onCancel(args: Object): void {
    this.owner.handleTokenStreamCancel();
  }
}

class RemoteMessageStreamHandler implements StreamHandler {
  private owner: HmsPushOhosPlugin;

  constructor(owner: HmsPushOhosPlugin) {
    this.owner = owner;
  }

  onListen(args: Object, events: EventSink): void {
    this.owner.handleRemoteMessageStreamListen(events);
  }

  onCancel(args: Object): void {
    this.owner.handleRemoteMessageStreamCancel();
  }
}

class NotificationOpenStreamHandler implements StreamHandler {
  private owner: HmsPushOhosPlugin;

  constructor(owner: HmsPushOhosPlugin) {
    this.owner = owner;
  }

  onListen(args: Object, events: EventSink): void {
    this.owner.handleNotificationOpenStreamListen(events);
  }

  onCancel(args: Object): void {
    this.owner.handleNotificationOpenStreamCancel();
  }
}

let activePlugin: HmsPushOhosPlugin | null = null;
const pendingForegroundPayloads: Object[] = [];
let abilityReceiveMessageRegistered: boolean = false;
let pendingLaunchWant: Want | null = null;

export default class HmsPushOhosPlugin
  implements FlutterPlugin, MethodCallHandler, AbilityAware, NewWantListener {
  private methodChannel: MethodChannel | null = null;
  private tokenChannel: EventChannel | null = null;
  private multiSenderTokenChannel: EventChannel | null = null;
  private remoteMessageReceiveChannel: EventChannel | null = null;
  private remoteMessageSendStatusChannel: EventChannel | null = null;
  private remoteMessageNotificationIntentChannel: EventChannel | null = null;
  private notificationOpenChannel: EventChannel | null = null;
  private localNotificationClickChannel: EventChannel | null = null;

  private tokenSink: EventSink | null = null;
  private remoteMessageReceiveSink: EventSink | null = null;
  private notificationOpenSink: EventSink | null = null;
  private uiContext: common.UIAbilityContext | null = null;
  private abilityBinding: AbilityPluginBinding | null = null;
  private ability: UIAbility | null = null;
  private cachedToken: string = '';
  private initialNotification: NotificationOpenPayload | null = null;
  private initialIntent: string | null = null;
  private pushReceiverRegistered: boolean = false;

  /**
   * Capture notification-open Want from Ability.onCreate (cold start) or
   * Ability.onNewWant (warm/background). Cold start never goes through
   * Flutter NewWantListener alone.
   */
  static captureLaunchWant(want: Want): void {
    if (activePlugin != null) {
      activePlugin.captureNotificationOpen(want);
      return;
    }
    pendingLaunchWant = want;
    Log.i(TAG, 'Queued launch Want for notification open (plugin not ready).');
  }

  /**
   * Must be called from EntryAbility.onCreate with the Ability that declares
   * action.ohos.push.listener. Push Kit only delivers foreground messages when
   * receiveMessage is registered in Ability onCreate.
   */
  static registerReceiveMessage(ability: UIAbility): void {
    if (abilityReceiveMessageRegistered) {
      return;
    }
    abilityReceiveMessageRegistered = true;
    try {
      pushService.receiveMessage(
        'DEFAULT',
        ability,
        (payload: Object) => {
          Log.i(TAG, 'receiveMessage callback type=DEFAULT (Ability.onCreate)');
          HmsPushOhosPlugin.dispatchForegroundPayload(payload);
        },
      );
      Log.i(TAG, 'Registered receiveMessage callback type=DEFAULT in Ability.onCreate');
    } catch (error) {
      abilityReceiveMessageRegistered = false;
      Log.e(
        TAG,
        `Failed to register receiveMessage(DEFAULT) in Ability.onCreate: ${HmsPushOhosPlugin.errorToMessageStatic(error as Object)}`,
      );
    }
  }

  static dispatchForegroundPayload(payload: Object): void {
    if (activePlugin != null) {
      activePlugin.handleForegroundPayload(payload);
      return;
    }
    pendingForegroundPayloads.push(payload);
    Log.w(TAG, 'Queued foreground push payload; Flutter plugin not ready yet.');
  }

  private static errorToMessageStatic(error: Object): string {
    const businessError = error as BusinessError;
    const errorCode = businessError.code;
    const errorMessage = businessError.message;
    if (errorCode != undefined || errorMessage != undefined) {
      return `BusinessError(code=${errorCode}, message=${errorMessage})`;
    }
    return `${error}`;
  }

  getUniqueClassName(): string {
    return TAG;
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    activePlugin = this;
    this.methodChannel = new MethodChannel(
      binding.getBinaryMessenger(),
      METHOD_CHANNEL,
    );
    this.methodChannel.setMethodCallHandler(this);

    this.tokenChannel = new EventChannel(binding.getBinaryMessenger(), TOKEN_CHANNEL);
    this.multiSenderTokenChannel = new EventChannel(
      binding.getBinaryMessenger(),
      MULTI_SENDER_TOKEN_CHANNEL,
    );
    this.remoteMessageReceiveChannel = new EventChannel(
      binding.getBinaryMessenger(),
      REMOTE_MESSAGE_RECEIVE_CHANNEL,
    );
    this.remoteMessageSendStatusChannel = new EventChannel(
      binding.getBinaryMessenger(),
      REMOTE_MESSAGE_SEND_STATUS_CHANNEL,
    );
    this.remoteMessageNotificationIntentChannel = new EventChannel(
      binding.getBinaryMessenger(),
      REMOTE_MESSAGE_NOTIFICATION_INTENT_CHANNEL,
    );
    this.notificationOpenChannel = new EventChannel(
      binding.getBinaryMessenger(),
      NOTIFICATION_OPEN_CHANNEL,
    );
    this.localNotificationClickChannel = new EventChannel(
      binding.getBinaryMessenger(),
      LOCAL_NOTIFICATION_CLICK_CHANNEL,
    );

    this.tokenChannel.setStreamHandler(new TokenStreamHandler(this));
    this.multiSenderTokenChannel.setStreamHandler(new NoOpStreamHandler());
    this.remoteMessageReceiveChannel.setStreamHandler(new RemoteMessageStreamHandler(this));
    this.remoteMessageSendStatusChannel.setStreamHandler(new NoOpStreamHandler());
    this.remoteMessageNotificationIntentChannel.setStreamHandler(new NoOpStreamHandler());
    this.notificationOpenChannel.setStreamHandler(new NotificationOpenStreamHandler(this));
    this.localNotificationClickChannel.setStreamHandler(new NoOpStreamHandler());
    Log.i(TAG, 'OHOS Huawei push plugin registered');
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (activePlugin === this) {
      activePlugin = null;
    }
    this.methodChannel?.setMethodCallHandler(null);
    this.tokenChannel?.setStreamHandler(new NoOpStreamHandler());
    this.multiSenderTokenChannel?.setStreamHandler(new NoOpStreamHandler());
    this.remoteMessageReceiveChannel?.setStreamHandler(new NoOpStreamHandler());
    this.remoteMessageSendStatusChannel?.setStreamHandler(new NoOpStreamHandler());
    this.remoteMessageNotificationIntentChannel?.setStreamHandler(new NoOpStreamHandler());
    this.notificationOpenChannel?.setStreamHandler(new NoOpStreamHandler());
    this.localNotificationClickChannel?.setStreamHandler(new NoOpStreamHandler());

    this.methodChannel = null;
    this.tokenChannel = null;
    this.multiSenderTokenChannel = null;
    this.remoteMessageReceiveChannel = null;
    this.remoteMessageSendStatusChannel = null;
    this.remoteMessageNotificationIntentChannel = null;
    this.notificationOpenChannel = null;
    this.localNotificationClickChannel = null;
    this.tokenSink = null;
    this.remoteMessageReceiveSink = null;
    this.notificationOpenSink = null;
    this.abilityBinding = null;
    this.ability = null;
    this.uiContext = null;
    this.initialNotification = null;
    this.initialIntent = null;
    this.pushReceiverRegistered = false;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.abilityBinding = binding;
    this.ability = binding.getAbility();
    this.uiContext = binding.getAbility().context;
    binding.addOnNewWantListener(this);
    this.registerPushCallbacksIfNeeded();
    if (pendingLaunchWant != null) {
      const launchWant = pendingLaunchWant;
      pendingLaunchWant = null;
      this.captureNotificationOpen(launchWant);
    }
  }

  onReattachedToAbilityForConfigChanges(binding: AbilityPluginBinding): void {
    this.onAttachedToAbility(binding);
  }

  onDetachedFromAbilityForConfigChanges(): void {
    this.onDetachedFromAbility();
  }

  onDetachedFromAbility(): void {
    if (this.abilityBinding != null) {
      this.abilityBinding.removeOnNewWantListener(this);
    }
    this.abilityBinding = null;
    this.ability = null;
    this.uiContext = null;
  }

  onNewWant(want: Want, launchParams: AbilityConstant.LaunchParam): void {
    this.captureNotificationOpen(want);
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    this.handleMethodCall(call, result);
  }

  private async handleMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      Log.d(TAG, `Method: ${call.method}`);
      switch (call.method) {
        case 'getToken':
          await this.requestToken(result);
          return;
        case 'getTokenOhos':
          await this.getTokenDirect(result);
          return;
        case 'requestPermission':
          await this.requestPermission(result);
          return;
        case 'getInitialNotification': {
          // Return once for cold-start consumers, then clear so warm-start
          // stream events remain the sole source afterward.
          const initial = this.initialNotificationToMap();
          this.initialNotification = null;
          this.initialIntent = null;
          result.success(initial);
          return;
        }
        case 'getInitialIntent':
          result.success(this.initialIntent ?? '');
          return;
        case 'getAppId':
        case 'getId':
        case 'getAAID':
        case 'getCreationTime':
        case 'getOdid':
        case 'getAgConnectValues':
          result.success('');
          return;
        case 'getNotifications':
        case 'getScheduledNotifications':
        case 'getChannels':
          result.success([]);
          return;
        case 'channelExists':
        case 'channelBlocked':
        case 'isAutoInitEnabled':
        case 'isSupportProfile':
          result.success(false);
          return;
        case 'registerBackgroundMessageHandler':
        case 'removeBackgroundMessageHandler':
          result.success(false);
          return;
        case 'turnOnPush':
        case 'turnOffPush':
        case 'deleteAAID':
        case 'deleteToken':
        case 'deleteMultiSenderToken':
        case 'subscribe':
        case 'unsubscribe':
        case 'send':
        case 'setAutoInitEnabled':
        case 'deleteChannel':
        case 'addProfile':
        case 'addMultiSenderProfile':
        case 'deleteProfile':
        case 'deleteMultiSenderProfile':
        case 'consentOn':
        case 'consentOff':
          result.success('0');
          return;
        case 'localNotification':
        case 'localNotificationSchedule':
          result.success('{}');
          return;
        case 'cancelNotifications':
        case 'cancelAllNotifications':
        case 'cancelScheduledNotifications':
        case 'cancelNotificationsWithTag':
        case 'cancelNotificationsWithId':
        case 'cancelNotificationsWithIdTag':
        case 'showToast':
        case 'enableLogger':
        case 'disableLogger':
        case 'getMultiSenderToken':
          result.success(null);
          return;
        default:
          result.notImplemented();
          return;
      }
    } catch (e) {
      const errorMessage = this.errorToMessage(e as Object);
      Log.e(TAG, `Push call failed. method=${call.method}, error=${errorMessage}`);
      result.error('push_ohos_error', errorMessage, null);
    }
  }

  handleTokenStreamListen(events: EventSink): void {
    this.tokenSink = events;
    if (this.cachedToken.length > 0) {
      this.tokenSink.success(this.cachedToken);
    }
  }

  handleTokenStreamCancel(): void {
    this.tokenSink = null;
  }

  handleRemoteMessageStreamListen(events: EventSink): void {
    this.remoteMessageReceiveSink = events;
    this.flushPendingForegroundPayloads();
  }

  handleRemoteMessageStreamCancel(): void {
    this.remoteMessageReceiveSink = null;
  }

  handleNotificationOpenStreamListen(events: EventSink): void {
    this.notificationOpenSink = events;
  }

  handleNotificationOpenStreamCancel(): void {
    this.notificationOpenSink = null;
  }

  private async requestToken(result: MethodResult): Promise<void> {
    const token = await pushService.getToken();
    this.cachedToken = token;
    if (this.tokenSink != null) {
      this.tokenSink.success(token);
    }
    result.success(null);
  }

  private async getTokenDirect(result: MethodResult): Promise<void> {
    if (this.cachedToken.length > 0) {
      result.success(this.cachedToken);
      return;
    }
    const token = await pushService.getToken();
    this.cachedToken = token;
    result.success(token);
  }

  private async requestPermission(result: MethodResult): Promise<void> {
    const context = this.uiContext;
    if (context == null) {
      result.error('push_ohos_no_context', 'UI context is not available.', null);
      return;
    }

    const enabled = await notificationManager.isNotificationEnabled();
    if (enabled) {
      result.success(true);
      return;
    }
    await notificationManager.requestEnableNotification(context);
    result.success(true);
  }

  private registerPushCallbacksIfNeeded(): void {
    if (this.pushReceiverRegistered || this.ability == null) {
      return;
    }

    this.pushReceiverRegistered = true;
    // Prefer Ability.onCreate registration. Keep AbilityAware as fallback only.
    if (!abilityReceiveMessageRegistered) {
      const defaultRegistered = this.registerDefaultMessageReceiver();
      if (!defaultRegistered) {
        this.pushReceiverRegistered = false;
        Log.w(TAG, 'No receiveMessage callback registered for OHOS push.');
      }
    } else {
      Log.i(TAG, 'Skipping AbilityAware receiveMessage; already registered in Ability.onCreate');
    }

    try {
      pushService.on(
        'tokenUpdate',
        this.ability,
        (token: string) => {
          this.cachedToken = token;
          if (this.tokenSink != null) {
            this.tokenSink.success(token);
          }
        },
      );
    } catch (error) {
      Log.w(TAG, `Failed to register tokenUpdate callback: ${this.errorToMessage(error as Object)}`);
    }
  }

  private registerDefaultMessageReceiver(): boolean {
    if (this.ability == null) {
      return false;
    }
    try {
      pushService.receiveMessage(
        'DEFAULT',
        this.ability,
        (payload: Object) => {
          Log.i(TAG, 'receiveMessage callback type=DEFAULT (AbilityAware fallback)');
          this.handleForegroundPayload(payload);
        },
      );
      abilityReceiveMessageRegistered = true;
      Log.i(TAG, 'Registered receiveMessage callback type=DEFAULT');
      return true;
    } catch (error) {
      Log.w(
        TAG,
        `Failed to register receiveMessage(DEFAULT): ${this.errorToMessage(error as Object)}`,
      );
      return false;
    }
  }

  captureNotificationOpen(want: Want): void {
    const extras = this.extractWantParameters(want);
    const uriPage = this.extractWantUri(want);
    const extrasJson = this.safeStringify(extras);
    const hasExtras = extrasJson != '{}' && extrasJson.length > 2;
    if (!hasExtras && uriPage.length === 0) {
      Log.w(TAG, 'Ignore notification open Want without extras/uri');
      return;
    }

    const payload = new NotificationOpenPayload();
    payload.uriPage = uriPage;
    payload.extras = hasExtras ? extras : this.buildExtrasFromUri(uriPage);
    payload.remoteMessage = this.buildRemoteMessageFromExtras(
      hasExtras ? extrasJson : this.safeStringify(payload.extras),
    );
    this.initialIntent = payload.uriPage;
    this.initialNotification = payload;
    Log.i(
      TAG,
      `Captured notification open uri=${uriPage}, extrasLength=${extrasJson.length}`,
    );

    if (this.notificationOpenSink != null) {
      const openMap = this.initialNotificationToMap();
      if (openMap != null) {
        this.notificationOpenSink.success(this.safeStringify(openMap));
      }
    }
  }

  private initialNotificationToMap(): Object | null {
    if (this.initialNotification == null) {
      return null;
    }
    // Serialize via JSON so MethodChannel receives a plain map.
    return JSON.parse(this.safeStringify(this.initialNotification as Object)) as Object;
  }

  private buildExtrasFromUri(uriPage: string): Object {
    if (uriPage.length === 0) {
      return JSON.parse('{}') as Object;
    }
    return JSON.parse(`{"url":${JSON.stringify(uriPage)}}`) as Object;
  }

  handleForegroundPayload(payload: Object): void {
    const remoteMessageMap = this.buildRemoteMessage(payload);
    const encoded = this.safeStringify(remoteMessageMap);
    Log.i(TAG, `Forwarding foreground push payload length=${encoded.length}`);
    if (this.remoteMessageReceiveSink != null) {
      this.remoteMessageReceiveSink.success(encoded);
      return;
    }
    pendingForegroundPayloads.push(payload);
    Log.w(TAG, 'Queued foreground push payload; EventChannel sink not listening yet.');
  }

  private flushPendingForegroundPayloads(): void {
    if (this.remoteMessageReceiveSink == null || pendingForegroundPayloads.length === 0) {
      return;
    }
    const queued = pendingForegroundPayloads.splice(0, pendingForegroundPayloads.length);
    Log.i(TAG, `Flushing ${queued.length} pending foreground push payload(s)`);
    for (let i = 0; i < queued.length; i++) {
      const remoteMessageMap = this.buildRemoteMessage(queued[i]);
      this.remoteMessageReceiveSink.success(this.safeStringify(remoteMessageMap));
    }
  }

  private buildRemoteMessage(payload: Object): RemoteMessagePayload {
    const payloadLike = payload as PushPayloadLike;
    const message = new RemoteMessagePayload();
    const payloadData = payloadLike.data != undefined
      ? `${payloadLike.data}`
      : this.safeStringify(payload);

    message.to = payloadLike.to != undefined ? `${payloadLike.to}` : '';
    message.from = payloadLike.from != undefined ? `${payloadLike.from}` : '';
    message.messageId = this.extractMessageId(payloadLike);
    message.token = this.cachedToken;
    message.sentTime = payloadLike.sentTime != undefined ? Number(`${payloadLike.sentTime}`) : 0;
    message.urgency = payloadLike.urgency != undefined ? Number(`${payloadLike.urgency}`) : 0;
    message.originalUrgency =
      payloadLike.originalUrgency != undefined ? Number(`${payloadLike.originalUrgency}`) : 0;
    message.ttl = payloadLike.ttl != undefined ? Number(`${payloadLike.ttl}`) : 0;
    message.messageType = payloadLike.messageType != undefined ? `${payloadLike.messageType}` : '';
    message.collapseKey = payloadLike.collapseKey != undefined ? `${payloadLike.collapseKey}` : '';
    message.data = payloadData;
    this.fillNotificationFromPayloadData(payloadData, message.notification);
    message.dataOfMap = this.resolveDataOfMap(payloadData);
    return message;
  }

  private buildRemoteMessageFromExtras(extrasJson: string): RemoteMessagePayload {
    const message = new RemoteMessagePayload();
    message.token = this.cachedToken;
    message.data = extrasJson;
    message.dataOfMap = this.resolveDataOfMap(extrasJson);
    return message;
  }

  private resolveDataOfMap(data: string): string {
    const parsedPayload = this.parsePayloadData(data);
    if (parsedPayload != null && parsedPayload.data != undefined) {
      const nestedData = parsedPayload.data;
      if (typeof nestedData === 'string') {
        const nestedText = `${nestedData}`.trim();
        return nestedText.startsWith('{') && nestedText.endsWith('}')
          ? nestedText
          : `{"value":${JSON.stringify(nestedText)}}`;
      }
      return this.safeStringify(nestedData);
    }
    const trimmed = data.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      // Keep original JSON; Dart side now tolerates nested values.
      return trimmed;
    }
    return '{}';
  }

  private extractMessageId(payload: PushPayloadLike): string {
    if (payload.messageId != undefined) {
      return `${payload.messageId}`;
    }
    if (payload.msgId != undefined) {
      return `${payload.msgId}`;
    }
    return '';
  }

  private extractWantParameters(want: Want): Object {
    const wantWithParameters = want as WantLike;
    const parameters = wantWithParameters.parameters;
    if (parameters == undefined) {
      return JSON.parse('{}') as Object;
    }
    return parameters;
  }

  private fillNotificationFromPayloadData(
    payloadData: string,
    notification: RemoteMessageNotificationPayload,
  ): void {
    const payload = this.parsePayloadData(payloadData);
    if (payload == null) {
      return;
    }

    if (payload.notification != undefined) {
      const payloadNotification = payload.notification as NotificationLike;
      notification.title =
        payloadNotification.title != undefined ? `${payloadNotification.title}` : '';
      notification.body =
        payloadNotification.body != undefined ? `${payloadNotification.body}` : '';
      notification.NotifyId =
        payloadNotification.notifyId != undefined ? Number(`${payloadNotification.notifyId}`) : 0;
      return;
    }

    notification.title = payload.title != undefined ? `${payload.title}` : '';
    if (payload.body != undefined) {
      notification.body = `${payload.body}`;
      return;
    }
    notification.body = payload.content != undefined ? `${payload.content}` : '';
  }

  private parsePayloadData(payloadData: string): PayloadDataLike | null {
    try {
      const parsedObject = JSON.parse(payloadData) as Object;
      return parsedObject as PayloadDataLike;
    } catch (_) {
      return null;
    }
  }

  private extractWantUri(want: Want): string {
    const wantWithUri = want as WantLike;
    return wantWithUri.uri ?? '';
  }

  private safeStringify(value: Object): string {
    try {
      return JSON.stringify(value);
    } catch (_) {
      return '';
    }
  }

  private errorToMessage(error: Object): string {
    const businessError = error as BusinessError;
    const errorCode = businessError.code;
    const errorMessage = businessError.message;
    if (errorCode != undefined || errorMessage != undefined) {
      return `BusinessError(code=${errorCode}, message=${errorMessage})`;
    }
    return `${error}`;
  }
}
