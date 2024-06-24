{
  nixConfig.extra-substituers = ["https://kasuboski-feedreader.cachix.org"];
  nixConfig.extra-trusted-public-keys = ["kasuboski-feedreader.cachix.org-1:3wVuiH3ORfbrJrfU0uk8p/71wrPvYwpILEfxIEIJgoU="];
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };
  };
  outputs = {
    self,
    nixpkgs,
    flake-utils,
    rust-overlay,
  } @ inputs:
    flake-utils.lib.eachDefaultSystem
    (
      system: let
        overlays = [(import rust-overlay)];
        pkgs = import nixpkgs {
          inherit system overlays;
        };
        rustToolchain = pkgs.pkgsBuildHost.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
        goPlatforms = ["linux-amd64" "linux-arm64"];
        repo = "ghcr.io/kasuboski/feedreader";
        craneImageNames = builtins.map (arch: ''-m "${repo}:$TAG-${arch}"'') goPlatforms;
        combineImages = pkgs.writeShellApplication {
          name = "combine-images";

          runtimeInputs = [pkgs.crane pkgs.git];

          text = ''
            TAG=''${CI_SHORT_SHA:="$(git rev-parse --short=8 HEAD)"}
            crane index append -t "${repo}:$TAG" ${builtins.concatStringsSep " " craneImageNames}
          '';
        };
      in {
        formatter = pkgs.alejandra;
        devShells.default = pkgs.mkShell {
          # instead of passing `buildInputs` / `nativeBuildInputs`,
          # we refer to an existing derivation here
          buildInputs = [] ++ pkgs.lib.optional pkgs.stdenv.isDarwin [pkgs.libiconv pkgs.darwin.apple_sdk.frameworks.Security];
          packages = with pkgs; [
            just
            rustToolchain
            cargo-nextest
            turso-cli

            combineImages

            # github actions
            act
            actionlint

            # image stuff
            earthly
            pkgs.crane
            dive
            docker
            skopeo
          ];
        };
      }
    );
}
