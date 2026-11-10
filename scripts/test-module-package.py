#!/usr/bin/env python3
"""Verify the extracted Runtime module archives without a Runtime source checkout."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_name(name: str, root_name: str) -> str:
    item = PurePosixPath(name)
    if item.is_absolute() or not item.parts or item.parts[0] != root_name:
        raise RuntimeError(f"archive entry outside expected root: {name!r}")
    if any(part in ("", ".", "..") for part in item.parts):
        raise RuntimeError(f"unsafe archive path: {name!r}")
    return item.as_posix()


def extract_tar(archive_path: Path, destination: Path, root_name: str) -> Path:
    package_root = destination / root_name
    package_root.mkdir(parents=True)
    seen: set[str] = set()
    with tarfile.open(archive_path, "r:gz") as archive:
        for member in archive.getmembers():
            name = safe_name(member.name, root_name)
            if name in seen:
                raise RuntimeError(f"duplicate TAR entry: {name}")
            seen.add(name)
            if not member.isfile():
                raise RuntimeError(f"non-regular TAR entry is forbidden: {name}")
            relative = PurePosixPath(name).relative_to(root_name)
            target = package_root.joinpath(*relative.parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            source = archive.extractfile(member)
            if source is None:
                raise RuntimeError(f"could not read TAR entry: {name}")
            with source, target.open("xb") as output:
                shutil.copyfileobj(source, output)
    return package_root


def extract_zip(archive_path: Path, destination: Path, root_name: str) -> Path:
    package_root = destination / root_name
    package_root.mkdir(parents=True)
    seen: set[str] = set()
    with zipfile.ZipFile(archive_path) as archive:
        for member in archive.infolist():
            name = safe_name(member.filename, root_name)
            if member.is_dir():
                raise RuntimeError(f"unexpected directory entry in ZIP: {name}")
            mode = (member.external_attr >> 16) & 0xFFFF
            file_type = stat.S_IFMT(mode)
            if file_type not in (0, stat.S_IFREG):
                raise RuntimeError(f"non-regular ZIP entry is forbidden: {name}")
            if name in seen:
                raise RuntimeError(f"duplicate ZIP entry: {name}")
            seen.add(name)
            relative = PurePosixPath(name).relative_to(root_name)
            target = package_root.joinpath(*relative.parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(member, "r") as source, target.open("xb") as output:
                shutil.copyfileobj(source, output)
    return package_root


def verify_package_tree(package_root: Path, metadata: dict[str, object]) -> None:
    manifest_path = package_root / "package-manifest.json"
    if not manifest_path.is_file():
        raise RuntimeError("package-manifest.json is missing")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    for key in ("component_id", "variant", "version", "source_revision", "layout"):
        expected = {
            "component_id": "runtime",
            "variant": "default",
            "version": metadata["version"],
            "source_revision": metadata["source_units"][0]["revision"],
            "layout": "lua-module-tree-v1",
        }[key]
        if manifest.get(key) != expected:
            raise RuntimeError(f"package manifest {key} mismatch: {manifest.get(key)!r} != {expected!r}")

    records = manifest.get("files")
    if not isinstance(records, list) or not records:
        raise RuntimeError("package manifest has no file records")
    expected_names = {"package-manifest.json"}
    for record in records:
        if not isinstance(record, dict):
            raise RuntimeError("invalid package file record")
        relative = record.get("path")
        if not isinstance(relative, str) or relative.startswith("/") or ".." in PurePosixPath(relative).parts:
            raise RuntimeError(f"unsafe package manifest path: {relative!r}")
        target = package_root.joinpath(*PurePosixPath(relative).parts)
        if not target.is_file() or target.is_symlink():
            raise RuntimeError(f"manifest file is missing or not regular: {relative}")
        data = target.read_bytes()
        if len(data) != record.get("size_bytes") or hashlib.sha256(data).hexdigest() != record.get("sha256"):
            raise RuntimeError(f"package file digest/size mismatch: {relative}")
        expected_names.add(relative)

    actual_names = {
        path.relative_to(package_root).as_posix()
        for path in package_root.rglob("*")
        if path.is_file()
    }
    if actual_names != expected_names:
        raise RuntimeError(
            f"package contains missing or unexpected files: "
            f"missing={sorted(expected_names - actual_names)}, extra={sorted(actual_names - expected_names)}"
        )
    if not (package_root / "lua/cdin/runtime/core/version.lua").is_file():
        raise RuntimeError("Runtime version module is missing")
    if not (package_root / "lua/cdin/runtime/core/release_metadata.lua").is_file():
        raise RuntimeError("embedded release version module is missing")
    if not (package_root / "LICENSE").is_file() or not (package_root / "NOTICE").is_file():
        raise RuntimeError("license or notice is missing")

    for forbidden in (".git", ".github", "tests", "docs", "build", "dist"):
        if (package_root / forbidden).exists():
            raise RuntimeError(f"development content must not be shipped: {forbidden}")


def verify_lua_load(package_root: Path, expected_version: str) -> None:
    lua_path = subprocess.run(
        ["bash", "scripts/lua-bin.sh"], cwd=ROOT, check=True,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    ).stdout.strip().splitlines()[-1]
    expression = (
        'package.path = "lua/?.lua;lua/?/init.lua;" .. package.path; '
        f'local version = require("cdin.runtime.core.version"); '
        f'assert(version.runtime == "{expected_version}", version.runtime); '
        'assert(version.extension_contract.major == 1); '
        'assert(version.extension_contract.minor == 0); '
        'assert(type(require("cdin.runtime.core.strict").install) == "function")'
    )
    env = os.environ.copy()
    env.pop("CDIN_RUNTIME_VERSION", None)
    subprocess.run([lua_path, "-e", expression], cwd=package_root, env=env, check=True)


def verify_archive(
    archive_path: Path,
    expected_format: str,
    root_name: str,
    metadata: dict[str, object],
    scratch: Path,
) -> Path:
    checksum_path = archive_path.with_name(archive_path.name + ".sha256")
    if not checksum_path.is_file():
        raise RuntimeError(f"checksum sidecar is missing: {checksum_path.name}")
    checksum_fields = checksum_path.read_text(encoding="utf-8").strip().split()
    if len(checksum_fields) != 2 or checksum_fields[1] != archive_path.name:
        raise RuntimeError(f"malformed checksum sidecar: {checksum_path.name}")
    digest = sha256_file(archive_path)
    if checksum_fields[0] != digest:
        raise RuntimeError(f"checksum mismatch: {archive_path.name}")

    formats = metadata.get("extensions", {}).get("org.cdin.runtime.package-formats", {})
    companion = formats.get(expected_format)
    if not isinstance(companion, dict):
        raise RuntimeError(f"release metadata is missing the {expected_format} companion descriptor")
    if companion.get("file_name") != archive_path.name:
        raise RuntimeError(f"release metadata filename mismatch for {archive_path.name}")
    if companion.get("sha256") != digest or companion.get("size_bytes") != archive_path.stat().st_size:
        raise RuntimeError(f"release metadata digest/size mismatch for {archive_path.name}")

    destination = scratch / expected_format
    destination.mkdir()
    if expected_format == "tar.gz":
        package_root = extract_tar(archive_path, destination, root_name)
    else:
        package_root = extract_zip(archive_path, destination, root_name)
    verify_package_tree(package_root, metadata)
    return package_root


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifact-dir", type=Path, default=ROOT / "dist")
    parser.add_argument("--version", default="")
    args = parser.parse_args()

    metadata_files = sorted(args.artifact_dir.glob("runtime-*.release.json"))
    if args.version:
        metadata_files = [path for path in metadata_files if path.name == f"runtime-{args.version}.release.json"]
    if len(metadata_files) != 1:
        raise RuntimeError(f"expected exactly one Runtime release metadata file, found {len(metadata_files)}")
    metadata_path = metadata_files[0]
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    version = metadata.get("version")
    if not isinstance(version, str) or metadata.get("component_id") != "runtime":
        raise RuntimeError("invalid Runtime Component Release Metadata")
    source_units = metadata.get("source_units")
    if not isinstance(source_units, list) or len(source_units) != 1:
        raise RuntimeError("expected exactly one Runtime source unit")
    revision = source_units[0].get("revision")
    if not isinstance(revision, str) or len(revision) not in (40, 64):
        raise RuntimeError("release metadata has no full source revision")

    artifacts = metadata.get("artifacts")
    if not isinstance(artifacts, list) or len(artifacts) != 1:
        raise RuntimeError("Registry metadata must expose one canonical artifact per universal target")
    canonical = artifacts[0]
    if (
        canonical.get("kind") != "runtime-module-archive"
        or canonical.get("format") != "tar.gz"
        or canonical.get("target") != {"os": "any", "architecture": "any", "abi": "none"}
        or canonical.get("layout") != "lua-module-tree-v1"
    ):
        raise RuntimeError("invalid canonical Runtime Registry artifact descriptor")

    # The ZIP is published as a convenience companion, but not advertised as a
    # second Registry match for the same target (which would be ambiguous).
    formats = metadata.get("extensions", {}).get("org.cdin.runtime.package-formats", {})
    tar_name = canonical.get("file_name")
    zip_record = formats.get("zip", {})
    zip_name = zip_record.get("file_name")
    tar_path = args.artifact_dir / str(tar_name)
    zip_path = args.artifact_dir / str(zip_name)
    if tar_path.name != tar_name or zip_path.name != zip_name:
        raise RuntimeError("unsafe Runtime artifact filename")
    if canonical.get("sha256") != sha256_file(tar_path):
        raise RuntimeError("canonical TAR artifact digest does not match Registry metadata")

    root_name = f"cdin-runtime-{version}"
    with tempfile.TemporaryDirectory(prefix="cdin-runtime-package-test-") as temporary:
        scratch = Path(temporary)
        tar_root = verify_archive(tar_path, "tar.gz", root_name, metadata, scratch)
        zip_root = verify_archive(zip_path, "zip", root_name, metadata, scratch)
        tar_files = {
            path.relative_to(tar_root).as_posix(): path.read_bytes()
            for path in tar_root.rglob("*") if path.is_file()
        }
        zip_files = {
            path.relative_to(zip_root).as_posix(): path.read_bytes()
            for path in zip_root.rglob("*") if path.is_file()
        }
        if tar_files != zip_files:
            raise RuntimeError("TAR and ZIP package contents differ")
        verify_lua_load(tar_root, version)
        verify_lua_load(zip_root, version)

    print(f"Runtime module artifacts verified: {version} ({revision})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, KeyError, TypeError, ValueError, subprocess.CalledProcessError, zipfile.BadZipFile, tarfile.TarError) as error:
        print(f"test-module-package: {error}", file=sys.stderr)
        raise SystemExit(1)
