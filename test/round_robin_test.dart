import 'package:main_thread_processor/main_thread_processor.dart';
import 'package:test/test.dart';

void main() {
  group('Processor Round-Robin & Isolation', () {
    late Processor sharedProcessor;

    setUp(() {
      sharedProcessor = Processor.shared;
      sharedProcessor.removeAllTasks();
      // Since all processors share the central engine, we should clear everything globally if possible,
      // but the API only exposes clearing *my* tasks.
      // For tests, we can trust that new instances have empty queues.
    });

    test('tasks are executed in round-robin order across processor instances',
        () async {
      final processorA = Processor();
      final processorB = Processor();

      final executionOrder = <String>[];

      // Add 3 tasks to Processor A
      processorA.addTask(
          ProcessRunnables.single('A1', () => executionOrder.add('A1')));
      processorA.addTask(
          ProcessRunnables.single('A2', () => executionOrder.add('A2')));
      processorA.addTask(
          ProcessRunnables.single('A3', () => executionOrder.add('A3')));

      // Add 2 tasks to Processor B
      processorB.addTask(
          ProcessRunnables.single('B1', () => executionOrder.add('B1')));
      processorB.addTask(
          ProcessRunnables.single('B2', () => executionOrder.add('B2')));

      // Expected Round Robin Order:
      // A1 -> B1 -> A2 -> B2 -> A3

      // We need to drive the update loop. Any processor can do it.
      while (processorA.hasOutstanding || processorB.hasOutstanding) {
        await processorA.update();
      }

      expect(executionOrder, ['A1', 'B1', 'A2', 'B2', 'A3']);
    });

    test('removing tasks for a specific processor works', () {
      final processorA = Processor();
      final processorB = Processor();

      final taskA = ProcessRunnables.single('A1', () {});
      final taskB = ProcessRunnables.single('B1', () {});

      processorA.addTask(taskA);
      processorB.addTask(taskB);

      expect(processorA.hasOutstanding, isTrue);
      expect(processorB.hasOutstanding, isTrue);

      processorA.removeAllTasks();

      // Processor A should be empty
      expect(processorA.hasOutstanding, isFalse);

      // Processor B should still have tasks
      expect(processorB.hasOutstanding, isTrue);

      processorB.removeAllTasks();
      expect(processorB.hasOutstanding, isFalse);
    });

    test('Processor.shared is distinct from new instances', () async {
      final executionOrder = <String>[];
      final processorA = Processor();

      Processor.shared.addTask(ProcessRunnables.single(
          'Shared1', () => executionOrder.add('Shared1')));
      processorA.addTask(
          ProcessRunnables.single('A1', () => executionOrder.add('A1')));
      Processor.shared.addTask(ProcessRunnables.single(
          'Shared2', () => executionOrder.add('Shared2')));

      while (Processor.shared.hasOutstanding || processorA.hasOutstanding) {
        await Processor.shared.update();
      }

      // Order: Shared1 -> A1 -> Shared2 (assuming Shared was added first)
      expect(executionOrder, ['Shared1', 'A1', 'Shared2']);
    });
  });
}
