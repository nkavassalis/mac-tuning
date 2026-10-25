#!/usr/bin/env python3
"""Time to solve, cut from a full concurrency-1 run (scripts/run_flint.sh) instead of a separate run_tts.sh pass.

Same subsets as spark-tuning's quality/run_tts.sh: HumanEval+ every 4th problem (41), LiveCodeBench every 8th of lcb80 (10).
At concurrency 1 each request's elapsed_s is the wall clock to answer it, and deep_eval.py seeds each request with
crc32(task_id), so these are the same requests run_tts.sh would send.
  tts_from_full.py <results dir> [<lcb80.jsonl>]      prints a report, also writes <dir>/tts_from_full.json
Also reports how many answers used the whole token budget (truncated: rec returns no finish_reason on those).
Stdlib only.
"""
import json, os, sys

d = sys.argv[1]
lcb_data = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser("~/spark-quality/data/lcb80.jsonl")
rows = lambda f: [json.loads(l) for l in open(os.path.join(d, f))]
out = {}

def report(name, recs, ok, budget):
    n = len(recs); k = sum(ok[r["task_id"]] for r in recs); T = sum(r["elapsed_s"] for r in recs)
    cut = sum(r["completion_tokens"] >= budget for r in recs)
    out[name] = {"n": n, "solved": k, "wall_s": round(T, 1), "s_per_problem": round(T / n, 1),
                 "s_per_solved": round(T / max(k, 1), 1), "mean_tokens": round(sum(r["completion_tokens"] for r in recs) / n),
                 "at_budget": cut}
    print(f"{name}: solved {k}/{n}, {T/n:.1f} s/problem, {T/max(k,1):.1f} s per solved, "
          f"mean tokens {out[name]['mean_tokens']}, {cut} at the {budget}-token budget")

budget = int(os.environ.get("MAX_TOKENS", 32768))
if os.path.exists(os.path.join(d, "he_think_eval_results.json")):
    ev = json.load(open(os.path.join(d, "he_think_eval_results.json")))["eval"]
    ok = {t: v[0]["base_status"] == "pass" and v[0]["plus_status"] == "pass" for t, v in ev.items()}
    he = rows("he_think.jsonl")
    report("HE+ full (164)", he, ok, budget)
    report("HE+ TTS subset (every 4th)", [r for r in he if int(r["task_id"].split("/")[1]) % 4 == 0], ok, budget)
if os.path.exists(os.path.join(d, "lcb_think_scored.json")):
    ok = json.load(open(os.path.join(d, "lcb_think_scored.json")))["per_task"]
    lcb = {r["task_id"]: r for r in rows("lcb_think.jsonl")}
    sub = [json.loads(l)["task_id"] for l in open(lcb_data)][::8]
    report("LCB full (80)", list(lcb.values()), ok, budget)
    report("LCB TTS subset (every 8th)", [lcb[t] for t in sub], ok, budget)
json.dump(out, open(os.path.join(d, "tts_from_full.json"), "w"), indent=1)
