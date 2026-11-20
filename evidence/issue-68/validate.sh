#!/usr/bin/env bash
# Run from the repository root. One resource gate per Flutter/Dart command.
set -euo pipefail
exec 9>/tmp/pickteams-flutter-validation.lock
flock -n -E 75 9
mem=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
printf 'MemAvailable=%s KiB; minimum=2621440 KiB\n' "$mem"
if (( mem < 2621440 )); then
  printf 'Validation denied: insufficient memory; no retry.\n' >&2
  exit 75
fi
sdk=/home/agents/.local/share/pickteams-f001-sdk/flutter/bin
cd app
case "${1:-}" in
  format)
    set -- "$sdk/dart" format lib/features/draft/presentation/pages/draft_selection_page.dart test/features/draft/presentation/draft_selection_page_search_test.dart ;;
  focused)
    set -- "$sdk/flutter" test --no-pub test/features/draft/presentation/draft_selection_page_search_test.dart ;;
  analyze)
    set -- "$sdk/flutter" analyze --no-pub ;;
  full)
    set -- "$sdk/flutter" test --no-pub --coverage --concurrency=1 ;;
  *) printf 'Usage: bash evidence/issue-68/validate.sh format|focused|analyze|full\n' >&2; exit 2 ;;
esac
printf 'Command:'; printf ' %q' "$@"; printf '\n'
"$@"
