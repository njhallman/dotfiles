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
- Installs the 1Password CLI (`op`) so secrets resolve from `op://`
- Installs the Claude Code VS Code extension (`anthropic.claude-code`)
- Installs and licenses **Stata** (StataNow 18, Linux x86_64) — see below

## How it works (implementation)

The exact mechanism, end to end:

1. **No secrets live in this (public) repo.** They come from two runtime
   sources: 1Password (via the `op` CLI and the `OP_SERVICE_ACCOUNT_TOKEN`
   Codespaces secret) and/or plain Codespaces secrets (env vars).
2. **Stata installer** (`StataNow18Linux64.tar`, ~730 MB) lives in a **public**
   Cloudflare R2 bucket and is downloaded over HTTPS with `curl` — no
   credentials:
   `https://pub-7fea5c052fbe4dfa88bf8892e457c684.r2.dev/StataNow18Linux64.tar`
   (override with the `STATA_INSTALLER_URL` env/secret).
3. **Stata license** comes from `STATA_*` env vars (Codespaces secrets) if set,
   otherwise from the 1Password item `op://AI-Agents/stata-license`.
4. **Two entry points.** Your personal `install.sh` runs via *dotfiles* on every
   Codespace (git config, `op`, Claude extension, Stata). Projects use a
   `.devcontainer/devcontainer.json` whose `postCreateCommand` fetches and runs
   `project-setup.sh` — the one universal setup (LaTeX, Python, `op`, Stata +
   the VS Code extensions). Editing `project-setup.sh` updates every project on
   its next rebuild.
5. **Stata install steps** (shared by both): add libncurses5/libtinfo5 shims ->
   extract the tar to `/usr/local/stata` -> run `./install` (auto-answered) ->
   run `./stinit` with the license to write `stata.lic`. Idempotent — skips if
   `stata-se` exists.

## Stata

`install.sh` installs and licenses StataNow 18 (Linux x86_64) to
`/usr/local/stata`. The logic mirrors the proven bootstrap in
`njhallman/gender-private:setup_environment.py`. It needs two inputs — a
**license** and the **installer** — and each can come from more than one place:

| Input | Where it comes from |
|-------|---------------------|
| License | `STATA_*` env vars (Codespaces secrets) **if set**, else 1Password `op://AI-Agents/stata-license` |
| Installer (~730 MB) | `STATA_INSTALLER_URL` (public R2 bucket, no credentials) **if set**, else private R2 bucket via credentials |

This repo is **public**, so no secrets are committed — the license is never in
the script, and the installer is fetched from a public URL or via a token
provided at runtime.

### For the repo owner (you)

Your license lives in 1Password (**AI-Agents** vault, item `stata-license`,
fields `serial` / `code` / `authorization` / `name` / `affiliation`), read at
runtime via the `OP_SERVICE_ACCOUNT_TOKEN` Codespaces user secret. The
installer is fetched from the public bucket URL baked into `install.sh`.

### For coauthors (no 1Password access needed)

Anyone with their **own** Stata license can use this without 1Password — they
set their license as **Codespaces user secrets**
([github.com/settings/codespaces](https://github.com/settings/codespaces) →
Secrets), and the public installer URL needs nothing:

| Codespaces secret | Value |
|-------------------|-------|
| `STATA_SERIAL` | their serial number |
| `STATA_CODE` | their license code |
| `STATA_AUTHORIZATION` | their authorization code |
| `STATA_NAME` | licensee name |
| `STATA_AFFILIATION` | licensee affiliation |

For **shared projects**, this same logic belongs in the *project repo's*
devcontainer (e.g. a `postCreateCommand` script), not in personal dotfiles —
Codespaces dotfiles are per-user and would also carry the owner's git identity.
Each coauthor still supplies their own license via the secrets above.

### Hosting the installer (public R2 bucket)

The installer is proprietary StataCorp software. It is hosted in a **dedicated
public R2 bucket** (`stata-installer`, separate from the `gender` data bucket)
as a deliberate owner choice to avoid distributing R2 credentials. To (re)enable
public access:

1. Cloudflare dashboard → **R2** → bucket **`stata-installer`** → **Settings**
   → **Public access** → **R2.dev subdomain** → *Allow Access*.
2. Copy the public bucket URL (`https://pub-<hash>.r2.dev`). The installer URL
   is that + `/StataNow18Linux64.tar`.
3. Set it as the `STATA_INSTALLER_URL` default in `install.sh` and
   `project-setup.sh`, or export `STATA_INSTALLER_URL` as a secret.

The current public URL
(`https://pub-7fea5c052fbe4dfa88bf8892e457c684.r2.dev/StataNow18Linux64.tar`) is
already baked into both scripts; `install.sh` falls back to the private R2 bucket
via credentials only if it is ever unset (owner only).

### Notes

- If no license is resolvable, the Stata step skips with a message rather than
  failing the rest of the bootstrap.
- Set `DOTFILES_SKIP_STATA=1` to skip Stata entirely (e.g. on a small Codespace).
- Stata packages (`estout`, `reghdfe`, …) are project-level `ssc install`s and
  are intentionally left to the project repo, not installed here.

## One devcontainer for all your projects

Every project gets the same environment from **one file** — a
`.devcontainer/devcontainer.json` whose `postCreateCommand` fetches and runs
[`project-setup.sh`](project-setup.sh) from this repo. That script is the single
source of truth: **LaTeX** (TeX Live + `latexmk` + `biber`), a **Python** venv,
the **1Password CLI**, and **Stata**, plus the Claude Code, Python, Jupyter, and
LaTeX Workshop VS Code extensions. Edit `project-setup.sh` once and every project
picks it up on its next Codespace rebuild.

### Easiest: paste it on the GitHub website (no terminal)

1. On the project repo: **Code ▸ Codespaces ▸ ⋯ ▸ Configure dev container**
   (or **Add file ▸ Create new file** named `.devcontainer/devcontainer.json`).
2. Select all, delete the generated contents, and paste
   [`template/.devcontainer/devcontainer.json`](template/.devcontainer/devcontainer.json)
   (change `"name"` to your project if you like).
3. Click **Commit changes**.

### Or scaffold from a terminal

```sh
curl -fsSL https://raw.githubusercontent.com/njhallman/dotfiles/main/scaffold-devcontainer.sh | bash -s -- /path/to/project
```

Then, either way: set your Codespaces secrets (`STATA_SERIAL`, `STATA_CODE`,
`STATA_AUTHORIZATION`, `STATA_NAME`, `STATA_AFFILIATION`; optionally
`OP_SERVICE_ACCOUNT_TOKEN`) at
[github.com/settings/codespaces](https://github.com/settings/codespaces), then
create a Codespace on the repo — `project-setup.sh` runs automatically. Works for
new and existing projects, and for coauthors using their own secrets.

## Extending

Add idempotent setup steps to `install.sh`. Common candidates:

- Shell aliases / functions (drop them in a `.bashrc.d/*.sh`)
- Tool installs (`pipx install ...`, `npm install -g ...`)
- Editor settings (symlink configs into `~/.config/`)

Codespaces re-runs `install.sh` on every Codespace creation, so every
step should be safe to run twice.
