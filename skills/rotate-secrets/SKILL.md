---
name: rotate-secrets
description: Rotate (regenerate) any secret that was previously stored in cleartext on disk — old project.json tokens, .profile/.env keys, committed config, shell history — then vault the NEW value in OpenBao and scrub the old copies. Use when migrating a project that had plaintext secrets, or when the user says a key/token was exposed, leaked, or "in cleartext".
---

# rotate-secrets — cleartext means compromised

**Core rule: a secret that has ever existed in cleartext on disk is compromised. You ROTATE it — you do not just move it.** Copying the old value into OpenBao does **not** undo the exposure; it only changes where the still-leaked value is stored.

Triggers (anything where the value sat unencrypted): old `pswitch`/`project.json` tokens, `~/.profile`/`~/.bashrc` exports, `.env` files, values committed to a git repo, shell history, screenshots/logs/this chat.

For **each** such secret:
1. **Identify** it — what service/account/scope is it valid for? (GitHub PAT, Hetzner `hcloud_token`, API key, deploy key, …)
2. **Rotate at the source** — regenerate/revoke-and-reissue it in the issuing system, and update everything that consumes it (CI, other machines).
3. **Vault the NEW value** in OpenBao at the right path (`infra/…` · `customers/<name>/…` · `personal/<you>/…`). Never echo the value.
4. **Scrub the old cleartext** — delete the file/line/entry. If it was ever **git-committed**, the history is leaked too: rotation is mandatory regardless, and consider history rewrite + enabling secret scanning.
5. **Wire** the new path into `.envrc.local` (gitignored) — never the value into a committed file.

> A migration is **not done** while a known-leaked secret is still live. Default to rotating; only skip if you can prove the value never left a trusted boundary.
