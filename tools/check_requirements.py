# -*- coding: utf-8 -*-
"""Пази правилото, че няма изискване без източник (задача 1.5).

    python tools/check_requirements.py

Документ с изисквания загнива по един и същи начин навсякъде: някой добавя ред,
защото звучи разумно, никой не пита откъде идва, и след година никой не помни дали
е измерено, или е било предположение.

Затова редът без източник или без начин за проверка проваля билда.

Без външни зависимости. Изходен код 0 при успех, 1 при поне едно нарушение.
"""

from __future__ import print_function

import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCUMENT = os.path.join(ROOT, "docs", "ИЗИСКВАНИЯ.md")

# Кодовете, които се броят за източник. Всичко останало е несъществуващ източник.
KNOWN_SOURCES = re.compile(r"^(0\.[1-7]|1\.[1-5]|2\.[1-6]|3\.[1-7]|4\.[1-6]|5\.[1-5]|"
                           r"6\.[1-7]|7\.[1-3]|8\.[1-3]|9\.[1-3])$")

# Източници, които още не са свършени. Изискване, което стъпва само на тях, е
# вярване и трябва да е изброено в раздела "Изисквания без основа".
UNFINISHED = {"1.2", "1.3", "1.4"}

ROW = re.compile(r"^\|\s*(И-\d+)\s*\|(.+?)\|(.+?)\|(.+?)\|\s*$")
GAP_ROW = re.compile(r"^\|\s*(И-\d+)\s*\|", re.MULTILINE)


def parse():
    text = io.open(DOCUMENT, encoding="utf-8").read()
    body, _, gaps_section = text.partition("## Изисквания без основа")

    rows = []
    for number, line in enumerate(body.splitlines(), 1):
        match = ROW.match(line)
        if match:
            rows.append({
                "id": match.group(1),
                "text": match.group(2).strip(),
                "sources": [s.strip() for s in match.group(3).split(",") if s.strip()],
                "check": match.group(4).strip(),
                "line": number,
            })

    listed_gaps = set(GAP_ROW.findall(gaps_section))
    return rows, listed_gaps


def main():
    if not os.path.exists(DOCUMENT):
        print("ГРЕШКА липсва docs/ИЗИСКВАНИЯ.md")
        return 1

    rows, listed_gaps = parse()
    errors, notes = [], []
    seen = {}

    for row in rows:
        where = "ред %d (%s)" % (row["line"], row["id"])

        if row["id"] in seen:
            errors.append("%s: номерът вече е използван на ред %d"
                          % (where, seen[row["id"]]))
        seen[row["id"]] = row["line"]

        if not row["sources"]:
            errors.append("%s: няма източник" % where)
        for source in row["sources"]:
            if not KNOWN_SOURCES.match(source):
                errors.append("%s: %r не е задача от плана" % (where, source))

        if not row["check"]:
            errors.append("%s: няма начин за проверка" % where)

        grounded = [s for s in row["sources"] if s not in UNFINISHED]
        if row["sources"] and not grounded and row["id"] not in listed_gaps:
            errors.append("%s: стъпва само на несвършена задача (%s), но липсва в "
                          "раздела „Изисквания без основа“"
                          % (where, ", ".join(row["sources"])))

    for identifier in sorted(listed_gaps):
        if identifier not in seen:
            errors.append("%s е изброено като без основа, но такова изискване няма"
                          % identifier)

    notes.append("изисквания: %d" % len(rows))
    notes.append("без затворена основа: %d" % len(listed_gaps))

    for message in notes:
        print("       %s" % message)
    for message in errors:
        print("ГРЕШКА %s" % message)
    print("проверени %d изисквания, %d нарушения" % (len(rows), len(errors)))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
