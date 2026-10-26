#!/usr/bin/env python3
"""Fail CI when the English/Russian Localizable.strings files drift apart."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCALES = ("en", "ru")
ENTRY = re.compile(r'^"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)";', re.MULTILINE)
PLACEHOLDER = re.compile(
    r'%(?:\d+\$)?[-+#0 ]*\d*(?:\.\d+)?(?:hh|h|ll|l|z|t|j)?[@diuoxXfFeEgGaAcCsSpn%]'
)
# Literal keys passed to SwiftUI APIs that implicitly/localize through LocalizedStringKey.
UI_KEY_PATTERNS = (
    re.compile(r'\bText\(\s*"((?:\\.|[^"\\])*)"\s*\)'),
    re.compile(r'\bButton\(\s*"((?:\\.|[^"\\])*)"'),
    re.compile(r'\bLabel\(\s*"((?:\\.|[^"\\])*)"'),
    re.compile(r'\bnavigationTitle\(\s*"((?:\\.|[^"\\])*)"\s*\)'),
    re.compile(r'\baccessibilityLabel\(\s*"((?:\\.|[^"\\])*)"\s*\)'),
    re.compile(r'\bLocalizedStringKey\(\s*"((?:\\.|[^"\\])*)"\s*\)'),
    re.compile(r'\b(?:alert|confirmationDialog)\(\s*"((?:\\.|[^"\\])*)"'),
    # UI component arguments are often passed through reusable components that
    # render them as LocalizedStringKey (for example SectionHeading/ActionRow).
    re.compile(r'\b(?:title|detail):\s*"((?:\\.|[^"\\])*)"'),
)
UI_LITERAL_EXCEPTIONS = {"PunPlayer"}  # Brand name, not a translation key.


def unescape(value: str) -> str:
    return value.replace(r'\n', '\n').replace(r'\t', '\t').replace(r'\"', '"').replace(r'\\', '\\')


def load(locale: str) -> dict[str, str]:
    path = ROOT / "PunPlayer" / "Resources" / f"{locale}.lproj" / "Localizable.strings"
    if not path.is_file():
        raise ValueError(f"Missing localization file: {path}")
    raw = path.read_text(encoding="utf-8")
    pairs = [(unescape(key), unescape(value)) for key, value in ENTRY.findall(raw)]
    if not pairs:
        raise ValueError(f"No keys parsed from {path}")
    result: dict[str, str] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate key {key!r} in {path}")
        result[key] = value
    # Strip %% (escaped percent) from the signature so it is not treated as an argument.
    return result


def signature(value: str) -> list[str]:
    return [token for token in PLACEHOLDER.findall(value) if token != "%%"]


def main() -> int:
    try:
        tables = {locale: load(locale) for locale in LOCALES}
        en, ru = tables["en"], tables["ru"]
        missing_ru = sorted(set(en) - set(ru))
        missing_en = sorted(set(ru) - set(en))
        if missing_ru or missing_en:
            if missing_ru:
                print("Missing Russian keys:", *missing_ru, sep="\n  ", file=sys.stderr)
            if missing_en:
                print("Missing English keys:", *missing_en, sep="\n  ", file=sys.stderr)
            return 1
        bad_formats = [
            key for key in en
            if signature(en[key]) != signature(ru[key])
        ]
        if bad_formats:
            print("Format placeholders differ between locales:", *bad_formats, sep="\n  ", file=sys.stderr)
            return 1

        missing_ui: list[str] = []
        for source in (ROOT / "PunPlayer" / "UI").rglob("*.swift"):
            content = source.read_text(encoding="utf-8")
            for pattern in UI_KEY_PATTERNS:
                for match in pattern.finditer(content):
                    key = unescape(match.group(1))
                    if key not in en and key not in UI_LITERAL_EXCEPTIONS:
                        missing_ui.append(f"{source.relative_to(ROOT)}: {key}")
        if missing_ui:
            print("Static UI keys missing from localization files:", *sorted(set(missing_ui)), sep="\n  ", file=sys.stderr)
            return 1

        print(f"Localization check passed: {len(en)} matching keys (en/ru), format placeholders agree, static UI keys present.")
        return 0
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
