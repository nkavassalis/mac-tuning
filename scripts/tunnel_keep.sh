#!/usr/bin/env bash
# tunnel_keep.sh: keep both legs of the Flint tunnel up (restart a leg within 5 s if it drops). Run in the foreground or
# as a background job; Ctrl-C / kill stops both. Same path as tunnel.sh: Mac 127.0.0.1:11500 -> here :11501 -> worker 127.0.0.1:11500.
set -uo pipefail
cd "$(dirname "$0")/.."; . ./mac.env
O=(-N -o BatchMode=yes -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=4)
trap 'kill $(jobs -p) 2>/dev/null; exit 0' INT TERM EXIT
leg() { while true; do ssh "${O[@]}" "$@"; echo "$(date -u +%FT%TZ) leg exited ($?), restarting: ${*: -1}" >&2; sleep 5; done; }
leg -i "$MAC_KEY" -L 127.0.0.1:11501:127.0.0.1:11500 "$MAC" &
sleep 2
leg -R 127.0.0.1:11500:127.0.0.1:11501 "$WORKER" &
wait
