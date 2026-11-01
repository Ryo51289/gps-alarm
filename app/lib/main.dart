import 'package:flutter/widgets.dart';
import 'package:napstop/app/app.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/features/destination/data/station_license.dart';

void main() {
  registerStationDataLicense();
  runApp(NapStopApp(flavor: AppFlavor.current));
}
