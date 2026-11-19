#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# VeylRoute Linux foundation: read-only environment probe.
# No TUN creation, Tor startup, elevation, routing, DNS, or firewall changes.
set -euo pipefail

json=false
require_deps=false
for option in "$@"; do
  case "$option" in
    --json) json=true ;;
    --require-deps) require_deps=true ;;
    -h|--help)
      printf '%s\n' 'Usage: check-environment.sh [--json] [--require-deps]' \
        'Read-only Linux prerequisite detection. No network configuration changes.'
      exit 0 ;;
    *) printf 'Unsupported option: %s\n' "$option" >&2; exit 2 ;;
  esac
done

if [[ "$(uname -s)" != Linux ]]; then
  printf '%s\n' 'VeylRoute Linux probe runs on Linux only.' >&2
  exit 2
fi

present() {
  if command -v "$1" >/dev/null 2>&1; then printf true; else printf false; fi
}

architecture="$(uname -m)"
if [[ ! "$architecture" =~ ^[A-Za-z0-9_.-]+$ ]]; then
  printf '%s\n' 'Unexpected uname architecture format.' >&2
  exit 2
fi

if [[ -c /dev/net/tun ]]; then tun=true; else tun=false; fi
iproute2="$(present ip)"
nftables="$(present nft)"
tor="$(present tor)"
tun2socks="$(present tun2socks)"
lyrebird="$(present lyrebird)"
obfs4proxy="$(present obfs4proxy)"
resolved="$(present resolvectl)"
network_manager="$(present nmcli)"

if [[ "$lyrebird" == true || "$obfs4proxy" == true ]]; then obfs4=true; else obfs4=false; fi
# This flag means only binary presence; it is NOT a routing/privacy qualification.
if [[ "$tun" == true && "$iproute2" == true && "$nftables" == true && "$tor" == true && "$tun2socks" == true && "$obfs4" == true ]]; then
  deps_present=true
else
  deps_present=false
fi

if [[ "$json" == true ]]; then
  printf '{"platform":"linux","architecture":"%s","mode":"read-only-probe","tun":%s,"iproute2":%s,"nftables":%s,"tor":%s,"tun2socks":%s,"obfs4_transport":%s,"resolvectl":%s,"networkmanager":%s,"dependencies_present":%s,"routing_qualified":false}\n' \
    "$architecture" "$tun" "$iproute2" "$nftables" "$tor" "$tun2socks" "$obfs4" "$resolved" "$network_manager" "$deps_present"
else
  printf '%s\n' 'VeylRoute Linux foundation: READ-ONLY prerequisite check'
  printf 'Architecture             : %s\n' "$architecture"
  printf 'TUN character device     : %s\n' "$tun"
  printf 'iproute2                 : %s\n' "$iproute2"
  printf 'nftables                 : %s\n' "$nftables"
  printf 'Tor executable           : %s\n' "$tor"
  printf 'tun2socks executable     : %s\n' "$tun2socks"
  printf 'obfs4 transport          : %s\n' "$obfs4"
  printf 'systemd-resolved tool    : %s\n' "$resolved"
  printf 'NetworkManager CLI       : %s\n' "$network_manager"
  printf 'Core binaries detected   : %s\n' "$deps_present"
  printf '%s\n' 'Routing and privacy NOT qualified. No changes made to this system.'
fi

if [[ "$require_deps" == true && "$deps_present" != true ]]; then exit 1; fi
