# Tutorial: Reproducible Dev Environment & Per-Project Contexts (Nix + direnv + OpenBao)

A hands-on walkthrough for setting up a Mac (or Linux) dev environment that is:
- **reproducible** — declared once in a Nix flake, identical on every machine;
- **context-aware** — each project/customer directory auto-loads its own toolchain, secrets, and git identity;
- **secret-clean** — credentials come from OpenBao at runtime, never committed.

It replaces an older manual model (hand-edited shell env + plaintext tokens in a per-project file).

> **Read the ⚠️ STUMBLE blocks.** Every one was hit for real during the first build — they'll save you an hour each.

## Mental model
- **git** syncs code. **Nix** syncs the *environment*. **direnv** scopes it *per directory*. **OpenBao** supplies *secrets*.
- A change flow you'll repeat constantly: **edit a `.nix` file → `home-manager switch` → open a new shell → see it live** (and `home-manager rollback` if bad).

### The picture (and how settings cascade)

- **A flake is a *locked recipe card*** — it lists the exact tools and exact versions a project needs, pinned so anyone, on any machine, today or in three years, builds the *identical* kit. The cure for "but it worked on mine."
- **An `.envrc` is a *note taped to a folder's door*** — "when you walk in, lay out these tools and settings; when you walk out, put them away." `cd` in → the toolkit appears; `cd` out → it's gone. (`use flake` just means *"the kit to lay out is the one on the recipe card."*)
- **direnv walks *upward*** — when you enter a folder it looks there for an `.envrc`; if there isn't one it keeps looking **up the parent folders** until it finds one. So a note on a *parent* door covers everything beneath it.

That upward walk is how **project-wide / group-wide settings cascade**:

```
~/projects/websites/          .envrc + flake   → shared Hugo kit for ALL sites
├── simple-site/              (no .envrc)        → inherits the parent's kit, automatically
├── pinned-site/              own .envrc+flake   → OVERRIDES (older Hugo) — nearest note wins
└── extended-site/            own .envrc         → uses `source_up` to INHERIT the group +
                                                    add its own (hugo+tofu, secrets)
```

So the two moves you have:
- **Put shared settings high up** (a parent `.envrc` + flake) → every folder below inherits them for free, just by being there.
- A specific project can **override** (its own `.envrc`/flake — the *nearest* one wins) or **extend** (`source_up` runs the parent's note first, then adds its own).

One-line summary: **flake = the locked recipe; `.envrc` = the door-note that lays it out on entry; and the nearest door-note up the tree wins (or `source_up` to stack them).**

---

## Step 0 — Install Nix
Determinate Systems installer (flakes on by default, clean uninstaller):
```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```
Then **open a new terminal** so `nix` is on `PATH`. Verify: `nix --version`.

---

## Step 1 — Home-manager base (shell + CLI tools)
Repo `~/projects/env` (destined for your private git remote). Minimal layout:
```
flake.nix              # inputs: nixpkgs + home-manager; output homeConfigurations.<user>
home/common.nix        # home.packages (rg, fd, jq, gh, glab, opentofu, direnv…), imports bash/git
home/bash.nix          # programs.bash — aliases, PATH, prompt (ports your old ~/.profile)
home/git.nix           # programs.git — identity + includeIf
```
Validate before applying:
```bash
cd ~/projects/env
nix --extra-experimental-features 'nix-command flakes' build ".#homeConfigurations.<user>.activationPackage"
```
Apply:
```bash
nix run home-manager/master -- switch --flake .#<user> -b backup
```

> ⚠️ **STUMBLE 1 — "Existing file '~/.profile' would be clobbered".** Home-manager won't overwrite a real dotfile. **Fix:** add `-b backup` (it renames the old file to `*.backup`). The backup may still contain old plaintext secrets — clean it up after.

> ⚠️ **STUMBLE 2 — `programs.git.userName` deprecation warnings.** Recent home-manager renamed git options. **Fix:** use the `programs.git.settings = { user.name = …; user.email = …; … }` schema, not `userName`/`userEmail`/`extraConfig`.

> ⚠️ **STUMBLE 3 — `home.stateVersion` complaint.** Set it to whatever value the error suggests for your home-manager release (e.g. `"25.05"`).

> 💡 **What actually happened:** `switch` builds an immutable result in `/nix/store` and points your home at it via symlinks (`~/.profile` → `/nix/store/…-home-manager-files/.profile`; `~/.nix-profile/bin/jq` → `/nix/store/…-jq/bin/jq`). Tools aren't "installed globally" — they're store paths you symlink to, which is why versions never collide.

---

## Step 2 — direnv basics
`programs.direnv.enable = true` (with `nix-direnv.enable = true`) installs a shell hook. Test:
```bash
mkdir -p ~/sandbox/hello && cd ~/sandbox/hello
echo 'export GREETING="hi"' > .envrc
echo $GREETING        # empty — direnv hasn't run it
direnv allow          # security gate: you approve the .envrc
echo $GREETING        # now set
cd .. && echo $GREETING   # empty again — unloaded on exit
```

> ⚠️ **STUMBLE 4 — `.envrc` set but `$VAR` always empty, even after `direnv allow`.** The direnv shell hook isn't active because **you're in a shell opened before the home-manager switch** — the hook only lands in *new* shells. **Fix:** open a new terminal. **Verify:** `type -t _direnv_hook` → `function`.

> 💡 `.envrc` is **plain bash** plus direnv "stdlib" helpers: `use flake`, `source_up`, `dotenv`, `PATH_add`, `watch_file`. `direnv allow` is required after every edit (it runs code).

---

## Step 3 — devShells: a toolchain per directory
```bash
mkdir -p ~/sandbox/web && cd ~/sandbox/web
cat > flake.nix <<'EOF'
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  outputs = { nixpkgs, ... }:
    let pkgs = nixpkgs.legacyPackages."aarch64-darwin";
    in { devShells."aarch64-darwin".default = pkgs.mkShell { packages = [ pkgs.hugo ]; }; };
}
EOF
echo 'use flake' > .envrc && direnv allow
which hugo      # inside → /nix/store/...   |   cd ~ then which hugo → not found
```
`nixpkgs` = the ~120k-package collection (`github:NixOS/nixpkgs`); `pkgs.mkShell` is a helper *function* from it. `nixpkgs-unstable` is the rolling newest branch (right for a workstation); update deliberately with `nix flake update`.

---

## Step 4 — Different versions in parallel
Two dirs, two versions, switched by `cd`, coexisting (even in two terminals at once):
```bash
# proj-a → nodejs_22 ; proj-b → nodejs_24  (mkShell packages = [ pkgs.nodejs_22 ] etc.)
cd ~/sandbox/proj-a && node --version   # v22.x
cd ~/sandbox/proj-b && node --version   # v24.x
```

> ⚠️ **STUMBLE 5 — "Refusing to evaluate package 'nodejs-20…' because it is marked as insecure".** The version reached **end-of-life**, so nixpkgs blocks it by default (a feature). **Fix:** use a supported version (`nodejs_22`/`nodejs_24`). For a *genuinely required* old version, pin an **older nixpkgs commit** via a second `inputs.nixpkgs-old` rather than disabling the guard. Last resort: `NIXPKGS_ALLOW_INSECURE=1` + `--impure`, or `permittedInsecurePackages`.

---

## Step 5 — Secrets from OpenBao (retires plaintext tokens)
```bash
export BAO_ADDR=https://openbao.<your-domain>
bao login -method=userpass username=<you>
bao kv put personal/<you>/sandbox token=hello-from-bao

mkdir -p ~/sandbox/secret && cd ~/sandbox/secret
echo 'export MY_TOKEN="$(bao kv get -field=token personal/<you>/sandbox)"' > .envrc
direnv allow
echo "$MY_TOKEN"                       # set inside, empty outside
grep -rn hello-from-bao .              # nothing — secret never touches disk
```

> ⚠️ **STUMBLE 6 — `bao` errors: `dial tcp 127.0.0.1:8200: connect: connection refused`.** `BAO_ADDR` isn't set in this shell, so `bao` used its localhost default. **Fix now:** `export BAO_ADDR=…`. **Fix forever:** declare it in home-manager so every shell has it:
> ```nix
> home.sessionVariables.BAO_ADDR = "https://openbao.<your-domain>";
> ```
> General rule: **a var you want everywhere goes in the flake, not a manual `export`.**

> ⚠️ **STUMBLE 7 — secret fetch returns empty after a while.** Login tokens are short-lived (e.g. 1h TTL, by design for fast revocation). **Fix:** `bao login` again. (Long-term: an OpenBao Agent or OIDC session.)

---

## Step 6 — git identity per directory (`includeIf`)
In `home/git.nix`, inside `programs.git`:
```nix
includes = [
  { condition = "gitdir:~/customers/acme/";
    contents.user = { name = "<Name>"; email = "you@acme.example"; }; }
];
```
`switch`, then inside a repo under that path `git config user.email` returns the scoped identity; elsewhere it returns your default. Parallel-safe (per-repo, not a global env mutation).

> ⚠️ **STUMBLE 8 — `includeIf` set but `git config user.email` still returns the default.** A **stale legacy `~/.gitconfig`** (from before Nix) is read *after* the home-manager-managed `~/.config/git/config`, and git's *last-wins* merge lets it override the included identity. **Diagnose:** `git config --show-origin --get-all user.email` (you'll see the `includeIf` value present but overridden by `~/.gitconfig`). **Fix:** `mv ~/.gitconfig ~/.gitconfig.pre-nix`. (macOS path canonicalization is *not* usually the cause — check `--show-origin` first.)

> 💡 **No silent default, fail loud.** Pair the per-context rules with `user.useConfigOnly = true` and **no** unconditional global `user.name`/`user.email`. Give a broad work-tree default via `includeIf gitdir:~/projects/` (listed first; specific rules override, last-match-wins). Then a repo *outside* `~/projects/` matches nothing → the commit fails loudly (`Author identity unknown`) instead of being silently mis-attributed. See `COOKBOOK.md` §5.

---

## Step 7 — The cascade: customer context → projects (`source_up`)
```
~/customers/acme/.envrc          # export CUSTOMER, AWS_PROFILE, secret paths…
~/customers/acme/site/.envrc     # source_up   (inherit acme context)
                                 # use flake    (this project's toolchain)
~/customers/acme/site/flake.nix  # devShell
```
`source_up` pulls in the parent `.envrc`, so one `cd` into a project gives you: **inherited customer env + secrets + that project's toolchain**, plus the right git identity (via Step 6's `includeIf` keyed to `~/customers/acme/`). Everything clears on exit. (Both parent and child `.envrc` must be `direnv allow`-ed.)

This is the full replacement for the old manual context-switching model: context = directory; identity/secrets/toolchain all switch automatically and safely, in parallel across terminals.

---

## Step 8 — Zero-effort bootstrap for BOTH macOS and Linux

Goal: onboard any machine with `git clone <env-repo> && cd env && ./bootstrap.sh` — no manual steps, same result on macOS or Linux (incl. an Apple `container machine` / Ubuntu).

**One flake, two configs** — a helper builds the same modules for each system:
```nix
# flake.nix
outputs = { nixpkgs, home-manager, ... }:
  let
    mkHome = system: home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.${system};
      modules = [ ./home/common.nix ];
    };
  in {
    homeConfigurations = {
      "<user>"        = mkHome "aarch64-darwin";   # Mac
      "<user>-linux"  = mkHome "aarch64-linux";    # container machine / Ubuntu
    };
  };
```

**Make the one OS-specific bit conditional** — the home path:
```nix
# home/common.nix
{ pkgs, ... }:
let isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
in {
  home.homeDirectory = if isDarwin then "/Users/<user>" else "/home/<user>";
  # everything else is portable (guard macOS-only lines, e.g. `[ -x /opt/homebrew/bin/brew ] && …`)
}
```

**`bootstrap.sh`** — installs Nix if missing, picks the config by OS, activates:
```bash
#!/usr/bin/env bash
set -euo pipefail
if ! command -v nix >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh 2>/dev/null || true
fi
case "$(uname -s)" in
  Darwin) CONF="<user>" ;;
  Linux)  CONF="<user>-linux" ;;
  *) echo "Unsupported OS"; exit 1 ;;
esac
export USER="${USER:-$(id -un)}"        # see STUMBLE 10
export LOGNAME="${LOGNAME:-$USER}"
exec nix run home-manager/master -- switch --flake ".#${CONF}" -b backup
```

> ⚠️ **STUMBLE 10 — `home-manager: line 158: USER: unbound variable`.** A **non-login / container shell** (e.g. `container machine run`, CI) doesn't export `USER`/`LOGNAME`, and home-manager needs them. **Fix:** the bootstrap sets them itself (above). General rule: **a bootstrap must not assume a login-shell environment** — set the vars it depends on.

> 💡 Inside an Apple `container machine`, your Mac files are mounted at `/Users/<you>` but the machine's `$HOME` is the **native `/home/<you>`** — so there's *no* dotfile clash; the Mac runs its home-manager into `/Users/...`, the machine runs the Linux config into `/home/...`. Code is shared via the mount (or git); dotfiles stay per-OS, as they should.

> 💡 **GUI apps on macOS aren't Nix's job.** nixpkgs GUI apps are Linux-oriented and don't integrate on darwin. Manage `.app` bundles with Homebrew **casks** and make that layer reproducible with a committed `Brewfile` (`brew bundle`) — the same "put it in code, not a one-off" rule, just a different tool.

---

## Platform gotchas worth knowing (macOS)

> ⚠️ **`dig` says NXDOMAIN but the name works in `curl`/browser.** On macOS `dig` ignores `/etc/resolver/*` and talks straight to the default resolver. **Test macOS resolution with** `dscacheutil -q host -a name <host>` **or `curl`, not `dig`.**

> ⚠️ **Internal `*.your.domain` names don't resolve at all, even though a VPN/mesh (e.g. Tailscale) shows a split-DNS route.** The mesh sometimes fails to apply the split route to the macOS resolver. **Fix:** create the resolver file directly:
> ```bash
> echo "nameserver <internal-dns-ip>" | sudo tee /etc/resolver/your.domain
> ```
> (Codify it later via nix-darwin so every Mac gets it.)

> ⚠️ **macOS ships bash 3.2 and defaults to zsh.** Don't fight it with Homebrew hacks — home-manager installs a modern bash 5.x ahead of it on `PATH`.

---

## Cosmetics (optional, but everyone asks)

**Quiet/soften direnv's log chatter** — via `~/.config/direnv/direnv.toml` (codify with `programs.direnv.config.global`):
```toml
[global]
hide_env_diff = true                                  # drop the noisy "export +VAR" line
log_filter = "^direnv: (loading|unloading|export|using)"  # hide routine lines, keep errors
```
> ⚠️ **STUMBLE 9 — `export DIRENV_LOG_FORMAT=` doesn't silence direnv.** Some builds ignore the env var / treat empty as "default format" (you still see full text, or a custom format shows no effect). **Fix:** use the `direnv.toml` above instead of the env var.

**venv-style prompt indicator** — direnv **deliberately ignores `PS1` set from an `.envrc`**, so your *own* prompt must read `$DIRENV_DIR` (set when a context is active). In `home/bash.nix`:
```nix
__direnv_tag() { [ -n "$DIRENV_DIR" ] && printf '(*) '; }
export PS1='$(__direnv_tag)\[\e[32m\]\u@:\w\$ \[\e[0m\]'
```

---

## What to gitignore (Nix / direnv) — and where

Two buckets, and the *location* of the rule differs:

- **Tooling artifacts (yours)** — appear in *every* repo because you run Nix/direnv: **`.direnv/`**, **`result`**, **`result-*`**. Put these in your **global** gitignore (`~/.config/git/ignore`), set once via home-manager:
  ```nix
  programs.git.ignores = [ ".direnv/" "result" "result-*" ];
  ```
  This applies to every repo on every machine and **never pollutes a customer's repo** with your tooling's leftovers. Don't add `.direnv/` to individual repos' `.gitignore`.
- **Project build outputs** — go in *that project's* committed `.gitignore` (Hugo `public/`/`resources/`, `node_modules/`, etc.) — they're about that project, and everyone working on it needs them ignored.

**Commit, never ignore:** `flake.nix`, `flake.lock`, `.envrc` — they *are* the reproducible toolchain (`.envrc` holds `bao kv get` *commands*, not secret values).

> Rule of thumb: **"appears because of MY tools" → global gitignore; "this project's build output" → the project's `.gitignore`.**

### Secret-wiring in shared / external repos

A committed `.envrc` that does `bao kv get …` is a problem the moment the repo has **non-org collaborators** (a customer's devs, a public fork): it *breaks* for them (they can't reach your OpenBao) **and** it *leaks* your Bao address + secret paths into a repo others read. Secret-sourcing is a property of *your* environment, not the project. So split it:

- **Committed, generic `.envrc`** (safe for anyone) — loads the toolchain, includes the personal layer, and *documents + guards* the required vars (this replaces a separate `.env.example`):
  ```bash
  use flake
  source_env_if_exists .envrc.local                  # personal secret wiring, gitignored
  # contract: required vars (non-fatal nudge if a collaborator hasn't supplied them)
  [ -n "$TF_VAR_hcloud_token" ] || log_status "TF_VAR_hcloud_token unset — create .envrc.local"
  ```
  `log_status` prints a `direnv:` line that the `log_filter` won't mute, so a collaborator without `.envrc.local` gets a precise nudge instead of silently-empty vars; you (who have it) see nothing.
- **Gitignored `.envrc.local`** (your machines only) — the actual `bao kv get` / token wiring. Globally ignored (`programs.git.ignores = [ … ".envrc.local" ]`), so it can never be committed.
- Document the *contract* — which env vars the project needs — in a comment or `.env.example`, not the values or paths.

Audience rule: **org-internal repo** → fine to commit the `bao` `.envrc` (all collaborators authed + can reach Bao). **Customer / external / public repo** → use the split; only `flake.nix` + the generic `.envrc` travel.

## Multi-account git (SSH aliases + per-context routing)

To push as different accounts — including two on the same host (e.g. a personal + a client GitHub):
- **One SSH key per account, per device** (`~/.ssh/id_<alias>`), enrolled on that account (public half only). Private keys never leave the device, never go in Bao.
- **`~/.ssh/config` host aliases** (home-manager `programs.ssh.matchBlocks`): `github-<acct>`, `github-<client>`, … each `HostName github.com` with its own `IdentityFile`.
- **Per-context `includeIf`** (`git.nix`) sets identity *and* routes the repo through its account's alias:
  ```nix
  url."git@github-<acct>:".insteadOf = "https://github.com/";   # host-only prefix → owner/repo path preserved
  ```
- **Cloning** a private/org repo: use the alias URL explicitly (`git clone git@github-<acct>:owner/repo.git`) — the `insteadOf` rewrite is gitdir-scoped and doesn't apply when cloning from outside the repo.
- **First connect to a new/self-hosted host:** `ssh -T` returning *"Host key verification failed"* is **not** an auth error — connect once interactively, verify the fingerprint, and accept it into `~/.ssh/known_hosts`. Non-standard SSH port → put `port = …;` in the alias.
- **Test recipe:** `git config user.email` · `ssh -T git@<alias>` (→ "Hi <account>!") · `git ls-remote --get-url` (shows the rewritten URL) · `git ls-remote` (fetch over the key).

## Troubleshooting quick-reference

| Symptom | Cause | Fix |
|---|---|---|
| `.envrc` set but `$VAR` empty | hook not in this (old) shell | open a NEW terminal; `type -t _direnv_hook` |
| `switch`: "file would be clobbered" | real dotfile in the way | re-run with `-b backup` |
| `git.userName` deprecation warning | old schema | use `programs.git.settings` |
| pkg "marked as insecure" | EOL version | supported version, or pin older nixpkgs |
| `bao` → 127.0.0.1:8200 refused | `BAO_ADDR` unset | export it / `home.sessionVariables` |
| Bao fetch empty after a while | token TTL expired | `bao login` again |
| `includeIf` identity ignored | stale `~/.gitconfig` shadows XDG config | `mv ~/.gitconfig ~/.gitconfig.pre-nix`; `git config --show-origin` |
| commit succeeds with the *wrong* identity | a global default catches everything | drop the global default; `useConfigOnly = true` + scoped rules (fail loud) |
| `dig` NXDOMAIN but curl works | `dig` ignores `/etc/resolver` | use `dscacheutil`/`curl` |
| internal names won't resolve | mesh/VPN split-DNS not applied | create `/etc/resolver/<domain>` |
| direnv log noise persists | env var ignored | `~/.config/direnv/direnv.toml` |
| env var lost in new shell | per-shell, not declared | put it in home-manager |
| `home-manager: USER: unbound variable` | non-login/container shell doesn't export `USER` | `export USER="${USER:-$(id -un)}"` in the bootstrap |
| `use flake` works on Mac, fails in Linux machine | flake hardcodes `aarch64-darwin` | make it `eachDefaultSystem` (multi-system) |
| `Path 'flake.nix' … is not tracked by Git` | flake files untracked inside a git repo | `git add flake.nix .envrc` — Nix ignores untracked files (commit them so the toolchain travels) |
| `Host key verification failed` on first push | new/self-hosted host key not trusted yet | connect once interactively, verify fingerprint, accept into `known_hosts` |
| clone of private/org repo → "Repository not found" | cloned over HTTPS / wrong owner; `url.insteadOf` is gitdir-scoped so it doesn't apply when cloning from the parent dir | clone via the SSH-alias URL: `git clone git@<alias>:<org>/<repo>.git`; check owner is the **org**, not the user |
| permalink/config errors on `hugo` build | site uses tokens removed in a newer Hugo (e.g. `:filename` removed in 0.144) | per-site flake pinning an older Hugo via a pinned nixpkgs commit |

---

## The golden rules
1. **New shell after every `switch`** (config reaches new shells only).
2. **A var/tool you want everywhere → declare it in the flake**, never a manual `export`/`brew install`.
3. **Secrets come from OpenBao at runtime**, never committed; clean up `*.backup` / `*.pre-nix` leftovers.
4. **Stale legacy dotfiles silently shadow managed ones** (`.profile`, `.gitconfig`) — retire them.
5. **Edit → switch → new shell → verify; rollback if bad.**
