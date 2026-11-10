"""Capture the real score header with fake providers and local assets only.

Run: playwright-local python tool/capture_match_scores.py URL OUTPUT_DIR
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
        for width, height, scale, insets in [
            (360, 640, 1, False),
            (360, 640, 1, True),
            (360, 640, 1.6, True),
            (1440, 1000, 1, False),
        ]:
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
            page.goto(
                f"{url}/?page=match&score=saved&scale={scale}"
                + ("&insets=android" if insets else ""),
                wait_until="networkidle",
            )
            page.wait_for_selector("flutter-view")
            page.wait_for_timeout(2500)
            page.locator("flt-semantics-placeholder").evaluate("node => node.click()")
            for state in ["saved", "editing", "resaved"]:
                if state == "editing":
                    page.get_by_role("button", name="Akcje meczu").click()
                    page.get_by_text("Wprowadź wynik", exact=True).click()
                    fields = page.get_by_role("textbox")
                    assert fields.count() == 2
                    assert fields.nth(0).input_value() == "14"
                    assert fields.nth(1).input_value() == "5"
                    fields.nth(0).fill("15")
                    fields.nth(1).fill("6")
                    # Leave the values from the reported image in the proof frame.
                    fields.nth(0).fill("14")
                    fields.nth(1).fill("5")
                elif state == "resaved":
                    page.get_by_role("button", name="Zapisz", exact=True).click()
                    assert page.get_by_role("textbox").count() == 0
                    page.get_by_text("14", exact=True).wait_for()
                    page.get_by_text("5", exact=True).wait_for()
                page.wait_for_timeout(500)
                path = out / f"match-{state}-{width}x{height}-scale{scale}-insets{int(insets)}.png"
                page.screenshot(path=str(path), full_page=False)
                records.append({
                    "state": state,
                    "viewport": page.viewport_size,
                    "deviceScaleFactor": 1,
                    "textScale": scale,
                    "simulatedSystemInsets": 24 if insets else 0,
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
assert len(records) == 12
