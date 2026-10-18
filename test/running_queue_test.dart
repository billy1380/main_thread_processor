import 'dart:async';

import 'package:main_thread_processor/src/processor.dart';
import 'package:main_thread_processor/src/task.dart';
import 'package:test/test.dart';

class _CountingTask extends Task {
  int runs = 0;
  double value = 0;
  final double step;

  _CountingTask({this.step = 0});

  @override
  void run() {
    runs++;
    value += step;
  }

  @override
  void reset() {}

  @override
  double get progress => value;
}

class _AsyncTask extends Task {
  final Completer<void> work = Completer<void>();
  int runs = 0;
  double _progress = 0;
  bool _started = false;

  @override
  void run() {
    runs++;

    if (_started) return;
    _started = true;

    work.future.then((_) => _progress = 1);
  }

  @override
  void reset() {}

  @override
  double get progress => _progress;
}

void main() {
  group('Running queue', () {
    final scheduler = Scheduler.shared;
    late Processor processor;

    setUp(() {
      processor = Processor();
    });

    tearDown(() {
      processor.removeAllTasks();
    });

    test('a call that made no progress is not repeated', () async {
      final task = _CountingTask();
      processor.addTask(task);

      for (var i = 0; i < 5; i++) {
        await scheduler.update();
      }

      expect(task.runs, 1);
      expect(processor.hasOutstanding, isTrue);
    });

    test('the task is called again once its progress changes', () async {
      final task = _CountingTask();
      processor.addTask(task);

      await scheduler.update();
      await scheduler.update();
      expect(task.runs, 1);

      task.value = 0.5;
      await scheduler.update();
      expect(task.runs, 2);

      await scheduler.update();
      await scheduler.update();
      expect(task.runs, 2);
    });

    test('a task that makes progress on every call keeps being called',
        () async {
      final task = _CountingTask(step: 0.1);
      processor.addTask(task);

      for (var i = 0; i < 5; i++) {
        await scheduler.update();
      }

      expect(task.runs, 5);
    });

    test('async work is started once and the task finishes when it ends',
        () async {
      final task = _AsyncTask();
      processor.addTask(task);

      for (var i = 0; i < 4; i++) {
        await scheduler.update();
      }
      expect(task.runs, 1);

      task.work.complete();
      await Future<void>.delayed(Duration.zero);

      await scheduler.update();
      expect(processor.hasOutstanding, isFalse);
    });

    test('a running task holds its context but not the others', () async {
      final other = Processor();
      final running = _CountingTask();
      final behind = _CountingTask();
      final unrelated = _CountingTask(step: 0.25);

      processor.addTask(running);
      processor.addTask(behind);
      other.addTask(unrelated);

      for (var i = 0; i < 8; i++) {
        await scheduler.update();
      }

      expect(running.runs, 1);
      expect(behind.runs, 0);
      expect(unrelated.runs, 4);
      expect(other.hasOutstanding, isFalse);

      other.removeAllTasks();
    });

    test('the next task starts once the running task has finished', () async {
      final running = _CountingTask();
      final behind = _CountingTask(step: 1);

      processor.addTask(running);
      processor.addTask(behind);

      await scheduler.update();
      await scheduler.update();
      expect(behind.runs, 0);

      running.value = 1;
      await scheduler.update();
      await scheduler.update();

      expect(behind.runs, 1);
      expect(processor.hasOutstanding, isFalse);
    });

    test('a running task can be removed', () async {
      final task = _CountingTask();
      processor.addTask(task);

      await scheduler.update();
      expect(processor.hasOutstanding, isTrue);

      processor.removeTask(task);
      expect(processor.hasOutstanding, isFalse);
    });

    test('removing every task clears the running ones too', () async {
      processor.addTask(_CountingTask());

      await scheduler.update();
      expect(processor.hasOutstanding, isTrue);

      processor.removeAllTasks();
      expect(processor.hasOutstanding, isFalse);
    });
  });
}
