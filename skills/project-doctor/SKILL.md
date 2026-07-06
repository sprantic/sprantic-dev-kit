---
name: project-doctor
description: Verify a project's env context is correctly wired — git identity, account/SSH routing, remote reachability, the Nix devShell toolchain, and that any previously-cleartext secrets were rotated. Use when the user asks to check/verify/test a project's setup, after onboarding a project, or to debug "wrong git identity / pushing as the wrong account / toolchain missing".
---

# project-doctor — verify a project's context

Run inside the project dir. Report each as ✅ / ⚠️ with the fix.

1. **Identity** — `git config user.name` / `user.email` → expected per the `includeIf`. If it's your default, the gitdir doesn't match (check the path; check a stale `~/.gitconfig` isn't shadowing: `git config --show-origin --get-all user.email`).
2. **Account routing** — `git ls-remote --get-url` → `git@<alias>:<owner>/<repo>` for a distinct account. Still https when you expected routing → `url.insteadOf` inactive (or cloned before switching).
3. **Account auth** — `ssh -T git@<alias>` → "Hi <account>!". If not, the per-account key isn't generated/enrolled. `Host key verification failed` on a new/self-hosted host ⇒ not an auth failure — connect once interactively, verify the fingerprint, accept it into `~/.ssh/known_hosts`.
4. **Reachability** — `git ls-remote >/dev/null` → fetch works over the right key.
5. **Toolchain** — `nix develop -c <primary-tool> --version` → builds, expected version. `"flake.nix … not tracked"` → `git add flake.nix`. Feature removed in a newer version → **pin-tool**.
6. **Secrets present** (if any) — in a `direnv allow`-ed shell the expected `$VARS` are non-empty and the `.envrc` guards don't warn. Empty → `.envrc.local` missing, or Bao unreachable (the Linux machine often can't reach OpenBao).
7. **Secrets rotated** — if this project was migrated from a cleartext source (old `project.json`/`.env`/`.profile`), confirm those secrets were **rotated** (not just copied into Bao) and the old copies scrubbed. A still-live leaked secret ⇒ **not done** → **rotate-secrets**.
8. **Registry** (if the `repo` command is installed — COOKBOOK §10) — `repo status` shows this project `present`. `UNTRACKED` → `repo register` + commit the manifest in the env repo. `DRIFTED` → pick the side that's truth: local is right → `repo register --update`; manifest is right → `repo sync --fix-remotes`.
