import 'package:main_thread_processor/src/processor.dart';
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

    test('multiple ProcessRunnables in queue, each with multiple items',
        () async {
      final processor = Processor.shared;
      processor.removeAllTasks();

      final task1Results = <String>[];
      final task2Results = <String>[];
      final task3Results = <String>[];

      final task1 = ProcessRunnables.list([
        ('task1-item1', () => task1Results.add("task1-item1")),
        ('task1-item2', () => task1Results.add("task1-item2")),
        ('task1-item3', () => task1Results.add("task1-item3")),
      ]);

      final task2 = ProcessRunnables.list([
        ('task2-item1', () => task2Results.add("task2-item1")),
        ('task2-item2', () => task2Results.add("task2-item2")),
      ]);

      final task3 = ProcessRunnables.list([
        ('task3-item1', () => task3Results.add("task3-item1")),
        ('task3-item2', () => task3Results.add("task3-item2")),
        ('task3-item3', () => task3Results.add("task3-item3")),
        ('task3-item4', () => task3Results.add("task3-item4")),
      ]);

      processor.addTask(task1);
      processor.addTask(task2);
      processor.addTask(task3);

      expect(processor.hasOutstanding, isTrue);
      expect(task1.progress, 0.0);
      expect(task2.progress, 0.0);
      expect(task3.progress, 0.0);

      // Process task1 - should execute all 3 items
      await processor.update();
      expect(task1Results, ["task1-item1"]);
      expect(task1.progress, closeTo(0.33, 0.01));

      await processor.update();
      expect(task1Results, ["task1-item1", "task1-item2"]);
      expect(task1.progress, closeTo(0.67, 0.01));

      await processor.update();
      expect(task1Results, ["task1-item1", "task1-item2", "task1-item3"]);
      expect(task1.progress, 1.0);

      // Task1 should be removed, now process task2
      await processor.update();
      expect(task2Results, ["task2-item1"]);
      expect(task2.progress, 0.5);

      await processor.update();
      expect(task2Results, ["task2-item1", "task2-item2"]);
      expect(task2.progress, 1.0);

      // Task2 should be removed, now process task3
      await processor.update();
      expect(task3Results, ["task3-item1"]);
      expect(task3.progress, 0.25);

      await processor.update();
      expect(task3Results, ["task3-item1", "task3-item2"]);
      expect(task3.progress, 0.5);

      await processor.update();
      expect(task3Results, ["task3-item1", "task3-item2", "task3-item3"]);
      expect(task3.progress, 0.75);

      await processor.update();
      expect(task3Results,
          ["task3-item1", "task3-item2", "task3-item3", "task3-item4"]);
      expect(task3.progress, 1.0);

      // All tasks should be complete
      expect(processor.hasOutstanding, isFalse);

      // Verify all items executed in the correct order
      expect(task1Results, ["task1-item1", "task1-item2", "task1-item3"]);
      expect(task2Results, ["task2-item1", "task2-item2"]);
      expect(task3Results,
          ["task3-item1", "task3-item2", "task3-item3", "task3-item4"]);

      processor.removeAllTasks();
    });
  });
}
