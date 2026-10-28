import 'dart:io';

import 'package:tracegen/tracegen.dart';

Future<void> main(List<String> args) async {
  exitCode = await runCli(args, out: stdout, err: stderr);
}
