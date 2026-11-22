from pathlib import Path
import tempfile
import unittest

from check_fork_catalog import extracted_keys, localization_errors, shipped_languages


class CheckForkCatalogTests(unittest.TestCase):
    def test_extraction_handles_both_labels_escapes_and_interpolation(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "View.swift").write_text(r'''
Text(
    "A \"name\"",
    tableName: "Fork"
)
Text("\(tools) tools", tableName: "Fork")
String(localized: "Imported \(spec.name)", table: "Fork")
LocalizedStringResource("Live Mode", table: "Fork")
Text("Excluded", tableName: "Localizable")
''')
            self.assertEqual(extracted_keys(root), ({'A "name"', "%lld tools", "Imported %@", "Live Mode"}, []))

    def test_unsupported_call_and_interpolation_fail_closed(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "View.swift").write_text(r'''
Text(variable, tableName: "Fork")
Text("\(unmapped)", tableName: "Fork")
''')
            keys, errors = extracted_keys(root)
            self.assertEqual(keys, set())
            self.assertEqual(len(errors), 2)
            self.assertIn("View.swift:2: expected a direct Swift literal", errors[0])
            self.assertIn("View.swift:3: unknown interpolation", errors[1])

    def test_missing_language_keys_and_placeholders_are_errors(self):
        entries = {"%lld tools": {"localizations": {"en": {"stringUnit": {"value": "%@ tools"}}}}}
        self.assertEqual(list(localization_errors({"%lld tools", "Open"}, {"en", "de"}, entries)), [
            "[de] missing or empty Fork translation: '%lld tools'",
            "[en] Fork format arguments differ from source: '%lld tools'",
            "missing Fork key: 'Open'",
        ])

    def test_shipped_languages_include_source_and_catalog_locales(self):
        catalog = {"sourceLanguage": "en", "strings": {"Open": {"localizations": {"de": {}}}, "Close": {}}}
        self.assertEqual(shipped_languages(catalog), {"en", "de"})
