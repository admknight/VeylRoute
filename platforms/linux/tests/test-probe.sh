#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "$0")/../../.." && pwd)"
probe="$root/platforms/linux/check-environment.sh"
bash -n "$probe"
text="$(bash "$probe")"
[[ "$text" == *'READ-ONLY prerequisite check'* ]]
[[ "$text" == *'Routing and privacy NOT qualified'* ]]
report="$(bash "$probe" --json)"
python3 - "$report" <<'PY'
import json,sys
j=json.loads(sys.argv[1]);assert j['platform']=='linux';assert j['routing_qualified'] is False
for k in ('tun','iproute2','nftables','tor','tun2socks','obfs4_transport','resolvectl','networkmanager','dependencies_present'):
    assert isinstance(j[k],bool)
PY
if bash "$probe" --unknown >/dev/null 2>&1; then echo 'Unknown option erroneously accepted'; exit 1; fi
printf '%s\n' 'PASS Linux read-only prerequisite probe contract'
