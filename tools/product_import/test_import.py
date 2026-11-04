"""Тесты импортёра. Данные ниже — ТЕСТОВЫЕ ФИКСТУРЫ, в каталог приложения не попадают."""
import csv
import json
import os
import sqlite3
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import barcode_validator as bv  # noqa: E402
import main as imp  # noqa: E402
import nutrition_normalizer as nn  # noqa: E402


class Barcodes(unittest.TestCase):
    def test_ean13_valid(self):
        self.assertEqual(bv.normalize("4606068171360")[0], "4606068171360")

    def test_upca_to_ean13_keeps_original(self):
        code, orig, why = bv.normalize("036000291452")
        self.assertEqual((code, orig, why), ("0036000291452", "036000291452", ""))
        self.assertIn("036000291452", bv.variants(code))

    def test_leading_zero_not_lost(self):
        self.assertEqual(bv.normalize("0036000291452")[0], "0036000291452")

    def test_ean8_and_bad(self):
        self.assertEqual(bv.normalize("96385074")[0], "96385074")
        self.assertEqual(bv.normalize("4606068171361")[2], "bad_checksum")
        self.assertEqual(bv.normalize("123")[2], "bad_length")
        self.assertEqual(bv.normalize("0000000000000")[2], "placeholder")
        self.assertEqual(bv.normalize("")[2], "empty")

    def test_float_artifact(self):
        self.assertEqual(bv.clean("4606068171360.0"), "4606068171360")


class Nutrition(unittest.TestCase):
    def test_missing_stays_null(self):
        n = nn.normalize(None, "5", "", "10")
        self.assertIsNone(n.calories)
        self.assertIsNone(n.fats)
        self.assertEqual(n.proteins, 5)

    def test_comma_and_basis(self):
        n = nn.normalize("52,5", "0,3", "0,2", "13,8", basis="100 мл")
        self.assertEqual((n.calories, n.basis), (52.5, "ml"))

    def test_per_serving_needs_size(self):
        self.assertFalse(nn.normalize(200, 10, 10, 20, per_serving=True).complete)
        n = nn.normalize(200, 10, 10, 20, per_serving=True, serving_size=50)
        self.assertEqual((n.calories, n.proteins), (400, 20))

    def test_invalid_values_nulled_not_dropped(self):
        n = nn.normalize(-5, 10, 10, 10)
        self.assertIsNone(n.calories)
        self.assertIn("negative_calories", n.issues)
        self.assertIsNone(nn.normalize(2000, 1, 1, 1).calories)

    def test_macro_energy_mismatch_is_kept(self):
        # 4/9/4 даёт 4*10+9*5+4*20 = 165, заявлено 300: продукт сохраняется как есть
        n = nn.normalize(300, 10, 5, 20)
        self.assertEqual(n.calories, 300)


class Pipeline(unittest.TestCase):
    def run_import(self, rows, extra=()):
        d = tempfile.mkdtemp()
        src, out = os.path.join(d, "in.csv"), os.path.join(d, "products_ru.db")
        with open(src, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=sorted({k for r in rows for k in r}))
            w.writeheader()
            w.writerows(rows)
        imp.main(["--input", src, "--output", out, "--source", "тест", "--catalog-version", "t1", *extra])
        return out

    def test_end_to_end(self):
        rows = [
            {"name": "Гречка", "barcode": "4606068171360", "brand": "A", "calories": "343",
             "proteins": "13", "fats": "3,4", "carbohydrates": "62"},
            {"name": "Гречка", "barcode": "4606068171360", "calories": "343"},  # дубль, менее полный
            {"name": "Гречка", "barcode": "96385074", "brand": "B"},  # тот же название, другой производитель
            {"name": "Молоко", "barcode": "4606068171361", "calories": "60"},  # плохая контрольная сумма
            {"name": "", "barcode": "96385074"},
            {"name": "Сок", "barcode": "036000291452", "calories": "45", "nutrition_basis": "мл"},
        ]
        out = self.run_import(rows)
        db = sqlite3.connect(out)
        self.assertEqual(db.execute("PRAGMA integrity_check").fetchone()[0], "ok")
        self.assertEqual(db.execute("SELECT count(*) FROM products").fetchone()[0], 4)
        # дубль слит, остаётся более полная запись
        self.assertEqual(db.execute("SELECT brand FROM products WHERE barcode='4606068171360'").fetchone()[0], "A")
        # одинаковые названия разных производителей сохранены
        self.assertEqual(db.execute("SELECT count(*) FROM products WHERE name='Гречка'").fetchone()[0], 2)
        # NULL, а не 0
        self.assertIsNone(db.execute("SELECT calories FROM products WHERE barcode='96385074'").fetchone()[0])
        # некорректный штрихкод: продукт остаётся без кода
        self.assertIsNone(db.execute("SELECT barcode FROM products WHERE name='Молоко'").fetchone()[0])
        # UPC-A находится и по EAN-13, и по исходному коду
        for code in ("0036000291452", "036000291452"):
            pid = db.execute("SELECT product_id FROM product_barcodes WHERE barcode=?", (code,)).fetchone()[0]
            self.assertEqual(db.execute("SELECT nutrition_basis FROM products WHERE id=?", (pid,)).fetchone()[0], "ml")
        # поиск по русскому названию через FTS5
        hits = db.execute("SELECT count(*) FROM products_fts WHERE products_fts MATCH 'греч*'").fetchone()[0]
        self.assertEqual(hits, 2)
        meta = dict(db.execute("SELECT key, value FROM meta").fetchall())
        self.assertEqual(meta["catalog_version"], "t1")
        self.assertTrue(os.path.exists(out + ".sha256"))
        rep = json.load(open(os.path.splitext(out)[0] + "_report.json", encoding="utf-8"))
        self.assertEqual(rep["stats"]["duplicates"], 1)
        self.assertEqual(rep["stats"]["invalid_barcodes"], 1)
        self.assertEqual(rep["stats"]["skipped_empty_name"], 1)

    def test_barcode_lookup_is_fast(self):
        rows = [{"name": f"Товар {i}", "barcode": ""} for i in range(1)]
        out = self.run_import(rows)
        db = sqlite3.connect(out)
        plan = db.execute("EXPLAIN QUERY PLAN SELECT * FROM product_barcodes WHERE barcode='1'").fetchall()
        self.assertIn("INDEX", " ".join(str(r) for r in plan).upper())


if __name__ == "__main__":
    unittest.main()
