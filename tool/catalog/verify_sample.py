#!/usr/bin/env python3
"""Сверка случайных строк каталога с исходными CSV USDA (независимый разбор).

python tool/catalog/verify_sample.py --catalog assets/catalog/catalog.sqlite --sr SR.zip --fndds FNDDS.zip [-n 20] [--seed 7]
"""
import argparse
import csv
import io
import random
import sqlite3
import sys
import zipfile
from pathlib import Path


def rows(z, name):
    m = [p for p in z.namelist() if Path(p).name == name][0]
    return csv.DictReader(io.TextIOWrapper(z.open(m), encoding='utf-8-sig'))


def original(zpath, fdc_ids):
    """kcal/белки/жиры/углеводы и описание по fdc_id прямо из CSV (по номеру нутриента)."""
    z = zipfile.ZipFile(zpath)
    nbr_by_id = {r['id']: r['nutrient_nbr'] for r in rows(z, 'nutrient.csv')}
    want = {'203': 'protein', '204': 'fat', '205': 'carbs', '208': 'kcal'}
    out = {i: {} for i in fdc_ids}
    for r in rows(z, 'food.csv'):
        if r['fdc_id'] in out:
            out[r['fdc_id']]['name'] = r['description']
    for r in rows(z, 'food_nutrient.csv'):
        if r['fdc_id'] in out:
            nbr = nbr_by_id.get(r['nutrient_id'], r['nutrient_id'])
            if nbr in want and r['amount'] != '':
                out[r['fdc_id']][want[nbr]] = float(r['amount'])
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--catalog', required=True)
    ap.add_argument('--sr', required=True)
    ap.add_argument('--fndds', required=True)
    ap.add_argument('-n', type=int, default=20)
    ap.add_argument('--seed', type=int, default=7)
    a = ap.parse_args()
    con = sqlite3.connect(a.catalog)
    allrows = con.execute('SELECT id, source, source_id, name_en, kcal, protein, fat, carbs FROM foods').fetchall()
    random.seed(a.seed)
    sample = random.sample(allrows, a.n)
    sr_ids = [r[2] for r in sample if r[0].startswith('sr_')]
    fn_ids = [r[2] for r in sample if r[0].startswith('fndds_')]
    orig = {}
    if sr_ids:
        orig.update({('sr', k): v for k, v in original(a.sr, sr_ids).items()})
    if fn_ids:
        orig.update({('fndds', k): v for k, v in original(a.fndds, fn_ids).items()})
    bad = 0
    for id_, src, sid, name, kcal, p, f, c in sample:
        o = orig[(id_.split('_')[0], sid)]
        ok = (o.get('name') == name and
              all(abs(o.get(k, 1e9) - v) < 1e-9 for k, v in (('kcal', kcal), ('protein', p), ('fat', f), ('carbs', c))))
        bad += 0 if ok else 1
        print(f"{'OK ' if ok else 'ERR'} {id_:<16} {name[:52]:<52} ккал {kcal:>6} Б {p:>5} Ж {f:>5} У {c:>5}")
    print(f'\nПроверено {len(sample)}, расхождений: {bad}')
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
