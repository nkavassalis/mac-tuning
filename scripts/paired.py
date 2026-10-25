#!/usr/bin/env python3
"""Paired McNemar test (exact, two-sided) between runs of one task, the same test spark-tuning's `deep_eval.py compare` runs on
LiveCodeBench, extended to evalplus results (HumanEval+ / MBPP+, "plus" = base and extra tests pass).
  scripts/paired.py <ref> <other> [...]
Each argument is a scored file: `*_eval_results.json` (evalplus) or `lcb_*_scored.json` (deep_eval). The first is the reference;
every row prints its pass rate on the shared tasks, problems lost / gained against the reference, and p. Stdlib only."""
import json, math, sys


def per_task(path):
    d = json.load(open(path))
    if "per_task" in d:
        return d["per_task"]
    return {t: r[0]["base_status"] == "pass" and r[0]["plus_status"] == "pass" for t, r in d["eval"].items()}


def main(files):
    ref = per_task(files[0])
    print(f"{'file':<58} {'n':>4} {'acc %':>6} {'lost':>5} {'gained':>6}  McNemar p")
    for f in files:
        x = per_task(f); ks = sorted(set(ref) & set(x))
        lost = sum(1 for k in ks if ref[k] and not x[k]); gained = sum(1 for k in ks if x[k] and not ref[k])
        n = lost + gained
        p = min(1.0, 2 * sum(math.comb(n, i) for i in range(min(lost, gained) + 1)) / 2 ** n) if n else 1.0
        print(f"{f:<58} {len(ks):>4} {100 * sum(x[k] for k in ks) / len(ks):>6.1f} {lost:>5} {gained:>6}  p={p:.3f}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main(sys.argv[1:])
