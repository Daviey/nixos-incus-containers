{ nixpkgs }:
let
  system = "x86_64-linux";
  lib = nixpkgs.lib;

  makeHelperApps = {
    pkgs,
    containerName,
    flakeOutPath,
    nixosConfiguration ? null,
    sshKeys ? [],
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

      # Deploy using flake reference (for now, keeping it simple)
      remote_root=${remoteRoot}

      # Create a minimal scoped flake that just imports the configuration
      sshKeysList="[${builtins.concatStringsSep " " (map (key: ''"${key}"'') sshKeys)}]"
      minimal_flake="$(cat << FLAKE_EOF
{
  description = "Container flake for ${containerName}";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.nixos-incus-containers = {
    url = "github:Daviey/nixos-incus-containers";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = { nixpkgs, nixos-incus-containers, ... }: {
    nixosConfigurations.${containerName} = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixos-incus-containers.nixosModules.incus-container
        {
          incus.container.enable = true;
          networking.hostName = "${containerName}";

          # SSH access with provided keys
          users.users.root.openssh.authorizedKeys.keys = $sshKeysList;

          # Basic nginx hello world
          services.nginx = {
            enable = true;
            virtualHosts."localhost" = {
              listen = [{ addr = "0.0.0.0"; port = 8080; }];
              locations."/" = {
                return = "200 \"<!DOCTYPE html><html><head><title>Hello World Container</title></head><body><h1>Hello from NixOS Incus Container!</h1><p>Container: ${containerName}</p></body></html>\"";
                extraConfig = "add_header Content-Type text/html;";
              };
            };
          };
          networking.firewall.allowedTCPPorts = [ 8080 ];
          system.stateVersion = "25.05";
        }
      ];
    };
  };
}
FLAKE_EOF
)"

      incus exec "$instance" -- rm -rf "$remote_root"
      incus exec "$instance" -- mkdir -p "$remote_root"
      echo "$minimal_flake" | incus file push - "$instance$remote_root/flake.nix"

      incus exec "$instance" -- nixos-rebuild switch \
        --option experimental-features "nix-command flakes" \
        --flake "$remote_root#${containerName}"

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
      echo "  incus exec $instance -- nixos-rebuild switch --option experimental-features \"nix-command flakes\" --flake $remote_root#${containerName}"
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