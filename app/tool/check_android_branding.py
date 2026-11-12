"""Check Android branding without building; optionally inspect a final APK with aapt2."""
import argparse
import json
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


def parse_xmltree(output):
    """Parse aapt2's indentation tree; reject incomplete or ambiguous evidence."""
    root = ET.Element("dump")
    stack = [(-2, root)]
    element_step = 2
    for line in output.splitlines():
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip(" "))
        text = line[indent:]
        require(indent % 2 == 0, "Invalid xmltree indentation")
        if text.startswith("N: "):
            namespace = re.fullmatch(
                r"N: android=http://schemas.android.com/apk/res/android( \(line=\d+\))?", text)
            require(indent == 0 and len(root) == 0 and namespace is not None,
                    "Unexpected xmltree namespace")
            # aapt2 uses four spaces per element level, two for attributes.
            # Legacy aapt uses two for both, without namespace line numbers.
            element_step = 4 if namespace[1] else 2
            stack = [(2 - element_step, root)]
            continue
        if text.startswith("E: "):
            match = re.fullmatch(r"E: ([\w-]+) \(line=\d+\)", text)
            require(match is not None, "Malformed xmltree element")
            while stack and stack[-1][0] >= indent:
                stack.pop()
            require(stack and indent == stack[-1][0] + element_step,
                    "Missing xmltree parent")
            node = ET.SubElement(stack[-1][1], match[1])
            stack.append((indent, node))
        elif text.startswith("A: "):
            match = re.fullmatch(
                r"A: ((?:http://schemas.android.com/apk/res/android:)?[\w:.-]+)"
                r"(?:\(0x[0-9a-fA-F]+\))?=(.+)", text)
            require(match is not None and indent == stack[-1][0] + 2,
                    "Malformed xmltree attribute")
            node = stack[-1][1]
            key = match[1].replace("http://schemas.android.com/apk/res/android:", "android:")
            require(key not in node.attrib, "Duplicate xmltree attribute")
            node.set(key, match[2])
        else:
            raise ValueError("Unknown xmltree record")
    require(len(root) == 1 and root[0].tag == "manifest", "Missing manifest tree")
    return root[0]


def tree_string(value):
    """Only literal compiled strings, not references or typed/null values."""
    require(value is not None, "Missing compiled string")
    match = re.fullmatch(r'("(?:[^"\\]|\\.)*")(?: \(Raw: ("(?:[^"\\]|\\.)*")\))?', value)
    require(match is not None, "Unresolved compiled string")
    result = json.loads(match[1])
    require(match[2] is None or json.loads(match[2]) == result,
            "Inconsistent compiled string")
    return result


def check_launcher_tree(output, launchers):
    manifest = parse_xmltree(output)
    require(tree_string(manifest.get("package")) == PACKAGE, "Manifest package mismatch")
    applications = manifest.findall("application")
    require(len(applications) == 1, "Missing or ambiguous application")
    application = applications[0]
    app_label = application.get("android:label")
    require(app_label is not None, "Missing application label")
    if not re.fullmatch(r"@0x[0-9a-fA-F]{8}", app_label):
        require(tree_string(app_label) == LABEL, "Wrong application label")

    def name(value):
        value = tree_string(value)
        require(bool(value), "Empty component name")
        return PACKAGE + value if value.startswith(".") else (
            PACKAGE + "." + value if "." not in value else value)

    def label(node):
        value = node.get("android:label")
        if value is not None and value != app_label:
            require(tree_string(value) == LABEL, "Explicit launcher label must be Pickteams")

    components = {}
    declared = set()
    for node in application:
        if node.tag not in ("activity", "activity-alias"):
            continue
        identity = name(node.get("android:name"))
        require(identity not in components, "Duplicate component identity")
        components[identity] = node
        for intent in node.findall("intent-filter"):
            actions = {tree_string(e.get("android:name")) for e in intent.findall("action")}
            categories = {tree_string(e.get("android:name")) for e in intent.findall("category")}
            if "android.intent.action.MAIN" in actions and "android.intent.category.LAUNCHER" in categories:
                label(intent)
                declared.add(identity)
    require(declared and declared == set(launchers), "Missing or inconsistent launcher identity")
    for identity in declared:
        node = components[identity]
        label(node)
        if node.tag == "activity-alias":
            target = name(node.get("android:targetActivity"))
            # Android permits only an activity declared before the alias, not alias chains.
            require(target in components and components[target].tag == "activity"
                    and list(components).index(target) < list(components).index(identity),
                    "Missing, cyclic or invalid alias target")
            if node.get("android:label") is None:
                label(components[target])


def check_badging(output, manifest_tree=None):
    package = re.search(r"^package: name='([^']+)'", output, re.MULTILINE)
    require(package is not None and package[1] == PACKAGE,
            "APK package must be com.example.app")
    labels = re.findall(r"^application-label(?:-[^:]+)?:'([^']*)'$",
                        output, re.MULTILINE)
    require(f"application-label:'{LABEL}'" in output.splitlines()
            and labels and all(label == LABEL for label in labels),
            "Every compiled application label must be Pickteams")
    launchers = re.findall(r"^launchable-activity: name='([^']+)'\s+label='([^']*)'",
                          output, re.MULTILINE)
    require(launchers and len({name for name, _ in launchers}) == len(launchers)
            and len(launchers) == len(re.findall(r"^launchable-activity:", output, re.MULTILINE))
            and all(label == LABEL or (label == "" and manifest_tree is not None)
                    for _, label in launchers),
            "Every compiled launcher label must be Pickteams")
    if manifest_tree is not None:
        check_launcher_tree(manifest_tree, [name for name, _ in launchers])


def check_apk(apk, aapt):
    result = subprocess.run([aapt, "dump", "badging", str(apk)],
                            check=True, text=True, capture_output=True)
    tree = subprocess.run([aapt, "dump", "xmltree", str(apk), "--file", "AndroidManifest.xml"],
                          check=True, text=True, capture_output=True)
    check_badging(result.stdout, tree.stdout)


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
