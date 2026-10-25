#!/usr/bin/env python3
"""Offline check before every commit (AGENTS.md): no leaks in tracked/staged files, and every repo path a doc names exists.
Stdlib only. Exit 1 on any finding."""
import glob, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
problems = []
# Dataset content, not ours: MBPP+ task 593 strips leading zeroes from an IP address.
ALLOW = {"216.08.094.196", "216.8.94.196"}
LEAK = re.compile(r"\b(?!0\.0\.0\.0\b)(?!127\.0\.0\.1\b)(\d{1,3}\.){3}\d{1,3}\b|/home/|/Users/|hf_[A-Za-z0-9]{10,}|gh[pousr]_[A-Za-z0-9]{10,}")
files = subprocess.run(["git", "ls-files", "-co", "--exclude-standard"], capture_output=True, text=True).stdout.split()
for f in files:
    if not os.path.isfile(f) or f.endswith((".pkl", ".png")):
        continue
    for i, line in enumerate(open(f, errors="replace"), 1):
        if "grep -nE" in line or "LEAK = re.compile" in line:
            continue   # the scan patterns themselves
        for m in LEAK.finditer(line):
            s = m.group(0)
            if s in ALLOW:
                continue
            if re.fullmatch(r"(\d+\.){3}\d+", s) and all(int(p) < 10 for p in s.split(".")):
                continue   # version-like numbers (0.3.1.0) and the like
            problems.append(f"{f}:{i}: possible leak `{s}`")
TOP = {d for d in os.listdir(".") if os.path.isdir(d) and not d.startswith(".")}
for d in glob.glob("*.md"):
    text = open(d).read()
    for m in re.finditer(r"`([^`\s]+)", text):
        tok = m.group(1).rstrip(".,;:)")
        if "/" in tok and tok.split("/")[0] in TOP and not re.search(r"[*<>{}$\[|]", tok) and not os.path.exists(tok):
            problems.append(f"{d}: path `{tok}` does not exist")
if problems:
    print("\n".join(problems)); sys.exit(1)
print(f"check_repo: ok ({len(files)} files)")
