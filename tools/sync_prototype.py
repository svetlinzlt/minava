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
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_DIR = os.path.join(ROOT, "clinical", "personal")
TARGET = os.path.join(ROOT, "docs", "prototype", "practices.js")

# Видовете, които прототипът показва по подразбиране.
PUBLISHABLE_KINDS = ("regulation", "grounding")

# Експозицията се пренася, но НЕ се предлага: стига до екрана само в личния режим,
# който е изключен по подразбиране, и само след екрана с противопоказанията. Това е
# уеб съответствието на BuildKind.personal — виж docs/ТЕСТ-НА-ТЕЛЕФОН.md.
PERSONAL_KINDS = ("exposure",)

# Редът на секциите на екрана. Отпред е онова, което човек посяга да направи, когато
# вече се чувства зле; отзад — онова, което се прави в спокоен момент.
SECTION_ORDER = ["nervous-system", "worry", "attention", "action", "mindset", "challenge"]

# Редът вътре в секция. Практика, която не е в списъка, не изчезва: влиза накрая, по
# азбучен ред.
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
    "worry-postponement",
    "thought-not-command",
    "detached-observation",
    "worry-window",
    "three-breaths",
    "breath-anchor",
    "sounds-around",
    "body-scan-slow",
    "one-small-step",
    "what-matters",
    "movement-dose",
    "normalizing-attitude",
    "three-steps-support",
    "safety-questions",
    "metacognition-questions",
    "graded-challenge",
    "ladder-crowd",
]

HEADER = u"""// Генериран файл. Не се редактира на ръка.
//
// Източник: clinical/personal/. Пренася се от tools/sync_prototype.py, а
// tools/sync_prototype.py --check проваля билда, ако двата текста се разминат.
//
// Експозиционните протоколи нарочно ги няма: прототипът е публичен, а
// степенуваното предизвикване няма екраниращи въпроси (задача 6.4).
window.MINAVA_PRACTICES = """

SCREENING_HEADER = u"""
window.MINAVA_SCREENING = """


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

        kind = doc.get("kind")
        if kind == "screening":
            # Екраниращият протокол не е упражнение; пренася се отделно.
            continue
        if kind not in PUBLISHABLE_KINDS and kind not in PERSONAL_KINDS:
            skipped.append((name, kind))
            continue
        # Одобреното живее в protocols/. Ако попадне тук, нещо е сгрешено и мълчаливото
        # пренасяне би го превърнало в „публикувано одобрено съдържание".
        if doc.get("status") != "draft":
            skipped.append((name, "status=%s" % doc.get("status")))
            continue

        entry = {
            "id": doc["id"],
            "title": doc["title"]["bg"],
            "section": doc["section"],
            "steps": steps_of(doc, "steps"),
        }
        if kind in PERSONAL_KINDS:
            # Единственият флаг, който интерфейсът гледа, преди да покаже нещо.
            entry["personalOnly"] = True
            entry["recovery"] = doc["recoveryProtocol"]
            entry["screening"] = doc["excludedBy"]
        if doc.get("situation"):
            entry["situation"] = doc["situation"]
        if doc.get("estimatedMinutes"):
            entry["minutes"] = doc["estimatedMinutes"]
        if doc.get("stopRule"):
            entry["stopRule"] = doc["stopRule"]["bg"]
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
        section = entry.get("section")
        return (SECTION_ORDER.index(section) if section in SECTION_ORDER
                else len(SECTION_ORDER),
                ORDER.index(entry["id"]) if entry["id"] in ORDER else len(ORDER),
                entry["id"])

    practices.sort(key=rank)
    return practices, skipped


def collect_screening():
    """Противопоказанията, като отделен запис.

    Не са упражнение и не стоят в каталога: прочитат се веднъж, точно преди
    предизвикване, и всеки отговор „да" го спира.
    """
    path = os.path.join(SOURCE_DIR, "exposure-screening.json")
    if not os.path.exists(path):
        return None
    doc = json.load(io.open(path, encoding="utf-8"))
    return {"id": doc["id"],
            "title": doc["title"]["bg"],
            "questions": [s["text"]["bg"] for s in doc.get("steps") or []]}


def rendered(practices, screening):
    body = json.dumps(practices, ensure_ascii=False, indent=2, sort_keys=True)
    text = HEADER + body + u";\n"
    if screening:
        text += SCREENING_HEADER + json.dumps(screening, ensure_ascii=False, indent=2,
                                              sort_keys=True) + u";\n"
    return text


def versions():
    """Номерът на версията в страницата и името на кеша в service worker-а.

    Двете трябва да вървят заедно. Разминат ли се, екранът ще показва версия, която
    телефонът няма, или кешът ще се смени, без човек да може да го види — и в двата
    случая въпросът „обнови ли се" остава без отговор.
    """
    page = io.open(os.path.join(ROOT, "docs", "prototype", "index.html"),
                   encoding="utf-8").read()
    worker = io.open(os.path.join(ROOT, "docs", "prototype", "sw.js"),
                     encoding="utf-8").read()

    in_page = re.search(r"var BUILD = (\d+);", page)
    in_worker = re.search(r'var CACHE = "minava-prototype-(\d+)";', worker)
    return (int(in_page.group(1)) if in_page else None,
            int(in_worker.group(1)) if in_worker else None)


def main():
    check = "--check" in sys.argv
    practices, skipped = collect()

    page_build, worker_build = versions()
    if page_build is None or worker_build is None:
        print("ГРЕШКА не намирам версията в index.html или в sw.js")
        return 1
    if page_build != worker_build:
        print("ГРЕШКА версията в index.html е %d, а кешът в sw.js е %d — вдигат се "
              "заедно" % (page_build, worker_build))
        return 1
    screening = collect_screening()
    if not screening:
        print("ГРЕШКА липсва екраниращият протокол за предизвикване")
        return 1
    text = rendered(practices, screening)

    for name, reason in skipped:
        print("пропуснато %s (%s)" % (name, reason))

    if not practices:
        print("ГРЕШКА няма нито една практика за прототипа")
        return 1

    def current(path):
        return io.open(path, encoding="utf-8").read() if os.path.exists(path) else None

    targets = ((TARGET, text, "clinical/personal/"),)

    if check:
        for path, body, source in targets:
            if current(path) != body:
                print("ГРЕШКА %s не е в крак с %s — пусни python tools/sync_prototype.py"
                      % (os.path.relpath(path, ROOT).replace(os.sep, "/"), source))
                return 1
        print("прототипът е в крак: %d практики" % len(practices))
        return 0

    for path, body, _ in targets:
        relative = os.path.relpath(path, ROOT).replace(os.sep, "/")
        if current(path) != body:
            with io.open(path, "w", encoding="utf-8", newline="\n") as handle:
                handle.write(body)
            print("записан %s" % relative)

    print("готово: %d практики" % len(practices))
    return 0


if __name__ == "__main__":
    sys.exit(main())
