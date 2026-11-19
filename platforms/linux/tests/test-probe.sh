#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Isolated Linux foundation test: no sudo, network calls or OS configuration.
set -euo pipefail
root="$(cd -- "$(dirname -- "$0")/../../.." && pwd)"
probe="$root/platforms/linux/check-environment.sh"

bash -n "$probe"
text="$(bash "$probe")"
[[ "$text" == *'READ-ONLY prerequisite check'* ]]
[[ "$text" == *'Routing and privacy NOT qualified'* ]]

json="$(bash "$probe" --json)"
python3 - "$json" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj['platform'] == 'linux'
assert obj['mode'] == 'read-only-probe'
assert obj['routing_qualified'] is False
assert isinstance(obj['architecture'], str) and obj['architecture']
for name in ('tun','iproute2','nftables','tor','tun2socks','obfs4_transport',
             'resolvectl','networkmanager','dependencies_present'):
    assert isinstance(obj[name], bool), name
PY

if bash "$probe" --unrecognized >/dev/null 2>&1; then
  echo 'FAIL: unknown option was silently accepted' >&2
  exit 1
fi

bash "$probe" --help | grep -q -- '--require-deps'
printf '%s\n' 'PASS: Linux read-only foundation probe and JSON contract'
