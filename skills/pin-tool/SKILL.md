---
name: pin-tool
description: Pin an older or specific version of a tool in a project's Nix devShell when the current one breaks the build — e.g. a Hugo that still supports a removed permalink token, an older Node, a specific Go. Use when a build fails because a tool removed/changed a feature, or the user asks to pin/downgrade a tool version for a project.
---

# pin-tool — pin a specific tool version via a nixpkgs commit

When a project needs a tool version different from current nixpkgs (usually OLDER, because a feature was removed):

1. **Find the version + nixpkgs commit** that packages it — `https://www.nixhub.io/packages/<tool>` or `https://lazamar.co.uk/nix-versions/?package=<tool>`. Note the exact commit hash.
2. **Add a second pinned input** and use it for just that package:
   ```nix
   inputs.nixpkgs.url     = "github:NixOS/nixpkgs/nixpkgs-unstable";
   inputs.nixpkgs-pin.url = "github:NixOS/nixpkgs/<commit-with-the-version>";
   # in the per-system let: pinned = nixpkgs-pin.legacyPackages.${system};
   #   packages = [ pinned.hugo  pkgs.go ... ];   # old tool from the pin, rest from current
   ```
   (Or pin the whole devShell's nixpkgs if the project wants one consistent old snapshot.)
3. **Don't disable safety** (`NIXPKGS_ALLOW_INSECURE`) unless truly unavoidable — pin a snapshot from before the tool was flagged instead.
4. `git add flake.nix flake.lock`, `direnv reload` / `nix develop`, confirm the version.

Worked precedent: a Hugo site using the `:filename` permalink token (removed in 0.144.0) → pinned Hugo **0.143.1** via nixpkgs commit `2d068ae5c6516b2d04562de50a58c682540de9bf`.
