{
  description = "website — Hugo (extended)";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = nixpkgs.legacyPackages.${system};
      in {
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.hugo        # extended build (SCSS)
            # pkgs.go        # uncomment if the theme is a Hugo Module (go.mod present)
            # pkgs.nodejs_22 # uncomment if there's an npm asset pipeline (package.json present)
          ];
        };
      });
}
