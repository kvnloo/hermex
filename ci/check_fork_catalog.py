#!/usr/bin/env python3
"""Check Fork table calls and translations without an Xcode build."""

import argparse
import json
from pathlib import Path
import re
import sys

REPO = Path(__file__).resolve().parents[1]
RESOURCES = REPO / "HermesMobile" / "Resources"
TABLE_ARGUMENT = re.compile(r'\btable(?:Name)?\s*:\s*"Fork"')
LITERAL_CALL = re.compile(
    r'\b(?:Text|String|LocalizedStringResource)\(\s*(?:localized:\s*)?'
    r'"(?P<literal>(?:[^"\\\n]|\\.)*)"\s*,\s*(?P<table>' + TABLE_ARGUMENT.pattern + ')'
)
ESCAPE = re.compile(r'\\(?:\(([^()]*)\)|(.))')
NUMERIC_INTERPOLATIONS = {"tools", "probe.tools.count", "reply.status"}
OBJECT_INTERPOLATIONS = {"spec.name", "key", "role", "value", "target.connection.name"}
FORMAT_TOKEN = re.compile(r'%(?:(\d+)\$)?(lld|@)')


def catalog_key(literal):
    def replace(match):
        expression, escape = match.groups()
        if expression is not None:
            expression = expression.strip()
            if expression in NUMERIC_INTERPOLATIONS:
                return "%lld"
            if expression in OBJECT_INTERPOLATIONS:
                return "%@"
            raise ValueError(f"unknown interpolation: {expression}")
        if escape in {'"', "\\", "n", "r", "t"}:
            return json.loads('"' + match[0] + '"')
        raise ValueError(f"unsupported Swift escape: {match[0]}")

    return ESCAPE.sub(replace, literal)


def extracted_keys(root):
    keys = set()
    errors = []
    for source in sorted(root.rglob("*.swift")):
        text = source.read_text(encoding="utf-8")
        calls = {match.start("table"): match["literal"] for match in LITERAL_CALL.finditer(text)}
        for table in TABLE_ARGUMENT.finditer(text):
            try:
                if table.start() not in calls:
                    raise ValueError("expected a direct Swift literal before the Fork table argument")
                keys.add(catalog_key(calls[table.start()]))
            except ValueError as error:
                line = text.count("\n", 0, table.start()) + 1
                errors.append(f"{source.relative_to(root)}:{line}: {error}")
    return keys, errors


def shipped_languages(catalog):
    return {catalog["sourceLanguage"]} | {
        language for entry in catalog["strings"].values() for language in entry.get("localizations", {})
    }


def format_arguments(text):
    return sorted((int(index) if index else i, kind)
                  for i, (index, kind) in enumerate(FORMAT_TOKEN.findall(text), 1))


def localization_errors(keys, languages, strings):
    for key in sorted(keys):
        entry = strings.get(key, {})
        if not entry:
            yield f"missing Fork key: {key!r}"
            continue
        for language in sorted(languages):
            unit = entry.get("localizations", {}).get(language, {})
            plural = unit.get("variations", {}).get("plural")
            values = [item.get("stringUnit", {}).get("value", "") for item in plural.values()] if plural else [
                unit.get("stringUnit", {}).get("value", "")
            ]
            if (plural and "other" not in plural) or not all(value.strip() for value in values):
                yield f"[{language}] missing or empty Fork translation: {key!r}"
            else:
                for value in values:
                    if format_arguments(key) != format_arguments(value):
                        yield f"[{language}] Fork format arguments differ from source: {key!r}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=RESOURCES / "Fork.xcstrings")
    args = parser.parse_args()

    keys, errors = extracted_keys(REPO)
    if not keys:
        errors.append("no Fork table keys extracted")
    languages = shipped_languages(json.loads((RESOURCES / "Localizable.xcstrings").read_text(encoding="utf-8")))
    catalog = json.loads(args.catalog.read_text(encoding="utf-8"))
    if catalog["sourceLanguage"] != "en":
        errors.append("Fork.xcstrings sourceLanguage must be en")
    errors.extend(localization_errors(keys, languages, catalog["strings"]))
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"Fork.xcstrings covers {len(keys)} source keys in {len(languages)} languages.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
