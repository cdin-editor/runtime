#!/usr/bin/env bash
# Build source release archives into dist/. Used by `pipeline.toml` (task
# `package`) and by the Pipeline release workflow as its build command.
#
# The version comes from the release tag (PIPELINE_RELEASE_TAG, else
# GITHUB_REF_NAME) and must equal the git-derived Runtime version, so a tag on
# the wrong commit cannot ship under another version's name.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$here/.."

tag="${PIPELINE_RELEASE_TAG:-${GITHUB_REF_NAME:-}}"
if [[ -z "$tag" ]]; then
  echo "set PIPELINE_RELEASE_TAG (for example v1.0.0) to build release archives" >&2
  exit 2
fi
version="${tag#v}"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$ ]]; then
  echo "unsupported release tag: ${tag} (use vMAJOR.MINOR.PATCH with an optional SemVer prerelease)" >&2
  exit 1
fi

# Spec: RT-001 / ADR-0019 require the supported PUC Lua 5.4 runtime.
# Invoke through bash because source archives may not preserve executable bits.
lua_bin="$(bash "$here/lua-bin.sh")"
runtime_version="$("$lua_bin" -e 'package.path = "lua/?.lua;lua/?/init.lua;" .. package.path; io.write(require("cdin.runtime.core.version").runtime)')"
if [[ "${PIPELINE_DRY_RUN:-false}" == "true" && "${GITHUB_REF_TYPE:-}" != "tag" ]]; then
  # The Pipeline candidate tag is synthetic on branch dry-runs. Keep Runtime
  # artifacts tied to the version resolved from the source tree.
  version="$runtime_version"
else
  if [[ "$runtime_version" != "$version" ]]; then
    echo "git-derived Runtime version (${runtime_version}) does not match tag (${version})" >&2
    echo "make sure the tag points at the intended commit and history/tags are fetched" >&2
    exit 1
  fi
fi

if [[ "${PIPELINE_DRY_RUN:-false}" != "true" || "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
  if ! grep -Fq "## [${version}]" CHANGELOG.md; then
    echo "CHANGELOG.md has no section for ${version}" >&2
    exit 1
  fi
else
  echo "Branch dry-run: skipping the release changelog section check for derived version ${version}."
fi

command -v zip >/dev/null 2>&1 || { echo "zip is required to build the .zip archive" >&2; exit 2; }

name="cdin-runtime-${version}"
rm -rf dist release-root
mkdir -p dist "release-root/${name}"

git archive --format=tar HEAD | tar -xf - -C "release-root/${name}"

# git archive has no .git, so embed the version as a generated module.
# Source checkouts keep using `git describe`. The file is not tracked.
printf 'return "%s"\n' "$version" > "release-root/${name}/lua/cdin/runtime/core/release_metadata.lua"

tar -C release-root -czf "dist/${name}.tar.gz" "$name"
(cd release-root && zip -qr "../dist/${name}.zip" "$name")
(
  cd dist
  sha256sum "${name}.tar.gz" > "${name}.tar.gz.sha256"
  sha256sum "${name}.zip" > "${name}.zip.sha256"
)
rm -rf release-root

echo "built dist/${name}.tar.gz and dist/${name}.zip (+ .sha256)"
