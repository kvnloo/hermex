import tempfile
import unittest
from pathlib import Path

from check_ephemeral_gallery import FILES, verify


class GalleryPinTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.vendor = Path(directory.name)
        self.pin, self.current = "a" * 40, "b" * 40
        (self.vendor / "REVISION").write_text(self.pin)
        for path in FILES:
            (self.vendor / Path(path).name).write_bytes(path.encode())

    def test_unchanged_files_allow_newer_upstream_commit(self):
        verify(self.vendor, self.current, lambda _, path: path.encode())

    def test_upstream_catalog_change_requires_revendoring(self):
        def fetch(revision, path):
            return b"new kind" if revision == self.current and path == FILES[0] else path.encode()

        with self.assertRaisesRegex(ValueError, "catalog/catalog.json is stale"):
            verify(self.vendor, self.current, fetch)

    def test_modified_vendored_file_fails_even_if_pin_is_current(self):
        (self.vendor / "glide.json").write_bytes(b"edited")
        with self.assertRaisesRegex(ValueError, "glide.json differs from pinned revision"):
            verify(self.vendor, self.pin, lambda _, path: path.encode())
