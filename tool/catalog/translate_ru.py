"""Перевод названий USDA на русский по проверяемому глоссарию.

Название USDA имеет вид «Основа, уточнение, уточнение, ...». Перевод принимается,
только если ВСЕ сегменты найдены в глоссарии (glossary_ru.json). Иначе возвращается
пустая строка: частичные и догадочные переводы не допускаются.

В глоссарии у основы указан род (m, f, n, p — мн. ч.); уточнения-прилагательные
помечены «~» и согласуются с основой по роду.
"""
import json
from pathlib import Path

_G = json.loads((Path(__file__).parent / 'glossary_ru.json').read_text(encoding='utf-8'))
BASES = {k.lower(): v for k, v in _G['bases'].items()}   # -> [перевод, род]
MODS = {k.lower(): v for k, v in _G['modifiers'].items()}
COMBOS = {k.lower(): v for k, v in _G.get('combos', {}).items()}  # «основа, уточнение» с особым значением


def _inflect(adj, gender):
    if gender == 'm':
        return adj
    if adj == 'свежий':
        return {'f': 'свежая', 'n': 'свежее', 'p': 'свежие'}[gender]
    if adj.endswith(('ый', 'ой')):
        stem = adj[:-2]
        return stem + {'f': 'ая', 'n': 'ое', 'p': 'ые'}[gender]
    if adj.endswith('ий'):
        stem = adj[:-2]
        if stem and stem[-1] in 'кгх':
            return stem + {'f': 'ая', 'n': 'ое', 'p': 'ие'}[gender]
        raise ValueError(adj)
    return adj


def translate(name_en):
    parts = [p.strip() for p in name_en.split(',') if p.strip()]
    if not parts:
        return None, None
    rest = parts[1:]
    if len(parts) > 1 and f'{parts[0]}, {parts[1]}'.lower() in COMBOS:
        base, gender = COMBOS[f'{parts[0]}, {parts[1]}'.lower()]
        rest = parts[2:]
    elif parts[0].lower() in BASES:
        base, gender = BASES[parts[0].lower()]
    else:
        return None, None
    out = [base]
    for m in rest:
        ru = MODS.get(m.lower())
        if ru is None:
            return None, None
        out.append(_inflect(ru[1:], gender) if ru.startswith('~') else ru)
    return ', '.join(out), 'glossary'


def uncovered(names):
    """Какие базовые слова и уточнения мешают перевести (для расширения глоссария)."""
    from collections import Counter
    b, m = Counter(), Counter()
    for n in names:
        parts = [p.strip() for p in n.split(',') if p.strip()]
        if parts and parts[0].lower() not in BASES:
            b[parts[0]] += 1
        for x in parts[1:]:
            if x.lower() not in MODS:
                m[x] += 1
    return b, m


def base_ru(name_en):
    """Русское название основы (первый сегмент) для поиска по-русски; None, если основы нет в глоссарии."""
    parts = [p.strip() for p in name_en.split(',') if p.strip()]
    if not parts:
        return None
    if len(parts) > 1 and f'{parts[0]}, {parts[1]}'.lower() in COMBOS:
        return COMBOS[f'{parts[0]}, {parts[1]}'.lower()][0]
    b = BASES.get(parts[0].lower())
    return b[0] if b else None
