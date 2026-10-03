import '../../shared/models/entry.dart';
import '../database/document.dart';

/// A labelled product snapshot, separate from the USDA ingredient catalogue.
class BarcodeFood {
  final String code, title, brand, modified;
  final Map<String, double> nutrition;
  const BarcodeFood({
    required this.code,
    required this.title,
    required this.brand,
    required this.modified,
    required this.nutrition,
  });

  factory BarcodeFood.fromJson(Map<String, dynamic> data) {
    final code = data['code'];
    final title = data['title'];
    if (code is! String ||
        !validBarcode(code) ||
        title is! String ||
        title.trim().isEmpty ||
        data['basisGrams'] != 100) {
      throw const FormatException('Неподдерживаемые данные продукта');
    }
    final values = <String, double>{};
    for (final key in ['calories', 'protein', 'fat', 'carbs']) {
      final value = data[key];
      if (value is! num || !value.isFinite || value < 0) {
        throw const FormatException('В базе нет полных БЖУ этого продукта');
      }
      values[key] = value.toDouble();
    }
    return BarcodeFood(
      code: code,
      title: title.trim(),
      brand: data['brand'] as String? ?? '',
      modified: data['modified'] as String? ?? '',
      nutrition: Map.unmodifiable(values),
    );
  }

  Entry toEntry() => Entry(
    kind: Kind.food,
    title: title,
    data: {
      ...nutrition,
      'nutritionKnown': true,
      'barcode': code,
      'nutritionSource': {
        'provider': 'Open Food Facts',
        'code': code,
        'modified': modified,
        'basisGrams': 100,
        'userEdited': false,
        'url': 'https://world.openfoodfacts.org/product/$code',
        'license': 'ODbL-1.0',
      },
      'notes':
          'Open Food Facts · ODbL · $code${brand.isEmpty ? '' : '\n$brand'}',
    },
  );

  Entry forDocument(MiraDocument document) {
    for (final entry in document.of(Kind.food)) {
      final source = entry.data['nutritionSource'];
      if (source is Map &&
          source['provider'] == 'Open Food Facts' &&
          source['code'] == code &&
          source['modified'] == modified &&
          source['userEdited'] != true &&
          entry.title == title &&
          entry.data['nutritionKnown'] == true &&
          nutrition.entries.every((n) => entry.data[n.key] == n.value)) {
        return entry;
      }
    }
    return toEntry();
  }
}

/// GTIN-8, UPC-A, EAN-13 and GTIN-14. Never convert codes to numbers.
bool validBarcode(String code) {
  if (!RegExp(r'^(?:\d{8}|\d{12}|\d{13}|\d{14})$').hasMatch(code)) {
    return false;
  }
  var sum = 0;
  for (var i = code.length - 2, weight = 3; i >= 0; i--, weight = 4 - weight) {
    sum += int.parse(code[i]) * weight;
  }
  return (10 - sum % 10) % 10 == int.parse(code[code.length - 1]);
}
