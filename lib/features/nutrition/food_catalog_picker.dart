import 'package:flutter/material.dart';
import '../../services/nutrition/food_catalog.dart';

class FoodCatalogPicker extends StatefulWidget {
  const FoodCatalogPicker({super.key});
  @override
  State<FoodCatalogPicker> createState() => _FoodCatalogPickerState();
}

class _FoodCatalogPickerState extends State<FoodCatalogPicker> {
  late Future<FoodCatalog> catalog = FoodCatalog.load();
  String query = '';
  CatalogFood? selected;

  String number(double value) => value.toStringAsFixed(1).replaceAll('.', ',');
  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .86,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Справочник продуктов',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              IconButton(
                tooltip: 'Закрыть справочник',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const Text('USDA SR Legacy · на 100 г · выпуск 2018'),
          const SizedBox(height: 16),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Найти ингредиент',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) => setState(() {
              query = value;
              selected = null;
            }),
          ),
          const SizedBox(height: 12),
          const Text('Выбери нужный вариант: сырой, сухой или приготовленный.'),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<FoodCatalog>(
              future: catalog,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: TextButton(
                      onPressed: () =>
                          setState(() => catalog = FoodCatalog.load()),
                      child: const Text(
                        'Не удалось открыть справочник. Повторить',
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final foods = snapshot.data!.search(query);
                if (foods.isEmpty) {
                  return const Center(
                    child: Text(
                      'В этом справочнике нет такого продукта. Можно добавить значения с упаковки вручную.',
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: foods.length,
                  itemBuilder: (context, index) {
                    final food = foods[index];
                    final active = selected?.fdcId == food.fdcId;
                    return Card(
                      child: ListTile(
                        selected: active,
                        title: Text(food.title),
                        subtitle: Text(
                          '${number(food.nutrition['calories']!)} ккал\n'
                          'Б ${number(food.nutrition['protein']!)} · Ж ${number(food.nutrition['fat']!)} · У ${number(food.nutrition['carbs']!)}',
                        ),
                        trailing: Icon(
                          active
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                        ),
                        onTap: () => setState(() => selected = food),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            selected == null
                ? 'Справочные значения. Для упакованного продукта сверяйся с этикеткой.'
                : 'Источник: USDA · ${selected!.release} · FDC ${selected!.fdcId}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: selected == null
                  ? null
                  : () => Navigator.pop(context, selected),
              child: const Text('Выбрать продукт'),
            ),
          ),
        ],
      ),
    ),
  );
}
