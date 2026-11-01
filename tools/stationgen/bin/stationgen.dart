import 'dart:io';

import 'package:stationgen/stationgen.dart';

Future<void> main(List<String> args) async {
  exitCode = await runCli(args, out: stdout, err: stderr);
}
