import { advertising, AutoAdComponent } from '@kit.AdsKit';
import {
  HMS_BANNER_AD_ID,
  HMS_BANNER_HEIGHT,
  HMS_BANNER_LEFT,
  HMS_BANNER_REVEALED,
  HMS_BANNER_TOKEN,
  HMS_BANNER_TOP,
  HMS_BANNER_VISIBLE,
  HMS_BANNER_WIDTH,
} from './HmsBannerOverlayStorage';

const AD_TYPE_BANNER = 8;

/**
 * Host-side banner overlay for HarmonyOS Ads Kit.
 *
 * Flutter OHOS cannot paint Ads Kit banners inside PlatformView (hybrid
 * composition is a stub; texture cannot capture remote UIExtension). Host apps
 * must place this above FlutterPage:
 *
 * ```
 * Stack {
 *   FlutterPage({ viewId: this.viewId })
 *   HuaweiBannerOverlay()
 * }
 * ```
 *
 * Position / reveal updates do not remount AutoAdComponent (avoids scroll jank
 * and re-fired impressions).
 */
@Component
export struct HuaweiBannerOverlay {
  @StorageLink(HMS_BANNER_VISIBLE) bannerVisible: boolean = false;
  @StorageLink(HMS_BANNER_REVEALED) bannerRevealed: boolean = false;
  @StorageLink(HMS_BANNER_AD_ID) bannerAdId: string = '';
  @StorageLink(HMS_BANNER_LEFT) bannerLeft: number = 0;
  @StorageLink(HMS_BANNER_TOP) bannerTop: number = 0;
  @StorageLink(HMS_BANNER_WIDTH) bannerWidth: number = 360;
  @StorageLink(HMS_BANNER_HEIGHT) bannerHeight: number = 57;
  @StorageLink(HMS_BANNER_TOKEN) bannerToken: number = 0;

  build() {
    // Transparent stack so Flutter keeps receiving touches outside the ad.
    Stack() {
      if (this.bannerVisible && this.bannerAdId.length > 0) {
        HuaweiBannerAdHost({
          adId: this.bannerAdId,
          token: this.bannerToken,
          bannerWidth: this.bannerWidth,
          bannerHeight: this.bannerHeight,
        })
          .width(this.bannerWidth > 0 ? this.bannerWidth : '100%')
          .height(this.bannerHeight > 0 ? this.bannerHeight : 57)
          .position({ x: this.bannerLeft, y: this.bannerTop })
          // Hide under sticky headers without destroying the ad instance.
          .opacity(this.bannerRevealed ? 1 : 0)
          .hitTestBehavior(
            this.bannerRevealed ? HitTestMode.Default : HitTestMode.None
          )
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }
}

@Component
struct HuaweiBannerAdHost {
  @Prop adId: string = '';
  @Prop token: number = 0;
  @Prop bannerWidth: number = 360;
  @Prop bannerHeight: number = 57;

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

  build() {
    // Remount only when token/adId change, not on every scroll position tick.
    ForEach([this.token], (token: number) => {
      AutoAdComponent({
        adParam: {
          adType: AD_TYPE_BANNER,
          adId: this.adId,
          adWidth: 360,
          adHeight: this.bannerHeight >= 100 ? 144 : 57,
        },
        adOptions: this.adOptions,
        displayOptions: this.displayOptions,
        interactionListener: {
          onStatusChanged: (_status: string, _ad: advertising.Advertisement, _data: string) => {
          },
        },
      })
        .width('100%')
        .height('100%')
    }, (token: number) => `${token}_${this.adId}`)
  }
}
