{
  description = "NixOS modules and Docker helpers for XivMitmLatencyMitigator";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      nixosModules = {
        client = import ./modules/client.nix;
        server = import ./modules/server.nix { inherit self; };
        default = self.nixosModules.server;
      };

      apps = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          dockerRun = import ./nix/apps/docker-run.nix { inherit self pkgs; };
        in
        {
          default = self.apps.${system}.docker-run;
          docker-run = {
            type = "app";
            program = "${dockerRun}/bin/xivmitm-docker-run";
            meta.description = "Build and run XivMitmLatencyMitigator with Docker host networking";
          };
        }
      );

      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.runCommand "xivmitm-docker-files" { } ''
            mkdir -p "$out"
            cp ${./docker/Dockerfile} "$out/Dockerfile"
            cp ${./docker/docker-compose.yml} "$out/docker-compose.yml"
          '';
        }
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt);
    };
}
