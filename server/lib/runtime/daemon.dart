import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dart_frog/dart_frog.dart' show serve;
import 'package:path/path.dart' as p;

import '../adapters/http/http_api.dart';
import '../application/task_service.dart';
import '../infrastructure/sqlite_task_repository.dart';

/// Paths and lifecycle operations for one local daemon profile.
class DaemonManager {
  DaemonManager({String? dataPath, String? webPath})
    : dataDirectory = Directory(dataPath ?? _defaultDataPath()),
      webDirectory = Directory(
        webPath ?? p.join(p.dirname(p.dirname(Platform.resolvedExecutable)), 'web'),
      );

  final Directory dataDirectory;
  final Directory webDirectory;

  File get _descriptorFile => File(p.join(dataDirectory.path, 'daemon.json'));
  File get _lockFile => File(p.join(dataDirectory.path, 'daemon.lock'));
  String get _databasePath => p.join(dataDirectory.path, 'tasks.sqlite3');

  Future<DaemonDescriptor> ensureRunning() async {
    await _prepareDataDirectory();
    final existing = await _readDescriptor();
    if (existing != null && await _probe(existing)) return existing;

    final args = <String>['serve', '--data', dataDirectory.path, '--web', webDirectory.path];
    final script = Platform.script;
    final executableArgs = script.scheme == 'file' && script.path.endsWith('.dart')
        ? <String>[script.toFilePath(), ...args]
        : args;
    final process = await Process.start(
      Platform.resolvedExecutable,
      executableArgs,
      mode: ProcessStartMode.detached,
      workingDirectory: Directory.current.path,
    );
    // Detached children have no attached standard streams. Their diagnostics
    // stay outside MCP stdout and live in the child process's default sink.
    for (var attempt = 0; attempt < 100; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final descriptor = await _readDescriptor();
      if (descriptor != null && await _probe(descriptor)) {
        if (process.pid != descriptor.pid) {
          Process.killPid(process.pid, ProcessSignal.sigterm);
        }
        return descriptor;
      }
    }
    throw StateError('The local daemon did not become ready');
  }

  Future<void> serveDaemon() async {
    await _prepareDataDirectory();
    final lock = await _acquireOwnerLock();
    final token = _createToken();
    final repository = SqliteTaskRepository.open(_databasePath);
    final tasks = TaskService(repository);
    final lifetime = Completer<void>();
    HttpServer? server;
    DaemonDescriptor? descriptor;
    var stopping = false;

    Future<void> stop() async {
      if (stopping) return;
      stopping = true;
      await server?.close(force: true);
      await tasks.close();
      repository.close();
      if (descriptor != null) {
        final current = await _readDescriptor();
        if (current?.pid == pid) {
          try {
            await _descriptorFile.delete();
          } on FileSystemException {
            // Another shutdown path already removed it.
          }
        }
      }
      await lock.close();
      if (!lifetime.isCompleted) lifetime.complete();
    }

    try {
      if (!await webDirectory.exists()) {
        throw FileSystemException('Web assets directory does not exist', webDirectory.path);
      }
      final api = HttpApi(tasks: tasks, token: token, webDirectory: webDirectory);
      server = await serve(api.handler, InternetAddress.loopbackIPv4, 0);
      api.port = server.port;
      descriptor = DaemonDescriptor(port: server.port, token: token, pid: pid, version: appVersion);
      await _writeDescriptor(descriptor);

      final signals = <StreamSubscription<ProcessSignal>>[
        ProcessSignal.sigint.watch().listen((_) => unawaited(stop())),
      ];
      if (!Platform.isWindows) {
        signals.add(ProcessSignal.sigterm.watch().listen((_) => unawaited(stop())));
      }
      await lifetime.future;
      for (final signal in signals) {
        await signal.cancel();
      }
      await stop();
    } finally {
      await stop();
    }
  }

  Future<bool> stopDaemon() async {
    final descriptor = await _readDescriptor();
    if (descriptor == null || !await _probe(descriptor)) return false;
    if (!Process.killPid(descriptor.pid, ProcessSignal.sigterm)) return false;
    for (var attempt = 0; attempt < 60; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (await _readDescriptor() == null) return true;
    }
    return false;
  }

  Uri bootstrapUri(DaemonDescriptor descriptor) => Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: descriptor.port,
    fragment: 'token=${Uri.encodeComponent(descriptor.token)}',
  );

  Future<bool> _probe(DaemonDescriptor descriptor) async {
    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 400);
    try {
      final request = await client.getUrl(
        Uri(scheme: 'http', host: '127.0.0.1', port: descriptor.port, path: '/api/tasks'),
      );
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${descriptor.token}');
      final response = await request.close().timeout(const Duration(milliseconds: 700));
      await response.drain<void>();
      return response.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<DaemonDescriptor?> _readDescriptor() async {
    try {
      final json = jsonDecode(await _descriptorFile.readAsString());
      if (json is! Map<String, dynamic>) return null;
      return DaemonDescriptor.fromJson(json);
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<void> _writeDescriptor(DaemonDescriptor descriptor) async {
    final temporary = File('${_descriptorFile.path}.tmp');
    await temporary.writeAsString(jsonEncode(descriptor.toJson()), flush: true);
    await _setOwnerOnly(temporary.path, directory: false);
    await temporary.rename(_descriptorFile.path);
  }

  Future<RandomAccessFile> _acquireOwnerLock() async {
    if (!await _lockFile.exists()) await _lockFile.create();
    await _setOwnerOnly(_lockFile.path, directory: false);
    final handle = await _lockFile.open(mode: FileMode.append);
    await handle.lock(FileLock.exclusive);
    final existing = await _readDescriptor();
    if (existing != null && await _probe(existing)) {
      await handle.close();
      throw StateError('A daemon already owns this data directory');
    }
    if (await _descriptorFile.exists()) {
      await _descriptorFile.delete();
    }
    return handle;
  }

  Future<void> _prepareDataDirectory() async {
    await dataDirectory.create(recursive: true);
    await _setOwnerOnly(dataDirectory.path, directory: true);
  }

  Future<void> _setOwnerOnly(String path, {required bool directory}) async {
    if (Platform.isWindows) return;
    await Process.run('chmod', [directory ? '700' : '600', path]);
  }

  static String _defaultDataPath() {
    final env = Platform.environment;
    final override = env['TODO_AGENT_APP_DATA'];
    if (override != null && override.isNotEmpty) return override;
    if (Platform.isMacOS) {
      return p.join(env['HOME']!, 'Library', 'Application Support', 'todo-agent-app');
    }
    return p.join(
      env['XDG_DATA_HOME'] ?? p.join(env['HOME']!, '.local', 'share'),
      'todo-agent-app',
    );
  }

  String _createToken() {
    final random = Random.secure();
    return base64Url.encode(List<int>.generate(32, (_) => random.nextInt(256))).replaceAll('=', '');
  }
}

class DaemonDescriptor {
  const DaemonDescriptor({
    required this.port,
    required this.token,
    required this.pid,
    required this.version,
  });

  final int port;
  final String token;
  final int pid;
  final String version;

  Map<String, Object> toJson() => {'port': port, 'token': token, 'pid': pid, 'version': version};

  factory DaemonDescriptor.fromJson(Map<String, dynamic> json) => DaemonDescriptor(
    port: json['port'] as int,
    token: json['token'] as String,
    pid: json['pid'] as int,
    version: json['version'] as String,
  );
}
