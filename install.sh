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

echo "==> dotfiles: done"
