#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
godot="$(command -v "${GODOT:-godot}")"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# Keep the character-creator save, logs, and engine data away from real profiles.
export HOME="$scratch" XDG_DATA_HOME="$scratch" XDG_CONFIG_HOME="$scratch" XDG_CACHE_HOME="$scratch"
export APPDATA="$scratch"
"$godot" --headless --path . --import --log-file "$scratch/import.log"
"$godot" --headless --path . --fixed-fps 60 --quit-after 1800 \
	--log-file "$scratch/tests.log" res://test/gameplay/GameplayTests.tscn -- --portrait
# Godot also reports macOS Keychain access and resource cleanup diagnostics.
if grep -E '^(SCRIPT ERROR|ERROR):' "$scratch/tests.log" |
	grep -Ev '^ERROR: (Condition "ret != noErr" is true[.] Returning: ""|[0-9]+ resources? still in use at exit.*)$'; then
	exit 1
fi
summary="$(sed -nE 's/^Completed ([0-9]+ gameplay checks)$/PASS: \1/p' "$scratch/tests.log")"
test -n "$summary"
printf '%s\n' "$summary"
