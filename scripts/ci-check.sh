#!/usr/bin/env bash
# Full local/CI gate: dependencies, unit + integration tests, boundary checks.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "$here/install-deps.sh"
bash "$here/with-lua.sh" check
bash "$here/check-boundaries.sh"
