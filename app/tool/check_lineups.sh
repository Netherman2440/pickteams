#!/usr/bin/env bash
# One private, source-pinned validation lane. Exit 75 means resource blocked.
set -euo pipefail
umask 077
WT=$(git rev-parse --show-toplevel)
SOURCE=${1:?candidate SHA required}
E=${2:?absolute evidence directory required}
mkdir -p "$E"
server_pid=
cleanup() {
  rc=$?
  trap - EXIT
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  printf '%s\n' "$rc" > "$E/run.exit"
  exit "$rc"
}
trap cleanup EXIT
printf '%s\n' "$$" > "$E/run.pid"
printf 'lock\n' > "$E/stage"
exec 9>/tmp/pickteams-flutter-validation.lock
flock -n -E75 9
[[ $(git rev-parse HEAD) == "$SOURCE" ]]
[[ -z $(git status --porcelain) ]]
printf '%s\n' "$SOURCE" > "$E/source.txt"
export PATH="$HOME/.local/bin:$HOME/.local/share/pickteams-f001-sdk/unzip/usr/bin:$HOME/.local/share/pickteams-f001-sdk/flutter/bin:$PATH"
cd "$WT/app"
printf 'dependencies\n' > "$E/stage"
flutter pub get --offline --enforce-lockfile > "$E/pub-get.log" 2>&1
if ! git diff --quiet -- analysis_options.yaml; then
  git diff -- analysis_options.yaml > "$E/sdk-migration.diff"
  cmp "$E/sdk-migration.diff" /home/agents/dev/pickteams/.limen/releases/8c0aa30/analysis-options-migration.diff
  git restore -- analysis_options.yaml
fi
printf 'tests\n' > "$E/stage"
flutter test --no-pub --concurrency=1 \
  test/features/matches/presentation/lineup_collapse_test.dart \
  test/features/matches/presentation/match_score_breakpoint_test.dart \
  test/features/matches/presentation/match_actions_menu_test.dart \
  test/features/draft/presentation/player_lists_responsive_test.dart \
  test/draft/presentation/draft_results_page_rules_test.dart \
  test/draft/application/accept_match_draft_use_case_test.dart > "$E/tests.log" 2>&1
printf 'analysis\n' > "$E/stage"
flutter analyze --no-pub \
  lib/core/widgets/lineup_header.dart \
  lib/features/matches/presentation/pages/match_details_page.dart \
  lib/features/draft/presentation/pages/draft_results_page.dart \
  test/features/matches/presentation/lineup_collapse_test.dart \
  test/features/matches/presentation/match_score_breakpoint_test.dart \
  test/features/matches/presentation/match_actions_menu_test.dart \
  test/features/draft/presentation/player_lists_responsive_test.dart \
  test/fixtures/player_lists_app.dart test/fixtures/lineup_app.dart \
  tool/lineup_preview.dart > "$E/analyze.log" 2>&1
printf 'memory\n' > "$E/stage"
available=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
printf '%s kB\n' "$available" > "$E/memory.txt"
(( available >= 2621440 )) || exit 75
printf 'build\n' > "$E/stage"
flutter build web --no-pub --profile --no-web-resources-cdn --no-wasm-dry-run --target tool/lineup_preview.dart > "$E/build.log" 2>&1
python3 -u -c 'import http.server,os,sys; os.chdir("build/web"); s=http.server.ThreadingHTTPServer(("127.0.0.1",0),http.server.SimpleHTTPRequestHandler); open(sys.argv[1],"w").write(str(s.server_port)); s.serve_forever()' "$E/server.port" > "$E/server.log" 2>&1 &
server_pid=$!
printf '%s\n' "$server_pid" > "$E/server.pid"
for i in {1..50}; do [[ -s "$E/server.port" ]] && break; sleep .2; done
export LD_LIBRARY_PATH="$HOME/.local/share/playwright-system-libs/root/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export FONTCONFIG_FILE="$HOME/.local/share/playwright-system-libs/fonts.conf"
printf 'capture\n' > "$E/stage"
timeout 600s playwright-local python tool/capture_lineups.py "http://127.0.0.1:$(< "$E/server.port")" "$E/frames" > "$E/capture.log" 2>&1
[[ $(git rev-parse HEAD) == "$SOURCE" ]]
[[ -z $(git status --porcelain) ]]
printf 'captured; inspect originals before acceptance\n' > "$E/stage"
