{
  nixConfig.extra-substituers = ["https://kasuboski-feedreader.cachix.org"];
  nixConfig.extra-trusted-public-keys = ["kasuboski-feedreader.cachix.org-1:3wVuiH3ORfbrJrfU0uk8p/71wrPvYwpILEfxIEIJgoU="];
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
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
        supportedArches = ["x86_64-linux" "aarch64-linux"];
        crossArchs = builtins.listToAttrs (builtins.map (arch: {
            name = "${arch}-bin";
            value = build.packages.${arch}.bin;
          })
          supportedArches);
        name = "feedreader";
        bin = build.packages.${system}.default;
        buildImage = arch: {
          dockerTools,
          cmd,
        }:
          dockerTools.streamLayeredImage {
            inherit name;
            tag = "build-${arch}";
            contents = [pkgs.sqlite];
            config = {Cmd = [cmd];};
          };
        images = builtins.listToAttrs (builtins.map (arch: let
            target = "${pkgs.lib.strings.removeSuffix "-linux" arch}-unknown-linux-gnu";
          in {
            name = "image-${arch}";
            value = pkgs.callPackage (buildImage arch) {cmd = ./target/${target}/release/feedreader;};
          })
          supportedArches);
        image = images."image-${system}";
        repo = "ghcr.io/kasuboski/feedreader";
        baseTag = "nix";
        pushImageFunc = image:
          pkgs.writeShellApplication {
            name = "push-image";

            runtimeInputs = [pkgs.skopeo];

            text = ''
              BASE_TAG=''${CI_SHORT_SHA:="${baseTag}"}
              ${image} | skopeo --insecure-policy copy docker-archive:///dev/stdin "docker://${repo}:$BASE_TAG-${pkgs.lib.strings.removePrefix "build-" image.imageTag}"
            '';
          };
        pushImage = pushImages."pushImage-${system}";
        pushImages = builtins.listToAttrs (builtins.map (arch: let
            lookup = "image-${arch}";
          in {
            name = "pushImage-${arch}";
            value = pushImageFunc images.${lookup};
          })
          supportedArches);
        craneImageNames = builtins.map (arch: ''-m "${repo}:''${CI_SHORT_SHA:-${baseTag}}-${arch}"'') supportedArches;
        combineImages = pkgs.writeShellApplication {
          name = "combine-images";

          runtimeInputs = [pkgs.crane];

          text = ''
            TAG=''${CI_SHORT_SHA:="${baseTag}"}
            crane index append -t "${repo}:$TAG" ${builtins.concatStringsSep " " craneImageNames}
          '';
        };
      in {
        formatter = pkgs.alejandra;
        packages =
          {
            # that way we can build `bin` specifically,
            # but it's also the default.
            inherit bin image pushImage combineImages;
            default = bin;
          }
          // crossArchs
          // images
          // pushImages;
        apps = rec {
          default = feedreader;
          feedreader = flake-utils.lib.mkApp {drv = self.packages.${system}.default;};
        };
        devShells.default = pkgs.mkShell {
          # instead of passing `buildInputs` / `nativeBuildInputs`,
          # we refer to an existing derivation here
          inputsFrom = [bin];
          packages = with pkgs; [
            just
            turso-cli
            rustup

            # github actions
            act
            actionlint

            # image stuff
            pkgs.crane
            dive
            docker
            skopeo
          ];
        };
      }
    );
}
