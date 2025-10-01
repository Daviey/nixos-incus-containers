{ nixpkgs }:
let
  system = "x86_64-linux";
  lib = nixpkgs.lib;

  makeHelperApps = {
    pkgs,
    containerName,
    flakeOutPath,
    imageRemote ? "images",
    imagePath ? "nixos/unstable",
    remoteRoot ? "/root/${containerName}-flake",
  }:
  let
    mkScript = name: text:
      pkgs.writeShellApplication {
        inherit name text;
        runtimeInputs = [ pkgs.incus pkgs.coreutils pkgs.util-linux pkgs.gnugrep pkgs.gawk ];
      };

    importScript = mkScript "incus-${containerName}-import" ''
      set -euo pipefail

      alias=${containerName}
      if [ "$#" -ge 1 ]; then
        alias="$1"
        shift
      fi

      if ! incus remote list --format=csv | grep -q "^${imageRemote},"; then
        incus remote add ${imageRemote} https://images.linuxcontainers.org --protocol=simplestreams --public
      fi

      existing=$(incus image alias list --format=csv | awk -F, -v n="$alias" '$1 == n { print $2 }')
      if [ -n "$existing" ]; then
        incus image alias delete "$alias"
        incus image delete "$existing" || true
      fi

      incus image copy ${imageRemote}:${imagePath} local: --alias "$alias" "$@"
    '';

    deleteScript = mkScript "incus-${containerName}-delete" ''
      set -euo pipefail

      instance=${containerName}
      if [ "$#" -ge 1 ]; then
        instance="$1"
        shift
      fi

      if incus info "$instance" >/dev/null 2>&1; then
        incus stop "$instance" --force >/dev/null 2>&1 || true
        incus delete "$instance"
      else
        echo "Container $instance not found" >&2
      fi
    '';

    launchScript = mkScript "incus-${containerName}-launch" ''
      set -euo pipefail

      instance=${containerName}
      if [ "$#" -ge 1 ]; then
        instance="$1"
        shift
      fi

      alias=${containerName}
      if [ "$#" -ge 1 ]; then
        alias="$1"
        shift
      fi

      if ! incus remote list --format=csv | grep -q "^${imageRemote},"; then
        incus remote add ${imageRemote} https://images.linuxcontainers.org --protocol=simplestreams --public
      fi

      if ! incus image show "$alias" >/dev/null 2>&1; then
        ${importScript}/bin/incus-${containerName}-import "$alias"
      fi

      if incus info "$instance" >/dev/null 2>&1; then
        echo "Container $instance already exists" >&2
        exit 1
      fi

      incus launch "$alias" "$instance" --config security.nesting=true "$@"

      for _ in $(seq 1 20); do
        if incus exec "$instance" -- true >/dev/null 2>&1; then
          break
        fi
        sleep 2
      done

      remote_root=${remoteRoot}
      remote_flake=${remoteRoot}/$(basename ${flakeOutPath})

      incus exec "$instance" -- rm -rf "$remote_root"
      incus exec "$instance" -- mkdir -p "$remote_root"
      incus file push -p -r ${flakeOutPath} "$instance$remote_root"

      incus exec "$instance" -- nixos-rebuild switch \
        --option experimental-features "nix-command flakes" \
        --flake "$remote_flake#${containerName}"

      ip=""
      for _ in $(seq 1 20); do
        ip=$(incus list "$instance" --format=csv | awk -F, 'NR==1 {print $3}' | cut -d' ' -f1)
        if [ -n "$ip" ] && [ "$ip" != "<nil>" ]; then
          break
        fi
        sleep 2
      done

      if [ -z "$ip" ] || [ "$ip" = "<nil>" ]; then
        echo "Launched $instance but could not determine IP" >&2
        ${deleteScript}/bin/incus-${containerName}-delete "$instance"
        exit 1
      fi

      echo "Container $instance is up at $ip"
      echo "To redeploy:"
      echo "  incus exec $instance -- nixos-rebuild switch --option experimental-features \"nix-command flakes\" --flake $remote_flake#${containerName}"
    '';

  in
  {
    "incus-${containerName}-import" = {
      type = "app";
      program = "${importScript}/bin/incus-${containerName}-import";
    };
    "incus-${containerName}-launch" = {
      type = "app";
      program = "${launchScript}/bin/incus-${containerName}-launch";
    };
    "incus-${containerName}-delete" = {
      type = "app";
      program = "${deleteScript}/bin/incus-${containerName}-delete";
    };
  };

  makeIncusHost = {
    name,
    modules,
    system ? "x86_64-linux",
  }:
  nixpkgs.lib.nixosSystem {
    inherit system;
    modules = modules ++ [
      (import ./modules/incus-container.nix)
      { incus.container.enable = true; }
    ];
  };

in
{
  inherit makeIncusHost makeHelperApps;
}