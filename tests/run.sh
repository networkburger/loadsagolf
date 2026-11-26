#!/usr/bin/env bash
# Run headless tests. Fails on test failures *and* on any script error
# (GDScript has no exceptions, so a crashing test would otherwise look green).
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --import >/dev/null 2>&1
out=$("$GODOT" --headless -s tests/run_tests.gd 2>&1)
code=$?
echo "$out" | grep -vE "^Godot Engine|^\s*$"
if echo "$out" | grep -qE "SCRIPT ERROR|Parse Error|Compile Error"; then
  echo "FAILED: script errors above" >&2
  exit 1
fi
exit $code
