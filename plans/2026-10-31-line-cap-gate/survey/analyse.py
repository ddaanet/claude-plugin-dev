#!/usr/bin/env python3
"""Analyse the line-cap survey TSVs; print each report table as Markdown.

Usage: python3 -I analyse.py [section ...]
Sections: types repotype splitcap cohort cohort-full candidates sweep
          flips flips-cpd handoff flips-full pertype hub wrap longlines
          breakdown
Default: every section except cohort-full and flips-full (the long listings).

Reads <repo>/tmp/line-cap-survey/*.tsv, written by survey/measure.sh. Governed
set = scope gated + docs-md. plans and changelog never enter a count. The
"adjusted" set drops type lock and docs/superpowers/ (plans the survey filed
under docs-md). Standard library only.
"""
import csv
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.normpath(os.path.join(HERE, "..", "..", "..", "tmp",
                                     "line-cap-survey"))
CPD = "claude-plugin-dev"
CAP = 400
HUB_CAP = 200
GROUPS = [  # (group, member types), in report order
    ("md", ["md"]), ("sh", ["sh", "bash"]), ("bats", ["bats"]),
    ("py", ["py"]), ("just", ["just"]), ("js/ts", ["mjs", "ts", "tsx"]),
    ("json", ["json", "jsonl"]),
    ("config", ["toml", "yml", "cfg", "editorconfig", "python-version",
                "envrc", "gitignore", "gitmodules", "include", "template"]),
    ("txt", ["txt"]), ("lock", ["lock"]), ("other", ["none", "awk"]),
]
CODE = ["sh", "bats", "py", "just", "js/ts"]
MAJOR = ["md", "sh", "bats", "py", "just", "js/ts"]
GROUP_OF = {t: g for g, ts in GROUPS for t in ts}
HUB_RE = re.compile(r"(^|/)skills/[^/]+/SKILL\.md$")


def load():
    rows = []
    for path in sorted(glob.glob(os.path.join(DATA, "*.tsv"))):
        with open(path, newline="", encoding="utf-8") as fh:
            for r in csv.DictReader(fh, delimiter="\t", quoting=csv.QUOTE_NONE):
                for k in ("lines", "bytes", "nonws", "words", "maxlen"):
                    r[k] = int(r[k])
                r["group"] = GROUP_OF.get(r["type"], "other")
                r["ratio"] = r["nonws"] / r["lines"]
                rows.append(r)
    return rows


def pct(xs, p):
    """Percentile p (0-100) with linear interpolation; None when empty."""
    if not xs:
        return None
    s = sorted(xs)
    k = (len(s) - 1) * p / 100
    lo = int(k)
    hi = min(lo + 1, len(s) - 1)
    return s[lo] + (s[hi] - s[lo]) * (k - lo)


def near(x, step=500):
    return int(round(x / step)) * step


def up(x, step=500):
    return int(-(-x // step)) * step


def fmt(x, nd=1):
    return "-" if x is None else f"{x:.{nd}f}"


def table(head, body, align=None):
    """Markdown table; align is a string of l/r/c per column."""
    align = align or "l" + "r" * (len(head) - 1)
    w = [max(len(str(r[i])) for r in [head] + body) for i in range(len(head))]
    def cell(i, c):
        return (str(c).ljust(w[i]) if align[i] == "l"
                else str(c).center(w[i]) if align[i] == "c"
                else str(c).rjust(w[i]))
    def line(r):
        return "| " + " | ".join(cell(i, c) for i, c in enumerate(r)) + " |"
    sep = "|" + "|".join(
        (":" + "-" * (w[i] + 1)) if align[i] == "l" else ("-" * (w[i] + 1) + ":")
        for i in range(len(head))) + "|"
    return "\n".join([line(head), sep] + [line(r) for r in body])


def short(r, width=40):
    s = f"{r['repo']}:{r['path']}"
    return s if len(s) <= width else "~" + s[-(width - 1):]


def governed(rows):
    return [r for r in rows if r["scope"] in ("gated", "docs-md")]


def adjusted(g):
    return [r for r in g if r["group"] != "lock"
            and not r["path"].startswith("docs/superpowers/")]


def big(rs):
    return [r for r in rs if r["lines"] >= 100]


def repos_of(rs):
    return sorted({r["repo"] for r in rs}, key=lambda x: (x != CPD, x))


def stats_row(label, rs):
    rat = [r["ratio"] for r in rs]
    ln = sum(r["lines"] for r in rs)
    agg = sum(r["nonws"] for r in rs) / ln if ln else None
    return [label, len(rs), ln, fmt(agg)] + [fmt(pct(rat, p)) for p in
                                             (50, 10, 25, 75, 90)]


def sec_types(rows):
    g = governed(rows)
    head = ["group", "files", "lines", "agg", "p50", "p10", "p25", "p75", "p90"]
    out = []
    for title, sel in (("all governed files", g),
                       ("governed files with >=100 lines", big(g))):
        body = [stats_row(name, [r for r in sel if r["group"] == name])
                for name, _ in GROUPS
                if any(r["group"] == name for r in sel)]
        body.append(stats_row("code*", [r for r in sel if r["group"] in CODE]))
        body.append(stats_row("ALL", sel))
        out.append(f"{title} (nonws/line; agg = total nonws / total lines)\n\n"
                   + table(head, body))
    return "\n\n".join(out)


def sec_repotype(rows):
    g = big(governed(rows))
    cols = MAJOR + ["ALL"]
    body = []
    omitted = []
    for repo in repos_of(g):
        if sum(1 for r in g if r["repo"] == repo) < 3:
            omitted.append(repo)
            continue
        cells = []
        for c in cols:
            rs = [r for r in g if r["repo"] == repo
                  and (c == "ALL" or r["group"] == c)]
            cells.append(f"{len(rs)}:{pct([r['ratio'] for r in rs], 50):.0f}"
                         if rs else "-")
        body.append([repo] + cells)
    return ("cells are n:median nonws/line, governed files with >=100 lines; "
            "omitted, fewer than 3 such files: " + ", ".join(omitted)
            + "\n\n" + table(["repo"] + cols, body))


def sec_splitcap(rows):
    """Does a repo pile up just under 400 lines and thin out above it?"""
    g = governed(rows)
    bands = [(340, 359), (360, 379), (380, 400), (401, 420), (421, 440),
             (441, 460)]
    body = []
    for repo in repos_of(g):
        rs = [r for r in g if r["repo"] == repo]
        cells = [sum(1 for r in rs if lo <= r["lines"] <= hi)
                 for lo, hi in bands]
        over = [r for r in rs if r["lines"] > CAP]
        if sum(cells) + len(over) < 3:
            continue
        sp = sum(1 for r in over if r["group"] == "lock"
                 or r["path"].startswith("docs/superpowers/"))
        body.append([repo, len(rs)] + cells + [len(over), sp])
    head = ["repo", "files"] + [str(lo) for lo, _ in bands] \
        + [">400", "l/sp"]
    small = [x for x in repos_of(g) if x not in {b[0] for b in body}]
    return ("governed files per 20-line band starting at the header value "
            "(380 = 380-400), all types; l/sp = of the >400 files, those "
            "that are a lock file or under docs/superpowers/; omitted, "
            "fewer than 3 files in or above the bands: " + ", ".join(small) + "\n\n"
            + table(head, body))


def cohort(rows):
    return [r for r in governed(rows) if 300 <= r["lines"] <= CAP]


def sec_cohort(rows):
    co = cohort(rows)
    summ = []
    small = []
    def srow(label, rs):
        nz = [r["nonws"] for r in rs]
        return [label, len(rs), fmt(pct([r["lines"] for r in rs], 50), 0),
                fmt(pct(nz, 50), 0), max(nz),
                fmt(pct([r["ratio"] for r in rs], 50))]
    for repo in repos_of(governed(rows)):
        rs = [r for r in co if r["repo"] == repo]
        if len(rs) >= 10:
            summ.append(srow(repo, rs))
        elif rs:
            small += rs
    nl = [r for r in co if r["group"] != "lock"]
    nsm = len({r["repo"] for r in small})
    summ.append(srow(f"{nsm} repos with n<10 each", small))
    summ.append(srow("ALL (no lock)", nl))
    out = ["per-repo summary of governed files with 300-400 lines\n\n"
           + table(["repo", "n", "med L", "med nonws", "max nonws", "n/l"],
                   summ)]
    cp = [r for r in co if r["repo"] == CPD]
    bt = []
    for lab, sel in (("14 repos, no lock", nl), (CPD, cp)):
        for n in ("md", "sh", "bats", "py"):
            xs = [r["nonws"] for r in sel if r["group"] == n]
            if xs:
                bt.append([lab, n, len(xs)] + [f"{pct(xs, p):.0f}"
                                               for p in (10, 50, 90, 100)])
    out.append("cohort nonws by type\n\n" + table(
        ["set", "type", "n", "p10", "p50", "p90", "max"], bt, "llrrrrr"))
    out.append(cohort_listing(co, [CPD]))
    return "\n\n".join(out)


def cohort_listing(co, repos, extremes=False, title=True):
    body = []
    for repo in repos:
        rs = sorted([r for r in co if r["repo"] == repo],
                    key=lambda r: -r["nonws"])
        if extremes and len(rs) > 4:
            rs = rs[:3] + rs[-1:]
        for r in rs:
            p = r["path"] if extremes is False else f"{repo}:{r['path']}"
            if len(p) > 44:
                p = "~" + p[-43:]
            body.append([p, r["group"], r["lines"], r["nonws"],
                         f"{r['ratio']:.1f}"])
    if not title:
        return table(["path", "type", "lines", "nonws", "n/l"], body, "llrrr")
    cells = [f"{abbrev(b[0]):<24} {b[2]:>3} {b[3]:>5} {b[4]:>4}"
             for b in body]
    half = (len(cells) + 1) // 2
    rows2 = [cells[k] + "  " + (cells[k + half] if k + half < len(cells)
                                 else "") for k in range(half)]
    txt = "\n".join(r.rstrip() for r in rows2)
    return (f"{CPD} cohort, {len(body)} files, largest nonws first down the "
            "left column then the right; name, lines, nonws, nonws/line; "
            "t/ = tests/ with -test.sh dropped, d/ = docs/, ref/ = "
            "references/, k/ = toolkit/\n\n```text\n" + txt + "\n```")


def abbrev(path):
    """Shorten a path for the two-column cohort listing."""
    if path.startswith("tests/") and path.endswith("-test.sh"):
        return "t/" + path[6:-8]
    for long, short_ in (("docs/", "d/"), ("toolkit/", "k/")):
        if path.startswith(long):
            path = short_ + path[len(long):]
    return path.replace("references/", "ref/")


def sec_cohort_full(rows):
    co = cohort(rows)
    return "\n\n".join(
        f"{repo} ({sum(1 for r in co if r['repo'] == repo)})\n\n"
        + cohort_listing(co, [repo], title=False)
        for repo in repos_of(co))


def candidates(rows):
    """Return (list of candidate dicts, governed rows)."""
    g = governed(rows)
    b = big(g)
    med = lambda sel: pct([r["ratio"] for r in sel], 50)
    cpd_ok = [r for r in g if r["repo"] == CPD and r["lines"] <= CAP]
    all_ok = [r for r in g if r["lines"] <= CAP]
    nolock = [r for r in all_ok if r["group"] != "lock"]
    cands = []
    def add(key, name, f, cap):
        cands.append({"key": key, "name": name, "f": f, "cap": cap})
    for key, name, f in (
            ("A", "pooled med", med(b)),
            ("B", "md med", med([r for r in b if r["group"] == "md"])),
            ("C", "sh med", med([r for r in b if r["group"] == "sh"])),
            ("D", "bats med", med([r for r in b if r["group"] == "bats"])),
            ("E", "py med", med([r for r in b if r["group"] == "py"])),
            ("F", "pooled p75", pct([r["ratio"] for r in b], 75))):
        add(key, name, f, near(f * CAP))
    for key, name, sel in (("G", "noreg cpd", cpd_ok),
                           ("H", "noreg 14", all_ok),
                           ("I", "noreg 14-lk", nolock)):
        mx = max(sel, key=lambda r: r["nonws"])
        add(key, name, mx["nonws"] / CAP, up(mx["nonws"]))
        cands[-1]["maxrow"] = mx
    return cands, g


def flips_for(cand, g):
    fin = [r for r in g if r["lines"] <= CAP and r["nonws"] > cand["cap"]]
    fout = [r for r in g if r["lines"] > CAP and r["nonws"] <= cand["cap"]]
    fin.sort(key=lambda r: -(r["nonws"] - cand["cap"]))
    fout.sort(key=lambda r: -(cand["cap"] - r["nonws"]))
    return fin, fout


def count_row(c, sel):
    """over-cap, compliant->fail, fail->pass counts over sel."""
    fin, fout = flips_for(c, sel)
    return sum(1 for r in sel if r["nonws"] > c["cap"]), len(fin), len(fout)


def sec_candidates(rows):
    cands, g = candidates(rows)
    cp = [r for r in g if r["repo"] == CPD]
    body = []
    for c in cands:
        o14, i14, f14 = count_row(c, g)
        oc, ic, fc = count_row(c, cp)
        body.append([c["key"], c["name"], f"{c['f']:.1f}", c["cap"],
                     o14, oc, i14, ic, f14, fc])  # idx 4..9
    a = adjusted(g)
    for c, row in zip(cands, body):
        _, ai, ao = count_row(c, a)
        row += [ai, ao]
    t = table(["", "candidate", "f", "cap", "over", "in", "out", "cpdIn",
               "adjIn", "adjOut"],
              [[b[0], b[1], b[2], b[3], b[4], b[6], b[8], b[7], b[10], b[11]]
               for b in body], "llrrrrrrrr")
    today = sum(1 for r in g if r["lines"] > CAP)
    extra = ["no-regression maxima (cap = max rounded up to 500):"]
    for c in cands:
        if "maxrow" in c:
            r = c["maxrow"]
            extra.append(f"- {c['key']}: {short(r, 58)} ({r['group']}, "
                         f"{r['lines']} L, {r['nonws']} nonws)")
    adj_today = sum(1 for r in a if r["lines"] > CAP)
    return (f"{len(g)} governed files over 14 repos, {len(cp)} in {CPD}. "
            f"Over 400 lines today: {today} (14 repos), 0 (cpd). cap = f x "
            "400 rounded to 500 (G, H, I round up). over = files above the "
            "cap, 14 repos; in = compliant today, fails under the cap; out = "
            "fails today, passes under it; cpd in = in, cpd only (cpd out is "
            f"0 throughout). adj = governed minus lock files and "
            f"docs/superpowers/ ({len(a)} files, {adj_today} over 400 lines "
            "today)\n\n" + t + "\n\n" + "\n".join(extra))


def sweep_min(sel):
    """Cap minimising in+out over sel: (min flips, lowest cap, highest cap)."""
    pts = sorted({r["nonws"] for r in sel} | {0})
    best = None
    for cap in pts:
        n = sum(1 for r in sel if (r["lines"] <= CAP and r["nonws"] > cap)
                or (r["lines"] > CAP and r["nonws"] <= cap))
        if best is None or n < best[0]:
            best = [n, cap, cap]
        elif n == best[0]:
            best[2] = cap
    nxt = [p for p in pts if p > best[2]]
    return best[0], best[1], (nxt[0] - 1 if nxt else best[2])


def sec_sweep(rows):
    cands, g = candidates(rows)
    a = adjusted(g)
    cp = [r for r in g if r["repo"] == CPD]
    body = []
    for cap in (14000, 16000, 18000, 20000, 22000):
        c = {"cap": cap}
        r = [cap, f"{cap / CAP:.0f}"]
        for sel in (g, a, cp):
            _, i, f = count_row(c, sel)
            r.append(f"{i}/{f}")
        body.append(r)
    t = table(["cap", "f", "14: in/out", "adj: in/out", "cpd: in/out"], body)
    mins = []
    for lab, sel in (("14 repos", g), ("adjusted", a)):
        n, lo, hi = sweep_min(sel)
        mins.append(f"- {lab}: fewest flips {n} (in+out), for caps "
                    f"{lo}..{hi} (f {lo / CAP:.1f}..{hi / CAP:.1f})")
    return (t + "\n\nexact minimiser of in+out:\n" + "\n".join(mins))


def marks(r, cands, per, limit):
    out = ""
    for c, lst in zip(cands, per):
        top = any(x is r for x in lst[:limit])
        hit = top or any(x is r for x in lst)
        out += "X" if top else "x" if hit else "."
    return out


def flip_table(per, cands, keys, seen, idx):
    body = []
    for k in keys:
        r = seen[k]
        body.append([short(r, 36), r["group"], r["lines"], r["nonws"],
                     marks(r, cands, per, 15)])
    return table(["file", "type", "lines", "nonws",
                  "".join(c["key"] for c in cands)], body, "llrrl")


def sec_flips(rows, limit=15):
    cands, g = candidates(rows)
    out = []
    for idx, label in ((0, "in: compliant today, fails under the cap"),
                       (1, "out: fails today, passes under the cap")):
        per = [flips_for(c, g)[idx] for c in cands]
        seen = {}
        for lst in per:
            for r in lst[:limit]:
                seen[(r["repo"], r["path"])] = r
        keys = sorted(seen, key=lambda k: -seen[k]["nonws"] if idx == 0
                      else -seen[k]["lines"])
        out.append(f"{label}\n\n" + flip_table(per, cands, keys, seen, idx))
    return "\n\n".join(out)


def sec_flips_cpd(rows):
    cands, g = candidates(rows)
    cp = [r for r in g if r["repo"] == CPD]
    per = [flips_for(c, cp)[0] for c in cands]
    seen = {}
    for c, lst in zip(cands, per):
        if c["key"] in "ABCF":
            for r in lst:
                seen[(r["repo"], r["path"])] = r
    keys = sorted(seen, key=lambda k: -seen[k]["nonws"])
    body = []
    for k in keys:
        r = seen[k]
        m = "".join("x" if any(x is r for x in lst) else "." for lst in per)
        body.append([r["path"], r["group"], r["lines"], r["nonws"], m])
    cnt = ", ".join(f"{c['key']} {len(l)}" for c, l in zip(cands, per))
    return (f"{CPD}: files compliant today that a candidate fails, counts "
            f"{cnt}. Rows are the files failing under A, B, C or F; marks "
            "cover all candidates, so D and E fail more files than shown\n\n"
            + table(["file", "type", "lines", "nonws",
                     "".join(c["key"] for c in cands)], body, "llrrl"))


def sec_handoff(rows):
    cands, g = candidates(rows)
    pick = [r for r in g if r["repo"] == "handoff" and
            (r["lines"] > CAP or r["path"] in ("scripts/_lib.sh",
                                               "scripts/_lib_drive.sh")
             or r["path"] == "docs/changelog.md"
             or r["path"].endswith("hook-test.bats"))]
    pick.sort(key=lambda r: -r["nonws"])
    body = []
    for r in pick:
        m = "".join("F" if r["nonws"] > c["cap"] else "p" for c in cands)
        body.append([r["path"], r["group"], r["lines"], r["nonws"],
                     f"{r['ratio']:.1f}", m])
    absent = [p for p in ("tests/hook-test.bats",)
              if not any(r["path"] == p for r in rows if r["repo"] == "handoff")]
    return ("handoff files over 400 lines, docs/changelog.md and the scripts/_lib*.sh set. "
            "Marks per candidate: p = passes the nonws cap, F = fails it; "
            "letters as in the candidate table "
            + "".join(c["key"] for c in cands) + "\n\n"
            + table(["file", "type", "lines", "nonws", "n/l", "marks"], body,
                    "llrrrl") + "\n\nnot in the survey: " + ", ".join(absent))


def sec_flips_full(rows):
    cands, g = candidates(rows)
    out = []
    for c in cands:
        fin, fout = flips_for(c, g)
        for lab, lst in (("compliant->fail", fin), ("fail->pass", fout)):
            out.append(f"{c['key']} {c['name']} cap {c['cap']} {lab} "
                       f"({len(lst)})")
            for r in lst:
                out.append(f"  {short(r, 60)} {r['group']} {r['lines']} "
                           f"{r['nonws']}")
    return "\n".join(out)


def sec_pertype(rows):
    cands, g = candidates(rows)
    b = big(g)
    cap = {c["key"]: c["cap"] for c in cands}
    body = []
    for name in MAJOR:
        sel = [r for r in b if r["group"] == name]
        allg = [r for r in g if r["group"] == name]
        m = pct([r["ratio"] for r in sel], 50)
        own = near(m * CAP)
        def cnt(cp):
            fi = sum(1 for r in allg if r["lines"] <= CAP and r["nonws"] > cp)
            fo = sum(1 for r in allg if r["lines"] > CAP and r["nonws"] <= cp)
            return f"{fi}/{fo}"
        body.append([name, len(allg), len(sel), fmt(m), own,
                     f"{cap['A'] / m:.0f}", cnt(cap["A"]), cnt(own),
                     f"{cap['F'] / m:.0f}"])
    return (f"A = pooled-median cap ({cap['A']}), F = pooled-p75 cap "
            f"({cap['F']}); own = round(400 x type median, 500); eq L = cap / "
            "type median, the line count at which a median-density file of "
            "the type reaches the cap; flips are in/out over all governed "
            "files of the type\n\n"
            + table(["type", "files", "n100", "med", "own", "eqA", "flipA",
                     "flipOwn", "eqF"], body))


def sec_hub(rows):
    cands, _ = candidates(rows)
    hubs = sorted([r for r in governed(rows) if HUB_RE.search(r["path"])],
                  key=lambda r: (r["repo"], r["path"]))
    by = {}
    for r in hubs:
        by.setdefault(r["repo"], []).append(r)
    def line(label, rs):
        return [label, len(rs), fmt(pct([r["lines"] for r in rs], 50), 0),
                max(r["lines"] for r in rs),
                fmt(pct([r["nonws"] for r in rs], 50), 0),
                max(r["nonws"] for r in rs),
                fmt(pct([r["ratio"] for r in rs], 50)),
                max(r["maxlen"] for r in rs)]
    body = [line(k, v) for k, v in by.items()] + [line("ALL", hubs)]
    t1 = table(["repo", "n", "medL", "maxL", "medNW", "maxNW", "n/l",
                "maxlen"], body)
    caps = [near(c["f"] * HUB_CAP, 100) for c in cands]
    t3 = table([""] + [c["key"] for c in cands],
               [["200 x f"] + caps,
                ["hubs over"] + [sum(1 for r in hubs if r["nonws"] > cp)
                                 for cp in caps]], "l" + "r" * 9)
    return "\n\n".join([t1, t3])


def wrap_row(label, sel):
    b = big(sel)
    tb = sum(r["bytes"] for r in sel)
    tl = sum(r["lines"] for r in sel)
    tn = sum(r["nonws"] for r in sel)
    tw = sum(r["words"] for r in sel)
    return [label, len(b),
            fmt(pct([r["maxlen"] for r in b], 50), 0),
            fmt(pct([r["maxlen"] for r in b], 90), 0),
            fmt(tb / tl, 0), fmt(pct([r["ratio"] for r in b], 50)),
            f"{tn / tb:.3f}", f"{tn / tw:.2f}"]


def sec_wrap(rows):
    g = [r for r in governed(rows) if r["group"] == "md"]
    head = ["", ">=100", "medmax", "p90max", "B/line", "n/l", "n/B", "n/w"]
    body = [wrap_row(repo, [r for r in g if r["repo"] == repo])
            for repo in repos_of(g)
            if sum(1 for r in g if r["repo"] == repo and r["lines"] >= 100) >= 9]
    wrapped = {r["repo"] for r in rows if r["path"] == ".rumdl.toml"}
    body.append(wrap_row("with .rumdl.toml", [r for r in g if r["repo"] in wrapped]))
    body.append(wrap_row("without", [r for r in g
                                         if r["repo"] not in wrapped]))
    t1 = table(head, body)
    classes = [("maxlen <= 100", lambda r: r["maxlen"] <= 100),
               ("101-200", lambda r: 100 < r["maxlen"] <= 200),
               ("201-500", lambda r: 200 < r["maxlen"] <= 500),
               ("> 500", lambda r: r["maxlen"] > 500)]
    body2 = []
    for lab, test in classes:
        sel = [r for r in g if test(r) and r["lines"] >= 100]
        ratios = [r["ratio"] for r in sel]
        body2.append([lab, len(sel), fmt(pct(ratios, 50)),
                      fmt(pct(ratios, 25)), fmt(pct(ratios, 75)),
                      f"{sum(r['nonws'] for r in sel) / sum(r['bytes'] for r in sel):.3f}",
                      f"{sum(r['nonws'] for r in sel) / sum(r['words'] for r in sel):.2f}",
                      fmt(20000 / pct(ratios, 50), 0)])
    t2 = table(["file maxlen", "n", "n/l", "p25", "p75", "n/B", "n/w",
                "L@20k"], body2)
    return "\n\n".join([t1, t2])


def sec_longlines(rows):
    longs = sorted([r for r in governed(rows) if r["lines"] >= 50
                    and r["ratio"] > 100 and r["group"] != "lock"],
                   key=lambda r: -r["ratio"])
    return ("governed files with >=50 lines and nonws/line > 100, lock files "
            "excluded\n\n"
            + table(["file", "type", "lines", "nonws", "n/l", "maxlen"],
                    [[short(r, 34), r["group"], r["lines"], r["nonws"],
                      f"{r['ratio']:.0f}", r["maxlen"]] for r in longs],
                    "llrrrr"))


def sec_breakdown(rows):
    """The counts the report's prose quotes beside its tables."""
    import collections
    cands, g = candidates(rows)
    a = cands[0]
    fin, _ = flips_for(a, g)
    out = [f"A in-flips ({len(fin)}) by type: "
           + ", ".join(f"{k} {v}" for k, v in
                       collections.Counter(r["group"] for r in fin).most_common())
           + "\nA in-flips by repo: "
           + ", ".join(f"{k} {v}" for k, v in
                       collections.Counter(r["repo"] for r in fin).most_common(4))]
    hb = [r for r in g if r["repo"] == "handoff" and r["group"] == "bats"]
    over = {c["key"]: sum(1 for r in hb if r["nonws"] > c["cap"]) for c in cands}
    out.append(f"handoff bats: {len(hb)} files, "
               f"{min(r['lines'] for r in hb)}-{max(r['lines'] for r in hb)} "
               f"lines, {min(r['nonws'] for r in hb)}-"
               f"{max(r['nonws'] for r in hb)} nonws; over each cap: "
               + ", ".join(f"{k} {v}" for k, v in over.items()))
    other = collections.Counter(os.path.basename(r["path"]) for r in g
                                if r["type"] == "none")
    out.append("type none (in group other): "
               + ", ".join(f"{k} {v}" for k, v in other.most_common()))
    return "\n".join(out)


SECTIONS = {
    "types": sec_types, "repotype": sec_repotype, "splitcap": sec_splitcap,
    "cohort": sec_cohort, "cohort-full": sec_cohort_full,
    "candidates": sec_candidates,
    "sweep": sec_sweep, "flips": sec_flips, "flips-cpd": sec_flips_cpd,
    "handoff": sec_handoff, "flips-full": sec_flips_full,
    "pertype": sec_pertype, "hub": sec_hub, "wrap": sec_wrap,
    "longlines": sec_longlines, "breakdown": sec_breakdown,
}
LONG = ("cohort-full", "flips-full")


def main(argv):
    names = argv or [s for s in SECTIONS if s not in LONG]
    rows = load()
    for n in names:
        print(f"## {n}\n")
        print(SECTIONS[n](rows))
        print()


if __name__ == "__main__":
    main(sys.argv[1:])
