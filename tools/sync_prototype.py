# -*- coding: utf-8 -*-
"""Пренася практиките от clinical/personal/ в уеб прототипа.

    python tools/sync_prototype.py           # презаписва docs/prototype/practices.js
    python tools/sync_prototype.py --check    # само проверява дали файлът е в крак

Прототипът е статична страница и не може да чете clinical/. Затова практиките се
пренасят в генериран файл. Генериран значи, че не се пипа на ръка: ако някой промени
текст в clinical/personal/ и забрави прототипа, --check проваля билда вместо да
остави двата текста да се разминат мълчаливо.

**Какво нарочно НЕ се пренася.** Експозиция. Прототипът се публикува на GitHub Pages,
тоест всеки с адреса може да го отвори, а степенуваното предизвикване няма екраниращи
въпроси (задача 6.4). Упражнение, което вдига активацията, не се предлага на непознат
без тях. Това не е бележка в документ, а правило в този скрипт.

Без външни зависимости. Изходен код 0 при успех, 1 при разминаване или при отказан файл.
"""

from __future__ import print_function

import io
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_DIR = os.path.join(ROOT, "clinical", "personal")
TARGET = os.path.join(ROOT, "docs", "prototype", "practices.js")

# Видовете, които прототипът има право да показва.
PUBLISHABLE_KINDS = ("regulation", "grounding")

# Редът на списъка. Азбучният ред по id е случаен за човека, който гледа екрана, а
# първите две-три неща са единствените, които някой ще пробва в лош ден. Затова най-
# отпред стоят най-късите и най-физическите, а въпросите — най-отзад.
#
# Практика, която не е в списъка, не изчезва: влиза накрая, по азбучен ред.
ORDER = [
    "cold-water",
    "shoulders-belly-release",
    "orienting-room",
    "senses-grounding",
    "palm-on-body",
    "self-hug",
    "body-scan-exhale",
    "belly-breathing",
    "humming",
    "salamander",
    "nadi-shodhana",
    "normalizing-attitude",
    "three-steps-support",
    "safety-questions",
    "metacognition-questions",
]

HEADER = u"""// Генериран файл. Не се редактира на ръка.
//
// Източник: clinical/personal/. Пренася се от tools/sync_prototype.py, а
// tools/sync_prototype.py --check проваля билда, ако двата текста се разминат.
//
// Експозиционните протоколи нарочно ги няма: прототипът е публичен, а
// степенуваното предизвикване няма екраниращи въпроси (задача 6.4).
window.MINAVA_PRACTICES = """


def steps_of(doc, field):
    out = []
    for step in doc.get(field) or []:
        item = {"bg": step["text"]["bg"]}
        if step.get("minDuration") is not None:
            item["min"] = step["minDuration"]
        out.append(item)
    return out


def collect():
    practices, skipped = [], []
    if not os.path.isdir(SOURCE_DIR):
        return practices, skipped

    for name in sorted(os.listdir(SOURCE_DIR)):
        if not name.endswith(".json"):
            continue
        doc = json.load(io.open(os.path.join(SOURCE_DIR, name), encoding="utf-8"))

        if doc.get("kind") not in PUBLISHABLE_KINDS:
            skipped.append((name, doc.get("kind")))
            continue
        # Одобреното живее в protocols/. Ако попадне тук, нещо е сгрешено и мълчаливото
        # пренасяне би го превърнало в „публикувано одобрено съдържание".
        if doc.get("status") != "draft":
            skipped.append((name, "status=%s" % doc.get("status")))
            continue

        entry = {
            "id": doc["id"],
            "title": doc["title"]["bg"],
            "steps": steps_of(doc, "steps"),
        }
        preparation = steps_of(doc, "preparation")
        if preparation:
            entry["preparation"] = preparation
        if doc.get("rounds"):
            entry["rounds"] = doc["rounds"]
        if doc.get("sides"):
            entry["sides"] = doc["sides"]
        if doc.get("measure"):
            entry["measure"] = doc["measure"]
        practices.append(entry)

    def rank(entry):
        return (ORDER.index(entry["id"]) if entry["id"] in ORDER else len(ORDER),
                entry["id"])

    practices.sort(key=rank)
    return practices, skipped


def rendered(practices):
    body = json.dumps(practices, ensure_ascii=False, indent=2, sort_keys=True)
    return HEADER + body + u";\n"


def main():
    check = "--check" in sys.argv
    practices, skipped = collect()
    text = rendered(practices)

    for name, reason in skipped:
        print("пропуснато %s (%s)" % (name, reason))

    if not practices:
        print("ГРЕШКА няма нито една практика за прототипа")
        return 1

    existing = None
    if os.path.exists(TARGET):
        existing = io.open(TARGET, encoding="utf-8").read()

    if check:
        if existing != text:
            print("ГРЕШКА docs/prototype/practices.js не е в крак с clinical/personal/ — "
                  "пусни python tools/sync_prototype.py")
            return 1
        print("прототипът е в крак: %d практики" % len(practices))
        return 0

    if existing != text:
        with io.open(TARGET, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
        print("записани %d практики в docs/prototype/practices.js" % len(practices))
    else:
        print("без промяна: %d практики" % len(practices))
    return 0


if __name__ == "__main__":
    sys.exit(main())
