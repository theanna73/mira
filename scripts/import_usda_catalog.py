"""Rebuild a curated offline catalogue from USDA's unmodified SR Legacy export."""
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


def build(archive):
    labels = json.loads((ROOT / 'scripts/usda_food_labels.json').read_text())
    with zipfile.ZipFile(archive) as z:
        def rows(name):
            path = next(n for n in z.namelist() if n.endswith('/' + name))
            return csv.DictReader(io.TextIOWrapper(z.open(path), encoding='utf-8-sig'))
        definitions = {r['id']: r for r in rows('nutrient.csv')}
        for nid, (_, unit) in NUTRIENTS.items():
            assert definitions[nid]['unit_name'].upper() == unit
        foods = {r['fdc_id']: r for r in rows('food.csv') if r['fdc_id'] in labels}
        assert foods.keys() == labels.keys(), 'Unknown FDC identifier'
        values = {fid: {} for fid in labels}
        for row in rows('food_nutrient.csv'):
            fid, nid = row['fdc_id'], row['nutrient_id']
            if fid in values and nid in NUTRIENTS and row['amount']:
                key = NUTRIENTS[nid][0]
                assert key not in values[fid], 'Duplicate nutrient'
                value = float(row['amount'])
                assert 0 <= value < float('inf')
                values[fid][key] = value
        products = []
        for fid, label in labels.items():
            assert len(values[fid]) == 4, f'Missing nutrition: {fid}'
            food = foods[fid]
            products.append({'fdcId': fid, 'title': label, 'description': food['description'],
                             'publicationDate': food['publication_date'], **values[fid]})
    result = {'schemaVersion': 1, 'source': 'USDA FoodData Central', 'release': 'SR Legacy 04/2018',
              'downloadUrl': SOURCE, 'archiveSha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
              'basisGrams': 100, 'foods': products}
    target = ROOT / 'assets/data/usda_foods.json'
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(f'{len(products)} foods; archive SHA256 {result["archiveSha256"]}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('archive', type=Path)
    build(parser.parse_args().archive)
