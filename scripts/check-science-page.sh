#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_root=$(cd -- "$script_dir/.." && pwd -P)

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

pdf_paths=(
  papers/increasing-efficiency-chitin-nanofibers-barrier-film.pdf
  papers/chitin-nanofibril-nanocomposites-water-resistance.pdf
  papers/naturally-drug-loaded-chitin.pdf
  papers/chitosan-succinate-enteric-coated-tablet.pdf
  papers/chitosan-succinate-chitosan-phthalate-diclofenac.pdf
)

[[ -f "$repo_root/science.html" ]] || fail "science.html is missing"

for pdf in "${pdf_paths[@]}"
do
  [[ -f "$repo_root/$pdf" ]] || fail "missing PDF asset: $pdf"
done

python3 - "$repo_root" "${pdf_paths[@]}" <<'PY'
from html.parser import HTMLParser
from pathlib import Path
import sys

repo_root = Path(sys.argv[1])
pdf_paths = sys.argv[2:]

index = (repo_root / "index.html").read_text()
science = (repo_root / "science.html").read_text()

required_ids = {
    "science-overview",
    "why-chitin",
    "comparison",
    "research-pillars",
    "research-library",
    "validation-status",
    "references",
}

class ScienceParser(HTMLParser):
    VOID_TAGS = {
        "area",
        "base",
        "br",
        "col",
        "embed",
        "hr",
        "img",
        "input",
        "link",
        "meta",
        "param",
        "source",
        "track",
        "wbr",
    }

    def __init__(self):
        super().__init__()
        self.ids = set()
        self.classes = set()
        self.embeds = []
        self.anchors = []
        self.title_text = ""
        self.in_title = False
        self.text_chunks = []
        self._stack = []
        self._current_anchor = None

    @staticmethod
    def _normalize_text(value):
        return " ".join(value.split())

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag not in self.VOID_TAGS:
            self._stack.append(tag)
        if "id" in attrs:
            self.ids.add(attrs["id"])
        if "class" in attrs:
            self.classes.update(attrs["class"].split())
        if tag in {"iframe", "embed"} and "src" in attrs:
            self.embeds.append(attrs["src"])
        if tag == "object" and "data" in attrs:
            self.embeds.append(attrs["data"])
        if tag == "title":
            self.in_title = True
        if tag == "a":
            self._current_anchor = {
                "href": attrs.get("href", ""),
                "text": [],
                "context": tuple(self._stack[:-1]),
            }

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if tag not in self.VOID_TAGS:
            self.handle_endtag(tag)

    def handle_endtag(self, tag):
        if tag == "title":
            self.in_title = False
        if tag == "a" and self._current_anchor is not None:
            self.anchors.append(
                {
                    "href": self._current_anchor["href"],
                    "text": self._normalize_text("".join(self._current_anchor["text"])),
                    "context": self._current_anchor["context"],
                }
            )
            self._current_anchor = None
        if self._stack and self._stack[-1] == tag:
            self._stack.pop()

    def handle_data(self, data):
        if self.in_title:
            self.title_text += data
        if self._current_anchor is not None:
            self._current_anchor["text"].append(data)
        self.text_chunks.append(data)

science_parser = ScienceParser()
science_parser.feed(science)
index_parser = ScienceParser()
index_parser.feed(index)

page_text = " ".join(chunk.strip() for chunk in science_parser.text_chunks if chunk.strip())

def has_link(parser, *, href=None, text=None, context=()):
    for anchor in parser.anchors:
        if href is not None and anchor["href"] != href:
            continue
        if text is not None and anchor["text"] != text:
            continue
        if context and not all(tag in anchor["context"] for tag in context):
            continue
        return True
    return False

checks = [
    ("The Science Behind InfinityCoat(TM)" in science_parser.title_text, "science page title missing or incorrect"),
    ("The Science Behind InfinityCoat" in page_text, "science page hero heading missing"),
    (required_ids.issubset(science_parser.ids), f"science page missing required section IDs: {sorted(required_ids - science_parser.ids)}"),
    ("science-mechanism" in science_parser.classes, "mechanism graphic block missing"),
    (has_link(index_parser, href="science.html", text="Science", context=("nav",)), "homepage nav missing science link"),
    (has_link(index_parser, href="science.html", text="Science", context=("footer",)), "homepage footer missing science link"),
    (has_link(science_parser, href="science.html", text="Science", context=("nav",)), "science page missing current-page science nav link"),
    (has_link(science_parser, href="index.html#landing", context=("header",)), "science page brand link does not return home"),
]

for pdf in pdf_paths:
    checks.append((pdf in science_parser.embeds, f"science page missing inline embed for {pdf}"))
    checks.append((has_link(science_parser, href=pdf, context=("main",)), f"science page missing Open PDF link for {pdf}"))

for ok, message in checks:
    if not ok:
        raise SystemExit(f"FAIL: {message}")
PY

printf 'PASS: science page smoke checks passed\n'
