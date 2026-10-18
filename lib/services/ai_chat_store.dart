import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'ai_guide_service.dart';
import 'json_file.dart';
import '../widgets/ada_avatars.dart';

/// Общая история чата Ады для главного окна, плавающего пузыря и оверлея.
///
/// Два Flutter-движка не делят память, поэтому запись всегда идёт через
/// [JsonFile.writeWithSnapshot], а после слияния вызывающий обязан принять
/// вернувшийся список — иначе локальная копия расходится с диском.
class AiChatStore {
  AiChatStore._();

  static const key = 'ai_chat_history';

  /// Растёт в этом движке после каждой удачной записи. Второй движок
  /// видит то же число в `ada_sync_state.historyRev`.
  static final ValueNotifier<int> tick = ValueNotifier<int>(0);

  static List<AiMessage> parse(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .map((item) => AiMessage.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  static Future<({List<AiMessage> messages, String? snapshot})> load() async {
    final raw = await JsonFile.read(key);
    return (messages: parse(raw), snapshot: raw);
  }

  static Future<({List<AiMessage> messages, String snapshot})> save(
    List<AiMessage> messages,
    String? snapshot,
  ) async {
    var toSave = messages;
    if (toSave.length > 1000) {
      toSave = toSave.sublist(toSave.length - 1000);
    }
    final value = jsonEncode(toSave.map((message) => message.toJson()).toList());
    final resolved = await JsonFile.writeWithSnapshot(key, value, snapshot);
    final next = DateTime.now().millisecondsSinceEpoch;
    tick.value = next;
    await writeAdaSyncState(historyRev: next);
    return (messages: parse(resolved), snapshot: resolved);
  }

  /// Дописывает сообщения, которые уже есть в памяти, но ещё не попали
  /// в слитый снимок (например, только что набранный вопрос, пока шёл merge).
  static List<AiMessage> adopt(
    List<AiMessage> local,
    List<AiMessage> incoming,
  ) {
    if (incoming.isEmpty && local.isEmpty) return local;
    final seen = {for (final message in incoming) identity(message)};
    final extra = local.where((message) => seen.add(identity(message)));
    return [...incoming, ...extra];
  }

  static String identity(AiMessage message) =>
      '${message.ts}:${message.isUser}:${message.text}';
}
