#!/usr/bin/env bash
# install_marketplace.sh — Install the SPL marketplace skills for Google Antigravity.
#
# In Claude Code, use /plugin instead (see README). This script is for Antigravity:
# it symlinks each skill into ~/.gemini/antigravity/skills/ so the same /commands are
# available there. These plugins are skills-only (no MCP servers), so there is nothing
# else to configure.
#
# Auto-discovers skills by scanning plugins/*/skills/*/ (any dir with a SKILL.md).
#
# Usage:
#   bash install_marketplace.sh            # print the symlink commands (no changes)
#   bash install_marketplace.sh --install  # symlink skills into Antigravity (with confirmation)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_DIR="$REPO_ROOT/plugins"

ANTIGRAVITY_SKILLS="$HOME/.gemini/antigravity/skills"

# ── Discover skills ──────────────────────────────────────────────────────────
# Each skill is a directory plugins/<plugin>/skills/<skill>/ holding a SKILL.md.
# Prints one absolute skill-dir path (no trailing slash) per line.

collect_skills() {
    for plugin_dir in "$PLUGINS_DIR"/*/; do
        local skills_dir="${plugin_dir}skills"
        [ -d "$skills_dir" ] || continue
        for skill_dir in "$skills_dir"/*/; do
            if [ -f "${skill_dir}SKILL.md" ]; then
                echo "${skill_dir%/}"
            fi
        done
    done
}

if [ -z "$(collect_skills)" ]; then
    echo "No skills found under $PLUGINS_DIR/*/skills/ (expected dirs containing SKILL.md)." >&2
    exit 1
fi

# ── Print symlink commands ───────────────────────────────────────────────────

print_symlink_commands() {
    while IFS= read -r skill_dir; do
        echo "  ln -sfn \"$skill_dir\" \"$ANTIGRAVITY_SKILLS/$(basename "$skill_dir")\""
    done < <(collect_skills)
}

# ── Install ──────────────────────────────────────────────────────────────────

install_configs() {
    if [ ! -d "$HOME/.gemini" ]; then
        echo "Antigravity not detected (~/.gemini/ is missing)."
        echo "Open Antigravity once to create it, then re-run — or run without --install"
        echo "to print the symlink commands and run them manually."
        exit 0
    fi

    echo "This will symlink the marketplace skills into:"
    echo "  $ANTIGRAVITY_SKILLS/"
    echo ""
    read -r -p "Proceed? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        echo "Aborted."
        exit 0
    fi

    echo ""
    mkdir -p "$ANTIGRAVITY_SKILLS"
    while IFS= read -r skill_dir; do
        local name
        name=$(basename "$skill_dir")
        ln -sfn "$skill_dir" "$ANTIGRAVITY_SKILLS/$name"
        echo "  Linked $ANTIGRAVITY_SKILLS/$name -> $skill_dir"
    done < <(collect_skills)

    echo ""
    echo "Done. Restart Antigravity to pick up the new skills."
}

# ── Parse arguments ──────────────────────────────────────────────────────────

INSTALL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install)
            INSTALL=true
            shift
            ;;
        --help|-h)
            echo "Usage: bash install_marketplace.sh [--install]"
            echo ""
            echo "  --install  Symlink skills into ~/.gemini/antigravity/skills/"
            echo "  --help     Show this help"
            echo ""
            echo "With no flag, prints the symlink commands without changing anything."
            echo "In Claude Code, install via /plugin instead — this script is for Antigravity."
            echo ""
            echo "Discovered skills:"
            while IFS= read -r skill_dir; do
                echo "  - $(basename "$skill_dir")"
            done < <(collect_skills)
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Run with --help for usage." >&2
            exit 1
            ;;
    esac
done

# ── Main ─────────────────────────────────────────────────────────────────────

echo "SPL Claude Marketplace — Antigravity skill install"
echo "Skills discovered: $(collect_skills | xargs -n1 basename | paste -sd' ' -)"
echo ""

if [ "$INSTALL" = true ]; then
    install_configs
    exit 0
fi

echo "Symlink skills into $ANTIGRAVITY_SKILLS/ :"
echo ""
print_symlink_commands
echo ""
echo "Run the commands above, or re-run with --install to apply them automatically."
