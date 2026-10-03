import 'package:uuid/uuid.dart';

enum Kind {
  event,
  task,
  habit,
  habitLog,
  wardrobe,
  outfit,
  plannedOutfit,
  wishlist,
  food,
  recipe,
  meal,
  mealPlan,
  pantry,
  water,
  supply,
  shoppingList,
  listItem,
  routine,
}

/// A versioned, extensible record. Relationships always store IDs, never copies.
class Entry {
  final String id;
  final Kind kind;
  final String title;
  final Map<String, dynamic> data;
  Entry({
    String? id,
    required this.kind,
    required this.title,
    Map<String, dynamic>? data,
  }) : id = id ?? const Uuid().v4(),
       data = Map.unmodifiable(data ?? {});
  String text(String key, [String fallback = '']) =>
      data[key]?.toString() ?? fallback;
  double number(String key, [double fallback = 0]) =>
      (data[key] as num?)?.toDouble() ?? fallback;
  bool flag(String key) => data[key] == true;
  List<String> ids(String key) => (data[key] as List? ?? []).cast<String>();
  DateTime? time(String key) => DateTime.tryParse(text(key));
  Entry copy({String? title, Map<String, dynamic>? data}) => Entry(
    id: id,
    kind: kind,
    title: title ?? this.title,
    data: data ?? this.data,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'title': title,
    'data': data,
  };
  factory Entry.fromJson(Map<String, dynamic> json) => Entry(
    id: json['id'] as String,
    kind: Kind.values.byName(json['kind'] as String),
    title: json['title'] as String,
    data: Map<String, dynamic>.from(json['data'] as Map),
  );
}

String dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
bool sameDay(DateTime? a, DateTime b) => a != null && dayKey(a) == dayKey(b);

class NutritionTotals {
  final double calories, protein, fat, carbs;
  const NutritionTotals({
    this.calories = 0,
    this.protein = 0,
    this.fat = 0,
    this.carbs = 0,
  });
  NutritionTotals operator +(NutritionTotals other) => NutritionTotals(
    calories: calories + other.calories,
    protein: protein + other.protein,
    fat: fat + other.fat,
    carbs: carbs + other.carbs,
  );
  factory NutritionTotals.fromEntry(Entry e, [double factor = 1]) =>
      NutritionTotals(
        calories: e.number('calories') * factor,
        protein: e.number('protein') * factor,
        fat: e.number('fat') * factor,
        carbs: e.number('carbs') * factor,
      );
}

// Display formatting only; storage and API dates remain ISO.
String displayDate(String value, {bool includeTime = false}) {
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  String two(int value) => value.toString().padLeft(2, '0');
  final label =
      '${two(date.day)}/${two(date.month)}/${date.year.toString().padLeft(4, '0')}';
  return includeTime ? '$label, ${two(date.hour)}:${two(date.minute)}' : label;
}
