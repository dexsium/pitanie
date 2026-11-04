#!/usr/bin/env python3
"""Импорт выгрузки каталога продуктов (CSV / JSON / JSONL / SQLite) в products_ru.db.

Инструмент НЕ скачивает данные с сайтов. Вход — файл, который вам передал владелец
данных (или данные с явной лицензией). Подробности: README.md.

Пример:
  python main.py --input export.csv --output products_ru.db --source "perek.us (выгрузка владельца)" \
      --catalog-version 2026.11.1 --map name=Название --map barcode=Штрихкод
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import sqlite3
import sys
import time
from collections import Counter

import barcode_validator as bv
import nutrition_normalizer as nn
import sqlite_exporter as ex

FIELDS = ["source_id", "barcode", "name", "brand", "manufacturer", "category", "calories",
          "proteins", "fats", "carbohydrates", "serving_size", "package_weight",
          "nutrition_basis", "updated_at"]


def read_rows(path: str, table: str | None):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".csv":
        with open(path, newline="", encoding="utf-8-sig") as f:
            sample = f.read(4096)
            f.seek(0)
            try:
                dialect = csv.Sniffer().sniff(sample, delimiters=",;\t")
            except csv.Error:
                dialect = csv.excel
            yield from csv.DictReader(f, dialect=dialect)
    elif ext == ".json":
        with open(path, encoding="utf-8-sig") as f:
            data = json.load(f)
        if isinstance(data, dict):
            data = next((v for v in data.values() if isinstance(v, list)), [])
        yield from data
    elif ext in (".jsonl", ".ndjson"):
        with open(path, encoding="utf-8-sig") as f:
            for line in f:
                if line.strip():
                    yield json.loads(line)
    elif ext in (".db", ".sqlite", ".sqlite3"):
        db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        db.row_factory = sqlite3.Row
        t = table or "products"
        for r in db.execute(f'SELECT * FROM "{t}"'):
            yield dict(r)
        db.close()
    else:
        raise SystemExit(f"Неизвестный формат входного файла: {ext}")


def text(v) -> str | None:
    if v is None:
        return None
    s = " ".join(str(v).split())
    return s or None


def process(rows, mapping, args):
    """Возвращает (products, stats, issues)."""
    stats = Counter()
    issues = Counter()
    items: list[dict] = []
    for raw in rows:
        stats["rows_read"] += 1
        g = lambda f: raw.get(mapping.get(f, f))  # noqa: E731
        name = text(g("name"))
        if not name:
            stats["skipped_empty_name"] += 1
            continue
        code, original, why = bv.normalize(g("barcode"))
        if why and why != "empty":
            stats["invalid_barcodes"] += 1
            issues[f"barcode_{why}"] += 1
        per_serving = args.per_serving or str(g("per_serving") or "").lower() in {"1", "true", "да"}
        n = nn.normalize(g("calories"), g("proteins"), g("fats"), g("carbohydrates"),
                         basis=g("nutrition_basis"), per_serving=per_serving,
                         serving_size=g("serving_size"))
        for i in n.issues:
            issues[i] += 1
        item = {
            "source_id": text(g("source_id")),
            "barcode": code,
            "name": name,
            "brand": text(g("brand")),
            "manufacturer": text(g("manufacturer")),
            "category": text(g("category")),
            "calories": n.calories,
            "proteins": n.proteins,
            "fats": n.fats,
            "carbohydrates": n.carbohydrates,
            "serving_size": nn.to_float(g("serving_size")),
            "package_weight": nn.to_float(g("package_weight")),
            "nutrition_basis": n.basis,
            "source": args.source,
            "updated_at": text(g("updated_at")),
            "barcodes": bv.variants(code) if code else [],
            "_complete": n.complete,
        }
        items.append(item)
    stats["valid_rows"] = len(items)
    return items, stats, issues


def completeness(p: dict) -> int:
    return sum(p.get(k) is not None for k in
               ("calories", "proteins", "fats", "carbohydrates", "brand", "manufacturer",
                "category", "serving_size", "package_weight", "updated_at"))


def dedupe(items: list[dict], stats: Counter) -> list[dict]:
    """Дубль = один канонический штрихкод; для записей без кода — полное совпадение
    (название, марка, производитель, основа, КБЖУ). Остаётся более полная запись."""
    best: dict = {}
    for p in items:
        if p["barcode"]:
            key = ("b", p["barcode"])
        else:
            key = ("n", p["name"].lower(), (p["brand"] or "").lower(),
                   (p["manufacturer"] or "").lower(), p["nutrition_basis"],
                   p["calories"], p["proteins"], p["fats"], p["carbohydrates"])
        cur = best.get(key)
        if cur is None:
            best[key] = p
        else:
            stats["duplicates"] += 1
            if completeness(p) > completeness(cur):
                best[key] = p
    return list(best.values())


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--input", required=True)
    ap.add_argument("--output", default="products_ru.db")
    ap.add_argument("--table", help="таблица во входной SQLite (по умолчанию products)")
    ap.add_argument("--source", required=True, help="значение products.source, например 'perek.us (выгрузка владельца)'")
    ap.add_argument("--catalog-version", required=True)
    ap.add_argument("--map", action="append", default=[], metavar="поле=колонка",
                    help="сопоставление: поле каталога → колонка входного файла")
    ap.add_argument("--per-serving", action="store_true",
                    help="КБЖУ во входном файле даны на порцию (нужен serving_size)")
    ap.add_argument("--report", help="путь к JSON-отчёту (по умолчанию рядом с БД)")
    args = ap.parse_args(argv)

    mapping = dict(m.split("=", 1) for m in args.map)
    t0 = time.time()
    items, stats, issues = process(read_rows(args.input, args.table), mapping, args)
    unique = dedupe(items, stats)
    full = sum(1 for p in unique if p["_complete"])
    barcodes = {p["barcode"] for p in unique if p["barcode"]}
    stats.update({
        "unique_products": len(unique),
        "unique_barcodes": len(barcodes),
        "complete_nutrition": full,
        "incomplete_nutrition": len(unique) - full,
    })
    digest = ex.export(unique, args.output, catalog_version=args.catalog_version,
                       stats={"unique_barcodes": len(barcodes), "complete_nutrition": full})
    report = {
        "input": os.path.basename(args.input),
        "source": args.source,
        "catalog_version": args.catalog_version,
        "stats": dict(stats),
        "issues": dict(issues),
        "sqlite_bytes": os.path.getsize(args.output),
        "sha256": digest,
        "seconds": round(time.time() - t0, 2),
        "completeness_note": "Полнота определяется только входной выгрузкой; "
                              "утверждение о 100 % полноте требует подтверждения владельца источника.",
    }
    rp = args.report or os.path.splitext(args.output)[0] + "_report.json"
    with open(rp, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
