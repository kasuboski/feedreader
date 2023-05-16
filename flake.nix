{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };
    crane = {
      url = "github:ipetkov/crane";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        rust-overlay.follows = "rust-overlay";
        flake-utils.follows = "flake-utils";
      };
    };
  };
  outputs = {
    self,
    nixpkgs,
    flake-utils,
    rust-overlay,
    crane,
  } @ inputs:
    flake-utils.lib.eachDefaultSystem
    (
      system: let
        overlays = [(import rust-overlay)];
        pkgs = import nixpkgs {
          inherit system overlays;
        };
        build = pkgs.callPackage ./cross.nix {
          inherit nixpkgs crane flake-utils rust-overlay;
        };
        bin = build.packages.${system}.default;
        x86cross =
          build
          .packages
          .x86_64-linux
          .bin;
        aarch64cross =
          build
          .packages
          .aarch64-linux
          .bin;
        image = pkgs.dockerTools.streamLayeredImage {
          name = "feedreader";
          contents = [pkgs.sqlite];
          config = {
            Cmd = ["${bin}/bin/feedreader"];
          };
        };
      in {
        formatter = pkgs.alejandra;
        packages = {
          # that way we can build `bin` specifically,
          # but it's also the default.
          inherit bin x86cross aarch64cross image;
          default = bin;
        };
        apps = rec {
          default = feedreader;
          feedreader = flake-utils.lib.mkApp {drv = self.packages.${system}.default;};
        };
        devShells.default = pkgs.mkShell {
          # instead of passing `buildInputs` / `nativeBuildInputs`,
          # we refer to an existing derivation here
          inputsFrom = [bin];
          buildInputs = with pkgs; [
            dive
            docker
          ];
        };
      }
    );
}
