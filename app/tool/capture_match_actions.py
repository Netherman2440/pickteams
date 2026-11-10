"""Capture the real match page without changing viewport or shell content.

Run: playwright-local python tool/capture_match_actions.py URL OUTPUT_DIR
"""
import json
from pathlib import Path
import sys
from urllib.parse import urlparse

from playwright.sync_api import sync_playwright

url, output = sys.argv[1:]
out = Path(output)
out.mkdir(parents=True, exist_ok=True)
records = []
with sync_playwright() as p:
    browser = p.chromium.launch()
    try:
        for width, height in [(360, 640), (1440, 1000)]:
            page = browser.new_page(
                viewport={"width": width, "height": height}, device_scale_factor=1
            )
            errors, blocked = [], []
            page.on("pageerror", lambda error: errors.append(str(error)))

            def local_only(route):
                if urlparse(route.request.url).netloc == urlparse(url).netloc:
                    route.continue_()
                else:
                    blocked.append(route.request.url)
                    route.abort()

            page.route("**/*", local_only)
            page.goto(f"{url}/?page=match", wait_until="networkidle")
            page.wait_for_selector("flutter-view")
            page.wait_for_timeout(2500)
            # Enable Flutter's accessibility tree, not a replacement UI.
            page.locator("flt-semantics-placeholder").evaluate("node => node.click()")
            for state in (["closed", "open"] if width == 360 else ["desktop"]):
                if state == "open":
                    page.get_by_role("button", name="Akcje meczu").click()
                    page.wait_for_timeout(500)
                path = out / f"match-{state}-{width}x{height}.png"
                page.screenshot(path=str(path), full_page=False)
                records.append({
                    "state": state,
                    "viewport": page.viewport_size,
                    "deviceScaleFactor": 1,
                    "textScale": 1,
                    "image": str(path),
                    "errors": list(errors),
                    "blockedExternalRequests": list(blocked),
                    "documentWidth": page.evaluate("document.documentElement.scrollWidth"),
                    "semantics": page.locator("flt-semantics-host").inner_text(),
                })
            page.close()
    finally:
        browser.close()
(out / "browser.json").write_text(json.dumps(records, indent=2))
assert all(not record["errors"] for record in records), records
assert all(record["documentWidth"] == record["viewport"]["width"] for record in records), records
