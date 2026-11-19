#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Optional kernel rule check in a brand-new network namespace only.
set -euo pipefail
here="$(cd -- "$(dirname -- "$0")/.." && pwd)"
if ! command -v nft >/dev/null 2>&1; then echo 'SKIP: nft unavailable'; exit 0; fi
if ! command -v sudo >/dev/null 2>&1; then echo 'SKIP: sudo unavailable'; exit 0; fi
rules="$(mktemp)"
trap 'rm -f -- "$rules"' EXIT
PYTHONPATH="$here" python3 -c 'from veylroute.model import build_nft_plan; print(build_nft_plan(993))' > "$rules"
# Never invoke nft against the host namespace. If unshare is forbidden,
# report a skip rather than testing against or modifying the host firewall.
if ! sudo unshare --net -- bash -c 'true' >/dev/null 2>&1; then
  echo 'SKIP: kernel forbids isolated network namespaces'; exit 0
fi
sudo unshare --net -- bash -c '
set -eu
nft -f "$1"
nft list table ip veylroute_nat >/dev/null
nft list table inet veylroute_guard >/dev/null
nft delete table ip veylroute_nat
nft delete table inet veylroute_guard
if nft list tables | grep -q veylroute; then echo "FAIL: tables remained" >&2; exit 1; fi
' _ "$rules"
echo 'PASS: isolated nftables install/remove contract; host networking untouched'
