#!/usr/bin/env python3

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SKILLS_ROOT = ROOT / ".agents" / "skills"
SKILL_ROUTING = ROOT / ".agents" / "docs" / "skill-routing.md"

MAKE_TARGET_RE = re.compile(r"^([A-Za-z0-9_.-]+):", re.MULTILINE)
MARKDOWN_LINK_RE = re.compile(r"\[[^\]]+\]\(([^)]+)\)")
INLINE_PATH_RE = re.compile(
    r"`((?:\.\.?/|references/|assets/|\.agents/|scripts/|App/|Packages/|Config/|\.github/|AGENTS\.md|README\.md|Makefile)[^`\s]*)`"
)
INLINE_MAKE_RE = re.compile(r"`make\s+([A-Za-z0-9_.-]+)`")
FENCED_CODE_BLOCK_RE = re.compile(r"```[^\n]*\n(.*?)```", re.DOTALL)
TOP_LEVEL_HEADING_RE = re.compile(r"^##\s+(.+)$", re.MULTILINE)
KNOWN_PATH_SUFFIXES = (
    ".md",
    ".sh",
    ".py",
    ".swift",
    ".xcodeproj",
    ".xcworkspace",
    ".strings",
    "/",
)
REQUIRED_SKILL_SECTIONS = ("Role", "When to Use")
SCOPE_SECTION_NAMES = ("Scope Boundary", "Scope Boundaries")
ALLOWED_SKILL_CHILDREN = {"SKILL.md", "references", "scripts", "assets"}
PLACEHOLDER_PATTERNS = {
    "AppName.xcodeproj": "generic Xcode placeholder",
    "npm test": "non-Verbi test command placeholder",
    "Chrome DevTools": "web-specific debugging guidance",
    "console.log": "web-specific logging guidance",
    "VS Code": "editor-specific generic guidance",
}


def markdown_files() -> list[Path]:
    return [
        ROOT / "AGENTS.md",
        *sorted((ROOT / ".agents" / "docs").rglob("*.md")),
        *sorted(SKILLS_ROOT.rglob("*.md")),
    ]


def parse_make_targets(makefile_path: Path) -> set[str]:
    text = makefile_path.read_text(encoding="utf-8")
    targets: set[str] = set()

    for match in MAKE_TARGET_RE.finditer(text):
        target = match.group(1)
        if target.startswith("."):
            continue
        targets.add(target)

    return targets


def clean_local_reference(reference: str) -> str | None:
    clean_reference = reference.split("#", 1)[0].strip()
    if not clean_reference:
        return None
    if clean_reference.startswith(("http://", "https://", "mailto:", "file://")):
        return None
    if any(token in clean_reference for token in ("*", "{", "}", "...")):
        return None

    return clean_reference.replace("%20", " ")


def resolve_markdown_path(source_file: Path, reference: str) -> Path | None:
    clean_reference = clean_local_reference(reference)
    if clean_reference is None:
        return None

    return (source_file.parent / clean_reference).resolve()


def resolve_inline_path(source_file: Path, reference: str) -> Path | None:
    clean_reference = clean_local_reference(reference)
    if clean_reference is None:
        return None

    if clean_reference.startswith(("./", "../", "references/", "assets/")):
        source_relative = (source_file.parent / clean_reference).resolve()
        if source_relative.exists():
            return source_relative

    return (ROOT / clean_reference).resolve()


def extract_make_targets(text: str) -> set[str]:
    targets = {match.group(1) for match in INLINE_MAKE_RE.finditer(text)}

    for block in FENCED_CODE_BLOCK_RE.findall(text):
        for line in block.splitlines():
            stripped = line.strip()
            if not stripped.startswith("make "):
                continue
            target = stripped.split()[1]
            if re.fullmatch(r"[A-Za-z0-9_.-]+", target):
                targets.add(target)

    return targets


def looks_like_local_reference(reference: str) -> bool:
    return "/" in reference or reference.endswith(KNOWN_PATH_SUFFIXES)


def validate_make_references(markdown_file: Path, text: str, known_targets: set[str]) -> list[str]:
    errors: list[str] = []
    for target in sorted(extract_make_targets(text)):
        if target not in known_targets:
            errors.append(f"Unknown make target '{target}' in {markdown_file.relative_to(ROOT)}")
    return errors


def validate_path_references(markdown_file: Path, text: str) -> list[str]:
    errors: list[str] = []
    text_without_code_blocks = FENCED_CODE_BLOCK_RE.sub("", text)

    reference_groups = (
        (
            {match.group(1) for match in MARKDOWN_LINK_RE.finditer(text_without_code_blocks)},
            resolve_markdown_path,
        ),
        (
            {match.group(1) for match in INLINE_PATH_RE.finditer(text_without_code_blocks)},
            resolve_inline_path,
        ),
    )

    for references, resolver in reference_groups:
        for reference in sorted(references):
            if not looks_like_local_reference(reference):
                continue

            local_path = resolver(markdown_file, reference)
            if local_path is None:
                continue
            if not local_path.exists():
                errors.append(
                    f"Missing local reference '{reference}' in {markdown_file.relative_to(ROOT)}"
                )

    return errors


def parse_routed_skills(routing_path: Path) -> set[str]:
    text = routing_path.read_text(encoding="utf-8")
    return set(
        match.group(1)
        for match in re.finditer(r"`([a-z0-9-]+)`", text)
        if match.group(1) not in {"macos", "main"}
    )


def validate_skill_routing() -> list[str]:
    errors: list[str] = []
    skill_dirs = sorted(
        path.name
        for path in SKILLS_ROOT.iterdir()
        if path.is_dir() and (path / "SKILL.md").exists()
    )
    routed = parse_routed_skills(SKILL_ROUTING)

    for skill in skill_dirs:
        if skill not in routed:
            errors.append(
                f"Skill '{skill}' exists in .agents/skills but is missing from .agents/docs/skill-routing.md"
            )

    return errors


def validate_skill_structure(skill_file: Path, text: str) -> list[str]:
    errors: list[str] = []
    rel = skill_file.relative_to(ROOT)
    headings = TOP_LEVEL_HEADING_RE.findall(text)
    heading_set = set(headings)

    for section in REQUIRED_SKILL_SECTIONS:
        if section not in heading_set:
            errors.append(f"Missing required section '{section}' in {rel}")

    if not any(scope in heading_set for scope in SCOPE_SECTION_NAMES):
        errors.append(f"Missing required scope section in {rel}")

    duplicates = sorted({heading for heading in headings if headings.count(heading) > 1})
    for heading in duplicates:
        errors.append(f"Duplicate section heading '{heading}' in {rel}")

    return errors


def validate_skill_directory(skill_dir: Path) -> list[str]:
    errors: list[str] = []
    rel = skill_dir.relative_to(ROOT)

    for child in sorted(skill_dir.iterdir(), key=lambda path: path.name):
        if child.name.startswith("."):
            errors.append(f"Hidden file or directory '{child.name}' is not allowed in {rel}")
            continue
        if child.name not in ALLOWED_SKILL_CHILDREN:
            errors.append(f"Unexpected file or directory '{child.name}' in {rel}")

    return errors


def has_non_hidden_content(skill_dir: Path) -> bool:
    for descendant in skill_dir.rglob("*"):
        relative = descendant.relative_to(skill_dir)
        if any(part.startswith(".") for part in relative.parts):
            continue
        return True
    return False


def validate_placeholders(markdown_file: Path, text: str) -> list[str]:
    errors: list[str] = []
    rel = markdown_file.relative_to(ROOT)
    for needle, reason in PLACEHOLDER_PATTERNS.items():
        if needle in text:
            errors.append(f"Disallowed placeholder '{needle}' ({reason}) in {rel}")
    return errors


def main() -> int:
    known_targets = parse_make_targets(ROOT / "Makefile")
    errors: list[str] = []
    errors.extend(validate_skill_routing())

    for markdown_file in markdown_files():
        text = markdown_file.read_text(encoding="utf-8")
        errors.extend(validate_make_references(markdown_file, text, known_targets))
        errors.extend(validate_path_references(markdown_file, text))
        if markdown_file.name == "SKILL.md" and markdown_file.parent.parent == SKILLS_ROOT:
            errors.extend(validate_skill_structure(markdown_file, text))
            errors.extend(validate_placeholders(markdown_file, text))

    for skill_dir in sorted(path for path in SKILLS_ROOT.iterdir() if path.is_dir()):
        if (skill_dir / "SKILL.md").exists():
            errors.extend(validate_skill_directory(skill_dir))
        elif has_non_hidden_content(skill_dir):
            errors.append(
                f"Skill directory '{skill_dir.name}' contains content but has no SKILL.md"
            )

    if errors:
        for error in sorted(set(errors)):
            print(f"error: {error}")
        return 1

    print("Guidance validation passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
