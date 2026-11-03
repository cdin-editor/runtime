#!/usr/bin/env bash
# Run a Makefile target with the detected interpreter: scripts/with-lua.sh unit
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$here/.."
# Spec: RT-001 / ADR-0019 require the supported PUC Lua 5.4 runtime.
# Invoke through bash because source archives may not preserve executable bits.
lua_bin="$(bash "$here/lua-bin.sh")"
exec make "$@" LUA="$lua_bin"
