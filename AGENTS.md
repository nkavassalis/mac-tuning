Project mode: REAL

# AGENTS.md: mac-tuning

## Purpose
Public notes, scripts and measured results from running Recursive **Flint** (40B MoE, ~2.5B active, 262K context) on one
**Mac mini M4 Pro, 64 GB**, with Recursive's `rec` runtime (MLX, int4). Sister repo of
[spark-tuning](https://github.com/nkavassalis/spark-tuning), whose quality harness (`quality/`) and decode benchmark
(`spark-tuning/scripts/bench_decode.py`) are reused unmodified so the numbers line up with the Spark models.
- Flint int4 under `rec` 0.1.0: set up and benchmarked 2026-10-24/25 (speed, quality and time to solve at T = 1.0 / 0.6 / 0): `FLINT.md`.
- Contamination check (2026-10-25): Flint int4 vs Qwen FP4-Local on 147 post-cutoff AtCoder problems (`scripts/atcoder_prep.py`,
  samples-only scoring), FLINT.md "Testing for contamination". The Q8_0 follow-up was dropped (user's call, 2026-10-25).
Goal: is a 64 GB Mac a credible single-user coding-agent server, and how does it compare with the 2-node Spark cluster?

## THE PUBLIC RULE (read first)
**This repo is PUBLIC on GitHub.** It must never contain:
- IPs, hostnames/machine names, usernames, home-directory paths, network details;
- tokens or credentials of any kind (the `rec` API key, HF token, GitHub token, etc.).
Real values live only in the untracked `mac.env` (template `mac.env.example`). Results JSON contain the URL used: sed it to
`<mac>` before committing. Before every commit run:
```bash
git diff --cached | grep -nE '([0-9]{1,3}\.){3}[0-9]{1,3}|/home/|/Users/|hf_[A-Za-z0-9]{10,}|gh[pousr]_[A-Za-z0-9]{10,}'
```
and inspect every hit (`scripts/check_repo.py` runs the same scan over the tree).

## Layout
| Path | Responsibility |
|---|---|
| `README.md` | human entry point: results summary, setup, how to rerun |
| `FLINT.md` | Flint int4 write-up: setup, memory/KV, speed, quality and time to solve per temperature, vs the Spark models |
| `mac.env.example` | template for the untracked `mac.env` (MAC, MAC_KEY, WORKER, SPARK) |
| `scripts/serve.sh` | run on the Mac: the exact `rec serve` command line plus `--metrics` (per-request engine JSONL) |
| `scripts/install_launchd.sh [--uninstall]` | run on the Mac: Flint (`rec serve`, same command line as `serve.sh`) and the LAN relay as user LaunchAgents, started at boot and restarted if they exit |
| `scripts/flint_relay.py` | stdlib TCP relay, LAN `:11502` -> `127.0.0.1:11500` (rec binds loopback only); copied to `~/mac-tuning-svc/` on the Mac |
| `scripts/power_modes.sh` | decode speed and CPU+GPU power in each macOS power mode (`pmset powermode` 1 / 0 / 2), through the relay |
| `scripts/tunnel_keep.sh` | self-healing two-leg SSH tunnel: Mac 127.0.0.1:11500 -> here :11501 -> worker 127.0.0.1:11500 (nothing on the LAN) |
| `scripts/run_flint.sh` | on the worker: the full quality suite at one temperature, 32K budget, concurrency 1 |
| `scripts/tts_from_full.py` | time-to-solve subsets cut from the concurrency-1 full runs; budget-hit counts |
| `scripts/paired.py` | paired McNemar test (evalplus `*_eval_results.json` and LCB `*_scored.json`) |
| `scripts/atcoder_prep.py` | contamination set: post-cutoff ABC/ARC problems -> LCB-format jsonl (samples as tests; drops interactive, tolerance, any-answer) |
| `scripts/strata.py` | LCB pass rates by difficulty / contest / letter |
| `scripts/matrix.sh` | the whole matrix from here: speed bench, then `run_flint.sh` at each temperature |
| `scripts/check_repo.py` | offline: leak scan, paths named in docs exist |
| `LICENSE` | MIT |
| `results/` | raw outputs (`results/<date>/` speed, `results/quality/FLINT-*` quality) |

## How to run
```bash
cp mac.env.example mac.env                         # fill in (never commit)
scp scripts/flint_relay.py "$MAC":mac-tuning-svc/          # once (mkdir -p ~/mac-tuning-svc on the Mac)
ssh -i "$MAC_KEY" "$MAC" 'bash -s' < scripts/install_launchd.sh   # Flint + relay as LaunchAgents (start at boot)
# or, without launchd: ssh -i "$MAC_KEY" "$MAC" 'bash -s' < scripts/serve.sh   (one-off rec serve with --metrics)
scripts/tunnel_keep.sh &                           # keep the tunnel up
scp scripts/run_flint.sh scripts/tts_from_full.py "$WORKER":mac-quality/   # + the API key in ~/mac-quality/flint_key
scripts/matrix.sh                                  # speed, then quality at TEMPS="1.0 0.6 0"
```
The worker needs spark-tuning's harness checked out as `~/spark-quality` (its `quality/` dir) with the `spark-quality:evalplus-0.3.1` image.

## How to run the tests
```bash
scripts/check_repo.py
bash -n scripts/*.sh; python3 -m py_compile scripts/*.py
```

## Design decisions and why
- **Harness reused, not forked**: same prompts, seeds (`crc32(task_id)`), sandbox and scoring as spark-tuning, so a Flint number and a
  Spark number differ only in the model/server (and the budget, stated wherever it differs).
- **32K thinking budget**: Flint always reasons; its model card asks for >= 32768 tokens on hard problems, and 16K truncated 8/10 LCB
  answers. spark-tuning's LCB was rerun at 32K for the comparison (2026-10-24/25).
- **Concurrency 1**: `rec` runs one generation at a time (admission queue of 9, then 429), so parallel requests only queue; at 1 every
  request's wall clock is a time-to-solve sample.
- **Harness runs on the Spark worker, through a tunnel**: it has docker, the image, the data and the sandbox already; the Mac serves only.
  The tunnel binds loopback on all three hops so the API is never exposed on the LAN. **Superseded 2026-10-29:** Flint now also
  serves the LAN through `scripts/flint_relay.py` (`:11502`) so pi on another machine can call it (the private pi-escalation
  repo). rec's API key still guards every request (401 without it), but the traffic is plain HTTP, so anyone who can read LAN
  traffic can read the key. The benchmarks above all ran through the tunnel.
- **launchd, not nohup** (2026-10-29): `scripts/install_launchd.sh` installs `local.flint.serve` and `local.flint.relay` in
  `~/Library/LaunchAgents` with `RunAtLoad` + `KeepAlive`. They are user agents, so they start when the user logs in, and the
  Mac logs in automatically at boot. No root is needed. Logs go to `~/mac-tuning-logs/{serve,relay}.log`. The relay runs on the
  system `/usr/bin/python3`, Flint on rec's bundled Python.
- **`--metrics`**: `rec serve` has no metrics flag, so `scripts/serve.sh` launches the same `rec_mlx` command `rec serve` runs, plus
  `--metrics <jsonl>`. Logging only; no serving setting differs.
- **Mac power**: High Power mode, sleep disabled, the earlier oMLX server and its model removed (2026-10-24). Power modes measured
  2026-10-29 (FLINT.md "Power modes"): Automatic = High Power in speed and watts. Low Power is ~1.5× slower at a third of the power.
  The Mac is still in High Power (2026-10-29).

## Conventions
- Every number in the docs is measured, with the result file next to it. Label anything unmeasured as unmeasured.
- Dates YYYY-MM-DD. Shell `set -euo pipefail` (runners that must survive one failed step use `set -uo pipefail`). Python stdlib only.

## Do-not-touch (ask the user first)
- Don't run anything else on the Mac during a speed or time-to-solve run.
- Don't touch unrelated files in the Mac's home directory.
- Don't change repo visibility, push secrets/site details, or rewrite history without asking.
