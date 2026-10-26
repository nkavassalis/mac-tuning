#!/usr/bin/env python3
"""Pass rate of LCB-format runs by stratum (difficulty, contest type, letter), for the contamination test (FLINT.md).
  scripts/strata.py <data.jsonl> <lcb_think_scored.json> [...]
data.jsonl is the problem file the runs were scored on (lcb80.jsonl or atc147.jsonl). Stdlib only."""
import collections, json, sys


def main(data, runs):
    meta = {}
    for line in open(data):
        d = json.loads(line); name = d["task_id"].split("/")[1]
        meta[d["task_id"]] = {"difficulty": d.get("difficulty"), "contest": name[:3],
                              "letter": d.get("letter") or name.split("_")[-1]}
    for key in ("difficulty", "contest", "letter"):
        groups = sorted({m[key] for m in meta.values()})
        print(f"{'by ' + key:<44}" + "".join(f"{g:>10}" for g in groups) + f"{'all':>10}")
        for r in runs:
            pt = json.load(open(r))["per_task"]; c = collections.defaultdict(lambda: [0, 0])
            for t, ok in pt.items():
                c[meta[t][key]][0] += ok; c[meta[t][key]][1] += 1
            cells = "".join(f"{f'{c[g][0]}/{c[g][1]}':>10}" for g in groups)
            print(f"{r[-44:]:<44}{cells}{f'{sum(pt.values())}/{len(pt)}':>10}")
        print()


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2:])
