import 'dart:async';

import 'package:logging/logging.dart';
import 'package:main_thread_processor/src/task.dart';

class Processor {
  static final Logger _log = Logger("Processor");

  static Processor? _one;

  StreamSubscription? _subscription;
  int _period = 20;

  Processor._();

  static Processor get shared => _one ??= Processor._();

  bool get _isPaused => _subscription == null;
  bool _inUpdate = false;
  List<Task>? taskQueue;

  void addTask(Task task) {
    taskQueue ??= <Task>[];

    taskQueue!.add(task);

    if (_isPaused && !_inUpdate) {
      _log.info("resuming update loop...");

      resume();
    }
  }

  void removeTask(Task? task) {
    if (task != null && taskQueue != null) {
      bool paused = false;

      if (!_isPaused) {
        pause();
        paused = true;
      }

      taskQueue!.remove(task);

      if (paused) {
        resume();
      }
    }
  }

  void removeAllTasks() {
    if (taskQueue != null) {
      bool paused = false;

      if (!_isPaused) {
        pause();
        paused = true;
      }

      taskQueue!.clear();

      if (paused) {
        resume();
      }
    }

    _inUpdate = false;
  }

  Future<bool> update() async {
    bool more = false;

    if (_isPaused) {
      more = taskQueue?.isNotEmpty ?? false;
    } else {
      _inUpdate = true;

      if (!_isPaused && hasOutstanding) {
        Task task = taskQueue!.first;

        _log.info("Found task 1 of ${taskQueue!.length}");

        _log.info("running task...");
        task.run();

        double progress = task.progress;
        final progressPercentage = progress * 100;
        _log.info("current run is ${progressPercentage.toStringAsFixed(1)}%");
        if (progress >= 1) {
          _log.info("task complete removing...");
          taskQueue!.remove(task);
        }

        if (hasOutstanding) {
          _log.info("resuming update loop...");
          more = true;
        }
      } else {
        _log.info("Task queue is empty");
      }

      if (!more) {
        pause();
      }

      _inUpdate = false;
    }

    return more;
  }

  bool get hasOutstanding => taskQueue != null && taskQueue!.isNotEmpty;

  void pause() {
    _subscription?.cancel();
    _subscription = null;
  }

  void resume() {
    if (!_inUpdate && hasOutstanding && _isPaused) {
      _subscription = Stream.periodic(const Duration(seconds: 1))
          .listen((event) => update());
    }
  }

  int get period {
    return _period;
  }

  set period(int value) {
    pause();
    _period = value;
    resume();
  }
}
