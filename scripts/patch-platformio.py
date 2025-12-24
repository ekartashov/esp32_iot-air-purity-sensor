#!/usr/bin/env python3
"""
PlatformIO IDE (VSCodium / vscode-oss) extension patcher.

What it does (same as your bash script):
- Finds the first directory matching:
    ~/.vscode-oss/extensions/platformio.platformio-ide-*
- Backs up package.json -> package.json.bak
- Moves "extensionDependencies" entries into "extensionPack" (deduped)
- Writes patched package.json with pretty JSON formatting
"""

from __future__ import annotations

import json
import shutil
from pathlib import Path


def find_platformio_ext_dir(base: Path) -> Path:
    matches = sorted(base.glob("platformio.platformio-ide-*"))
    if not matches:
        raise FileNotFoundError(
            f"No PlatformIO extension dir found under: {base}\n"
            f"Expected something like: {base}/platformio.platformio-ide-*"
        )
    return matches[0]  # mimic `ls ... | head -n1` (first in sorted order)


def patch_package_json(pkg_path: Path) -> bool:
    data = json.loads(pkg_path.read_text(encoding="utf-8"))

    deps = data.pop("extensionDependencies", None)
    if not deps:
        # Nothing to do
        return False

    pack = data.setdefault("extensionPack", [])
    if not isinstance(pack, list):
        raise TypeError(f'"extensionPack" is not a list in {pkg_path}')

    for d in deps:
        if d not in pack:
            pack.append(d)

    pkg_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    return True


def main() -> int:
    ext_base = Path.home() / ".vscode-oss" / "extensions"
    pio_dir = find_platformio_ext_dir(ext_base)

    pkg = pio_dir / "package.json"
    if not pkg.is_file():
        raise FileNotFoundError(f"package.json not found at: {pkg}")

    # Backup (like `cp -a package.json package.json.bak`)
    bak = pio_dir / "package.json.bak"
    shutil.copy2(pkg, bak)

    changed = patch_package_json(pkg)
    print(f"Patched: {pkg}" if changed else f"No changes needed: {pkg}")
    print(f"Backup:  {bak}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
