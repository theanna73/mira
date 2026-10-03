import 'dart:convert';
import '../ai/chat_message.dart';
import '../../shared/models/entry.dart';

class MiraDocument {
  final Map<String, dynamic> profile;
  final List<Entry> entries;
  final List<ChatMessage> chat;
  MiraDocument({
    Map<String, dynamic>? profile,
    List<Entry>? entries,
    List<ChatMessage>? chat,
  }) : profile =
           profile ??
           {
             'name': '',
             'modules': ['planner', 'style', 'nutrition'],
             'nutritionMode': 'planning',
             'waterGoal': 2000,
             'calorieGoal': 2000,
             'onboarded': false,
           },
       entries = entries ?? [],
       chat = chat ?? [];
  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'profile': profile,
    'entries': entries.map((e) => e.toJson()).toList(),
    'chat': chat.map((m) => m.toJson()).toList(),
  };
  factory MiraDocument.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Неподдерживаемая версия данных');
    }
    return MiraDocument(
      profile: Map<String, dynamic>.from(json['profile'] as Map),
      chat: (json['chat'] as List? ?? [])
          .map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m as Map)))
          .toList(),
      entries: (json['entries'] as List)
          .map((e) => Entry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
  MiraDocument clone() => MiraDocument.fromJson(
    jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>,
  );
  bool sameContent(MiraDocument other) => _sameValue(toJson(), other.toJson());

  static bool _sameValue(Object? a, Object? b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every(
            (key) => b.containsKey(key) && _sameValue(a[key], b[key]),
          );
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_sameValue(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  void addMessage(ChatMessage message) {
    chat.add(message);
    if (chat.length > 60) chat.removeRange(0, chat.length - 60);
  }

  List<Entry> of(Kind kind) => entries.where((e) => e.kind == kind).toList();
  Entry? find(String id) {
    for (final e in entries) {
      if (e.id == id) {
        return e;
      }
    }
    return null;
  }

  void put(Entry e) {
    validate(e);
    if (e.kind == Kind.plannedOutfit &&
        e.flag('worn') &&
        find(e.id)?.flag('worn') != true) {
      e = e.copy(
        data: {
          ...e.data,
          'wornItems':
              find(e.text('outfitId'))?.ids('items') ?? e.ids('wornItems'),
        },
      );
    }
    entries.removeWhere((v) => v.id == e.id);
    entries.add(e);
  }

  void validate(Entry e) {
    if (e.title.trim().isEmpty || e.title.length > 300) {
      throw const FormatException('Введите название до 300 символов');
    }
    void ref(String key, Set<Kind> kinds) {
      final id = e.text(key);
      if (id.isNotEmpty && !kinds.contains(find(id)?.kind)) {
        throw const FormatException('Связанный объект уже удалён');
      }
    }

    if (e.kind == Kind.outfit) {
      for (final id in e.ids('items')) {
        if (find(id)?.kind != Kind.wardrobe) {
          throw const FormatException('Вещь уже удалена');
        }
      }
    }
    if (e.kind == Kind.plannedOutfit) {
      ref('outfitId', {Kind.outfit});
    }
    if (e.kind == Kind.listItem) {
      ref('listId', {Kind.shoppingList});
    }
    if (e.kind == Kind.habitLog) {
      ref('habitId', {Kind.habit});
    }
    if (e.kind == Kind.meal || e.kind == Kind.mealPlan) {
      ref('sourceId', {Kind.food, Kind.recipe});
    }
    for (final key in ['expiry', 'opened', 'lastDone']) {
      if (e.text(key).isNotEmpty) {
        final date = e.time(key);
        if (date == null ||
            dayKey(date) != e.text(key) ||
            date.year < 2000 ||
            date.year > 2100) {
          throw const FormatException('Некорректная дата');
        }
      }
    }
    if (e.number('openMonths') > 120 || e.number('openMonths') % 1 != 0) {
      throw const FormatException(
        'Срок после открытия: целое число от 0 до 120 месяцев',
      );
    }
    for (final key in [
      'calories',
      'protein',
      'fat',
      'carbs',
      'grams',
      'amount',
      'price',
      'servings',
      'openMonths',
      'notifyDays',
      'intervalDays',
    ]) {
      if (e.data.containsKey(key) &&
          (!e.number(key).isFinite || e.number(key) < 0)) {
        throw const FormatException('Числа должны быть неотрицательными');
      }
    }
  }

  void remove(String id) {
    final removed = find(id);
    entries.removeWhere(
      (e) =>
          e.id == id ||
          (e.text('outfitId') == id && !e.flag('worn')) ||
          e.text('habitId') == id ||
          e.text('listId') == id,
    );
    if (removed?.kind == Kind.outfit) {
      for (final planned in of(
        Kind.plannedOutfit,
      ).where((e) => e.text('outfitId') == id).toList()) {
        put(
          planned.copy(
            data: {
              ...planned.data,
              'outfitId': '',
              'wornItems': planned.data.containsKey('wornItems')
                  ? planned.ids('wornItems')
                  : removed!.ids('items'),
            },
          ),
        );
      }
    }
    if (removed?.kind == Kind.wardrobe) {
      for (final outfit in of(Kind.outfit)) {
        put(
          outfit.copy(
            data: {
              ...outfit.data,
              'items': outfit.ids('items').where((v) => v != id).toList(),
            },
          ),
        );
      }
    }
    if (removed?.kind == Kind.food) {
      for (final recipe in of(Kind.recipe)) {
        final rows = recipe.data['ingredients'] as List? ?? [];
        if (!rows.any((row) => row['foodId'] == id)) continue;
        put(
          recipe.copy(
            data: {
              ...recipe.data,
              'ingredients': rows
                  .map(
                    (row) => <String, dynamic>{
                      ...Map<String, dynamic>.from(row as Map),
                      if (row['foodId'] == id) ...{
                        'foodId': '',
                        'title': row['title'] ?? removed!.title,
                      },
                    },
                  )
                  .toList(),
            },
          ),
        );
      }
    }
    // Meal history keeps its nutritional snapshot when its source is deleted.
    for (final meal in [...of(Kind.meal), ...of(Kind.mealPlan)]) {
      if (meal.text('sourceId') == id) {
        put(meal.copy(data: {...meal.data, 'sourceId': ''}));
      }
    }
  }

  NutritionTotals totals(DateTime date) => of(Kind.meal)
      .where(
        (e) =>
            e.text('date') == dayKey(date) && e.data['nutritionKnown'] != false,
      )
      .fold(
        const NutritionTotals(),
        (total, e) => total + NutritionTotals.fromEntry(e),
      );
  int wears(String wardrobeId) => of(Kind.plannedOutfit)
      .where(
        (e) =>
            e.flag('worn') &&
            (e.data.containsKey('wornItems')
                ? e.ids('wornItems').contains(wardrobeId)
                : (find(
                        e.text('outfitId'),
                      )?.ids('items').contains(wardrobeId) ??
                      false)),
      )
      .length;
  double? costPerWear(Entry item) {
    final n = wears(item.id);
    return n == 0 ? null : item.number('price') / n;
  }
}
