---
name: new-project
description: Set up or onboard a project/sub-project into the reproducible dev env — Nix-flake toolchain, direnv auto-loading, per-context git identity + account routing, and OpenBao secrets. Use when the user says things like "new website / go / node / python project", "set up/onboard this repo for customer X" or "...internally", or hands over a git repo URL to "get going".
---

# new-project — no-brainer onboarding

From a one-line intent (e.g. *"new website for customer XY, repo git@…:org/repo.git, go"*), produce a fully wired project following `COOKBOOK.md` (sibling of this skill's plugin root). **Don't make the user write `flake.nix`** — assemble it from a template.

## 1. Gather (ask ONLY what you can't infer)
- **Stack**: website(hugo) | go | node | python | tofu/infra | other. If onboarding an existing repo, *infer from contents*: `go.mod`→go, `package.json`→node, `config.toml`/`hugo.*`→website, `*.tf`→tofu, `pyproject.toml`→python.
- **Owner**: a customer (→ group `~/projects/<customer>/`, or `~/projects/websites/` for sites) or **internal** (`~/projects/internal/`).
- **Git**: repo URL + the **account** it's under (GitHub/GitLab). If that account is new here → set up its alias/key first (see "New account").
- **Secrets**: does it need API tokens? which ones.

## 2. Execute (the cookbook, automated — read COOKBOOK.md for the rules)
1. **Layout**: choose `~/projects/<group>/<repo>` (COOKBOOK §1).
2. **Clone via the SSH alias** (not HTTPS — avoids private/org "not found"):
   `git clone git@github-<acct>:<owner>/<repo>.git ~/projects/<group>/<repo>` (or `git init` for a brand-new repo).
3. **Toolchain**: copy `templates/flake.<stack>.nix` → `<project>/flake.nix`; tweak the `packages` list for what the repo actually needs. `git add flake.nix` (Nix ignores untracked files). If many projects in the group share the stack, put it at the **group** level instead and let this one inherit.
4. **`.envrc`**: copy `templates/envrc` → `<project>/.envrc`; add a `log_status` guard line per required var. `git add`.
5. **`.envrc.local`** (only if it has secrets): copy `templates/envrc.local`, fill the `bao kv get` lines with this project's paths (COOKBOOK §7). It's globally gitignored — never commit it.
6. **Identity + account**: append an `includeIf` to `~/projects/env/home/git.nix` for the project/group gitdir (name/email, + `url.insteadOf` if a distinct account). New account → also add its alias to `~/projects/env/home/ssh.nix`.
7. **Secrets**: `bao kv put <path> …` at the right path (COOKBOOK §7). Don't echo secret values.
   - 🔑 **If migrating from a source that held secrets in cleartext** (old `project.json`/`.env`/`.profile`, committed config, shell history): those are **compromised** — invoke **rotate-secrets** to regenerate them at the source and vault the NEW values; never copy the old leaked value into Bao. Scrub the old copies.
8. **Apply**: `cd ~/projects/env && ./bootstrap.sh`; then `cd <project> && direnv allow`.
9. **Verify**: run the **project-doctor** skill (4-layer test).

## New account (if the repo's account isn't wired yet)
- Add `github-<acct>` to `home/ssh.nix`; `ssh-keygen -t ed25519 -f ~/.ssh/id_github_<acct> -C "<acct>@$(hostname -s)"`; tell the user to enroll the `.pub` on that account; verify `ssh -T git@github-<acct>` → "Hi <acct>!".

## Hard rules (never violate)
- **Commit**: `flake.nix`/`flake.lock`, generic `.envrc`. **Never commit**: `.envrc.local`, secret values.
- **Private SSH keys** stay on-device (`~/.ssh/`), one per account; never in Bao. **Public keys** → the account/server, not Bao. **Bao = tokens/secrets only.**
- **Cleartext = compromised.** Any secret that previously sat in cleartext (old config/.env/.profile/history/committed file) must be **rotated**, not just moved into Bao. Don't close a migration while a leaked secret is still live.
- Build fails on a removed/changed tool feature → use the **pin-tool** skill (pin an older version via a nixpkgs commit), don't disable safety.
- Anything you set up by hand that should reach every machine → put it in the flake, not a one-off command.
