import common from '@ohos.app.ability.common';
import PlatformView, { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import {
  BinaryMessenger,
  EventChannel,
  EventSink,
  Log,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  StreamHandler,
} from '@ohos/flutter_ohos';
import { advertising, AutoAdComponent } from '@kit.AdsKit';

const TAG = 'HmsAdsBannerOhosView';
const BANNER_VIEW_TYPE = 'com.huawei.hms.flutter.ads/banner/view';
const AD_TYPE_BANNER = 8;
const bannerOwners: Map<number, Object> = new Map();
let nextBannerOwnerId: number = 1;

class BannerEventStreamHandler implements StreamHandler {
  private owner: HmsAdsBannerOhosView;

  constructor(owner: HmsAdsBannerOhosView) {
    this.owner = owner;
  }

  onListen(_args: Object, events: EventSink): void {
    this.owner.setEventSink(events);
  }

  onCancel(_args: Object): void {
    this.owner.setEventSink(null);
  }
}

/**
 * Banner PlatformView backed by Ads Kit AutoAdComponent.
 *
 * Prefer Flutter hybrid composition (initExpensiveOhosView). Texture-layer
 * composition can report onAdOpen while painting a blank surface because
 * AutoAdComponent hosts a remote ad UIAbility.
 */
export class HmsAdsBannerOhosView extends PlatformView implements MethodCallHandler {
  private readonly context: common.Context;
  private readonly channel: MethodChannel;
  private readonly eventChannel: EventChannel;
  private eventSink: EventSink | null = null;
  private adSlotId: string = '';
  // HarmonyOS Ads Kit Banner supported sizes: 360x57 / 360x144 (vp).
  private adWidth: number = 360;
  private adHeight: number = 57;
  private loadOnStart: boolean = true;
  private readonly ownerId: number;
  private showAd: boolean = true;

  constructor(context: common.Context, messenger: BinaryMessenger, viewId: number, args: object) {
    super();
    this.context = context;
    this.ownerId = nextBannerOwnerId;
    nextBannerOwnerId += 1;
    bannerOwners.set(this.ownerId, this);
    this.channel = new MethodChannel(messenger, `${BANNER_VIEW_TYPE}_${viewId}`);
    this.channel.setMethodCallHandler(this);
    this.eventChannel = new EventChannel(
      messenger,
      `com.huawei.hms.flutter.ads/banner/event/${viewId}`,
    );
    this.eventChannel.setStreamHandler(new BannerEventStreamHandler(this));
    this.initFromCreationParams(args);
    Log.i(
      TAG,
      `Banner view created slot=${this.adSlotId} size=${this.adWidth}x${this.adHeight} loadOnStart=${this.loadOnStart}`,
    );
  }

  getOwnerId(): number {
    return this.ownerId;
  }

  shouldShowAd(): boolean {
    return this.showAd && this.loadOnStart && this.adSlotId.length > 0;
  }

  getAdRequestParams(): advertising.AdRequestParams {
    return {
      adId: this.adSlotId,
      adType: AD_TYPE_BANNER,
      adWidth: this.adWidth,
      adHeight: this.adHeight,
    };
  }

  setEventSink(sink: EventSink | null): void {
    this.eventSink = sink;
  }

  private initFromCreationParams(args: object): void {
    const params = args as Map<string, Object>;
    const slot = params.get('adSlotId');
    if (typeof slot === 'string') {
      this.adSlotId = slot;
    }
    const loadOnStart = params.get('loadOnStart');
    if (typeof loadOnStart === 'boolean') {
      this.loadOnStart = loadOnStart;
    }
    const bannerSize = params.get('bannerSize');
    if (typeof bannerSize === 'string') {
      this.parseBannerSize(bannerSize);
    }
  }

  private parseBannerSize(bannerSize: string): void {
    const parts = bannerSize.split('_');
    if (parts.length >= 3) {
      const width = Number(parts[1]);
      const height = Number(parts[2]);
      if (!Number.isNaN(width) && width > 0) {
        this.adWidth = width;
      }
      if (!Number.isNaN(height) && height > 0) {
        this.adHeight = height;
      }
    }

    // Map common Android/AdMob sizes to HarmonyOS-supported Banner sizes.
    if (this.adHeight >= 100) {
      this.adWidth = 360;
      this.adHeight = 144;
    } else {
      this.adWidth = 360;
      this.adHeight = 57;
    }
  }

  private emit(event: string, errorCode?: number): void {
    if (this.eventSink == null) {
      return;
    }
    const payload: Record<string, Object> = { 'event': event };
    if (errorCode != undefined) {
      payload['errorCode'] = errorCode;
    }
    this.eventSink.success(payload);
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'loadAd':
        this.showAd = true;
        result.success(true);
        break;
      case 'destroyAd':
        this.showAd = false;
        result.success(true);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  getView(): WrappedBuilder<[Params]> {
    return new WrappedBuilder(HmsAdsBannerComponentBuilder);
  }

  onStatusChanged(status: string, _ad: advertising.Advertisement, _data: string): void {
    Log.i(TAG, `Banner status=${status}`);
    switch (status) {
      case 'onAdLoad':
      case 'AD_LOAD':
        this.emit('onAdLoaded');
        this.emit('onAdImpression');
        break;
      case 'onAdFail':
      case 'AD_FAIL':
        this.emit('onAdFailed', -1);
        break;
      case 'onAdOpen':
      case 'AD_OPEN':
        this.emit('onAdOpened');
        break;
      case 'onAdClick':
      case 'AD_CLICKED':
        this.emit('onAdClicked');
        break;
      case 'onAdClose':
      case 'AD_CLOSED':
        this.emit('onAdClosed');
        break;
      default:
        break;
    }
  }

  dispose(): void {
    bannerOwners.delete(this.ownerId);
    this.channel.setMethodCallHandler(null);
    this.eventChannel.setStreamHandler(null);
    this.eventSink = null;
    this.showAd = false;
  }
}

@Component
struct HmsAdsBannerNativeView {
  @ObjectLink params: Params;
  @State private adReady: boolean = false;
  @State private adParam: advertising.AdRequestParams = {
    adType: AD_TYPE_BANNER,
    adId: '',
    adWidth: 360,
    adHeight: 57,
  };
  private ownerId: number = 0;
  private mountTimerId: number = -1;
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

  aboutToAppear(): void {
    const view = this.params.platformView as HmsAdsBannerOhosView;
    this.ownerId = view.getOwnerId();
    if (!view.shouldShowAd()) {
      return;
    }
    // Delay until Flutter route slide finishes. AutoAdComponent marks itself
    // invisible when visibleRatio < 1 during the transition and may never
    // recover for remote ad UI.
    this.mountTimerId = setTimeout(() => {
      this.adParam = view.getAdRequestParams();
      this.adReady = true;
      Log.i(
        TAG,
        `AutoAdComponent ready slot=${this.adParam.adId} size=${this.adParam.adWidth}x${this.adParam.adHeight}`,
      );
    }, 450);
  }

  aboutToDisappear(): void {
    if (this.mountTimerId >= 0) {
      clearTimeout(this.mountTimerId);
      this.mountTimerId = -1;
    }
  }

  build() {
    Column() {
      if (this.adReady) {
        AutoAdComponent({
          adParam: this.adParam,
          adOptions: this.adOptions,
          displayOptions: this.displayOptions,
          interactionListener: {
            onStatusChanged: (status: string, ad: advertising.Advertisement, data: string) => {
              const owner = bannerOwners.get(this.ownerId) as HmsAdsBannerOhosView;
              if (owner) {
                owner.onStatusChanged(status, ad, data);
              }
            },
          },
        })
          .width('100%')
          .height('100%')
      }
    }
    .width('100%')
    .height('100%')
  }
}

@Builder
function HmsAdsBannerComponentBuilder(params: Params) {
  HmsAdsBannerNativeView({ params: params })
}
