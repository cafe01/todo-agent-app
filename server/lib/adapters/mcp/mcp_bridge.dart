import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart' as mcp;

import '../../runtime/daemon.dart';

/// Serves the app's MCP tools over stdio through the MCP SDK.
Future<void> runMcp(DaemonManager manager) async {
  final server = createMcpServer(manager);
  await server.connect(mcp.StdioServerTransport());
}

/// Creates the MCP server so SDK clients can exercise the tools in-process.
mcp.McpServer createMcpServer(DaemonManager manager) {
  final server = mcp.McpServer(
    const mcp.Implementation(name: 'todo-agent-app', version: '0.1.1'),
    options: const mcp.McpServerOptions(
      capabilities: mcp.ServerCapabilities(tools: mcp.ServerCapabilitiesTools()),
    ),
  );

  server.registerTool(
    'app_open',
    title: 'Open task app',
    description: 'Return the local task app URL for the current user.',
    inputSchema: mcp.JsonSchema.object(properties: const {}),
    annotations: const mcp.ToolAnnotations(readOnlyHint: true, openWorldHint: false),
    callback: (_, _) async {
      try {
        final descriptor = await manager.ensureRunning();
        final result = {'url': manager.bootstrapUri(descriptor).toString()};
        return _success(result);
      } catch (error) {
        return _failure('unavailable', error.toString());
      }
    },
  );

  server.registerTool(
    'tasks_list',
    title: 'List tasks',
    description: 'Return the current task snapshot.',
    inputSchema: mcp.JsonSchema.object(properties: const {}),
    annotations: const mcp.ToolAnnotations(readOnlyHint: true, openWorldHint: false),
    callback: (_, _) => _call(manager, 'GET', '/api/tasks'),
  );

  server.registerTool(
    'tasks_create',
    title: 'Create task',
    description: 'Create a task with a title.',
    inputSchema: mcp.JsonSchema.object(
      properties: {'title': mcp.JsonSchema.string(description: 'Task title, 1 to 200 characters.')},
      required: ['title'],
    ),
    annotations: const mcp.ToolAnnotations(
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false,
    ),
    callback: (args, _) => _call(manager, 'POST', '/api/tasks', body: {'title': args['title']}),
  );

  server.registerTool(
    'tasks_update',
    title: 'Update task',
    description: 'Update a task using its current revision.',
    inputSchema: mcp.JsonSchema.object(
      properties: {
        'id': mcp.JsonSchema.string(),
        'expectedRevision': mcp.JsonSchema.integer(),
        'title': mcp.JsonSchema.string(),
        'completed': mcp.JsonSchema.boolean(),
      },
      required: ['id', 'expectedRevision'],
    ),
    annotations: const mcp.ToolAnnotations(openWorldHint: false),
    callback: (args, _) {
      final body = <String, Object?>{'expectedRevision': args['expectedRevision']};
      if (args.containsKey('title')) body['title'] = args['title'];
      if (args.containsKey('completed')) body['completed'] = args['completed'];
      return _call(
        manager,
        'PATCH',
        '/api/tasks/${Uri.encodeComponent(args['id'] as String)}',
        body: body,
      );
    },
  );

  server.registerTool(
    'tasks_delete',
    title: 'Delete task',
    description: 'Delete a task using its current revision.',
    inputSchema: mcp.JsonSchema.object(
      properties: {'id': mcp.JsonSchema.string(), 'expectedRevision': mcp.JsonSchema.integer()},
      required: ['id', 'expectedRevision'],
    ),
    annotations: const mcp.ToolAnnotations(openWorldHint: false),
    callback: (args, _) => _call(
      manager,
      'DELETE',
      '/api/tasks/${Uri.encodeComponent(args['id'] as String)}',
      body: {'expectedRevision': args['expectedRevision']},
    ),
  );

  return server;
}

Future<mcp.CallToolResult> _call(
  DaemonManager manager,
  String method,
  String path, {
  Map<String, Object?>? body,
}) async {
  try {
    final descriptor = await manager.ensureRunning();
    final client = HttpClient();
    try {
      final request = await client.openUrl(
        method,
        Uri(scheme: 'http', host: '127.0.0.1', port: descriptor.port, path: path),
      );
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${descriptor.token}');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      final decoded = text.isEmpty ? <String, Object?>{} : jsonDecode(text);
      if (response.statusCode >= 400) {
        final error = (decoded as Map<String, dynamic>)['error'] as Map<String, dynamic>;
        return _failure(error['code'] as String, error['message'] as String);
      }
      final result = decoded is Map<String, Object?>
          ? decoded
          : <String, Object?>{'value': decoded};
      return _success(result);
    } finally {
      client.close(force: true);
    }
  } catch (error) {
    return _failure('unavailable', error.toString());
  }
}

mcp.CallToolResult _success(Map<String, Object?> result) => mcp.CallToolResult(
  content: [mcp.TextContent(text: jsonEncode(result))],
  structuredContent: result,
);

mcp.CallToolResult _failure(String code, String message) => mcp.CallToolResult(
  content: [
    mcp.TextContent(
      text: jsonEncode({
        'error': {'code': code, 'message': message},
      }),
    ),
  ],
  isError: true,
  structuredContent: {
    'error': {'code': code, 'message': message},
  },
);
