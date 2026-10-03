import 'dart:convert';
import 'package:flutter/services.dart';
import '../../shared/models/entry.dart';
import '../database/document.dart';

class CatalogFood {
  final String fdcId, title, description, publicationDate, release;
  final Map<String, double> nutrition;
  CatalogFood._(
    this.fdcId,
    this.title,
    this.description,
    this.publicationDate,
    this.release,
    this.nutrition,
  );

  Entry toEntry() => Entry(
    kind: Kind.food,
    title: title,
    data: {
      ...nutrition,
      'nutritionKnown': true,
      'nutritionSource': {
        'provider': 'USDA FoodData Central',
        'fdcId': fdcId,
        'release': release,
        'description': description,
        'publicationDate': publicationDate,
        'basisGrams': 100,
        'userEdited': false,
        'url': 'https://fdc.nal.usda.gov/food-details/$fdcId/nutrients',
      },
      'notes': 'USDA FoodData Central · $release · FDC $fdcId\n$description',
    },
  );

  Entry forDocument(MiraDocument document) {
    for (final entry in document.of(Kind.food)) {
      final source = entry.data['nutritionSource'];
      if (source is Map &&
          source['provider'] == 'USDA FoodData Central' &&
          source['fdcId'] == fdcId &&
          source['release'] == release &&
          source['userEdited'] != true &&
          entry.data['nutritionKnown'] != false &&
          nutrition.entries.every((n) => entry.data[n.key] == n.value)) {
        return entry;
      }
    }
    return toEntry();
  }
}

class FoodCatalog {
  final List<CatalogFood> foods;
  FoodCatalog._(this.foods);
  static Future<FoodCatalog> load() async => FoodCatalog.fromJson(
    jsonDecode(await rootBundle.loadString('assets/data/usda_foods.json'))
        as Map<String, dynamic>,
  );

  factory FoodCatalog.fromJson(Map<String, dynamic> data) {
    if (data['schemaVersion'] != 1 ||
        data['basisGrams'] != 100 ||
        data['source'] != 'USDA FoodData Central' ||
        data['release'] is! String) {
      throw const FormatException('Неподдерживаемый справочник');
    }
    final ids = <String>{};
    final foods = <CatalogFood>[];
    for (final row in data['foods'] as List) {
      final id = row['fdcId'];
      if (id is! String ||
          !RegExp(r'^\d+$').hasMatch(id) ||
          !ids.add(id) ||
          row['title'] is! String ||
          (row['title'] as String).trim().isEmpty ||
          row['description'] is! String ||
          row['publicationDate'] is! String) {
        throw const FormatException('Некорректная запись справочника');
      }
      final nutrition = <String, double>{};
      for (final key in ['calories', 'protein', 'fat', 'carbs']) {
        final value = row[key];
        if (value is! num || !value.isFinite || value < 0) {
          throw const FormatException('Неполные данные БЖУ');
        }
        nutrition[key] = value.toDouble();
      }
      foods.add(
        CatalogFood._(
          id,
          row['title'] as String,
          row['description'] as String,
          row['publicationDate'] as String,
          data['release'] as String,
          Map.unmodifiable(nutrition),
        ),
      );
    }
    return FoodCatalog._(List.unmodifiable(foods));
  }

  static String normalize(String text) => text
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^a-zа-я0-9]+'), ' ')
      .trim();

  List<CatalogFood> search(String query) {
    final terms = normalize(
      query,
    ).split(' ').where((t) => t.isNotEmpty).toList();
    return foods.where((food) {
      final aliases = switch (food.fdcId) {
        '171077' ||
        '171477' ||
        '171478' => 'курица куриная грудка куриное филе',
        '170685' || '170686' => 'гречка гречневая крупа',
        '168927' || '168928' => 'паста макароны спагетти',
        '169705' => 'овес',
        _ => '',
      };
      final text = normalize('${food.title} ${food.description} $aliases');
      return terms.every(text.contains);
    }).toList();
  }
}
