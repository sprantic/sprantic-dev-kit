---
name: machine-sync
description: Bring a machine's project clones in line with the repo registry (repos.manifest in the env repo) — clone what's missing, resolve drifted origin URLs, register untracked clones. Use when setting up a new/additional machine, when the user says "get my projects onto this machine" / "sync my repos", or when a clone exists on one machine but not another.
---

# machine-sync — same clones on every machine

Converge this machine's `~/projects` with the registry (COOKBOOK §10, sibling of this skill's plugin root). Requires the `repo` command (wired via `templates/repo-registry.nix` in the env repo) and a pulled env repo — on a **brand-new machine** bootstrap the env first (COOKBOOK §8) so `repo`, direnv, and the SSH aliases exist at all.

## Steps
1. **Fresh manifest**: `cd ~/projects/env && git pull` — the manifest travels with the env repo.
2. **Preview**: `repo status` → `MISSING` (will be cloned), `DRIFTED` (step 4), `UNTRACKED` (step 5). Nothing flagged → done, say so.
3. **Sync**: `repo sync` clones everything missing through `direnv exec <parent>`, so each tree's identity/SSH routing applies. A clone failing on a blocked `.envrc` → `direnv allow <parent>` once on this machine, re-run `repo sync`.
4. **Drift** — the manifest is the published truth; don't guess which side wins, ask/check:
   - the **local** URL is the newer, correct one → `repo register --update <dir>` (publishes it into the manifest).
   - the **manifest** is right → `repo sync --fix-remotes` (resets local origins).
5. **Untracked**: a clone worth syncing → `repo register <dir>`; a legacy/one-machine tree → an `ignore <prefix>` line in the manifest (the ignore rule itself syncs to every machine).
6. **Publish**: manifest changed → commit + push the env repo (that *is* the sync channel).
7. **Verify**: `repo status` shows every entry `present`; spot-check one fresh clone with **project-doctor** (identity, routing, toolchain).

## Hard rules
- Resolve `DRIFTED` only via the two verbs (`--update` / `--fix-remotes`) — hand-edited remotes leave manifest and machines diverged.
- An origin URL with embedded credentials is a leak even though the tooling strips it from the manifest: the token sat in cleartext (git config, shell history) → **rotate-secrets**.
- Don't delete local clones the manifest doesn't know about — register or `ignore` them; removal is the user's call.
