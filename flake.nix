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
  }@inputs:
    flake-utils.lib.eachDefaultSystem
    (
      system: let
        overlays = [(import rust-overlay)];
        pkgs = import nixpkgs {
          inherit system overlays;
        };
        rustToolchain = pkgs.pkgsBuildHost.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
        # this is how we can tell crane to use our toolchain!
        craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;
        additionalFilter = path: _type: builtins.match ".*html$|.*opml$" path != null;
        # https://crane.dev/API.html#cranelibfiltercargosources
        src = nixpkgs.lib.cleanSourceWith {
          src = craneLib.path ./.;
          filter = path: type: (additionalFilter path type) || (craneLib.filterCargoSources path type);
        };
        # buildCross = crossSystem: let
        #   crossPkgs = import nixpkgs {
        #     inherit crossSystem;
        #     localSystem = system;
        #     inherit overlays;
        #   };
        #   commonCross =
        #     commonArgs
        #     // {
        #       cargoExtraArgs = "--target x86_64-unknown-linux-gnu";
        #       CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER = "${crossPkgs.stdenv.cc.targetPrefix}cc";
        #       CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_RUNNER = "qemu-x86_64";
        #       HOST_CC = "${crossPkgs.stdenv.cc.nativePrefix}cc";
        #       TARGET_CC = "${crossPkgs.stdenv.cc.targetPrefix}cc";
        #     };
        # in {
        #   cargoArtifacts = craneLib.buildDepsOnly commonCross;

        #   bin = craneLib.buildPackage (commonCross
        #     // {
        #       inherit cargoArtifacts;
        #     });
        # };
        nativeBuildInputs = with pkgs; [rustToolchain pkg-config];
        buildInputs = with pkgs; [openssl sqlite];
        # because we'll use it for both `cargoArtifacts` and `bin`
        commonArgs = {
          inherit src buildInputs nativeBuildInputs;
        };
        cargoArtifacts = craneLib.buildDepsOnly commonArgs;
        bin = craneLib.buildPackage (commonArgs
          // {
            inherit cargoArtifacts;
          });
      in {
        formatter = pkgs.alejandra;
        packages = {
          # that way we can build `bin` specifically,
          # but it's also the default.
          inherit bin;
          default = bin;
          x86cross = (pkgs.callPackage ./cross.nix {
            inherit nixpkgs crane flake-utils rust-overlay;
            crossSystem = "x86_64-linux";
          }).packages.${system}.bin;
          aarch64cross = (pkgs.callPackage ./cross.nix {
            inherit nixpkgs crane flake-utils rust-overlay;
            crossSystem = "aarch64-linux";
          }).packages.${system}.bin;
        };
        apps = rec {
          default = feedreader;
          feedreader = flake-utils.lib.mkApp {drv = self.packages.${system}.default;};
        };
        devShells.default = pkgs.mkShell {
          # instead of passing `buildInputs` / `nativeBuildInputs`,
          # we refer to an existing derivation here
          inputsFrom = [bin];
        };
      }
    );
}