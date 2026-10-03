import '../../services/database/document.dart';
import '../../shared/models/entry.dart';

Map<String, dynamic> nutritionSnapshot(Entry source, double quantity) {
  if (!quantity.isFinite || quantity <= 0) {
    throw const FormatException('Количество должно быть больше нуля');
  }
  final factor = source.kind == Kind.food ? quantity / 100 : quantity;
  return {
    if (source.data['nutritionKnown'] == false) 'nutritionKnown': false,
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

/// A recipe can contain a named ingredient whose nutritional data is unknown.
/// Never turn missing nutrition into a claimed zero-calorie meal.
Entry makeSuggestedRecipe(
  String title,
  double servings,
  List<Map<String, dynamic>> ingredients,
  String instructions,
  MiraDocument document, {
  String? id,
}) {
  if (!servings.isFinite ||
      servings <= 0 ||
      servings > 1000 ||
      ingredients.isEmpty ||
      ingredients.length > 30 ||
      instructions.trim().isEmpty ||
      instructions.length > 5000) {
    throw const FormatException(
      'Укажите состав, порции и способ приготовления',
    );
  }
  final snapshots = <Map<String, dynamic>>[];
  var total = const NutritionTotals();
  var known = true;
  for (final ingredient in ingredients) {
    final foodId = ingredient['foodId']?.toString() ?? '';
    final name = ingredient['title']?.toString().trim() ?? '';
    final grams = (ingredient['grams'] as num?)?.toDouble() ?? 0;
    if (name.isEmpty ||
        name.length > 300 ||
        !grams.isFinite ||
        grams <= 0 ||
        grams > 100000) {
      throw const FormatException('Некорректный ингредиент');
    }
    final food = document.find(foodId);
    if (foodId.isNotEmpty && food?.kind != Kind.food) {
      throw const FormatException('Продукт из предложения больше не доступен');
    }
    final nutritionKnown =
        food != null &&
        [
          'calories',
          'protein',
          'fat',
          'carbs',
        ].every((k) => food.data[k] is num);
    known = known && nutritionKnown;
    final snapshot = nutritionKnown
        ? nutritionSnapshot(food, grams)
        : <String, dynamic>{};
    if (nutritionKnown) {
      total =
          total +
          NutritionTotals.fromEntry(
            Entry(kind: Kind.food, title: name, data: snapshot),
          );
    }
    snapshots.add({
      'foodId': foodId,
      'title': food?.title ?? name,
      'grams': grams,
      'nutritionKnown': nutritionKnown,
      ...snapshot,
    });
  }
  return Entry(
    id: id,
    kind: Kind.recipe,
    title: title,
    data: {
      'servings': servings,
      'ingredients': snapshots,
      'instructions': instructions,
      'nutritionKnown': known,
      if (known) ...{
        'calories': total.calories / servings,
        'protein': total.protein / servings,
        'fat': total.fat / servings,
        'carbs': total.carbs / servings,
      },
    },
  );
}
