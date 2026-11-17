"""The CSP in web/vercel.json allows the inline script of /u by hash and same-origin scripts; this fails when the inline script and the hash drift apart or another inline script appears."""
import base64
import hashlib
import json
import re
import unittest
from pathlib import Path

WEB = Path(__file__).resolve().parent.parent / "web"


class WebCspTests(unittest.TestCase):
    def csp(self) -> str:
        config = json.loads((WEB / "vercel.json").read_text())
        for rule in config["headers"]:
            for header in rule["headers"]:
                if header["key"] == "Content-Security-Policy":
                    return header["value"]
        self.fail("no Content-Security-Policy header in web/vercel.json")

    def test_inline_script_hash_matches(self) -> None:
        html = (WEB / "u" / "index.html").read_text()
        script = re.search(r"<script>(.*?)</script>", html, re.S).group(1)
        digest = base64.b64encode(hashlib.sha256(script.encode()).digest()).decode()
        self.assertIn(f"'sha256-{digest}'", self.csp())

    def test_no_other_inline_scripts_or_unsafe_directives(self) -> None:
        for page in WEB.rglob("*.html"):
            scripts = re.findall(r"<script\b(?![^>]*\bsrc=)", page.read_text())
            self.assertEqual(len(scripts), 1 if page.parent.name == "u" else 0, page)
        for page in WEB.rglob("*.html"):
            text = page.read_text()
            self.assertNotRegex(text, r"<style\b|\sstyle=", str(page))
        self.assertNotIn("unsafe-inline", self.csp())
        self.assertIn("frame-ancestors 'none'", self.csp())


if __name__ == "__main__":
    unittest.main()
