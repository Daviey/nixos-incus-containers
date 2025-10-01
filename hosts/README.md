# Host Flakes

Keep project-specific host flakes here. Each host typically imports the shared module exported by `../host-common`:

```nix
inputs.incusHost.url = "path:../host-common";

outputs = inputs@{ incusHost, nixpkgs, ... }:
  incusHost.lib.makeIncusHost {
    inherit inputs;
    name = "my-container";
    modules = [
      ({ pkgs, ... }: {
        # host-specific services
      })
    ];
    ssh.authorizedKeys = [ "ssh-ed25519 AAAA..." ];
    firewall.tcpPorts = [ 8080 ];
  };
```
