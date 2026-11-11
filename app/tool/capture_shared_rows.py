"""Capture unchanged Flutter RootShell pages from a loopback fixture build.

Run under the shared validation lock:
  playwright-local python tool/capture_shared_rows.py URL OUTPUT_DIR
PNG inspection is required: DOM width and semantics do not prove painted text.
"""
import hashlib
import json
from pathlib import Path
import re
import sys
from urllib.parse import urlparse

from playwright.sync_api import sync_playwright


def capture(url, output):
    origin = urlparse(url)
    if origin.hostname not in ("127.0.0.1", "localhost", "::1"):
        raise ValueError("Only loopback fixture URLs are allowed")
    out = Path(output)
    out.mkdir(parents=True, exist_ok=True)
    records = []
    executable = Path.home() / ".cache/ms-playwright/chromium_headless_shell-1248/chrome-headless-shell-linux64/chrome-headless-shell"
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(
            executable_path=str(executable), args=["--disable-dev-shm-usage"]
        )
        try:
            for width, height in [(360, 640), (1440, 1000)]:
                for scale in [1.0, 1.6]:
                    for screen in ["selection", "players", "match", "results"]:
                        record = {
                            "screen": screen, "viewport": [width, height],
                            "textScale": scale, "console": [], "pageErrors": [],
                            "blockedRequests": [], "stubbedFontStylesheets": [],
                            "frames": [], "checks": [],
                        }
                        records.append(record)
                        page = browser.new_page(
                            viewport={"width": width, "height": height},
                            device_scale_factor=1,
                        )
                        page.on("console", lambda msg: record["console"].append(
                            {"type": msg.type, "text": msg.text}))
                        page.on("pageerror", lambda error: record["pageErrors"].append(str(error)))

                        def local_only(route):
                            request = urlparse(route.request.url)
                            if request.netloc == origin.netloc:
                                route.continue_()
                            elif (request.scheme == "https"
                                  and request.netloc == "fonts.googleapis.com"
                                  and request.path == "/css2"
                                  and route.request.resource_type == "stylesheet"):
                                # Legacy index.html CSS is unused by CanvasKit;
                                # Flutter loads its bundled fonts independently.
                                record["stubbedFontStylesheets"].append(route.request.url)
                                route.fulfill(status=200, content_type="text/css", body="")
                            else:
                                record["blockedRequests"].append(route.request.url)
                                route.abort()

                        page.route("**/*", local_only)
                        prefix = f"{screen}-{width}-{scale}"

                        def frame(state):
                            page.wait_for_timeout(500)
                            path = out / f"{prefix}-{state}.png"
                            image = page.screenshot(path=str(path))
                            record["frames"].append({
                                "state": state, "file": path.name,
                                "sha256": hashlib.sha256(image).hexdigest(),
                                "semantics": page.locator("flt-semantics-host").inner_text(),
                            })
                            assert page.evaluate("document.documentElement.scrollWidth") == width

                        def scroll_bottom():
                            page.mouse.move(width * .65, height * .8)
                            # Wheel gestures go through Flutter's real scroll handling.
                            for _ in range(14 if screen in ("selection", "players") else 4):
                                page.mouse.wheel(0, 900)
                                page.wait_for_timeout(80)
                            page.wait_for_timeout(400)

                        try:
                            page.goto(f"{url}/?page={screen}&scale={scale}", wait_until="networkidle")
                            page.wait_for_selector("flutter-view")
                            # Its absolutely positioned children leave the host with
                            # zero bounds. Attachment, not host visibility, is required.
                            page.wait_for_selector("flt-semantics-host", state="attached")
                            page.wait_for_timeout(1800)
                            frame("top")
                            if screen == "selection":
                                search = page.get_by_role("textbox")
                                search_box = search.bounding_box()
                                assert search_box is not None
                                scroll_bottom()
                                frame("bottom")
                                assert "Gracz 100" in record["frames"][-1]["semantics"]
                                assert search.bounding_box() == search_box
                                assert record["frames"][0]["sha256"] != record["frames"][-1]["sha256"]
                                record["checks"].append("one list reaches player 100; search stays fixed")
                                search.fill("Anna")
                                page.wait_for_timeout(500)
                                frame("search-selected")
                                content = record["frames"][-1]["semantics"]
                                assert "Wybrani gracze (2)" in content
                                assert "Brak dostępnych graczy" in content
                                search.fill("Gracz 100")
                                page.wait_for_timeout(500)
                                frame("search-available")
                                content = record["frames"][-1]["semantics"]
                                assert "Wybrani gracze (2)" in content
                                assert "Brak wybranych graczy" in content
                                record["checks"].append("query filters each group and retains selected count")
                            elif screen == "players":
                                scroll_bottom()
                                frame("bottom")
                                assert "Gracz 100" in record["frames"][-1]["semantics"]
                            elif screen == "results":
                                scroll_bottom()
                                frame("summary")
                                content = record["frames"][-1]["semantics"]
                                assert "Ranking gospodarzy" in content and "Ranking gości" in content
                                record["checks"].append("summary labels present; inspect PNG pixels for readable glyphs")
                            elif scale == 1.6:
                                scroll_bottom()
                                frame("bottom")
                            assert not record["pageErrors"], record["pageErrors"]
                            assert not record["blockedRequests"], record["blockedRequests"]
                            errors = [m for m in record["console"] if m["type"] == "error"
                                      or "F014_FLUTTER_ERROR" in m["text"]
                                      or re.search(r"overflowed|RenderFlex", m["text"], re.I)]
                            assert not errors, errors
                            record["status"] = "passed; pixel review required"
                        except Exception as error:
                            record["status"] = "failed"
                            record["failure"] = str(error)
                            page.screenshot(path=str(out / f"{prefix}-failure.png"))
                            (out / f"{prefix}-failure.html").write_text(page.content())
                        finally:
                            page.close()
                            (out / "browser.json").write_text(json.dumps(records, indent=2, ensure_ascii=False))
        finally:
            browser.close()
    failed = [r for r in records if r["status"] == "failed"]
    print(json.dumps({"cases": len(records), "failures": len(failed)}, indent=2))
    if failed:
        for record in failed:
            print(record["screen"], record["viewport"], record["textScale"], record["failure"])
        raise SystemExit(1)


if __name__ == "__main__":
    capture(*sys.argv[1:])
