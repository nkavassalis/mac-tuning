#!/usr/bin/env python3
"""Build a LiveCodeBench-format problem set from AtCoder contests newer than a cutoff (the contamination test, FLINT.md).
  scripts/atcoder_prep.py --raw DIR --out atc.jsonl [--after 2026-07-01] [--before 2026-10-26]
Fetches the contest archive and every task page of each ABC / ARC in the window (English statement, 1 request per second;
pages are cached in DIR, so a rerun downloads nothing), converts each statement to the plain-text layout of
`livecodebench/code_generation_lite` and writes one row per problem in the format of spark-tuning's `lcb80.jsonl`
(task_id, question, difficulty, platform, contest_date, tests), plus letter / score. Tests are the statement's samples only:
AtCoder no longer publishes full test data.
Dropped, with the reason printed and written to <out>.excluded.json, because exact-output scoring can't judge them:
interactive problems, real-valued answers (an error tolerance), problems accepting any of several outputs, no samples.
Stdlib only."""
import argparse, html, json, os, re, sys, time, urllib.request

BASE = "https://atcoder.jp"
UA = {"User-Agent": "Mozilla/5.0 (spark-tuning contamination check; 1 request/s)"}


def fetch(raw, name, url):
    path = os.path.join(raw, name)
    if not os.path.exists(path):
        time.sleep(1)
        body = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60).read().decode("utf-8")
        open(path, "w").write(body)
    return open(path).read()


def contests(raw, after, before):
    out = {}
    for page in range(1, 6):
        s = fetch(raw, f"archive-{page}.html", f"{BASE}/contests/archive?lang=en&page={page}")
        rows = re.findall(r"<time class='fixtime fixtime-full'>([^<]*)</time>.*?href=\"/contests/([a-z0-9]+)\"", s, re.S)
        for t, c in rows:
            if re.fullmatch(r"(abc|arc)\d+", c) and after <= t[:10] < before:
                out[c] = t[:10]
        if rows and min(t[:10] for t, _ in rows) < after:
            break
    return dict(sorted(out.items(), key=lambda kv: kv[1]))


def text(fragment):
    """AtCoder statement HTML -> the plain text LiveCodeBench stores (TeX kept, $ dropped, lists as '- ')."""
    s = re.sub(r"<li>\s*", "- ", fragment)
    s = re.sub(r"</?(var|strong|em|code|span|b|i|u)[^>]*>", "", s)
    s = re.sub(r"<br\s*/?>", "\n", s)
    s = re.sub(r"</(p|li|pre|h3|div|section|ul|ol)>", "\n", s)
    s = re.sub(r"<[^>]+>", "", s)
    s = html.unescape(s)
    return re.sub(r"\n{3,}", "\n\n", "\n".join(ln.rstrip() for ln in s.splitlines())).strip()


def sections(page):
    i = page.find('<span class="lang-en">')
    if i < 0:
        return None, None
    en = page[i:]
    en = en[:en.find('<span class="lang-ja">')] if '<span class="lang-ja">' in en else en
    m = re.search(r"Score\s*:\s*<var>(\d+)</var>", en)
    secs = re.findall(r"<section>\s*<h3>(.*?)</h3>(.*?)</section>", en, re.S)
    return (int(m.group(1)) if m else None), [(text(h), body) for h, body in secs]


def sample_text(body):
    m = re.search(r"<pre[^>]*>(.*?)</pre>", body, re.S)
    return html.unescape(re.sub(r"<[^>]+>", "", m.group(1))).strip("\r\n") + "\n" if m else None


TOLERANCE = re.compile(r"(absolute or relative|relative or absolute) error|error (from the true value )?is at most|"
                       r"within an (absolute|relative) error|10\^\{-\d+\}\s*or less", re.I)
ANY_OUTPUT = re.compile(r"(if there are (multiple|several|many)[^.]*?(print|output|any))|((print|output) any (one )?(of them|such))|"
                        r"any of them (will be|is|are) (accepted|considered|judged)|(may|can) (print|output) any", re.I)


def difficulty(contest, letter, score):
    # LiveCodeBench labels AtCoder by score: <= 200 easy (ABC A/B), 250-400 medium, more hard. lcb80's own mix agrees
    # (ABC A/B easy, C medium, D medium or hard, E-G hard). Approximate for ARC, whose A problems are 300-500.
    if score is None:
        return None
    return "easy" if score <= 200 else "medium" if score <= 400 else "hard"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", required=True); ap.add_argument("--out", required=True)
    ap.add_argument("--after", default="2026-07-01"); ap.add_argument("--before", default="2026-10-26")
    a = ap.parse_args()
    os.makedirs(a.raw, exist_ok=True)
    cs = contests(a.raw, a.after, a.before)
    print(f"{len(cs)} contests {a.after} .. {a.before}: {' '.join(cs)}", file=sys.stderr)
    rows, excluded = [], []
    for c, date in cs.items():
        lst = fetch(a.raw, f"{c}-tasks.html", f"{BASE}/contests/{c}/tasks?lang=en")
        tasks = sorted(set(re.findall(rf"/contests/{c}/tasks/({c}_[a-z0-9]+)\"", lst)))
        for t in tasks:
            letter = t.split("_")[-1]
            score, secs = sections(fetch(a.raw, f"{t}.html", f"{BASE}/contests/{c}/tasks/{t}?lang=en"))
            tid = f"atc/{t}"
            if secs is None:
                excluded.append({"task_id": tid, "why": "no English statement"}); continue
            body = [(h, b) for h, b in secs if not re.match(r"Sample (Input|Output)", h)]
            ins = {int(m.group(1)): sample_text(b) for h, b in secs if (m := re.match(r"Sample Input (\d+)", h))}
            outs = {int(m.group(1)): sample_text(b) for h, b in secs if (m := re.match(r"Sample Output (\d+)", h))}
            # statement text: problem statement without its heading, then every other part under its heading (LCB layout)
            parts = [text(b) if h == "Problem Statement" else f"{h}\n\n{text(b)}" for h, b in body]
            parts += [f"Sample Input {k}\n\n{ins[k]}\nSample Output {k}\n\n{outs.get(k) or ''}" for k in sorted(ins)]
            q = "\n\n".join(parts)
            stmt = " ".join(text(b) for h, b in body)
            why = ("interactive" if any(h == "Interaction" for h, _ in body) or re.search(r"interactive problem", stmt, re.I)
                   else "error tolerance" if TOLERANCE.search(stmt)
                   else "any valid output" if ANY_OUTPUT.search(stmt)
                   else "no samples" if not ins or any(outs.get(k) is None for k in ins) else None)
            if why:
                excluded.append({"task_id": tid, "why": why}); print(f"  drop {tid}: {why}", file=sys.stderr); continue
            rows.append({"task_id": tid, "question": q, "difficulty": difficulty(c, letter, score), "platform": "atcoder",
                         "contest_date": date + "T00:00:00", "letter": letter, "score": score,
                         "tests": [{"input": ins[k], "output": outs[k]} for k in sorted(ins)]})
    with open(a.out, "w") as fh:
        for r in rows:
            fh.write(json.dumps(r) + "\n")
    json.dump(excluded, open(a.out.replace(".jsonl", "") + ".excluded.json", "w"), indent=1)
    by = {}
    for r in rows:
        by[r["difficulty"]] = by.get(r["difficulty"], 0) + 1
    print(f"{len(rows)} problems kept {by}, {len(excluded)} dropped -> {a.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
