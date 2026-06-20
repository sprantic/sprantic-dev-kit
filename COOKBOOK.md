# Project Cookbook — what goes where

The reference the skills follow. Mental model: **flake = locked recipe card · `.envrc` = note on the folder door · direnv walks upward (parent settings cascade down) · OpenBao = secrets · git syncs code · Nix syncs the env.**

## What goes where (the one table)

| Thing | Lives at | Committed? |
|---|---|---|
| **Toolchain** (`flake.nix` + `flake.lock`) | the project dir, **or** the group dir if shared | ✅ commit |
| **Generic `.envrc`** (`use flake` + `source_env_if_exists .envrc.local` + guards) | project (or group) dir | ✅ commit |
| **`.envrc.local`** (your `bao kv get` / token wiring) | project/group dir | ❌ globally gitignored |
| **Git identity rule** (`includeIf`) | `env/home/git.nix` (keyed to the project/group gitdir) | ✅ commit to env repo |
| **SSH account alias** (`matchBlocks`) | `env/home/ssh.nix` (one per account) | ✅ commit to env repo |
| **SSH private key** (`~/.ssh/id_<alias>`) | `~/.ssh/` on each device | ❌ never — per-device, never synced/vaulted |
| **Secrets** (API tokens) | OpenBao | ❌ never in a repo |
| **Public keys** | GitHub/GitLab account, or the server (tofu input) | ❌ not Bao (public ≠ secret) |
| **`.direnv/`, `result`** | nowhere — global gitignore | ❌ ignored |

## Values: one fact, one home
Classify every *value* once — this is what keeps it from sprawling across files:
- **Secret** (token, password, access/secret key) → **OpenBao**, and *only* secrets go here.
- **Non-secret config** (sizes, regions, endpoints, bucket/repo names, public keys) → **committed** in the project that uses it (`variables.tf` defaults for Tofu; compose defaults / `.env` literals for apps).
- **A secret shared across a customer's projects** → **one** Bao section (e.g. `customers/<name>/s3`), read by each.

The `.envrc` files **store no values**: `.envrc` orchestrates (`use flake`), `.envrc.local` is a *fetch-and-rename map* (`bao kv get … → TF_VAR_x`/`AWS_x`). So a value never lives in two places — you edit config in the committed file and secrets in Bao; the plumbing just wires them together. **Don't put non-secret config in Bao** (that's the sprawl trap).

## 1. Layout — where the repo goes
`~/projects/<group>/<repo>`. Pick the group:
- **websites** → `~/projects/websites/` (shared Hugo kit; sites inherit it)
- **a customer** → `~/projects/<customer>/` (its own group; per-customer cascade)
- **internal** → `~/projects/internal/` (your own stuff)

Shared toolchain → put `flake.nix`+`.envrc` at the **group** level; sites/projects inherit by sitting under it (direnv walks up). A project that differs **overrides** (its own `flake.nix`/`.envrc`, nearest wins) or **extends** (`source_up`).

**Multi-project customers** → group by customer: `~/projects/<customer>/{website,infra,cms,…}`. The customer *context* binds via **one `includeIf` keyed to the whole `~/projects/<customer>/` dir** (identity for every sub-project) + **one reused SSH alias** + **one shared Bao namespace `customers/<name>/`**; colocation just adds the convenience cascade. Reserve `websites/` for true one-off standalone sites.

## 2. Toolchain — pick a stack template (`templates/flake.<stack>.nix`)
| Stack | Packages (starting point) |
|---|---|
| **website** | `hugo` (+ `go` for Hugo Modules, + `nodejs` for asset pipeline) |
| **go** | `go`, `gopls`, `golangci-lint` |
| **node** | `nodejs_22`, `pnpm` (or `nodejs_20` if required) |
| **python** | `python3`, `uv` |
| **tofu/infra** | `opentofu` (providers come via `tofu init`) |

All templates are `eachDefaultSystem` → work on macOS *and* the Linux machine. Need an **older** version (e.g. a Hugo that still has `:filename`)? → the **pin-tool** skill.

## 3. `.envrc` — the committed contract (`templates/envrc`)
```bash
use flake
source_env_if_exists .envrc.local
[ -n "$REQUIRED_VAR" ] || log_status "REQUIRED_VAR unset — create .envrc.local"
```
Generic + self-documenting + self-guarding. Replaces `.env.example`. **Org-internal-only** repos *may* instead put `bao kv get` directly in `.envrc`; **customer/public** repos must use the split (above).

## 4. `.envrc.local` — personal secret wiring (`templates/envrc.local`, gitignored)
```bash
export TF_VAR_hcloud_token="$(bao kv get -field=hcloud_token customers/<name>/infra)"
```

## 5. Git identity + account (`env/home/git.nix`)
```nix
{ condition = "gitdir:~/projects/<group>/<repo>/";
  contents = {
    user = { name = "<Name>"; email = "<email>"; };
    url."git@<alias>:".insteadOf = "https://github.com/";  # only if a distinct account
  }; }
```

## 6. SSH account alias (`env/home/ssh.nix`) — one per account
```nix
"github-<acct>" = { hostname = "github.com"; user = "git"; identityFile = "~/.ssh/id_github_<acct>"; identitiesOnly = true; };
```
Key: `ssh-keygen -t ed25519 -f ~/.ssh/id_github_<acct> -C "<acct>@$(hostname -s)"`, enroll the `.pub` on that account. **Clone via the alias** (`git clone git@github-<acct>:<owner>/<repo>.git`) — `insteadOf` doesn't apply when cloning from the parent dir.

## 7. Secrets — OpenBao paths
- **shared infra** → `infra/<service>`
- **customer** → `customers/<name>/<thing>`
- **personal** → `personal/<you>/<thing>`
```bash
bao kv put customers/<name>/infra hcloud_token=<…>
```

> 🔑 **ROTATE anything that was ever in cleartext.** If the value came from an old `project.json`/`.env`/`.profile`, a committed file, or shell history, it is **compromised** — regenerate it at the source and vault the **new** value. Copying the old value into Bao does *not* un-leak it. Then scrub the old copies. → **rotate-secrets** skill. A migration isn't done while a leaked secret is still live.

## 8. Apply + verify
```bash
cd ~/projects/env && ./bootstrap.sh        # apply git/ssh changes
cd <project> && direnv allow               # approve the .envrc
```
Then the 4-layer check (the **project-doctor** skill): `git config user.email` · `ssh -T git@<alias>` · `git ls-remote --get-url` · `git ls-remote` (+ `nix develop -c <tool> --version`).

## 9. OpenTofu / infra projects
- **Values split by sensitivity.** `sensitive = true` vars (tokens/keys) → `TF_VAR_*` from `.envrc.local` (OpenBao); **never** a committed `tfvars`. Non-secret config (sizes, regions, names, public keys) → **committed**: `variable` *defaults* in `variables.tf` (repos often `.gitignore` all `*.tfvars`) or a committed `*.auto.tfvars`. The `variables.tf` *declarations* always stay.
- **State backend by repo host.** GitLab-hosted repos → **GitLab-managed state** (the integration). **GitHub / external repos → an S3-compatible backend** (e.g. Hetzner, Backblaze B2, MinIO: `endpoints.s3` + `use_path_style` + `use_lockfile`, skip the AWS-isms; creds via `AWS_ACCESS_KEY_ID/SECRET` from Bao). The state bucket is created **manually** — it can't be a bucket the same config manages (chicken-and-egg). Backend blocks can't use variables, so endpoint/bucket/region are literals (non-secret).
- **Shared secrets across a customer group → one Bao path** (e.g. `customers/<name>/s3`), referenced by every consumer (tofu provider, state backend, app) under its own var name — single source, no drift.
- **Server replaces.** Persistent data belongs on a **separate volume** (survives VM re-create) + an **offsite backup** (S3); content lives in Git. Before an apply that replaces a server, confirm the **volume isn't also replaced** (only a `location` change ForceNew's a volume) and take a fresh backup first.
