# huawei_ads OHOS bridge

HarmonyOS NEXT Ads Kit bridge for the Flutter `huawei_ads` plugin.

## Scope (MVP)

- `HwAds.init`
- Banner via PlatformView (`BannerView` + `AdComponent`)
- Interstitial via `AdLoader` + `advertising.showAd`

Other formats return `notImplemented` on OHOS for now.

## Native APIs

- `@kit.AdsKit` / `advertising.AdLoader`
- Banner `adType = 8`, Interstitial `adType = 12`

## Test Ad Unit IDs (HarmonyOS)

| Format | ID |
|--------|----|
| Banner | `h5xkz3mbr2` |
| Interstitial | `p540739a8w` |

## Host app

Declare `ohos.permission.INTERNET` and optionally
`ohos.permission.APP_TRACKING_CONSENT` in the host `module.json5`.
