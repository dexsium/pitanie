"""Проверка и нормализация штрихкодов (EAN-8, UPC-A, EAN-13, GTIN-14).

Штрихкод всегда строка: ведущие нули значимы. Исходный код сохраняется отдельно
(таблица product_barcodes), в products.barcode лежит канонический вид:
UPC-A (12 цифр) приводится к EAN-13 добавлением ведущего нуля.
"""
from __future__ import annotations

import re

_DIGITS = re.compile(r"\D+")


def clean(raw: object) -> str:
    """Оставляет только цифры. Научная запись и float-артефакты (4.6e12, '123.0') не принимаются."""
    if raw is None:
        return ""
    s = str(raw).strip()
    if re.fullmatch(r"\d+\.0+", s):
        s = s.split(".")[0]
    return _DIGITS.sub("", s)


def check_digit_ok(code: str) -> bool:
    """Контрольная сумма GS1 (взвешивание 3/1 справа налево)."""
    if not code.isdigit() or len(code) < 2:
        return False
    body, check = code[:-1], int(code[-1])
    total = 0
    for i, ch in enumerate(reversed(body)):
        total += int(ch) * (3 if i % 2 == 0 else 1)
    return (10 - total % 10) % 10 == check


def normalize(raw: object) -> tuple[str | None, str, str]:
    """Возвращает (канонический код | None, исходная очищенная строка, причина).

    Причина пустая, если код корректен. Допустимые длины: 8, 12, 13, 14.
    """
    code = clean(raw)
    if not code:
        return None, "", "empty"
    if len(code) not in (8, 12, 13, 14):
        return None, code, "bad_length"
    if len(set(code)) == 1:
        return None, code, "placeholder"
    if not check_digit_ok(code):
        return None, code, "bad_checksum"
    if len(code) == 12:  # UPC-A -> EAN-13
        return "0" + code, code, ""
    if len(code) == 14 and code[0] == "0":  # GTIN-14 с нулевым индикатором = EAN-13
        return code[1:], code, ""
    return code, code, ""


def variants(canonical: str) -> list[str]:
    """Все формы, под которыми код могут отсканировать (EAN-13 с нулём ↔ UPC-A)."""
    out = [canonical]
    if len(canonical) == 13 and canonical.startswith("0"):
        out.append(canonical[1:])  # UPC-A
    if len(canonical) == 13:
        out.append("0" + canonical)  # GTIN-14
    return out
