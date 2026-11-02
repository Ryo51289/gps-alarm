import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/core/bridge/core_bridge.dart';

/// The one [CoreBridge] of the app (T14 §8). Widget tests override it with
/// `FakeCoreBridge` (test/helpers/fake_core_bridge.dart).
final coreBridgeProvider = Provider<CoreBridge>((ref) => CoreBridge());
