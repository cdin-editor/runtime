#!/usr/bin/env bash
# Make sure a Lua 5.4+ interpreter is available. Runtime has no other
# dependencies: it is pure Lua and links no logger or native library.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

if lua_bin="$(bash "$here/lua-bin.sh" 2>/dev/null)"; then
  echo "Lua found: $lua_bin ($("$lua_bin" -v 2>&1))"
  exit 0
fi

sudo_cmd=()
if [[ "$(id -u)" -ne 0 ]] && command -v sudo >/dev/null 2>&1; then
  sudo_cmd=(sudo)
fi

if command -v apt-get >/dev/null 2>&1; then
  "${sudo_cmd[@]}" apt-get update -qq
  "${sudo_cmd[@]}" apt-get install -y -qq lua5.4
elif command -v brew >/dev/null 2>&1; then
  brew install lua
elif command -v pacman >/dev/null 2>&1; then
  "${sudo_cmd[@]}" pacman -S --noconfirm lua
else
  echo "no supported package manager found; install Lua 5.4 manually" >&2
  exit 2
fi

lua_bin="$("$here/lua-bin.sh")"
echo "Lua installed: $lua_bin ($("$lua_bin" -v 2>&1))"
