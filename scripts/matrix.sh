#!/usr/bin/env bash
# The Flint benchmark matrix, run from this box (needs scripts/tunnel_keep.sh up). Nothing else may use rec meanwhile.
#   1. speed: spark-tuning's bench_decode.py through the tunnel (client side; rec has no /metrics, engine numbers come
#      from the --metrics JSONL on the Mac, see scripts/serve.sh)
#   2. quality + time to solve: scripts/run_flint.sh on the worker at each temperature in TEMPS, then tts_from_full.py
# Usage: scripts/matrix.sh [speed] [quality]     (default both). Logs: results/<date>/ here, ~/mac-quality/*.log on the worker.
set -euo pipefail
cd "$(dirname "$0")/.."; . ./mac.env
STEPS="${*:-speed quality}"; TEMPS="${TEMPS:-1.0 0.6 0}"; D=results/$(date +%F); mkdir -p "$D"
KEY=$(ssh -o BatchMode=yes "$WORKER" cat mac-quality/flint_key)
if [[ " $STEPS " == *" speed "* ]]; then
  API_KEY="$KEY" python3 "$SPARK/scripts/bench_decode.py" --url http://127.0.0.1:11501 --model flint --tasks code,edit \
    --contexts 1000,16000,64000,128000 --temps 0.0,1.0 --decode 1000 --label flint-int4-rec --json "$D/flint-speed.json" \
    | tee "$D/flint-speed.txt"
  sed -i 's#http://[0-9.]*:#http://<mac>:#' "$D/flint-speed.json"
fi
if [[ " $STEPS " == *" quality "* ]]; then
  for t in $TEMPS; do
    L=FLINT-t${t/./}
    ssh -o BatchMode=yes "$WORKER" "~/mac-quality/run_flint.sh $t $L > ~/mac-quality/$L.log 2>&1; python3 ~/mac-quality/tts_from_full.py ~/spark-quality/results/$L >> ~/mac-quality/$L.log 2>&1" < /dev/null
  done
fi
echo "matrix done: $STEPS"
