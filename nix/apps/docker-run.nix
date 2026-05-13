{ self, pkgs }:
pkgs.writeShellApplication {
  name = "xivmitm-docker-run";

  runtimeInputs = [
    pkgs.coreutils
    pkgs.docker
  ];

  text = ''
    set -euo pipefail

    upstream_rev="2ddfb8c3310782dbb7baaecdab17fc9c89ccce90"
    image="xivmitm-latency-mitigator:2ddfb8c"
    name="xivmitm"
    listen="0.0.0.0"
    port="10514"
    data_dir="$PWD/.xivmitm-data"
    ffxiv_dx11_exe="''${FFXIV_DX11_EXE:-}"
    build=1
    extra_args=()

    usage() {
      cat <<'EOF'
    Usage:
      xivmitm-docker-run --ffxiv-dx11-exe PATH [options] [-- extra-xivmitm-args...]

    Options:
      --ffxiv-dx11-exe PATH   Absolute path to ffxiv_dx11.exe. Can also use FFXIV_DX11_EXE.
      --data-dir DIR          Writable data directory. Default: $PWD/.xivmitm-data
      --listen ADDRESS        Listen address. Default: 0.0.0.0
      --port PORT             Listen port. Default: 10514
      --name NAME             Docker container name. Default: xivmitm
      --image IMAGE           Docker image tag. Default: xivmitm-latency-mitigator:2ddfb8c
      --rev REV               XivMitmLatencyMitigator git revision to build.
      --no-build              Skip docker build and run the image as-is.
      --help                  Show this help.

    Example:
      nix run .#docker-run -- --ffxiv-dx11-exe /mnt/shared/LinuxGames/ffxiv/ffxiv/game/ffxiv_dx11.exe
    EOF
    }

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --ffxiv-dx11-exe)
          ffxiv_dx11_exe="$2"
          shift 2
          ;;
        --data-dir)
          data_dir="$2"
          shift 2
          ;;
        --listen)
          listen="$2"
          shift 2
          ;;
        --port)
          port="$2"
          shift 2
          ;;
        --name)
          name="$2"
          shift 2
          ;;
        --image)
          image="$2"
          shift 2
          ;;
        --rev)
          upstream_rev="$2"
          shift 2
          ;;
        --no-build)
          build=0
          shift
          ;;
        --help|-h)
          usage
          exit 0
          ;;
        --)
          shift
          extra_args+=("$@")
          break
          ;;
        *)
          extra_args+=("$1")
          shift
          ;;
      esac
    done

    if [[ -z "$ffxiv_dx11_exe" ]]; then
      echo "error: --ffxiv-dx11-exe or FFXIV_DX11_EXE is required" >&2
      exit 1
    fi

    if [[ "$ffxiv_dx11_exe" != /* ]]; then
      echo "error: ffxiv_dx11.exe path must be absolute" >&2
      exit 1
    fi

    if [[ ! -f "$ffxiv_dx11_exe" ]]; then
      echo "error: ffxiv_dx11.exe does not exist: $ffxiv_dx11_exe" >&2
      exit 1
    fi

    mkdir -p "$data_dir"

    if [[ "$build" = 1 ]]; then
      docker build \
        --build-arg "XIVMITM_REV=$upstream_rev" \
        -t "$image" \
        -f ${self}/docker/Dockerfile \
        ${self}/docker
    fi

    docker rm -f "$name" >/dev/null 2>&1 || true

    exec docker run --rm \
      --name "$name" \
      --network host \
      --init \
      -v "$data_dir:/data" \
      -v "$ffxiv_dx11_exe:/data/ffxiv_dx11.exe:ro" \
      "$image" \
      --directory /data \
      --listen "$listen:$port" \
      --firewall none \
      --measure-ping \
      --web-statistics \
      "''${extra_args[@]}"
  '';
}
