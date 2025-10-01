# Incus NixOS Container Flake

A NixOS flake for managing Incus containers with proper module composition and helper applications.

## Features

- Standard NixOS module for Incus container configuration
- Configurable base packages and SSH settings
- Helper applications for container lifecycle management
- Composable with existing NixOS configurations

## Usage

### As a flake input

Add to your `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    incus-flake.url = "github:Daviey/incus-flake";
  };

  outputs = { nixpkgs, incus-flake, ... }: {
    nixosConfigurations.my-container = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        incus-flake.nixosModules.incus-container
        {
          incus.container.enable = true;
          networking.hostName = "my-container";

          # Customize packages
          incus.container.basePackages = with nixpkgs.legacyPackages.x86_64-linux; [
            git vim curl htop
          ];

          # Disable SSH if not needed
          incus.container.enableSSH = false;
        }
      ];
    };
  };
}
```

### Module Options

- `incus.container.enable` - Enable Incus container optimizations
- `incus.container.basePackages` - List of base packages to install (default: git, vim, curl, wget, htop)
- `incus.container.enableSSH` - Enable SSH service (default: true)

### Using the convenience helper

For simpler configuration, use the `makeIncusHost` helper:

```nix
{
  outputs = { nixpkgs, incus-flake, ... }:
    incus-flake.lib.makeIncusHost {
      name = "my-container";
      modules = [
        {
          networking.hostName = "my-container";
          services.nginx.enable = true;
        }
      ];
    };
}
```

### Helper Applications

The flake provides helper applications for container management:

- `nix run .#incus-<name>-import` - Import container image
- `nix run .#incus-<name>-launch` - Launch and configure container
- `nix run .#incus-<name>-delete` - Delete container

## Development

```bash
nix develop
```

## License

MIT
