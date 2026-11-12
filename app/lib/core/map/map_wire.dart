/// Wire format v1 of the MapKit platform view (T23.3 §2): creation params,
/// Dart → native calls and native → Dart events on the per-view channel
/// `app.napstop/nap_map/<viewId>` (`StandardMessageCodec`, no Pigeon: T14 D5).
/// The Swift side parses the same format (`MapWire.swift`); both are checked
/// against `fixtures/map_wire/cases.json`.
///
/// PRIVACY: nothing here logs, and no `toString` prints coordinates.
library;

import 'package:meta/meta.dart';
import 'package:napstop/core/map/map_point.dart';

export 'package:napstop/core/map/map_point.dart';

const String kNapMapViewType = 'app.napstop/nap_map';

String napMapChannelName(int viewId) => '$kNapMapViewType/$viewId';

const int kNapMapWireVersion = 1;

/// Largest zone radius on the wire, metres (§2: `(0, 100000]`).
const double kMaxWireRadiusM = 100000;

/// Largest padding of one edge on the wire, points (§2: `[0, 4000]`).
const double kMaxWirePaddingPt = 4000;

/// Edge insets of a camera frame, points.
typedef MapPadding = ({double top, double left, double bottom, double right});

const MapPadding kNoMapPadding = (top: 0, left: 0, bottom: 0, right: 0);

/// §2: finite, lat in [-90, 90], lng in [-180, 180].
bool isValidLatLng(double lat, double lng) =>
    lat.isFinite &&
    lng.isFinite &&
    lat >= -90 &&
    lat <= 90 &&
    lng >= -180 &&
    lng <= 180;

List<double> pointToWire(MapPoint p) => [p.lat, p.lng];

/// `[lat, lng]` with valid numbers, else null (never throws).
MapPoint? decodePoint(Object? args) {
  if (args is! List || args.length != 2) {
    return null;
  }
  final lat = args[0];
  final lng = args[1];
  if (lat is! num || lng is! num) {
    return null;
  }
  final la = lat.toDouble();
  final ln = lng.toDouble();
  return isValidLatLng(la, ln) ? MapPoint(la, ln) : null;
}

/// A lat/lng box, `south <= north`, `west <= east` (no antimeridian).
@immutable
final class MapBounds {
  const new({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;

  bool contains(MapPoint p) =>
      p.lat >= south && p.lat <= north && p.lng >= west && p.lng <= east;

  /// Whether the two boxes share at least one point.
  bool intersects(MapBounds o) =>
      o.south <= north && o.north >= south && o.west <= east && o.east >= west;

  Map<String, Object?> toWire() => {
    's': south,
    'w': west,
    'n': north,
    'e': east,
  };

  @override
  bool operator ==(Object other) =>
      other is MapBounds &&
      other.south == south &&
      other.west == west &&
      other.north == north &&
      other.east == east;

  @override
  int get hashCode => Object.hash(south, west, north, east);

  /// PRIVACY: no coordinates.
  @override
  String toString() => 'MapBounds';
}

/// Symbol drawn inside the pin (T24.3 §6.6, optional `glyph` key of
/// `<State>`).
enum MapPinGlyph {
  /// A roadside bus stop (SF Symbol `bus.fill` on iOS).
  bus;

  /// The wire value: null, absent or unknown → null (old behaviour).
  static MapPinGlyph? fromWire(Object? v) {
    for (final g in values) {
      if (g.name == v) {
        return g;
      }
    }
    return null;
  }
}

/// What the native map shows (§2 `<State>`). Never moves the camera.
@immutable
final class NapMapState {
  const new({
    this.pin,
    this.radiusM,
    this.pinDraggable = false,
    this.longPress = false,
    this.showsUser = false,
    this.dark = false,
    this.glyph,
  });

  final MapPoint? pin;

  /// Alarm zone around [pin]; null = no circle.
  final double? radiusM;
  final bool pinDraggable;
  final bool longPress;

  /// MapKit's own location dot (screen 4 only, D17).
  final bool showsUser;

  /// App appearance (D13), not the system one.
  final bool dark;

  /// Symbol inside the pin (T24.3); null = the plain pin. Only sent when
  /// set, so older native code keeps working.
  final MapPinGlyph? glyph;

  NapMapState copyWith({bool? showsUser}) => NapMapState(
    pin: pin,
    radiusM: radiusM,
    pinDraggable: pinDraggable,
    longPress: longPress,
    showsUser: showsUser ?? this.showsUser,
    dark: dark,
    glyph: glyph,
  );

  Map<String, Object?> toWire() {
    final p = pin;
    return {
      'pin': p == null ? null : pointToWire(p),
      'radiusM': radiusM,
      'pinDraggable': pinDraggable,
      'longPress': longPress,
      'showsUser': showsUser,
      'dark': dark,
      if (glyph != null) 'glyph': glyph!.name,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is NapMapState &&
      other.pin == pin &&
      other.radiusM == radiusM &&
      other.pinDraggable == pinDraggable &&
      other.longPress == longPress &&
      other.showsUser == showsUser &&
      other.dark == dark &&
      other.glyph == glyph;

  @override
  int get hashCode => Object.hash(
    pin,
    radiusM,
    pinDraggable,
    longPress,
    showsUser,
    dark,
    glyph,
  );

  /// PRIVACY: no coordinates.
  @override
  String toString() =>
      'NapMapState(pin: ${pin == null ? 'none' : 'set'}, '
      'circle: ${radiusM == null ? 'none' : 'set'}, '
      'draggable: $pinDraggable, longPress: $longPress, '
      'showsUser: $showsUser, dark: $dark, glyph: ${glyph?.name})';
}

/// A camera move (§2 `frame`).
@immutable
final class NapMapFrame {
  const new({
    required this.bounds,
    required this.padding,
    this.animated = true,
    this.includeUser = false,
  });

  final MapBounds bounds;
  final MapPadding padding;
  final bool animated;

  /// Also frame MapKit's user location when it has one (screen 4 "Vị trí
  /// của tôi"); the position never reaches Dart.
  final bool includeUser;

  Map<String, Object?> toWire() => {
    'bounds': bounds.toWire(),
    'pad': [padding.top, padding.left, padding.bottom, padding.right],
    'animated': animated,
    'includeUser': includeUser,
  };

  @override
  bool operator ==(Object other) =>
      other is NapMapFrame &&
      other.bounds == bounds &&
      other.padding == padding &&
      other.animated == animated &&
      other.includeUser == includeUser;

  @override
  int get hashCode => Object.hash(bounds, padding, animated, includeUser);

  /// PRIVACY: no coordinates.
  @override
  String toString() =>
      'NapMapFrame(animated: $animated, includeUser: $includeUser)';
}

/// Native → Dart events (§2).
sealed class NapMapEvent {
  const new();
}

/// The map finished loading once, or 3 s passed since creation.
final class NapMapReady extends NapMapEvent {
  const new();
}

/// Long press on the map, outside the pin (D8).
final class NapMapLongPress extends NapMapEvent {
  const new(this.at);

  final MapPoint at;

  @override
  String toString() => 'NapMapLongPress';
}

/// The pin was dragged and dropped (D6); Dart decides what it means.
final class NapMapPinDragEnd extends NapMapEvent {
  const new(this.at);

  final MapPoint at;

  @override
  String toString() => 'NapMapPinDragEnd';
}

/// MapKit could not load map data (D15).
final class NapMapLoadFailed extends NapMapEvent {
  const new();
}

/// null when [method] is unknown or [args] invalid (§2 rules).
NapMapEvent? decodeNapMapEvent(String method, Object? args) {
  switch (method) {
    case 'ready':
      return args == null ? const NapMapReady() : null;
    case 'loadFailed':
      return args == null ? const NapMapLoadFailed() : null;
    case 'longPress':
      final p = decodePoint(args);
      return p == null ? null : NapMapLongPress(p);
    case 'pinDragEnd':
      final p = decodePoint(args);
      return p == null ? null : NapMapPinDragEnd(p);
    default:
      return null;
  }
}

/// `creationParams` of the platform view (§2). [eastLimit] and [maxLngSpan]
/// switch on the D11 layers 2 and 1 (null = off).
Map<String, Object?> creationParams({
  required NapMapState state,
  required MapBounds initial,
  required int accentArgb,
  required String pinLabel,
  MapBounds? centerBounds,
  double? maxDistanceM,
  double? eastLimit,
  double? maxLngSpan,
}) => {
  'v': kNapMapWireVersion,
  'state': state.toWire(),
  'initial': initial.toWire(),
  'centerBounds': centerBounds?.toWire(),
  'maxDistanceM': maxDistanceM,
  'eastLimit': eastLimit,
  'maxLngSpan': maxLngSpan,
  'accent': accentArgb,
  'pinLabel': pinLabel,
};
