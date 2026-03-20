#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_root=$(cd -- "$script_dir/.." && pwd -P)

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[[ -f "$repo_root/contact.html" ]] || fail "contact.html is missing"

python3 - "$repo_root/contact.html" <<'PY'
from html.parser import HTMLParser
from pathlib import Path
import sys

contact_page = Path(sys.argv[1]).read_text()

class ContactParser(HTMLParser):
    VOID_TAGS = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"}

    def __init__(self):
        super().__init__()
        self.stack = []
        self.form_attrs = None
        self.inputs = {}
        self.highlights = 0
        self.routing_items = 0
        self.science_cta = False

    def _classes(self, attrs):
        return set(dict(attrs).get("class", "").split())

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        classes = set(attrs.get("class", "").split())
        if tag not in self.VOID_TAGS:
            self.stack.append((tag, classes))
        if tag == "form" and attrs.get("id") == "contact-form":
            self.form_attrs = attrs
        if tag in {"input", "textarea"} and "name" in attrs:
            self.inputs[attrs["name"]] = attrs
        if tag == "span" and any("contact-form-highlights" in classes for _, classes in self.stack):
            self.highlights += 1
        if tag == "li" and any("contact-routing-list" in classes for _, classes in self.stack):
            self.routing_items += 1
        if tag == "a" and attrs.get("href") == "science.html" and "contact-map-cta" in classes:
            self.science_cta = True

    def handle_endtag(self, tag):
        for index in range(len(self.stack) - 1, -1, -1):
            if self.stack[index][0] == tag:
                del self.stack[index:]
                break

parser = ContactParser()
parser.feed(contact_page)

checks = [
    (parser.form_attrs is not None, "contact form missing"),
    (parser.form_attrs and parser.form_attrs.get("data-netlify") == "true", "contact form is no longer configured for Netlify"),
    ("full-name" in parser.inputs, "full-name field missing"),
    ("email" in parser.inputs, "email field missing"),
    ("message" in parser.inputs, "message field missing"),
    (parser.highlights >= 3, "contact form highlight strip missing or incomplete"),
    (parser.routing_items >= 3, "routing detail list missing or incomplete"),
    (parser.science_cta, "science CTA missing from contact panel"),
]

for ok, message in checks:
    if not ok:
        raise SystemExit(f"FAIL: {message}")

print("PASS: contact page structure checks passed")
PY
