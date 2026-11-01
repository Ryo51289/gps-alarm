import 'package:flutter/widgets.dart';
import 'package:napstop/app/app.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/core/design/fonts/font_licenses.dart';
import 'package:napstop/features/destination/data/station_license.dart';

void main() {
  registerStationDataLicense();
  registerFontLicenses();
  runApp(NapStopApp(flavor: AppFlavor.current));
}
