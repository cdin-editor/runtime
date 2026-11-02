#!/usr/bin/env bash
# Run a Makefile target with the detected interpreter: scripts/with-lua.sh unit
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$here/.."
lua_bin="$("$here/lua-bin.sh")"
exec make "$@" LUA="$lua_bin"
