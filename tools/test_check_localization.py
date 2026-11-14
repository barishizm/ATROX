import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import check_localization as c


def catalog(strings):
    d = tempfile.mkdtemp()
    p = Path(d) / "T.xcstrings"
    p.write_text(json.dumps({"sourceLanguage": "en", "strings": strings}))
    return p


def loc(en, tr, tr_state="translated"):
    return {"localizations": {"en": {"stringUnit": {"state": "translated", "value": en}},
                              "tr": {"stringUnit": {"state": tr_state, "value": tr}}}}


class CheckLocalization(unittest.TestCase):
    def test_clean_catalog(self):
        self.assertEqual(c.check(catalog({"a": loc("Hi %d", "Selam %d")})), [])

    def test_missing_language(self):
        p = catalog({"a": {"localizations": {"en": {"stringUnit": {"state": "translated", "value": "x"}}}}})
        self.assertIn("no 'tr'", c.check(p)[0])

    def test_specifier_mismatch(self):
        self.assertIn("specifiers differ", c.check(catalog({"a": loc("Hi %d", "Selam %@")}))[0])

    def test_untranslated_state(self):
        self.assertIn("state", c.check(catalog({"a": loc("x", "y", "needs_review")}))[0])

    def test_literal_percent_and_dropped_positional_argument_are_fine(self):
        self.assertTrue(c.compatible("%1$lld%% a", "%%%1$lld%2$@ b"))
        self.assertFalse(c.compatible("%lld", "%lld %lld"))


if __name__ == "__main__":
    unittest.main()
