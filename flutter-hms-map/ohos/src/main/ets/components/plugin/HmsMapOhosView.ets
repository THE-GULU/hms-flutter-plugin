import common from '@ohos.app.ability.common';
import PlatformView, { Params, PlatformViewVisibleAreaEventOptions } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import ApplicationStateChangeCallback from '@ohos.app.ability.ApplicationStateChangeCallback';
import { BinaryMessenger, Log, MethodCall, MethodCallHandler, MethodChannel, MethodResult } from '@ohos/flutter_ohos';
import { BusinessError } from '@ohos.base';
import image from '@ohos.multimedia.image';
import map from '@hms.core.map.map';
import mapCommon from '@hms.core.map.mapCommon';
import { MapComponent } from '@hms.core.map.MapComponent';

const MAP_CHANNEL = 'com.huawei.hms.flutter.map/map';
const TAG = 'HmsMapOhosView';

const METHOD_MAP_WAIT_FOR_MAP = '[Map]waitForMap';
const METHOD_MAP_UPDATE = '[Map]update';
const METHOD_MARKERS_UPDATE = '[Markers]update';
const METHOD_POLYLINES_UPDATE = '[Polylines]update';
const METHOD_POLYGONS_UPDATE = '[Polygons]update';
const METHOD_CIRCLES_UPDATE = '[Circles]update';
const METHOD_GROUND_OVERLAYS_UPDATE = '[GroundOverlays]update';
const METHOD_TILE_OVERLAYS_UPDATE = '[TileOverlays]update';
const METHOD_HEATMAP_UPDATE = '[HeatMap]update';
const METHOD_CAMERA_MOVE = '[Camera]move';
const METHOD_CAMERA_ANIMATE = '[Camera]animate';
const METHOD_STOP_ANIMATION = '[Map]stopAnimation';
const METHOD_MAP_SET_STYLE = '[Map]setStyle';
const METHOD_SET_LOCATION = '[Map]setLocation';
const METHOD_SET_LOCATION_SOURCE = '[Map]setLocationSource';
const METHOD_DEACTIVATE_LOCATION_SOURCE = '[Map]deactivateLocationSource';
const METHOD_GET_VISIBLE_REGION = '[Map]getVisibleRegion';
const METHOD_GET_SCREEN_COORDINATE = '[Map]getScreenCoordinate';
const METHOD_GET_LATLNG = '[Map]getLatLng';
const METHOD_GET_ZOOM_LEVEL = '[Map]getZoomLevel';
const METHOD_GET_SCALE_PER_PIXEL = '[Map]getScalePerPixel';
const METHOD_TAKE_SNAPSHOT = '[Map]takeSnapshot';
const METHOD_SHOW_INFO_WINDOW = '[Markers]showInfoWindow';
const METHOD_HIDE_INFO_WINDOW = '[Markers]hideInfoWindow';
const METHOD_IS_INFO_WINDOW_SHOWN = '[Markers]isInfoWindowShown';
const METHOD_IS_MARKER_CLUSTERABLE = '[Markers]isMarkerClusterable';

const EVENT_CAMERA_MOVE_STARTED = '[Camera]onMoveStarted';
const EVENT_CAMERA_ON_MOVE = '[Camera]onMove';
const EVENT_CAMERA_ON_IDLE = '[Camera]onIdle';
const EVENT_MAP_CLICK = '[Map]click';
const EVENT_MAP_LONG_CLICK = '[Map]onLongPress';
const EVENT_MARKER_CLICK = '[Marker]click';
const EVENT_INFO_WINDOW_CLICK = '[InfoWindow]click';
const EVENT_INFO_WINDOW_CLOSE = '[InfoWindow]close';
const EVENT_MARKER_DRAG_START = '[Marker]onDragStart';
const EVENT_MARKER_DRAG = '[Marker]onDrag';
const EVENT_MARKER_DRAG_END = '[Marker]onDragEnd';
const EVENT_POI_CLICK = '[Map]onPoiClick';
const EVENT_MY_LOCATION_CLICK = '[Map]onMyLocationClick';
const EVENT_MY_LOCATION_BUTTON_CLICK = '[Map]onMyLocationButtonClick';

class MarkerTag {
  id: string = '';
}

enum MarkerIconPayloadType {
  NONE = 0,
  DEFAULT_MARKER = 1,
  FROM_BYTES = 2,
}

class MarkerIconPayload {
  type: MarkerIconPayloadType = MarkerIconPayloadType.NONE;
  icon: image.PixelMap | undefined = undefined;
}

@Observed
class HmsMapRuntimeState {
  ready: boolean = false;
  revision: number = 0;
}

export class HmsMapOhosView extends PlatformView implements MethodCallHandler {
  private readonly context: common.Context;
  private readonly channel: MethodChannel;
  private readonly runtimeState: HmsMapRuntimeState = new HmsMapRuntimeState();

  private mapOptions: mapCommon.MapOptions = {
    mapType: mapCommon.MapType.STANDARD,
    position: {
      target: { latitude: 0.0, longitude: 0.0 },
      zoom: 14.0,
      tilt: 0.0,
      bearing: 0.0,
    },
  };

  private controller: map.MapComponentController | undefined = undefined;
  private lastOptions: Map<string, Object> | undefined = undefined;
  private myLocationButtonClickEventEnabled: boolean = false;
  private myLocationButtonClickRegistered: boolean = false;
  private markerPayloadByFlutterId: Map<string, Map<string, Object>> = new Map<string, Map<string, Object>>();
  private markerByFlutterId: Map<string, map.Marker> = new Map<string, map.Marker>();
  private markerFlutterIdByNativeId: Map<string, string> = new Map<string, string>();
  private eventsRegistered: boolean = false;
  private released: boolean = false;
  private mapHidden: boolean = false;
  private appStateListening: boolean = false;
  private appStateCallback: ApplicationStateChangeCallback | undefined = undefined;
  private ownedPixelMaps: Array<image.PixelMap> = [];
  private mapReadyCallback: (error: BusinessError, controller: map.MapComponentController) => void =
    (error: BusinessError, controller: map.MapComponentController): void => {
      if (error != undefined || controller != undefined) {
        return;
      }
    };
  private cameraMoveStartListener: (reason: number) => void = (reason: number): void => {
    if (reason < 0) {
      return;
    }
  };
  private cameraMoveListener: () => void = (): void => {
  };
  private cameraIdleListener: () => void = (): void => {
  };
  private mapClickListener: (latLng: mapCommon.LatLng) => void = (latLng: mapCommon.LatLng): void => {
    if (latLng.latitude < -90) {
      return;
    }
  };
  private mapLongClickListener: (latLng: mapCommon.LatLng) => void = (latLng: mapCommon.LatLng): void => {
    if (latLng.latitude < -90) {
      return;
    }
  };
  private poiClickListener: (poi: mapCommon.Poi) => void = (poi: mapCommon.Poi): void => {
    if (poi.name.length < 0) {
      return;
    }
  };
  private myLocationClickListener: (latLng: mapCommon.LatLng) => void = (latLng: mapCommon.LatLng): void => {
    if (latLng.latitude < -90) {
      return;
    }
  };
  private myLocationButtonClickListener: () => boolean = (): boolean => false;
  private markerClickListener: (marker: map.Marker) => void = (marker: map.Marker): void => {
    marker.getId();
  };
  private infoWindowClickListener: (marker: map.Marker) => void = (marker: map.Marker): void => {
    marker.getId();
  };
  private infoWindowCloseListener: (marker: map.Marker) => void = (marker: map.Marker): void => {
    marker.getId();
  };
  private markerDragStartListener: (marker: map.Marker) => void = (marker: map.Marker): void => {
    marker.getId();
  };
  private markerDragListener: (marker: map.Marker) => void = (marker: map.Marker): void => {
    marker.getId();
  };
  private markerDragEndListener: (marker: map.Marker) => void = (marker: map.Marker): void => {
    marker.getId();
  };

  constructor(context: common.Context, messenger: BinaryMessenger, viewId: number, args: object) {
    super();
    this.context = context;
    this.channel = new MethodChannel(messenger, `${MAP_CHANNEL}_${viewId}`);
    this.initListeners();
    this.channel.setMethodCallHandler(this);
    this.initFromCreationParams(args);
    this.registerAppStateListener();
  }

  private initListeners(): void {
    this.mapReadyCallback = (error: BusinessError, controller: map.MapComponentController): void => {
      this.onMapReady(error, controller);
    };
    this.cameraMoveStartListener = (reason: number): void => {
      const payload = new Map<string, Object>();
      payload.set('reason', reason);
      this.channel.invokeMethod(EVENT_CAMERA_MOVE_STARTED, payload);
    };
    this.cameraMoveListener = (): void => {
      this.emitCameraPosition();
    };
    this.cameraIdleListener = (): void => {
      this.channel.invokeMethod(EVENT_CAMERA_ON_IDLE, null);
    };
    this.mapClickListener = (latLng: mapCommon.LatLng): void => {
      const payload = new Map<string, Object>();
      payload.set('position', [latLng.latitude, latLng.longitude]);
      this.channel.invokeMethod(EVENT_MAP_CLICK, payload);
    };
    this.mapLongClickListener = (latLng: mapCommon.LatLng): void => {
      const payload = new Map<string, Object>();
      payload.set('position', [latLng.latitude, latLng.longitude]);
      this.channel.invokeMethod(EVENT_MAP_LONG_CLICK, payload);
    };
    this.poiClickListener = (poi: mapCommon.Poi): void => {
      const poiPayload = new Map<string, Object>();
      poiPayload.set('name', poi.name);
      poiPayload.set('placeId', poi.id);
      poiPayload.set('latLng', [poi.position.latitude, poi.position.longitude]);
      const payload = new Map<string, Object>();
      payload.set('pointOfInterest', poiPayload);
      this.channel.invokeMethod(EVENT_POI_CLICK, payload);
    };
    this.myLocationClickListener = (latLng: mapCommon.LatLng): void => {
      const locationPayload = new Map<string, Object>();
      locationPayload.set('latitude', latLng.latitude);
      locationPayload.set('longitude', latLng.longitude);
      const payload = new Map<string, Object>();
      payload.set('location', locationPayload);
      this.channel.invokeMethod(EVENT_MY_LOCATION_CLICK, payload);
    };
    this.myLocationButtonClickListener = (): boolean => {
      this.channel.invokeMethod(EVENT_MY_LOCATION_BUTTON_CLICK, false);
      return false;
    };
    this.markerClickListener = (marker: map.Marker): void => {
      const payload = new Map<string, Object>();
      payload.set('markerId', this.resolveFlutterMarkerId(marker));
      this.channel.invokeMethod(EVENT_MARKER_CLICK, payload);
    };
    this.infoWindowClickListener = (marker: map.Marker): void => {
      const payload = new Map<string, Object>();
      payload.set('markerId', this.resolveFlutterMarkerId(marker));
      this.channel.invokeMethod(EVENT_INFO_WINDOW_CLICK, payload);
    };
    this.infoWindowCloseListener = (marker: map.Marker): void => {
      const payload = new Map<string, Object>();
      payload.set('markerId', this.resolveFlutterMarkerId(marker));
      this.channel.invokeMethod(EVENT_INFO_WINDOW_CLOSE, payload);
    };
    this.markerDragStartListener = (marker: map.Marker): void => {
      this.channel.invokeMethod(EVENT_MARKER_DRAG_START, this.createMarkerDragPayload(marker));
    };
    this.markerDragListener = (marker: map.Marker): void => {
      this.channel.invokeMethod(EVENT_MARKER_DRAG, this.createMarkerDragPayload(marker));
    };
    this.markerDragEndListener = (marker: map.Marker): void => {
      this.channel.invokeMethod(EVENT_MARKER_DRAG_END, this.createMarkerDragPayload(marker));
    };
  }

  private initFromCreationParams(args: object): void {
    const params = args as Map<string, Object>;
    const initialCameraPosition = params.get('initialCameraPosition') as Map<string, Object> | undefined;
    if (initialCameraPosition != undefined) {
      this.mapOptions.position = this.toCameraPosition(initialCameraPosition);
    }

    const options = params.get('options') as Map<string, Object> | undefined;
    if (options != undefined) {
      this.lastOptions = options;
      this.applyMapOptions(options);
    }

    const markers = params.get('markersToAdd') as Array<Map<string, Object>> | undefined;
    if (markers != undefined) {
      markers.forEach((item) => {
        const markerId = this.getMarkerPayloadId(item);
        if (markerId.length > 0) {
          this.markerPayloadByFlutterId.set(markerId, item);
        }
      });
    }
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    Log.d(TAG, `Map method: ${call.method}`);
    switch (call.method) {
      case METHOD_MAP_WAIT_FOR_MAP:
        result.success(null);
        return;
      case METHOD_MAP_UPDATE: {
        const options = call.argument('options') as Map<string, Object> | undefined;
        if (options != undefined) {
          this.lastOptions = options;
          this.applyMapOptions(options);
        }
        result.success(null);
        return;
      }
      case METHOD_MARKERS_UPDATE: {
        const markersToAdd = call.argument('markersToAdd') as Array<Map<string, Object>> | undefined;
        const markersToChange = call.argument('markersToChange') as Array<Map<string, Object>> | undefined;
        const markerIdsToRemove = call.argument('markerIdsToRemove') as Array<string> | undefined;
        this.handleMarkerPayloadUpdates(markersToAdd, markersToChange, markerIdsToRemove);
        this.syncMarkers().then(() => result.success(null)).catch((_error: Object) => result.success(null));
        return;
      }
      case METHOD_POLYLINES_UPDATE:
      case METHOD_POLYGONS_UPDATE:
      case METHOD_CIRCLES_UPDATE:
      case METHOD_GROUND_OVERLAYS_UPDATE:
      case METHOD_TILE_OVERLAYS_UPDATE:
      case METHOD_HEATMAP_UPDATE:
      case METHOD_STOP_ANIMATION:
      case METHOD_SET_LOCATION_SOURCE:
      case METHOD_DEACTIVATE_LOCATION_SOURCE:
        result.success(null);
        return;
      case METHOD_MAP_SET_STYLE:
        result.success(null);
        return;
      case METHOD_SET_LOCATION: {
        const latLngArray = call.args as Array<number> | undefined;
        if (latLngArray != undefined) {
          const location = this.toLatLng(latLngArray);
          const update = map.newLatLng(location);
          if (this.controller != undefined) {
            this.controller.moveCamera(update);
          }
        }
        result.success(null);
        return;
      }
      case METHOD_CAMERA_MOVE:
      case METHOD_CAMERA_ANIMATE: {
        const cameraUpdateData = call.argument('cameraUpdate') as Array<Object> | undefined;
        const cameraUpdate = this.toCameraUpdate(cameraUpdateData);
        if (cameraUpdate != undefined && this.controller != undefined) {
          if (call.method == METHOD_CAMERA_ANIMATE) {
            this.controller.animateCamera(cameraUpdate, 300);
          } else {
            this.controller.moveCamera(cameraUpdate);
          }
        }
        result.success(null);
        return;
      }
      case METHOD_GET_ZOOM_LEVEL:
        result.success(this.controller != undefined ? this.controller.getCameraPosition().zoom : this.mapOptions.position.zoom);
        return;
      case METHOD_GET_SCALE_PER_PIXEL:
        result.success(this.controller != undefined ? this.controller.getScalePerPixel() : 0.0);
        return;
      case METHOD_GET_VISIBLE_REGION: {
        const region = this.getVisibleRegionPayload();
        result.success(region);
        return;
      }
      case METHOD_GET_SCREEN_COORDINATE: {
        const latLngArray = call.args as Array<number>;
        const payload = this.getScreenCoordinatePayload(latLngArray);
        result.success(payload);
        return;
      }
      case METHOD_GET_LATLNG: {
        const point = call.args as Map<string, number>;
        const payload = this.getLatLngPayload(point);
        result.success(payload);
        return;
      }
      case METHOD_TAKE_SNAPSHOT:
        result.success(null);
        return;
      case METHOD_SHOW_INFO_WINDOW: {
        const markerId = call.argument('markerId') as string;
        const marker = this.markerByFlutterId.get(markerId);
        if (marker != undefined) {
          marker.setInfoWindowVisible(true);
        }
        result.success(null);
        return;
      }
      case METHOD_HIDE_INFO_WINDOW: {
        const markerId = call.argument('markerId') as string;
        const marker = this.markerByFlutterId.get(markerId);
        if (marker != undefined) {
          marker.setInfoWindowVisible(false);
        }
        result.success(null);
        return;
      }
      case METHOD_IS_INFO_WINDOW_SHOWN: {
        const markerId = call.argument('markerId') as string;
        const marker = this.markerByFlutterId.get(markerId);
        result.success(marker != undefined ? marker.isInfoWindowVisible() : false);
        return;
      }
      case METHOD_IS_MARKER_CLUSTERABLE:
        result.success(false);
        return;
      default:
        Log.w(TAG, `Unsupported map method: ${call.method}`);
        result.success(null);
        return;
    }
  }

  private applyMapOptions(options: Map<string, Object>): void {
    const controller = this.controller;

    if (options.has('mapType')) {
      const mapTypeValue = Number(options.get('mapType'));
      const mapType = this.toMapType(mapTypeValue);
      this.mapOptions.mapType = mapType;
      if (controller != undefined) {
        controller.setMapType(mapType);
      }
    }
    if (options.has('rotateGesturesEnabled') && controller != undefined) {
      controller.setRotateGesturesEnabled(Boolean(options.get('rotateGesturesEnabled')));
    }
    if (options.has('scrollGesturesEnabled') && controller != undefined) {
      controller.setScrollGesturesEnabled(Boolean(options.get('scrollGesturesEnabled')));
    }
    if (options.has('tiltGesturesEnabled') && controller != undefined) {
      controller.setTiltGesturesEnabled(Boolean(options.get('tiltGesturesEnabled')));
    }
    if (options.has('zoomGesturesEnabled') && controller != undefined) {
      controller.setZoomGesturesEnabled(Boolean(options.get('zoomGesturesEnabled')));
    }
    if (options.has('zoomControlsEnabled') && controller != undefined) {
      controller.setZoomControlsEnabled(Boolean(options.get('zoomControlsEnabled')));
    }
    if (options.has('myLocationEnabled') && controller != undefined) {
      controller.setMyLocationEnabled(Boolean(options.get('myLocationEnabled')));
    }
    if (options.has('myLocationButtonEnabled') && controller != undefined) {
      controller.setMyLocationControlsEnabled(Boolean(options.get('myLocationButtonEnabled')));
    }
    if (options.has('myLocationButtonClickEventEnabled')) {
      this.myLocationButtonClickEventEnabled = Boolean(options.get('myLocationButtonClickEventEnabled'));
      if (controller != undefined) {
        this.registerMyLocationButtonClickListener(controller);
      }
    }
    if (options.has('trafficEnabled') && controller != undefined) {
      controller.setTrafficEnabled(Boolean(options.get('trafficEnabled')));
    }
    if (options.has('buildingsEnabled') && controller != undefined) {
      controller.setBuildingEnabled(Boolean(options.get('buildingsEnabled')));
    }
    if (options.has('allGesturesEnabled') && controller != undefined) {
      controller.setAllGesturesEnabled(Boolean(options.get('allGesturesEnabled')));
    }
    if (options.has('compassEnabled') && controller != undefined) {
      controller.setCompassControlsEnabled(Boolean(options.get('compassEnabled')));
    }
    if (options.has('minMaxZoomPreference') && controller != undefined) {
      const zooms = options.get('minMaxZoomPreference') as Array<number>;
      if (zooms != undefined && zooms.length > 1) {
        controller.setMinZoom(Number(zooms[0]));
        controller.setMaxZoom(Number(zooms[1]));
      }
    }
    if (options.has('padding') && controller != undefined) {
      const padding = options.get('padding') as Array<number>;
      if (padding != undefined && padding.length >= 4) {
        controller.setPadding({
          top: Number(padding[0]),
          left: Number(padding[1]),
          bottom: Number(padding[2]),
          right: Number(padding[3]),
        });
      }
    }

    this.runtimeState.revision = this.runtimeState.revision + 1;
  }

  private handleMarkerPayloadUpdates(
    markersToAdd: Array<Map<string, Object>> | undefined,
    markersToChange: Array<Map<string, Object>> | undefined,
    markerIdsToRemove: Array<string> | undefined,
  ): void {
    if (markerIdsToRemove != undefined) {
      markerIdsToRemove.forEach((id) => this.markerPayloadByFlutterId.delete(id));
    }
    const upsert = (payloads: Array<Map<string, Object>> | undefined): void => {
      if (payloads == undefined) {
        return;
      }
      payloads.forEach((payload) => {
        const markerId = this.getMarkerPayloadId(payload);
        if (markerId.length > 0) {
          this.markerPayloadByFlutterId.set(markerId, payload);
        }
      });
    };
    upsert(markersToAdd);
    upsert(markersToChange);
  }

  private async syncMarkers(): Promise<void> {
    if (this.controller == undefined) {
      return;
    }

    for (const existingId of this.markerByFlutterId.keys()) {
      if (!this.markerPayloadByFlutterId.has(existingId)) {
        const marker = this.markerByFlutterId.get(existingId);
        if (marker != undefined) {
          this.markerFlutterIdByNativeId.delete(marker.getId());
          marker.remove();
        }
        this.markerByFlutterId.delete(existingId);
      }
    }

    for (const flutterId of this.markerPayloadByFlutterId.keys()) {
      const payload = this.markerPayloadByFlutterId.get(flutterId);
      if (payload == undefined) {
        continue;
      }
      const existingMarker = this.markerByFlutterId.get(flutterId);
      if (existingMarker != undefined) {
        await this.applyMarkerToDelegate(existingMarker, payload);
      } else {
        const markerOptions = await this.toMarkerOptions(payload);
        const marker = await this.controller.addMarker(markerOptions);
        const markerTag = new MarkerTag();
        markerTag.id = flutterId;
        marker.setTag(markerTag);
        this.markerByFlutterId.set(flutterId, marker);
        this.markerFlutterIdByNativeId.set(marker.getId(), flutterId);
      }
    }
  }

  private async toMarkerOptions(payload: Map<string, Object>): Promise<mapCommon.MarkerOptions> {
    const markerOptions: mapCommon.MarkerOptions = {
      position: this.toLatLng(payload.get('position') as Array<number>),
    };

    if (payload.has('alpha')) {
      markerOptions.alpha = Number(payload.get('alpha'));
    }
    if (payload.has('zIndex')) {
      markerOptions.zIndex = Number(payload.get('zIndex'));
    }
    if (payload.has('clickable')) {
      markerOptions.clickable = Boolean(payload.get('clickable'));
    }
    if (payload.has('draggable')) {
      markerOptions.draggable = Boolean(payload.get('draggable'));
    }
    if (payload.has('flat')) {
      markerOptions.flat = Boolean(payload.get('flat'));
    }
    if (payload.has('rotation')) {
      markerOptions.rotation = Number(payload.get('rotation'));
    }
    const icon = await this.toMarkerIcon(payload);
    if (icon != undefined) {
      markerOptions.icon = icon;
    }

    const anchor = payload.get('anchor') as Array<number> | undefined;
    if (anchor != undefined && anchor.length >= 2) {
      markerOptions.anchorU = Number(anchor[0]);
      markerOptions.anchorV = Number(anchor[1]);
    }

    const infoWindow = payload.get('infoWindow') as Map<string, Object> | undefined;
    if (infoWindow != undefined) {
      if (infoWindow.has('title')) {
        markerOptions.title = String(infoWindow.get('title'));
      }
      if (infoWindow.has('snippet')) {
        markerOptions.snippet = String(infoWindow.get('snippet'));
      }
      const infoAnchor = infoWindow.get('anchor') as Array<number> | undefined;
      if (infoAnchor != undefined && infoAnchor.length >= 2) {
        markerOptions.infoWindowAnchorU = Number(infoAnchor[0]);
        markerOptions.infoWindowAnchorV = Number(infoAnchor[1]);
      }
    }
    return markerOptions;
  }

  private async applyMarkerToDelegate(marker: map.Marker, payload: Map<string, Object>): Promise<void> {
    const markerIconPayload = await this.toMarkerIconPayload(payload);
    let markerDelegate = marker;
    if (markerIconPayload.type == MarkerIconPayloadType.DEFAULT_MARKER) {
      markerDelegate = await this.resetMarkerToDefaultIcon(markerDelegate, payload);
    }
    if (payload.has('position')) {
      markerDelegate.setPosition(this.toLatLng(payload.get('position') as Array<number>));
    }
    if (payload.has('alpha')) {
      markerDelegate.setAlpha(Number(payload.get('alpha')));
    }
    if (payload.has('zIndex')) {
      markerDelegate.setZIndex(Number(payload.get('zIndex')));
    }
    if (payload.has('clickable')) {
      markerDelegate.setClickable(Boolean(payload.get('clickable')));
    }
    if (payload.has('draggable')) {
      markerDelegate.setDraggable(Boolean(payload.get('draggable')));
    }
    if (payload.has('flat')) {
      markerDelegate.setFlat(Boolean(payload.get('flat')));
    }
    if (payload.has('rotation')) {
      markerDelegate.setRotation(Number(payload.get('rotation')));
    }
    if (markerIconPayload.type == MarkerIconPayloadType.FROM_BYTES && markerIconPayload.icon != undefined) {
      await markerDelegate.setIcon(markerIconPayload.icon);
    }
    const anchor = payload.get('anchor') as Array<number> | undefined;
    if (anchor != undefined && anchor.length >= 2) {
      markerDelegate.setMarkerAnchor(Number(anchor[0]), Number(anchor[1]));
    }
    const infoWindow = payload.get('infoWindow') as Map<string, Object> | undefined;
    if (infoWindow != undefined) {
      if (infoWindow.has('title')) {
        markerDelegate.setTitle(String(infoWindow.get('title')));
      }
      if (infoWindow.has('snippet')) {
        markerDelegate.setSnippet(String(infoWindow.get('snippet')));
      }
      const infoAnchor = infoWindow.get('anchor') as Array<number> | undefined;
      if (infoAnchor != undefined && infoAnchor.length >= 2) {
        markerDelegate.setInfoWindowAnchor(Number(infoAnchor[0]), Number(infoAnchor[1]));
      }
    }
    if (payload.has('visible')) {
      markerDelegate.setVisible(Boolean(payload.get('visible')));
    }
  }

  private getMarkerPayloadId(payload: Map<string, Object>): string {
    const idValue = payload.get('markerId');
    return idValue == undefined ? '' : String(idValue);
  }

  private async toMarkerIcon(payload: Map<string, Object>): Promise<image.PixelMap | undefined> {
    const markerIconPayload = await this.toMarkerIconPayload(payload);
    return markerIconPayload.icon;
  }

  private async toMarkerIconPayload(payload: Map<string, Object>): Promise<MarkerIconPayload> {
    const iconPayload = payload.get('icon');
    const markerIconPayload = new MarkerIconPayload();
    if (iconPayload == undefined) {
      return markerIconPayload;
    }

    const iconData = iconPayload as Array<Object>;
    const iconType = String(iconData[0]);
    if (iconType == 'defaultMarker') {
      markerIconPayload.type = MarkerIconPayloadType.DEFAULT_MARKER;
      return markerIconPayload;
    }
    if (iconType != 'fromBytes' || iconData.length < 2) {
      return markerIconPayload;
    }

    const buffer = this.toArrayBuffer(iconData[1]);
    if (buffer == undefined) {
      return markerIconPayload;
    }

    const imageSource = image.createImageSource(buffer);
    try {
      const pixelMap = await imageSource.createPixelMap();
      markerIconPayload.type = MarkerIconPayloadType.FROM_BYTES;
      markerIconPayload.icon = pixelMap;
      this.ownedPixelMaps.push(pixelMap);
    } finally {
      await imageSource.release();
    }
    return markerIconPayload;
  }

  private async resetMarkerToDefaultIcon(marker: map.Marker, payload: Map<string, Object>): Promise<map.Marker> {
    const controller = this.controller;
    const flutterId = this.resolveFlutterMarkerId(marker);
    const nativeId = marker.getId();
    if (controller == undefined || flutterId.length == 0) {
      return marker;
    }
    this.markerFlutterIdByNativeId.delete(nativeId);
    marker.remove();
    const markerOptions = await this.toMarkerOptions(payload);
    const updatedMarker = await controller.addMarker(markerOptions);
    const markerTag = new MarkerTag();
    markerTag.id = flutterId;
    updatedMarker.setTag(markerTag);
    this.markerByFlutterId.set(flutterId, updatedMarker);
    this.markerFlutterIdByNativeId.set(updatedMarker.getId(), flutterId);
    return updatedMarker;
  }

  private toArrayBuffer(value: Object): ArrayBuffer | undefined {
    if (value == undefined) {
      return undefined;
    }
    if (value instanceof ArrayBuffer) {
      return value;
    }
    if (value instanceof Uint8Array) {
      return value.buffer.slice(value.byteOffset, value.byteOffset + value.byteLength);
    }
    if (Array.isArray(value)) {
      const list = value as Array<number>;
      const bytes = new Uint8Array(list.length);
      for (let i = 0; i < list.length; i++) {
        bytes[i] = Number(list[i]) & 0xFF;
      }
      return bytes.buffer;
    }
    return undefined;
  }

  private toLatLng(latLngArray: Array<number>): mapCommon.LatLng {
    return {
      latitude: Number(latLngArray[0]),
      longitude: Number(latLngArray[1]),
    };
  }

  private toCameraPosition(data: Map<string, Object>): mapCommon.CameraPosition {
    const target = data.get('target') as Array<number>;
    const zoom = Number(data.get('zoom'));
    const tiltData = data.get('tilt');
    const bearingData = data.get('bearing');
    return {
      target: this.toLatLng(target),
      zoom: zoom,
      tilt: tiltData == undefined ? 0.0 : Number(tiltData),
      bearing: bearingData == undefined ? 0.0 : Number(bearingData),
    };
  }

  private toMapType(type: number): mapCommon.MapType {
    switch (type) {
      case 0:
        return mapCommon.MapType.NONE;
      case 1:
        return mapCommon.MapType.STANDARD;
      case 2:
      case 3:
        return mapCommon.MapType.TERRAIN;
      default:
        return mapCommon.MapType.STANDARD;
    }
  }

  private toCameraUpdate(data: Array<Object> | undefined): map.CameraUpdate | undefined {
    if (data == undefined || data.length == 0) {
      return undefined;
    }
    const op = String(data[0]);
    switch (op) {
      case 'newLatLng':
        return map.newLatLng(this.toLatLng(data[1] as Array<number>));
      case 'newLatLngZoom':
        return map.newLatLng(this.toLatLng(data[1] as Array<number>), Number(data[2]));
      case 'newCameraPosition':
        return map.newCameraPosition(this.toCameraPosition(data[1] as Map<string, Object>));
      case 'zoomIn':
        return map.zoomIn();
      case 'zoomOut':
        return map.zoomOut();
      case 'zoomTo':
        return map.zoomTo(Number(data[1]));
      case 'scrollBy':
        return map.scrollBy(Number(data[1]), Number(data[2]));
      case 'zoomBy':
        return map.zoomBy(Number(data[1]));
      case 'newLatLngBounds': {
        const boundsRaw = data[1] as Array<Array<number>>;
        const bounds: mapCommon.LatLngBounds = {
          southwest: this.toLatLng(boundsRaw[0]),
          northeast: this.toLatLng(boundsRaw[1]),
        };
        if (data.length > 2) {
          return map.newLatLngBounds(bounds, Number(data[2]));
        }
        return map.newLatLngBounds(bounds);
      }
      default:
        return undefined;
    }
  }

  private emitCameraPosition(): void {
    if (this.controller == undefined) {
      return;
    }
    const position = this.controller.getCameraPosition();
    const target = [position.target.latitude, position.target.longitude];
    const payload = new Map<string, Object>();
    const cameraPayload = new Map<string, Object>();
    cameraPayload.set('target', target);
    cameraPayload.set('zoom', position.zoom);
    cameraPayload.set('tilt', position.tilt == undefined ? 0.0 : position.tilt);
    cameraPayload.set('bearing', position.bearing == undefined ? 0.0 : position.bearing);
    payload.set('position', cameraPayload);
    this.channel.invokeMethod(EVENT_CAMERA_ON_MOVE, payload);
  }

  private getVisibleRegionPayload(): Map<string, Object> {
    const response = new Map<string, Object>();
    if (this.controller == undefined) {
      response.set('northeast', [0.0, 0.0]);
      response.set('southwest', [0.0, 0.0]);
      return response;
    }
    const bounds = this.controller.getProjection().getVisibleRegion().bounds;
    response.set('northeast', [bounds.northeast.latitude, bounds.northeast.longitude]);
    response.set('southwest', [bounds.southwest.latitude, bounds.southwest.longitude]);
    return response;
  }

  private getScreenCoordinatePayload(latLngArray: Array<number>): Map<string, number> {
    const response = new Map<string, number>();
    if (this.controller == undefined) {
      response.set('x', 0);
      response.set('y', 0);
      return response;
    }
    const point = this.controller.getProjection().toScreenLocation(this.toLatLng(latLngArray));
    response.set('x', point.positionX);
    response.set('y', point.positionY);
    return response;
  }

  private getLatLngPayload(pointData: Map<string, number>): Array<number> {
    if (this.controller == undefined) {
      return [0.0, 0.0];
    }
    const point: mapCommon.MapPoint = {
      positionX: Number(pointData.get('x')),
      positionY: Number(pointData.get('y')),
    };
    const latLng = this.controller.getProjection().fromScreenLocation(point);
    return [latLng.latitude, latLng.longitude];
  }

  private registerEvents(controller: map.MapComponentController): void {
    if (this.eventsRegistered) {
      return;
    }
    this.eventsRegistered = true;

    controller.on('cameraMoveStart', this.cameraMoveStartListener);
    controller.on('cameraMove', this.cameraMoveListener);
    controller.on('cameraIdle', this.cameraIdleListener);
    controller.on('mapClick', this.mapClickListener);
    controller.on('mapLongClick', this.mapLongClickListener);
    controller.on('poiClick', this.poiClickListener);
    controller.on('myLocationClick', this.myLocationClickListener);
    this.registerMyLocationButtonClickListener(controller);
    controller.on('markerClick', this.markerClickListener);
    controller.on('infoWindowClick', this.infoWindowClickListener);
    controller.on('infoWindowClose', this.infoWindowCloseListener);
    controller.on('markerDragStart', this.markerDragStartListener);
    controller.on('markerDrag', this.markerDragListener);
    controller.on('markerDragEnd', this.markerDragEndListener);
  }

  private unregisterEvents(controller: map.MapComponentController): void {
    if (!this.eventsRegistered) {
      return;
    }
    // off() is declared as Callback<void>, which does not accept the typed listeners passed to on().
    const events: ESObject = controller as ESObject;
    events.off('cameraMoveStart', this.cameraMoveStartListener);
    events.off('cameraMove', this.cameraMoveListener);
    events.off('cameraIdle', this.cameraIdleListener);
    events.off('mapClick', this.mapClickListener);
    events.off('mapLongClick', this.mapLongClickListener);
    events.off('poiClick', this.poiClickListener);
    events.off('myLocationClick', this.myLocationClickListener);
    if (this.myLocationButtonClickRegistered) {
      events.off('myLocationButtonClick', this.myLocationButtonClickListener);
    }
    events.off('markerClick', this.markerClickListener);
    events.off('infoWindowClick', this.infoWindowClickListener);
    events.off('infoWindowClose', this.infoWindowCloseListener);
    events.off('markerDragStart', this.markerDragStartListener);
    events.off('markerDrag', this.markerDragListener);
    events.off('markerDragEnd', this.markerDragEndListener);
    this.eventsRegistered = false;
    this.myLocationButtonClickRegistered = false;
  }

  private registerMyLocationButtonClickListener(controller: map.MapComponentController): void {
    if (!this.myLocationButtonClickEventEnabled || this.myLocationButtonClickRegistered) {
      return;
    }
    this.myLocationButtonClickRegistered = true;
    controller.on('myLocationButtonClick', this.myLocationButtonClickListener);
  }

  private resolveFlutterMarkerId(marker: map.Marker): string {
    const nativeId = marker.getId();
    const byNative = this.markerFlutterIdByNativeId.get(nativeId);
    if (byNative != undefined) {
      return byNative;
    }
    const tag = marker.getTag() as MarkerTag;
    if (tag != undefined && tag.id != undefined) {
      return tag.id;
    }
    return nativeId;
  }

  private createMarkerDragPayload(marker: map.Marker): Map<string, Object> {
    const payload = new Map<string, Object>();
    payload.set('markerId', this.resolveFlutterMarkerId(marker));
    const position = marker.getPosition();
    payload.set('position', [position.latitude, position.longitude]);
    return payload;
  }

  onMapReady(error: BusinessError, controller: map.MapComponentController): void {
    if (error != undefined) {
      Log.e(TAG, `Map init failed: ${error.message}`);
      return;
    }
    if (this.released) {
      this.shutdownController(controller, false);
      return;
    }
    this.controller = controller;
    this.mapHidden = false;
    this.runtimeState.ready = true;
    const options = this.lastOptions;
    if (options != undefined) {
      this.applyMapOptions(options);
    } else {
      this.applyMapOptions(new Map<string, Object>());
    }
    this.registerEvents(controller);
    this.syncMarkers();
    Log.i(TAG, 'Map component ready');
  }

  getView(): WrappedBuilder<[Params]> {
    return new WrappedBuilder(HmsMapComponentBuilder);
  }

  getMapOptions(): mapCommon.MapOptions {
    return this.mapOptions;
  }

  isReady(): boolean {
    return this.runtimeState.ready;
  }

  getMapReadyCallback(): (error: BusinessError, controller: map.MapComponentController) => void {
    return this.mapReadyCallback;
  }

  showMap(): void {
    const controller = this.controller;
    if (this.released || controller == undefined || !this.mapHidden) {
      return;
    }
    try {
      controller.show();
      this.mapHidden = false;
    } catch (error) {
      Log.w(TAG, `map show failed: ${error}`);
    }
  }

  hideMap(): void {
    const controller = this.controller;
    if (this.released || controller == undefined || this.mapHidden) {
      return;
    }
    try {
      controller.hide();
      this.mapHidden = true;
    } catch (error) {
      Log.w(TAG, `map hide failed: ${error}`);
    }
  }

  detachMap(): void {
    const controller = this.controller;
    this.controller = undefined;
    this.runtimeState.ready = false;
    if (controller != undefined) {
      this.shutdownController(controller, true);
    } else {
      this.releaseOwnedPixelMaps();
    }
    this.mapHidden = false;
  }

  getPlatformViewVisibleAreaEventOptions(): PlatformViewVisibleAreaEventOptions {
    return {
      enable: true,
      ratios: [0.0, 1.0],
      expectedUpdateInterval: 1000,
      onInactiveThreshold: 0.0,
      onActiveThreshold: 1.0,
    };
  }

  onInactive(): void {
    this.hideMap();
  }

  onActive(): void {
    this.showMap();
  }

  dispose(): void {
    if (this.released) {
      return;
    }
    this.released = true;
    this.detachMap();
    this.unregisterAppStateListener();
    this.channel.setMethodCallHandler(null);
  }

  private registerAppStateListener(): void {
    if (this.appStateListening) {
      return;
    }
    const callback = new MapAppStateCallback(this);
    this.appStateCallback = callback;
    try {
      this.context.getApplicationContext().on('applicationStateChange', callback);
      this.appStateListening = true;
    } catch (error) {
      Log.w(TAG, `applicationStateChange register failed: ${error}`);
    }
  }

  private unregisterAppStateListener(): void {
    const callback = this.appStateCallback;
    if (!this.appStateListening || callback == undefined) {
      return;
    }
    try {
      this.context.getApplicationContext().off('applicationStateChange', callback);
    } catch (error) {
      Log.w(TAG, `applicationStateChange unregister failed: ${error}`);
    }
    this.appStateListening = false;
    this.appStateCallback = undefined;
  }

  private shutdownController(controller: map.MapComponentController, unregister: boolean): void {
    try {
      controller.hide();
    } catch (error) {
      Log.w(TAG, `map hide failed: ${error}`);
    }
    if (unregister) {
      try {
        this.unregisterEvents(controller);
      } catch (error) {
        Log.w(TAG, `map listener unregister failed: ${error}`);
      }
      this.removeNativeMarkers();
    }
    try {
      controller.clear();
    } catch (error) {
      Log.w(TAG, `map clear failed: ${error}`);
    }
    this.releaseOwnedPixelMaps();
  }

  private removeNativeMarkers(): void {
    for (const flutterId of this.markerByFlutterId.keys()) {
      const marker = this.markerByFlutterId.get(flutterId);
      if (marker != undefined) {
        try {
          marker.remove();
        } catch (error) {
          Log.w(TAG, `marker remove failed: ${error}`);
        }
      }
    }
    this.markerByFlutterId.clear();
    this.markerFlutterIdByNativeId.clear();
  }

  private releaseOwnedPixelMaps(): void {
    const pixelMaps = this.ownedPixelMaps;
    this.ownedPixelMaps = [];
    for (let index = 0; index < pixelMaps.length; index++) {
      pixelMaps[index].release().catch((error: BusinessError) => {
        Log.w(TAG, `pixelMap release failed: ${error.message}`);
      });
    }
  }
}

@Component
struct HmsMapNativeView {
  @ObjectLink params: Params;
  mapView: HmsMapOhosView = this.params.platformView as HmsMapOhosView;

  aboutToDisappear(): void {
    this.mapView.detachMap();
  }

  build() {
    Column() {
      MapComponent({
        mapOptions: this.mapView.getMapOptions(),
        mapCallback: this.mapView.getMapReadyCallback(),
      })
        .width('100%')
        .height('100%');
    }
      .width('100%')
      .height('100%');
  }
}

@Builder
function HmsMapComponentBuilder(params: Params) {
  HmsMapNativeView({ params: params });
}

class MapAppStateCallback extends ApplicationStateChangeCallback {
  private readonly owner: HmsMapOhosView;

  constructor(owner: HmsMapOhosView) {
    super();
    this.owner = owner;
  }

  onApplicationForeground(): void {
    this.owner.showMap();
  }

  onApplicationBackground(): void {
    this.owner.hideMap();
  }
}

