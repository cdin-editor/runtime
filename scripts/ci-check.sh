#!/usr/bin/env bash
# Full local/CI gate: dependencies, unit + integration tests, boundary checks
# and an extracted, source-independent Runtime module package smoke test.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
root="$(cd "$here/.." && pwd -P)"
bash "$here/install-deps.sh"
bash "$here/with-lua.sh" check
bash "$here/check-boundaries.sh"
python3 "$here/package-modules.py"
python3 "$here/test-module-package.py"
