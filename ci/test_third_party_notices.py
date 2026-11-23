import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NOTICES = ROOT / "HermesMobile" / "Resources" / "ThirdPartyNotices"
PROJECT = ROOT / "HermesMobile.xcodeproj" / "project.pbxproj"
UPSTREAM_LICENSE = NOTICES / "Hermex-LICENSE.txt"


class ThirdPartyNoticesTests(unittest.TestCase):
    def test_upstream_hermex_license_is_the_root_license_verbatim(self):
        self.assertTrue(UPSTREAM_LICENSE.is_file(), f"missing {UPSTREAM_LICENSE.relative_to(ROOT)}")
        self.assertEqual(UPSTREAM_LICENSE.read_bytes(), (ROOT / "LICENSE").read_bytes())
        self.assertIn("Copyright (c) 2026 Uzair Ansar", UPSTREAM_LICENSE.read_text(encoding="utf-8"))

    def test_notice_index_lists_every_license_file(self):
        index = (NOTICES / "NOTICE.txt").read_text(encoding="utf-8")
        for path in sorted(NOTICES.glob("*.txt")):
            if path.name != "NOTICE.txt":
                with self.subTest(path.name):
                    self.assertIn(f"See {path.name}.", index)

    def test_notices_folder_is_copied_into_the_app_bundle(self):
        project = PROJECT.read_text(encoding="utf-8")
        reference = re.search(
            r"(\w+) /\* ThirdPartyNotices \*/ = \{isa = PBXFileReference; lastKnownFileType = folder; path = ThirdPartyNotices;",
            project,
        )
        self.assertIsNotNone(reference, "ThirdPartyNotices must stay a folder reference so every file in it ships")
        build_file = re.search(
            r"(\w+) /\* ThirdPartyNotices in Resources \*/ = \{isa = PBXBuildFile; fileRef = "
            + reference.group(1),
            project,
        )
        self.assertIsNotNone(build_file, "ThirdPartyNotices is not in a Resources build phase")
        self.assertIn(f"{build_file.group(1)} /* ThirdPartyNotices in Resources */,", project)


if __name__ == "__main__":
    unittest.main()
