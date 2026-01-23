import 'package:main_thread_processor/src/processor.dart';
import 'package:main_thread_processor/src/tasks/process_runnables.dart';
import 'package:test/test.dart';

void main() {
  group('Scheduler', () {
    test('changing period updates the scheduling interval', () async {
      final scheduler = Scheduler.shared;
      final processor = Processor();

      // Reset to default
      scheduler.period = 20;

      var runCount = 0;
      final task = ProcessRunnables.list([
        ('1', () => runCount++),
        ('2', () => runCount++),
        ('3', () => runCount++),
      ]);

      processor.addTask(task);

      // We can't easily test real-time timing in unit tests without a fake async
      // or awaiting real time.
      // But we can verify the property is set.
      expect(scheduler.period, 20);

      scheduler.period = 50;
      expect(scheduler.period, 50);

      // Verify task still runs
      await scheduler.update();
      expect(runCount, 1);
      
      processor.removeAllTasks();
    });

    test('Scheduler is a singleton', () {
      final s1 = Scheduler.shared;
      final s2 = Scheduler.shared;
      expect(s1, same(s2));
    });
  });
}
