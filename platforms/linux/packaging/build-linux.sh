#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Build only. No host networking, Tor startup, or system configuration.
set -euo pipefail
here="$(cd -- "$(dirname -- "$0")/.." && pwd)"
root="$(cd -- "$here/../.." && pwd)"
version="$(PYTHONPATH="$here" python3 -c 'import veylroute; print(veylroute.__version__)')"
output="${1:-$root/dist}"
mkdir -p "$output"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
stage="$work/veylroute-linux-$version"
mkdir -p "$stage/bin" "$stage/veylroute"
cp "$here/bin/veylroute" "$here/bin/veylroute-gui" "$stage/bin/"
cp "$here/veylroute/"*.py "$stage/veylroute/"
cp "$here/README.md" "$stage/README.md"
cp "$root/LICENSE" "$stage/LICENSE"
chmod 0755 "$stage/bin/"*
( cd "$work" && tar -czf "$output/VeylRoute-Linux-$version-Portable.tar.gz" "veylroute-linux-$version" )

pkg="$work/pkg"
mkdir -p "$pkg/DEBIAN" "$pkg/usr/lib/veylroute/veylroute" "$pkg/usr/bin" \
  "$pkg/usr/share/applications" "$pkg/usr/share/doc/veylroute"
cp "$here/veylroute/"*.py "$pkg/usr/lib/veylroute/veylroute/"
cp "$here/bin/veylroute" "$here/bin/veylroute-gui" "$pkg/usr/bin/"
cp "$here/packaging/veylroute.desktop" "$pkg/usr/share/applications/"
cp "$here/README.md" "$pkg/usr/share/doc/veylroute/README.md"
cp "$root/LICENSE" "$pkg/usr/share/doc/veylroute/LICENSE"
chmod 0755 "$pkg/usr/bin/"*
cat > "$pkg/DEBIAN/control" <<EOF
Package: veylroute
Version: $version
Section: net
Priority: optional
Architecture: all
Maintainer: Adam Knight <noreply@users.noreply.github.com>
Depends: python3 (>= 3.10), tor, nftables, iproute2, adduser
Recommends: python3-tk, polkitd, obfs4proxy
Description: Experimental Linux Tor routing control center
 This version is a developer preview and has not passed full Linux
 network leak and recovery validation. Do not deploy as a VPN service.
EOF
cat > "$pkg/DEBIAN/postinst" <<'POST'
#!/bin/sh
set -eu
if [ "${1:-}" = configure ]; then
  if ! getent passwd veylroute-tor >/dev/null; then
    adduser --system --group --home /var/lib/veylroute --no-create-home \
      --disabled-login veylroute-tor
  fi
  install -d -o veylroute-tor -g veylroute-tor -m 0700 /var/lib/veylroute
  install -d -o veylroute-tor -g veylroute-tor -m 0700 /var/lib/veylroute/tor-data
fi
POST
cat > "$pkg/DEBIAN/prerm" <<'PRE'
#!/bin/sh
set -eu
case "${1:-}" in
  remove|upgrade|deconfigure)
    if [ -f /run/veylroute/session.json ] || [ -f /run/veylroute/pending.json ]; then
      echo 'Disconnect or recover VeylRoute before replacing/uninstalling the Linux package.' >&2
      exit 1
    fi
    if command -v nft >/dev/null 2>&1 && nft list table inet veylroute_guard >/dev/null 2>&1; then
      echo 'VeylRoute firewall guard is active. Run sudo veylroute recover before package removal.' >&2
      exit 1
    fi
    if command -v nft >/dev/null 2>&1 && nft list table ip veylroute_nat >/dev/null 2>&1; then
      echo 'VeylRoute NAT redirect is active. Recover before package removal.' >&2
      exit 1
    fi
    ;;
esac
PRE
chmod 0755 "$pkg/DEBIAN/postinst" "$pkg/DEBIAN/prerm"
dpkg-deb --root-owner-group --build "$pkg" "$output/VeylRoute-Linux-$version-Preview.deb"
(cd "$output" && sha256sum "VeylRoute-Linux-$version-Portable.tar.gz" "VeylRoute-Linux-$version-Preview.deb" > SHA256SUMS-Linux.txt)
printf 'Built Linux unsigned preview artifacts under %s\n' "$output"
