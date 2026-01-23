# Future Work & Code Review Notes

This document tracks recommendations and potential improvements identified during code reviews to guide future development.

## 🟢 Architecture Review (Jan 2026)

The core architecture is solid, with a clear separation between `Processor` (queue management) and `Scheduler` (global execution loop).

### 🚀 Recommended Enhancements

#### 1. Throttled Parallel Execution
In `ProcessAsyncRunnables`, when `runInParallel` is `true`, all futures are triggered immediately.
- **Goal:** Add a `maxConcurrent` parameter.
- **Benefit:** Prevents resource exhaustion (e.g., too many simultaneous network requests or file handles) while still allowing parallel processing.

#### 2. Fine-grained Scheduling (Slicing)
Currently, `Scheduler` executes exactly one `run()` call per tick.
- **Goal:** Consider a "budgeted" update where the `Scheduler` runs as many tasks as possible within a certain time budget (e.g., 8ms) per tick.
- **Benefit:** Higher throughput on powerful devices while still maintaining 60fps/120fps.

#### 3. Task Priorities
Tasks are currently processed in a strict Round-Robin order across contexts.
- **Goal:** Introduce priority levels (e.g., High, Medium, Low).
- **Benefit:** Allows critical UI-blocking tasks to jump ahead of background maintenance tasks.

#### 4. Improved Async Polling
The `Scheduler` currently calls `run()` on `ProcessAsyncRunnables` every tick, which results in a no-op after the first call.
- **Goal:** Allow `Task` to signal to the `Scheduler` if it needs to be polled or if it will notify the scheduler when it's done.
- **Benefit:** Minor CPU optimization for long-running async tasks.

### 🛠 Maintenance Notes

- **TaskContext Identity:** Reminder that `TaskContext` uses instance identity. If we ever want serializable contexts, we'll need to implement `operator ==` and `hashCode` based on a unique string identifier.
- **Testing:** Ensure `fake_async` is considered for future timing-related tests in `Scheduler` to avoid real-time `Future.delayed` calls.
