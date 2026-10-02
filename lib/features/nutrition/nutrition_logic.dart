import '../../services/database/document.dart';
import '../../shared/models/entry.dart';

Map<String, dynamic> nutritionSnapshot(Entry source, double quantity) {
  if (!quantity.isFinite || quantity <= 0) {
    throw const FormatException('Количество должно быть больше нуля');
  }
  final factor = source.kind == Kind.food ? quantity / 100 : quantity;
  return {
    for (final key in ['calories', 'protein', 'fat', 'carbs'])
      key: source.number(key) * factor,
  };
}

Entry makeRecipe(
  String title,
  double servings,
  List<Map<String, dynamic>> ingredients,
  String instructions,
  MiraDocument document, {
  String? id,
}) {
  if (!servings.isFinite || servings <= 0 || ingredients.isEmpty) {
    throw const FormatException('Укажите порции и хотя бы один ингредиент');
  }
  var totals = const NutritionTotals();
  final snapshots = <Map<String, dynamic>>[];
  for (final ingredient in ingredients) {
    final food = document.find(ingredient['foodId'] as String);
    if (food?.kind != Kind.food) {
      throw const FormatException('Продукт уже удалён');
    }
    final grams = (ingredient['grams'] as num).toDouble();
    final snapshot = nutritionSnapshot(food!, grams);
    totals =
        totals +
        NutritionTotals.fromEntry(
          Entry(kind: Kind.food, title: food.title, data: snapshot),
        );
    snapshots.add({...ingredient, 'title': food.title, ...snapshot});
  }
  return Entry(
    id: id,
    kind: Kind.recipe,
    title: title,
    data: {
      'servings': servings,
      'ingredients': snapshots,
      'instructions': instructions,
      'calories': totals.calories / servings,
      'protein': totals.protein / servings,
      'fat': totals.fat / servings,
      'carbs': totals.carbs / servings,
    },
  );
}
