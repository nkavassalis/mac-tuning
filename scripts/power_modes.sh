#!/usr/bin/env bash
# Decode speed and package power in each macOS power mode (pmset powermode 1 = Low Power, 0 = Automatic, 2 = High Power).
# Run from this box; needs the LAN relay (scripts/install_launchd.sh) and sudo on the Mac (pmset, powermetrics).
# Nothing else may use rec meanwhile. Restores the mode it found at the end.
#   scripts/power_modes.sh            # MODES="1 0 2" CONTEXTS=1000,16000,64000
set -euo pipefail
cd "$(dirname "$0")/.."; . ./mac.env
MODES="${MODES:-1 0 2}"; CONTEXTS="${CONTEXTS:-1000,16000,64000}"; D=results/$(date +%F); mkdir -p "$D"
mac() { ssh -o BatchMode=yes ${MAC_KEY:+-i "$MAC_KEY"} "$MAC" "$@" < /dev/null; }
URL=http://${MAC#*@}:11502; KEY=$(mac cat .local/share/rec/config/api-key)
ORIG=$(mac "pmset -g | awk '/powermode/{print \$2}'")
trap 'mac "sudo -n pmset -a powermode $ORIG; sudo -n pkill -x powermetrics" || true' EXIT
# average "Combined Power" (CPU+GPU+ANE, mW) over N 1 s samples
watt() { mac "sudo -n powermetrics -i 1000 -n $1 --samplers cpu_power,gpu_power 2>/dev/null | awk '/Combined Power/{s+=\$(NF-1); n++} END{printf \"%.0f\", s/n}'"; }
for m in $MODES; do
  mac "sudo -n pmset -a powermode $m"; sleep 5
  idle=$(watt 20)
  mac "sudo -n powermetrics -i 1000 --samplers cpu_power,gpu_power > /tmp/pm-$m.txt 2>/dev/null &"
  API_KEY="$KEY" python3 "$SPARK/scripts/bench_decode.py" --url "$URL" --model flint --tasks code,edit \
    --contexts "$CONTEXTS" --temps 0.0 --decode 1000 --label "flint-int4-powermode$m" --json "$D/power-mode$m.json" \
    | tee "$D/power-mode$m.txt"
  load=$(mac "sudo -n pkill -x powermetrics; sleep 1; awk '/Combined Power/{s+=\$(NF-1); n++} END{printf \"%.0f\", s/n}' /tmp/pm-$m.txt; rm -f /tmp/pm-$m.txt")
  echo "powermode $m: idle ${idle} mW, average over the bench ${load} mW" | tee -a "$D/power-modes.txt"
  sed -i 's#http://[0-9.]*:#http://<mac>:#' "$D/power-mode$m.json"
done
