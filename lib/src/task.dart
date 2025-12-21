abstract class Task {
  void run();
  void reset();
  double get progress;

  bool get isComplete => progress == 1.0;
}
