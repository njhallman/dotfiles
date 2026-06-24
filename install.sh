#!/usr/bin/env bash
# Dotfiles install script for GitHub Codespaces.
#
# Codespaces runs this once at Codespace creation. Add as many idempotent
# setup steps here as you like — anything that should be true of every
# Codespace you spin up.

set -euo pipefail

echo "==> dotfiles: configuring git"

# Match your GitHub profile name *exactly* so gh-gpgsign (the Codespaces
# commit-signing helper) accepts you as a valid author. Mismatched names
# fail with "403 | Author is invalid" even when GPG verification is
# enabled and the repo is on the trusted list.
git config --global user.name  "Nicholas Hallman"
git config --global user.email "69807938+njhallman@users.noreply.github.com"

# Sign every commit by default. gh-gpgsign uses the Codespace's
# GITHUB_TOKEN to sign on your behalf via GitHub's API. Commits will
# show as "Verified" on github.com.
git config --global commit.gpgsign true
git config --global gpg.program   /.codespaces/bin/gh-gpgsign

# Reasonable defaults you probably want
git config --global init.defaultBranch  main
git config --global pull.rebase          false
git config --global push.autoSetupRemote true   # `git push` works on new branches
git config --global fetch.prune          true   # auto-clean deleted remote branches

# 1Password CLI (op) — lets AI agents in this Codespace resolve op:// secret
# references via the OP_SERVICE_ACCOUNT_TOKEN Codespaces user secret.
# Installed in every Codespace (idempotent). Resolve a secret with:
#   op read "op://AI-Agents/<item>/<field>"
# or inject into a process:  op run -- <command>
echo "==> dotfiles: installing 1Password CLI (op)"
if ! command -v op >/dev/null 2>&1; then
  ARCH="$(dpkg --print-architecture)"   # amd64 / arm64
  OP_VERSION="2.34.0"
  curl -sSf "https://cache.agilebits.com/dist/1P/op2/pkg/v${OP_VERSION}/op_linux_${ARCH}_v${OP_VERSION}.zip" -o /tmp/op.zip
  unzip -o /tmp/op.zip op -d /tmp/op-bin
  sudo install -m 0755 /tmp/op-bin/op /usr/local/bin/op
  rm -rf /tmp/op.zip /tmp/op-bin
fi
op --version

# Claude Code VS Code extension (anthropic.claude-code) — installs the
# native IDE integration into every Codespace via the `code` CLI, which
# talks to the Codespace's VS Code Server. `--install-extension` is itself
# idempotent (re-running just reports "already installed"). The `code` CLI
# may not be on PATH this early in Codespace setup, so we skip gracefully
# rather than abort the whole script (set -e) if it's missing.
echo "==> dotfiles: installing Claude Code VS Code extension"
if command -v code >/dev/null 2>&1; then
  code --install-extension anthropic.claude-code --force || \
    echo "    (skipped: 'code --install-extension' failed)"
else
  echo "    (skipped: 'code' CLI not available yet)"
fi

# Stata (StataNow 18, Linux x86_64) — install + license Stata in every Codespace.
#
# License: from env vars if set (point Codespaces *user secrets* at them — this
# is how coauthors with their OWN Stata license use this without 1Password), else
# from 1Password (op://AI-Agents/stata-license).
#
# Installer (~730MB): downloaded from STATA_INSTALLER_URL — a PUBLIC R2 bucket, so
# no credentials are needed (this is how coauthors fetch it). Falls back to the
# private R2 bucket via credentials when the URL is unset. No secrets are
# committed to this (public) repo. NOTE: the installer is proprietary StataCorp
# software; the public URL hosting it is a deliberate owner choice.
# Mirrors njhallman/gender-private:setup_environment.py. Opt out: DOTFILES_SKIP_STATA=1.
echo "==> dotfiles: installing Stata"
STATA_DIR=/usr/local/stata

# Resolve the license: env vars (Codespaces secrets) take precedence over 1Password.
ST_SERIAL=""; ST_CODE=""; ST_AUTH=""; ST_NAME=""; ST_AFFIL=""
if [ -n "${STATA_SERIAL:-}" ]; then
  ST_SERIAL="$STATA_SERIAL"; ST_CODE="${STATA_CODE:-}"; ST_AUTH="${STATA_AUTHORIZATION:-}"
  ST_NAME="${STATA_NAME:-Stata User}"; ST_AFFIL="${STATA_AFFILIATION:-}"
elif command -v op >/dev/null 2>&1 && [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ] \
     && ST_SERIAL=$(op read "op://AI-Agents/stata-license/serial" 2>/dev/null); then
  ST_CODE=$(op read "op://AI-Agents/stata-license/code")
  ST_AUTH=$(op read "op://AI-Agents/stata-license/authorization")
  ST_NAME=$(op read "op://AI-Agents/stata-license/name")
  ST_AFFIL=$(op read "op://AI-Agents/stata-license/affiliation")
fi

# Installer source. Prefer a public URL (no credentials); fall back to the
# private R2 bucket via credentials (env vars, else 1Password) when unset.
STATA_INSTALLER_URL="${STATA_INSTALLER_URL:-https://pub-7fea5c052fbe4dfa88bf8892e457c684.r2.dev/StataNow18Linux64.tar}"
case "$STATA_INSTALLER_URL" in *REPLACE_ME*) STATA_INSTALLER_URL="" ;; esac   # blanked only if still a placeholder
R2_KEY="${R2_ACCESS_KEY_ID:-}"; R2_SECRET="${R2_SECRET_ACCESS_KEY:-}"
if [ -z "$STATA_INSTALLER_URL" ] && [ -z "$R2_KEY" ] \
   && command -v op >/dev/null 2>&1 && [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
  R2_KEY=$(op read "op://AI-Agents/cloudflare-r2/access_key_id" 2>/dev/null || true)
  R2_SECRET=$(op read "op://AI-Agents/cloudflare-r2/secret_access_key" 2>/dev/null || true)
fi

if [ -n "${DOTFILES_SKIP_STATA:-}" ]; then
  echo "    (skipped: DOTFILES_SKIP_STATA set)"
elif [ -x "$STATA_DIR/stata-se" ]; then
  echo "    (skipped: already installed at $STATA_DIR)"
elif [ "$(dpkg --print-architecture)" != "amd64" ]; then
  echo "    (skipped: StataNow18Linux64 is x86_64-only; this host is $(dpkg --print-architecture))"
elif [ -z "$ST_SERIAL" ]; then
  echo "    (skipped: no license — set STATA_SERIAL/STATA_CODE/STATA_AUTHORIZATION/STATA_NAME/STATA_AFFILIATION as Codespaces secrets, or add a 'stata-license' item to 1Password; see README)"
elif [ -z "$STATA_INSTALLER_URL" ] && [ -z "$R2_KEY" ]; then
  echo "    (skipped: no installer source — set STATA_INSTALLER_URL or R2 credentials; see README)"
else
  TARDIR="$(mktemp -d)"
  if [ -n "$STATA_INSTALLER_URL" ]; then
    echo "    downloading StataNow18Linux64.tar (~730MB, public URL)..."
    curl -fSL --retry 3 "$STATA_INSTALLER_URL" -o "$TARDIR/stata.tar"
  else
    # boto3 drives the S3-compatible (SigV4) download from the private R2 bucket.
    python3 -c "import boto3" 2>/dev/null || pip install --quiet --break-system-packages boto3 \
      || pip install --quiet boto3
    echo "    downloading StataNow18Linux64.tar (~730MB, private R2)..."
    R2_KEY="$R2_KEY" R2_SECRET="$R2_SECRET" TARGET="$TARDIR/stata.tar" python3 - <<'PY'
import os, boto3
from botocore.config import Config
s3 = boto3.client(
    "s3",
    endpoint_url="https://e3d142792462e58b3d56f127c3a5af06.r2.cloudflarestorage.com",
    aws_access_key_id=os.environ["R2_KEY"],
    aws_secret_access_key=os.environ["R2_SECRET"],
    config=Config(signature_version="s3v4"), region_name="auto",
)
s3.download_file("gender", "stata/StataNow18Linux64.tar", os.environ["TARGET"])
PY
  fi

  # libncurses5 / libtinfo5 shims Stata's console needs on modern Ubuntu.
  LIBDIR=/usr/lib/x86_64-linux-gnu
  [ -e "$LIBDIR/libncursesw.so.6" ] && [ ! -e "$LIBDIR/libncurses.so.5" ] \
    && sudo ln -s "$LIBDIR/libncursesw.so.6" "$LIBDIR/libncurses.so.5"
  [ -e "$LIBDIR/libtinfo.so.6" ] && [ ! -e "$LIBDIR/libtinfo.so.5" ] \
    && sudo ln -s "$LIBDIR/libtinfo.so.6" "$LIBDIR/libtinfo.so.5"

  sudo mkdir -p "$STATA_DIR"
  sudo tar xf "$TARDIR/stata.tar" -C "$STATA_DIR"
  # ./install unpacks the .taz archives and creates stata-se, stinit, etc., so
  # stinit only exists *after* it runs — chmod/run it second.
  sudo chmod 755 "$STATA_DIR/install"
  ( cd "$STATA_DIR" && printf 'y\ny\ny\n' | sudo bash ./install ) >/dev/null 2>&1 || true
  sudo chmod 755 "$STATA_DIR/stinit"
  # stinit writes the stata.lic license file into $STATA_DIR.
  ( cd "$STATA_DIR" && printf 'y\ny\n%s\n%s\n%s\nY\nY\n%s\n%s\nY\n' \
      "$ST_SERIAL" "$ST_CODE" "$ST_AUTH" "$ST_NAME" "$ST_AFFIL" | sudo ./stinit ) \
      >/dev/null 2>&1 || true
  rm -rf "$TARDIR"

  if [ -x "$STATA_DIR/stata-se" ]; then
    echo "    Stata installed at $STATA_DIR"
  else
    echo "    (warning: install ran but $STATA_DIR/stata-se missing — check license)"
  fi
fi

echo "==> dotfiles: done"
