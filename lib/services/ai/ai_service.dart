import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/document.dart';
import '../../features/nutrition/nutrition_logic.dart';
import '../../shared/models/entry.dart';

class AiAction {
  final String type, title, date, referenceId, slot;
  final double quantity;
  AiAction({
    required this.type,
    required this.title,
    required this.date,
    this.referenceId = '',
    this.slot = 'dinner',
    this.quantity = 1,
  });
  factory AiAction.fromJson(Map<String, dynamic> json) => AiAction(
    type: json['type'] as String,
    title: json['title'] as String,
    date: json['date'] as String,
    referenceId: json['referenceId'] as String? ?? '',
    slot: json['slot'] as String? ?? 'dinner',
    quantity: (json['quantity'] as num?)?.toDouble() ?? 1,
  );
  Entry toEntry(MiraDocument document) {
    final parsed = DateTime.tryParse(date);
    if (parsed == null ||
        dayKey(parsed) != date ||
        parsed.year < 2000 ||
        parsed.year > 2100) {
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
          throw const FormatException('Образ уже удалён');
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

  String get preview => switch (type) {
    'create_task' => 'Добавить задачу «$title» · $date',
    'plan_outfit' => 'Запланировать образ «$title» · $date',
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
    Map<String, dynamic>? weather,
  ) async {
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
            'document': document.toJson(),
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
