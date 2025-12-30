# Main Thread Processor

A Dart package designed to manage and execute tasks on the main thread without blocking the UI. It breaks down complex or long-running operations into smaller "runnables" (synchronous or asynchronous) and processes them incrementally using a periodic timer.

This approach is ideal for preventing frame drops (jank) in Flutter applications when performing heavy computations or batch processing.

## Features

-   **Chunked Execution**: Splits heavy work into small steps to keep the UI responsive.
-   **Task Queue**: A central `Processor` singleton manages a queue of tasks.
-   **Sync & Async Support**:
    -   `ProcessRunnables`: For synchronous work (CPU bound).
    -   `ProcessAsyncRunnables`: For asynchronous work (IO bound), with support for sequential or parallel execution.
-   **Progress Tracking**: Built-in 0.0 to 1.0 progress reporting for all tasks.
-   **Automatic Resource Management**: The processor automatically pauses its timer when the queue is empty.

## Getting Started

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  main_thread_processor: ^1.0.0
```

## Usage

### 1. The Processor

The `Processor` is a singleton that drives the execution of tasks. It checks the task queue every 20ms (default) and runs the current task.

```dart
// (Optional) Configure the update period
Processor.shared.period = 30; // Check/Run tasks every 30ms
```

### 2. Synchronous Tasks (`ProcessRunnables`)

Use `ProcessRunnables` for CPU-intensive work that can be broken into steps.

```dart
import 'package:main_thread_processor/main_thread_processor.dart';

void main() {
  // 1. Create a task with a list of steps
  final syncTask = ProcessRunnables.list([
    ('Initialize', () => print('Initializing core...')),
    ('Load Config', () => print('Loading configuration...')),
    ('Compute Hash', () {
       // Perform a chunk of heavy math here
       print('Computing...');
    }),
  ]);

  // 2. Add individual steps manually if needed
  syncTask.addRunnable('Finalize', () => print('Done!'));

  // 3. Schedule the task
  Processor.shared.addTask(syncTask);
  
  // The Processor will now execute one runnable every 'period' (20ms) 
  // until the task is complete.
}
```

### 3. Asynchronous Tasks (`ProcessAsyncRunnables`)

Use `ProcessAsyncRunnables` for futures, such as network requests or file IO. You can choosing between parallel or sequential execution.

#### Parallel Execution (Default)
All futures are triggered immediately. Progress updates as they complete.

```dart
final parallelTask = ProcessAsyncRunnables(runInParallel: true);

parallelTask.addAsyncRunnable('Download A', () async {
  await downloadFile('A');
});
parallelTask.addAsyncRunnable('Download B', () async {
  await downloadFile('B');
});

Processor.shared.addTask(parallelTask);
```

#### Sequential Execution
Tasks run one after another. Task B waits for Task A to complete.

```dart
final sequenceTask = ProcessAsyncRunnables(runInParallel: false);

sequenceTask.addAsyncRunnable('Step 1', () async => await doFirstThing());
sequenceTask.addAsyncRunnable('Step 2', () async => await doSecondThing());

Processor.shared.addTask(sequenceTask);
```

### 4. Logging

The package uses the standard `logging` package. To see internal processor logs (helpful for debugging):

```dart
import 'package:logging/logging.dart';

void main() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });
  
  // ... tasks ...
}
```

## API Overview

### `Processor`
-   `Processor.shared`: Access the singleton instance.
-   `addTask(Task task)`: specific task to the queue for execution.
-   `removeTask(Task task)`: Cancels and removes a specific task.
-   `removeAllTasks()`: Clears the entire queue.
-   `period`: (int) Get or set the interval in milliseconds between processing ticks.

### `Task` (Abstract)
-   `progress`: (double) Current completion status (0.0 to 1.0).
-   `isComplete`: (bool) Returns true when progress is 1.0.
-   `reset()`: Resets the task state so it can be re-run.

### `ProcessRunnables`
-   `addRunnable(String name, Runnable runnable)`: Adds a sync function unique name.

### `ProcessAsyncRunnables`
-   `addAsyncRunnable(String name, AsyncRunnable runnable)`: Adds an async function.
-   `runInParallel`: (bool) Controls execution mode.