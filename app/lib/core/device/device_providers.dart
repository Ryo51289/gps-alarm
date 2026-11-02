import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';

/// Platform, OS version and model; read once and kept for the session (it
/// does not change while the app runs).
final deviceInfoProvider = FutureProvider<DeviceInfoMsg>(
  (ref) => ref.watch(coreBridgeProvider).deviceInfo(),
);
