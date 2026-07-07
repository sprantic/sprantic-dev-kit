{ pkgs, ... }:
{
  # `repo` — cross-machine registry of git clones (see repo-registry.sh, COOKBOOK §10).
  # Copy both template files side by side into your env repo's home-manager tree;
  # builtins.readFile resolves relative to THIS file.
  home.packages = [
    (pkgs.writeShellApplication {
      name = "repo";
      runtimeInputs = with pkgs; [ git findutils gawk coreutils gnused ];
      text = builtins.readFile ./repo-registry.sh;
    })
  ];
}
