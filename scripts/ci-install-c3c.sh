#!/bin/sh
set -eu

platform=$1
if [ "$platform" = macos-x86_64 ]; then
    nix build --impure --no-link --print-out-paths --expr '
      let
        pkgs = import (builtins.getFlake
          "github:NixOS/nixpkgs/0c32f40fe3e2a9adfc427fd5abc061a31043ea44").outPath {
          system = builtins.currentSystem;
        };
      in pkgs.c3c.overrideAttrs (_: {
        version = "0.8.4";
        src = pkgs.fetchFromGitHub {
          owner = "c3lang";
          repo = "c3c";
          tag = "v0.8.4";
          hash = "sha256-SuG27bZAnvtlZQHbrgZKufXawok5f3ePNU7fwmnVaqU=";
        };
      })'
else
    nix build --no-link --print-out-paths "${NIXPKGS_REF}#c3c"
fi
