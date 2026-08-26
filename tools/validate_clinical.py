# -*- coding: utf-8 -*-
"""Проверява клиничните файлове срещу схемата (задача 3.1).

    python tools/validate_clinical.py            # проверява всичко
    python tools/validate_clinical.py --release  # плюс: отказва неодобрено

Без външни зависимости. Приложението няма нито една и инструментите също нямат
— всяка зависимост е нов начин билдът да се счупи след ъпдейт.

Схемата в clinical/schema/ е договорът. Тук е малък интерпретатор на тази част
от JSON Schema, която схемата наистина използва, плюс проверките между полета,
които схемата не може да изрази.

Изходен код 0 при успех, 1 при поне една грешка. Предупрежденията не спират билда.
"""

from __future__ import print_function

import io
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCHEMA_PATH = os.path.join(ROOT, "clinical", "schema", "protocol.schema.json")
PROTOCOL_DIR = os.path.join(ROOT, "clinical", "protocols")
EXAMPLE_DIR = os.path.join(ROOT, "clinical", "examples")

MAX_TOTAL_SECONDS = 20 * 60
PHASE_ORDER = ["inhale", "holdIn", "exhale", "holdOut"]


# --- малкият интерпретатор на схемата ---------------------------------------

def check(schema, value, path, errors):
    if "const" in schema and value != schema["const"]:
        errors.append("%s: очаква се %r" % (path, schema["const"]))
        return

    if "oneOf" in schema:
        for option in schema["oneOf"]:
            branch = []
            check(option, value, path, branch)
            if not branch:
                return
        errors.append("%s: не отговаря на нито един от допустимите варианти" % path)
        return

    expected = schema.get("type")
    if expected and not has_type(value, expected):
        errors.append("%s: очаква се %s, а е %s"
                      % (path, expected, type(value).__name__))
        return

    if "enum" in schema and value not in schema["enum"]:
        errors.append("%s: %r не е сред %s" % (path, value, schema["enum"]))

    if expected == "object" and isinstance(value, dict):
        check_object(schema, value, path, errors)
    elif expected == "array" and isinstance(value, list):
        check_array(schema, value, path, errors)
    elif expected == "string" and isinstance(value, str):
        check_string(schema, value, path, errors)
    elif expected in ("number", "integer"):
        check_number(schema, value, path, errors)


def has_type(value, expected):
    if expected == "object":
        return isinstance(value, dict)
    if expected == "array":
        return isinstance(value, list)
    if expected == "string":
        return isinstance(value, str)
    if expected == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if expected == "null":
        return value is None
    return True


def check_object(schema, value, path, errors):
    properties = schema.get("properties", {})
    for name in schema.get("required", []):
        if name not in value:
            errors.append("%s: липсва задължителното поле %r" % (path, name))
    if schema.get("additionalProperties") is False:
        for name in value:
            if name not in properties:
                errors.append("%s: непознато поле %r" % (path, name))
    for name, sub in properties.items():
        if name in value:
            check(sub, value[name], "%s.%s" % (path, name), errors)


def check_array(schema, value, path, errors):
    if "minItems" in schema and len(value) < schema["minItems"]:
        errors.append("%s: поне %d елемента" % (path, schema["minItems"]))
    if "maxItems" in schema and len(value) > schema["maxItems"]:
        errors.append("%s: най-много %d елемента" % (path, schema["maxItems"]))
    if "items" in schema:
        for index, item in enumerate(value):
            check(schema["items"], item, "%s[%d]" % (path, index), errors)


def check_string(schema, value, path, errors):
    if "minLength" in schema and len(value) < schema["minLength"]:
        errors.append("%s: поне %d знака" % (path, schema["minLength"]))
    if "pattern" in schema and not re.match(schema["pattern"], value):
        errors.append("%s: %r не отговаря на %s" % (path, value, schema["pattern"]))


def check_number(schema, value, path, errors):
    if "minimum" in schema and value < schema["minimum"]:
        errors.append("%s: под долната граница %s" % (path, schema["minimum"]))
    if "maximum" in schema and value > schema["maximum"]:
        errors.append("%s: над горната граница %s" % (path, schema["maximum"]))


# --- проверките, които схемата не може да изрази ----------------------------

def check_consistency(doc, errors, warnings):
    kind = doc.get("kind")
    if kind == "breathing" and "breathing" not in doc:
        errors.append("kind е breathing, но липсва блокът breathing")
    if kind == "grounding" and "steps" not in doc:
        errors.append("kind е grounding, но липсват steps")

    approval = doc.get("approval")
    status = doc.get("status")
    if status == "approved" and approval is None:
        errors.append("status е approved, а approval е празно")
    if approval is not None and status != "approved":
        errors.append("има approval, а status не е approved")
    if isinstance(approval, dict):
        if approval.get("appliesToVersion") != doc.get("version"):
            errors.append(
                "одобрението е за версия %s, а файлът е версия %s — одобрението е "
                "на конкретна версия, не на протокола по принцип"
                % (approval.get("appliesToVersion"), doc.get("version")))

    breathing = doc.get("breathing")
    if isinstance(breathing, dict):
        check_breathing(breathing, errors, warnings)


def check_breathing(breathing, errors, warnings):
    phases = breathing.get("cycle", {}).get("phases", [])
    types = [p.get("type") for p in phases if isinstance(p, dict)]

    if "inhale" not in types:
        errors.append("цикълът няма вдишване")
    if "exhale" not in types:
        errors.append("цикълът няма издишване")
    if len(set(types)) != len(types):
        errors.append("фаза се повтаря в един цикъл: %s" % types)

    rank = [PHASE_ORDER.index(t) for t in types if t in PHASE_ORDER]
    if rank != sorted(rank):
        errors.append("фазите не са в реда вдишване, задържане горе, издишване, "
                      "задържане долу: %s" % types)

    cycle_seconds = sum(p.get("duration", 0) for p in phases if isinstance(p, dict))
    cycles = breathing.get("repeat", {}).get("cycles", 0)
    factor = breathing.get("repeat", {}).get("firstCycleFactor", 1)
    total = (breathing.get("entry", {}).get("duration", 0)
             + cycle_seconds * (cycles - 1 + factor)
             + breathing.get("exit", {}).get("duration", 0))
    if total > MAX_TOTAL_SECONDS:
        errors.append("общата продължителност е %.0f сек, таванът е %d"
                      % (total, MAX_TOTAL_SECONDS))

    tempo = breathing.get("userTempo")
    if isinstance(tempo, dict) and not (tempo.get("min", 1) <= 1 <= tempo.get("max", 1)):
        errors.append("userTempo не съдържа 1.0 — нормалното темпо трябва да е достижимо")

    if cycle_seconds and total < 20:
        warnings.append("упражнението трае под 20 секунди — проверено ли е, че е нарочно?")


# --- обхождане ---------------------------------------------------------------

def load(path, errors):
    try:
        return json.load(io.open(path, encoding="utf-8"))
    except ValueError as exc:
        errors.append("невалиден JSON: %s" % exc)
        return None


def validate_file(path, schema):
    errors, warnings = [], []
    doc = load(path, errors)
    if doc is None:
        return errors, warnings
    check(schema, doc, "$", errors)
    if not errors:
        check_consistency(doc, errors, warnings)
    expected_name = "%s.json" % doc.get("id", "")
    base = os.path.basename(path)
    if base not in (expected_name, "%s.example.json" % doc.get("id", "")):
        warnings.append("името на файла не съвпада с id (%r)" % doc.get("id"))
    return errors, warnings


def collect(directory):
    if not os.path.isdir(directory):
        return []
    return sorted(os.path.join(directory, name)
                  for name in os.listdir(directory) if name.endswith(".json"))


def main():
    release = "--release" in sys.argv
    schema = json.load(io.open(SCHEMA_PATH, encoding="utf-8"))

    shipped = collect(PROTOCOL_DIR)
    examples = collect(EXAMPLE_DIR)
    failed = 0
    seen_ids = {}

    for path in shipped + examples:
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        errors, warnings = validate_file(path, schema)

        doc = load(path, [])
        if isinstance(doc, dict) and doc.get("id"):
            if doc["id"] in seen_ids:
                errors.append("id %r се използва и в %s" % (doc["id"], seen_ids[doc["id"]]))
            seen_ids[doc["id"]] = rel

        if release and path in shipped:
            if not isinstance(doc, dict) or doc.get("status") != "approved":
                errors.append("релийз билд: протокол без писмено одобрение")

        for message in errors:
            print("ГРЕШКА  %s: %s" % (rel, message))
        for message in warnings:
            print("бележка %s: %s" % (rel, message))
        if errors:
            failed += 1

    total = len(shipped) + len(examples)
    if release and not shipped:
        print("бележка clinical/protocols/: няма нито един одобрен протокол — "
              "приложението се пуска без съответната част")

    print("проверени %d файла, %d с грешки%s"
          % (total, failed, " (режим релийз)" if release else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
