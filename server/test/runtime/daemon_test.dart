import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('daemon launch races converge, survives bridge exits, and recovers after a crash', () async {
    final directory = await Directory.systemTemp.createTemp('todo-daemon-test-');
    final web = Directory('${directory.path}/web')..createSync();
    File('${web.path}/index.html').writeAsStringSync('<html>app</html>');
    final dataPath = '${directory.path}/data';
    final cliFile = '${Directory.current.path}/bin/todo_agent_app.dart';

    Future<ProcessResult> launchUrl() =>
        Process.run('dart', ['run', cliFile, 'url', '--data', dataPath, '--web', web.path]);

    Uri resultUrl(ProcessResult result) {
      expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');
      final line = (result.stdout as String)
          .split('\n')
          .where((line) => line.startsWith('http://127.0.0.1:'))
          .last;
      return Uri.parse(line);
    }

    Future<Uri> url() async => resultUrl(await launchUrl());

    Future<void> stop() async {
      final result = await Process.run('dart', [
        'run',
        cliFile,
        'stop',
        '--data',
        dataPath,
        '--web',
        web.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');
    }

    try {
      final concurrent = await Future.wait([launchUrl(), launchUrl()]);
      final firstUrl = resultUrl(concurrent.first);
      expect(resultUrl(concurrent.last), firstUrl);

      // A second explicit server process waits on the same OS lock and cannot
      // create a second listener or open another SQLite owner.
      final secondServer = await Process.start('dart', [
        'run',
        cliFile,
        'serve',
        '--data',
        dataPath,
        '--web',
        web.path,
      ]);
      secondServer.stdout.listen((_) {});
      secondServer.stderr.listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(secondServer.kill(ProcessSignal.sigkill), isTrue);
      await secondServer.exitCode;

      final token = Uri.splitQueryString(firstUrl.fragment)['token']!;
      final client = HttpClient();
      try {
        final create = await client.postUrl(Uri.parse('${firstUrl.origin}/api/tasks'));
        create.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        create.headers.contentType = ContentType.json;
        create.write(jsonEncode({'title': 'Persist me'}));
        final created = await create.close();
        expect(created.statusCode, 201);
        await created.drain<void>();
      } finally {
        client.close(force: true);
      }

      await stop();
      final secondUrl = await url();
      final secondToken = Uri.splitQueryString(secondUrl.fragment)['token']!;
      final verifyClient = HttpClient();
      try {
        final request = await verifyClient.getUrl(Uri.parse('${secondUrl.origin}/api/tasks'));
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secondToken');
        final response = await request.close();
        final snapshot = jsonDecode(await response.transform(utf8.decoder).join());
        expect(snapshot['tasks'], hasLength(1));
        expect(snapshot['tasks'].single['title'], 'Persist me');
      } finally {
        verifyClient.close(force: true);
      }
      final oldDescriptor = jsonDecode(await File('$dataPath/daemon.json').readAsString());

      // The OS releases the profile lock after an unclean death. The next
      // bridge replaces the stale descriptor only after taking that lock.
      expect(Process.killPid(oldDescriptor['pid'] as int, ProcessSignal.sigkill), isTrue);
      final recoveredUrl = await url();
      final recoveredToken = Uri.splitQueryString(recoveredUrl.fragment)['token']!;
      expect(recoveredToken, isNot(secondToken));
      final recoveryClient = HttpClient();
      try {
        final request = await recoveryClient.getUrl(Uri.parse('${recoveredUrl.origin}/api/tasks'));
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $recoveredToken');
        final response = await request.close();
        final snapshot = jsonDecode(await response.transform(utf8.decoder).join());
        expect(snapshot['tasks'], hasLength(1));
      } finally {
        recoveryClient.close(force: true);
      }
      await stop();
    } finally {
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 1)));
}
