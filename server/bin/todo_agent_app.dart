import 'dart:io';

import 'package:todo_agent_app/cli.dart';

Future<void> main(List<String> args) async {
  exitCode = await runCli(args);
}
