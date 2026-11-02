import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Current time. Tests override it with a fixed time.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
