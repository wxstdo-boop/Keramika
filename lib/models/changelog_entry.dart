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
  });

  final String version;
  final String date;
  final List<String> changes;
}
