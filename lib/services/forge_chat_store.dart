import 'dart:convert';

import 'forge_agent.dart';
import 'json_file.dart';

/// История диалога с «Кузницей» между запусками приложения.
///
/// Хранилище общее с остальными данными (зашифрованный [JsonFile]), поэтому
/// разговор переживает перезапуск. Если хранилище недоступно, экран просто
/// работает с пустой историей — падать из-за этого нельзя.
class ForgeChatStore {
  ForgeChatStore._();

  static const key = 'forge_chat_history';

  /// Потолок истории: контекст уходит в промпт, и бесконечный лог съел бы
  /// окно модели. Держим последние реплики.
  static const maxMessages = 200;

  static List<ForgeChatMessage> parse(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map<String, dynamic>) ForgeChatMessage.fromJson(item),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<List<ForgeChatMessage>> load() async {
    try {
      return parse(await JsonFile.read(key));
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(List<ForgeChatMessage> messages) async {
    final trimmed = messages.length > maxMessages
        ? messages.sublist(messages.length - maxMessages)
        : messages;
    try {
      await JsonFile.write(
        key,
        jsonEncode(trimmed.map((m) => m.toJson()).toList()),
      );
    } catch (_) {
      // История — удобство, а не данные пользователя: молча живём без неё.
    }
  }

  static Future<void> clear() async {
    try {
      await JsonFile.write(key, '[]');
    } catch (_) {
      // см. save()
    }
  }
}
