# -*- coding: utf-8 -*-
"""Пази офлайн обещанието в кода (задача 3.4).

    python tools/check_offline.py

Написано е **преди** да има код, нарочно. Така първият ред, който донесе мрежа
по паник пътя, се проваля още при първото пускане, вместо да бъде открит, когато
приложението вече е в App Store.

Без външни зависимости. Изходен код 0 при успех, 1 при поне едно нарушение.

Изключения се разрешават с коментар на същия или на предишния ред:

    let container = CKContainer(...)  // offline-exempt: синхронът е извън паник пътя

Изключение с празна или кратка причина не се приема. По паник пътя изключения
не се приемат изобщо — там правилото няма смисъл, ако може да се заобиколи.
"""

from __future__ import print_function

import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_DIRS = ["Sources", "Apps"]
SOURCE_SUFFIXES = (".swift", ".m", ".mm", ".h")

# Какво се разрешава на кой модул. Първото съвпадение по префикс печели.
# "panic" означава, че изключения не се приемат.
RULES = [
    ("Sources/MinavaPanic", {"allow": set(), "panic": True}),
    ("Sources/MinavaCore", {"allow": set(), "panic": True}),
    ("Sources/MinavaSync", {"allow": {"cloudkit"}, "panic": False}),
    ("Sources", {"allow": set(), "panic": False}),
    ("Apps", {"allow": {"cloudkit"}, "panic": False}),
]

GROUPS = {
    "network": [
        (r"\bURLSession\b", "URLSession"),
        (r"\bURLRequest\b", "URLRequest"),
        (r"\bNWConnection\b", "NWConnection"),
        (r"\bNWPathMonitor\b", "NWPathMonitor"),
        (r"^\s*import\s+Network\b", "import Network"),
        (r"^\s*import\s+CFNetwork\b", "import CFNetwork"),
        (r"\bWKWebView\b", "WKWebView"),
        (r"\b(data|download|upload)Task\b", "URLSession task"),
        (r"https?://[^\s\"']+", "адрес в кода"),
    ],
    "cloudkit": [
        (r"^\s*import\s+CloudKit\b", "import CloudKit"),
        (r"\bCKContainer\b", "CKContainer"),
        (r"\bCKDatabase\b", "CKDatabase"),
        (r"\bcloudKitDatabase\s*:", "cloudKitDatabase:"),
    ],
}

# Хващат се, но само като бележка — има законна употреба с локален файл.
SUSPICIOUS = [
    (r"\b(Data|String)\(contentsOf\s*:", "contentsOf: — локален файл ли е?"),
    (r"\bAVPlayer\s*\(\s*url\s*:", "AVPlayer(url:) — локален файл ли е?"),
]

EXEMPT = re.compile(r"//\s*offline-exempt\s*:\s*(.+)$")


def rule_for(rel_path):
    for prefix, rule in RULES:
        if rel_path.startswith(prefix + "/") or rel_path == prefix:
            return prefix, rule
    return None, None


def exemption(lines, index):
    """Причина за изключение от този или от предишния ред, ако има."""
    for candidate in (lines[index], lines[index - 1] if index else ""):
        found = EXEMPT.search(candidate)
        if found:
            return found.group(1).strip()
    return None


def scan_file(path, rel_path, rule, errors, notes):
    lines = io.open(path, encoding="utf-8", errors="replace").read().splitlines()
    for index, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("//") and not EXEMPT.search(line):
            continue

        for group, patterns in GROUPS.items():
            if group in rule["allow"]:
                continue
            for pattern, label in patterns:
                if not re.search(pattern, line):
                    continue
                reason = exemption(lines, index)
                where = "%s:%d" % (rel_path, index + 1)
                if reason and rule["panic"]:
                    errors.append("%s: %s — по паник пътя изключения не се приемат"
                                  % (where, label))
                elif reason and len(reason) < 10:
                    errors.append("%s: %s — изключението няма истинска причина"
                                  % (where, label))
                elif reason:
                    notes.append("%s: %s, разрешено: %s" % (where, label, reason))
                else:
                    errors.append("%s: %s не се допуска тук" % (where, label))

        for pattern, label in SUSPICIOUS:
            if re.search(pattern, line) and not exemption(lines, index):
                notes.append("%s: %s" % (rel_path + ":" + str(index + 1), label))


def collect():
    found = []
    for directory in SOURCE_DIRS:
        base = os.path.join(ROOT, directory)
        for current, dirs, files in os.walk(base):
            dirs[:] = [d for d in dirs if d not in (".build", "build", "DerivedData")]
            for name in files:
                if name.endswith(SOURCE_SUFFIXES):
                    path = os.path.join(current, name)
                    found.append((path, os.path.relpath(path, ROOT).replace(os.sep, "/")))
    return sorted(found, key=lambda pair: pair[1])


def main():
    files = collect()
    if not files:
        print("Още няма изходен код. Правилата са заредени и чакат:")
        for prefix, rule in RULES:
            allowed = ", ".join(sorted(rule["allow"])) or "нищо"
            hard = " (без изключения)" if rule["panic"] else ""
            print("  %-24s разрешено: %s%s" % (prefix + "/", allowed, hard))
        return 0

    errors, notes = [], []
    checked = 0
    for path, rel_path in files:
        prefix, rule = rule_for(rel_path)
        if rule is None:
            continue
        checked += 1
        scan_file(path, rel_path, rule, errors, notes)

    for message in notes:
        print("бележка %s" % message)
    for message in errors:
        print("ГРЕШКА  %s" % message)
    print("проверени %d файла, %d нарушения" % (checked, len(errors)))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
