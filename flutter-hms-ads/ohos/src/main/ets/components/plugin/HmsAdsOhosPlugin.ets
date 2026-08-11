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
  StreamHandler,
} from '@ohos/flutter_ohos';
import common from '@ohos.app.ability.common';
import { advertising } from '@kit.AdsKit';
import { HmsAdsBannerOhosViewFactory } from './HmsAdsBannerOhosViewFactory';

const TAG = 'HmsAdsOhosPlugin';
const METHOD_CHANNEL = 'com.huawei.hms.flutter.ads/method';
const BANNER_METHOD_CHANNEL = 'com.huawei.hms.flutter.ads/banner/method';
const BANNER_EVENT_CHANNEL = 'com.huawei.hms.flutter.ads/banner/event';
const INTERSTITIAL_METHOD_CHANNEL = 'com.huawei.hms.flutter.ads/interstitial/method';
const INTERSTITIAL_EVENT_CHANNEL = 'com.huawei.hms.flutter.ads/interstitial/event';
const BANNER_VIEW_TYPE = 'com.huawei.hms.flutter.ads/banner/view';

const AD_TYPE_BANNER = 8;
const AD_TYPE_INTERSTITIAL = 12;

// Must match ohos/entry/.../ads/HuaweiBannerOverlay.ets keys.
const HMS_BANNER_VISIBLE = 'hms_banner_visible';
const HMS_BANNER_AD_ID = 'hms_banner_ad_id';
const HMS_BANNER_LEFT = 'hms_banner_left';
const HMS_BANNER_TOP = 'hms_banner_top';
const HMS_BANNER_WIDTH = 'hms_banner_width';
const HMS_BANNER_HEIGHT = 'hms_banner_height';
const HMS_BANNER_TOKEN = 'hms_banner_token';
let bannerOverlayToken: number = 1;

class AdEventStreamHandler implements StreamHandler {
  private owner: HmsAdsOhosPlugin;
  private readonly adId: number;
  private readonly kind: string;

  constructor(owner: HmsAdsOhosPlugin, adId: number, kind: string) {
    this.owner = owner;
    this.adId = adId;
    this.kind = kind;
  }

  onListen(_args: Object, events: EventSink): void {
    this.owner.setEventSink(this.kind, this.adId, events);
  }

  onCancel(_args: Object): void {
    this.owner.setEventSink(this.kind, this.adId, null);
  }
}

class InterstitialAdRecord {
  adSlotId: string = '';
  ads: Array<advertising.Advertisement> = [];
  loaded: boolean = false;
  loading: boolean = false;
  eventChannel: EventChannel | null = null;
  eventSink: EventSink | null = null;
}

class BannerAdRecord {
  adSlotId: string = '';
  width: number = 320;
  height: number = 50;
  ads: Array<advertising.Advertisement> = [];
  loaded: boolean = false;
  loading: boolean = false;
  eventChannel: EventChannel | null = null;
  eventSink: EventSink | null = null;
}

export default class HmsAdsOhosPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private methodChannel: MethodChannel | null = null;
  private bannerMethodChannel: MethodChannel | null = null;
  private interstitialMethodChannel: MethodChannel | null = null;
  private uiContext: common.UIAbilityContext | null = null;
  private readonly interstitialAds: Map<number, InterstitialAdRecord> = new Map();
  private readonly bannerAds: Map<number, BannerAdRecord> = new Map();
  private messenger: FlutterPluginBinding | null = null;

  private readonly adOptions: advertising.AdOptions = {
    adContentClassification: 'A',
    nonPersonalizedAd: 0,
    tagForChildProtection: -1,
    tagForUnderAgeOfPromise: -1,
    allowMobileTraffic: 0,
  };

  private readonly displayOptions: advertising.AdDisplayOptions = {
    mute: true,
  };

  getUniqueClassName(): string {
    return TAG;
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.messenger = binding;
    this.ensureBannerOverlayDefaults();
    this.methodChannel = new MethodChannel(binding.getBinaryMessenger(), METHOD_CHANNEL);
    this.methodChannel.setMethodCallHandler(this);

    this.bannerMethodChannel = new MethodChannel(
      binding.getBinaryMessenger(),
      BANNER_METHOD_CHANNEL,
    );
    this.bannerMethodChannel.setMethodCallHandler(this);

    this.interstitialMethodChannel = new MethodChannel(
      binding.getBinaryMessenger(),
      INTERSTITIAL_METHOD_CHANNEL,
    );
    this.interstitialMethodChannel.setMethodCallHandler(this);

    binding
      .getPlatformViewRegistry()
      .registerViewFactory(
        BANNER_VIEW_TYPE,
        new HmsAdsBannerOhosViewFactory(binding.getBinaryMessenger()),
      );

    Log.i(TAG, 'OHOS Huawei ads plugin registered');
  }

  private ensureBannerOverlayDefaults(): void {
    AppStorage.setOrCreate(HMS_BANNER_VISIBLE, false);
    AppStorage.setOrCreate(HMS_BANNER_AD_ID, '');
    AppStorage.setOrCreate(HMS_BANNER_LEFT, 0);
    AppStorage.setOrCreate(HMS_BANNER_TOP, 0);
    AppStorage.setOrCreate(HMS_BANNER_WIDTH, 360);
    AppStorage.setOrCreate(HMS_BANNER_HEIGHT, 57);
    AppStorage.setOrCreate(HMS_BANNER_TOKEN, 0);
  }

  private hideBannerOverlay(): void {
    AppStorage.setOrCreate(HMS_BANNER_VISIBLE, false);
    AppStorage.setOrCreate(HMS_BANNER_AD_ID, '');
  }

  private showBannerOverlay(
    adSlotId: string,
    left: number,
    top: number,
    width: number,
    height: number,
  ): void {
    // HarmonyOS Ads Kit Banner only accepts 360x57 / 360x144.
    const adHeight = height >= 100 ? 144 : 57;
    const previousAdId = AppStorage.get<string>(HMS_BANNER_AD_ID);
    const wasVisible = AppStorage.get<boolean>(HMS_BANNER_VISIBLE) === true;
    if (!wasVisible || previousAdId !== adSlotId) {
      bannerOverlayToken += 1;
      AppStorage.setOrCreate(HMS_BANNER_TOKEN, bannerOverlayToken);
    }
    AppStorage.setOrCreate(HMS_BANNER_AD_ID, adSlotId);
    AppStorage.setOrCreate(HMS_BANNER_LEFT, left);
    AppStorage.setOrCreate(HMS_BANNER_TOP, top);
    AppStorage.setOrCreate(HMS_BANNER_WIDTH, width > 0 ? width : 360);
    AppStorage.setOrCreate(HMS_BANNER_HEIGHT, adHeight);
    AppStorage.setOrCreate(HMS_BANNER_VISIBLE, true);
    Log.i(
      TAG,
      `Banner overlay show slot=${adSlotId} frame=${left},${top} ${width}x${adHeight} token=${bannerOverlayToken}`,
    );
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.methodChannel?.setMethodCallHandler(null);
    this.bannerMethodChannel?.setMethodCallHandler(null);
    this.interstitialMethodChannel?.setMethodCallHandler(null);
    this.methodChannel = null;
    this.bannerMethodChannel = null;
    this.interstitialMethodChannel = null;
    this.messenger = null;
    this.interstitialAds.clear();
    this.bannerAds.clear();
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.uiContext = binding.getAbility().context;
    Log.i(TAG, 'Ads plugin attached to ability');
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

  setEventSink(kind: string, adId: number, sink: EventSink | null): void {
    if (kind === 'interstitial') {
      const record = this.interstitialAds.get(adId);
      if (record != null) {
        record.eventSink = sink;
      }
      return;
    }
    if (kind === 'banner') {
      const record = this.bannerAds.get(adId);
      if (record != null) {
        record.eventSink = sink;
      }
    }
  }

  private emit(sink: EventSink | null, event: string, errorCode?: number): void {
    if (sink == null) {
      return;
    }
    const payload: Record<string, Object> = { 'event': event };
    if (errorCode != undefined) {
      payload['errorCode'] = errorCode;
    }
    sink.success(payload);
  }

  private requireContext(result: MethodResult): common.UIAbilityContext | null {
    if (this.uiContext == null) {
      result.error('NO_CONTEXT', 'UIAbilityContext is not available for Ads Kit', null);
      return null;
    }
    return this.uiContext;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    try {
      switch (call.method) {
        case 'HwAds-init':
        case 'HwAds-initWithAppCode':
          result.success(null);
          break;
        case 'HwAds-getSdkVersion':
          result.success('ohos-ads-kit');
          break;
        case 'enableLogger':
        case 'disableLogger':
          result.success(true);
          break;
        case 'initBannerAd':
          this.initBannerAd(call, result);
          break;
        case 'loadBannerAd':
          this.loadBannerAd(call, result);
          break;
        case 'showBannerAd':
          this.showBannerAd(call, result);
          break;
        case 'hideBannerAd':
          this.hideBannerOverlay();
          result.success(true);
          break;
        case 'isAdLoading':
          this.isAdLoading(call, result);
          break;
        case 'pauseAd':
        case 'resumeAd':
          result.success(true);
          break;
        case 'destroyAd':
          this.destroyAd(call, result);
          break;
        case 'initInterstitialAd':
          this.initInterstitialAd(call, result);
          break;
        case 'loadInterstitialAd':
          this.loadInterstitialAd(call, result);
          break;
        case 'showInterstitialAd':
          this.showInterstitialAd(call, result);
          break;
        case 'isAdLoaded':
          this.isAdLoaded(call, result);
          break;
        default:
          Log.w(TAG, `Unsupported ads method: ${call.method}`);
          result.notImplemented();
          break;
      }
    } catch (error) {
      Log.e(TAG, `Ads method failed: ${call.method} ${JSON.stringify(error)}`);
      result.error('ADS_ERROR', `${error}`, null);
    }
  }

  private argsMap(call: MethodCall): Map<string, Object> {
    return call.args as Map<string, Object>;
  }

  private readId(call: MethodCall): number {
    const id = this.argsMap(call).get('id');
    if (typeof id === 'number') {
      return id;
    }
    return Number(id);
  }

  private initBannerAd(call: MethodCall, result: MethodResult): void {
    if (this.messenger == null) {
      result.error('NO_ENGINE', 'Flutter engine is not attached', null);
      return;
    }
    const args = this.argsMap(call);
    const id = this.readId(call);
    const record = new BannerAdRecord();
    const width = args.get('width');
    const height = args.get('height');
    if (typeof width === 'number' && width > 0) {
      record.width = width;
    }
    if (typeof height === 'number' && height > 0) {
      record.height = height;
    }
    // Normalize to HarmonyOS Ads Kit supported banner sizes.
    if (record.height >= 100) {
      record.width = 360;
      record.height = 144;
    } else {
      record.width = 360;
      record.height = 57;
    }
    record.eventChannel = new EventChannel(
      this.messenger.getBinaryMessenger(),
      `${BANNER_EVENT_CHANNEL}/${id}`,
    );
    record.eventChannel.setStreamHandler(new AdEventStreamHandler(this, id, 'banner'));
    this.bannerAds.set(id, record);
    result.success(true);
  }

  private loadBannerAd(call: MethodCall, result: MethodResult): void {
    // Overlay AutoAdComponent loads itself; keep this as a lightweight prepare step.
    const args = this.argsMap(call);
    const id = this.readId(call);
    const record = this.bannerAds.get(id);
    if (record == null) {
      result.error('NOT_FOUND', `Banner ad ${id} not initialized`, null);
      return;
    }
    const adSlotId = args.get('adSlotId');
    if (typeof adSlotId === 'string') {
      record.adSlotId = adSlotId;
    }
    record.loading = false;
    record.loaded = record.adSlotId.length > 0;
    if (record.loaded) {
      this.emit(record.eventSink, 'onAdLoaded');
    }
    result.success(true);
  }

  private showBannerAd(call: MethodCall, result: MethodResult): void {
    const args = this.argsMap(call);
    const id = this.readId(call);
    const record = this.bannerAds.get(id);
    if (record == null) {
      result.error('NOT_FOUND', `Banner ad ${id} not initialized`, null);
      return;
    }
    if (record.adSlotId.length === 0) {
      result.error('NO_SLOT', 'Banner adSlotId is empty', null);
      return;
    }

    let left = 0;
    let top = 0;
    let width = record.width;
    let height = record.height;
    const leftArg = args.get('left');
    const topArg = args.get('top');
    const widthArg = args.get('width');
    const heightArg = args.get('height');
    if (typeof leftArg === 'number') {
      left = leftArg;
    }
    if (typeof topArg === 'number') {
      top = topArg;
    }
    if (typeof widthArg === 'number' && widthArg > 0) {
      width = widthArg;
    }
    if (typeof heightArg === 'number' && heightArg > 0) {
      height = heightArg;
    }

    // Fallback gravity/offset when absolute frame is not provided.
    if (!(typeof leftArg === 'number' && typeof topArg === 'number')) {
      const gravity = args.get('gravity');
      const offsetRaw = args.get('offset');
      let offset = 0;
      if (typeof offsetRaw === 'string') {
        offset = Number(offsetRaw);
      } else if (typeof offsetRaw === 'number') {
        offset = offsetRaw;
      }
      left = 0;
      width = width > 0 ? width : 360;
      height = height >= 100 ? 144 : 57;
      top = gravity === 'top' ? offset : Math.max(0, 800 - height - offset);
    }

    this.showBannerOverlay(record.adSlotId, left, top, width, height);
    this.emit(record.eventSink, 'onAdOpened');
    this.emit(record.eventSink, 'onAdImpression');
    result.success(true);
  }

  private initInterstitialAd(call: MethodCall, result: MethodResult): void {
    if (this.messenger == null) {
      result.error('NO_ENGINE', 'Flutter engine is not attached', null);
      return;
    }
    const id = this.readId(call);
    const record = new InterstitialAdRecord();
    record.eventChannel = new EventChannel(
      this.messenger.getBinaryMessenger(),
      `${INTERSTITIAL_EVENT_CHANNEL}/${id}`,
    );
    record.eventChannel.setStreamHandler(new AdEventStreamHandler(this, id, 'interstitial'));
    this.interstitialAds.set(id, record);
    result.success(true);
  }

  private loadInterstitialAd(call: MethodCall, result: MethodResult): void {
    const context = this.requireContext(result);
    if (context == null) {
      return;
    }
    const args = this.argsMap(call);
    const id = this.readId(call);
    const record = this.interstitialAds.get(id);
    if (record == null) {
      result.error('NOT_FOUND', `Interstitial ad ${id} not initialized`, null);
      return;
    }
    const adSlotId = args.get('adSlotId');
    if (typeof adSlotId === 'string') {
      record.adSlotId = adSlotId;
    }
    record.loading = true;
    record.loaded = false;

    const adRequestParams: advertising.AdRequestParams = {
      adId: record.adSlotId,
      adType: AD_TYPE_INTERSTITIAL,
    };
    const listener: advertising.AdLoadListener = {
      onAdLoadFailure: (errorCode: number, errorMsg: string) => {
        record.loading = false;
        record.loaded = false;
        Log.e(TAG, `Interstitial ${id} failed: ${errorCode} ${errorMsg}`);
        this.emit(record.eventSink, 'onAdFailed', errorCode);
      },
      onAdLoadSuccess: (ads: Array<advertising.Advertisement>) => {
        record.loading = false;
        record.loaded = ads.length > 0;
        record.ads = ads;
        Log.i(TAG, `Interstitial ${id} loaded`);
        this.emit(record.eventSink, 'onAdLoaded');
      },
    };
    try {
      const adLoader = new advertising.AdLoader(context);
      adLoader.loadAd(adRequestParams, this.adOptions, listener);
      result.success(true);
    } catch (error) {
      record.loading = false;
      result.error('LOAD_ERROR', `${error}`, null);
    }
  }

  private showInterstitialAd(call: MethodCall, result: MethodResult): void {
    const context = this.requireContext(result);
    if (context == null) {
      return;
    }
    const id = this.readId(call);
    const record = this.interstitialAds.get(id);
    if (record == null || !record.loaded || record.ads.length === 0) {
      result.error('NOT_LOADED', `Interstitial ad ${id} is not loaded`, null);
      return;
    }
    try {
      advertising.showAd(record.ads[0], this.displayOptions, context);
      this.emit(record.eventSink, 'onAdOpened');
      this.emit(record.eventSink, 'onAdImpression');
      result.success(true);
    } catch (error) {
      this.emit(record.eventSink, 'onAdFailed', -1);
      result.error('SHOW_ERROR', `${error}`, null);
    }
  }

  private isAdLoading(call: MethodCall, result: MethodResult): void {
    const args = this.argsMap(call);
    const id = this.readId(call);
    const adType = args.get('adType');
    if (adType === 'Interstitial') {
      result.success(this.interstitialAds.get(id)?.loading ?? false);
      return;
    }
    result.success(this.bannerAds.get(id)?.loading ?? false);
  }

  private isAdLoaded(call: MethodCall, result: MethodResult): void {
    const args = this.argsMap(call);
    const id = this.readId(call);
    const adType = args.get('adType');
    if (adType === 'Interstitial') {
      result.success(this.interstitialAds.get(id)?.loaded ?? false);
      return;
    }
    result.success(this.bannerAds.get(id)?.loaded ?? false);
  }

  private destroyAd(call: MethodCall, result: MethodResult): void {
    const args = this.argsMap(call);
    const id = this.readId(call);
    const adType = args.get('adType');
    if (adType === 'Interstitial') {
      const record = this.interstitialAds.get(id);
      record?.eventChannel?.setStreamHandler(null);
      this.interstitialAds.delete(id);
      result.success(true);
      return;
    }
    const banner = this.bannerAds.get(id);
    banner?.eventChannel?.setStreamHandler(null);
    this.bannerAds.delete(id);
    this.hideBannerOverlay();
    result.success(true);
  }
}
