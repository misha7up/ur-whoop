#!/usr/bin/env python3
"""
Генерирует VinWmiTable.kt и VinWmiTable.swift из таблицы Wikibooks WMI.

Источник (wikitext):
  https://en.wikibooks.org/wiki/Vehicle_Identification_Numbers_(VIN_codes)/World_Manufacturer_Identifier

Использование:
  python3 scripts/generate_vin_wmi_table.py
  python3 scripts/generate_vin_wmi_table.py --input /path/to/dump.wiki

По умолчанию скачивает action=raw (нужна сеть). Лицензия контента Wikibooks: CC BY-SA.
"""
from __future__ import annotations

import argparse
import re
import sys
import urllib.request
from pathlib import Path

WIKI_RAW_URL = (
    "https://en.wikibooks.org/w/index.php?"
    "title=Vehicle_Identification_Numbers_(VIN_codes)/World_Manufacturer_Identifier"
    "&action=raw"
)

REPO_ROOT = Path(__file__).resolve().parents[1]
OUT_KOTLIN = REPO_ROOT / "android/app/src/main/java/com/uremont/bluetooth/VinWmiTable.kt"
OUT_SWIFT = REPO_ROOT / "ios/UremontWhoop/OBD/VinWmiTable.swift"


def strip_wiki_md_links(text: str) -> str:
    out: list[str] = []
    i = 0
    n = len(text)
    while i < n:
        if text[i] == "[":
            j = text.find("]", i)
            if j == -1:
                out.append(text[i])
                i += 1
                continue
            if j + 1 < n and text[j + 1] == "(":
                link_text = text[i + 1 : j]
                k = j + 2
                depth = 1
                while k < n and depth:
                    if text[k] == "(":
                        depth += 1
                    elif text[k] == ")":
                        depth -= 1
                    k += 1
                out.append(link_text)
                i = k
                continue
        out.append(text[i])
        i += 1
    return "".join(out)


def clean_label(s: str) -> str:
    s = re.sub(r"<[^>]+>", "", s)
    s = strip_wiki_md_links(s)
    s = s.replace("'''", "").replace("''", "")
    if " made by " in s:
        s = s.split(" made by ")[0].strip()
    s = re.sub(r"\s*\([^)]*\)\s*$", "", s).strip()
    s = re.sub(r"\s+", " ", s).strip()
    s = re.sub(r"\)\s*$", "", s).strip()
    s = re.sub(r"^\(([^)]+)\)\s+", r"\1 ", s)
    s = re.sub(r"([^\s])&([^\s])", r"\1 & \2", s)
    s = re.sub(r"([A-Za-z0-9])&\s*", r"\1 & ", s)
    s = re.sub(r"\s+", " ", s).strip()
    if len(s) < 2 or len(s) > 80:
        return ""
    return s


def parse_wmi_table(text: str) -> dict[str, str]:
    pat = re.compile(r"^\| ([A-Z0-9]{3}) \| (.+?) \|$", re.MULTILINE)
    seen: dict[str, str] = {}
    for m in pat.finditer(text):
        wmi, raw = m.group(1), m.group(2)
        if wmi == "WMI":
            continue
        label = clean_label(raw)
        if label:
            seen[wmi] = label
    return seen


def esc_kotlin(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')


def esc_swift(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')


def write_kotlin(seen: dict[str, str]) -> None:
    lines = [
        "package com.uremont.bluetooth",
        "",
        "/**",
        " * Справочник WMI (первые 3 символа VIN) → отображаемое название производителя/завода.",
        " * Источник: Wikibooks «World Manufacturer Identifier» (community-maintained),",
        " * не заменяет официальную платную подписку SAE J1044.",
        " * Обновление: scripts/generate_vin_wmi_table.py",
        " */",
        "object VinWmiTable {",
        "",
        "    private val ENTRIES: Map<String, String> = mapOf(",
    ]
    for k in sorted(seen.keys()):
        lines.append(f'        "{k}" to "{esc_kotlin(seen[k])}",')
    lines.extend(
        [
            "    )",
            "",
            "    /** Возвращает подпись по WMI или null, если кода нет в таблице. */",
            "    fun getMake(wmi: String): String? = ENTRIES[wmi.uppercase()]",
            "}",
        ]
    )
    OUT_KOTLIN.write_text("\n".join(lines), encoding="utf-8")


def write_swift(seen: dict[str, str]) -> None:
    sl = [
        "import Foundation",
        "",
        "/// Справочник WMI → подпись производителя (Wikibooks, community).",
        "/// Обновление: scripts/generate_vin_wmi_table.py",
        "enum VinWmiTable {",
        "    private static let entries: [String: String] = [",
    ]
    for k in sorted(seen.keys()):
        sl.append(f'        "{k}": "{esc_swift(seen[k])}",')
    sl.extend(
        [
            "    ]",
            "",
            "    static func getMake(wmi: String) -> String? {",
            "        entries[wmi.uppercased()]",
            "    }",
            "}",
        ]
    )
    OUT_SWIFT.write_text("\n".join(sl), encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", type=Path, help="Локальный wikitext вместо загрузки")
    args = ap.parse_args()
    if args.input:
        text = args.input.read_text(encoding="utf-8", errors="replace")
    else:
        req = urllib.request.Request(
            WIKI_RAW_URL,
            headers={"User-Agent": "uremont-whoop-wmi-generator/1.0 (open source)"},
        )
        with urllib.request.urlopen(req, timeout=60) as resp:
            text = resp.read().decode("utf-8", errors="replace")
    seen = parse_wmi_table(text)
    if len(seen) < 500:
        print("error: слишком мало WMI, проверьте источник", file=sys.stderr)
        return 1
    write_kotlin(seen)
    write_swift(seen)
    print(f"OK: {len(seen)} WMI → {OUT_KOTLIN.relative_to(REPO_ROOT)}, {OUT_SWIFT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
