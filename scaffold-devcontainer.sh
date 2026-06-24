#!/usr/bin/env bash
# Scaffold the universal devcontainer into a project — a CLI alternative to
# pasting devcontainer.json via the GitHub "Configure dev container" UI.
# Drops a single .devcontainer/devcontainer.json whose postCreateCommand fetches
# and runs project-setup.sh (LaTeX + Python + op + Stata) from njhallman/dotfiles.
#
# Usage (from a clone):  bash scaffold-devcontainer.sh [TARGET_DIR]
# Usage (anywhere):      curl -fsSL https://raw.githubusercontent.com/njhallman/dotfiles/main/scaffold-devcontainer.sh | bash -s -- /path/to/project
# Set FORCE=1 to overwrite an existing file.
set -euo pipefail
TARGET="${1:-$PWD}"
FORCE="${FORCE:-0}"
RAW="https://raw.githubusercontent.com/njhallman/dotfiles/main/template/.devcontainer/devcontainer.json"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"
[ -d "$TARGET" ] || { echo "Target dir does not exist: $TARGET" >&2; exit 1; }
dest="$TARGET/.devcontainer"
out="$dest/devcontainer.json"
mkdir -p "$dest"
if [ -e "$out" ] && [ "$FORCE" != "1" ]; then
  echo "Refusing to overwrite existing $out (set FORCE=1 to override)." >&2; exit 1
fi
if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/template/.devcontainer/devcontainer.json" ]; then
  cp "$SELF_DIR/template/.devcontainer/devcontainer.json" "$out"
else
  curl -fsSL "$RAW" -o "$out"
fi
proj="$(basename "$(cd "$TARGET" && pwd)")"
tmp="$(mktemp)"; sed "s/PROJECT_NAME/${proj//\//_}/" "$out" > "$tmp" && mv "$tmp" "$out"
cat <<EOF
Scaffolded $out

Next steps:
  1. Commit .devcontainer/devcontainer.json to the project repo.
  2. Set Codespaces secrets if you use Stata: STATA_SERIAL, STATA_CODE,
     STATA_AUTHORIZATION, STATA_NAME, STATA_AFFILIATION (optionally
     OP_SERVICE_ACCOUNT_TOKEN).
  3. Create a Codespace — project-setup.sh runs automatically.
EOF
