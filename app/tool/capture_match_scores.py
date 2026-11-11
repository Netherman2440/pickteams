"""Capture the real score header with fake providers and local assets only.

Run: playwright-local python tool/capture_match_scores.py URL OUTPUT_DIR
"""
import json
from pathlib import Path
import re
import sys
from time import monotonic
from urllib.parse import urlparse

from playwright.sync_api import expect, sync_playwright

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
                    page.get_by_role("menuitem", name="Wprowadź wynik", exact=True).click()
                    fields = page.get_by_role("textbox")
                    expect(fields).to_have_count(2)
                    # Flutter populates each semantics input only on focus.
                    fields.nth(0).click()
                    expect(fields.nth(0)).to_have_value("14")
                    fields.nth(1).click()
                    expect(fields.nth(1)).to_have_value("5")
                    # Let Flutter apply each semantics edit before moving focus.
                    # Restore the reported values for the final proof frame.
                    for index, value in [(0, "15"), (1, "6"), (0, "14"), (1, "5")]:
                        field = fields.nth(index)
                        field.click()
                        expect(field).to_be_focused()
                        # Allow the native editing connection to follow focus.
                        page.wait_for_timeout(100)
                        # Send real keys through Flutter's editor, not a DOM fill
                        # of the accessibility proxy that Flutter can overwrite.
                        field.press("ControlOrMeta+A")
                        page.evaluate("""() => new Promise(resolve =>
                            requestAnimationFrame(() => requestAnimationFrame(resolve)))""")
                        field.press("Backspace")
                        page.evaluate("""() => new Promise(resolve =>
                            requestAnimationFrame(() => requestAnimationFrame(resolve)))""")
                        expect(field).to_have_value("")
                        field.press_sequentially(value, delay=25)
                        page.evaluate("""() => new Promise(resolve =>
                            requestAnimationFrame(() => requestAnimationFrame(resolve)))""")
                        expect(field).to_have_value(value)
                elif state == "resaved":
                    page.get_by_role("button", name="Zapisz", exact=True).click()
                    expect(page.get_by_role("textbox")).to_have_count(0)
                    # Read the accessibility tree across Flutter's shadow roots;
                    # adjacent static text can be merged into a single node.
                    deadline = monotonic() + 5
                    while True:
                        semantics = page.locator("flt-semantics-host").aria_snapshot()
                        if re.search(r"\b14\s*:\s*5\b", semantics):
                            break
                        assert monotonic() < deadline, semantics
                        page.wait_for_timeout(50)
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
                    "semantics": page.locator("flt-semantics-host").aria_snapshot(),
                })
            page.close()
    except BaseException:
        if "page" in locals() and not page.is_closed():
            try:
                page.screenshot(path=str(out / "failure.png"))
                (out / "failure.html").write_text(page.content())
                (out / "failure.json").write_text(json.dumps({
                    "state": locals().get("state"),
                    "viewport": page.viewport_size,
                    "semantics": page.locator("flt-semantics-host").aria_snapshot(),
                    "inputs": page.locator("input").evaluate_all(
                        "nodes => nodes.map(node => ({label: node.getAttribute('aria-label'), value: node.value}))"
                    ),
                }, indent=2))
            except Exception:
                pass
        raise
    finally:
        browser.close()
(out / "browser.json").write_text(json.dumps(records, indent=2))
assert all(not record["errors"] for record in records), records
assert all(record["documentWidth"] == record["viewport"]["width"] for record in records), records
assert len(records) == 12
