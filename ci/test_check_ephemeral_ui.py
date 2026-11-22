import contextlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import check_ephemeral_ui as check


def theme(version="0.1.0", v=0):
    return {"v": v, "id": "glide", "name": "Glide", "version": version}


def catalog(*names, version="0.1.0", v=0):
    entries = [{"kind": name, "fixtures": [{"id": f"{name}/a", "state": "sample", "props": {}}]} for name in names]
    return {"v": v, "version": version, "count": {"kinds": len(entries), "fixtures": len(entries)}, "kinds": entries}


class EphemeralUIPinTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root)
        self.source = self.root / "ephemeral-ui"
        self.vendor = self.root / "vendor"
        (self.source / "theme").mkdir(parents=True)
        (self.source / "catalog").mkdir()
        self.publish(theme(), catalog("sculpt", "merge"))
        self.vendor.mkdir()
        (self.vendor / "coverage.json").write_text(json.dumps({"kinds": {"sculpt": "props", "merge": "props"}}))
        self.assertEqual(self.run_check("--vendor", str(self.source)), 0)

    def publish(self, theme_doc, catalog_doc):
        (self.source / "theme" / "glide.json").write_text(json.dumps(theme_doc))
        (self.source / "catalog" / "catalog.json").write_text(json.dumps(catalog_doc))
        git = ["git", "-C", str(self.source), "-c", "user.name=t", "-c", "user.email=t@t"]
        if not (self.source / ".git").exists():
            subprocess.run(git[:3] + ["init", "-q"], check=True)
        subprocess.run(git + ["add", "-A"], check=True)
        subprocess.run(git + ["commit", "-qm", "publish", "--allow-empty"], check=True)

    def run_check(self, *args):
        self.stderr = io.StringIO()
        with contextlib.redirect_stderr(self.stderr), contextlib.redirect_stdout(io.StringIO()):
            return check.main(["--vendor-dir", str(self.vendor), *args])

    def test_a_fresh_vendored_copy_passes_offline_and_against_its_source(self):
        self.assertEqual(self.run_check(), 0)
        self.assertEqual(self.run_check("--source", str(self.source)), 0)

    def test_an_edited_copy_fails(self):
        (self.vendor / "glide.json").write_text(json.dumps(theme() | {"name": "Edited"}))
        self.assertEqual(self.run_check(), 1)
        self.assertIn("glide.json differs from PIN.json", self.stderr.getvalue())

    def test_a_stale_pin_fails_and_names_the_new_kind(self):
        self.publish(theme("0.2.0"), catalog("sculpt", "merge", "orbit", version="0.2.0"))
        self.assertEqual(self.run_check("--source", str(self.source)), 1)
        self.assertIn("stale: vendored glide.json 0.1.0", self.stderr.getvalue())
        self.assertIn("uncovered kind: 'orbit'", self.stderr.getvalue())

    def test_re_vendoring_a_new_kind_fails_until_coverage_names_it(self):
        self.publish(theme(), catalog("sculpt", "merge", "orbit", version="0.2.0"))
        self.assertEqual(self.run_check("--vendor", str(self.source)), 1)
        self.assertIn("uncovered kind: 'orbit'", self.stderr.getvalue())
        (self.vendor / "coverage.json").write_text(
            json.dumps({"kinds": {"sculpt": "props", "merge": "props", "orbit": "native"}}))
        self.assertEqual(self.run_check("--source", str(self.source)), 0)

    def test_a_file_shape_this_app_cannot_read_fails(self):
        self.publish(theme(v=1), catalog("sculpt", "merge"))
        self.assertEqual(self.run_check("--vendor", str(self.source)), 1)
        self.assertIn("glide.json has v 1", self.stderr.getvalue())

    def test_the_upstream_ref_is_read_from_the_raw_url(self):
        published = check.read_source(self.source)
        refs = []

        def fetch(ref):
            refs.append(ref)
            return published

        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(check.main(["--vendor-dir", str(self.vendor), "--upstream", "main"], fetch=fetch), 0)
        self.assertEqual(refs, ["main"])

    def test_the_repo_copy_is_intact(self):
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(check.main([]), 0)


if __name__ == "__main__":
    unittest.main()
