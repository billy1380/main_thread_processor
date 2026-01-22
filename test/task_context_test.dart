import 'package:main_thread_processor/src/task_context.dart';
import 'package:test/test.dart';

void main() {
  group('TaskContext', () {
    test('uses name in toString when provided', () {
      final context = TaskContext('MyContext');
      expect(context.toString(), contains('TaskContext(MyContext#'));
    });

    test('uses identity hash when name is null', () {
      final context = TaskContext(null);
      expect(context.toString(), startsWith('TaskContext@'));
    });

    test('uses identity hash when name is empty', () {
      final context = TaskContext('');
      expect(context.toString(), startsWith('TaskContext@'));
    });

    test('two contexts with the same name are not equal', () {
      final context1 = TaskContext('SameName');
      final context2 = TaskContext('SameName');

      expect(context1, isNot(equals(context2)));
      expect(context1.toString(), isNot(equals(context2.toString())));
    });

    test('identity hash is included in named contexts', () {
      final context = TaskContext('Test');
      final hash = identityHashCode(context).toRadixString(16);
      expect(context.toString(), contains('#$hash)'));
    });
  });
}
