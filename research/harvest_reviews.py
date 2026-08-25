# -*- coding: utf-8 -*-
"""Събира публичните ревюта на конкурентните приложения от App Store (задача 1.1).

Ползва публичния RSS канал на Apple за клиентски ревюта. Без ключ, без акаунт.
Каналът връща само ревюта с текст, най-новите първи, до 500 на държава на
приложение — това не е случайна извадка и скриптът не се преструва, че е.

Суровите ревюта НЕ се комитват в хранилището: чужд текст, писан от хора, които
не са давали съгласие да бъдат препубликувани. Комитва се този скрипт, за да може
всеки да си възстанови данните и да провери изводите в docs/РЕВЮТА.md.

    python research/harvest_reviews.py <изходна-папка>
"""

import io
import json
import os
import re
import sys
import time
import urllib.request
from collections import Counter

# Идентификаторите са от публичното търсене в iTunes.
# „Present" от първоначалния списък не беше открит в App Store към 25.08.2026 г.
APPS = [
    ("Rootd",       1289018369, ["us", "gb", "ca", "au", "ie", "nz", "in", "za",
                                 "sg", "ph", "my", "ae", "de", "nl", "se", "dk",
                                 "no", "fi", "fr", "es", "it", "br", "mx", "jp"], 10),
    ("Dare",        1034311206, ["us", "gb", "ca", "au", "ie", "nz", "in", "za",
                                 "sg", "ph", "my", "ae", "de", "nl", "se", "dk",
                                 "no", "fi", "fr", "es", "it", "br", "mx", "jp"], 10),
    ("PanicShield", 1135763618, ["us", "gb", "ca", "au", "ie"], 5),
    ("Tap to Calm", 1615434239, ["us", "gb", "ca", "au", "ie"], 5),
    ("PanicHaven",  6448590219, ["us", "gb"], 3),
    ("panic.btn",   6757411632, ["us", "gb"], 3),
    ("ANIMA",       1454340067, ["bg", "us", "gb", "de"], 5),
]

FEED = ("https://itunes.apple.com/%s/rss/customerreviews"
        "/page=%d/id=%d/sortby=mostrecent/json")


def label(value, default=""):
    """Каналът връща ту {"label": ...}, ту гол низ. Изравнява двете."""
    if isinstance(value, dict):
        return value.get("label", default)
    if isinstance(value, str):
        return value
    return default


def fetch(country, app_id, page):
    request = urllib.request.Request(
        FEED % (country, page, app_id),
        headers={"User-Agent": "minava-research/0.1"})
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.loads(response.read().decode("utf-8"))


def harvest():
    rows, seen, errors = [], set(), 0
    for name, app_id, countries, max_page in APPS:
        for country in countries:
            for page in range(1, max_page + 1):
                try:
                    data = fetch(country, app_id, page)
                except Exception:
                    errors += 1
                    break
                entries = data.get("feed", {}).get("entry") or []
                if isinstance(entries, dict):
                    entries = [entries]
                # Първият запис описва самото приложение, не е ревю.
                entries = [e for e in entries
                           if isinstance(e, dict) and "im:rating" in e]
                fresh = 0
                for entry in entries:
                    review_id = label(entry.get("id"))
                    if review_id in seen:
                        continue
                    seen.add(review_id)
                    fresh += 1
                    rows.append({
                        "app": name,
                        "country": country,
                        "rating": int(label(entry["im:rating"], "0") or 0),
                        "version": label(entry.get("im:version")),
                        "title": label(entry.get("title")),
                        "text": label(entry.get("content")),
                    })
                if fresh == 0:
                    break
                time.sleep(0.12)
    return rows, errors


def summarise(rows, errors):
    critical = [r for r in rows if r["rating"] <= 3]
    total = Counter(r["app"] for r in rows)
    low = Counter(r["app"] for r in critical)
    lines = ["събрани: %d   критични (1-3 звезди): %d   неуспешни заявки: %d"
             % (len(rows), len(critical), errors), ""]
    lines.append("%-13s %8s %8s" % ("приложение", "всички", "1-3*"))
    for app in total:
        lines.append("%-13s %8d %8d" % (app, total[app], low[app]))
    return "\n".join(lines)


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    rows, errors = harvest()
    io.open(os.path.join(out_dir, "reviews.json"), "w", encoding="utf-8").write(
        json.dumps(rows, ensure_ascii=False, indent=1))
    report = summarise(rows, errors)
    io.open(os.path.join(out_dir, "reviews_summary.txt"), "w",
            encoding="utf-8").write(report)
    sys.stderr.write(report + "\n")


if __name__ == "__main__":
    main()
