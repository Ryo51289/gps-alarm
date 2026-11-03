import 'package:flutter/material.dart';

/// Semantic icon names (spec T20 section 3.4). Material Icons from the SDK.
///
/// Screens use these constants, never `Icons.*` directly, so the icon set
/// can change in one place. Features may add constants here.
abstract final class NapIcons {
  static const IconData back = Icons.chevron_left;
  static const IconData chevron = Icons.chevron_right;
  static const IconData settings = Icons.settings_outlined;
  static const IconData search = Icons.search;
  static const IconData home = Icons.home_outlined;
  static const IconData place = Icons.place_outlined;
  static const IconData work = Icons.work_outline;
  static const IconData train = Icons.train_outlined;
  static const IconData coach = Icons.directions_bus_outlined;
  static const IconData bus = Icons.directions_bus_filled_outlined;
  static const IconData check = Icons.check;
  static const IconData info = Icons.info_outline;
  static const IconData warning = Icons.warning_amber_rounded;
  static const IconData error = Icons.error_outline;
  static const IconData gps = Icons.gps_fixed;
  static const IconData gpsOff = Icons.gps_off;
  static const IconData battery = Icons.battery_std_outlined;
  static const IconData batteryLow = Icons.battery_alert_outlined;
  static const IconData headphones = Icons.headphones_outlined;
  static const IconData alarm = Icons.notifications_outlined;
  static const IconData vibrate = Icons.vibration;
  static const IconData play = Icons.play_arrow_rounded;
  static const IconData bookmark = Icons.bookmark_border;
  static const IconData sleep = Icons.bedtime_outlined;
  static const IconData redo = Icons.replay;
  static const IconData snooze = Icons.snooze;
  static const IconData history = Icons.route_outlined;
  static const IconData smart = Icons.auto_awesome_outlined;
  static const IconData add = Icons.add;
  static const IconData clear = Icons.close;
  // T21: screens 0 and 9.
  static const IconData fullScreen = Icons.fullscreen;
  static const IconData alarmClock = Icons.alarm;
  static const IconData timer = Icons.timer_outlined;
}
