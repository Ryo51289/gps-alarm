import 'package:flutter/widgets.dart';
import 'package:napstop/app/app.dart';
import 'package:napstop/app/flavor.dart';

void main() {
  runApp(NapStopApp(flavor: AppFlavor.current));
}
