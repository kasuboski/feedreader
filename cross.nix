{ nixpkgs, crane, flake-utils, rust-overlay, system, crossSystem }:
  flake-utils.lib.eachDefaultSystem
    (
      system: let
        overlays = [(import rust-overlay)];
        pkgs = import nixpkgs {
            inherit crossSystem;
            localSystem = system;
            inherit overlays;
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
        nativeBuildInputs = with pkgs; [rustToolchain pkg-config];
        buildInputs = with pkgs; [openssl sqlite];
        # because we'll use it for both `cargoArtifacts` and `bin`
        archInfo = {
          x86_64-linux = {
            rustTarget = "x86_64-unknown-linux-gnu";
            qemu = "x86_64";
          };
          aarch64-linux = {
            rustTarget = "aarch64-unknown-linux-gnu";
            qemu = "aarch64";
          };
        };
        commonArgs = {
          inherit src buildInputs nativeBuildInputs;
          cargoExtraArgs = "--target ${archInfo.${crossSystem}.rustTarget}";
          CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER = "${pkgs.stdenv.cc.targetPrefix}cc";
          CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_RUNNER = "qemu-${archInfo.${crossSystem}.qemu}";
          HOST_CC = "${pkgs.stdenv.cc.nativePrefix}cc";
          TARGET_CC = "${pkgs.stdenv.cc.targetPrefix}cc"; 
        };
        cargoArtifacts = craneLib.buildDepsOnly commonArgs;
        bin = craneLib.buildPackage (commonArgs
          // {
            inherit cargoArtifacts;
          });
      in rec {
        packages = {
          # that way we can build `bin` specifically,
          # but it's also the default.
          inherit bin;
          default = bin;
        };
      }
    ) 