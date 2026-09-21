#!/bin/sh
set -eu

platform=$1
case "$platform" in
    linux-aarch64|macos-aarch64)
        nixpkgs_ref=${NIXPKGS_REF:?NIXPKGS_REF must be set}
        case "$platform" in
            linux-aarch64) nix_system=aarch64-linux ;;
            macos-aarch64) nix_system=aarch64-darwin ;;
        esac
        ;;
    macos-x86_64)
        nixpkgs_ref=github:NixOS/nixpkgs/0c32f40fe3e2a9adfc427fd5abc061a31043ea44
        nix_system=x86_64-darwin
        ;;
    *)
        echo "unsupported CI compiler platform: $platform" >&2
        exit 2
        ;;
esac

repository=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
lock_file=$repository/examples/sqlite-example/.c3pm/nix/flake.lock
test -f "$lock_file"
export C3PM_CI_C3C_LOCK_FILE="$lock_file"
export C3PM_CI_NIXPKGS_REF="$nixpkgs_ref"
export C3PM_CI_C3_VERSION="${C3_VERSION:?C3_VERSION must be set}"

# Match c3pm's generated selectC3c recipe, including its locked source tree.
# Merely requesting the same version from nixpkgs produces a different derivation.
# shellcheck disable=SC2016
expression='
  let
    lock = builtins.fromJSON (builtins.readFile (builtins.getEnv "C3PM_CI_C3C_LOCK_FILE"));
    source = lock.nodes.c3c-source.locked;
    version = builtins.getEnv "C3PM_CI_C3_VERSION";
    c3cSource = (builtins.fetchTree {
      inherit (source) owner repo rev narHash;
      type = source.type;
    }).outPath;
    pkgs = import (builtins.getFlake
      (builtins.getEnv "C3PM_CI_NIXPKGS_REF")).outPath {
        system = builtins.currentSystem;
      };
  in
    if lock.nodes.c3c-source.original.ref != "v${version}" then
      throw "CI C3 version does not match the example flake lock"
    else pkgs.c3c.overrideAttrs (_: {
      inherit version;
      src = c3cSource;
    })'

if [ "${C3PM_CI_EVAL_DERIVATION:-}" = 1 ]; then
    nix eval --raw --impure --system "$nix_system" --expr "($expression).drvPath"
else
    nix build --impure --no-link --print-out-paths --expr "$expression"
fi
