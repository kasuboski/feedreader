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
        build = pkgs.callPackage ./default.nix {
          inherit nixpkgs crane flake-utils rust-overlay;
        };
        crossArchs = builtins.listToAttrs (builtins.map (arch: {
          name = "${arch}-cross";
          value = build.packages.${arch}.bin;
        }) ["x86_64-linux" "aarch64-linux"]);
        name = "feedreader";
        bin = build.packages.${system}.default;
        buildImage = arch: {
          dockerTools,
          callPackage,
          cmd,
        }:
          dockerTools.streamLayeredImage {
            inherit name;
            tag = "build-${arch}";
            contents = [pkgs.sqlite];
            config = {Cmd = [cmd];};
          };
        images = builtins.listToAttrs (builtins.map (arch: let lookup = "${arch}-cross"; in {
          name = "image-${arch}";
          value = pkgs.callPackage (buildImage arch) {cmd = crossArchs.${lookup};};
        }) ["x86_64-linux" "aarch64-linux"]);
        image = pkgs.dockerTools.streamLayeredImage {
          inherit name;
          contents = [pkgs.sqlite];
          config = {
            Cmd = ["${bin}/bin/feedreader"];
          };
        };
      in {
        formatter = pkgs.alejandra;
        packages =
          {
            # that way we can build `bin` specifically,
            # but it's also the default.
            inherit bin image;
            default = bin;
          }
          // crossArchs
          // images;
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
