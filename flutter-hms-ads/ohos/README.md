# huawei_ads OHOS bridge

HarmonyOS NEXT Ads Kit bridge for the Flutter `huawei_ads` plugin.

## Scope (MVP)

- `HwAds.init`
- Banner via host ArkUI overlay (`HuaweiBannerOverlay` + `BannerAd.show` /
  `updateFrame` / `hide`) — preferred on current OHOS Flutter
- Banner PlatformView (`BannerView` + `AutoAdComponent`) — kept for future
  hybrid/texture support; blank today for Ads Kit remote UI
- Interstitial via `AdLoader` + `advertising.showAd`

Other formats return `notImplemented` on OHOS for now.

## Native APIs

- `@kit.AdsKit` / `advertising.AdLoader` / `AutoAdComponent`
- Banner `adType = 8`, Interstitial `adType = 12`

## Test Ad Unit IDs (HarmonyOS)

| Format | ID |
|--------|----|
| Banner | `h5xkz3mbr2` |
| Interstitial | `p540739a8w` |

## Host app

Declare `ohos.permission.INTERNET` and optionally
`ohos.permission.APP_TRACKING_CONSENT` in the host `module.json5`.

Place the exported overlay above `FlutterPage` in the host entry page:

```ets
import { FlutterPage } from '@ohos/flutter_ohos'
import { HuaweiBannerOverlay } from 'huawei_ads'

Stack({ alignContent: Alignment.TopStart }) {
  FlutterPage({ viewId: this.viewId })
    .width('100%')
    .height('100%')
  HuaweiBannerOverlay()
}
.width('100%')
.height('100%')
```
