#!/usr/bin/env bash
# Scaffold a self-contained .devcontainer/ into a project, copied from this
# repo's template/. The result depends only on Codespaces secrets — never on
# your personal dotfiles — so coauthors get the same environment.
#
# Usage (from a cloned copy of this repo):
#   bash scaffold-devcontainer.sh [TARGET_DIR]        # default: current dir
#
# Usage (anywhere, fetches the template from the public repo):
#   curl -fsSL https://raw.githubusercontent.com/njhallman/dotfiles/main/scaffold-devcontainer.sh \
#     | bash -s -- /path/to/project
#
# Set FORCE=1 to overwrite an existing .devcontainer/.
set -euo pipefail

TARGET="${1:-$PWD}"
FORCE="${FORCE:-0}"
RAW="https://raw.githubusercontent.com/njhallman/dotfiles/main/template/.devcontainer"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"

[ -d "$TARGET" ] || { echo "Target dir does not exist: $TARGET" >&2; exit 1; }
dest="$TARGET/.devcontainer"
if [ -e "$dest" ] && [ "$FORCE" != "1" ]; then
  echo "Refusing to overwrite existing $dest (set FORCE=1 to override)." >&2
  exit 1
fi
mkdir -p "$dest"

# Copy from a local template if present (cloned repo), else fetch from the repo.
fetch() {
  local name="$1"
  if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/template/.devcontainer/$name" ]; then
    cp "$SELF_DIR/template/.devcontainer/$name" "$dest/$name"
  else
    curl -fsSL "$RAW/$name" -o "$dest/$name"
  fi
}
fetch devcontainer.json
fetch setup.sh
chmod +x "$dest/setup.sh"

# Name the devcontainer after the project folder (portable; no sed -i).
proj="$(basename "$(cd "$TARGET" && pwd)")"
tmp="$(mktemp)"
sed "s/PROJECT_NAME/${proj//\//_}/" "$dest/devcontainer.json" > "$tmp" && mv "$tmp" "$dest/devcontainer.json"

cat <<EOF
Scaffolded $dest

Next steps:
  1. Commit the .devcontainer/ directory to the project repo.
  2. Set Codespaces secrets for anyone who needs Stata (their OWN license):
       STATA_SERIAL, STATA_CODE, STATA_AUTHORIZATION, STATA_NAME, STATA_AFFILIATION
     (and optionally OP_SERVICE_ACCOUNT_TOKEN for op:// secrets).
  3. Create a Codespace on the repo — setup.sh runs automatically.
EOF
