import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart' show serve;
import 'package:mcp_dart/mcp_dart.dart' as mcp;
import 'package:test/test.dart';
import 'package:todo_agent_app/adapters/http/http_api.dart';
import 'package:todo_agent_app/adapters/mcp/mcp_bridge.dart';
import 'package:todo_agent_app/application/task_service.dart';
import 'package:todo_agent_app/infrastructure/sqlite_task_repository.dart';
import 'package:todo_agent_app/runtime/daemon.dart';

void main() {
  test('real MCP SDK client uses the same authenticated task application', () async {
    final directory = await Directory.systemTemp.createTemp('todo-mcp-test-');
    final web = Directory('${directory.path}/web')..createSync();
    File('${web.path}/index.html').writeAsStringSync('<html>app</html>');
    final repository = SqliteTaskRepository.open('${directory.path}/tasks.sqlite3');
    final tasks = TaskService(repository);
    final api = HttpApi(tasks: tasks, token: 'sdk-test-token', webDirectory: web);
    final http = await serve(api.handler, '127.0.0.1', 0);
    api.port = http.port;
    await File('${directory.path}/daemon.json').writeAsString(
      jsonEncode({'port': http.port, 'token': 'sdk-test-token', 'pid': pid, 'version': '0.1.0'}),
    );
    final manager = DaemonManager(dataPath: directory.path, webPath: web.path);

    final clientToServer = StreamController<List<int>>();
    final serverToClient = StreamController<List<int>>();
    final serverTransport = mcp.IOStreamTransport(
      stream: clientToServer.stream,
      sink: serverToClient.sink,
    );
    final clientTransport = mcp.IOStreamTransport(
      stream: serverToClient.stream,
      sink: clientToServer.sink,
    );
    final server = createMcpServer(manager);
    final client = mcp.McpClient(const mcp.Implementation(name: 'test-client', version: '1.0.0'));

    try {
      await server.connect(serverTransport);
      await client.connect(clientTransport);

      final opened = await client.callTool(const mcp.CallToolRequest(name: 'app_open'));
      expect(opened.isError, isFalse);
      expect(opened.structuredContent!['url'], contains('#token='));

      final created = await client.callTool(
        const mcp.CallToolRequest(name: 'tasks_create', arguments: {'title': 'SDK task'}),
      );
      expect(created.isError, isFalse);
      final task = created.structuredContent!;
      expect(task['title'], 'SDK task');

      final listed = await client.callTool(const mcp.CallToolRequest(name: 'tasks_list'));
      expect(listed.structuredContent!['revision'], 1);
      expect((listed.structuredContent!['tasks'] as List).single['id'], task['id']);

      final updated = await client.callTool(
        mcp.CallToolRequest(
          name: 'tasks_update',
          arguments: {'id': task['id'], 'completed': true, 'expectedRevision': task['revision']},
        ),
      );
      expect(updated.structuredContent!['completed'], isTrue);

      final deleted = await client.callTool(
        mcp.CallToolRequest(
          name: 'tasks_delete',
          arguments: {'id': task['id'], 'expectedRevision': updated.structuredContent!['revision']},
        ),
      );
      expect(deleted.isError, isFalse);
      expect(deleted.structuredContent, isEmpty);
    } finally {
      await client.close();
      await server.close();
      await clientToServer.close();
      await serverToClient.close();
      await http.close(force: true);
      await tasks.close();
      repository.close();
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(seconds: 20)));
}
