import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

import '../../application/task_service.dart';
import '../../domain/app_error.dart';
import '../../domain/task.dart';

const appIdentity = 'todo-agent-app';
const appVersion = '0.1.1';

/// Builds the Dart Frog handler for the app's authenticated local API and web UI.
class HttpApi {
  HttpApi({required this.tasks, required this.token, this.port = 0, required this.webDirectory});

  final TaskService tasks;
  final String token;
  int port;
  final Directory webDirectory;

  Handler get handler => (context) async {
    final request = context.request;
    final path = _normalizedPath(request.url.path);
    if (!_allowedHost(request.headers['host'])) {
      return _error(403, 'forbidden', 'Unexpected Host');
    }
    final origin = request.headers['origin'];
    if (origin != null && origin != 'http://127.0.0.1:$port') {
      return _error(403, 'forbidden', 'Unexpected Origin');
    }
    if (path == 'health' && request.method == HttpMethod.get) {
      return Response.json(body: {'app': appIdentity, 'version': appVersion});
    }
    if (path.startsWith('api/') || path == 'api') {
      if (request.headers['authorization'] != 'Bearer $token') {
        return _error(401, 'unauthorized', 'Valid bearer token required');
      }
      return _api(context, path);
    }
    return _static(path);
  };

  String _normalizedPath(String path) => path.startsWith('/') ? path.substring(1) : path;

  bool _allowedHost(String? host) => host == '127.0.0.1:$port' || host == 'localhost:$port';

  Future<Response> _api(RequestContext context, String path) async {
    final request = context.request;
    try {
      if (path == 'api/tasks' && request.method == HttpMethod.get) {
        return Response.json(body: tasks.list().toJson());
      }
      if (path == 'api/tasks' && request.method == HttpMethod.post) {
        final body = await _jsonObject(request);
        final title = body['title'];
        if (title is! String) throw AppError.invalidInput('title must be a string');
        final task = await tasks.create(title);
        return Response.json(statusCode: 201, body: task.toJson());
      }
      if (path == 'api/events' && request.method == HttpMethod.get) {
        return _events();
      }
      final taskMatch = RegExp(r'^api/tasks/([^/]+)$').firstMatch(path);
      if (taskMatch != null && request.method == HttpMethod.patch) {
        final body = await _jsonObject(request);
        final expectedRevision = body['expectedRevision'];
        if (expectedRevision is! int) {
          throw AppError.invalidInput('expectedRevision must be an integer');
        }
        final title = body['title'];
        final completed = body['completed'];
        if (title != null && title is! String) {
          throw AppError.invalidInput('title must be a string');
        }
        if (completed != null && completed is! bool) {
          throw AppError.invalidInput('completed must be a boolean');
        }
        final task = await tasks.update(
          Uri.decodeComponent(taskMatch.group(1)!),
          title: title as String?,
          completed: completed as bool?,
          expectedRevision: expectedRevision,
        );
        return Response.json(body: task.toJson());
      }
      if (taskMatch != null && request.method == HttpMethod.delete) {
        final body = await _jsonObject(request);
        final expectedRevision = body['expectedRevision'];
        if (expectedRevision is! int) {
          throw AppError.invalidInput('expectedRevision must be an integer');
        }
        await tasks.delete(
          Uri.decodeComponent(taskMatch.group(1)!),
          expectedRevision: expectedRevision,
        );
        return Response(statusCode: 204);
      }
      return _error(404, 'notFound', 'Route not found');
    } on AppError catch (error) {
      final status = switch (error.code) {
        'invalidInput' => 400,
        'notFound' => 404,
        'conflict' => 409,
        _ => 500,
      };
      return _error(status, error.code, error.message);
    } on FormatException {
      return _error(400, 'invalidInput', 'Request body must be a JSON object');
    }
  }

  Future<Map<String, Object?>> _jsonObject(Request request) async {
    final decoded = jsonDecode(await request.body());
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('JSON object required');
    }
    return decoded;
  }

  Response _events() {
    late StreamController<List<int>> controller;
    StreamSubscription<TaskSnapshot>? subscription;
    Timer? heartbeat;
    var closed = false;
    void send(TaskSnapshot snapshot) {
      if (closed) return;
      final bytes = utf8.encode('event: snapshot\ndata: ${jsonEncode(snapshot.toJson())}\n\n');
      controller.add(bytes);
    }

    controller = StreamController<List<int>>(
      onListen: () {
        // Subscribe before reading the initial view. Any race is represented by
        // a later complete snapshot, and clients discard older revisions.
        subscription = tasks.snapshots.listen(send);
        send(tasks.list());
        heartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
          if (!closed) controller.add(utf8.encode(': heartbeat\n\n'));
        });
      },
      onCancel: () async {
        closed = true;
        heartbeat?.cancel();
        await subscription?.cancel();
      },
    );
    return Response.stream(
      body: controller.stream,
      bufferOutput: false,
      headers: const {
        'content-type': 'text/event-stream; charset=utf-8',
        'cache-control': 'no-cache, no-transform',
        'connection': 'keep-alive',
        'x-accel-buffering': 'no',
      },
    );
  }

  Future<Response> _static(String requestPath) async {
    final relative = requestPath.isEmpty ? 'index.html' : requestPath;
    final decoded = Uri.decodeComponent(relative);
    final segments = decoded.split('/');
    if (segments.any((segment) => segment == '..' || segment.isEmpty)) {
      return _error(404, 'notFound', 'File not found');
    }
    final root = await webDirectory.resolveSymbolicLinks();
    var file = File('$root${Platform.pathSeparator}${segments.join(Platform.pathSeparator)}');
    if (await file.exists() &&
        (await FileSystemEntity.type(file.path, followLinks: true)) ==
            FileSystemEntityType.directory) {
      file = File('${file.path}${Platform.pathSeparator}index.html');
    }
    if (!await file.exists()) {
      return _error(404, 'notFound', 'File not found');
    }
    final resolved = await file.resolveSymbolicLinks();
    if (!resolved.startsWith('$root${Platform.pathSeparator}')) {
      return _error(404, 'notFound', 'File not found');
    }
    final extension = file.path.split('.').last.toLowerCase();
    final type = switch (extension) {
      'html' => 'text/html; charset=utf-8',
      'js' => 'text/javascript; charset=utf-8',
      'css' => 'text/css; charset=utf-8',
      'svg' => 'image/svg+xml',
      'png' => 'image/png',
      'ico' => 'image/x-icon',
      'json' => 'application/json',
      'woff' => 'font/woff',
      'woff2' => 'font/woff2',
      _ => 'application/octet-stream',
    };
    return Response.bytes(body: await file.readAsBytes(), headers: {'content-type': type});
  }

  Response _error(int status, String code, String message) => Response.json(
    statusCode: status,
    body: {
      'error': {'code': code, 'message': message},
    },
  );
}
