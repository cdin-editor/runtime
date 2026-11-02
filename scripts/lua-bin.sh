#!/usr/bin/env bash
# Print the Lua 5.4+ interpreter to use. Honors $LUA, then lua5.4, then lua.
# Exit 2 with a message when none is usable. Sourced-free: run it, read stdout.
set -euo pipefail

is_supported() {
  local bin="$1"
  command -v "$bin" >/dev/null 2>&1 || return 1
  "$bin" -e 'local m = tonumber(_VERSION:match("(%d+%.%d+)")); os.exit(m and m >= 5.4 and 0 or 1)' >/dev/null 2>&1
}

for candidate in "${LUA:-}" lua5.4 lua5.5 lua; do
  [[ -n "$candidate" ]] || continue
  if is_supported "$candidate"; then
    printf '%s\n' "$candidate"
    exit 0
  fi
done
echo "Lua 5.4 or newer is required (set LUA=... or run scripts/install-deps.sh)" >&2
exit 2
