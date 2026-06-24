#!/usr/bin/env bash
# Universal Codespaces project setup, maintained in njhallman/dotfiles.
# A project's .devcontainer/devcontainer.json fetches and runs this on create:
#   "postCreateCommand": "curl -fsSL .../project-setup.sh | bash"
# Edit this one file and every project picks it up on its next Codespace rebuild.
#
# Installs: build tools, LaTeX (TeX Live + latexmk + biber), a Python venv
# (+ requirements.txt if present), the 1Password CLI, and Stata.
#
# NO credentials live in any repo. Stata's license and any op token come from
# Codespaces secrets (github.com/settings/codespaces -> Secrets):
#   STATA_SERIAL, STATA_CODE, STATA_AUTHORIZATION, STATA_NAME, STATA_AFFILIATION
#   OP_SERVICE_ACCOUNT_TOKEN  (optional, for op:// secrets)
# Override the installer with STATA_INSTALLER_URL; skip Stata with DOTFILES_SKIP_STATA=1.
set -euo pipefail

echo "==> setup: system packages + LaTeX (TeX Live is large — a few minutes on first build)"
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  build-essential python3-dev python3-venv git-lfs unzip curl \
  texlive-latex-recommended texlive-latex-extra texlive-fonts-recommended \
  texlive-bibtex-extra latexmk biber chktex >/dev/null
git lfs install >/dev/null 2>&1 || true

echo "==> setup: Python virtual environment (.venv)"
python3 -m venv .venv
.venv/bin/python -m pip install --upgrade pip setuptools wheel >/dev/null
if [ -f requirements.txt ]; then
  .venv/bin/python -m pip install --no-cache-dir -r requirements.txt
else
  echo "    (no requirements.txt — created an empty .venv)"
fi

echo "==> setup: 1Password CLI (op)"
if ! command -v op >/dev/null 2>&1; then
  ARCH="$(dpkg --print-architecture)"; OP_VERSION="2.34.0"
  curl -sSf "https://cache.agilebits.com/dist/1P/op2/pkg/v${OP_VERSION}/op_linux_${ARCH}_v${OP_VERSION}.zip" -o /tmp/op.zip
  unzip -o /tmp/op.zip op -d /tmp/op-bin >/dev/null
  sudo install -m 0755 /tmp/op-bin/op /usr/local/bin/op
  rm -rf /tmp/op.zip /tmp/op-bin
fi
op --version || true

echo "==> setup: Stata"
STATA_DIR=/usr/local/stata
STATA_INSTALLER_URL="${STATA_INSTALLER_URL:-https://pub-7fea5c052fbe4dfa88bf8892e457c684.r2.dev/StataNow18Linux64.tar}"

# License: env vars take precedence (coauthors set their own STATA_* Codespaces
# secrets); otherwise read it from 1Password (op://AI-Agents/stata-license) via the
# OP_SERVICE_ACCOUNT_TOKEN secret — so you only scope that ONE secret per repo.
ST_SERIAL="${STATA_SERIAL:-}"; ST_CODE="${STATA_CODE:-}"; ST_AUTH="${STATA_AUTHORIZATION:-}"
ST_NAME="${STATA_NAME:-}"; ST_AFFIL="${STATA_AFFILIATION:-}"
if [ -z "$ST_SERIAL" ] && command -v op >/dev/null 2>&1 && [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ] && ST_SERIAL=$(op read "op://AI-Agents/stata-license/serial" 2>/dev/null); then
  ST_CODE=$(op read "op://AI-Agents/stata-license/code")
  ST_AUTH=$(op read "op://AI-Agents/stata-license/authorization")
  ST_NAME=$(op read "op://AI-Agents/stata-license/name")
  ST_AFFIL=$(op read "op://AI-Agents/stata-license/affiliation")
fi
if [ -n "${DOTFILES_SKIP_STATA:-}" ]; then
  echo "    (skipped: DOTFILES_SKIP_STATA set)"
elif [ -x "$STATA_DIR/stata-se" ]; then
  echo "    (skipped: already installed at $STATA_DIR)"
elif [ "$(dpkg --print-architecture)" != "amd64" ]; then
  echo "    (skipped: StataNow18Linux64 is x86_64-only; host is $(dpkg --print-architecture))"
elif [ -z "$ST_SERIAL" ]; then
  echo "    (skipped: no license — set STATA_* Codespaces secrets, or scope OP_SERVICE_ACCOUNT_TOKEN to this repo so the license resolves from 1Password)"
else
  TARDIR="$(mktemp -d)"
  echo "    downloading StataNow18Linux64.tar (~730MB)..."
  curl -fSL --retry 3 "$STATA_INSTALLER_URL" -o "$TARDIR/stata.tar"
  LIBDIR=/usr/lib/x86_64-linux-gnu
  [ -e "$LIBDIR/libncursesw.so.6" ] && [ ! -e "$LIBDIR/libncurses.so.5" ] \
    && sudo ln -s "$LIBDIR/libncursesw.so.6" "$LIBDIR/libncurses.so.5"
  [ -e "$LIBDIR/libtinfo.so.6" ] && [ ! -e "$LIBDIR/libtinfo.so.5" ] \
    && sudo ln -s "$LIBDIR/libtinfo.so.6" "$LIBDIR/libtinfo.so.5"
  sudo mkdir -p "$STATA_DIR"
  sudo tar xf "$TARDIR/stata.tar" -C "$STATA_DIR"
  sudo chmod 755 "$STATA_DIR/install"
  ( cd "$STATA_DIR" && printf 'y\ny\ny\n' | sudo bash ./install ) >/dev/null 2>&1 || true
  sudo chmod 755 "$STATA_DIR/stinit"
  ( cd "$STATA_DIR" && printf 'y\ny\n%s\n%s\n%s\nY\nY\n%s\n%s\nY\n' \
      "$ST_SERIAL" "$ST_CODE" "$ST_AUTH" \
      "${ST_NAME:-Stata User}" "$ST_AFFIL" | sudo ./stinit ) >/dev/null 2>&1 || true
  rm -rf "$TARDIR"
  [ -x "$STATA_DIR/stata-se" ] && echo "    Stata installed at $STATA_DIR" \
    || echo "    (warning: install ran but stata-se missing — check license)"
fi

echo "==> setup: done"
