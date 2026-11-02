#!/usr/bin/env bash
# Inspect the built archive the way a user receives it: verify checksums,
# unpack, confirm the embedded version, and run the full test suite inside.
# Used as the Pipeline release `artifact-test-command`.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
search_root="${PIPELINE_ARTIFACT_TEST_DIR:-$here/../dist}"

archive="$(find "$search_root" -name 'cdin-runtime-*.tar.gz' -print | sort | head -n 1)"
[[ -n "$archive" ]] || { echo "no cdin-runtime-*.tar.gz under ${search_root}" >&2; exit 1; }

(cd "$(dirname "$archive")" && sha256sum -c "$(basename "$archive").sha256")

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
tar -xzf "$archive" -C "$work"
package_dir="$(find "$work" -mindepth 1 -maxdepth 1 -type d | head -n 1)"

expected="$(basename "$archive" .tar.gz)"
expected="${expected#cdin-runtime-}"
embedded="$(sed -n 's/^return "\(.*\)"$/\1/p' "$package_dir/lua/cdin/runtime/core/release_metadata.lua")"
[[ "$embedded" == "$expected" ]] || { echo "embedded version ${embedded} != archive version ${expected}" >&2; exit 1; }

lua_bin="$("$here/lua-bin.sh")"
reported="$(cd "$package_dir" && "$lua_bin" -e 'package.path = "lua/?.lua;lua/?/init.lua;" .. package.path; io.write(require("cdin.runtime.core.version").runtime)')"
[[ "$reported" == "$expected" ]] || { echo "package reports version ${reported}, expected ${expected}" >&2; exit 1; }

(cd "$package_dir" && make check LUA="$lua_bin" && bash scripts/check-boundaries.sh)
echo "package ${expected} verified"
