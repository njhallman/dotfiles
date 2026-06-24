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
4. **Install steps** (`install.sh` for you; `template/.devcontainer/setup.sh`
   for projects): add libncurses5/libtinfo5 shims -> extract the tar to
   `/usr/local/stata` -> run `./install` (auto-answered) -> run `./stinit` with
   the license to write `stata.lic`. Idempotent — skips if `stata-se` exists.
5. **Personal vs. shared.** `install.sh` runs via your per-user *dotfiles* on
   every Codespace. For shared projects, `scaffold-devcontainer.sh` drops a
   self-contained `.devcontainer/` into the repo so coauthors get the same
   environment using *their own* Codespaces secrets.

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
3. Set it as the `STATA_INSTALLER_URL` default in `install.sh` (replace the
   `pub-REPLACE_ME` placeholder), or export `STATA_INSTALLER_URL` as a secret.

Until a real URL is set, the placeholder is ignored and `install.sh` falls back
to the private R2 bucket via credentials (owner only).

### Notes

- If no license is resolvable, the Stata step skips with a message rather than
  failing the rest of the bootstrap.
- Set `DOTFILES_SKIP_STATA=1` to skip Stata entirely (e.g. on a small Codespace).
- Stata packages (`estout`, `reghdfe`, …) are project-level `ssc install`s and
  are intentionally left to the project repo, not installed here.

## Reusing this for new projects (scaffold a devcontainer)

Dotfiles are **per-user**: once you opt in, *you* get this setup on every
Codespace automatically. To give a **project** the same environment — shared,
reproducible, and available to **coauthors who don't have your dotfiles** — drop
a devcontainer into it with the scaffold:

```sh
# from a clone of this repo:
bash scaffold-devcontainer.sh /path/to/project

# or anywhere, no clone needed:
curl -fsSL https://raw.githubusercontent.com/njhallman/dotfiles/main/scaffold-devcontainer.sh \
  | bash -s -- /path/to/project
```

This writes a **self-contained** `.devcontainer/` (`devcontainer.json` +
`setup.sh`) into the project — copied from [`template/`](template/). It contains
**no credentials**; everything secret comes from each user's Codespaces secrets.
It installs:

- the Claude Code, Python, and Jupyter VS Code extensions,
- a Python `.venv` (+ `requirements.txt` if present),
- the 1Password CLI (`op`) — used only if the user sets their own
  `OP_SERVICE_ACCOUNT_TOKEN` secret,
- **Stata**, licensed from each user's own `STATA_*` Codespaces secrets and
  fetched from the public installer URL.

Then: commit `.devcontainer/`, have each collaborator set their Codespaces
secrets (`STATA_SERIAL`, `STATA_CODE`, `STATA_AUTHORIZATION`, `STATA_NAME`,
`STATA_AFFILIATION`; optionally `OP_SERVICE_ACCOUNT_TOKEN`), and create a
Codespace — `setup.sh` runs on create. Works for new projects and for adding a
Codespace setup to existing ones.

> The Stata installer URL is baked into two places — `install.sh` (your personal
> dotfiles) and `template/.devcontainer/setup.sh` (the project template) — both
> pointing at the public R2 bucket. Override per-Codespace with the
> `STATA_INSTALLER_URL` secret (see
> [Hosting the installer](#hosting-the-installer-public-r2-bucket)).

## Extending

Add idempotent setup steps to `install.sh`. Common candidates:

- Shell aliases / functions (drop them in a `.bashrc.d/*.sh`)
- Tool installs (`pipx install ...`, `npm install -g ...`)
- Editor settings (symlink configs into `~/.config/`)

Codespaces re-runs `install.sh` on every Codespace creation, so every
step should be safe to run twice.
