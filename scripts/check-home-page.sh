#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_root=$(cd -- "$script_dir/.." && pwd -P)

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

chrome_bin="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

[[ -f "$repo_root/index.html" ]] || fail "index.html is missing"
[[ -x "$chrome_bin" ]] || fail "Google Chrome is required at $chrome_bin"

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/carapex-home-check.XXXXXX")
chrome_log="$tmp_dir/chrome.log"
json_target="$tmp_dir/target.json"

cleanup() {
  if [[ -n "${chrome_pid:-}" ]]; then
    kill "$chrome_pid" >/dev/null 2>&1 || true
    wait "$chrome_pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp_dir"
}

trap cleanup EXIT

"$chrome_bin" \
  --headless=new \
  --disable-gpu \
  --no-first-run \
  --no-default-browser-check \
  --allow-file-access-from-files \
  --user-data-dir="$tmp_dir/profile" \
  --remote-debugging-port=0 \
  about:blank >"$chrome_log" 2>&1 &
chrome_pid=$!

for _ in $(seq 1 100)
do
  if grep -q "DevTools listening on ws://127.0.0.1:" "$chrome_log"; then
    break
  fi
  sleep 0.1
done

debug_url=$(python3 - "$chrome_log" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text()
match = re.search(r"DevTools listening on (ws://127\.0\.0\.1:(\d+)/\S+)", text)
if not match:
    raise SystemExit(1)
print(match.group(1))
PY
) || fail "headless Chrome did not expose a DevTools endpoint"

debug_port=$(python3 - "$debug_url" <<'PY'
import sys
from urllib.parse import urlparse

print(urlparse(sys.argv[1]).port or "")
PY
)

target_url="file://$repo_root/index.html"
curl -sS -X PUT "http://127.0.0.1:$debug_port/json/new?$target_url" >"$json_target"

page_ws_url=$(python3 - "$json_target" <<'PY'
from pathlib import Path
import json
import sys

payload = json.loads(Path(sys.argv[1]).read_text())
print(payload["webSocketDebuggerUrl"])
PY
) || fail "could not create a headless page target"

PAGE_WS_URL="$page_ws_url" node <<'EOF'
const wsUrl = process.env.PAGE_WS_URL;

if (!wsUrl) {
  console.error("FAIL: missing page websocket URL");
  process.exit(1);
}

const ws = new WebSocket(wsUrl);
let nextId = 0;
const pending = new Map();

function send(method, params = {}) {
  const id = ++nextId;
  ws.send(JSON.stringify({ id, method, params }));
  return new Promise((resolve, reject) => {
    pending.set(id, { resolve, reject });
    setTimeout(() => {
      if (pending.has(id)) {
        pending.delete(id);
        reject(new Error(`Timed out waiting for ${method}`));
      }
    }, 5000);
  });
}

function closeWithError(message) {
  console.error(`FAIL: ${message}`);
  try {
    ws.close();
  } finally {
    process.exit(1);
  }
}

ws.addEventListener("message", (event) => {
  const payload = JSON.parse(event.data.toString());
  if (!payload.id) return;

  const entry = pending.get(payload.id);
  if (!entry) return;
  pending.delete(payload.id);

  if (payload.error) {
    entry.reject(new Error(payload.error.message || "CDP error"));
    return;
  }

  entry.resolve(payload.result);
});

ws.addEventListener("error", () => {
  closeWithError("could not connect to the Chrome DevTools target");
});

ws.addEventListener("open", async () => {
  try {
    await send("Page.enable");
    await send("Runtime.enable");
    async function measureViewport(width, height) {
      await send("Emulation.setDeviceMetricsOverride", {
        width,
        height,
        deviceScaleFactor: 1,
        mobile: false
      });
      await send("Page.reload");

      const { result } = await send("Runtime.evaluate", {
        expression: `
          (async () => {
            const wait = (ms) => new Promise((resolve) => window.setTimeout(resolve, ms));

            if (document.readyState === "loading") {
              await new Promise((resolve) => document.addEventListener("DOMContentLoaded", resolve, { once: true }));
            }

            await wait(250);

            const dots = Array.from(document.querySelectorAll(".hero-dot"));
            const slides = Array.from(document.querySelectorAll(".hero-slide"));
            const secondDot = dots[1];

            secondDot?.click();
            await wait(250);

            const active = document.querySelector(".hero-slide.active");
            const paragraph = active?.querySelector("p:last-of-type") || active?.querySelector("p");
            const dotRect = secondDot?.getBoundingClientRect();
            const activeRect = active?.getBoundingClientRect();
            const paragraphRect = paragraph?.getBoundingClientRect();
            const heroMainRect = document.querySelector(".hero-main")?.getBoundingClientRect();
            const bottomPanelRect = document.querySelector(".hero-bottom-panel")?.getBoundingClientRect();

            return {
              viewport: { width: ${width}, height: ${height} },
              slideCount: slides.length,
              dotCount: dots.length,
              activeIndex: active?.dataset.index ?? null,
              clickWorked: active?.dataset.index === "1",
              dotWidth: dotRect?.width ?? 0,
              dotHeight: dotRect?.height ?? 0,
              targetSizeOk: (dotRect?.width ?? 0) >= 24 && (dotRect?.height ?? 0) >= 24,
              activeClientHeight: active?.clientHeight ?? 0,
              activeScrollHeight: active?.scrollHeight ?? 0,
              contentFits: active ? active.scrollHeight <= active.clientHeight + 1 : false,
              paragraphBottomWithinSlide: activeRect && paragraphRect
                ? paragraphRect.bottom <= activeRect.bottom + 1
                : false,
              heroMainBottom: heroMainRect?.bottom ?? 0,
              bottomPanelTop: bottomPanelRect?.top ?? 0,
              heroGapOk: heroMainRect && bottomPanelRect
                ? heroMainRect.bottom <= bottomPanelRect.top - 8
                : false
            };
          })()
        `,
        awaitPromise: true,
        returnByValue: true
      });

      return result?.value;
    }

    async function measureMobileMenu(width, height) {
      await send("Emulation.setDeviceMetricsOverride", {
        width,
        height,
        deviceScaleFactor: 1,
        mobile: true
      });
      await send("Page.reload");

      const { result } = await send("Runtime.evaluate", {
        expression: `
          (async () => {
            const wait = (ms) => new Promise((resolve) => window.setTimeout(resolve, ms));

            if (document.readyState === "loading") {
              await new Promise((resolve) => document.addEventListener("DOMContentLoaded", resolve, { once: true }));
            }

            await wait(250);

            const button = document.querySelector(".menu-toggle");
            const bars = Array.from(document.querySelectorAll(".menu-toggle span"));
            const buttonRect = button?.getBoundingClientRect();
            const deltas = bars.map((bar) => {
              const rect = bar.getBoundingClientRect();
              return ((rect.left + rect.right) / 2) - ((buttonRect.left + buttonRect.right) / 2);
            });

            return {
              viewport: { width: ${width}, height: ${height} },
              buttonVisible: !!button && button.offsetParent !== null,
              barCount: bars.length,
              maxCenterOffset: deltas.length ? Math.max(...deltas.map((delta) => Math.abs(delta))) : Infinity
            };
          })()
        `,
        awaitPromise: true,
        returnByValue: true
      });

      return result?.value;
    }

    const desktopSummary = await measureViewport(1600, 900);
    const compactSummary = await measureViewport(1366, 768);
    const shortDesktopSummary = await measureViewport(1440, 700);
    const mobileMenuSummary = await measureMobileMenu(375, 812);

    if (!desktopSummary || !compactSummary || !shortDesktopSummary || !mobileMenuSummary) {
      closeWithError("homepage metrics could not be collected");
      return;
    }

    const failures = [];

    if (desktopSummary.slideCount !== 3) failures.push(`expected 3 hero slides, found ${desktopSummary.slideCount}`);
    if (desktopSummary.dotCount !== 3) failures.push(`expected 3 hero dots, found ${desktopSummary.dotCount}`);
    if (!desktopSummary.clickWorked) failures.push("clicking the second hero dot did not activate the second slide");
    if (!desktopSummary.targetSizeOk) {
      failures.push(`hero dot hit area is too small (${desktopSummary.dotWidth}x${desktopSummary.dotHeight}px)`);
    }
    if (!desktopSummary.contentFits || !desktopSummary.paragraphBottomWithinSlide) {
      failures.push(
        `hero slide content is clipped (clientHeight=${desktopSummary.activeClientHeight}, scrollHeight=${desktopSummary.activeScrollHeight})`
      );
    }
    if (!compactSummary.heroGapOk) {
      failures.push(
        `hero copy overlaps the bottom panel at ${compactSummary.viewport.width}x${compactSummary.viewport.height} (heroMainBottom=${compactSummary.heroMainBottom}, bottomPanelTop=${compactSummary.bottomPanelTop})`
      );
    }
    if (!shortDesktopSummary.heroGapOk) {
      failures.push(
        `hero copy overlaps the bottom panel at ${shortDesktopSummary.viewport.width}x${shortDesktopSummary.viewport.height} (heroMainBottom=${shortDesktopSummary.heroMainBottom}, bottomPanelTop=${shortDesktopSummary.bottomPanelTop})`
      );
    }
    if (!mobileMenuSummary.buttonVisible) {
      failures.push(`mobile menu toggle is not visible at ${mobileMenuSummary.viewport.width}x${mobileMenuSummary.viewport.height}`);
    }
    if (mobileMenuSummary.barCount !== 2) {
      failures.push(`expected 2 hamburger bars, found ${mobileMenuSummary.barCount}`);
    }
    if (mobileMenuSummary.maxCenterOffset > 1) {
      failures.push(
        `mobile menu bars are off-center by ${mobileMenuSummary.maxCenterOffset}px at ${mobileMenuSummary.viewport.width}x${mobileMenuSummary.viewport.height}`
      );
    }

    if (failures.length) {
      closeWithError(failures.join("; "));
      return;
    }

    console.log("PASS: homepage hero checks passed");
    ws.close();
  } catch (error) {
    closeWithError(error.message);
  }
});
EOF
