import {
  BinaryMessenger,
  PlatformView,
  PlatformViewFactory,
  StandardMessageCodec,
} from '@ohos/flutter_ohos';
import common from '@ohos.app.ability.common';
import { HmsAdsBannerOhosView } from './HmsAdsBannerOhosView';

export class HmsAdsBannerOhosViewFactory extends PlatformViewFactory {
  private messenger: BinaryMessenger;

  constructor(messenger: BinaryMessenger) {
    super(StandardMessageCodec.INSTANCE);
    this.messenger = messenger;
  }

  create(context: common.Context, viewId: number, args: object): PlatformView {
    return new HmsAdsBannerOhosView(context, this.messenger, viewId, args);
  }
}
