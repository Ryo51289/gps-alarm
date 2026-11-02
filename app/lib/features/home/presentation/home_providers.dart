import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/device/device_providers.dart';
import 'package:napstop/core/trip/domain/saved_place.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';
import 'package:napstop/core/trip/trip_providers.dart';
import 'package:napstop/features/home/domain/readiness.dart';

final savedPlacesProvider = StreamProvider<Map<SavedPlaceSlot, SavedPlace>>(
  (ref) => ref.watch(savedPlacesRepositoryProvider).watchAll(),
);

final recentTripsProvider = StreamProvider<List<TripRecord>>(
  (ref) => ref.watch(tripsRepositoryProvider).watchRecentDestinations(),
);

/// The "Sẵn sàng" card. Re-read on resume and after returning from screens
/// 0 and 9 (the screen invalidates it). A failing `deviceStatus()` only
/// drops the battery/volume/DND chips; a failing `permissionStatus()` or
/// `deviceInfo()` puts the card in its error state.
final FutureProvider<Readiness> readinessProvider =
    FutureProvider.autoDispose<Readiness>((ref) async {
      final bridge = ref.watch(coreBridgeProvider);
      final results = await Future.wait<Object?>([
        bridge.permissionStatus(),
        bridge.deviceStatus().then<DeviceStatusMsg?>(
          (s) => s,
          onError: (Object _) => null,
        ),
        ref.watch(deviceInfoProvider.future),
      ]);
      return evaluateReadiness(
        permissions: results[0]! as PermissionStatusMsg,
        status: results[1] as DeviceStatusMsg?,
        device: results[2]! as DeviceInfoMsg,
      );
    });
