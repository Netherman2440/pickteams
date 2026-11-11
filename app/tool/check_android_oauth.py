"""Static OAuth contract check; this does not build or run Android."""
from pathlib import Path
from urllib.parse import urlparse
import re
import xml.etree.ElementTree as ET

app = Path(__file__).resolve().parents[1]
auth = app / "lib/features/auth"
redirect_source = (auth / "infrastructure/oauth_redirect.dart").read_text()
callback = re.search(r"'(pl\.pickteams://[^']+)'", redirect_source).group(1)
uri = urlparse(callback)
android = "{http://schemas.android.com/apk/res/android}"
root = ET.parse(app / "android/app/src/main/AndroidManifest.xml").getroot()
assert any(p.get(android + "name") == "android.permission.INTERNET"
           for p in root.findall("uses-permission"))
activity = root.find("application/activity")
assert activity.get(android + "exported") == "true"
assert activity.get(android + "launchMode") == "singleTop"
assert any(m.get(android + "name") == "flutter_deeplinking_enabled"
           and m.get(android + "value") == "false"
           for m in activity.findall("meta-data"))
matching = []
for intent in activity.findall("intent-filter"):
    data = intent.find("data")
    if data is not None and data.get(android + "scheme") == uri.scheme:
        matching.append(intent)
        assert data.get(android + "host") == uri.hostname
        assert data.get(android + "path") == uri.path
        assert intent.find("action").get(android + "name") == "android.intent.action.VIEW"
        assert {c.get(android + "name") for c in intent.findall("category")} == {
            "android.intent.category.DEFAULT", "android.intent.category.BROWSABLE"}
assert len(matching) == 1
assert 'applicationId = "com.example.app"' in (app / "android/app/build.gradle.kts").read_text()
for path in auth.rglob("*.dart"):
    source = path.read_text()
    assert "getSessionFromUrl(" not in source, path
    assert "exchangeCodeForSession(" not in source, path
    assert "uriLinkStream" not in source, path
assert "Uri.base" not in (auth / "presentation/pages/auth_callback_page.dart").read_text()
assert callback in (app / "tool/android_google_oauth.md").read_text()
print(f"PASS: {callback} matches Android intent; release Internet enabled; Flutter link routing disabled")
print("PASS: applicationId unchanged; auth has no duplicate link listener or code exchange")
print("Static checks only: APK, Android dispatch, dashboard allowlist and Google provider are unproven")
