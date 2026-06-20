# project-kit

A no-brainer skillset for setting up and maintaining projects in the reproducible dev env
(Nix flakes + direnv + per-context git identity/account + OpenBao secrets). Say the intent;
the skills do the rest.

- *"new website for customer XY, repo git@…:org/repo.git, get going"* → **new-project**
- *"this site needs an older hugo"* → **pin-tool**
- *"that token was in cleartext"* / migrating an old project.json → **rotate-secrets**
- *"check the <customer> project is wired right"* → **project-doctor**

## Contents
- `COOKBOOK.md` — the what-goes-where reference (start here).
- `skills/` — model-invoked skills: `new-project`, `pin-tool`, `rotate-secrets`, `project-doctor`.
- `templates/` — per-stack `flake.<stack>.nix` + the generic `.envrc` / `.envrc.local`.

## Requirements / opinionated about
This kit assumes a specific (swappable) stack: **Nix flakes** for toolchains, **direnv** for
auto-loading, per-context **git identity/account routing**, and **OpenBao** for secrets. The
conventions live in `COOKBOOK.md`; adapt the secret-store and Tofu state-backend specifics to
your own infra.

## Install as a Claude Code plugin
This repo is plugin-shaped (`.claude-plugin/plugin.json` + `skills/`). Load it with
`claude --plugin-dir /path/to/project-kit`, or publish it to a plugin marketplace.

## License
MIT — see [`LICENSE`](LICENSE).
