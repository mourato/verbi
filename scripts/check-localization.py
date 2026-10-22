#!/usr/bin/env python3

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path


SUPPORTED_LOCALES = ("en", "pt")
LOCALIZATION_KEY_RE = re.compile(r'^"([^"]+)"', re.MULTILINE)
LITERAL_LOCALIZED_KEY_RE = re.compile(r'"([A-Za-z0-9_.-]+)"\.localized(?:\(|\b)')


def localization_keys(root: Path, locale: str) -> set[str]:
    path = root / "Packages/VerbiCore/Sources/Common/Resources" / f"{locale}.lproj/Localizable.strings"
    try:
        contents = path.read_text(encoding="utf-8")
    except FileNotFoundError as error:
        raise ValueError(f"missing localization file: {path}") from error
    except UnicodeDecodeError as error:
        raise ValueError(f"localization file is not UTF-8: {path}") from error
    return {match.group(1) for match in LOCALIZATION_KEY_RE.finditer(contents)}


def swift_files(root: Path):
    scan_roots = (root / "App", root / "Packages/VerbiCore/Sources")
    for scan_root in scan_roots:
        if not scan_root.is_dir():
            raise ValueError(f"missing localization source root: {scan_root}")
        yield from swift_files_under(scan_root)


def swift_files_under(scan_root: Path):
    for directory, directory_names, file_names in os.walk(scan_root):
        directory_names[:] = sorted(name for name in directory_names if not name.startswith("."))
        for name in sorted(file_names):
            if name.startswith(".") or not name.endswith(".swift"):
                continue
            path = Path(directory) / name
            if path.is_file():
                yield path


def literal_localized_keys(root: Path) -> set[str]:
    keys: set[str] = set()
    for path in swift_files(root):
        try:
            contents = path.read_text(encoding="utf-8")
        except UnicodeDecodeError as error:
            raise ValueError(f"Swift source is not UTF-8: {path}") from error
        keys.update(match.group(1) for match in LITERAL_LOCALIZED_KEY_RE.finditer(contents))
    return keys


def check(root: Path) -> int:
    try:
        locale_keys = {locale: localization_keys(root, locale) for locale in SUPPORTED_LOCALES}
        used_keys = literal_localized_keys(root)
    except ValueError as error:
        print("LOCALIZATION_CHECK_STATUS=FAIL")
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    errors: list[str] = []
    en_keys = locale_keys["en"]
    pt_keys = locale_keys["pt"]
    missing_from_en = sorted(pt_keys - en_keys)
    missing_from_pt = sorted(en_keys - pt_keys)
    missing_from_locales = sorted(used_keys - en_keys)

    resource_root = root / "Packages/VerbiCore/Sources/Common/Resources"
    if missing_from_en:
        errors.append(
            f"Missing from en ({resource_root / 'en.lproj/Localizable.strings'}): {', '.join(missing_from_en)}"
        )
    if missing_from_pt:
        errors.append(
            f"Missing from pt ({resource_root / 'pt.lproj/Localizable.strings'}): {', '.join(missing_from_pt)}"
        )
    if missing_from_locales:
        errors.append(
            "Literal keys missing from locales "
            f"(Swift sources under {root / 'App'} and {root / 'Packages/VerbiCore/Sources'}): "
            f"{', '.join(missing_from_locales)}"
        )

    if errors:
        print("LOCALIZATION_CHECK_STATUS=FAIL")
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print(f"LOCALIZATION_CHECK_STATUS=PASS locales={len(SUPPORTED_LOCALES)} literal_keys={len(used_keys)}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Check en/pt locale symmetry and literal .localized key registration without running XCTest."
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="Project root to inspect (default: repository root).",
    )
    args = parser.parse_args()
    return check(args.root.resolve())


if __name__ == "__main__":
    raise SystemExit(main())
