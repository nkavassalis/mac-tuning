# Recursive Flint on a Mac mini M4 Pro (64 GB): speed, quality and time to solve

**Question (2026-10-24):** Recursive's [`rec`](https://docs.recursive.com/edge/rec) runs Flint (40B MoE, ~2.5B active, 262K
context) locally on a Mac. How fast is it, how good is it at code, and what does temperature do? And how does it compare with
the models on the 2-node DGX Spark cluster in [spark-tuning](https://github.com/nkavassalis/spark-tuning)?

**Status 2026-10-25:** the int4 suite under `rec` is done (speed; HumanEval+, MBPP+, GSM8K, LiveCodeBench and time to solve at
T = 1.0 / 0.6 / 0). Next, queued (user's call, 2026-10-24): a community Q8_0 GGUF under llama.cpp, to see whether the 64 GB
headroom buys quality (below, "Next: Q8_0"). Also planned: a contamination check on AtCoder problems newer than Flint's
knowledge cutoff ("Testing for contamination").

## Summary

- **Best LiveCodeBench measured on either machine.** Flint scores 65.0 / **71.2** / 70.0% at T = 1.0 / 0.6 / 0 on the 80
  problems spark-tuning uses, at a 32K thinking budget. At the same 32K budget the Spark models reach 48.8–58.8%. Flint at T=0.6
  beats every Spark run at 32K, paired: Qwen FP4-Local `medium` / `xhigh` (p<0.001), MiMo (p=0.006–0.007) and GLM FP4-Local
  (p≤0.002). At T=1.0 the gap to MiMo and GLM is not significant (p=0.11–0.18).
- **Weaker on easy code.** HumanEval+ 88.4–91.5% vs Qwen FP4-Local `medium` 95.7% (p=0.039 against Flint's best run). MBPP+
  79.1–79.4%: ties Qwen's thinking-off run, below GLM FP4-Local `low` (83.6%, p=0.006), above MiMo thinking off (75.4%, p=0.044).
- **Temperature: T=0.6 or T=0, not the model card's 1.0.** Every test but MBPP+ (79.1 vs 79.4) is equal or better at 0.6 than at 1.0,
  but no single difference is significant (LCB 71.2 vs 65.0, p=0.18; HE+ 91.5 vs 88.4, p=0.18). T=0 lands between them.
- **Speed (single user):** decode **114–120 tok/s at 1K** context, 84–91 at 16K, 45–51 at 64K, 26–31 at 128K. Prefill is the
  weak point: ~600 tok/s up to 16K, ~270 tok/s at 100K+, so a cold 100K-token prompt takes **6.5–9 minutes** before the
  first token. The Spark's Qwen prefills ~2,700 tok/s.
- **Time to solve:** HumanEval+ 16–24 s per problem (T=0.6 fastest; Qwen FP4-Local `medium` on the Spark: 14.3 s). LiveCodeBench
  subset 4–5 of 10 solved at 269–311 s per problem; every Spark model solved 1–3 of the same 10, at 564–717 s.
- **Memory:** 23 GB resident, 31.7 GB peak on a 123K-token prompt. The KV cache is ~28.5 KiB per token, so the full 262K context
  fits with half the Mac free.
- **`rec` 0.1.0 crashed after 30 h / 4,542 requests** (10.5M generated tokens): `[metal::malloc] Resource limit (499000) exceeded`,
  then HTTP 503 on every request until restarted. Looks like a Metal buffer leak; it would hit a long-running agent server too.
  A restart fixed it (details under Caveats).
- **One request at a time.** `rec` 0.1.0 serves a single generation; parallel requests queue. Fine for one agent, not for several.
  A long cold prompt blocks everything behind it for minutes.
- **Needs a 32K budget.** Flint always reasons and its model card asks for at least 32,768 tokens on hard problems: at 16K, 8 of
  10 LCB subset answers hit the cap. At 32K, 19–21 of 80 still do.

## Setup

Hardware: Mac mini, Apple M4 Pro, 64 GB unified memory, macOS 27.0.1. High Power mode on (`pmset powermode 2`, set by the user), system
sleep off (`caffeinate`), the earlier oMLX server and its model removed (2026-10-24). Nothing else runs on it.

Server: `rec` 0.1.0, installed with Recursive's one-liner
(`curl -fsSL https://raw.githubusercontent.com/recursive-oss/rec/main/install.sh | bash`), model `flint-int4` (MLX 4-bit, 21 GB on
disk). `scripts/serve.sh` starts the same `rec_mlx` command line that `rec serve` runs (read off the process on 2026-10-24) plus
`--metrics`, which logs per-request engine counters (prefill/decode time, cached prompt tokens, peak memory). No serving setting
differs. Context limit 262,144, bf16 KV cache, API key on, bound to 127.0.0.1.

Client: spark-tuning's harness (`quality/`), unmodified, running on a Spark worker with docker and the sandbox image, reaching the Mac
through a loopback-only SSH tunnel (`scripts/tunnel_keep.sh`). `scripts/run_flint.sh` runs the whole suite at one temperature.
What differs from the Spark runs, and why:
- **32K budget for everything** (`max_tokens` 32,768): Flint has no switch to turn reasoning off, and its card asks for ≥ 32K.
  spark-tuning's LiveCodeBench was rerun at 32K for this comparison (spark-tuning COMPARISON.md, "Thinking budget 32K instead
  of 16K").
- **MBPP+ / GSM8K go through the harness's thinking-off path** with an empty `chat_template_kwargs` (there is nothing to turn
  off), at the run's temperature, so Flint reasons on them while the Spark models ran them with thinking off.
- **Concurrency 1**: `rec` runs one generation at a time anyway, so every request's wall clock is a time-to-solve sample. The
  time-to-solve subsets (every 4th HumanEval+, every 8th LiveCodeBench problem, as spark-tuning's `run_tts.sh`) are cut from the
  full runs by `scripts/tts_from_full.py` instead of being generated a second time.
- **Sampling:** top_p 0.95, top_k 20 (the card's), temperature 1.0 / 0.6 / 0. The server fills in top_k 20 when a request omits it.
- **No NLL / long-context tests**: `rec` returns no prompt logprobs, and the harness's long-context test needs them.
- **GSM8K skipped at T=0** (user's call, 2026-10-25): every model here scores ~96% (Flint 96.3 / 96.6 at 1.0 / 0.6; the Spark
  models 96.3–96.5), so it can't separate temperatures or models, and it would have cost ~4.5 h of the T=0 run.

Seeds are per task (`crc32(task_id)`), as in spark-tuning. Under `rec` they reproduce: the 32K run at T=0.6 returned the 16K run's
answers token for token where they finished under 16K, and continued them where they didn't. (The Spark's vLLM servers don't
reproduce a seeded sample; spark-tuning COMPARISON.md.)

## Speed (`spark-tuning/scripts/bench_decode.py`, 1,000 decode tokens, nothing else on the Mac)

Client-side, through the tunnel; `code` and `edit` prompts at four context sizes, temperature 0 and 1.0
(`results/2026-10-24/flint-speed.json`). Every prompt has a unique prefix, so no cache hits.

| Context target | Prompt tokens | Time to first token | Decode tok/s | Prefill tok/s |
|---|---|---|---|---|
| 1K | 823–998 | 1.2–1.6 s | **114–120** | ~670 |
| 16K | 12,823–15,414 | 21–27 s | 84–91 | ~565–610 |
| 64K | 51,223–61,630 | 128–169 s | 45–51 | ~360–400 |
| 128K | 102,423–123,485 | 377–528 s | 26–31 | ~235–272 |

Temperature makes no difference (≤ 6% either way, in both directions). Decode falls with context because 14 of Flint's 49 layers
are full attention over the whole prompt; prefill falls for the same reason. For comparison, the Spark's Qwen FP4-Local decodes
~63 tok/s (thinking off) to ~50 (thinking on) roughly flat with context, and prefills ~2,700 tok/s at 32K–64K (spark-tuning
FP4LOCAL.md): **Flint on the Mac decodes faster up to ~16K and slower by 64K, and prefills 4–10× slower.**

The engine's own decode rate (from `--metrics`) agrees: 94–115 tok/s on the quality runs, lower on the longest answers.

## Memory and KV cache (engine `--metrics`, 2026-10-24/25)

- Weights 21–22.6 GB on disk; **23.1 GB resident** after loading (process peak RSS).
- **Peak 31.7 GB** (MLX peak) on the 123,485-token speed prompt, KV allocated for 131,072 tokens.
- KV is small: only 14 of 49 layers hold full attention (4 KV heads × 128), the other 35 use a 513-token sliding window (a fixed
  2–74 MB in the metrics). 1,915,826,176 bytes for 65,536 tokens of capacity = **~28.5 KiB per token**; it grows in 65,536-token steps.
- So the full 262K context would be ~7.7 GB of KV, **~33–35 GB total (estimate; no 262K request was run)**. The 64 GB Mac
  caps context at the model's 262K positions, not at memory. macOS's GPU working-set limit is 60.1 GB.
- Prefix cache: `rec` keeps the previous prompt so the next turn of a conversation can skip re-prefill. The speed bench defeats it
  by design (unique prefixes); a repeated short prompt did hit (14/14 tokens cached). Its behaviour on a real agent session (how
  much of a 100K history it reuses) is **not measured**, and it matters more here than on the Spark given the prefill speed.

## Quality (spark-tuning's harness, data and sandbox; 32K budget; one run per cell)

| Test | T=1.0 (card) | **T=0.6** | T=0 | Best Spark run (spark-tuning) |
|---|---|---|---|---|
| HumanEval+ (164), base / plus | 97.6 / 88.4 | 97.6 / **91.5** | 96.3 / 90.2 | 95.7 Qwen FP4-Local `medium` (16K) |
| MBPP+ (378), base / plus | 94.7 / 79.4 | 94.2 / 79.1 | 93.7 / 79.1 | 83.6 GLM FP4-Local `low` (thinking-off path) |
| GSM8K (1319) | 96.29 | **96.59** | — (skipped) | 96.5 |
| **LiveCodeBench (80)** | 65.0 | **71.2** | 70.0 | 58.8 MiMo / GLM FP4-Local, 32K |
| LCB answers at the 32K cap | 21 | 19 | 19 | 28–36 |
| LCB mean completion tokens | 16,983 | 16,608 | 16,872 | 13,800–18,667 |

Paired (McNemar, exact; `scripts/paired.py` for evalplus results, spark-tuning's `deep_eval.py compare` for LCB):
- **Temperature:** nothing significant. LCB 0.6 vs 1.0: 2 lost / 7 gained, p=0.18; 0 vs 0.6: 5 / 4, p=1.0. HE+ 0.6 vs 1.0 p=0.18,
  0 vs 0.6 p=0.77. MBPP+ 0.6 vs 1.0: 11 / 10, p=1.0; 0 vs 0.6: 9 / 9, p=1.0.
- **LCB vs the Spark at 32K** (the Spark runs from spark-tuning COMPARISON.md; problems Flint solved and the other didn't / the reverse):

  | Spark run (32K) | LCB | vs Flint T=0.6 | vs Flint T=0 | vs Flint T=1.0 |
  |---|---|---|---|---|
  | Qwen FP4-Local `medium`, T=0.6 | 51.2 | 16 / 0, p<0.001 | 17 / 2, p=0.001 | 12 / 1, p=0.003 |
  | Qwen FP4-Local `xhigh`, T=0.6 | 48.8 | 18 / 0, p<0.001 | 19 / 2, p<0.001 | 14 / 1, p=0.001 |
  | MiMo, T=1.0 | 58.8 | 11 / 1, p=0.006 | 10 / 1, p=0.012 | 7 / 2, p=0.18 |
  | MiMo, T=0.6 | 57.5 | 13 / 2, p=0.007 | 12 / 2, p=0.013 | 8 / 2, p=0.11 |
  | GLM FP4-Local `high`, T=1.0 | 58.8 | 10 / 0, p=0.002 | 12 / 3, p=0.035 | 7 / 2, p=0.18 |
  | GLM FP4-Local `high`, T=0.6 | 48.8 | 19 / 1, p<0.001 | 17 / 0, p<0.001 | 14 / 1, p=0.001 |

- **HE+:** Qwen FP4-Local `medium` (16K, T=0.6) over Flint T=0.6: 1 lost / 8 gained, **p=0.039**. MiMo thinking on and GLM
  FP4-Local `high`: ties (p ≥ 0.79).
- **MBPP+** (Spark runs are thinking off; Flint reasons): GLM FP4-Local `low` T=0.6 over Flint, **p=0.006**; Flint over MiMo
  thinking off T=0.6, **p=0.044**; Qwen FP4-Local thinking off: tie (p=0.73).

Reading it: Flint is a strong competitive-programming reasoner (it solves more of the hard LCB problems than any Spark model, and
finishes more of them inside 32K), and an average-to-good everyday coder (HE+/MBPP+ in the Spark models' range, below Qwen on
HE+). LiveCodeBench is the test that matters most for "hard problem, agent waits"; HE+/MBPP+ are closer to the edit-and-test loop.

## Time to solve (concurrency 1, nothing else on the Mac; cut from the full runs)

Every 4th HumanEval+ problem (41) and every 8th LiveCodeBench problem (10), the subsets spark-tuning times
(`results/quality/FLINT-*/tts_from_full.json`; the full sets in the same file).

| Setting | HE+ solved / 41 | s per problem | s per solved | mean tokens | LCB solved / 10 | s per problem | at the cap |
|---|---|---|---|---|---|---|---|
| Flint T=1.0 | 35 | 18.6 | 21.7 | 1,963 | 4 | 311 | 4 |
| **Flint T=0.6** | 36 | **15.9** | 18.1 | 1,741 | **5** | **282** | 4 |
| Flint T=0 | **37** | 24.4 | 27.1 | 2,555 | **5** | **269** | 4 |
| Flint T=0.6, **16K** (`results/quality/FLINT-TTS-t06`) | 36 | 16.2 | — | — | 1 | — | 8 |
| Spark, Qwen FP4-Local `medium`, 32K | 36 | 14.3 | 16.3 | 935 | 1 | 564 | 9 |
| Spark, MiMo thinking on, 32K | 37 | 22.1 | 24.5 | 1,005 | 1 | 717 | 8 |
| Spark, GLM FP4-Local `high`, 32K | 37 | 9.0 | 10.0 | 370 | 3 | 628 | 6 |

Flint writes ~2× the tokens of Qwen `medium` on easy problems and decodes ~2× faster, so HumanEval+ time per problem is about the
same as the Spark's Qwen. On the hard subset it solves more and spends about half the time per problem of any Spark model at 32K,
because it finishes more answers before the cap. n=10 is small: against each Spark run Flint T=0.6 solved 3–4 subset problems
the other didn't and lost at most 1, p ≥ 0.125 on its own. The full-run LCB numbers (186–198 s per problem over all 80) say the
same thing with more problems.

## Why a "small" model on a small machine scores this well (theories, 2026-10-25; none tested yet)

Written down after the suite finished, as candidate explanations. Each is labelled with the evidence it rests on; the last one
could undo the others, and the next section is the test for it.

1. **The hardware sets the speed, not the quality.** Answers come from the weights. The Mac only makes each answer take longer;
   the same checkpoint, quantization and sampling on a faster box would give the same answers sooner. What *could* cost quality
   here is the int4 quantization, and Flint still came out on top (the Q8_0 run below measures how much int4 costs).
2. **It isn't small.** 40B parameters in total hold the knowledge; only ~2.5B are active per token. The small active count is what
   makes it fast, not shallow. (Model card figures.)
3. **It looks trained for exactly this kind of test.** LiveCodeBench is contest programming, which rewards models trained with
   reinforcement learning on verifiable code and math. Flint is the newest model in the comparison (vLLM's day-0 post is dated
   2026-10-21) and its profile fits: best on the hard contest problems, weaker on HumanEval+ (91.5 vs Qwen's 95.7, p=0.039), whose
   extra tests mostly catch missed edge cases in simple functions, which favours broad, careful coders over deep reasoners.
   (Inference from the score pattern; Recursive doesn't publish its training mix.)
4. **It finishes its reasoning inside the budget.** All the models write about the same amount on LiveCodeBench (mean 14–19K
   tokens), but only 19–21 of Flint's 80 answers hit the 32K cap, against 28–36 for the Spark models. Qwen FP4-Local still hits
   32K on 36 problems, so part of its gap may be budget alone; a 64K rerun would show how much (not run).
5. **Contamination: the main doubt.** The 80 problems are AtCoder contests from 2025-01-11 to 2025-04-06, 15 months before Flint's
   stated knowledge cutoff (June 2026, model card) and also before the Spark models' releases. A model whose training data
   includes these problems, their editorials or accepted solutions would score higher for that reason, and the newest model is
   the most likely to have seen them. That would inflate 3 and 4, and nothing in this suite can tell it apart from skill.

Why it's fast *on a Mac* in particular: decode is limited by memory bandwidth. At 4 bits, 2.5B active parameters is roughly
1.3–1.5 GB read per token; at the M4 Pro's 273 GB/s (Apple's spec) that's a ceiling around 180–200 tok/s, and it measures 114–120 at
1K context (arithmetic estimate, not profiled). Prefill is limited by compute instead, where the Spark's GPU wins by 4–10×: hence a
6–9 minute wait on a cold 100K-token prompt.

### Testing for contamination: problems newer than Flint (planned, not run)

No public benchmark post-dates Flint's June 2026 cutoff: the newest LiveCodeBench release (v6) ends in April 2025, and AtCoder no
longer publishes full test data. AtCoder ABC 466–481 (2026-07-04 to 2026-10-24) are all after the cutoff, and problems C–G of those
16 contests give 80 problems, but only with the 1–4 sample tests in each statement. Samples-only scoring was checked on the current
80 problems, where both exist, by rescoring every 32K run on the public tests alone:

| Run (32K) | Full tests | Samples only |
|---|---|---|
| Flint T=0.6 / T=0 / T=1.0 | 71.2 / 70.0 / 65.0 | 76.2 / 75.0 / 71.2 |
| Qwen FP4-Local `medium` / `xhigh` | 51.2 / 48.8 | 53.8 / 53.8 |
| MiMo T=1.0 / T=0.6 | 58.8 / 57.5 | 62.5 / 62.5 |
| GLM FP4-Local `high` T=1.0 / T=0.6 | 58.8 / 48.8 | 62.5 / 55.0 |

Samples-only reads 2.5–6 points high for every run and keeps the order, so it is fine for comparing models. The test: Flint's lead
over Qwen FP4-Local on the new problems, against its samples-only lead on the old ones (+22 points, 76.2 vs 53.8). If the lead holds
on problems nobody could have trained on, contamination isn't the explanation; if it collapses, it was.

## Flint on the Spark cluster: not run (user's call, 2026-10-25)

Considered and deferred. If revisited: Recursive's [NVFP4 GGUF](https://huggingface.co/RecursiveSI/flint-nvfp4-gguf) (22.9 GB,
quantization-aware trained, the card lists DGX Spark) on **one** Spark (TP=1), with vLLM PR
[#62938](https://github.com/vllm-project/vllm/pull/62938) plus a GB10 kernel-gate patch, as in the community
[single-Spark recipe](https://github.com/prestonlogan/Flint-vLLM-Single-DGX-Spark). That recipe reports 84–86 tok/s single-stream
decode on the stock W4A16 path and ~135 tok/s with an experimental faster decode kernel (third-party numbers, **not measured
here**). TP=2 across both Sparks is unlikely to help: ~2.5B active parameters make each token ~7 ms of compute, two all-reduces per
layer over the 200G link add a few ms (estimate), the model fits one node ~5× over, and Flint's fast kernels are TP=1-only
([vLLM blog](https://vllm.ai/blog/2026-10-21-flint)).

## Next: Q8_0 (queued)

Goal (user's, 2026-10-24): does the 64 GB Mac's headroom buy quality? `rec` can't load 8-bit weights (its loader asserts 4-bit), and
BF16 (79.6 GB) doesn't fit, so the candidate is a community Q8_0 GGUF (~42 GB) under a llama.cpp build that supports Flint, run
through the same suite and compared paired against the int4 runs above. **Caveats to carry into that comparison:** the runtime
changes with the quantization (llama.cpp vs MLX), so a difference can't be pinned on 8 bits alone; there's no Q4 llama.cpp control
run; and Q8_0 is a community conversion, not an official release.

## Caveats / not measured

- One run per quality cell; time-to-solve subsets are small (41 / 10). The spread between the three temperatures (LCB 65.0–71.2) is
  a fair guide to run-to-run noise here.
- MBPP+ and GSM8K compare a reasoning Flint with thinking-off Spark runs.
- The Spark's LCB 32K reruns sampled at concurrency 8 on servers that don't reproduce seeds; Flint ran at concurrency 1 and does.
  Neither affects scoring, but the Spark 16K-vs-32K pairs are independent draws.
- Speed is client-side through an SSH tunnel; at these rates (≤ 120 tok/s of small JSON chunks) the tunnel cost is negligible, but
  it wasn't measured separately.
- **Stability:** on 2026-10-25 at 20:40 UTC, after 30 h 17 min of uptime and 4,542 completed requests, `rec` began failing every
  request with `RuntimeError: [metal::malloc] Resource limit (499000) exceeded` in the KV-cache write, and answered 503 (even
  `/health`) until restarted. 499,000 is Metal's per-process buffer-allocation limit, so something allocates buffers it never
  frees. It cost the last 33 MBPP+ problems at T=0, which were rerun after a restart (same seeds; resumable harness). Not
  reproduced or bisected; a periodic restart would avoid it on a long-running server.
- Not measured: a real agent session (task success, wall clock, prefix-cache reuse on a growing history), tool calling, a 262K
  request, long-context quality, thermal behaviour over many hours.
