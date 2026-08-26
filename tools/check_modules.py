# -*- coding: utf-8 -*-
"""Пази посоката между модулите (задача 3.5).

    python tools/check_modules.py

Ядрото не знае за интерфейса, интерфейсът зависи от ядрото, и никога обратното.
Един import в грешната посока се поправя за минута днес и за седмица след година.

Без външни зависимости. Изходен код 0 при успех, 1 при поне едно нарушение.
"""

from __future__ import print_function

import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = os.path.join(ROOT, "Sources")

# Трябва да съвпада с Package.swift. Разминаване се съобщава като грешка.
ALLOWED = {
    "MinavaCore": {"Foundation"},
    "MinavaPanic": {"Foundation", "MinavaCore"},
    "MinavaSync": {"Foundation", "MinavaCore", "CloudKit", "SwiftData"},
    # Единственият модул с достъп до хардуерната хаптика. Границата, която пази
    # ядрото, е между MinavaPanic и него — не между пакета и приложението.
    "MinavaHaptics": {"Foundation", "MinavaCore", "MinavaPanic", "CoreHaptics", "WatchKit"},
}

# Не влизат в модул, който не ги е поискал изрично в ALLOWED. Интерфейсът и
# устройството са на приложенията; модулите общуват с тях през протоколи.
BELONGS_TO_APPS = {
    "SwiftUI", "UIKit", "AppKit", "WatchKit", "WidgetKit", "ActivityKit",
    "CoreHaptics", "AVFoundation", "AVFAudio", "UserNotifications",
}

IMPORT = re.compile(r"^\s*(?:@[A-Za-z_]+\s+)*import\s+(?:struct|class|enum|protocol|func|var|let\s+)?\s*([A-Za-z_][A-Za-z0-9_]*)")


def modules_on_disk():
    if not os.path.isdir(SOURCES):
        return []
    return sorted(name for name in os.listdir(SOURCES)
                  if os.path.isdir(os.path.join(SOURCES, name)))


def declared_dependencies():
    """Грубо изчитане на Package.swift — само за да се хване разминаване."""
    path = os.path.join(ROOT, "Package.swift")
    if not os.path.exists(path):
        return None
    text = io.open(path, encoding="utf-8").read()
    found = {}
    for match in re.finditer(r'\.target\(\s*name:\s*"([A-Za-z0-9_]+)"([^)]*)\)', text):
        name, tail = match.group(1), match.group(2)
        found[name] = set(re.findall(r'"([A-Za-z0-9_]+)"', tail))
    return found


def check_imports(errors):
    for module in modules_on_disk():
        if module not in ALLOWED:
            errors.append("Sources/%s/: модул без правило в tools/check_modules.py" % module)
            continue
        base = os.path.join(SOURCES, module)
        for current, dirs, files in os.walk(base):
            dirs[:] = [d for d in dirs if not d.startswith(".")]
            for name in sorted(files):
                if not name.endswith(".swift"):
                    continue
                path = os.path.join(current, name)
                rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
                for index, line in enumerate(
                        io.open(path, encoding="utf-8", errors="replace").read().splitlines()):
                    match = IMPORT.match(line)
                    if not match:
                        continue
                    imported = match.group(1)
                    where = "%s:%d" % (rel, index + 1)
                    if imported in ALLOWED[module]:
                        continue
                    if imported in BELONGS_TO_APPS:
                        errors.append("%s: import %s — интерфейсът и устройството са на "
                                      "приложенията, не на модулите" % (where, imported))
                    elif imported not in ALLOWED[module]:
                        errors.append("%s: %s няма право да внася %s"
                                      % (where, module, imported))


def check_package(errors):
    declared = declared_dependencies()
    if declared is None:
        errors.append("липсва Package.swift")
        return
    for module, allowed in ALLOWED.items():
        if module not in declared:
            errors.append("Package.swift няма цел %s" % module)
            continue
        internal_allowed = {name for name in allowed if name.startswith("Minava")}
        if declared[module] - {module} != internal_allowed:
            errors.append("Package.swift: зависимостите на %s (%s) не съвпадат с правилата "
                          "тук (%s)" % (module,
                                        ", ".join(sorted(declared[module] - {module})) or "няма",
                                        ", ".join(sorted(internal_allowed)) or "няма"))


def main():
    if not modules_on_disk():
        print("Още няма модули. Правилата са заредени и чакат:")
        for module in sorted(ALLOWED):
            print("  %-14s може да внася: %s" % (module, ", ".join(sorted(ALLOWED[module]))))
        return 0

    errors = []
    check_package(errors)
    check_imports(errors)
    for message in errors:
        print("ГРЕШКА  %s" % message)
    print("проверени %d модула, %d нарушения" % (len(modules_on_disk()), len(errors)))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
