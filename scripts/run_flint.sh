#!/usr/bin/env bash
# Full Flint quality suite at one temperature, on the worker, from spark-tuning's harness (~/spark-quality).
#   scripts/run_flint.sh <temp> <label>        e.g. scripts/run_flint.sh 1.0 FLINT-t10
# Copied to the worker as ~/mac-quality/run_flint.sh; the API is the tunnel end at worker localhost:11500
# (scripts/tunnel_keep.sh), key in ~/mac-quality/flint_key.
# Differences from spark-tuning's run_deep.sh / run_quality.sh, all because of how Flint and rec work:
#   - MAX_TOKENS (default 32768) for every task: Flint always reasons and its model card asks for >= 32768 on hard
#     problems; 16384 truncated 8/10 LCB answers (results/FLINT-TTS-t06, 2026-10-24).
#   - CONCURRENCY=1 everywhere: rec runs one generation at a time anyway, and at 1 every per-request elapsed_s is a
#     time-to-solve sample. The time-to-solve subsets (HE+ every 4th, LCB every 8th, as run_tts.sh) are cut from these
#     full runs by tts_from_full.py instead of being generated twice (same requests, same seeds).
#   - MBPP+ / GSM8K go through quality_eval.py gen with NOTHINK_KWARGS='{}' (no reasoning switch exists) and
#     NOTHINK_TEMP=<temp> (top_k omitted, server default 20). NLL is skipped (rec has no prompt logprobs).
# LCB_DATA: LCB problem file under data/ (default lcb80.jsonl; atc147.jsonl = the contamination set from atcoder_prep.py).
# TASKS (default "humaneval lcb mbpp gsm8k"; at T=0 without gsm8k, see below) selects a subset. Everything is resumable: rerun to continue.
set -uo pipefail
T="${1:?usage: run_flint.sh <temp> <label>}"; L="${2:?usage: run_flint.sh <temp> <label>}"
MAX=${MAX_TOKENS:-32768}
# GSM8K is skipped at temperature 0 (user's call, 2026-10-25): every model here scores ~96% on it (Flint 96.3 at T=1.0, the
# Spark models 96.3-96.5), so it cannot separate temperatures or models, and at T=0 it would cost ~4.5 h of the ~11 h run.
DEFAULT_TASKS="humaneval lcb mbpp gsm8k"; [ "$T" = 0 ] && DEFAULT_TASKS="humaneval lcb mbpp"
TASKS="${TASKS:-$DEFAULT_TASKS}"
has() { [[ " $TASKS " == *" $1 "* ]]; }
W="$HOME/spark-quality"; OUT="$W/results/$L"; mkdir -p "$OUT"; cd "$W"
IMG=spark-quality:evalplus-0.3.1
NET=(docker run --rm --network host -u "$(id -u):$(id -g)" -e HOME=/tmp -e XDG_CACHE_HOME=/cache
     -e API=http://localhost:11500 -e API_KEY="$(cat ~/mac-quality/flint_key)" -e MODEL=flint -e CONCURRENCY=1
     -e GSM8K=/data/gsm8k_test.jsonl -e THINK_KWARGS='{}' -e NOTHINK_KWARGS='{}' -e NOTHINK_MAX_TOKENS="$MAX"
     -e THINK_TEMP="$T" -e THINK_TOP_P=0.95 -e THINK_TOP_K=20 -e NOTHINK_TEMP="$T" -e NOTHINK_TOP_P=0.95
     -v "$W":/work -v "$W/cache":/cache -v "$W/data":/data $IMG)
BOX=(docker run --rm --network none --memory 6g --pids-limit 512 --cpus 8 -u "$(id -u):$(id -g)" -e HOME=/tmp -e XDG_CACHE_HOME=/cache
     -v "$W":/work:ro -v "$W/cache":/cache -v "$W/data":/data -v "$OUT":/out $IMG)
echo "=== $(date -u +%FT%TZ) $L temp $T max_tokens $MAX tasks: $TASKS"
if has humaneval; then
  echo "=== $(date -u +%T) $L HE+"
  "${NET[@]}" python3 deep_eval.py gen-think --task humaneval --max-tokens "$MAX" --out "results/$L/he_think.jsonl"
  rm -f "$OUT/he_think_eval_results.json"
  "${BOX[@]}" evalplus.evaluate --dataset humaneval --samples /out/he_think.jsonl --parallel 8 --i-just-wanna-run 2>&1 \
    | grep -E "pass@|base|plus" | tee "$OUT/he_think_score.txt"
fi
if has lcb; then
  echo "=== $(date -u +%T) $L LCB"
  "${NET[@]}" python3 deep_eval.py gen-think --task lcb --data "/data/${LCB_DATA:-lcb80.jsonl}" --max-tokens "$MAX" --out "results/$L/lcb_think.jsonl"
  "${BOX[@]}" python3 deep_eval.py lcb-exec --data "/data/${LCB_DATA:-lcb80.jsonl}" --gen /out/lcb_think.jsonl | tee "$OUT/lcb_score.txt"
fi
for t in mbpp gsm8k; do
  has $t || continue
  echo "=== $(date -u +%T) $L $t"
  "${NET[@]}" python3 quality_eval.py gen --task $t --out "results/$L/$t.jsonl"
done
if has mbpp; then
  rm -f "$OUT/mbpp_eval_results.json"
  "${BOX[@]}" evalplus.evaluate --dataset mbpp --samples /out/mbpp.jsonl --parallel 8 --i-just-wanna-run 2>&1 \
    | grep -E "pass@|base|plus" | tee "$OUT/mbpp_score.txt"
fi
has gsm8k && "${NET[@]}" python3 quality_eval.py gsm8k-score "results/$L/gsm8k.jsonl" | tee "$OUT/gsm8k_score.txt"
echo "=== $(date -u +%T) $L suite done"
