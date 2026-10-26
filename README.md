# mac-tuning

Measured notes on running **Recursive Flint** (40B MoE, ~2.5B active, 262K context) as a local coding model on one
**Mac mini M4 Pro, 64 GB**, with Recursive's [`rec`](https://docs.recursive.com/edge/rec) runtime (MLX int4). Sister repo of
[spark-tuning](https://github.com/nkavassalis/spark-tuning) (LLM serving on a 2-node DGX Spark cluster): its quality harness and
decode benchmark are reused unmodified, so the numbers here line up with the Spark models'.

**Full write-up: [FLINT.md](FLINT.md).** Headline (2026-10-25, int4 under `rec` 0.1.0, 32K thinking budget):

| | Flint int4, Mac, T=0.6 | Best Spark model (spark-tuning, 32K) |
|---|---|---|
| LiveCodeBench (80) | **71.2%** | 58.8% (MiMo, GLM FP4-Local) |
| Post-cutoff AtCoder (147, sample tests, 2026-10-26) | **68.0%** | 53.7% (Qwen FP4-Local `medium`; others not run) |
| HumanEval+ (164) | 91.5% | 95.7% (Qwen FP4-Local `medium`) |
| MBPP+ (378) | 79.1% | 83.6% (GLM FP4-Local `low`, thinking off) |
| Decode, 1K / 64K / 128K context | 114–120 / 45–51 / 26–31 tok/s | ~50–63 tok/s (Qwen FP4-Local, flat) |
| Cold prefill | ~600 tok/s ≤ 16K, ~250 tok/s at 100K+ | ~2,700 tok/s |
| Concurrent requests | 1 | 8 |

Flint is the strongest hard-problem solver measured on either machine and decodes fast at short context; it is slower to read long
prompts and serves one request at a time. On problems newer than its training data its lead shrinks by ~8 points but stays
significant (p≤0.0003), so contamination inflates the LiveCodeBench number somewhat without explaining it. T=0.6 (or 0) is as good as or better than the model card's 1.0 on every test but MBPP+ (0.3 points lower; no difference is significant).

## Layout

| Path | What |
|---|---|
| [FLINT.md](FLINT.md) | setup, speed, memory/KV, quality and time to solve at T = 1.0 / 0.6 / 0, comparison with the Spark models, contamination check |
| [AGENTS.md](AGENTS.md) | rules for working on this repo (public: no hosts, IPs, users, keys), design decisions |
| `scripts/serve.sh` | the exact `rec serve` launch plus `--metrics` (run on the Mac) |
| `scripts/tunnel_keep.sh` | loopback-only SSH tunnel from the Mac to the box that runs the harness |
| `scripts/run_flint.sh` | the whole quality suite at one temperature (runs next to spark-tuning's harness) |
| `scripts/tts_from_full.py` | time-to-solve subsets cut from the concurrency-1 runs |
| `scripts/paired.py` | paired McNemar test for evalplus and LiveCodeBench results |
| `scripts/atcoder_prep.py`, `scripts/strata.py` | contamination set (post-cutoff AtCoder problems, sample tests) and per-stratum breakdown |
| `scripts/matrix.sh` | speed bench, then the suite at each temperature |
| `scripts/check_repo.py` | leak scan and doc-path check, run before every commit |
| `results/` | raw outputs: `results/2026-10-24/` speed, `results/quality/FLINT-*` quality |

## Reproduce

```bash
cp mac.env.example mac.env                               # fill in (never commit)
ssh -i "$MAC_KEY" "$MAC" 'bash -s' < scripts/serve.sh     # rec installed on the Mac first (FLINT.md "Setup")
scripts/tunnel_keep.sh &
scripts/matrix.sh                                        # speed, then TEMPS="1.0 0.6 0"
```
The harness side needs a Linux box with docker and spark-tuning's `quality/` set up (its README "Tests" and `quality/` scripts).

## License

MIT, like spark-tuning.
