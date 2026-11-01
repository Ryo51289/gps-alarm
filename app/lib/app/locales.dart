import 'package:flutter/widgets.dart';

/// Supported locales, Vietnamese first: when the device language is neither
/// vi nor en, Flutter's basic locale resolution falls back to the first entry
/// (spec T20 section 4.3, Q3).
const List<Locale> kAppSupportedLocales = [Locale('vi'), Locale('en')];
