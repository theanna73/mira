import 'package:flutter/material.dart';
import '../../services/database/document.dart';
import '../../services/nutrition/food_catalog.dart';
import '../../shared/models/entry.dart';
import 'nutrition_logic.dart';

/// Catalogue choices stay staged until the meal and product can be saved together.
class MealFoodChoice {
  final Entry food;
  final CatalogFood? catalogFood;
  final double quantity;
  const MealFoodChoice(this.food, this.quantity, [this.catalogFood]);

  void saveTo(MiraDocument document, DateTime date, String slot) {
    final source = catalogFood?.forDocument(document) ?? document.find(food.id);
    if (source == null) {
      throw const FormatException('Продукт уже удалён');
    }
    final snapshot = nutritionSnapshot(source, quantity);
    if (document.find(source.id) == null) {
      document.put(source);
    }
    document.put(
      Entry(
        kind: Kind.meal,
        title: source.title,
        data: {
          'date': dayKey(date),
          'slot': slot,
          'sourceId': source.id,
          'quantity': quantity,
          'unit': source.kind == Kind.recipe ? 'порц.' : 'г',
          ...snapshot,
        },
      ),
    );
  }
}

class MealFoodPicker extends StatefulWidget {
  final String title;
  final List<Entry> foods;
  final Future<FoodCatalog>? catalog;
  const MealFoodPicker({
    super.key,
    required this.title,
    required this.foods,
    this.catalog,
  });
  @override
  State<MealFoodPicker> createState() => _MealFoodPickerState();
}

class _MealFoodPickerState extends State<MealFoodPicker> {
  late final Future<FoodCatalog> catalog = widget.catalog ?? FoodCatalog.load();
  final amount = TextEditingController(text: '100');
  String query = '';
  Entry? selected;
  CatalogFood? selectedCatalog;
  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  double get quantity => double.tryParse(amount.text.replaceAll(',', '.')) ?? 0;
  bool get valid =>
      quantity.isFinite &&
      quantity > 0 &&
      (selected == null ||
          !knownNutrition(selected!) ||
          nutritionKeys.every(
            (key) =>
                (selected!.number(key) *
                        (selected!.kind == Kind.recipe
                            ? quantity
                            : quantity / 100))
                    .isFinite,
          ));
  void choose(Entry food, [CatalogFood? catalogFood]) {
    setState(() {
      selected = food;
      selectedCatalog = catalogFood;
      amount.text = food.kind == Kind.recipe ? '1' : '100';
    });
  }

  String number(double value) => value.toStringAsFixed(1).replaceAll('.', ',');
  Widget result(Entry food, [CatalogFood? catalogFood]) => Card(
    child: ListTile(
      title: Text(food.title),
      subtitle: Text(
        '${knownNutrition(food) ? '${number(food.number('calories'))} ккал' : 'БЖУ неизвестны'} · ${food.kind == Kind.recipe ? '1 порция' : '100 г'}\n${catalogFood != null
            ? 'USDA FoodData Central'
            : food.kind == Kind.recipe
            ? 'Мой рецепт'
            : 'Мой продукт'}',
      ),
      trailing: const Icon(Icons.add_circle_outline),
      onTap: () => choose(food, catalogFood),
    ),
  );
  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .86,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              IconButton(
                tooltip: 'Закрыть поиск еды',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          if (selected == null) ...[
            TextField(
              decoration: const InputDecoration(
                labelText: 'Найти продукт или рецепт',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => query = value),
            ),
            const SizedBox(height: 12),
            const Text(
              'Мои продукты, рецепты и USDA · выпуск 2018. Часть названий на английском.',
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<FoodCatalog>(
                future: catalog,
                builder: (context, snapshot) {
                  final terms = FoodCatalog.normalize(
                    query,
                  ).split(' ').where((s) => s.isNotEmpty);
                  final own = widget.foods.where((food) {
                    final words = FoodCatalog.normalize(food.title).split(' ');
                    return terms.every(
                      (term) => words.any((word) => word.startsWith(term)),
                    );
                  }).toList();
                  final savedIds = widget.foods
                      .map(
                        (food) =>
                            (food.data['nutritionSource'] as Map?)?['fdcId'],
                      )
                      .toSet();
                  final found =
                      snapshot.data
                          ?.search(query)
                          .where((food) => !savedIds.contains(food.fdcId))
                          .toList() ??
                      <CatalogFood>[];
                  return ListView.builder(
                    itemCount: own.length + found.length + 1,
                    itemBuilder: (context, index) {
                      if (index < own.length) return result(own[index]);
                      if (index < own.length + found.length) {
                        final food = found[index - own.length];
                        return result(food.toEntry(), food);
                      }
                      return Column(
                        children: [
                          if (snapshot.connectionState != ConnectionState.done)
                            const Padding(
                              padding: EdgeInsets.all(20),
                              child: LinearProgressIndicator(),
                            ),
                          if (snapshot.hasError)
                            const Text(
                              'Справочник недоступен. Можно выбрать сохранённые продукты.',
                            ),
                          if (snapshot.connectionState ==
                                  ConnectionState.done &&
                              own.isEmpty &&
                              found.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(20),
                              child: Text(
                                'Ничего не найдено. Добавь продукт с этикетки в разделе «Продукты».',
                              ),
                            ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ] else ...[
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextButton.icon(
                      onPressed: () => setState(() {
                        selected = null;
                        selectedCatalog = null;
                      }),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Другой продукт'),
                    ),
                    Text(
                      selected!.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: amount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: selected!.kind == Kind.recipe
                            ? 'Количество порций'
                            : 'Вес, г',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    if (!valid) const Text('Укажи количество больше нуля.'),
                    if (valid && knownNutrition(selected!))
                      Builder(
                        builder: (context) {
                          final factor = selected!.kind == Kind.recipe
                              ? quantity
                              : quantity / 100;
                          return Text(
                            '${number(selected!.number('calories') * factor)} ккал\nБ ${number(selected!.number('protein') * factor)} · Ж ${number(selected!.number('fat') * factor)} · У ${number(selected!.number('carbs') * factor)} г',
                          );
                        },
                      ),
                    if (!knownNutrition(selected!))
                      const Text(
                        'БЖУ неизвестны. Запись сохранится, но не войдёт в итоги калорий.',
                      ),
                    if (selectedCatalog != null)
                      const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: Text(
                          'Источник: USDA FoodData Central. Проверь сырой или приготовленный вариант.',
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: valid
                    ? () => Navigator.pop(
                        context,
                        MealFoodChoice(selected!, quantity, selectedCatalog),
                      )
                    : null,
                child: const Text('Записать в дневник'),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
