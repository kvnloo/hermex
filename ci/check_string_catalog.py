#!/usr/bin/env python3
"""Fail when a compiler-extracted UI string is missing from its catalog.

The app, Live Activity widget, and Notification Service Extension build with
SWIFT_EMIT_LOC_STRINGS=YES, so every Swift compile already writes a `.stringsdata`
file listing the localizable keys that source file uses. This reads those files
from an existing build (no extra build) and checks each `Localizable` key against
HermesMobile/Resources/Localizable.xcstrings and each app and widget Fork key
against Fork.xcstrings. Only presence is checked: stale
catalog keys and `shouldTranslate: false` entries never fail it, and empty
translations are LocalizationCatalogTests' job.

PR CI runs it after the build; locally:

    python3 ci/check_string_catalog.py --derived-data <DerivedData path>
"""

import argparse
import json
import os
from pathlib import Path
import sys

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "HermesMobile" / "Resources" / "Localizable.xcstrings"
FORK_CATALOG = CATALOG.with_name("Fork.xcstrings")
# Targets that bundle Localizable.xcstrings. The share extension bundles no catalog
# and uses English literals (docs/agents/i18n.md), so its keys are not checked.
TARGETS = ("HermesMobile", "HermesLiveActivityWidget", "HermesNotificationService")
FORK_TARGETS = ("HermesMobile", "HermesLiveActivityWidget")


def extracted_keys(derived_data, configuration):
    """Map table names to keys, and keys to {(source path, line): {targets}}."""
    build = Path(derived_data) / "Build" / "Intermediates.noindex" / "HermesMobile.build" / configuration
    tables = {"Localizable": {}, "Fork": {}}
    for target in TARGETS:
        # One file per source per architecture; the set collapses the duplicates.
        files = sorted(build.glob(f"{target}.build/Objects-normal/*/*.stringsdata"))
        if not files:
            sys.exit(
                f"error: no .stringsdata files for {target} under {build}.\n"
                "Build the HermesMobile scheme into this DerivedData first, or pass the matching "
                "--configuration (for example Release-iphonesimulator)."
            )
        for path in files:
            data = json.loads(path.read_text())
            source = Path(data.get("source", ""))
            # A source deleted since that build leaves its stale .stringsdata behind locally.
            if source.is_absolute() and not source.exists():
                continue
            for table, keys in tables.items():
                if table == "Fork" and target not in FORK_TARGETS:
                    continue
                for entry in data.get("tables", {}).get(table, []):
                    key = entry.get("key")
                    if key:
                        line = entry.get("location", {}).get("startingLine", 0)
                        keys.setdefault(key, {}).setdefault((display_path(source), line), set()).add(target)
    return tables


def display_path(source):
    try:
        return source.relative_to(REPO).as_posix()
    except ValueError:
        return source.as_posix()


def check_table(keys, catalog, targets):
    known = json.loads(catalog.read_text(encoding="utf-8"))["strings"]
    missing = sorted(key for key in keys if key not in known)
    if not missing:
        print(f"{catalog.name} covers all {len(keys)} extracted keys from {', '.join(targets)}.")
        return 0

    annotate = os.environ.get("GITHUB_ACTIONS") == "true"
    print(f"{len(missing)} UI string(s) are missing from HermesMobile/Resources/{catalog.name}:\n")
    for key in missing:
        quoted = json.dumps(key, ensure_ascii=False)
        print(f"  {quoted}")
        for (source, line), targets in sorted(keys[key].items()):
            print(f"    {source}:{line}  [{', '.join(sorted(targets))}]")
            if annotate:
                # Workflow commands treat % as an escape; keys like "%@ of %@" need %25.
                message = f"Missing from {catalog.name}: {quoted}".replace("%", "%25")
                print(f"::error file={source},line={line}::{message}")
    print(
        "\nEach key would ship English-only. Fix one of two ways:\n"
        f"  - UI copy: add the key to {catalog.name} with a translation for every shipped\n"
        "    language (\"state\" : \"needs_review\"); follow docs/agents/i18n.md > Editing the catalog.\n"
        "  - Debug-only copy (#if DEBUG): stop extraction with Text(verbatim:) or a plain String.\n"
        "Placeholder- or symbol-only keys belong in the catalog with \"shouldTranslate\" : false."
    )
    return 1


def main():
    parser = argparse.ArgumentParser(
        description="Fail when an extracted UI string is missing from Localizable.xcstrings or Fork.xcstrings.",
        epilog="example: python3 ci/check_string_catalog.py --derived-data DerivedData",
    )
    parser.add_argument("--derived-data", required=True, help="DerivedData path of a finished HermesMobile build")
    parser.add_argument("--configuration", default="Debug-iphonesimulator", help="build products directory name (default: %(default)s)")
    parser.add_argument("--catalog", type=Path, default=CATALOG, help="catalog to check against (default: the repo's Localizable.xcstrings)")
    parser.add_argument("--fork-catalog", type=Path, default=FORK_CATALOG, help="Fork catalog to check against")
    args = parser.parse_args()

    tables = extracted_keys(args.derived_data, args.configuration)
    localizable_status = check_table(tables["Localizable"], args.catalog, TARGETS)
    fork_status = check_table(tables["Fork"], args.fork_catalog, FORK_TARGETS)
    return localizable_status or fork_status


if __name__ == "__main__":
    sys.exit(main())
