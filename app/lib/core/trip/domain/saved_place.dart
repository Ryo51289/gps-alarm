/// Saved places of screen 1 (T22 §6.3).
library;

import 'package:meta/meta.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';

/// The three fixed slots, in display order.
enum SavedPlaceSlot { home, hometown, work }

/// A destination saved in a slot.
///
/// PRIVACY: [toString] never prints the name or the coordinates.
@immutable
final class SavedPlace {
  const new({
    required this.slot,
    required this.destination,
    required this.updatedAtMs,
  });

  final SavedPlaceSlot slot;
  final TripDestination destination;

  /// Epoch ms UTC of the last change.
  final int updatedAtMs;

  @override
  bool operator ==(Object other) =>
      other is SavedPlace &&
      other.slot == slot &&
      other.destination == destination &&
      other.updatedAtMs == updatedAtMs;

  @override
  int get hashCode => Object.hash(slot, destination, updatedAtMs);

  @override
  String toString() => 'SavedPlace(${slot.name}, $destination)';
}
