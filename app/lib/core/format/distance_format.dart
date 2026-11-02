/// Short distance labels (T22 §9.3); T25 reuses them for chips and summaries.
library;

import 'package:intl/intl.dart';

/// Below 1000 m: "850 m". Otherwise km with at most one decimal and the
/// locale decimal separator: 1000 -> "1 km", 1500 -> "1,5 km" (vi) /
/// "1.5 km" (en). Tenths are rounded: 1250 -> "1,3 km".
String formatDistanceShort(int meters, String locale) {
  if (meters < 1000) {
    return '$meters m';
  }
  final tenths = (meters / 100).round();
  final format = NumberFormat('#,##0.#', locale);
  return '${format.format(tenths / 10)} km';
}
