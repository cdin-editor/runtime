#!/usr/bin/env python3
"""Static checks for the extracted Runtime scaffold; requires Python 3.10+."""
from __future__ import annotations
import hashlib, json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
issues: list[str] = []

def check(condition: bool, message: str) -> None:
    if not condition: issues.append(message)

def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()

# Source manifest proves which existing source files were copied verbatim.
manifest_path = ROOT / 'SOURCE-MANIFEST.json'
try:
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    entries = manifest['files']
    for item in entries:
        target = ROOT / item['target_path']
        check(target.is_file(), f"missing copied source: {item['target_path']}")
        if target.is_file():
            check(sha(target) == item['sha256'], f"copied source changed from snapshot: {item['target_path']}")
except Exception as exc:
    issues.append(f"invalid SOURCE-MANIFEST.json: {exc}")
    entries = []

# Require graph: every literal core.* import must resolve to data/core/module.lua or init.lua.
require_pattern = re.compile(r"require\s*\(?\s*[\"'](core(?:\.[A-Za-z0-9_]+)+)[\"']\s*\)?")
lua_files = sorted((ROOT / 'data/core').rglob('*.lua'))
missing = set()
for file in lua_files:
    content = file.read_text(encoding='utf-8', errors='replace')
    for module in require_pattern.findall(content):
        rel = Path(*module.split('.'))
        if not ((ROOT / 'data' / rel).with_suffix('.lua').is_file() or (ROOT / 'data' / rel / 'init.lua').is_file()):
            missing.add((file.relative_to(ROOT).as_posix(), module))
for source, module in sorted(missing):
    issues.append(f"unresolved literal import in {source}: {module}")

# Runtime repo must not silently become Backend/Kernel/GUI implementation.
check(not (ROOT / 'src').exists(), 'native src/ directory copied into Runtime; keep C Host/Frontend in CDIN')
check(not (ROOT / 'build').exists(), 'build/ artifacts must not be included')
check(not (ROOT / 'include').exists(), 'public/native include/ must not be added as a Runtime build dependency')
check((ROOT / 'references/kernel/include/cdin/kernel.h').is_file(), 'reference-only Kernel header missing')
check(not any(p.suffix in {'.o','.obj','.a','.so','.dll','.dylib','.exe'} for p in ROOT.rglob('*') if p.is_file()), 'compiled artifact included')

# Required current and proposed architecture documents.
required = [
  'data/core/runtime/strict.lua', 'data/core/runtime/contracts.lua',
  'data/core/runtime/errors.lua', 'data/core/runtime/registry.lua',
  'data/core/runtime/host.lua', 'data/core/runtime/types.lua',
  'docs/architecture.md', 'docs/source-map.md', 'docs/migration-status.md',
  'docs/runtime-host-api.md', 'docs/types-and-ownership.md', 'docs/testing.md',
  'tests/unit/run.lua', 'references/spec/docs/components/runtime.md',
  'references/spec/docs/architecture/migration.md', 'references/kernel/docs/abi.md',
]
for name in required: check((ROOT / name).is_file(), f"required file missing: {name}")

# Guard against accidental direct Kernel implementation dependency in new adapter utilities.
for name in ['host.lua', 'contracts.lua', 'errors.lua', 'registry.lua']:
    file = ROOT / 'data/core/runtime' / name
    if file.exists():
        content = file.read_text(encoding='utf-8', errors='replace')
        check('cdin_kernel_create' not in content and 'cdin/kernel.h' not in content,
              f"{name} references native Kernel implementation directly")

# Make the transitional exception visible rather than silently claiming conformance.
doc_init = (ROOT / 'data/core/doc/init.lua').read_text(encoding='utf-8', errors='replace')
open_items = (ROOT / 'docs/migration-status.md').read_text(encoding='utf-8')
check('self.lines' in doc_init and 'undo_stack' in doc_init,
      'expected legacy document module changed; review migration assumptions')
check('Document ownership' in open_items and 'RT-003/RT-004' in open_items,
      'legacy document ownership exception is not documented')

# Check relative Markdown links inside source docs and reference snapshots.
md_roots = [ROOT / 'docs', ROOT / 'references/spec/docs', ROOT / 'references/spec', ROOT / 'references/kernel/docs', ROOT / 'references/kernel']
link_pattern = re.compile(r'(?<!!)\[[^\]]*\]\(([^)]+)\)')
seen = set()
for mdroot in md_roots:
    if not mdroot.exists(): continue
    for file in mdroot.rglob('*.md'):
        if file in seen: continue
        seen.add(file)
        content = file.read_text(encoding='utf-8', errors='replace')
        for raw in link_pattern.findall(content):
            url = raw.strip().split()[0].strip('<>')
            if not url or url.startswith(('http://','https://','mailto:','tel:','#','data:')): continue
            pathpart = url.split('#',1)[0].split('?',1)[0]
            if not pathpart: continue
            target = (file.parent / pathpart).resolve()
            if target.exists(): continue
            # CDIN architecture docs intentionally link to native Backend/GUI files that are excluded from Runtime.
            normalized = pathpart.replace('\\\\', '/')
            if normalized.endswith(('.c', '.h', '.cpp', '.cc')) or normalized.rstrip('/').endswith('/src') or normalized == '../../src':
                continue
            check(False, f"broken relative Markdown link: {file.relative_to(ROOT).as_posix()} -> {url}")

if issues:
    print(f"Runtime structure checks FAILED ({len(issues)} issue(s))", file=sys.stderr)
    for issue in issues: print(f" - {issue}", file=sys.stderr)
    sys.exit(1)
print(f"Runtime structure checks: PASS ({len(entries)} copied-source hashes, {len(lua_files)} Lua core files checked)")
