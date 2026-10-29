import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart' show serve;
import 'package:test/test.dart';
import 'package:todo_agent_app/adapters/http/http_api.dart';
import 'package:todo_agent_app/application/task_service.dart';
import 'package:todo_agent_app/infrastructure/sqlite_task_repository.dart';

void main() {
  group('HTTP API', () {
    late Directory directory;
    late Directory webDirectory;
    late SqliteTaskRepository repository;
    late TaskService tasks;
    late HttpApi api;
    late HttpServer server;
    late HttpClient client;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('todo-http-test-');
      webDirectory = Directory('${directory.path}/web')..createSync();
      File('${webDirectory.path}/index.html').writeAsStringSync('<html>ready</html>');
      repository = SqliteTaskRepository.open('${directory.path}/tasks.sqlite3');
      tasks = TaskService(repository);
      api = HttpApi(tasks: tasks, token: 'test-secret', webDirectory: webDirectory);
      server = await serve(api.handler, '127.0.0.1', 0);
      api.port = server.port;
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await server.close(force: true);
      await tasks.close();
      repository.close();
      await directory.delete(recursive: true);
    });

    test('health is public and authenticated CRUD shares task state', () async {
      final health = await _request(client, server, 'GET', '/health');
      expect(health.statusCode, 200);
      expect(jsonDecode(health.body), {'app': 'todo-agent-app', 'version': appVersion});

      final unauthorized = await _request(client, server, 'GET', '/api/tasks');
      expect(unauthorized.statusCode, 401);
      expect(jsonDecode(unauthorized.body)['error']['code'], 'unauthorized');

      final created = await _request(
        client,
        server,
        'POST',
        '/api/tasks',
        body: {'title': '  Write tests  '},
        authenticated: true,
      );
      expect(created.statusCode, 201);
      final task = jsonDecode(created.body) as Map<String, dynamic>;
      expect(task['title'], 'Write tests');

      final updated = await _request(
        client,
        server,
        'PATCH',
        '/api/tasks/${task['id']}',
        body: {'completed': true, 'expectedRevision': task['revision']},
        authenticated: true,
      );
      expect(updated.statusCode, 200);
      expect(jsonDecode(updated.body)['completed'], isTrue);
      expect(
        (await _request(client, server, 'GET', '/api/tasks', authenticated: true)).body,
        contains('"completed":true'),
      );
    });

    test('SSE sends a complete initial snapshot and later committed snapshots', () async {
      await _request(
        client,
        server,
        'POST',
        '/api/tasks',
        body: {'title': 'First'},
        authenticated: true,
      );
      final request = await client.getUrl(Uri.parse('http://127.0.0.1:${server.port}/api/events'));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer test-secret');
      final response = await request.close();
      expect(response.statusCode, 200);
      final content = StringBuffer();
      final receivedSecondSnapshot = Completer<String>();
      final subscription = response.transform(utf8.decoder).listen((chunk) {
        content.write(chunk);
        if (content.toString().contains('"revision":2') && !receivedSecondSnapshot.isCompleted) {
          receivedSecondSnapshot.complete(content.toString());
        }
      });
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(content.toString(), contains('event: snapshot'));
      expect(content.toString(), contains('"revision":1'));
      await _request(
        client,
        server,
        'POST',
        '/api/tasks',
        body: {'title': 'Second'},
        authenticated: true,
      );
      final laterEvents = await receivedSecondSnapshot.future.timeout(const Duration(seconds: 2));
      expect(laterEvents, contains('event: snapshot'));
      await subscription.cancel();
    });

    test('rejects foreign origins and stale revisions with contract errors', () async {
      final foreign = await _request(
        client,
        server,
        'GET',
        '/api/tasks',
        authenticated: true,
        origin: 'http://example.com',
      );
      expect(foreign.statusCode, 403);

      final created = await _request(
        client,
        server,
        'POST',
        '/api/tasks',
        body: {'title': 'First'},
        authenticated: true,
      );
      final id = jsonDecode(created.body)['id'] as String;
      final stale = await _request(
        client,
        server,
        'PATCH',
        '/api/tasks/$id',
        body: {'completed': true, 'expectedRevision': 9},
        authenticated: true,
      );
      expect(stale.statusCode, 409);
      expect(jsonDecode(stale.body)['error']['code'], 'conflict');
    });
  });
}

Future<_HttpResult> _request(
  HttpClient client,
  HttpServer server,
  String method,
  String path, {
  Map<String, Object?>? body,
  bool authenticated = false,
  String? origin,
}) async {
  final request = await client.openUrl(method, Uri.parse('http://127.0.0.1:${server.port}$path'));
  if (authenticated) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer test-secret');
  }
  if (origin != null) request.headers.set('origin', origin);
  if (body != null) {
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
  }
  final response = await request.close();
  return _HttpResult(response.statusCode, await response.transform(utf8.decoder).join());
}

class _HttpResult {
  const _HttpResult(this.statusCode, this.body);
  final int statusCode;
  final String body;
}
