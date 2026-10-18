import 'dart:async';

import 'package:logging/logging.dart';
import 'package:main_thread_processor/src/processor.dart';
import 'package:main_thread_processor/src/scheduler.dart';
import 'package:main_thread_processor/src/task.dart';
import 'package:main_thread_processor/src/tasks/process_runnables.dart';
import 'package:test/test.dart';

class _StuckTask extends Task {
  final double _progress;
  int runs = 0;

  _StuckTask({double progress = 0}) : _progress = progress;

  @override
  void run() => runs++;

  @override
  void reset() {}

  @override
  double get progress => _progress;
}

class _CreepingTask extends Task {
  double _progress = 0;

  @override
  void run() => _progress += 0.01;

  @override
  void reset() => _progress = 0;

  @override
  double get progress => _progress;
}

Future<void> _tick(Scheduler scheduler, [int milliseconds = 30]) async {
  await Future<void>.delayed(Duration(milliseconds: milliseconds));
  await scheduler.update();
}

void main() {
  group('Stall detection', () {
    final scheduler = Scheduler.shared;
    late Processor processor;
    late List<LogRecord> records;
    late StreamSubscription<LogRecord> subscription;

    Iterable<LogRecord> logged(Level level) =>
        records.where((r) => r.level == level);

    setUp(() {
      Logger.root.level = Level.ALL;
      records = [];
      subscription = Logger.root.onRecord.listen(records.add);
      scheduler.resetStallLimits();
      processor = Processor();
    });

    tearDown(() async {
      processor.removeAllTasks();
      scheduler.resetStallLimits();
      await subscription.cancel();
    });

    test('logs one warning when a task stops making progress', () async {
      scheduler.stallWarning = const Duration(milliseconds: 40);
      processor.addTask(_StuckTask());

      for (var i = 0; i < 6; i++) {
        await _tick(scheduler, 40);
      }

      final warnings =
          logged(Level.WARNING).where((r) => r.message.contains('_StuckTask'));
      expect(warnings.length, 1);
      expect(processor.hasOutstanding, isTrue);
    });

    test('removes a stuck task at the limit and logs it as severe', () async {
      scheduler.stallWarning = const Duration(milliseconds: 20);
      scheduler.stallLimit = const Duration(milliseconds: 60);
      final task = _StuckTask();
      processor.addTask(task);

      for (var i = 0; i < 20 && processor.hasOutstanding; i++) {
        await _tick(scheduler);
      }

      expect(processor.hasOutstanding, isFalse);
      expect(task.runs, greaterThan(0));
      expect(
          logged(Level.SEVERE).where((r) => r.message.contains('_StuckTask')),
          hasLength(1));
    });

    test('a progress of NaN is still detected as stuck', () async {
      scheduler.stallWarning = const Duration(milliseconds: 20);
      scheduler.stallLimit = const Duration(milliseconds: 60);
      processor.addTask(_StuckTask(progress: double.nan));

      for (var i = 0; i < 20 && processor.hasOutstanding; i++) {
        await _tick(scheduler);
      }

      expect(processor.hasOutstanding, isFalse);
      expect(logged(Level.SEVERE), isNotEmpty);
    });

    test('a task that keeps making progress is left alone', () async {
      scheduler.stallWarning = const Duration(milliseconds: 40);
      scheduler.stallLimit = const Duration(milliseconds: 80);
      processor.addTask(_CreepingTask());

      for (var i = 0; i < 8; i++) {
        await _tick(scheduler);
      }

      expect(processor.hasOutstanding, isTrue);
      expect(logged(Level.WARNING), isEmpty);
      expect(logged(Level.SEVERE), isEmpty);
    });

    test('a finished task is never reported', () async {
      scheduler.stallWarning = const Duration(milliseconds: 20);
      scheduler.stallLimit = const Duration(milliseconds: 40);
      processor.addTask(ProcessRunnables.list([('only', () {})]));

      await scheduler.update();
      await _tick(scheduler, 50);

      expect(processor.hasOutstanding, isFalse);
      expect(logged(Level.WARNING), isEmpty);
      expect(logged(Level.SEVERE), isEmpty);
    });

    test('the limits can be moved but not switched off', () {
      expect(() => scheduler.stallLimit = Duration.zero, throwsArgumentError);
      expect(() => scheduler.stallWarning = const Duration(seconds: -1),
          throwsArgumentError);

      scheduler.stallLimit = const Duration(seconds: 5);
      expect(scheduler.stallLimit, const Duration(seconds: 5));

      scheduler.resetStallLimits();
      expect(scheduler.stallWarning, const Duration(seconds: 10));
      expect(scheduler.stallLimit, const Duration(seconds: 120));
    });
  });
}
