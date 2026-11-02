#!/usr/bin/env bash
# Full local/CI gate: dependencies, unit + integration tests, boundary checks.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
"$here/install-deps.sh"
"$here/with-lua.sh" check
"$here/check-boundaries.sh"
