#!/usr/bin/env bash
# serve.sh: on the Mac, start Flint exactly as `rec serve` 0.1.0 does, plus `--metrics` so the engine appends one JSON line per
# request (prefill/decode seconds, decode tok/s, cached prompt tokens, peak memory). The flag only writes after a request
# finishes. Same python, same args, same env (HF_HUB_OFFLINE=1, TOKENIZERS_PARALLELISM=false) as rec's own launch, read
# with `ps eww` on 2026-10-24.
#   ssh mac 'bash -s' < scripts/serve.sh            # starts in the background, waits for /health
#   METRICS=~/mac-tuning-logs/flint-metrics.jsonl   # default
set -euo pipefail
D=$HOME/.local/share/rec
PY=$(ls -d "$D"/runtimes/*/python/bin/python3.12 | head -1)
MD=$(dirname "$(ls "$D"/models/*/flint-int4.json | head -1)")
METRICS=${METRICS:-$HOME/mac-tuning-logs/flint-metrics.jsonl}; mkdir -p "$(dirname "$METRICS")"
"$HOME/.local/bin/rec" stop >/dev/null 2>&1 || true
pkill -f "rec_mlx.cli serve" 2>/dev/null || true; sleep 2
HF_HUB_OFFLINE=1 TOKENIZERS_PARALLELISM=false nohup "$PY" -I -B -m rec_mlx.cli serve flint --model-dir "$MD" \
  --manifest "$MD/flint-int4.json" --port 11500 --context-limit 262144 --api-key-file "$D/config/api-key" \
  --metrics "$METRICS" > "$HOME/mac-tuning-logs/serve.log" 2>&1 < /dev/null &
K=$(cat "$D/config/api-key")
for i in $(seq 1 90); do
  curl -sf -m 3 -H "Authorization: Bearer $K" localhost:11500/health >/dev/null 2>&1 && { echo "flint up after $((i*2)) s, metrics -> $METRICS"; exit 0; }
  sleep 2
done
echo "flint did not come up"; tail -20 "$HOME/mac-tuning-logs/serve.log"; exit 1
