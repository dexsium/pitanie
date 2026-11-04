"""Нормализация КБЖУ к значениям на 100 г / 100 мл.

Правила:
* отсутствующее значение остаётся None (не 0);
* значения «на порцию» пересчитываются только при известной массе порции;
* отрицательные и невозможные значения заменяются на None с записью в issues;
* расхождение с расчётом 4/9/4 продукт НЕ отбраковывает (клетчатка, полиолы, округление).
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field

MAX_KCAL_PER_100 = 900.0  # чистый жир ≈ 884–900 ккал/100 г
MAX_MACRO_PER_100 = 100.0


def to_float(v: object) -> float | None:
    if v is None:
        return None
    if isinstance(v, (int, float)):
        return float(v)
    s = str(v).strip().replace(" ", "").replace(" ", "").replace(",", ".")
    if not s or s.lower() in {"nan", "null", "none", "-", "—", "н/д"}:
        return None
    m = re.fullmatch(r"[-+]?\d+(\.\d+)?", s)
    return float(s) if m else None


def basis_of(raw: object) -> str:
    """'g' или 'ml'. Всё неопознанное считается 100 г (по умолчанию в российской маркировке)."""
    s = str(raw or "").lower()
    if "мл" in s or "ml" in s or s in {"l", "liquid"}:
        return "ml"
    return "g"


@dataclass
class Nutrition:
    calories: float | None = None
    proteins: float | None = None
    fats: float | None = None
    carbohydrates: float | None = None
    basis: str = "g"
    issues: list[str] = field(default_factory=list)

    @property
    def complete(self) -> bool:
        return None not in (self.calories, self.proteins, self.fats, self.carbohydrates)


def normalize(calories, proteins, fats, carbs, *, basis="g", per_serving=False,
              serving_size=None) -> Nutrition:
    n = Nutrition(basis=basis_of(basis))
    vals = {
        "calories": to_float(calories),
        "proteins": to_float(proteins),
        "fats": to_float(fats),
        "carbohydrates": to_float(carbs),
    }
    if per_serving:
        ss = to_float(serving_size)
        if ss is None or ss <= 0:
            n.issues.append("per_serving_without_size")
            return n  # без достоверной массы порции пересчитывать нельзя
        k = 100.0 / ss
        vals = {key: (v * k if v is not None else None) for key, v in vals.items()}
    for key, v in vals.items():
        if v is None:
            continue
        limit = MAX_KCAL_PER_100 if key == "calories" else MAX_MACRO_PER_100
        if v < 0:
            n.issues.append(f"negative_{key}")
            v = None
        elif v > limit:
            n.issues.append(f"impossible_{key}")
            v = None
        setattr(n, key, None if v is None else round(v, 2))
    if None not in (n.proteins, n.fats, n.carbohydrates):
        if n.proteins + n.fats + n.carbohydrates > 100.5:
            n.issues.append("macros_over_100")
            n.proteins = n.fats = n.carbohydrates = None
    return n
