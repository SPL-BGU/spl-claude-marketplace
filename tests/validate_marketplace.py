#!/usr/bin/env python3
"""Validate the marketplace catalog and every plugin it lists.

Run locally before opening a PR:  python3 tests/validate_marketplace.py
CI runs the same script and gates merges to main on it passing.

Checks:
  - .claude-plugin/marketplace.json parses and has the required shape.
  - Each plugin's `source` directory exists.
  - Each plugin has .claude-plugin/plugin.json that parses.
  - plugin.json `name`/`version` match the catalog entry exactly.
  - Each plugin has a CLAUDE.md and at least one component (skills/ or .mcp.json).
  - Every SKILL.md has YAML frontmatter with `name:` and `description:`.
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
errors: list[str] = []


def err(msg: str) -> None:
    errors.append(msg)


def load_json(path: Path):
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        err(f"missing file: {path.relative_to(ROOT)}")
    except json.JSONDecodeError as e:
        err(f"invalid JSON in {path.relative_to(ROOT)}: {e}")
    return None


def check_skill_frontmatter(skill_md: Path) -> None:
    text = skill_md.read_text()
    rel = skill_md.relative_to(ROOT)
    if not text.startswith("---"):
        err(f"{rel}: missing YAML frontmatter (must start with '---')")
        return
    # frontmatter is everything between the first two '---' fences
    parts = text.split("---", 2)
    if len(parts) < 3:
        err(f"{rel}: unterminated YAML frontmatter")
        return
    front = parts[1]
    for field in ("name:", "description:"):
        if field not in front:
            err(f"{rel}: frontmatter missing '{field}'")


def main() -> int:
    catalog_path = ROOT / ".claude-plugin" / "marketplace.json"
    catalog = load_json(catalog_path)
    if catalog is None:
        print_report()
        return 1

    if "name" not in catalog:
        err("marketplace.json: missing top-level 'name'")
    plugins = catalog.get("plugins")
    if not isinstance(plugins, list) or not plugins:
        err("marketplace.json: 'plugins' must be a non-empty list")
        print_report()
        return 1

    for entry in plugins:
        name = entry.get("name", "<unnamed>")
        for field in ("name", "version", "source"):
            if field not in entry:
                err(f"catalog entry '{name}': missing '{field}'")
        source = entry.get("source")
        if not source:
            continue

        plugin_dir = (ROOT / source).resolve()
        if not plugin_dir.is_dir():
            err(f"catalog entry '{name}': source '{source}' is not a directory")
            continue

        manifest = load_json(plugin_dir / ".claude-plugin" / "plugin.json")
        if manifest is not None:
            if manifest.get("name") != entry.get("name"):
                err(f"'{name}': plugin.json name '{manifest.get('name')}' "
                    f"!= catalog name '{entry.get('name')}'")
            if manifest.get("version") != entry.get("version"):
                err(f"'{name}': plugin.json version '{manifest.get('version')}' "
                    f"!= catalog version '{entry.get('version')}' "
                    f"(bump both together)")

        if not (plugin_dir / "CLAUDE.md").is_file():
            err(f"'{name}': missing CLAUDE.md")

        skills_dir = plugin_dir / "skills"
        has_mcp = (plugin_dir / ".mcp.json").is_file()
        if not skills_dir.is_dir() and not has_mcp:
            err(f"'{name}': has no component (needs a skills/ dir or .mcp.json)")

        if skills_dir.is_dir():
            skill_files = list(skills_dir.rglob("SKILL.md"))
            if not skill_files:
                err(f"'{name}': skills/ exists but contains no SKILL.md")
            for skill_md in skill_files:
                check_skill_frontmatter(skill_md)

    print_report()
    return 1 if errors else 0


def print_report() -> None:
    if errors:
        print(f"FAILED — {len(errors)} problem(s):")
        for e in errors:
            print(f"  - {e}")
    else:
        print("OK — marketplace catalog and all plugins validate.")


if __name__ == "__main__":
    sys.exit(main())
