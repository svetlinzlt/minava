# -*- coding: utf-8 -*-
"""Пази секундите до първото вдишване (задача 4.2).

    python tools/check_timings.py
    python tools/check_timings.py --require-all   # преди пускане

Числата не се пазят в документ, защото документът остарява мълчаливо. Пази ги
проверка, която върви при всеки билд и се проваля, когато вход излезе над бюджета
си.

Неизмерен вход не е грешка днес — приложението още го няма. С --require-all е.

Методът за измерване е в docs/ИЗМЕРВАНЕ.md. Без него числата тук не значат нищо.
"""

from __future__ import print_function

import io
import json
import os
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "research", "entry-timings.json")

REQUIRED_FIELDS = ["date", "app", "entry", "device", "os", "coldStart", "locked", "seconds"]


def load():
    return json.load(io.open(DATA, encoding="utf-8"))


def check_shape(record, index, errors):
    for field in REQUIRED_FIELDS:
        if field not in record:
            errors.append("измерване #%d: липсва %r" % (index, field))
    seconds = record.get("seconds")
    if seconds is not None and (not isinstance(seconds, (int, float)) or seconds <= 0):
        errors.append("измерване #%d: seconds трябва да е положително число" % index)
    if "runs" in record and not isinstance(record["runs"], list):
        errors.append("измерване #%d: runs трябва да е списък от трите опита" % index)


def check_budget(record, index, budgets, ceiling, errors):
    entry = record.get("entry")
    if entry not in budgets:
        errors.append("измерване #%d: непознат вход %r — добави го в budgets, ако е нов"
                      % (index, entry))
        return
    if record.get("app") != "minava":
        return

    limit = ceiling if record.get("coldStart") else budgets[entry]
    label = "студен старт" if record.get("coldStart") else "бюджет"
    seconds = record.get("seconds")
    if isinstance(seconds, (int, float)) and seconds > limit:
        errors.append("%s на %s: %.2f сек при %s %.2f — пътят се смята за счупен"
                      % (entry, record.get("device", "?"), seconds, label, limit))


def report_coverage(data, measurements, require_all, errors, notes):
    ours = defaultdict(list)
    for record in measurements:
        if record.get("app") == "minava":
            ours[record.get("entry")].append(record.get("seconds"))

    for entry in sorted(data["budgets"]):
        values = [v for v in ours.get(entry, []) if isinstance(v, (int, float))]
        if values:
            notes.append("%-22s най-добро %.2f, най-лошо %.2f, бюджет %.1f"
                         % (entry, min(values), max(values), data["budgets"][entry]))
        elif require_all:
            errors.append("%s няма нито едно измерване" % entry)
        else:
            notes.append("%-22s още не е измерван" % entry)


def main():
    require_all = "--require-all" in sys.argv
    data = load()
    measurements = data.get("measurements", [])
    budgets = data.get("budgets", {})
    ceiling = data.get("ceilingColdStart", 5.0)

    errors, notes = [], []
    for index, record in enumerate(measurements, 1):
        check_shape(record, index, errors)
        check_budget(record, index, budgets, ceiling, errors)

    report_coverage(data, measurements, require_all, errors, notes)

    for message in notes:
        print("       %s" % message)
    for message in errors:
        print("ГРЕШКА %s" % message)

    print("измервания: %d, входове: %d, грешки: %d%s"
          % (len(measurements), len(budgets), len(errors),
             " (режим преди пускане)" if require_all else ""))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
