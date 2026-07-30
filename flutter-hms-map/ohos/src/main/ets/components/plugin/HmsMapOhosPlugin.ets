import {
  FlutterPlugin,
  FlutterPluginBinding,
  Log,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';

import { HmsMapOhosViewFactory } from './HmsMapOhosViewFactory';

const MAP_CHANNEL = 'com.huawei.hms.flutter.map/map';
const MAP_UTIL_CHANNEL = 'com.huawei.hms.flutter.map/mapUtils';
const TAG = 'HmsMapOhosPlugin';

export default class HmsMapOhosPlugin implements FlutterPlugin, MethodCallHandler {
  private mapUtilChannel: MethodChannel | null = null;

  getUniqueClassName(): string {
    return 'HmsMapOhosPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    Log.i(TAG, 'Registering OHOS Huawei map plugin');
    this.mapUtilChannel = new MethodChannel(binding.getBinaryMessenger(), MAP_UTIL_CHANNEL);
    this.mapUtilChannel.setMethodCallHandler(this);
    binding
      .getPlatformViewRegistry()
      .registerViewFactory(MAP_CHANNEL, new HmsMapOhosViewFactory(binding.getBinaryMessenger()));
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.mapUtilChannel != null) {
      this.mapUtilChannel.setMethodCallHandler(null);
      this.mapUtilChannel = null;
    }
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    Log.d(TAG, `MapUtil method: ${call.method}`);
    switch (call.method) {
      case '[MapUtil]initializeMap':
      case '[MapUtil]setApiKey':
      case '[MapUtil]setAccessToken':
      case '[MapUtil]enableLogger':
      case '[MapUtil]disableLogger':
        result.success(null);
        return;
      case '[MapUtil]distanceCalculator':
        result.success(0.0);
        return;
      case '[MapUtil]convertCoordinate':
        result.success(call.args);
        return;
      case '[MapUtil]convertCoordinates':
        result.success(call.args);
        return;
      default:
        Log.w(TAG, `Unsupported MapUtil method: ${call.method}`);
        result.notImplemented();
        return;
    }
  }
}
