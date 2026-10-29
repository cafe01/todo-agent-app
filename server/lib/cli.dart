import 'dart:io';

import 'package:args/args.dart';

import 'adapters/mcp/mcp_bridge.dart';
import 'runtime/daemon.dart';

/// Dispatches the app's small command line interface.
Future<int> runCli(List<String> args) async {
  final parser = ArgParser(allowTrailingOptions: true)
    ..addOption('data', help: 'Override the local data directory.')
    ..addOption('web', help: 'Override the compiled web assets directory.')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show command usage.');
  ArgResults parsed;
  try {
    parsed = parser.parse(args);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    _usage(toStderr: true);
    return 64;
  }
  if (parsed.flag('help') || parsed.rest.isEmpty) {
    _usage();
    return 0;
  }
  if (parsed.rest.length != 1 ||
      !const {'serve', 'mcp', 'url', 'stop'}.contains(parsed.rest.first)) {
    stderr.writeln('Expected one of: serve, mcp, url, stop');
    _usage(toStderr: true);
    return 64;
  }

  final manager = DaemonManager(dataPath: parsed.option('data'), webPath: parsed.option('web'));
  try {
    switch (parsed.rest.single) {
      case 'serve':
        await manager.serveDaemon();
        return 0;
      case 'mcp':
        await runMcp(manager);
        return 0;
      case 'url':
        final descriptor = await manager.ensureRunning();
        stdout.writeln(manager.bootstrapUri(descriptor));
        return 0;
      case 'stop':
        final stopped = await manager.stopDaemon();
        if (!stopped) {
          stderr.writeln('No verified daemon is running for this data directory');
          return 1;
        }
        return 0;
    }
    throw StateError('Unreachable command state');
  } catch (error) {
    stderr.writeln(error);
    return 1;
  }
}

void _usage({bool toStderr = false}) {
  final output = toStderr ? stderr : stdout;
  output.writeln('''Usage: todo-agent-app <serve|mcp|url|stop> [--data PATH] [--web PATH]

Commands:
  serve  Run the local HTTP daemon
  mcp    Serve MCP tools over stdio and ensure the daemon is running
  url    Ensure the daemon is running and print its browser URL
  stop   Stop the verified daemon for this data directory''');
}
