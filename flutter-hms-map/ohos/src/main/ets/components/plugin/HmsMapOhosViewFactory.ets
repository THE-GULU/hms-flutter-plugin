import common from '@ohos.app.ability.common';
import {
  BinaryMessenger,
  PlatformView,
  PlatformViewFactory,
  StandardMessageCodec,
} from '@ohos/flutter_ohos';

import { HmsMapOhosView } from './HmsMapOhosView';

export class HmsMapOhosViewFactory extends PlatformViewFactory {
  private messenger: BinaryMessenger;

  constructor(messenger: BinaryMessenger) {
    super(StandardMessageCodec.INSTANCE);
    this.messenger = messenger;
  }

  create(context: common.Context, viewId: number, args: object): PlatformView {
    return new HmsMapOhosView(context, this.messenger, viewId, args);
  }
}
