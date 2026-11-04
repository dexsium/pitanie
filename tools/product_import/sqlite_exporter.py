"""Сборка products_ru.db: таблица products, FTS5, альтернативные штрихкоды, мета и контрольная сумма."""
from __future__ import annotations

import hashlib
import os
import sqlite3
from datetime import datetime, timezone

SCHEMA_VERSION = 1

DDL = """
CREATE TABLE products (
    id INTEGER PRIMARY KEY,
    source_id TEXT,
    barcode TEXT,
    name TEXT NOT NULL,
    brand TEXT,
    manufacturer TEXT,
    category TEXT,
    calories REAL,
    proteins REAL,
    fats REAL,
    carbohydrates REAL,
    serving_size REAL,
    package_weight REAL,
    nutrition_basis TEXT NOT NULL,
    source TEXT NOT NULL,
    updated_at TEXT
);
CREATE INDEX idx_products_barcode ON products(barcode);
CREATE INDEX idx_products_name ON products(name);
CREATE INDEX idx_products_brand ON products(brand);
CREATE TABLE product_barcodes (
    barcode TEXT NOT NULL,
    product_id INTEGER NOT NULL REFERENCES products(id),
    original INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (barcode, product_id)
);
CREATE INDEX idx_product_barcodes_pid ON product_barcodes(product_id);
CREATE VIRTUAL TABLE products_fts USING fts5(
    name, brand, manufacturer,
    content='products', content_rowid='id', tokenize='unicode61 remove_diacritics 2'
);
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
"""

COLUMNS = ["source_id", "barcode", "name", "brand", "manufacturer", "category", "calories",
           "proteins", "fats", "carbohydrates", "serving_size", "package_weight",
           "nutrition_basis", "source", "updated_at"]


def sha256_of(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def export(products: list[dict], path: str, *, catalog_version: str, stats: dict) -> str:
    """products: словари с ключами COLUMNS + 'barcodes' (список всех форм кода).
    Возвращает sha256 файла (записывается и в path + '.sha256')."""
    if os.path.exists(path):
        os.remove(path)
    db = sqlite3.connect(path)
    try:
        db.executescript(DDL)
        for p in products:
            cur = db.execute(
                f"INSERT INTO products ({','.join(COLUMNS)}) VALUES ({','.join('?' * len(COLUMNS))})",
                [p.get(c) for c in COLUMNS],
            )
            pid = cur.lastrowid
            for i, code in enumerate(dict.fromkeys(p.get("barcodes") or [])):
                db.execute("INSERT OR IGNORE INTO product_barcodes VALUES (?,?,?)",
                           (code, pid, 1 if i == 0 else 0))
        db.execute("INSERT INTO products_fts(products_fts) VALUES('rebuild')")
        meta = {
            "schema_version": str(SCHEMA_VERSION),
            "catalog_version": catalog_version,
            "built_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "products": str(len(products)),
            **{k: str(v) for k, v in stats.items()},
        }
        db.executemany("INSERT INTO meta VALUES (?,?)", meta.items())
        db.commit()
        ok = db.execute("PRAGMA integrity_check").fetchone()[0]
        if ok != "ok":
            raise RuntimeError(f"integrity_check: {ok}")
        db.execute("VACUUM")
    finally:
        db.close()
    digest = sha256_of(path)
    with open(path + ".sha256", "w", encoding="utf-8") as f:
        f.write(f"{digest}  {os.path.basename(path)}\n")
    return digest
