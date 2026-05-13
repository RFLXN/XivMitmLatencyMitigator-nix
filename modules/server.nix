{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.xivMitmLatencyMitigator.server;

  defaultRanges = [
    "119.252.36.0/24"
    "119.252.37.0/24"
    "153.254.80.0/24"
    "204.2.29.0/24"
    "80.239.145.0/24"
  ];

  incomingMatch = lib.optionalString (cfg.incomingInterface != null) "-i ${cfg.incomingInterface}";
  outgoingInterface =
    if cfg.outgoingInterface != null then cfg.outgoingInterface else cfg.incomingInterface;
  outgoingMatch = lib.optionalString (outgoingInterface != null) "-o ${outgoingInterface}";
  clientMatch = lib.optionalString (cfg.clientCidr != null) "-s ${cfg.clientCidr}";

  preroutingRules = lib.concatMapStringsSep "\n" (range: ''
    iptables -w -t nat -A XIVMITM_PRE ${incomingMatch} ${clientMatch} -d ${range} -p tcp --dport ${cfg.portRange} -j DNAT --to-destination 127.0.0.1:${toString cfg.listenPort}
  '') cfg.ranges;

  postroutingRules = lib.concatMapStringsSep "\n" (range: ''
    iptables -w -t nat -A XIVMITM_POST ${outgoingMatch} ${clientMatch} -d ${range} -j MASQUERADE
  '') cfg.ranges;

  mitmArgs = [
    "--directory"
    "/data"
    "--listen"
    "${cfg.listenAddress}:${toString cfg.listenPort}"
    "--firewall"
    "none"
  ]
  ++ lib.optionals cfg.measurePing [ "--measure-ping" ]
  ++ lib.optionals cfg.webStatistics [ "--web-statistics" ]
  ++ cfg.extraMitmArgs;

  mitmArgsString = lib.escapeShellArgs mitmArgs;
  imageTag = "${cfg.imageName}:${cfg.imageTag}";
  ffxivDx11ExePath = if cfg.ffxivDx11Exe == null then "" else cfg.ffxivDx11Exe;
in
{
  options.services.xivMitmLatencyMitigator.server = {
    enable = lib.mkEnableOption "server-side XivMitmLatencyMitigator gateway";

    ffxivDx11Exe = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/mnt/shared/LinuxGames/ffxiv/ffxiv/game/ffxiv_dx11.exe";
      description = "Absolute runtime path to ffxiv_dx11.exe. This file is bind-mounted into the container and is not copied into the Nix store.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/xivmitm-latency-mitigator";
      description = "Writable runtime data directory for definitions.json and other XivMitm files.";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Address the XivMitm listener binds to inside host networking.";
    };

    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 10514;
      description = "Local TCP port used by XivMitmLatencyMitigator.";
    };

    incomingInterface = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "enp5s0";
      description = "Server interface receiving routed client FFXIV packets.";
    };

    outgoingInterface = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "enp5s0";
      description = "Server interface used for upstream FFXIV traffic. Defaults to incomingInterface.";
    };

    clientCidr = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "192.168.100.101/32";
      description = "Optional source CIDR for clients whose FFXIV traffic should be intercepted.";
    };

    ranges = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = defaultRanges;
      description = "FFXIV server IPv4 ranges intercepted by the gateway.";
    };

    portRange = lib.mkOption {
      type = lib.types.str;
      default = "1024:65535";
      description = "TCP destination port range intercepted for FFXIV server ranges, in iptables multiport syntax.";
    };

    manageDocker = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to enable Docker from this module.";
    };

    runContainer = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether this module should run the XivMitm Docker container with systemd.";
    };

    imageName = lib.mkOption {
      type = lib.types.str;
      default = "xivmitm-latency-mitigator";
      description = "Docker image name built by the systemd service.";
    };

    imageTag = lib.mkOption {
      type = lib.types.str;
      default = "2ddfb8c";
      description = "Docker image tag built by the systemd service.";
    };

    containerName = lib.mkOption {
      type = lib.types.str;
      default = "xivmitm";
      description = "Docker container name.";
    };

    upstreamRevision = lib.mkOption {
      type = lib.types.str;
      default = "2ddfb8c3310782dbb7baaecdab17fc9c89ccce90";
      description = "XivMitmLatencyMitigator git revision to build into the Docker image.";
    };

    measurePing = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Pass --measure-ping to XivMitmLatencyMitigator.";
    };

    webStatistics = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Pass --web-statistics to XivMitmLatencyMitigator.";
    };

    extraMitmArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "--region"
        "JP"
      ];
      description = "Extra arguments appended to the XivMitmLatencyMitigator command.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.ranges != [ ];
        message = "services.xivMitmLatencyMitigator.server.ranges must not be empty.";
      }
      {
        assertion = !cfg.runContainer || cfg.ffxivDx11Exe != null;
        message = "services.xivMitmLatencyMitigator.server.ffxivDx11Exe must be set when runContainer is true.";
      }
      {
        assertion = cfg.ffxivDx11Exe == null || lib.hasPrefix "/" cfg.ffxivDx11Exe;
        message = "services.xivMitmLatencyMitigator.server.ffxivDx11Exe must be an absolute runtime path.";
      }
      {
        assertion = lib.hasPrefix "/" cfg.dataDir;
        message = "services.xivMitmLatencyMitigator.server.dataDir must be an absolute path.";
      }
    ];

    virtualisation.docker.enable = lib.mkIf cfg.manageDocker true;

    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = lib.mkDefault 1;
      "net.ipv4.conf.all.route_localnet" = 1;
      "net.ipv4.conf.default.route_localnet" = 1;
    }
    // lib.optionalAttrs (cfg.incomingInterface != null) {
      "net.ipv4.conf.${cfg.incomingInterface}.route_localnet" = 1;
    };

    environment.systemPackages = [
      pkgs.iptables
      pkgs.iproute2
    ]
    ++ lib.optionals cfg.manageDocker [ pkgs.docker ];

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root - -"
    ];

    systemd.services.xivmitm-latency-mitigator-gateway = {
      description = "Redirect routed FFXIV traffic to XivMitmLatencyMitigator";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];

      path = [ pkgs.iptables ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        iptables -w -t nat -N XIVMITM_PRE 2>/dev/null || true
        iptables -w -t nat -N XIVMITM_POST 2>/dev/null || true
        iptables -w -t nat -F XIVMITM_PRE
        iptables -w -t nat -F XIVMITM_POST

        while iptables -w -t nat -D PREROUTING -p tcp -j XIVMITM_PRE 2>/dev/null; do :; done
        while iptables -w -t nat -D POSTROUTING -j XIVMITM_POST 2>/dev/null; do :; done
        iptables -w -t nat -I PREROUTING 1 -p tcp -j XIVMITM_PRE
        iptables -w -t nat -I POSTROUTING 1 -j XIVMITM_POST

        ${preroutingRules}
        ${postroutingRules}
      '';

      preStop = ''
        while iptables -w -t nat -D PREROUTING -p tcp -j XIVMITM_PRE 2>/dev/null; do :; done
        while iptables -w -t nat -D POSTROUTING -j XIVMITM_POST 2>/dev/null; do :; done
        iptables -w -t nat -F XIVMITM_PRE 2>/dev/null || true
        iptables -w -t nat -F XIVMITM_POST 2>/dev/null || true
        iptables -w -t nat -X XIVMITM_PRE 2>/dev/null || true
        iptables -w -t nat -X XIVMITM_POST 2>/dev/null || true
      '';
    };

    systemd.services.xivmitm-latency-mitigator = lib.mkIf cfg.runContainer {
      description = "XivMitmLatencyMitigator Docker container";
      wantedBy = [ "multi-user.target" ];
      wants = [
        "docker.service"
        "network-online.target"
        "xivmitm-latency-mitigator-gateway.service"
      ];
      after = [
        "docker.service"
        "network-online.target"
        "xivmitm-latency-mitigator-gateway.service"
      ];

      path = [
        pkgs.coreutils
        pkgs.docker
      ];

      preStart = ''
        test -f ${lib.escapeShellArg ffxivDx11ExePath}
        mkdir -p ${lib.escapeShellArg cfg.dataDir}
        docker build \
          --build-arg XIVMITM_REV=${lib.escapeShellArg cfg.upstreamRevision} \
          -t ${lib.escapeShellArg imageTag} \
          -f ${self}/docker/Dockerfile \
          ${self}/docker
        docker rm -f ${lib.escapeShellArg cfg.containerName} 2>/dev/null || true
      '';

      script = ''
        exec docker run --rm \
          --name ${lib.escapeShellArg cfg.containerName} \
          --network host \
          --init \
          -v ${lib.escapeShellArg "${cfg.dataDir}:/data"} \
          -v ${lib.escapeShellArg "${ffxivDx11ExePath}:/data/ffxiv_dx11.exe:ro"} \
          ${lib.escapeShellArg imageTag} \
          ${mitmArgsString}
      '';

      serviceConfig = {
        Restart = "always";
        RestartSec = 5;
        ExecStop = "-${pkgs.docker}/bin/docker stop ${lib.escapeShellArg cfg.containerName}";
      };
    };
  };
}
