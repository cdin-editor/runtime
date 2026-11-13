#!/usr/bin/env python3
"""Build deterministic, platform-neutral Runtime Lua module packages.

The output is an install-time artifact, not a replacement for the contributor
source archive. Registry consumes the generated Component Release Metadata
only after the corresponding immutable GitHub Release assets exist.
"""
from __future__ import annotations

import argparse
import datetime as dt
import gzip
import hashlib
import io
import json
import os
import re
import stat
import subprocess
import sys
import tarfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = "https://github.com/cdin-editor/runtime"
RELEASE_BASE = "https://github.com/cdin-editor/runtime/releases/download"
VERSION_PATTERN = re.compile(
    r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
    r"(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$"
)


def run(command: list[str], *, cwd: Path = ROOT, env: dict[str, str] | None = None) -> str:
    result = subprocess.run(
        command, cwd=cwd, env=env, check=True, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    return result.stdout.strip()


def git(*arguments: str) -> str:
    return run(["git", *arguments])


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def lua_executable() -> str:
    value = run(["bash", "scripts/lua-bin.sh"])
    executable = value.splitlines()[-1].strip()
    if not executable:
        raise RuntimeError("scripts/lua-bin.sh did not return a Lua executable")
    reported = run([executable, "-e", 'io.write(_VERSION)'])
    if reported != "Lua 5.4":
        raise RuntimeError(f"module packages require PUC Lua 5.4.x; found {reported}")
    return executable


def runtime_version(lua: str, *, override: str | None = None) -> str:
    env = os.environ.copy()
    env.pop("CDIN_RUNTIME_VERSION", None)
    if override:
        env["CDIN_RUNTIME_VERSION"] = override
    expression = (
        'package.path = "lua/?.lua;lua/?/init.lua;" .. package.path; '
        'io.write(require("cdin.runtime.core.version").runtime)'
    )
    return run([lua, "-e", expression], env=env)


def source_files() -> dict[str, bytes]:
    raw = subprocess.run(
        ["git", "ls-files", "-z", "--", "lua"],
        cwd=ROOT, check=True, stdout=subprocess.PIPE,
    ).stdout
    names = sorted(item.decode("utf-8") for item in raw.split(b"\0") if item)
    files: dict[str, bytes] = {}
    for name in names:
        path = ROOT / name
        if not name.startswith("lua/") or not name.endswith(".lua"):
            continue
        if path.is_symlink() or not path.is_file():
            raise RuntimeError(f"Runtime module must be a regular tracked file: {name}")
        files[name] = path.read_bytes()

    metadata_path = "lua/cdin/runtime/core/release_metadata.lua"
    if metadata_path not in files:
        raise RuntimeError(f"required module is missing: {metadata_path}")
    return files


def stable_json(value: object) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")


def archive_timestamp(epoch: int) -> tuple[int, int, int, int, int, int]:
    # ZIP has a 1980 lower bound and stores seconds at two-second precision.
    value = max(epoch, 315532800)
    stamp = dt.datetime.fromtimestamp(value, tz=dt.timezone.utc)
    return (stamp.year, stamp.month, stamp.day, stamp.hour, stamp.minute, stamp.second - stamp.second % 2)


def write_tar_gz(destination: Path, root_name: str, files: dict[str, bytes], epoch: int) -> None:
    with destination.open("wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, compresslevel=9, mtime=epoch) as compressed:
            with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as archive:
                for relative, data in sorted(files.items()):
                    info = tarfile.TarInfo(f"{root_name}/{relative}")
                    info.size = len(data)
                    info.mode = 0o644
                    info.uid = 0
                    info.gid = 0
                    info.uname = ""
                    info.gname = ""
                    info.mtime = epoch
                    archive.addfile(info, io.BytesIO(data))


def write_zip(destination: Path, root_name: str, files: dict[str, bytes], epoch: int) -> None:
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for relative, data in sorted(files.items()):
            info = zipfile.ZipInfo(f"{root_name}/{relative}", date_time=archive_timestamp(epoch))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = (stat.S_IFREG | 0o644) << 16
            info.flag_bits |= 0x800
            archive.writestr(info, data, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", help="package version; defaults to the version resolved by Runtime")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "dist")
    parser.add_argument("--runner", default=os.getenv("RUNTIME_PACKAGE_RUNNER", ""))
    args = parser.parse_args()

    if git("status", "--porcelain", "--untracked-files=no"):
        raise RuntimeError("refusing to package a source checkout with tracked modifications")

    revision = git("rev-parse", "--verify", "HEAD")
    if not re.fullmatch(r"(?:[0-9a-f]{40}|[0-9a-f]{64})", revision):
        raise RuntimeError(f"unexpected full Git revision: {revision}")
    epoch = int(git("show", "-s", "--format=%ct", "HEAD"))

    lua = lua_executable()
    resolved_version = runtime_version(lua)
    version = args.version or resolved_version
    if not VERSION_PATTERN.fullmatch(version):
        raise RuntimeError(f"invalid Runtime package version: {version!r}")
    if version != resolved_version:
        raise RuntimeError(
            f"requested package version {version} does not match Runtime's resolved version {resolved_version}"
        )

    release_tag = os.getenv("PIPELINE_RELEASE_TAG") or os.getenv("GITHUB_REF_NAME", "")
    is_release_tag = (
        os.getenv("PIPELINE_DRY_RUN", "false").lower() != "true"
        and (
            os.getenv("GITHUB_REF_TYPE") == "tag"
            or bool(os.getenv("PIPELINE_RELEASE_TAG"))
        )
    )
    if is_release_tag:
        expected_tag = f"v{version}"
        if release_tag != expected_tag:
            raise RuntimeError(
                f"release tag {release_tag!r} does not match the exact Runtime tag {expected_tag!r}"
            )
        resolved_tag_commit = git("rev-parse", "--verify", f"refs/tags/{release_tag}^{{commit}}")
        if resolved_tag_commit != revision:
            raise RuntimeError(
                f"release tag {release_tag} resolves to {resolved_tag_commit}, not packaged HEAD {revision}"
            )

    files = source_files()
    files["lua/cdin/runtime/core/release_metadata.lua"] = (
        f'return "{version}"\n'.encode("utf-8")
    )
    for legal_file in ("LICENSE", "NOTICE"):
        path = ROOT / legal_file
        if not path.is_file():
            raise RuntimeError(f"required package notice is missing: {legal_file}")
        files[legal_file] = path.read_bytes()

    file_records = [
        {"path": name, "size_bytes": len(data), "sha256": sha256(data)}
        for name, data in sorted(files.items())
    ]
    manifest = {
        "schema_version": "1.0.0",
        "component_id": "runtime",
        "variant": "default",
        "version": version,
        "source_revision": revision,
        "repository_uri": REPOSITORY,
        "layout": "lua-module-tree-v1",
        "module_root": "lua",
        "runtime_requirement": "PUC Lua >=5.4 <5.5",
        "contracts": {
            "provides": [
                {"contract_id": "org.cdin.runtime-extension-contract", "version": "1.0.0"}
            ],
            "requires": [
                {"contract_id": "org.cdin.runtime-host-api", "version_constraint": ">=1.0.0 <2.0.0"}
            ],
        },
        "files": file_records,
    }
    files["package-manifest.json"] = stable_json(manifest)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    root_name = f"cdin-runtime-{version}"
    stem = f"cdin-runtime-{version}-modules"
    tar_path = args.output_dir / f"{stem}.tar.gz"
    zip_path = args.output_dir / f"{stem}.zip"
    write_tar_gz(tar_path, root_name, files, epoch)
    write_zip(zip_path, root_name, files, epoch)

    runner = args.runner or (
        f"github-actions-{os.getenv('RUNNER_OS', 'unknown').lower()}-{os.getenv('RUNNER_ARCH', 'unknown').lower()}"
        if os.getenv("GITHUB_ACTIONS") == "true" else "local"
    )
    artifacts = []
    zip_companion: dict[str, object] = {}
    for artifact_path, archive_format in ((tar_path, "tar.gz"), (zip_path, "zip")):
        data = artifact_path.read_bytes()
        artifact = {
            "artifact_id": "runtime-lua-modules",
            "kind": "runtime-module-archive",
            "target": {"os": "any", "architecture": "any", "abi": "none"},
            "format": archive_format,
            "file_name": artifact_path.name,
            "uri": f"{RELEASE_BASE}/v{version}/{artifact_path.name}",
            "sha256": sha256(data),
            "size_bytes": len(data),
            "layout": "lua-module-tree-v1",
            "source_unit_ids": ["runtime-source"],
            "build": {
                "recipe": {"source_unit_id": "runtime-source", "path": "scripts/package-modules.py"},
                "toolchain": [
                    {"name": "PUC Lua", "version": "5.4.x"},
                    {"name": "Python", "version": f"{sys.version_info.major}.{sys.version_info.minor}"},
                ],
                "runner": runner,
            },
        }
        if archive_format == "tar.gz":
            # Registry resolves one artifact per target. Keep TAR.GZ canonical;
            # publishing ZIP as a second identical-target descriptor is ambiguous.
            artifacts.append(artifact)
        else:
            zip_companion = {
                "format": "zip",
                "file_name": artifact_path.name,
                "uri": artifact["uri"],
                "sha256": artifact["sha256"],
                "size_bytes": artifact["size_bytes"],
            }
        checksum = sha256(data)
        sidecar = artifact_path.with_name(artifact_path.name + ".sha256")
        sidecar.write_text(f"{checksum}  {artifact_path.name}\n", encoding="utf-8")

    release_metadata = {
        "schema_version": "1.2.0" if is_release_tag else "1.1.0",
        "component_id": "runtime",
        "variant": "default",
        "version": version,
        "status": "active",
        "source_units": [
            {"source_unit_id": "runtime-source", "repository_uri": REPOSITORY, "revision": revision}
        ],
        "dependencies": [],
        "contracts": {
            "provides": [
                {"contract_id": "org.cdin.runtime-extension-contract", "version": "1.0.0"}
            ],
            "requires": [
                {"contract_id": "org.cdin.runtime-host-api", "version_constraint": ">=1.0.0 <2.0.0"}
            ],
        },
        "artifacts": artifacts,
        "extensions": {
            "org.cdin.runtime.package-formats": {"zip": zip_companion}
        },
    }
    # ADR-0028: a tagged publisher emits the metadata JSON as a canonical
    # GitHub Release Asset. The document identifies the exact tag commit but
    # deliberately does not embed its own asset URI, digest or byte size;
    # GitHub Release Asset API metadata supplies those values to Registry.
    if is_release_tag:
        release_metadata["publication"] = {
            "provider": "github-releases-v1",
            "repository_uri": REPOSITORY,
            "tag": release_tag,
            "tag_commit": revision,
            "metadata_asset_name": f"runtime-{version}.json",
        }

    metadata_path = args.output_dir / f"runtime-{version}.json"
    metadata_path.write_bytes(stable_json(release_metadata))

    print(f"Runtime module package: {version} ({revision})")
    print(f"  {tar_path}")
    print(f"  {zip_path}")
    print(f"  {metadata_path}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.CalledProcessError, ValueError) as error:
        print(f"package-modules: {error}", file=sys.stderr)
        raise SystemExit(1)
