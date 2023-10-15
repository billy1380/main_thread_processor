import 'package:logging/logging.dart';
import 'package:main_thread_processor/src/task.dart';

typedef Runnable = void Function();

class ProcessRunnables implements Task {
  static final Logger _log = Logger("ProcessRunnables");

  List<Runnable>? _runnables;
  List<String>? _names;
  int _progress = 0;
  bool _running = false;

  @override
  double get progress =>
      _runnables == null ? 1 : _progress / _runnables!.length;

  @override
  void run() {
    _running = true;

    if (_runnables != null && _runnables!.length > progress) {
      _log.info("Running task named [${_names![_progress]}]");
      _runnables![_progress]();
    }

    _progress++;
  }

  void addRunnable(String name, Runnable runnable) {
    if (_running) {
      _log.info(
          "[$name] cannot be updated (discarded)... task is already running");
    } else {
      _ensureNames().add(name);
      _ensureRunnables().add(runnable);
    }
  }

  List<Runnable> _ensureRunnables() => _runnables ??= <Runnable>[];

  List<String> _ensureNames() => _names ??= <String>[];
}
