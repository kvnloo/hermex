#!/usr/bin/env python3
"""Check the vendored ephemeral-ui theme and card catalog against their pin.

Offline (default): the vendored files match PIN.json byte for byte, both carry
file shape v 0 and the pinned version, and coverage.json names every catalog
kind exactly once, so a re-vendored catalog with a new kind fails until the
kind is covered.

--upstream REF (or --source DIR): also fail when the pinned copy is stale,
naming the new version and any kind the pinned catalog does not cover yet.

--vendor DIR: copy theme/glide.json and catalog/catalog.json from an
ephemeral-ui checkout and rewrite PIN.json with its commit. coverage.json is
never rewritten; run the check afterwards to see which kinds need a decision.
"""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import urllib.error
import urllib.request

REPO = Path(__file__).resolve().parents[1]
VENDOR = REPO / "HermesMobile" / "Fork" / "Vendor" / "EphemeralUI"
UPSTREAM = "kvnloo/ephemeral-ui"
FILES = {"glide.json": "theme/glide.json", "catalog.json": "catalog/catalog.json"}
SUPPORT = {"native", "props"}
FILE_SHAPE = 0


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def kinds(catalog):
    return [entry["kind"] for entry in catalog.get("kinds", [])]


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def vendored_errors(vendor):
    errors = []
    pin_path = vendor / "PIN.json"
    if not pin_path.exists():
        return [f"missing {pin_path.name}; vendor with --vendor <ephemeral-ui checkout>"]
    pin = read_json(pin_path)
    documents = {}
    for name in FILES:
        path = vendor / name
        if not path.exists():
            errors.append(f"missing vendored {name}")
            continue
        data = path.read_bytes()
        entry = pin.get("files", {}).get(name, {})
        if sha256(data) != entry.get("sha256"):
            errors.append(f"{name} differs from PIN.json; re-vendor it, never edit the copy")
        document = json.loads(data)
        documents[name] = document
        if document.get("v") != FILE_SHAPE:
            errors.append(f"{name} has v {document.get('v')!r}; this app reads v {FILE_SHAPE}")
        if document.get("version") != entry.get("version"):
            errors.append(f"{name} is version {document.get('version')!r} but PIN.json says {entry.get('version')!r}")

    catalog = documents.get("catalog.json")
    if catalog is not None:
        listed = kinds(catalog)
        fixtures = sum(len(entry.get("fixtures", [])) for entry in catalog.get("kinds", []))
        count = catalog.get("count", {})
        if count.get("kinds") != len(listed) or count.get("fixtures") != fixtures:
            errors.append(f"catalog.json count {count} does not match {len(listed)} kinds, {fixtures} fixtures")
        errors.extend(coverage_errors(vendor, listed))
    return errors


def coverage_errors(vendor, listed):
    path = vendor / "coverage.json"
    if not path.exists():
        return ["missing coverage.json"]
    coverage = read_json(path).get("kinds", {})
    errors = [f"uncovered kind: {kind!r}; add it to coverage.json" for kind in listed if kind not in coverage]
    errors += [f"coverage.json names {kind!r}, which the catalog does not list"
               for kind in sorted(set(coverage) - set(listed))]
    errors += [f"coverage.json {kind!r} is {value!r}; use one of {sorted(SUPPORT)}"
               for kind, value in sorted(coverage.items()) if value not in SUPPORT]
    return errors


def fetch_upstream(ref, repo=UPSTREAM):
    out = {}
    for name, path in FILES.items():
        url = f"https://raw.githubusercontent.com/{repo}/{ref}/{path}"
        with urllib.request.urlopen(url, timeout=30) as response:
            out[name] = response.read()
    return out


def read_source(source):
    return {name: (source / path).read_bytes() for name, path in FILES.items()}


def stale_errors(vendor, upstream, label):
    errors = []
    pin = read_json(vendor / "PIN.json")
    for name, data in upstream.items():
        entry = pin.get("files", {}).get(name, {})
        if sha256(data) == entry.get("sha256"):
            continue
        errors.append(f"stale: vendored {name} {entry.get('version')} @ {pin.get('commit', '?')[:7]} differs from "
                      f"{label} ({json.loads(data).get('version')}); re-vendor with --vendor")
    if "catalog.json" in upstream:
        pinned = set(kinds(read_json(vendor / "catalog.json")))
        errors += [f"uncovered kind: {kind!r} is in {label} but not in the pinned catalog"
                   for kind in kinds(json.loads(upstream["catalog.json"])) if kind not in pinned]
    return errors


def vendor_from(source, vendor):
    commit = subprocess.run(["git", "-C", str(source), "rev-parse", "HEAD"], check=True,
                            capture_output=True, text=True).stdout.strip()
    vendor.mkdir(parents=True, exist_ok=True)
    files = {}
    for name, data in read_source(source).items():
        (vendor / name).write_bytes(data)
        files[name] = {"path": FILES[name], "version": json.loads(data).get("version"), "sha256": sha256(data)}
    pin = {"repo": UPSTREAM, "commit": commit, "files": files}
    (vendor / "PIN.json").write_text(json.dumps(pin, indent=2) + "\n", encoding="utf-8")
    return commit


def main(argv=None, fetch=fetch_upstream):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--vendor-dir", type=Path, default=VENDOR)
    parser.add_argument("--upstream", metavar="REF", help="compare against this ref of kvnloo/ephemeral-ui")
    parser.add_argument("--source", type=Path, help="compare against an ephemeral-ui checkout")
    parser.add_argument("--vendor", type=Path, metavar="DIR", help="re-vendor from an ephemeral-ui checkout")
    args = parser.parse_args(argv)

    if args.vendor:
        commit = vendor_from(args.vendor, args.vendor_dir)
        print(f"Vendored ephemeral-ui {commit[:7]} into {args.vendor_dir.name}.")

    errors = vendored_errors(args.vendor_dir)
    if not errors and (args.upstream or args.source):
        try:
            upstream = read_source(args.source) if args.source else fetch(args.upstream)
        except (OSError, urllib.error.URLError) as error:
            print(f"could not read upstream ephemeral-ui: {error}", file=sys.stderr)
            return 2
        label = str(args.source) if args.source else f"{UPSTREAM}@{args.upstream}"
        errors = stale_errors(args.vendor_dir, upstream, label)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    pin = read_json(args.vendor_dir / "PIN.json")
    catalog = read_json(args.vendor_dir / "catalog.json")
    versions = ", ".join(f"{name} {entry['version']}" for name, entry in sorted(pin["files"].items()))
    scope = " and matches upstream" if args.upstream or args.source else ""
    print(f"ephemeral-ui {pin['commit'][:7]} ({versions}) is intact{scope}; {len(kinds(catalog))} kinds covered.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
