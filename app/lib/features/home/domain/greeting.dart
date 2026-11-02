/// Greeting of screen 1 by local time of day (T22 §9.1).
library;

enum Greeting { morning, noon, afternoon, evening }

/// 05:00-10:59 morning, 11:00-12:59 noon, 13:00-17:59 afternoon, otherwise
/// evening.
Greeting greetingFor(DateTime local) {
  final h = local.hour;
  if (h >= 5 && h < 11) {
    return Greeting.morning;
  }
  if (h >= 11 && h < 13) {
    return Greeting.noon;
  }
  if (h >= 13 && h < 18) {
    return Greeting.afternoon;
  }
  return Greeting.evening;
}
