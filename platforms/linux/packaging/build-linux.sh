#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Build-only packaging, with no host network, firewall or Tor changes.
set -euo pipefail
here="$(cd -- "$(dirname -- "$0")/.." && pwd)"
root="$(cd -- "$here/../.." && pwd)"
version="$(PYTHONPATH="$here" python3 -c 'import veylroute; print(veylroute.__version__)')"
output="${1:-$root/dist}"
mkdir -p "$output"
output="$(cd "$output" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

# Portable: all code, approved icons, and GUI menu integration scripts.
stage="$work/veylroute-linux-$version"
mkdir -p "$stage/bin" "$stage/veylroute" "$stage/assets" "$stage/packaging"
cp "$here/bin/veylroute" "$here/bin/veylroute-gui" "$stage/bin/"
cp "$here/veylroute/"*.py "$stage/veylroute/"
cp "$here/assets/"*.png "$stage/assets/"
cp "$here/packaging/veylroute.desktop" "$stage/packaging/"
cp "$here/README.md" "$stage/README.md"
cp "$here/ASSET-PROVENANCE.md" "$stage/ASSET-PROVENANCE.md"
cp "$root/LICENSE" "$stage/LICENSE"
chmod 0755 "$stage/bin/"*
(cd "$work" && tar -czf "$output/VeylRoute-Linux-$version-Portable.tar.gz" "veylroute-linux-$version")

# Debian: XDG application entry and canonical hicolor icon are first-class.
pkg="$work/pkg"
mkdir -p "$pkg/DEBIAN" "$pkg/usr/lib/veylroute/veylroute" \
  "$pkg/usr/bin" "$pkg/usr/share/veylroute/assets" \
  "$pkg/usr/share/icons/hicolor/256x256/apps" \
  "$pkg/usr/share/applications" "$pkg/usr/share/doc/veylroute"
cp "$here/veylroute/"*.py "$pkg/usr/lib/veylroute/veylroute/"
cp "$here/bin/veylroute" "$here/bin/veylroute-gui" "$pkg/usr/bin/"
cp "$here/assets/"*.png "$pkg/usr/share/veylroute/assets/"
cp "$here/assets/veylroute.png" "$pkg/usr/share/icons/hicolor/256x256/apps/veylroute.png"
cp "$here/packaging/veylroute.desktop" "$pkg/usr/share/applications/veylroute.desktop"
cp "$here/README.md" "$pkg/usr/share/doc/veylroute/README.md"
cp "$here/ASSET-PROVENANCE.md" "$pkg/usr/share/doc/veylroute/ASSET-PROVENANCE.md"
cp "$root/LICENSE" "$pkg/usr/share/doc/veylroute/LICENSE"
chmod 0755 "$pkg/usr/bin/"*
cat > "$pkg/DEBIAN/control" <<EOF
Package: veylroute
Version: $version
Section: net
Priority: optional
Architecture: all
Maintainer: Adam Knight <noreply@users.noreply.github.com>
Depends: python3 (>= 3.10), python3-tk, tor, nftables, iproute2, adduser
Recommends: python3-pil, python3-gi, gir1.2-ayatanaappindicator3-0.1, gir1.2-gtk-3.0
Suggests: obfs4proxy, polkitd
Description: Experimental Linux Tor routing control center
 Includes an application launcher, custom icon and optional tray.
 This version is a developer preview and has not passed full Linux
 network leak and recovery qualification. Do not deploy as a VPN service.
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
  # Cache update is optional; the icon files themselves are shipped in the package.
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q -f /usr/share/icons/hicolor >/dev/null 2>&1 || :
  fi
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
      echo 'VeylRoute firewall guard active. Run sudo veylroute recover first.' >&2
      exit 1
    fi
    if command -v nft >/dev/null 2>&1 && nft list table ip veylroute_nat >/dev/null 2>&1; then
      echo 'VeylRoute NAT redirect active. Recover before package removal.' >&2
      exit 1
    fi
    ;;
esac
PRE
chmod 0755 "$pkg/DEBIAN/postinst" "$pkg/DEBIAN/prerm"
dpkg-deb --root-owner-group --build "$pkg" "$output/VeylRoute-Linux-$version-Preview.deb"
(cd "$output" && sha256sum "VeylRoute-Linux-$version-Portable.tar.gz" "VeylRoute-Linux-$version-Preview.deb" > SHA256SUMS-Linux.txt)
printf 'Built Linux unsigned preview artifacts under %s\n' "$output"
