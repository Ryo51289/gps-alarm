import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/app/clock.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';
import 'package:napstop/core/trip/trip_providers.dart';
import 'package:napstop/features/history/domain/history_logic.dart';

/// Rows of screen 11, newest first (simulated included).
final StreamProvider<List<TripRecord>> historyProvider =
    StreamProvider.autoDispose<List<TripRecord>>(
      (ref) => ref.watch(tripsRepositoryProvider).watchHistory(),
    );

/// "Tháng này" card. The month is taken when the provider is built; a month
/// change while the screen stays open shows at the next rebuild (accepted).
final StreamProvider<HistoryStats> monthStatsProvider =
    StreamProvider.autoDispose<HistoryStats>((ref) {
      final now = ref.watch(clockProvider)();
      return ref
          .watch(tripsRepositoryProvider)
          .watchRealTripsSince(monthStartMs(now))
          .map(monthStats);
    });
