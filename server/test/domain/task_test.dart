import 'package:test/test.dart';
import 'package:todo_agent_app/domain/task.dart';

void main() {
  group('Task title validation', () {
    test('trims surrounding whitespace', () {
      expect(Task.validateTitle('  read the plan  '), 'read the plan');
    });

    test('rejects empty and overlong titles', () {
      expect(() => Task.validateTitle('  '), throwsA(isA<ArgumentError>()));
      expect(() => Task.validateTitle('x' * 201), throwsA(isA<ArgumentError>()));
    });
  });
}
