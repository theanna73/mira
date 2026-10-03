import 'package:flutter/material.dart';
import '../../shared/models/entry.dart';
import '../../shared/widgets/common.dart';
import 'nutrition_logic.dart';
import '../../services/nutrition/food_catalog.dart';
import 'food_catalog_picker.dart';

class RecipeEditor extends StatefulWidget {
  final Entry? entry;
  const RecipeEditor({super.key, this.entry});
  @override
  State<RecipeEditor> createState() => _RecipeEditorState();
}

class _RecipeEditorState extends State<RecipeEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController title, servings, instructions;
  final ingredients = <Map<String, dynamic>>[];
  bool saving = false;
  String? ownerScope;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ownerScope ??= StoreScope.of(context).scope;
  }

  @override
  void initState() {
    super.initState();
    title = TextEditingController(text: widget.entry?.title ?? '');
    servings = TextEditingController(
      text: (widget.entry?.number('servings') ?? 1).toString(),
    );
    instructions = TextEditingController(
      text: widget.entry?.text('instructions') ?? '',
    );
    for (final i in widget.entry?.data['ingredients'] as List? ?? []) {
      ingredients.add({
        'foodId': i['foodId'] ?? '',
        'title': i['title'] ?? '',
        'controller': TextEditingController(text: i['grams'].toString()),
      });
    }
  }

  @override
  void dispose() {
    title.dispose();
    servings.dispose();
    instructions.dispose();
    for (final i in ingredients) {
      (i['controller'] as TextEditingController).dispose();
    }
    super.dispose();
  }

  String? positive(String? raw) {
    final n = double.tryParse((raw ?? '').replaceAll(',', '.'));
    return n == null || !n.isFinite || n <= 0 || n > 100000
        ? 'Введите положительное число до 100 000'
        : null;
  }

  Future<void> save() async {
    if (ownerScope != StoreScope.of(context).scope) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Аккаунт изменился. Откройте форму заново.'),
        ),
      );
      return;
    }
    if (!form.currentState!.validate()) {
      return;
    }
    setState(() => saving = true);
    final store = StoreScope.of(context);
    try {
      await store.mutate((document) {
        final rows = ingredients.map((i) {
          final catalogFood = i['catalogFood'];
          final food = catalogFood is CatalogFood
              ? catalogFood.forDocument(document)
              : document.find(i['foodId'] ?? '');
          if (catalogFood is CatalogFood) {
            if (food == null) throw const FormatException('Продукт не найден');
            if (document.find(food.id) == null) document.put(food);
          }
          return <String, dynamic>{
            'foodId': food?.id ?? i['foodId'] ?? '',
            'title': food?.title ?? i['title'] ?? '',
            'grams': double.parse(
              (i['controller'] as TextEditingController).text.replaceAll(
                ',',
                '.',
              ),
            ),
          };
        }).toList();
        document.put(
          makeSuggestedRecipe(
            title.text.trim(),
            double.parse(servings.text.replaceAll(',', '.')),
            rows,
            instructions.text.trim(),
            document,
            id: widget.entry?.id,
          ),
        );
      });
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is FormatException ? e.message : e.toString()),
          ),
        );
      }
    }
    if (mounted) {
      setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final foods = StoreScope.of(context).of(Kind.food);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .86,
      child: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Рецепт', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            TextFormField(
              controller: title,
              maxLength: 300,
              decoration: const InputDecoration(labelText: 'Название'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Введите название' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: servings,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Количество порций'),
              validator: positive,
            ),
            const Section('Ингредиенты'),
            if (foods.isEmpty)
              const Text(
                'Выбери ингредиенты из справочника или добавь свои продукты.',
              ),
            ...ingredients.map(
              (i) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  children: [
                    if (i['catalogFood'] == null &&
                        (i['title']?.toString().isNotEmpty ?? false))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(i['title'].toString()),
                      ),
                    if (i['catalogFood'] is CatalogFood)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text((i['catalogFood'] as CatalogFood).title),
                        subtitle: const Text('USDA · значения на 100 г'),
                      )
                    else
                      DropdownButtonFormField<String>(
                        initialValue: foods.any((e) => e.id == i['foodId'])
                            ? i['foodId']
                            : null,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Продукт'),
                        items: foods
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.id,
                                child: Text(e.title),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => i['foodId'] = v,
                        validator: (v) =>
                            v == null &&
                                (i['title']?.toString().isEmpty ?? true)
                            ? 'Выберите продукт'
                            : null,
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: i['controller'],
                            decoration: const InputDecoration(
                              labelText: 'Граммы',
                            ),
                            keyboardType: TextInputType.number,
                            validator: positive,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Убрать ингредиент',
                          onPressed: () => setState(() {
                            (i['controller'] as TextEditingController)
                                .dispose();
                            ingredients.remove(i);
                          }),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            TextButton.icon(
              onPressed: foods.isEmpty
                  ? null
                  : () => setState(
                      () => ingredients.add({
                        'foodId': foods.first.id,
                        'controller': TextEditingController(text: '100'),
                      }),
                    ),
              icon: const Icon(Icons.add),
              label: const Text('Добавить ингредиент'),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.search),
              label: const Text('Ингредиент из справочника'),
              onPressed: saving
                  ? null
                  : () async {
                      final food = await sheet<CatalogFood>(
                        context,
                        const FoodCatalogPicker(),
                      );
                      if (food == null || !mounted) return;
                      if (ownerScope != StoreScope.of(context).scope) return;
                      setState(
                        () => ingredients.add({
                          'catalogFood': food,
                          'title': food.title,
                          'controller': TextEditingController(text: '100'),
                        }),
                      );
                    },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: instructions,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(labelText: 'Как приготовить'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: saving ? null : save,
              child: Text(saving ? 'Сохранение…' : 'Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
}
