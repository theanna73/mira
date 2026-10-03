import '../../services/database/document.dart';
import '../../shared/models/entry.dart';

const nutritionKeys = ['calories', 'protein', 'fat', 'carbs'];

bool completeNutrition(Entry source) => nutritionKeys.every((key) {
  final value = source.data[key];
  return value is num && value.isFinite && value >= 0;
});

bool knownNutrition(Entry source) =>
    source.data['nutritionKnown'] != false && completeNutrition(source);

Map<String, dynamic> nutritionSnapshot(Entry source, double quantity) {
  if (!quantity.isFinite || quantity <= 0) {
    throw const FormatException('Количество должно быть больше нуля');
  }
  final factor = source.kind == Kind.food ? quantity / 100 : quantity;
  final known = knownNutrition(source);
  final values = {
    for (final key in nutritionKeys)
      key: known ? source.number(key) * factor : 0.0,
  };
  if (values.values.any((value) => !value.isFinite)) {
    throw const FormatException('Слишком большое количество или значение БЖУ');
  }
  return {'nutritionKnown': known, ...values};
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
  var known = true;
  final snapshots = <Map<String, dynamic>>[];
  for (final ingredient in ingredients) {
    final food = document.find(ingredient['foodId'] as String);
    if (food?.kind != Kind.food) {
      throw const FormatException('Продукт уже удалён');
    }
    final grams = (ingredient['grams'] as num).toDouble();
    final snapshot = nutritionSnapshot(food!, grams);
    known = known && snapshot['nutritionKnown'] == true;
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
      'nutritionKnown': known,
      if (known) ...{
        'calories': totals.calories / servings,
        'protein': totals.protein / servings,
        'fat': totals.fat / servings,
        'carbs': totals.carbs / servings,
      },
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
    final nutritionKnown = food != null && knownNutrition(food);
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
