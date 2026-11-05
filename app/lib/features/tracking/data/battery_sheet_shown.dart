import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Trips whose screen 7 sheet already opened by itself in this process
/// (T26 D10): it opens once per trip; afterwards only the banner remains.
final batterySheetShownProvider =
    NotifierProvider<BatterySheetShown, Set<String>>(BatterySheetShown.new);

class BatterySheetShown extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  /// Marks [tripId]; false when it was already marked.
  bool markShown(String tripId) {
    if (state.contains(tripId)) {
      return false;
    }
    state = {...state, tripId};
    return true;
  }
}
