"""Rebuild a complete-macro offline catalogue from unmodified USDA SR Legacy."""
import argparse
import csv
import hashlib
import io
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = 'https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2018-04.zip'
NUTRIENTS = {'1008': ('calories', 'KCAL'), '1003': ('protein', 'G'), '1004': ('fat', 'G'), '1005': ('carbs', 'G')}


# Russian category labels are search aids; retain the exact English description.
SEARCH_RULES = [('cheese, cottage', 'Зернёный творог', 'творог зерненый cottage cheese'), ('yogurt', 'Йогурт', 'йогурт'), ('milk', 'Молоко', 'молоко'), ('cream', 'Сливки', 'сливки'), ('butter', 'Сливочное масло', 'сливочное масло'), ('cheese', 'Сыр', 'сыр'), ('egg', 'Яйца', 'яйца яйцо'), ('chicken', 'Курица', 'курица куриная'), ('turkey', 'Индейка', 'индейка'), ('beef', 'Говядина', 'говядина'), ('pork', 'Свинина', 'свинина'), ('lamb', 'Баранина', 'баранина'), ('veal', 'Телятина', 'телятина'), ('duck', 'Утка', 'утка'), ('fish', 'Рыба', 'рыба'), ('crustaceans', 'Ракообразные', 'ракообразные'), ('mollusks', 'Моллюски', 'моллюски'), ('rice', 'Рис', 'рис'), ('buckwheat', 'Гречка', 'гречка гречневая'), ('oats', 'Овёс', 'овес овсяные'), ('oat', 'Овёс', 'овес овсяные'), ('quinoa', 'Киноа', 'киноа'), ('barley', 'Ячмень', 'ячмень перловая'), ('millet', 'Пшено', 'пшено'), ('wheat', 'Пшеница', 'пшеница'), ('pasta', 'Макароны', 'паста макароны'), ('spaghetti', 'Спагетти', 'спагетти макароны'), ('bread', 'Хлеб', 'хлеб'), ('rolls', 'Булочки', 'булочки'), ('flour', 'Мука', 'мука'), ('potato', 'Картофель', 'картофель картошка'), ('carrot', 'Морковь', 'морковь'), ('broccoli', 'Брокколи', 'брокколи'), ('cabbage', 'Капуста', 'капуста'), ('cauliflower', 'Цветная капуста', 'цветная капуста'), ('cucumber', 'Огурец', 'огурец огурцы'), ('tomato', 'Помидор', 'помидор томат'), ('pepper', 'Перец', 'перец'), ('onion', 'Лук', 'лук'), ('garlic', 'Чеснок', 'чеснок'), ('spinach', 'Шпинат', 'шпинат'), ('lettuce', 'Салат', 'салат'), ('squash', 'Кабачки и тыквы', 'тыква кабачки'), ('mushroom', 'Грибы', 'грибы'), ('bean', 'Фасоль', 'фасоль'), ('lentil', 'Чечевица', 'чечевица'), ('chickpea', 'Нут', 'нут'), ('pea', 'Горох', 'горох'), ('apple', 'Яблоко', 'яблоки яблоко'), ('banana', 'Банан', 'банан'), ('orange', 'Апельсин', 'апельсин'), ('pear', 'Груша', 'груша'), ('peach', 'Персик', 'персик'), ('apricot', 'Абрикос', 'абрикос'), ('plum', 'Слива', 'слива'), ('grape', 'Виноград', 'виноград'), ('strawberr', 'Клубника', 'клубника'), ('blueberr', 'Голубика', 'голубика'), ('raspberr', 'Малина', 'малина'), ('cherr', 'Вишня', 'вишня'), ('pineapple', 'Ананас', 'ананас'), ('avocado', 'Авокадо', 'авокадо'), ('lemon', 'Лимон', 'лимон'), ('lime', 'Лайм', 'лайм'), ('nuts', 'Орехи', 'орехи'), ('seeds', 'Семена', 'семена'), ('oil', 'Масло', 'масло'), ('honey', 'Мёд', 'мед'), ('sugar', 'Сахар', 'сахар'), ('salt', 'Соль', 'соль'), ('coffee', 'Кофе', 'кофе'), ('tea', 'Чай', 'чай'), ('chocolate', 'Шоколад', 'шоколад')]

def russian_search(description):
    text = description.lower()
    for match, title, aliases in SEARCH_RULES:
        if text.startswith(match):
            return title, aliases
    return '', ''


def build(archive):
    labels = json.loads((ROOT / 'scripts/usda_food_labels.json').read_text())
    with zipfile.ZipFile(archive) as z:
        def rows(name):
            path = next(n for n in z.namelist() if n.endswith('/' + name))
            return csv.DictReader(io.TextIOWrapper(z.open(path), encoding='utf-8-sig'))
        definitions = {r['id']: r for r in rows('nutrient.csv')}
        for nid, (_, unit) in NUTRIENTS.items():
            assert definitions[nid]['unit_name'].upper() == unit
        foods = {r['fdc_id']: r for r in rows('food.csv') }
        assert labels.keys() <= foods.keys(), 'Unknown FDC identifier'
        values = {fid: {} for fid in foods}
        for row in rows('food_nutrient.csv'):
            fid, nid = row['fdc_id'], row['nutrient_id']
            if fid in values and nid in NUTRIENTS and row['amount']:
                key = NUTRIENTS[nid][0]
                assert key not in values[fid], 'Duplicate nutrient'
                value = float(row['amount'])
                assert 0 <= value < float('inf')
                values[fid][key] = value
        products = []
        for fid in [*labels, *(fid for fid in foods if fid not in labels)]:
            if len(values[fid]) != 4:
                assert fid not in labels, f'Missing curated nutrition: {fid}'
                continue
            label = labels.get(fid)
            food = foods[fid]
            prefix, aliases = russian_search(foods[fid]['description'])
            title = label or (prefix + ' · ' if prefix else '') + foods[fid]['description']
            products.append({'fdcId': fid, 'title': title, 'aliases': aliases, 'description': food['description'],
                             'publicationDate': food['publication_date'], **values[fid]})
    result = {'schemaVersion': 1, 'source': 'USDA FoodData Central', 'release': 'SR Legacy 04/2018',
              'downloadUrl': SOURCE, 'archiveSha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
              'basisGrams': 100, 'foods': products}
    target = ROOT / 'assets/data/usda_foods.json'
    target.write_text(json.dumps(result, ensure_ascii=False, separators=(',', ':')) + '\n')
    print(f'{len(products)} foods; archive SHA256 {result["archiveSha256"]}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('archive', type=Path)
    build(parser.parse_args().archive)
