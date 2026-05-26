# dotfiles

Personal setup applied to every new GitHub Codespace.

GitHub Codespaces clones this repo to `~/dotfiles` on Codespace creation
and runs `install.sh`. To enable, opt in at
[github.com/settings/codespaces](https://github.com/settings/codespaces)
under "Dotfiles" — point the setting at this repo.

## What this does

- Sets `git user.name` / `user.email` to values that match the GitHub
  profile (required for `gh-gpgsign` to accept the author)
- Enables global commit signing via the Codespaces signing helper
- Sets a few sensible git defaults (`push.autoSetupRemote`, `fetch.prune`,
  `init.defaultBranch=main`)

## Extending

Add idempotent setup steps to `install.sh`. Common candidates:

- Shell aliases / functions (drop them in a `.bashrc.d/*.sh`)
- Tool installs (`pipx install ...`, `npm install -g ...`)
- Editor settings (symlink configs into `~/.config/`)

Codespaces re-runs `install.sh` on every Codespace creation, so every
step should be safe to run twice.
