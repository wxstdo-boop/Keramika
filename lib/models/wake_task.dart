enum WakeUpTask {
  none,
  math,
  pattern,
  memory;

  String get key {
    switch (this) {
      case WakeUpTask.none:
        return 'taskNone';
      case WakeUpTask.math:
        return 'taskMath';
      case WakeUpTask.pattern:
        return 'taskPattern';
      case WakeUpTask.memory:
        return 'taskMemory';
    }
  }
}
