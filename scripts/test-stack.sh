#!/usr/bin/env bash
# Launch a local test stack: one headless server + two windowed clients.
# Works on Windows (Git Bash / MSYS) and macOS.
#
# Usage:   scripts/test-stack.sh [--solo]
#   --solo : start only one client (for single-player / solo-test-mode runs)
#
# Stop everything with Ctrl+C — the script tears down all processes on exit.
# Per-process logs are written to test-logs/.

set -euo pipefail

SOLO=false
if [ "${1:-}" = "--solo" ]; then
    SOLO=true
fi

# --- Platform-dependent Godot binary ---------------------------------------
case "$(uname -s)" in
    Darwin*)
        GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
        ;;
    MINGW*|MSYS*|CYGWIN*)
        GODOT="/c/tools/Godot/Godot_v4.6.2-stable_win64.exe"
        ;;
    *)
        echo "Unsupported OS: $(uname -s)" >&2
        exit 1
        ;;
esac

if [ ! -x "$GODOT" ]; then
    echo "Godot binary not found or not executable: $GODOT" >&2
    echo "Update scripts/test-stack.sh with the correct path." >&2
    exit 1
fi

# --- Paths ------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$REPO_ROOT/godot"
LOG_DIR="$REPO_ROOT/test-logs"
mkdir -p "$LOG_DIR"

# --- Cleanup on exit --------------------------------------------------------
PIDS=()
cleanup() {
    echo ""
    echo "Shutting down test stack..."
    for pid in "${PIDS[@]:-}"; do
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
    done
    # Give them a moment to exit cleanly
    sleep 1
    for pid in "${PIDS[@]:-}"; do
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null || true
        fi
    done
    echo "Done."
}
trap cleanup EXIT INT TERM

# --- Launch server ----------------------------------------------------------
echo "Starting headless server..."
"$GODOT" --headless --path "$PROJECT_DIR" -- --server \
    > "$LOG_DIR/server.log" 2>&1 &
PIDS+=($!)

# Small delay so the server is listening before clients dial in
sleep 1

# --- Launch clients ---------------------------------------------------------
echo "Starting client 1..."
"$GODOT" --path "$PROJECT_DIR" \
    > "$LOG_DIR/client1.log" 2>&1 &
PIDS+=($!)

if [ "$SOLO" = false ]; then
    echo "Starting client 2..."
    "$GODOT" --path "$PROJECT_DIR" \
        > "$LOG_DIR/client2.log" 2>&1 &
    PIDS+=($!)
fi

# --- Summary ----------------------------------------------------------------
echo ""
echo "Test stack running:"
echo "  Server   PID ${PIDS[0]}  log: $LOG_DIR/server.log"
echo "  Client 1 PID ${PIDS[1]}  log: $LOG_DIR/client1.log"
if [ "$SOLO" = false ]; then
    echo "  Client 2 PID ${PIDS[2]}  log: $LOG_DIR/client2.log"
fi
echo ""
echo "Press Ctrl+C to stop everything."

# Wait for any child to exit (or Ctrl+C). If one dies, tear down the rest.
wait -n "${PIDS[@]}" 2>/dev/null || true
