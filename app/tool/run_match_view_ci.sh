#!/usr/bin/env bash
# Synthetic web proof only. Never load client config or publish the web bundle.
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
: "${PROOF_DIR:?Set an absolute artifact directory outside the checkout}"
: "${SOURCE_SHA:?Set the PR head SHA}"
mkdir -p "$PROOF_DIR"
server_pid=
cleanup() {
  rc=$?
  trap - EXIT
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  printf '%s\n' "$rc" > "$PROOF_DIR/run.exit"
  exit "$rc"
}
trap cleanup EXIT
run() {
  local phase=$1 rc
  shift
  printf 'COMMAND %s:' "$phase"
  printf ' %q' "$@"
  printf '\n'
  set +e
  "$@" > "$PROOF_DIR/$phase.log" 2>&1
  rc=$?
  set -e
  printf '%s\n' "$rc" > "$PROOF_DIR/$phase.exit"
  # Logs contain synthetic fixture diagnostics, never environment dumps.
  python3 -c 'import sys; print(open(sys.argv[1]).read(), end="")' "$PROOF_DIR/$phase.log"
  return "$rc"
}
source_check() {
  local phase=$1
  git rev-parse HEAD > "$PROOF_DIR/source-$phase.txt"
  git status --porcelain=v1 --untracked-files=all > "$PROOF_DIR/status-$phase.txt"
  test "$(git rev-parse HEAD)" = "$SOURCE_SHA"
  test ! -s "$PROOF_DIR/status-$phase.txt"
  git diff --exit-code > "$PROOF_DIR/diff-$phase.txt"
  git ls-files -z | xargs -0 sha256sum > "$PROOF_DIR/inputs-$phase.sha256"
}
cp .github/workflows/match-view-proof.yml "$PROOF_DIR/workflow-as-executed.yml"
cp app/tool/run_match_view_ci.sh "$PROOF_DIR/runner-as-executed.sh"
source_check before
exec 9>/tmp/pickteams-flutter-validation.lock
flock -n -E 75 9
awk '/MemTotal:|MemAvailable:/ {print}' /proc/meminfo > "$PROOF_DIR/resource.log"
# Hosted runner must have at least 7 GiB total and meet the unchanged build gate.
awk '/MemTotal:/ {if ($2 < 7340032) exit 1}' /proc/meminfo
awk '/MemAvailable:/ {if ($2 < 2621440) exit 1}' /proc/meminfo
run sdk flutter --version --machine
python3 - "$PROOF_DIR/sdk.log" <<'PY'
import json, sys
sdk = json.load(open(sys.argv[1]))
for key, expected in {
    'frameworkVersion': '3.47.9',
    'frameworkRevision': 'c197ca5199e9ee5661e865596c9c07294dfab51c',
    'engineRevision': '89c39edfdfae2949f6806e4a315c0c08522238b7',
}.items():
    assert sdk[key] == expected, (key, sdk[key], expected)
print('Exact framework version, framework revision and engine revision verified')
PY
cd app
run pub-get flutter pub get --enforce-lockfile
# Restore only the byte-for-byte known SDK insertion, never other changes.
git diff -- analysis_options.yaml > "$PROOF_DIR/sdk-migration.diff"
if [[ -s "$PROOF_DIR/sdk-migration.diff" ]]; then
  base64 --decode tool/match_view_analysis_migration.diff.b64 > "$PROOF_DIR/expected-sdk-migration.diff"
  cmp "$PROOF_DIR/sdk-migration.diff" "$PROOF_DIR/expected-sdk-migration.diff"
  git apply --reverse --check "$PROOF_DIR/expected-sdk-migration.diff"
  git apply --reverse "$PROOF_DIR/expected-sdk-migration.diff"
  printf 'Exact known migration compared and reversed\n' > "$PROOF_DIR/migration-restoration.txt"
else
  printf 'SDK made no analysis_options.yaml change\n' > "$PROOF_DIR/migration-restoration.txt"
fi
cd "$ROOT"
source_check before-build
cmp "$PROOF_DIR/inputs-before.sha256" "$PROOF_DIR/inputs-before-build.sha256"
cd app
run capture-unit python3 -m unittest discover -s tool -p test_match_view_capture.py -v
run fixture-format dart format --output=none --set-exit-if-changed tool/match_view_preview.dart
run fixture-analyze flutter analyze --no-pub tool/match_view_preview.dart
awk '/MemAvailable:/ {print; if ($2 < 2621440) exit 1}' /proc/meminfo >> "$PROOF_DIR/resource.log"
run build flutter build web --no-pub --profile --no-web-resources-cdn --no-wasm-dry-run --target tool/match_view_preview.dart
cd "$ROOT"
source_check after-build
cmp "$PROOF_DIR/inputs-before-build.sha256" "$PROOF_DIR/inputs-after-build.sha256"
cd app
python3 -u - "$PROOF_DIR/server.port" > "$PROOF_DIR/server.log" 2>&1 <<'PY' &
import http.server, os, sys
os.chdir('build/web')
server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), http.server.SimpleHTTPRequestHandler)
with open(sys.argv[1], 'w') as port:
    port.write(str(server.server_port))
server.serve_forever()
PY
server_pid=$!
for i in {1..50}; do [[ -s "$PROOF_DIR/server.port" ]] && break; sleep .2; done
port=$(< "$PROOF_DIR/server.port")
export MATCH_VIEW_CHROMIUM
MATCH_VIEW_CHROMIUM=$(python3 -c 'from playwright.sync_api import sync_playwright; p=sync_playwright().start(); print(p.chromium.executable_path); p.stop()')
export MATCH_VIEW_IMAGE_PYTHON
MATCH_VIEW_IMAGE_PYTHON=$(python3 -c 'import sys; print(sys.executable)')
run capture timeout 900s python3 tool/capture_match_view.py "http://127.0.0.1:$port" "$PROOF_DIR/frames"
cd "$ROOT"
source_check after-capture
cmp "$PROOF_DIR/inputs-before-build.sha256" "$PROOF_DIR/inputs-after-capture.sha256"
