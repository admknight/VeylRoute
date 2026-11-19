#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Read-only prerequisite checker for the independent Linux backend.
set -euo pipefail
json=false; require_deps=false
for arg in "$@"; do
  case "$arg" in
    --json) json=true;;
    --require-deps) require_deps=true;;
    -h|--help) printf '%s\n' 'Usage: check-environment.sh [--json] [--require-deps]'; exit 0;;
    *) printf 'Unknown option: %s\n' "$arg" >&2; exit 2;;
  esac
done
[[ $(uname -s) == Linux ]] || { echo 'Linux only.' >&2; exit 2; }
present(){ if command -v "$1" >/dev/null 2>&1; then echo true; else echo false; fi; }
architecture="$(uname -m)"
[[ "$architecture" =~ ^[a-zA-Z0-9_.-]+$ ]] || exit 2
[[ -c /dev/net/tun ]] && tun=true || tun=false
iproute2="$(present ip)"
nftables="$(present nft)"
tor="$(present tor)"
tun2socks="$(present tun2socks)"
lyrebird="$(present lyrebird)"
obfs4proxy="$(present obfs4proxy)"
resolvectl="$(present resolvectl)"
networkmanager="$(present nmcli)"
[[ "$lyrebird" == true || "$obfs4proxy" == true ]] && obfs4=true || obfs4=false
# Tor TransPort/DNSPort + nft, not Windows' Wintun/tun2socks.
[[ "$iproute2" == true && "$nftables" == true && "$tor" == true ]] && deps=true || deps=false
if "$json"; then
  printf '{"platform":"linux","architecture":"%s","mode":"read-only-probe","tun":%s,"iproute2":%s,"nftables":%s,"tor":%s,"tun2socks":%s,"obfs4_transport":%s,"resolvectl":%s,"networkmanager":%s,"dependencies_present":%s,"routing_qualified":false}\n' \
    "$architecture" "$tun" "$iproute2" "$nftables" "$tor" "$tun2socks" "$obfs4" "$resolvectl" "$networkmanager" "$deps"
else
  echo 'VeylRoute Linux: READ-ONLY prerequisite check'
  echo "Architecture            : $architecture"
  echo "Tor executable          : $tor"
  echo "nftables                : $nftables"
  echo "iproute2                : $iproute2"
  echo "obfs4 transport         : $obfs4 (optional without bridges)"
  echo "Core binaries detected  : $deps"
  echo 'Routing and privacy NOT qualified; no changes performed.'
fi
if "$require_deps" && [[ "$deps" != true ]]; then exit 1; fi
