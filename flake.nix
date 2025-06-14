{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    systems.url = "github:nix-systems/default";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = {
    self,
    nixpkgs,
    systems,
    fenix,
  }: let
    inherit (nixpkgs) lib;
    minimalShell = {
      lib,
      pkgs,
      system,
      packages ? [],
      shellHook ? "",
    }: let
      inherit (lib) getBin;
      inherit (pkgs) writeTextFile bashInteractive;
      bashPath = "${getBin bashInteractive}/bin/bash";
    in
      derivation {
        inherit system packages;
        name = "minimal-shell";
        builder = bashPath;
        args = ["-ec" "touch $out; exit 0"];
        stdenv = writeTextFile {
          name = "stdenv";
          destination = "/setup";
          text = ''
            : ''${outputs:=out}
            unset PATH
            for package in $packages; do
              [ -d "$package/bin" ] && PATH=$package/bin''${PATH:+:''${PATH}}
            done
            unset packages
            runHook() {
              eval "$shellHook"
              unset runHook shellHook
            }
          '';
        };
        shellHook = ''
          #!${bashPath}
          set -euo pipefail

          unset NIX_BUILD_TOP NIX_BUILD_CORES NIX_STORE TEMP TEMPDIR TMP TMPDIR
          unset name builder out shellHook stdenv system dontAddDisableDepTrack outputs

          if [[ "$SHELL" == "/noshell" || "$SHELL" == "/sbin/nologin" ]]; then
            export SHELL="${bashPath}"
          fi

          ${shellHook}
        '';
      };
    eachSystem = f:
      lib.genAttrs (import systems) (system:
        f (import nixpkgs {
          inherit system;
          overlays = [
            fenix.overlays.default
          ];
        }));
    formatter = eachSystem (pkgs: let
      inherit (pkgs) alejandra treefmt;
    in
      treefmt.withConfig {
        settings = {
          on-unmatched = "info";

          formatter = {
            alejandra = {
              command = "${alejandra}/bin/alejandra";
              includes = ["*.nix"];
            };
          };
        };
      });
    devShells = eachSystem (pkgs: let
      inherit (pkgs) callPackage clang pkg-config libiconv;
      inherit (pkgs.fenix.stable) rustc rust-src cargo clippy;
      inherit (pkgs.fenix.complete) rustfmt;
    in {
      default = let
        inherit (pkgs.fenix.stable) rustc rust-src cargo clippy;
        inherit (pkgs.fenix.complete) rustfmt;
      in
        callPackage minimalShell {
          packages = [
            pkg-config
            clang
            rustc
            cargo
            clippy
            rustfmt
          ];
          shellHook = ''
            export LIBRARY_PATH="${lib.makeLibraryPath [libiconv]}''${LIBRARY_PATH:+:''${LIBRARY_PATH}}";
            export RUST_SRC_PATH="${rust-src}/lib/rustlib/src/rust/library"
          '';
        };
      nightly = let
        inherit (pkgs.fenix.complete) rustc rust-src cargo clippy rustfmt;
      in
        callPackage minimalShell {
          packages = [
            pkg-config
            clang
            rustc
            cargo
            clippy
            rustfmt
          ];
          shellHook = ''
            export LIBRARY_PATH="${lib.makeLibraryPath [libiconv]}''${LIBRARY_PATH:+:''${LIBRARY_PATH}}";
            export RUST_SRC_PATH="${rust-src}/lib/rustlib/src/rust/library"
          '';
        };
    });
  in {
    inherit devShells formatter;
    lib = {inherit minimalShell;};
  };
}
