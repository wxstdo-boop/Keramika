/// Запись журнала изменений («Что нового»).
///
/// Одна запись = один релиз: версия, дата (YYYY-MM-DD) и список пунктов.
/// Раньше записи были захардкожены в экране и отставали от версии приложения;
/// теперь их собирает `UpdateService` из публичных GitHub-релизов, а этот тип
/// — общий для живого списка и встроенного запасного.
class ChangelogEntry {
  const ChangelogEntry({
    required this.version,
    required this.date,
    required this.changes,
    this.time = '',
  });

  final String version;

  /// Дата релиза, `YYYY-MM-DD` (как приходит из GitHub).
  final String date;

  /// Точное время релиза, `HH:MM:SS` в ЛОКАЛЬНОЙ зоне. Пустое, если в теле
  /// релиза времени не было — тогда показываем только дату.
  final String time;

  final List<String> changes;
}
