{ lib, config, modulesPath, pkgs, ... }:
{
  options.incus.container = {
    enable = lib.mkEnableOption "Incus container optimizations";

    basePackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with pkgs; [ git vim curl wget htop ];
      description = "Base packages to install in the container";
    };

    enableSSH = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable SSH service in the container";
    };
  };

  config = lib.mkIf config.incus.container.enable {
    imports = [
      (modulesPath + "/virtualisation/lxc-container.nix")
      (modulesPath + "/virtualisation/lxc-image-metadata.nix")
    ];

    boot.isContainer = true;

    networking.hostName = lib.mkDefault "incus-nixos";
    time.timeZone = lib.mkDefault "UTC";

    nix.settings.experimental-features = lib.mkBefore [
      "nix-command"
      "flakes"
    ];

    services.openssh = lib.mkIf config.incus.container.enableSSH {
      enable = lib.mkDefault true;
      startWhenNeeded = lib.mkDefault true;
    };

    environment.systemPackages = config.incus.container.basePackages;

    system.stateVersion = lib.mkDefault "25.05";
  };
}
