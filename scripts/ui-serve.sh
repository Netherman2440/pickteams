#!/usr/bin/env bash
# Lifecycle helper for the local Flutter web dev server used in UI-verification
# tasks (mobile audit / responsive refactor). Works from any checkout or
# cezar worktree of this repo — run it from the repo root.
#
#   bash scripts/ui-serve.sh start      # stop stale server, compile & serve, wait ready
#   bash scripts/ui-serve.sh restart    # stop + start (use after every code change)
#   bash scripts/ui-serve.sh stop       # stop the server
#   bash scripts/ui-serve.sh ready      # exit 0 when serving, 1 otherwise
#
# The server runs in DEBUG mode (flutter run -d web-server). This is required:
# debug builds expose the flt-semantics-placeholder (accessibility tree) and
# paint RenderFlex overflow stripes; release builds do not.
#
# Port is fixed (4370) so the browser tooling always hits the same URL.
set -uo pipefail

PORT=4370
HOST=127.0.0.1
BASE_URL="http://${HOST}:${PORT}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$REPO_ROOT/app"
ENV_FILE="$APP_DIR/.env"
TMP_DIR="$REPO_ROOT/.ai/cezar/tmp"
LOG_FILE="$TMP_DIR/ui-serve.log"

# The Supabase publishable (anon) key is public by design — it ships in the
# production JS bundle. These are the production project credentials so the
# dev server talks to real data (RLS keeps unauthenticated users read-only).
write_env_if_missing() {
  if [ ! -f "$ENV_FILE" ]; then
    mkdir -p "$(dirname "$ENV_FILE")"
    cat > "$ENV_FILE" <<'ENVEOF'
SUPABASE_URL=https://foyevztkvygfqbrtfqzx.supabase.co
SUPABASE_ANON_KEY=sb_publishable_caGWsuVMXXzz6WSTeANveA_WWWegP4R
ENVEOF
    echo "ui-serve: created $ENV_FILE (publishable key, gitignored)"
  fi
}

listening_pids() {
  netstat -ano 2>/dev/null | grep -E "TCP.*[:.]${PORT} .*LISTENING" | awk '{print $NF}' | sort -u
}

stop_server() {
  local pids
  pids="$(listening_pids)"
  if [ -n "$pids" ]; then
    for pid in $pids; do
      taskkill //T //F //PID "$pid" >/dev/null 2>&1 || true
    done
    # Give the OS a moment to free the port.
    for _ in 1 2 3 4 5 6; do
      [ -z "$(listening_pids)" ] && break
      sleep 1
    done
  fi
  if [ -n "$(listening_pids)" ]; then
    echo "ui-serve: WARN — port $PORT still busy after kill" >&2
  else
    echo "ui-serve: stopped (port $PORT free)"
  fi
}

wait_ready() {
  # Deadline covers a cold debug compile; incremental restarts are faster.
  local deadline=$((SECONDS + 150))
  while [ $SECONDS -lt $deadline ]; do
    if curl -s -o /dev/null -m 5 "$BASE_URL"; then
      echo "ui-serve: READY at $BASE_URL"
      return 0
    fi
    sleep 2
  done
  echo "ui-serve: server did not become ready within 240s — tail of log:" >&2
  tail -n 30 "$LOG_FILE" >&2
  return 1
}

case "${1:-}" in
  start)
    mkdir -p "$TMP_DIR"
    write_env_if_missing
    stop_server
    (cd "$APP_DIR" && flutter pub get >/dev/null 2>&1 || flutter pub get)
    echo "ui-serve: launching flutter run -d web-server (debug) on $BASE_URL ..."
    # Detach the launcher subshell's stdio so nothing in the flutter process
    # chain inherits this script's stdout/stdin — a caller piping the script
    # (e.g. `| tail`) would otherwise block until the server exits.
    ( cd "$APP_DIR" && nohup flutter run -d web-server \
        --web-hostname "$HOST" --web-port "$PORT" \
        --dart-define-from-file=.env < /dev/null > "$LOG_FILE" 2>&1 & ) \
        < /dev/null > /dev/null 2>&1
    wait_ready
    ;;
  restart)
    mkdir -p "$TMP_DIR"
    write_env_if_missing
    stop_server
    echo "ui-serve: relaunching (incremental compile is usually faster)..."
    ( cd "$APP_DIR" && nohup flutter run -d web-server \
        --web-hostname "$HOST" --web-port "$PORT" \
        --dart-define-from-file=.env < /dev/null > "$LOG_FILE" 2>&1 & ) \
        < /dev/null > /dev/null 2>&1
    wait_ready
    ;;
  stop)
    stop_server
    ;;
  ready)
    if curl -s -o /dev/null -m 5 "$BASE_URL"; then
      echo "ui-serve: READY at $BASE_URL"
    else
      echo "ui-serve: not serving" >&2
      exit 1
    fi
    ;;
  *)
    echo "usage: bash scripts/ui-serve.sh {start|restart|stop|ready}" >&2
    exit 2
    ;;
esac
