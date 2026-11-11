#!/bin/bash
# Runs the headless tests and prints a compact report; exits non-zero when a test fails.
# Usage: tools/t.sh [suite]      (set GODOT to your Godot 4.5 console executable)
# A local Godot path can live in tools/godot_path.local (one line; git-ignored).
LOCAL_GODOT=""
[ -f "$(dirname "$0")/godot_path.local" ] && LOCAL_GODOT="$(head -n1 "$(dirname "$0")/godot_path.local" | tr -d '\r')"
if [ -n "$GODOT" ]; then G="$GODOT"; elif [ -x "$LOCAL_GODOT" ]; then G="$LOCAL_GODOT"; else G=godot; fi
cd "$(dirname "$0")/.."
OUT="$(mktemp)"
if [ -n "$1" ]; then
	timeout 600 "$G" --headless --path . --script res://tests/run_tests.gd -- --suite=$1 > "$OUT" 2>&1
else
	timeout 900 "$G" --headless --path . --script res://tests/run_tests.gd > "$OUT" 2>&1
fi
STATUS=$?
# Suite headers, results and failure messages; expected error backtraces ("       [0] ...") are left out.
grep -E "^(==|  PASS|  FAIL|       |[0-9]+ tests)|SCRIPT ERROR|Parse Error|^ERROR:|RPG event error" "$OUT" \
	| grep -vE '^       \[[0-9]+\]' | head -"${LINES_MAX:-1000}"
rm -f "$OUT"
exit $STATUS
