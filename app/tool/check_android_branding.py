"""Check Android branding without building; optionally inspect a final APK with aapt2."""
import argparse
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

ANDROID = "{http://schemas.android.com/apk/res/android}"
LABEL = "Pickteams"
PACKAGE = "com.example.app"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def check_source(app):
    src = app / "android/app/src"
    root = ET.parse(src / "main/AndroidManifest.xml").getroot()
    application = root.find("application")
    require(application is not None, "Missing Android application")
    require(application.get(ANDROID + "label") == "@string/app_name",
            "Application label must use @string/app_name")
    strings = ET.parse(src / "main/res/values/strings.xml").getroot()
    names = strings.findall("string[@name='app_name']")
    require(len(names) == 1 and names[0].text == LABEL
            and names[0].get("translatable") == "false",
            "app_name must be non-translatable Pickteams")
    # A flavor, locale, activity or alias must not hide the application label.
    for manifest in src.glob("*/AndroidManifest.xml"):
        for element in ET.parse(manifest).getroot().iter():
            label = element.get(ANDROID + "label")
            require(label is None or label in ("@string/app_name", LABEL),
                    f"Unexpected label in {manifest}: {label!r}")
    for resource in src.glob("*/res/values*/*.xml"):
        for element in ET.parse(resource).getroot():
            if element.get("name") == "app_name":
                require(element.tag == "string" and element.text == LABEL,
                        f"Unexpected app_name override in {resource}")
    gradle = (app / "android/app/build.gradle.kts").read_text()
    require(re.search(r'applicationId\s*=\s*"com\.example\.app"', gradle),
            "Android applicationId must remain com.example.app")


def check_badging(output):
    package = re.search(r"^package: name='([^']+)'", output, re.MULTILINE)
    require(package is not None and package[1] == PACKAGE,
            "APK package must be com.example.app")
    labels = re.findall(r"^application-label(?:-[^:]+)?:'([^']*)'$",
                        output, re.MULTILINE)
    require(f"application-label:'{LABEL}'" in output.splitlines()
            and labels and all(label == LABEL for label in labels),
            "Every compiled application label must be Pickteams")
    launchers = re.findall(r"^launchable-activity:.*? label='([^']*)'",
                          output, re.MULTILINE)
    require(launchers and all(label == LABEL for label in launchers),
            "Every compiled launcher label must be Pickteams")


def check_apk(apk, aapt):
    result = subprocess.run([aapt, "dump", "badging", str(apk)],
                            check=True, text=True, capture_output=True)
    check_badging(result.stdout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--apk", type=Path, help="Final combined APK; does not build it")
    parser.add_argument("--aapt", default="aapt2", help="Android SDK aapt2 executable")
    args = parser.parse_args()
    try:
        check_source(args.app)
        print("PASS: Android source label is Pickteams; applicationId is com.example.app")
        if args.apk:
            check_apk(args.apk, args.aapt)
            print("PASS: APK application and launcher labels are Pickteams; package is com.example.app")
        else:
            print("PENDING: compiled APK label and package (use --apk and --aapt)")
        print("PENDING: device launcher and Android app-info display")
    except (ValueError, OSError, ET.ParseError, subprocess.CalledProcessError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
