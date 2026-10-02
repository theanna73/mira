import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../shared/models/entry.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/editor.dart';
import 'nutrition_logic.dart';
import 'recipe_editor.dart';

const mealSlots = {
  'breakfast': 'Завтрак',
  'lunch': 'Обед',
  'dinner': 'Ужин',
  'snack': 'Перекус',
};
Future<void> editFood(BuildContext context, [Entry? entry]) => sheet(
  context,
  EntryEditor(
    kind: Kind.food,
    heading: 'Продукт · на 100 г',
    entry: entry,
    fields: const [
      FieldSpec('calories', 'Ккал на 100 г', type: FieldType.number),
      FieldSpec('protein', 'Белки, г', type: FieldType.number),
      FieldSpec('fat', 'Жиры, г', type: FieldType.number),
      FieldSpec('carbs', 'Углеводы, г', type: FieldType.number),
      FieldSpec('notes', 'Источник данных / упаковка'),
    ],
    save: StoreScope.of(context).put,
  ),
);
Future<void> editMeal(
  BuildContext context,
  DateTime date, {
  bool plan = false,
  Entry? entry,
  Entry? source,
}) async {
  final store = StoreScope.of(context);
  final foods = [...store.of(Kind.food), ...store.of(Kind.recipe)];
  if (foods.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Сначала добавьте продукт или рецепт')),
    );
    return;
  }
  await sheet(
    context,
    EntryEditor(
      kind: plan ? Kind.mealPlan : Kind.meal,
      heading: plan ? 'План питания' : 'Приём пищи',
      entry: entry,
      defaults: {
        'title': source?.title ?? '',
        'date': dayKey(date),
        'slot': 'breakfast',
        if (source != null) 'sourceId': source.id,
        'quantity': source?.kind == Kind.recipe ? 1 : 100,
      },
      fields: [
        FieldSpec(
          'sourceId',
          'Продукт или рецепт',
          type: FieldType.choice,
          required: true,
          choices: {
            for (final e in foods)
              e.id: '${e.title} (${e.kind == Kind.food ? 'граммы' : 'порции'})',
          },
        ),
        const FieldSpec(
          'quantity',
          'Количество: граммы продукта / порции рецепта',
          type: FieldType.number,
          required: true,
        ),
        const FieldSpec('date', 'Дата', type: FieldType.date, required: true),
        const FieldSpec(
          'slot',
          'Приём пищи',
          type: FieldType.choice,
          required: true,
          choices: mealSlots,
        ),
      ],
      save: (e) async {
        final selected = store.document.find(e.text('sourceId'));
        if (selected == null) {
          throw const FormatException('Выбранный продукт удалён');
        }
        await store.put(
          e.copy(
            data: {
              ...e.data,
              ...nutritionSnapshot(selected, e.number('quantity')),
              'unit': selected.kind == Kind.food ? 'г' : 'порц.',
            },
          ),
        );
      },
    ),
  );
}

Future<void> editPantry(BuildContext context, [Entry? entry]) => sheet(
  context,
  EntryEditor(
    kind: Kind.pantry,
    heading: 'Продукты дома',
    entry: entry,
    fields: const [
      FieldSpec('amount', 'Количество', type: FieldType.number),
      FieldSpec(
        'unit',
        'Единица',
        type: FieldType.choice,
        choices: {'g': 'г', 'ml': 'мл', 'pc': 'шт'},
      ),
      FieldSpec('expiry', 'Годен до', type: FieldType.date),
      FieldSpec('notes', 'Заметки'),
    ],
    defaults: const {'unit': 'g'},
    save: StoreScope.of(context).put,
  ),
);

class NutritionPage extends StatefulWidget {
  const NutritionPage({super.key});
  @override
  State<NutritionPage> createState() => _NutritionPageState();
}

class _NutritionPageState extends State<NutritionPage> {
  String tab = 'diary';
  DateTime date = DateTime.now();
  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final mode = store.profile['nutritionMode'] as String? ?? 'planning';
    final totals = store.document.totals(date);
    final meals = store
        .of(Kind.meal)
        .where((e) => e.text('date') == dayKey(date))
        .toList();
    final plans = store
        .of(Kind.mealPlan)
        .where((e) => e.text('date') == dayKey(date))
        .toList();
    final water = store
        .of(Kind.water)
        .where((e) => e.text('date') == dayKey(date))
        .toList();
    final waterAmount = water.fold(0.0, (sum, e) => sum + e.number('amount'));
    Widget mealCard(Entry e, bool plan) => Card(
      child: ListTile(
        title: Text(e.title),
        subtitle: Text(
          '${mealSlots[e.text('slot')] ?? 'Приём пищи'} · ${e.number('quantity').toStringAsFixed(0)} ${e.text('unit')}',
        ),
        onTap: () => editMeal(context, date, plan: plan, entry: e),
        leading: plan
            ? IconButton(
                tooltip: 'Отметить как съеденное',
                icon: const Icon(Icons.restaurant),
                onPressed: () => perform(context, () => store.consumePlan(e)),
              )
            : const Icon(Icons.restaurant_outlined),
        trailing: IconButton(
          tooltip: 'Удалить запись',
          icon: const Icon(Icons.close),
          onPressed: () => perform(context, () => store.remove(e.id)),
        ),
      ),
    );
    return PageBody(
      title: 'Питание',
      subtitle: 'Планируй так, как удобно тебе',
      children: [
        Wrap(
          spacing: 8,
          children:
              {
                    'diary': 'Дневник',
                    'foods': 'Продукты',
                    'recipes': 'Рецепты',
                    'pantry': 'Дома',
                  }.entries
                  .map(
                    (e) => ChoiceChip(
                      label: Text(e.value),
                      selected: tab == e.key,
                      onSelected: (_) => setState(() => tab = e.key),
                    ),
                  )
                  .toList(),
        ),
        if (tab == 'diary') ...[
          Row(
            children: [
              IconButton(
                tooltip: 'Предыдущий день',
                onPressed: () => setState(
                  () => date = date.subtract(const Duration(days: 1)),
                ),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: TextButton(
                  onPressed: () async {
                    final v = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (v != null) {
                      setState(() => date = v);
                    }
                  },
                  child: Text(DateFormat('d MMMM', 'ru').format(date)),
                ),
              ),
              IconButton(
                tooltip: 'Следующий день',
                onPressed: () =>
                    setState(() => date = date.add(const Duration(days: 1))),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          if (mode == 'calories')
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${totals.calories.toStringAsFixed(0)} / ${store.profile['calorieGoal'] ?? 2000} ккал',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Белки ${totals.protein.toStringAsFixed(1)} г · Жиры ${totals.fat.toStringAsFixed(1)} г · Углеводы ${totals.carbs.toStringAsFixed(1)} г',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Цели задаются вручную. Данные продуктов вводятся с упаковки.',
                    ),
                  ],
                ),
              ),
            ),
          if (mode == 'balance')
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Приёмы пищи за день'),
                    Wrap(
                      spacing: 8,
                      children: mealSlots.entries
                          .map(
                            (s) => Chip(
                              avatar: Icon(
                                meals.any((e) => e.text('slot') == s.key)
                                    ? Icons.check_circle
                                    : Icons.circle_outlined,
                                size: 18,
                              ),
                              label: Text(s.value),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
          Section(
            'План на день',
            action: IconButton(
              tooltip: 'Запланировать питание',
              onPressed: () => editMeal(context, date, plan: true),
              icon: const Icon(Icons.add),
            ),
          ),
          if (plans.isEmpty)
            const EmptyCard(
              'Запланируйте приём пищи. Кнопка с тарелкой перенесёт его в дневник.',
            ),
          ...plans.map((e) => mealCard(e, true)),
          Section(
            'Съедено',
            action: IconButton(
              tooltip: 'Записать питание',
              onPressed: () => editMeal(context, date),
              icon: const Icon(Icons.add),
            ),
          ),
          if (meals.isEmpty) const EmptyCard('Пока нет записей за этот день'),
          ...meals.map((e) => mealCard(e, false)),
          const Section('Вода'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${waterAmount.toStringAsFixed(0)} / ${store.profile['waterGoal'] ?? 2000} мл',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final amount in [200, 250, 500])
                        OutlinedButton(
                          onPressed: () => perform(
                            context,
                            () => store.put(
                              Entry(
                                kind: Kind.water,
                                title: 'Вода',
                                data: {'date': dayKey(date), 'amount': amount},
                              ),
                            ),
                          ),
                          child: Text('+$amount мл'),
                        ),
                      if (water.isNotEmpty)
                        TextButton(
                          onPressed: () => perform(
                            context,
                            () => store.remove(water.last.id),
                          ),
                          child: const Text('Отменить последнюю'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        if (tab == 'foods') ...[
          Section(
            'Продукты',
            action: IconButton(
              tooltip: 'Добавить продукт',
              onPressed: () => editFood(context),
              icon: const Icon(Icons.add),
            ),
          ),
          if (store.of(Kind.food).isEmpty)
            const EmptyCard('Введите значения с упаковки на 100 г'),
          ...store
              .of(Kind.food)
              .map(
                (e) => Card(
                  child: ListTile(
                    title: Text(e.title),
                    subtitle: Text(
                      '${e.number('calories').toStringAsFixed(0)} ккал · Б ${e.number('protein')} · Ж ${e.number('fat')} · У ${e.number('carbs')} / 100 г',
                    ),
                    onTap: () => editFood(context, e),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'meal') {
                          await editMeal(context, date, source: e);
                        } else if (await confirm(
                              context,
                              'Удалить продукт?',
                              'Записи питания сохранят свои значения.',
                            ) &&
                            context.mounted) {
                          await perform(context, () => store.remove(e.id));
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'meal',
                          child: Text('Записать в дневник'),
                        ),
                        PopupMenuItem(value: 'delete', child: Text('Удалить')),
                      ],
                    ),
                  ),
                ),
              ),
        ],
        if (tab == 'recipes') ...[
          Section(
            'Рецепты',
            action: IconButton(
              tooltip: 'Добавить рецепт',
              onPressed: () => sheet(context, const RecipeEditor()),
              icon: const Icon(Icons.add),
            ),
          ),
          if (store.of(Kind.recipe).isEmpty)
            const EmptyCard('Соберите рецепт из своих продуктов'),
          ...store
              .of(Kind.recipe)
              .map(
                (e) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Порций: ${e.number('servings')} · ${e.number('calories').toStringAsFixed(0)} ккал на порцию',
                        ),
                        Text(
                          (e.data['ingredients'] as List? ?? [])
                              .map((i) => '${i['title']}: ${i['grams']} г')
                              .join('\n'),
                        ),
                        if (e.text('instructions').isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(e.text('instructions')),
                          ),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: () => editMeal(
                                context,
                                date,
                                plan: true,
                                source: e,
                              ),
                              child: const Text('В план'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  sheet(context, RecipeEditor(entry: e)),
                              child: const Text('Изменить'),
                            ),
                            IconButton(
                              tooltip: 'Удалить рецепт',
                              onPressed: () async {
                                if (await confirm(
                                      context,
                                      'Удалить рецепт?',
                                      e.title,
                                    ) &&
                                    context.mounted) {
                                  await perform(
                                    context,
                                    () => store.remove(e.id),
                                  );
                                }
                              },
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
        ],
        if (tab == 'pantry') ...[
          Section(
            'Продукты дома',
            action: IconButton(
              tooltip: 'Добавить запас',
              onPressed: () => editPantry(context),
              icon: const Icon(Icons.add),
            ),
          ),
          if (store.of(Kind.pantry).isEmpty)
            const EmptyCard('Добавьте продукты и сроки годности'),
          ...store
              .of(Kind.pantry)
              .map(
                (e) => Card(
                  child: ListTile(
                    title: Text(e.title),
                    subtitle: Text(
                      '${e.number('amount')} ${{'g': 'г', 'ml': 'мл', 'pc': 'шт'}[e.text('unit')] ?? ''}${e.text('expiry').isEmpty ? '' : '\nГоден до ${e.text('expiry')}'}',
                    ),
                    leading: Icon(
                      e.time('expiry')?.isBefore(DateTime.now()) == true
                          ? Icons.warning_amber
                          : Icons.kitchen_outlined,
                    ),
                    onTap: () => editPantry(context, e),
                    trailing: IconButton(
                      tooltip: 'Удалить запас',
                      icon: const Icon(Icons.close),
                      onPressed: () =>
                          perform(context, () => store.remove(e.id)),
                    ),
                  ),
                ),
              ),
        ],
      ],
    );
  }
}
