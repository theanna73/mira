import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mira/app/theme.dart';
import 'package:mira/features/nutrition/barcode_food_picker.dart';
import 'package:mira/services/nutrition/barcode_food.dart';
import 'package:mira/services/database/document.dart';

Map<String, dynamic> product() => {
  'code': '3017624010701',
  'title': 'Тестовый продукт',
  'brand': 'Пример',
  'modified': '1',
  'basisGrams': 100,
  'calories': 100,
  'protein': 2,
  'fat': 0,
  'carbs': 23,
};
void main() {
  test('GTIN validates check digits without losing leading zeros', () {
    expect(validBarcode('0034000470693'), isTrue);
    expect(validBarcode('034000470693'), isTrue);
    expect(validBarcode('3017624010701'), isTrue);
    for (final value in ['3017624010702', '1234', 'https://example.org']) {
      expect(validBarcode(value), isFalse);
    }
  });
  test('missing macros or incorrect bases never become known zero', () {
    for (final change in <void Function(Map<String, dynamic>)>[
      (d) => d.remove('fat'),
      (d) => d['fat'] = -1,
      (d) => d['basisGrams'] = 1,
      (d) => d['calories'] = double.nan,
    ]) {
      final d = product();
      change(d);
      expect(() => BarcodeFood.fromJson(d), throwsFormatException);
    }
    expect(BarcodeFood.fromJson(product()).nutrition['fat'], 0);
  });
  test('repeated imports reuse snapshots but preserve manual changes', () {
    final food = BarcodeFood.fromJson(product()), doc = MiraDocument();
    final original = food.forDocument(doc);
    doc.put(original);
    expect(food.forDocument(doc).id, original.id);
    doc.put(original.copy(data: {...original.data, 'protein': 4}));
    expect(food.forDocument(doc).id, isNot(original.id));
    expect(doc.find(original.id)!.number('protein'), 4);
  });
  testWidgets(
    'invalid code never calls lookup; product requires explicit selection',
    (tester) async {
      var calls = 0;
      BarcodeFood? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: miraTheme(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await showModalBottomSheet<BarcodeFood>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => BarcodeFoodPicker(
                      lookup: (code) async {
                        calls++;
                        return BarcodeFood.fromJson(product());
                      },
                    ),
                  );
                },
                child: const Text('Открыть'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('Найти продукт'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.enterText(find.byType(TextField), '3017624010701');
      await tester.tap(find.text('Найти продукт'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(selected, isNull);
      await tester.tap(find.text('Добавить продукт'));
      await tester.pumpAndSettle();
      expect(selected!.title, 'Тестовый продукт');
    },
  );
}
