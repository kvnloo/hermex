#!/usr/bin/env python3
"""Verify the vendored gallery files against both the pin and current upstream."""
import re
import subprocess
import sys
from pathlib import Path
from urllib.request import urlopen

REPO = "https://github.com/kvnloo/ephemeral-ui.git"
RAW = "https://raw.githubusercontent.com/kvnloo/ephemeral-ui"
VENDOR = Path(__file__).resolve().parents[1] / "HermesMobile/Resources/EphemeralGallery"
FILES = ("catalog/catalog.json", "catalog/VERSION", "theme/glide.json", "theme/tokens.schema.json")


def verify(vendor, current, fetch):
    pin = (vendor / "REVISION").read_text().strip()
    if not re.fullmatch(r"[a-f0-9]{40}", pin):
        raise ValueError("REVISION must contain a full commit SHA")
    for path in FILES:
        local = (vendor / Path(path).name).read_bytes()
        if local != fetch(pin, path):
            raise ValueError(f"{path} differs from pinned revision {pin}")
        if current != pin and local != fetch(current, path):
            raise ValueError(f"{path} is stale: upstream {current} differs from {pin}; re-vendor and review the snapshot")


def fetch(revision, path):
    with urlopen(f"{RAW}/{revision}/{path}", timeout=15) as response:
        return response.read()


def main():
    try:
        current = subprocess.check_output(
            ["git", "ls-remote", "--exit-code", REPO, "refs/heads/main"], text=True, timeout=30
        ).split()[0]
        verify(VENDOR, current, fetch)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"Ephemeral gallery pin check failed: {error}", file=sys.stderr)
        return 1
    print(f"Ephemeral gallery: {len(FILES)} files match pin and upstream {current}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
