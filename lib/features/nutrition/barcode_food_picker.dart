import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/nutrition/barcode_food.dart';

typedef BarcodeLookup = Future<BarcodeFood> Function(String code);

Future<BarcodeFood> lookupBarcode(String code) async {
  final client = Supabase.instance.client;
  if (client.auth.currentUser == null) {
    throw StateError('Для поиска войди в аккаунт.');
  }
  final result = await client.functions
      .invoke('food-lookup', body: {'code': code})
      .timeout(const Duration(seconds: 15));
  return BarcodeFood.fromJson(
    Map<String, dynamic>.from((result.data as Map)['food'] as Map),
  );
}

class BarcodeFoodPicker extends StatefulWidget {
  final BarcodeLookup? lookup;
  const BarcodeFoodPicker({super.key, this.lookup});
  @override
  State<BarcodeFoodPicker> createState() => _BarcodeFoodPickerState();
}

class _BarcodeFoodPickerState extends State<BarcodeFoodPicker> {
  final controller = TextEditingController();
  BarcodeFood? food;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> search() async {
    final code = controller.text.trim();
    if (!validBarcode(code)) {
      setState(() {
        food = null;
        error = 'Проверь цифры штрихкода на упаковке.';
      });
      return;
    }
    setState(() {
      busy = true;
      food = null;
      error = null;
    });
    try {
      final found = await (widget.lookup ?? lookupBarcode)(code);
      if (mounted) {
        setState(() => food = found);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FunctionException
              ? switch (e.status) {
                  401 => 'Войди в аккаунт заново.',
                  404 =>
                    'В базе нет этого продукта. Добавь БЖУ с упаковки вручную.',
                  422 =>
                    'Нет полных данных на 100 г. Добавь БЖУ с упаковки вручную.',
                  429 => 'Поиск временно ограничен. Попробуй через минуту.',
                  _ => 'Не удалось найти продукт. Проверь интернет и повтори.',
                }
              : e is StateError
              ? e.message.toString()
              : 'Не удалось найти продукт. Проверь интернет и повтори.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .86,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Продукт по штрихкоду',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Закрыть',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const Text(
                    'Введи цифры с упаковки. Поиск в Open Food Facts.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    enabled: !busy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Штрихкод',
                      prefixIcon: Icon(Icons.qr_code),
                    ),
                    onSubmitted: busy ? null : (_) => search(),
                    onChanged: (_) => setState(() {
                      food = null;
                      error = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: busy ? null : search,
                    icon: const Icon(Icons.search),
                    label: Text(busy ? 'Ищем продукт…' : 'Найти продукт'),
                  ),
                  if (busy) const LinearProgressIndicator(),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(error!),
                    ),
                  if (food != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              food!.title,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            if (food!.brand.isNotEmpty) Text(food!.brand),
                            const SizedBox(height: 12),
                            const Text('На 100 г'),
                            Text(
                              '${food!.nutrition['calories']} ккал\nБ ${food!.nutrition['protein']} · Ж ${food!.nutrition['fat']} · У ${food!.nutrition['carbs']}',
                            ),
                          ],
                        ),
                      ),
                    ),
                  const Spacer(),
                  const Text(
                    'Источник: Open Food Facts · ODbL. Данные заполняет сообщество — сверь БЖУ с этикеткой. Напитки пока добавляй вручную по весу.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: food == null || busy
                          ? null
                          : () => Navigator.pop(context, food),
                      child: const Text('Добавить продукт'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
