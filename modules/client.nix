{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.xivMitmLatencyMitigator.client;

  defaultRanges = [
    "119.252.36.0/24"
    "119.252.37.0/24"
    "153.254.80.0/24"
    "204.2.29.0/24"
    "80.239.145.0/24"
  ];

  routeUp = lib.concatMapStringsSep "\n" (range: ''
    ip route replace ${range} via ${cfg.gateway} dev ${cfg.interface}
  '') cfg.ranges;

  routeDown = lib.concatMapStringsSep "\n" (range: ''
    ip route del ${range} via ${cfg.gateway} dev ${cfg.interface} 2>/dev/null || true
  '') cfg.ranges;
in
{
  options.services.xivMitmLatencyMitigator.client = {
    enable = lib.mkEnableOption "client-side routing for XivMitmLatencyMitigator";

    gateway = lib.mkOption {
      type = lib.types.str;
      example = "192.168.100.100";
      description = "LAN IP address of the XivMitmLatencyMitigator gateway/server.";
    };

    interface = lib.mkOption {
      type = lib.types.str;
      example = "eno1";
      description = "Client network interface used to reach the gateway.";
    };

    ranges = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = defaultRanges;
      description = "FFXIV server IPv4 ranges routed through the gateway.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.ranges != [ ];
        message = "services.xivMitmLatencyMitigator.client.ranges must not be empty.";
      }
    ];

    environment.systemPackages = [ pkgs.iproute2 ];

    systemd.services.xivmitm-latency-mitigator-client-routes = {
      description = "Route FFXIV traffic through the XivMitmLatencyMitigator gateway";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];

      path = [ pkgs.iproute2 ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = routeUp;
      preStop = routeDown;
    };
  };
}
