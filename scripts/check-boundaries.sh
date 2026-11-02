#!/usr/bin/env bash
# Static guards for the Runtime logging and boundary rules (AGENTS.md rules 3, 13).
#   - Runtime never writes to stdout/stderr: records go to host:log, the Host
#     forwards them to the Kernel logger, and the Kernel decides where they land.
#   - Runtime never loads native code or its own logger (no log.c binding).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
status=0

check() {
  local description="$1" pattern="$2"
  local hits
  # Whole-line comments are documentation, not code.
  hits="$(grep -rnE --include='*.lua' "$pattern" lua | grep -vE '^[^:]+:[0-9]+:[[:space:]]*--' || true)"
  if [[ -n "$hits" ]]; then
    echo "boundary violation: $description" >&2
    echo "$hits" >&2
    status=1
  fi
}

check "direct console output (use host:log)" '(^|[^[:alnum:]_.:])print[[:space:]]*\(|io\.(write|stdout|stderr)|os\.exit'
check "native code or FFI (Runtime is pure Lua)" 'package\.loadlib|require[[:space:]]*\(?[[:space:]]*["'"'"'](ffi|alien|cffi|lfs)'
check "a second logger (the Kernel owns the only logger)" 'log\.c|mmlog|m-mdy-m/log|cdin_kernel_log|cdin_log_'

if [[ "$status" -eq 0 ]]; then
  echo "PASS boundary checks"
fi
exit "$status"
