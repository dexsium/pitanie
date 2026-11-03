#!/usr/bin/env python3
"""Сборка локального каталога КБЖУ из официальных выгрузок USDA FoodData Central.

Источники (общедоступные данные USDA, CC0):
  * SR Legacy (CSV, 2018-04):  FoodData_Central_sr_legacy_food_csv_2018-04.zip
  * FNDDS 2021-2023 (Survey Foods, CSV, 2024-10-31): FoodData_Central_survey_food_csv_2024-10-31.zip

Запуск:
  python tool/catalog/build_catalog.py --sr SR.zip --fndds FNDDS.zip --out assets/catalog

Принципы:
  * значения берутся как есть из выгрузки, на 100 г съедобной части;
  * отсутствующее значение НЕ заменяется нулём: запись без полного набора калорий/Б/Ж/У
    в каталог не попадает и учитывается в отчёте (skipped_missing);
  * физически невозможные значения (Б+Ж+У > 100 г, калории вне 0..902) отбрасываются
    и учитываются в отчёте (skipped_implausible);
  * перевод названий на русский выполняет translate_ru.py по проверяемому глоссарию;
    непереведённые названия остаются пустыми.
"""
import argparse
import csv
import io
import json
import re
import sqlite3
import sys
import zipfile
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import translate_ru  # noqa: E402

NBR = {'kcal': '208', 'kcal_gen': '957', 'kcal_spec': '958', 'protein': '203',
       'fat': '204', 'carbs': '205', 'fiber': '291', 'sugars': '269', 'sodium': '307'}

# Категории SR Legacy (food_category.csv) -> русские названия (фиксированный набор USDA).
SR_CATEGORY_RU = {
    'Dairy and Egg Products': 'Молочные продукты и яйца',
    'Spices and Herbs': 'Специи и травы',
    'Baby Foods': 'Детское питание',
    'Fats and Oils': 'Жиры и масла',
    'Poultry Products': 'Птица',
    'Soups, Sauces, and Gravies': 'Супы и соусы',
    'Sausages and Luncheon Meats': 'Колбасы и мясные деликатесы',
    'Breakfast Cereals': 'Готовые завтраки',
    'Fruits and Fruit Juices': 'Фрукты и фруктовые соки',
    'Pork Products': 'Свинина',
    'Vegetables and Vegetable Products': 'Овощи',
    'Nut and Seed Products': 'Орехи и семена',
    'Beef Products': 'Говядина',
    'Beverages': 'Напитки',
    'Finfish and Shellfish Products': 'Рыба и морепродукты',
    'Legumes and Legume Products': 'Бобовые',
    'Lamb, Veal, and Game Products': 'Баранина, телятина, дичь',
    'Baked Products': 'Выпечка',
    'Sweets': 'Сладости',
    'Cereal Grains and Pasta': 'Крупы и макаронные изделия',
    'Fast Foods': 'Фастфуд',
    'Meals, Entrees, and Side Dishes': 'Готовые блюда и гарниры',
    'Snacks': 'Снеки',
    'American Indian/Alaska Native Foods': 'Блюда коренных народов Америки',
    'Restaurant Foods': 'Блюда ресторанов',
    'Branded Food Products Database': 'Брендовые продукты',
    'Quality Control Materials': 'Контрольные материалы',
    'Alcoholic Beverages': 'Алкогольные напитки',
}

STATE_WORDS = [
    ('raw', 'сырой', re.compile(r'\braw\b|\buncooked\b', re.I)),
    ('boiled', 'варёный', re.compile(r'\bboiled\b|\bsimmered\b', re.I)),
    ('steamed', 'на пару', re.compile(r'\bsteamed\b', re.I)),
    ('roasted', 'запечённый', re.compile(r'\broasted\b|\bbaked\b', re.I)),
    ('fried', 'жареный', re.compile(r'\bfried\b|\bpan-fried\b|\bsauteed\b|\bsautéed\b', re.I)),
    ('grilled', 'на гриле', re.compile(r'\bgrilled\b|\bbroiled\b', re.I)),
    ('stewed', 'тушёный', re.compile(r'\bstewed\b|\bbraised\b', re.I)),
    ('cooked', 'приготовленный', re.compile(r'\bcooked\b', re.I)),
    ('canned', 'консервированный', re.compile(r'\bcanned\b', re.I)),
    ('dried', 'сушёный', re.compile(r'\bdried\b|\bdehydrated\b|\bdry\b', re.I)),
    ('frozen', 'замороженный', re.compile(r'\bfrozen\b', re.I)),
]


def csv_rows(zf, name):
    members = [p for p in zf.namelist() if Path(p).name.lower() == name.lower()]
    if not members:
        raise RuntimeError(f'В архиве нет {name}')
    with zf.open(members[0]) as s:
        yield from csv.DictReader(io.TextIOWrapper(s, encoding='utf-8-sig', newline=''))


def num(v):
    try:
        return float(v) if v is not None and str(v).strip() != '' else None
    except ValueError:
        return None


def detect_state(name):
    for key, _ru, rx in STATE_WORDS:
        if rx.search(name):
            return key
    return 'unknown'


def load_dataset(zpath, source, source_label, kind, data_types, stats):
    rows = []
    with zipfile.ZipFile(zpath) as z:
        nbr_by_id = {r['id']: r['nutrient_nbr'].strip() for r in csv_rows(z, 'nutrient.csv')}
        wanted = set(NBR.values())
        food = {r['fdc_id']: r for r in csv_rows(z, 'food.csv') if r['data_type'] in data_types}
        cat_sr = {r['id']: r['description'] for r in csv_rows(z, 'food_category.csv')} \
            if any(Path(n).name == 'food_category.csv' for n in z.namelist()) else {}
        cat_ww = {r['wweia_food_category']: r['wweia_food_category_description']
                  for r in csv_rows(z, 'wweia_food_category.csv')} \
            if any(Path(n).name == 'wweia_food_category.csv' for n in z.namelist()) else {}
        ww_of = {}
        if cat_ww:
            ww_of = {r['fdc_id']: r['wweia_category_number'] for r in csv_rows(z, 'survey_fndds_food.csv')}
        amounts = defaultdict(dict)
        for r in csv_rows(z, 'food_nutrient.csv'):
            if r['fdc_id'] not in food:
                continue
            nbr = nbr_by_id.get(r['nutrient_id'], r['nutrient_id'])  # в FNDDS nutrient_id уже равен nutrient_nbr
            if nbr in wanted:
                v = num(r['amount'])
                if v is not None:
                    amounts[r['fdc_id']][nbr] = v
        portions = defaultdict(list)
        for r in csv_rows(z, 'food_portion.csv'):
            if r['fdc_id'] not in food:
                continue
            g = num(r['gram_weight'])
            if not g or g <= 0:
                continue
            desc = (r.get('portion_description') or '').strip()
            mod = (r.get('modifier') or '').strip()
            amt = num(r.get('amount'))
            label = desc or (f'{amt:g} {mod}'.strip() if amt and mod and not mod.isdigit() else mod)
            if not label or label.isdigit() or label.lower().startswith('quantity not specified'):
                continue
            portions[r['fdc_id']].append((int(r.get('seq_num') or 0), label, g))

        for fdc, f in food.items():
            stats[source]['total'] += 1
            a = amounts.get(fdc, {})
            kcal = a.get(NBR['kcal'])
            used_atwater = False
            if kcal is None:
                kcal = a.get(NBR['kcal_gen'], a.get(NBR['kcal_spec']))
                used_atwater = kcal is not None
            p, fat, c = a.get(NBR['protein']), a.get(NBR['fat']), a.get(NBR['carbs'])
            if None in (kcal, p, fat, c):
                stats[source]['skipped_missing'] += 1
                continue
            if min(kcal, p, fat, c) < 0 or p + fat + c > 100.5 or kcal > 902:
                stats[source]['skipped_implausible'] += 1
                continue
            name = f['description'].strip()
            if used_atwater:
                stats[source]['kcal_from_atwater'] += 1
            if cat_sr:
                cat_en = cat_sr.get(f.get('food_category_id'), '')
                cat_ru = SR_CATEGORY_RU.get(cat_en, '')
            else:
                cat_en = cat_ww.get(ww_of.get(fdc, ''), '')
                cat_ru = ''
            ps = sorted(portions.get(fdc, []))[:6]
            rows.append({
                'id': f'{source}_{fdc}', 'source': source_label, 'source_id': fdc, 'kind': kind,
                'name_en': name, 'category_en': cat_en, 'category_ru': cat_ru,
                'kcal': kcal, 'protein': p, 'fat': fat, 'carbs': c,
                'fiber': a.get(NBR['fiber']), 'sugars': a.get(NBR['sugars']),
                'sodium_mg': a.get(NBR['sodium']),
                'state': detect_state(name),
                'portions': ps,
            })
            stats[source]['imported'] += 1
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--sr', required=True)
    ap.add_argument('--fndds', required=True)
    ap.add_argument('--out', default='assets/catalog')
    a = ap.parse_args()
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    stats = defaultdict(Counter)
    rows = load_dataset(a.sr, 'sr', 'USDA SR Legacy', 'food', {'sr_legacy_food'}, stats)
    rows += load_dataset(a.fndds, 'fndds', 'USDA FNDDS 2021-2023', 'dish', {'survey_fndds_food'}, stats)

    db = out / 'catalog.sqlite'
    if db.exists():
        db.unlink()
    con = sqlite3.connect(db)
    con.executescript('''
      CREATE TABLE foods (
        id TEXT PRIMARY KEY, source TEXT NOT NULL, source_id TEXT NOT NULL, kind TEXT NOT NULL,
        name_en TEXT NOT NULL, name_ru TEXT, name_ru_status TEXT, search_ru TEXT,
        category_en TEXT, category_ru TEXT,
        kcal REAL NOT NULL, protein REAL NOT NULL, fat REAL NOT NULL, carbs REAL NOT NULL,
        fiber REAL, sugars REAL, sodium_mg REAL,
        state TEXT NOT NULL, portion_g REAL, portion_label TEXT
      );
      CREATE TABLE portions (food_id TEXT NOT NULL, seq INTEGER NOT NULL, label TEXT NOT NULL, grams REAL NOT NULL);
      CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT);
    ''')
    tr_stats = Counter()
    for r in rows:
        ru, status = translate_ru.translate(r['name_en'])
        tr_stats['translated' if ru else 'not_translated'] += 1
        ps = r['portions']
        con.execute('INSERT INTO foods VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)', (
            r['id'], r['source'], r['source_id'], r['kind'], r['name_en'], ru, status, translate_ru.base_ru(r['name_en']),
            r['category_en'], r['category_ru'], r['kcal'], r['protein'], r['fat'], r['carbs'],
            r['fiber'], r['sugars'], r['sodium_mg'], r['state'],
            ps[0][2] if ps else None, ps[0][1] if ps else None))
        for i, (seq, label, g) in enumerate(ps):
            con.execute('INSERT INTO portions VALUES (?,?,?,?)', (r['id'], i, label, g))
    meta = {
        'basis': 'на 100 г съедобной части, значения из выгрузок USDA без изменений',
        'license': 'USDA FoodData Central: общедоступные данные (CC0)',
        'sr_legacy_url': 'https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2018-04.zip',
        'fndds_url': 'https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_survey_food_csv_2024-10-31.zip',
        'missing_values': 'записи без калорий, белков, жиров или углеводов в каталог не включены; нули не подставляются',
        'translation': 'name_ru заполнен только для названий, полностью покрытых глоссарием; остальные пусты',
    }
    con.executemany('INSERT INTO metadata VALUES (?,?)', meta.items())
    con.commit()
    con.execute('VACUUM')
    con.close()

    report = {
        'sr_legacy': dict(stats['sr']),
        'fndds_2021_2023': dict(stats['fndds']),
        'total_in_catalog': len(rows),
        'foods': sum(1 for r in rows if r['kind'] == 'food'),
        'dishes': sum(1 for r in rows if r['kind'] == 'dish'),
        'translation': dict(tr_stats),
        'sqlite_bytes': db.stat().st_size,
    }
    (out / 'import_report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
