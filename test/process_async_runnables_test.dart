import 'dart:async';
import 'package:main_thread_processor/src/tasks/process_async_runnables.dart';
import 'package:test/test.dart';

void main() {
  group('ProcessAsyncRunnables', () {
    test('runs futures concurrently and tracking progress', () async {
      final task = ProcessAsyncRunnables();
      final completer1 = Completer<void>();
      final completer2 = Completer<void>();

      var task1Started = false;
      var task2Started = false;

      task.addAsyncRunnable('task1', () async {
        task1Started = true;
        await completer1.future;
      });
      task.addAsyncRunnable('task2', () async {
        task2Started = true;
        await completer2.future;
      });

      expect(task.progress, 0.0);

      task.run();

      // Both should have started immediately
      expect(task1Started, isTrue);
      expect(task2Started, isTrue);
      expect(task.progress, 0.0);

      // Complete first
      completer1.complete();
      // Allow event loop to process
      await Future.delayed(Duration.zero);
      expect(task.progress, 0.5);

      // Complete second
      completer2.complete();
      await Future.delayed(Duration.zero);
      expect(task.progress, 1.0);
    });

    test('reset clears state and allows re-running', () async {
      final task = ProcessAsyncRunnables();
      final completer = Completer<void>();

      task.addAsyncRunnable('task1', () => completer.future);
      task.run();
      completer.complete();
      await Future.delayed(Duration.zero);

      expect(task.progress, 1.0);

      task.reset();
      expect(task.progress, 0.0);

      // Can run again (though here we'd need to add new tasks or reuse same logic if they weren't one-shot)
      // For this test, just verifying internal counters reset
    });

    test('single constructor works', () async {
      final completer = Completer<void>();
      final task =
          ProcessAsyncRunnables.single('single', () => completer.future);
      task.run();
      completer.complete();
      await Future.delayed(Duration.zero);
      expect(task.progress, 1.0);
    });

    test('list constructor works', () async {
      final c1 = Completer<void>();
      final c2 = Completer<void>();

      final task = ProcessAsyncRunnables.list([
        ('t1', () => c1.future),
        ('t2', () => c2.future),
      ]);

      task.run();
      c1.complete();
      c2.complete();
      await Future.delayed(Duration.zero);
      expect(task.progress, 1.0);
    });

    test('cannot add tasks after starting', () {
      final task = ProcessAsyncRunnables();
      task.run();

      task.addAsyncRunnable('late_task', () async {});
      expect(task.progress, 1.0); // 0/0 is considered 1, or empty list is 1.
      // Actually implementation returns 1 if empty.

      // Let's verify it wasn't added conceptually (no side effects exposed easily without getters,
      // but we can check progress stays at 1.0 if we assume it didn't get added to a list that would make it 0/1)
    });
    test('runInParallel: false executes tasks sequentially', () async {
      final task = ProcessAsyncRunnables(runInParallel: false);
      final completer1 = Completer<void>();
      final completer2 = Completer<void>();

      var task1Started = false;
      var task2Started = false;

      task.addAsyncRunnable('task1', () async {
        task1Started = true;
        await completer1.future;
      });
      task.addAsyncRunnable('task2', () async {
        task2Started = true;
        await completer2.future;
      });

      task.run();

      // Only task 1 should start
      expect(task1Started, isTrue);
      expect(task2Started, isFalse);
      expect(task.progress, 0.0);

      // Complete task 1, trigger task 2
      completer1.complete();
      await Future.delayed(Duration.zero);

      expect(task.progress, 0.5);
      expect(task2Started, isTrue);

      // Complete task 2
      completer2.complete();
      await Future.delayed(Duration.zero);
      expect(task.progress, 1.0);
    });
  });
}
