# -*- coding: utf-8 -*-
"""Пази валидността на кризисните номера (задачи 1.3 и 9.1).

    python tools/check_lines.py
    python tools/check_lines.py --release

Грешен кризисен номер е по-лош от липсващ. Човек, който набира и попада на
затворена линия или на чужд човек, губи опита, който му е коствал най-много.

Затова всеки номер носи дата на **лична** проверка и кой я е направил. Проверка
по-стара от година не важи: линиите се закриват, сменят номера и променят работно
време, без да съобщават на никого.

Обикновеното пускане съобщава какво е просрочено. С --release просроченото и
непровереното проваля билда — това е портата преди пускане и преди всяка есенна
поддръжка.

Без външни зависимости. Изходен код 0 при успех, 1 при поне един проблем.
"""

from __future__ import print_function

import datetime
import io
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "content", "кризисни-линии.json")

REQUIRED = ["id", "name", "number", "hours", "languages", "verifiedOn", "verifiedBy"]
NUMBER = re.compile(r"^[0-9 ]{3,20}$")
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def parse_date(value):
    try:
        return datetime.date(*[int(part) for part in value.split("-")])
    except (ValueError, AttributeError):
        return None


def main():
    release = "--release" in sys.argv
    data = json.load(io.open(DATA, encoding="utf-8"))
    valid_days = data.get("verificationValidDays", 365)
    today = datetime.date.today()

    errors, notes = [], []
    seen = set()

    for line in data.get("lines", []):
        name = line.get("name", "без име")

        for field in REQUIRED:
            if field not in line:
                errors.append("%s: липсва поле %r" % (name, field))

        identifier = line.get("id")
        if identifier in seen:
            errors.append("%s: повторен идентификатор %r" % (name, identifier))
        seen.add(identifier)

        number = line.get("number")
        if not isinstance(number, str) or not NUMBER.match(number):
            errors.append("%s: %r не изглежда като телефонен номер" % (name, number))

        verified_on = line.get("verifiedOn")
        if verified_on is None:
            message = "%s (%s): никога не е проверяван лично" % (name, number)
            (errors if release else notes).append(message)
            continue

        if not DATE.match(str(verified_on)) or parse_date(verified_on) is None:
            errors.append("%s: %r не е дата във формат ГГГГ-ММ-ДД" % (name, verified_on))
            continue

        if not line.get("verifiedBy"):
            errors.append("%s: има дата на проверка, но не и кой я е направил" % name)

        age = (today - parse_date(verified_on)).days
        if age > valid_days:
            message = ("%s (%s): проверен преди %d дни — проверката важи %d"
                       % (name, number, age, valid_days))
            (errors if release else notes).append(message)
        elif age > valid_days - 60:
            notes.append("%s: проверката изтича след %d дни" % (name, valid_days - age))

    for message in notes:
        print("       %s" % message)
    for message in errors:
        print("ГРЕШКА %s" % message)

    total = len(data.get("lines", []))
    verified = sum(1 for line in data.get("lines", []) if line.get("verifiedOn"))
    print("линии: %d, проверени лично: %d, проблеми: %d%s"
          % (total, verified, len(errors), " (режим преди пускане)" if release else ""))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
