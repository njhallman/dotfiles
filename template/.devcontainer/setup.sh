#!/usr/bin/env bash
# Project devcontainer bootstrap — scaffolded from njhallman/dotfiles.
#
# SELF-CONTAINED: this script and devcontainer.json are the whole setup. They
# depend on Codespaces secrets, NOT on anyone's personal dotfiles, so coauthors
# get an identical environment by supplying their OWN secrets.
#
# NO CREDENTIALS ARE COMMITTED. Set these as Codespaces secrets
# (github.com/settings/codespaces → Secrets, or repo/org Codespaces secrets):
#
#   Stata license (your own — install skips if STATA_SERIAL is unset):
#     STATA_SERIAL, STATA_CODE, STATA_AUTHORIZATION, STATA_NAME, STATA_AFFILIATION
#   Stata installer (public URL, no credentials):
#     STATA_INSTALLER_URL   (else the baked-in default below is used)
#   Optional, for op:// secret resolution in this project:
#     OP_SERVICE_ACCOUNT_TOKEN
#
# Opt out of the Stata step with DOTFILES_SKIP_STATA=1.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

echo "==> project setup: system packages"
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  build-essential python3-dev python3-venv git-lfs unzip >/dev/null
git lfs install >/dev/null 2>&1 || true

echo "==> project setup: Python virtual environment"
python3 -m venv .venv
.venv/bin/python -m pip install --upgrade pip setuptools wheel >/dev/null
if [ -f requirements.txt ]; then
  .venv/bin/python -m pip install --no-cache-dir -r requirements.txt
else
  echo "    (no requirements.txt — created an empty .venv)"
fi

echo "==> project setup: 1Password CLI (op)"
# Installed so op:// secrets resolve IF the user provides their own
# OP_SERVICE_ACCOUNT_TOKEN as a Codespaces secret. No token is baked in here.
if ! command -v op >/dev/null 2>&1; then
  ARCH="$(dpkg --print-architecture)"
  OP_VERSION="2.34.0"
  curl -sSf "https://cache.agilebits.com/dist/1P/op2/pkg/v${OP_VERSION}/op_linux_${ARCH}_v${OP_VERSION}.zip" -o /tmp/op.zip
  unzip -o /tmp/op.zip op -d /tmp/op-bin >/dev/null
  sudo install -m 0755 /tmp/op-bin/op /usr/local/bin/op
  rm -rf /tmp/op.zip /tmp/op-bin
fi
op --version || true

echo "==> project setup: Stata"
STATA_DIR=/usr/local/stata
# Public installer URL (no credentials). Replace the placeholder with your
# public R2 bucket URL, or override via the STATA_INSTALLER_URL secret.
STATA_INSTALLER_URL="${STATA_INSTALLER_URL:-https://pub-7fea5c052fbe4dfa88bf8892e457c684.r2.dev/StataNow18Linux64.tar}"
case "$STATA_INSTALLER_URL" in *REPLACE_ME*) STATA_INSTALLER_URL="" ;; esac
if [ -n "${DOTFILES_SKIP_STATA:-}" ]; then
  echo "    (skipped: DOTFILES_SKIP_STATA set)"
elif [ -x "$STATA_DIR/stata-se" ]; then
  echo "    (skipped: already installed at $STATA_DIR)"
elif [ "$(dpkg --print-architecture)" != "amd64" ]; then
  echo "    (skipped: StataNow18Linux64 is x86_64-only; host is $(dpkg --print-architecture))"
elif [ -z "${STATA_SERIAL:-}" ]; then
  echo "    (skipped: no license — set STATA_SERIAL/STATA_CODE/STATA_AUTHORIZATION/STATA_NAME/STATA_AFFILIATION as Codespaces secrets)"
elif [ -z "$STATA_INSTALLER_URL" ]; then
  echo "    (skipped: STATA_INSTALLER_URL not set; edit setup.sh or set the secret)"
else
  TARDIR="$(mktemp -d)"
  echo "    downloading StataNow18Linux64.tar (~730MB)..."
  curl -fSL --retry 3 "$STATA_INSTALLER_URL" -o "$TARDIR/stata.tar"

  # libncurses5 / libtinfo5 shims Stata's console needs on modern Ubuntu.
  LIBDIR=/usr/lib/x86_64-linux-gnu
  [ -e "$LIBDIR/libncursesw.so.6" ] && [ ! -e "$LIBDIR/libncurses.so.5" ] \
    && sudo ln -s "$LIBDIR/libncursesw.so.6" "$LIBDIR/libncurses.so.5"
  [ -e "$LIBDIR/libtinfo.so.6" ] && [ ! -e "$LIBDIR/libtinfo.so.5" ] \
    && sudo ln -s "$LIBDIR/libtinfo.so.6" "$LIBDIR/libtinfo.so.5"

  sudo mkdir -p "$STATA_DIR"
  sudo tar xf "$TARDIR/stata.tar" -C "$STATA_DIR"
  # ./install creates stata-se, stinit, etc., so stinit only exists afterwards.
  sudo chmod 755 "$STATA_DIR/install"
  ( cd "$STATA_DIR" && printf 'y\ny\ny\n' | sudo bash ./install ) >/dev/null 2>&1 || true
  sudo chmod 755 "$STATA_DIR/stinit"
  ( cd "$STATA_DIR" && printf 'y\ny\n%s\n%s\n%s\nY\nY\n%s\n%s\nY\n' \
      "$STATA_SERIAL" "${STATA_CODE:-}" "${STATA_AUTHORIZATION:-}" \
      "${STATA_NAME:-Stata User}" "${STATA_AFFILIATION:-}" | sudo ./stinit ) >/dev/null 2>&1 || true
  rm -rf "$TARDIR"

  if [ -x "$STATA_DIR/stata-se" ]; then
    echo "    Stata installed at $STATA_DIR"
  else
    echo "    (warning: install ran but $STATA_DIR/stata-se missing — check license)"
  fi
fi

echo "==> project setup: done"
