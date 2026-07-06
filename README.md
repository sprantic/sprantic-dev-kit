# sprantic-dev-kit

A no-brainer skillset for setting up and maintaining projects in the reproducible dev env
(Nix flakes + direnv + per-context git identity/account + OpenBao secrets). Say the intent;
the skills do the rest.

- *"new website for customer XY, repo git@…:org/repo.git, get going"* → **new-project**
- *"this site needs an older hugo"* → **pin-tool**
- *"that token was in cleartext"* / migrating an old project.json → **rotate-secrets**
- *"check the <customer> project is wired right"* → **project-doctor**
- *"new laptop — get my projects onto it"* → **machine-sync**

## Contents — reading order: **learn → reference → automate**
- `TUTORIAL.md` — **new here? start here.** Hands-on walkthrough of the whole model (Nix flakes, direnv, per-context git identity, OpenBao) with the real first-build gotchas.
- `COOKBOOK.md` — the what-goes-where **reference** once you know the model.
- `skills/` — model-invoked skills that **automate** the cookbook: `new-project`, `pin-tool`, `rotate-secrets`, `project-doctor`, `machine-sync`.
- `templates/` — per-stack `flake.<stack>.nix`, the generic `.envrc` / `.envrc.local`, and the `repo` clone registry (`repo-registry.sh` + home-manager wiring).

## Requirements / opinionated about
This kit assumes a specific (swappable) stack: **Nix flakes** for toolchains, **direnv** for
auto-loading, per-context **git identity/account routing**, and **OpenBao** for secrets. The
conventions live in `COOKBOOK.md`; adapt the secret-store and Tofu state-backend specifics to
your own infra.

## Install as a Claude Code plugin
This repo is plugin-shaped (`.claude-plugin/plugin.json` + `skills/`). Load it with
`claude --plugin-dir /path/to/sprantic-dev-kit`, or publish it to a plugin marketplace.

## License
MIT — see [`LICENSE`](LICENSE).
