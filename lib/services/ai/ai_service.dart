import 'dart:async';
import 'chat_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/document.dart';
import '../../features/nutrition/nutrition_logic.dart';
import '../../shared/models/entry.dart';

class AiAction {
  final String type, title, date, referenceId, slot, start, end;
  final double quantity;
  final List<String> itemIds;
  AiAction({
    required this.type,
    required this.title,
    required this.date,
    this.referenceId = '',
    this.slot = 'dinner',
    this.start = '',
    this.end = '',
    this.quantity = 1,
    this.itemIds = const [],
  });
  factory AiAction.fromJson(Map<String, dynamic> json) => AiAction(
    type: json['type'] as String,
    itemIds: (json['itemIds'] as List? ?? []).cast<String>(),
    title: json['title'] as String,
    date: json['date'] as String,
    referenceId: json['referenceId'] as String? ?? '',
    slot: json['slot'] as String? ?? 'dinner',
    start: json['start'] as String? ?? '',
    end: json['end'] as String? ?? '',
    quantity: (json['quantity'] as num?)?.toDouble() ?? 1,
  );
  Entry toEntry(MiraDocument document) {
    final parsed = DateTime.tryParse(date);
    if (!(type == 'create_outfit' && date.isEmpty) &&
        (parsed == null ||
            dayKey(parsed) != date ||
            parsed.year < 2000 ||
            parsed.year > 2100)) {
      throw const FormatException('MIRA предложила некорректную дату');
    }
    if (title.trim().isEmpty || title.length > 300) {
      throw const FormatException('Некорректное название');
    }
    switch (type) {
      case 'create_task':
        return Entry(
          kind: Kind.task,
          title: title,
          data: {'date': date, 'done': false, 'priority': 'normal'},
        );
      case 'plan_outfit':
        final outfit = document.find(referenceId);
        if (outfit?.kind != Kind.outfit) {
          throw const FormatException(
            'Предложение ссылается на отсутствующий образ. Попросите MIRA подобрать вещи или выбрать сохранённый образ.',
          );
        }
        if (document
            .of(Kind.plannedOutfit)
            .any((e) => e.text('date') == date)) {
          throw const FormatException(
            'На эту дату уже есть образ. Измените его в разделе «Стиль».',
          );
        }
        return Entry(
          kind: Kind.plannedOutfit,
          title: outfit!.title,
          data: {'outfitId': outfit.id, 'date': date, 'worn': false},
        );
      case 'reschedule_event':
        final event = document.find(referenceId);
        if (event?.kind != Kind.event) {
          throw const FormatException(
            'Событие больше не доступно. Получите новое предложение.',
          );
        }
        final from = DateTime.tryParse(start), to = DateTime.tryParse(end);
        if (from == null ||
            to == null ||
            !to.isAfter(from) ||
            dayKey(from) != date ||
            from.year < 2000 ||
            to.year > 2100) {
          throw const FormatException('Некорректное время события');
        }
        return event!.copy(data: {...event.data, 'start': start, 'end': end});
      case 'create_outfit':
        if (itemIds.isEmpty ||
            itemIds.length > 20 ||
            itemIds.toSet().length != itemIds.length) {
          throw const FormatException(
            'Образ должен содержать от 1 до 20 разных вещей',
          );
        }
        for (final id in itemIds) {
          if (document.find(id)?.kind != Kind.wardrobe) {
            throw const FormatException(
              'Вещь из предложения больше не доступна. Получите новый вариант.',
            );
          }
        }
        return Entry(
          kind: Kind.outfit,
          title: title,
          data: {'items': itemIds, 'occasion': 'casual', 'favorite': false},
        );
      case 'plan_meal':
        final source = document.find(referenceId);
        if (source == null || !{Kind.food, Kind.recipe}.contains(source.kind)) {
          throw const FormatException('Продукт или рецепт уже удалён');
        }
        if (!{'breakfast', 'lunch', 'dinner', 'snack'}.contains(slot) ||
            quantity > 100000) {
          throw const FormatException('Некорректное количество или приём пищи');
        }
        return Entry(
          kind: Kind.mealPlan,
          title: source.title,
          data: {
            'date': date,
            'slot': slot,
            'sourceId': source.id,
            'quantity': quantity,
            'unit': source.kind == Kind.food ? 'г' : 'порц.',
            ...nutritionSnapshot(source, quantity),
          },
        );
      default:
        throw const FormatException('Это действие не поддерживается');
    }
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'title': title,
    'date': date,
    'referenceId': referenceId,
    'slot': slot,
    'quantity': quantity,
    'itemIds': itemIds,
    'start': start,
    'end': end,
  };
  String get module => {'create_task', 'reschedule_event'}.contains(type)
      ? 'planner'
      : {'plan_outfit', 'create_outfit'}.contains(type)
      ? 'style'
      : 'nutrition';

  /// Must run inside a store mutation: both records commit or neither does.
  void apply(MiraDocument document) {
    if (!(document.profile['modules'] as List? ?? []).contains(module)) {
      throw const FormatException('Включите этот раздел в профиле');
    }
    if (type == 'create_outfit' &&
        date.isNotEmpty &&
        document.of(Kind.plannedOutfit).any((e) => e.text('date') == date)) {
      throw const FormatException(
        'На эту дату уже есть образ. Измените его в разделе «Стиль».',
      );
    }
    final entry = toEntry(document);
    document.put(entry);
    if (type == 'create_outfit' && date.isNotEmpty) {
      document.put(
        Entry(
          kind: Kind.plannedOutfit,
          title: title,
          data: {'outfitId': entry.id, 'date': date, 'worn': false},
        ),
      );
    }
  }

  String details(MiraDocument document) {
    if (type == 'reschedule_event') {
      final event = document.find(referenceId);
      return 'Перенести ${event?.title ?? title}\nБыло: ${event?.text('start') ?? 'Недоступно'} — ${event?.text('end') ?? ''}\nБудет: $start — $end';
    }
    if (type == 'create_outfit') {
      return '$preview\nВещи: ${itemIds.map((id) => document.find(id)?.title ?? 'Вещь недоступна').join(', ')}';
    }
    if (type == 'plan_outfit') {
      final outfit = document.find(referenceId);
      return '$preview\nВещи: ${outfit?.ids('items').map((id) => document.find(id)?.title ?? 'Вещь недоступна').join(', ') ?? 'Образ недоступен'}';
    }
    if (type == 'plan_meal') {
      final source = document.find(referenceId);
      final slotName =
          {
            'breakfast': 'Завтрак',
            'lunch': 'Обед',
            'dinner': 'Ужин',
            'snack': 'Перекус',
          }[slot] ??
          slot;
      return '$slotName · $date\n${source?.title ?? 'Источник недоступен'} · $quantity ${source?.kind == Kind.food ? 'г' : 'порц.'}';
    }
    return preview;
  }

  String get preview => switch (type) {
    'reschedule_event' => 'Перенести событие «$title» · $date',
    'create_task' => 'Добавить задачу «$title» · $date',
    'plan_outfit' => 'Запланировать образ «$title» · $date',
    'create_outfit' =>
      'Сохранить образ «$title»${date.isEmpty ? '' : ' и запланировать на $date'}',
    'plan_meal' => 'Запланировать «$title» · $date · количество $quantity',
    _ => 'Неизвестное действие',
  };
}

class AiSuggestion {
  final String message;
  final List<AiAction> actions;
  AiSuggestion(this.message, this.actions);
}

class AiService {
  final SupabaseClient client;
  AiService(this.client);
  Future<AiSuggestion> ask(
    String question,
    String context,
    String date,
    MiraDocument document,
    Map<String, dynamic>? weather, {
    List<ChatMessage> history = const [],
  }) async {
    if (client.auth.currentUser == null) {
      throw StateError('Для MIRA AI войдите в аккаунт');
    }
    final response = await client.functions
        .invoke(
          'mira-ai',
          body: {
            'question': question,
            'context': context,
            'date': date,
            'document': {
              'schemaVersion': 1,
              'profile': document.profile,
              'entries': document.entries.map((e) => e.toJson()).toList(),
            },
            'history': history.map((m) => m.toHistory()).toList(),
            'weather': weather,
          },
        )
        .timeout(const Duration(seconds: 55));
    if (response.status != 200 || response.data is! Map) {
      throw StateError('MIRA AI временно недоступна');
    }
    final data = Map<String, dynamic>.from(response.data as Map);
    final actions = (data['actions'] as List? ?? [])
        .take(5)
        .map((a) => AiAction.fromJson(Map<String, dynamic>.from(a as Map)))
        .toList();
    return AiSuggestion(data['message'] as String, actions);
  }
}

String aiErrorMessage(Object error) {
  if (error is FormatException) return error.message;
  if (error is TimeoutException) {
    return 'MIRA не успела ответить. Повторите запрос.';
  }
  if (error is FunctionException) {
    return switch (error.status) {
      401 => 'Войдите в аккаунт заново.',
      403 =>
        'Адрес приложения не разрешён. Проверьте ALLOWED_ORIGINS в Supabase.',
      429 => 'Достигнут лимит запросов. Попробуйте позже.',
      502 =>
        'AI-провайдер не ответил. Проверьте баланс API и настройки модели.',
      503 => 'Сервис AI недоступен. Проверьте настройки серверной функции.',
      _ => 'Не удалось получить ответ. Проверьте интернет и повторите запрос.',
    };
  }
  return 'Не удалось получить ответ. Проверьте интернет и повторите запрос.';
}
