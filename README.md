# XivMitmLatencyMitigator-nix

NixOS modules and Docker helpers for running
[Soreepeong/XivMitmLatencyMitigator](https://github.com/Soreepeong/XivMitmLatencyMitigator)
as a LAN gateway for FFXIV traffic.

This repository does not contain `ffxiv_dx11.exe`. Pass it as a runtime path.

## NixOS Server Module

```nix
{
  inputs.xivmitm-nix.url = "github:RFLXN/XivMitmLatencyMitigator-nix";
}
```

```nix
{ inputs, ... }: {
  imports = [
    inputs.xivmitm-nix.nixosModules.server
  ];

  services.xivMitmLatencyMitigator.server = {
    enable = true;
    ffxivDx11Exe = "/mnt/shared/LinuxGames/ffxiv/ffxiv/game/ffxiv_dx11.exe";
    incomingInterface = "enp5s0";
    clientCidr = "192.168.100.101/32";
    listenPort = 10514;
  };
}
```

The server module:

- enables Docker by default
- builds and runs a Docker container with host networking
- enables IPv4 forwarding and `route_localnet`
- adds iptables NAT chains that redirect routed FFXIV TCP traffic to the local MITM listener
- masquerades matching forwarded FFXIV traffic

Set `runContainer = false` if you want Nix to manage only sysctls and iptables while you run the container manually.

## NixOS Client Module

```nix
{ inputs, ... }: {
  imports = [
    inputs.xivmitm-nix.nixosModules.client
  ];

  services.xivMitmLatencyMitigator.client = {
    enable = true;
    gateway = "192.168.100.100";
    interface = "eno1";
  };
}
```

The client module adds systemd-managed routes for the FFXIV server ranges through the gateway.

## Raw Docker Compose

Copy or use the files in `docker/` on the server:

```bash
mkdir -p /home/rflxn/containers/xivmitm
cp docker/Dockerfile docker/docker-compose.yml /home/rflxn/containers/xivmitm/
cd /home/rflxn/containers/xivmitm
mkdir -p data
```

Create `.env`:

```env
FFXIV_DX11_EXE=/mnt/shared/LinuxGames/ffxiv/ffxiv/game/ffxiv_dx11.exe
XIVMITM_DATA_DIR=./data
XIVMITM_LISTEN=0.0.0.0:10514
```

Then run:

```bash
docker compose up -d --build
```

The Compose file uses `network_mode: host` and `--firewall none`. Host routing/firewall should be handled by NixOS or by your own host rules.

## `nix run` Docker Runner

Run the container without copying Compose files:

```bash
nix run github:RFLXN/XivMitmLatencyMitigator-nix#docker-run -- \
  --ffxiv-dx11-exe /mnt/shared/LinuxGames/ffxiv/ffxiv/game/ffxiv_dx11.exe \
  --data-dir /home/rflxn/containers/xivmitm/data
```

This builds the Docker image from `docker/Dockerfile`, removes any existing container with the same name, and runs XivMitmLatencyMitigator with host networking.

## Verification

On the client:

```bash
ip route get 204.2.29.1
```

Expected result should route via the server gateway.

On the server:

```bash
ss -ltnp | grep 10514
docker logs -f xivmitm
```

When FFXIV is connected and actions are used in-game, the logs should show game connections plus action/effect packet lines.

