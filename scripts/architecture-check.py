#!/usr/bin/env python3
"""Lightweight architecture checks for MeetingAssistantCore.

This script performs a fast static scan to prevent accidental layering violations.
It validates that Swift source files only `import` internal targets that are
declared as dependencies in `Packages/MeetingAssistantCore/Package.swift`.

Notes:
- DocC example sources are ignored (`.docc/**`) since they are not compiled.
- This is intentionally conservative and does not attempt to parse Swift fully.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Sequence, Set, Tuple


IMPORT_RE = re.compile(r"^\s*(?:@[_A-Za-z0-9]+\s+)*import\s+(?P<module>[A-Za-z_][A-Za-z0-9_]*)\b")


@dataclass(frozen=True)
class Violation:
    file: Path
    line: int
    importer_target: str
    imported_module: str
    message: str


def repo_root_from_script(script_path: Path) -> Path:
    return script_path.resolve().parent.parent


def dump_package(package_dir: Path) -> dict:
    result = subprocess.run(
        ["swift", "package", "dump-package"],
        cwd=str(package_dir),
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        sys.stderr.write("error: failed to run `swift package dump-package`\n")
        sys.stderr.write(result.stdout)
        sys.stderr.write(result.stderr)
        raise SystemExit(result.returncode)
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        sys.stderr.write("error: failed to parse dump-package JSON output\n")
        raise SystemExit(2) from exc


def internal_targets(package_json: dict) -> Set[str]:
    targets: Set[str] = set()
    for t in package_json.get("targets", []):
        name = t.get("name")
        if isinstance(name, str) and name.startswith("MeetingAssistantCore") and not name.endswith("Tests"):
            targets.add(name)
    return targets


def dependency_map(package_json: dict, internal: Set[str]) -> Dict[str, Set[str]]:
    mapping: Dict[str, Set[str]] = {}
    for t in package_json.get("targets", []):
        name = t.get("name")
        if not isinstance(name, str) or name not in internal:
            continue

        deps: Set[str] = set()
        for dep in t.get("dependencies", []):
            # `swift package dump-package` emits multiple dependency shapes.
            #
            # Target dependencies are usually:
            #   {"byName": ["MeetingAssistantCoreCommon", null]}
            # Product dependencies are usually:
            #   {"product": ["ExternalProduct", "external-package", null, null]}
            if "byName" in dep and isinstance(dep.get("byName"), list) and dep["byName"]:
                dep_name = dep["byName"][0]
                if isinstance(dep_name, str) and dep_name in internal:
                    deps.add(dep_name)
                continue

            if "target" in dep and isinstance(dep.get("target"), list) and dep["target"]:
                dep_name = dep["target"][0]
                if isinstance(dep_name, str) and dep_name in internal:
                    deps.add(dep_name)
                continue
        mapping[name] = deps
    return mapping


def target_path_map(package_json: dict, internal: Set[str], package_dir: Path) -> Dict[str, Path]:
    mapping: Dict[str, Path] = {}
    for target in package_json.get("targets", []):
        name = target.get("name")
        if not isinstance(name, str) or name not in internal:
            continue

        configured_path = target.get("path")
        if isinstance(configured_path, str) and configured_path:
            mapping[name] = package_dir / configured_path
        else:
            mapping[name] = package_dir / "Sources" / name
    return mapping


def swift_files_for_target(target_root: Path) -> List[Path]:
    if not target_root.exists():
        return []

    results: List[Path] = []
    for path in target_root.rglob("*.swift"):
        if ".docc" in path.parts:
            continue
        if "Resources" in path.parts:
            continue
        results.append(path)
    return results


def extract_imports(lines: Sequence[str]) -> List[Tuple[int, str]]:
    imports: List[Tuple[int, str]] = []
    for i, line in enumerate(lines, start=1):
        striped = line.strip()
        if not striped:
            continue
        if striped.startswith("//") or striped.startswith("/*") or striped.startswith("*"):
            continue
        m = IMPORT_RE.match(line)
        if not m:
            continue
        imports.append((i, m.group("module")))
    return imports


def validate_imports(
    target: str,
    files: Iterable[Path],
    internal: Set[str],
    allowed_internal_imports: Set[str],
    repo_root: Path,
) -> List[Violation]:
    violations: List[Violation] = []
    for f in files:
        try:
            content = f.read_text(encoding="utf-8")
        except OSError:
            continue

        for line_no, imported in extract_imports(content.splitlines()):
            if imported not in internal:
                continue

            if target != "MeetingAssistantCore" and imported == "MeetingAssistantCore":
                violations.append(
                    Violation(
                        file=f,
                        line=line_no,
                        importer_target=target,
                        imported_module=imported,
                        message="Do not import the compatibility export layer from internal modules.",
                    )
                )
                continue

            if imported not in allowed_internal_imports:
                allowed_sorted = ", ".join(sorted(allowed_internal_imports))
                violations.append(
                    Violation(
                        file=f,
                        line=line_no,
                        importer_target=target,
                        imported_module=imported,
                        message=f"Import is not declared as a target dependency. Allowed internal imports: {allowed_sorted}",
                    )
                )

    # De-duplicate violations deterministically
    unique: Dict[Tuple[str, int, str, str], Violation] = {}
    for v in violations:
        key = (str(v.file), v.line, v.importer_target, v.imported_module)
        unique[key] = v
    return [unique[k] for k in sorted(unique.keys())]


def main() -> int:
    script_path = Path(__file__)
    repo_root = repo_root_from_script(script_path)
    package_dir = repo_root / "Packages" / "MeetingAssistantCore"

    if not package_dir.exists():
        sys.stderr.write(f"error: package directory not found: {package_dir}\n")
        return 2

    package_json = dump_package(package_dir=package_dir)
    internal = internal_targets(package_json)
    deps = dependency_map(package_json, internal=internal)
    target_paths = target_path_map(package_json, internal=internal, package_dir=package_dir)

    violations: List[Violation] = []
    for target, target_deps in deps.items():
        allowed_internal = set(target_deps) | {target}
        target_files = swift_files_for_target(target_root=target_paths[target])
        violations.extend(
            validate_imports(
                target=target,
                files=target_files,
                internal=internal,
                allowed_internal_imports=allowed_internal,
                repo_root=repo_root,
            )
        )

    if not violations:
        print("✓ Architecture checks passed (internal imports match Package.swift dependencies).")
        return 0

    print("✗ Architecture checks failed.")
    for v in violations:
        rel = v.file.relative_to(repo_root) if v.file.is_absolute() else v.file
        print(f"- {rel}:{v.line}: {v.importer_target} imports {v.imported_module}: {v.message}")
    print(f"\nTotal violations: {len(violations)}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
