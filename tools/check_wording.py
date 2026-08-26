# -*- coding: utf-8 -*-
"""Пази езика на текста, който потребителят вижда (задача 5.2).

    python tools/check_wording.py

Границата между приложение за самопомощ и медицинско изделие минава през езика, не
през кода. Едно изречение в App Store може да вкара целия проект в регулаторна
територия, която безплатен проект не може да поддържа. Обосновката е в
docs/МЕДИЦИНСКО-ИЗДЕЛИЕ.md.

Проверяват се само файловете, изброени в content/забранени-думи.json — текстът,
който стига до човек. Вътрешните документи обсъждат тези думи по необходимост и не
се проверяват.

Изключение се допуска само ако е записано в самия списък, с файл и причина. Няма
изключение с коментар в текста: изключенията трябва да са на едно място, където
юрист може да ги прегледа наведнъж.

Без външни зависимости. Изходен код 0 при успех, 1 при поне едно нарушение.
"""

from __future__ import print_function

import io
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIST = os.path.join(ROOT, "content", "забранени-думи.json")

TAG = re.compile(r"<[^>]+>")


def visible_text(path, raw):
    """HTML се чисти от етикети — интересува ни какво се чете, не как е направено."""
    if path.endswith((".html", ".htm")):
        return TAG.sub(" ", raw)
    return raw


def allowances(data):
    allowed = {}
    for entry in data.get("allow", []):
        allowed.setdefault(entry["where"], set()).add(entry["pattern"].lower())
    return allowed


def main():
    data = json.load(io.open(LIST, encoding="utf-8"))
    allowed = allowances(data)

    errors, notes = [], []
    scanned = 0

    for relative in data.get("scan", []):
        path = os.path.join(ROOT, relative.replace("/", os.sep))
        if not os.path.exists(path):
            notes.append("%s още не съществува — ще се проверява, щом го има" % relative)
            continue

        scanned += 1
        raw = io.open(path, encoding="utf-8", errors="replace").read()
        text = visible_text(relative, raw).lower()
        permitted = allowed.get(relative, set())

        for group in data.get("groups", []):
            for pattern in group["patterns"]:
                needle = pattern.lower()
                if needle not in text:
                    continue
                if needle in permitted:
                    notes.append("%s: %r е разрешено изрично (%s)"
                                 % (relative, pattern, group["reason"]))
                    continue
                line = line_of(text, needle)
                errors.append("%s ред %d: %r — %s"
                              % (relative, line, pattern, group["reason"]))

    for entry in data.get("allow", []):
        target = os.path.join(ROOT, entry["where"].replace("/", os.sep))
        if os.path.exists(target):
            body = visible_text(entry["where"],
                                io.open(target, encoding="utf-8",
                                        errors="replace").read()).lower()
            if entry["pattern"].lower() not in body:
                notes.append("изключението за %r в %s вече не се ползва — може да отпадне"
                             % (entry["pattern"], entry["where"]))

    for message in notes:
        print("       %s" % message)
    for message in errors:
        print("ГРЕШКА %s" % message)

    print("проверени %d файла, %d нарушения (списъкът е %s)"
          % (scanned, len(errors), data.get("status", "без статус")))
    return 1 if errors else 0


def line_of(text, needle):
    index = text.find(needle)
    return text.count("\n", 0, index) + 1 if index >= 0 else 0


if __name__ == "__main__":
    sys.exit(main())
