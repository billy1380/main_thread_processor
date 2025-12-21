import 'package:main_thread_processor/src/tasks/process_runnables.dart';
import 'package:test/test.dart';

void main() {
  group('ProcessRunnables', () {
    test('runs runnables sequentially on each run call', () {
      final task = ProcessRunnables();
      var runCount1 = 0;
      var runCount2 = 0;

      task.addRunnable('task1', () {
        runCount1++;
      });
      task.addRunnable('task2', () {
        runCount2++;
      });

      expect(task.progress, 0.0);

      // First run should execute first task
      task.run();
      expect(runCount1, 1);
      expect(runCount2, 0);
      expect(task.progress, 0.5);

      // Second run should execute second task
      task.run();
      expect(runCount1, 1);
      expect(runCount2, 1);
      expect(task.progress, 1.0);

      // Subsequent runs should do nothing (or tracking keeps incrementing? implementation says _progress++ unconditionally)
      // Let's check implementation:
      // if (length > progress) { run }
      // _progress++
      // Wait, progress getter uses _progress / length.
      // if _progress > length, progress getter will return > 1.0?
      // Let's verify existing behavior.

      task.run();
      expect(runCount1, 1);
      expect(runCount2, 1);
    });

    test('reset clears state and allows re-running', () {
      final task = ProcessRunnables();
      var count = 0;
      task.addRunnable('task', () => count++);

      task.run();
      expect(count, 1);
      expect(task.progress, 1.0);

      task.reset();
      expect(task.progress, 0.0);

      task.run();
      expect(count, 2);
    });

    test('single constructor works', () {
      var count = 0;
      final task = ProcessRunnables.single('single', () => count++);
      task.run();
      expect(count, 1);
    });

    test('list constructor works', () {
      var count1 = 0;
      var count2 = 0;
      final task = ProcessRunnables.list([
        ('t1', () => count1++),
        ('t2', () => count2++),
      ]);

      task.run();
      expect(count1, 1);
      expect(count2, 0);
      task.run();
      expect(count1, 1);
      expect(count2, 1);
    });

    test('cannot add runnables after running has started', () {
      final task = ProcessRunnables();
      task.run(); // Sets _running = true

      task.addRunnable('late', () {});

      // Should not be added.
      // Since we don't have public access to list, effectively checking behavior or progress
      // If added, progress would be 0/1 = 0
      // If not added, progress would remain 0/0 = 1 (empty list is 1)

      expect(task.progress, 1.0);
    });
  });
}
