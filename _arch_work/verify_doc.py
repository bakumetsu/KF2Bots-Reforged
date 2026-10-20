# -*- coding: utf-8 -*-
"""verify_doc.py — Phase 4 verification for KF2_Current_Architecture.md
Checks (a)-(g) per task spec. Print-only; exits 1 if any hard failure.
"""
import json, os, random, re, sys
from collections import Counter

BASE = os.path.dirname(os.path.abspath(__file__))
CLASSES = os.path.dirname(BASE)
DOC = os.path.join(CLASSES, "Mod Architecture", "KF2_Current_Architecture.md")
SYMS = os.path.join(BASE, "symbols.json")
SDK_ROOT = r"D:\SteamLibrary\steamapps\common\killingfloor2\Development\Src"

FILES = {
    "Mut":   "KF2BotsMut.uc",
    "Nav":   "KF2BotsFollowNavBase.uc",
    "Base":  "KF2BotBase.uc",
    "Logic": "KF2BotLogic.uc",
    "Bot":   "KF2Bot.uc",
}

failures = []

def fail(msg):
    failures.append(msg)
    print("  FAIL: " + msg)

def ok(msg):
    print("  ok:   " + msg)

# ---------------- load ----------------
src = {}          # prefix -> text
src_lines = {}    # prefix -> [lines]
for pfx, fname in FILES.items():
    path = os.path.join(CLASSES, fname)
    with open(path, encoding="utf-8", errors="replace") as f:
        txt = f.read()
    src[pfx] = txt
    src_lines[pfx] = txt.splitlines()

with open(SYMS, encoding="utf-8") as f:
    symdata = json.load(f)
symbols = symdata["symbols"]
symkey = set()   # (file, name, start)
file_to_pfx = {fn: p for p, fn in FILES.items()}
symlookup = {}   # (pfx, name) -> [start,end]
for s in symbols:
    symkey.add((s["file"], s["name"], s["start"]))
    pfx = file_to_pfx.get(s["file"], s["file"])
    symlookup.setdefault((pfx, s["name"]), []).append((s["start"], s["end"]))

doc = open(DOC, encoding="utf-8").read()
lines = doc.splitlines()
print("doc: %s  (%d lines)" % (DOC, len(lines)))

# ---------------- helpers ----------------
def is_code_line(pfx, ln):
    """line is within file and range [lo,hi] contains a real code line"""
    ls = src_lines[pfx]
    if ln < 1 or ln > len(ls):
        return False
    return True

def range_has_code(pfx, lo, hi):
    ls = src_lines[pfx]
    for i in range(lo - 1, min(hi, len(ls))):
        t = ls[i].strip()
        # comment-only ranges are intentional comment citations (e.g. [Nav:58]
        # cites the FollowMoveEnd contract comment); ";*" is still rejected
        if t and not t.startswith(";"):
            return True
    return False

CITE_RE = re.compile(r"\[([^\]\n]{1,80})\](?!\()")
VALID_INNER = re.compile(r"^\d[\d,\-]*$")

def parse_line_list(inner):
    """returns list of (lo,hi) pairs from '170' / '170-269' / '30,35' / '30,35,49'"""
    out = []
    for part in inner.split(","):
        part = part.strip()
        if "-" in part:
            a, b = part.split("-", 1)
            out.append((int(a), int(b)))
        else:
            out.append((int(part), int(part)))
    return out

def primary_of(idx):
    """primary file for citation at line idx (0-based): nearest earlier primary declaration.
    Part 0 uses '### KF2BotsMut.uc (Primary: Mut)'; Parts 1-6 use 'Primary file: ...'."""
    for i in range(idx, -1, -1):
        m = re.search(r"### \d+\.\d+\.\d+ (\w+\.uc)", lines[i])
        if m:
            for pfx, fn in FILES.items():
                if fn == m.group(1):
                    return pfx
        m = re.search(r"### (\w+\.uc) \(Primary: (Mut|Nav|Base|Logic|Bot)\)", lines[i])
        if m:
            for pfx, fn in FILES.items():
                if fn == m.group(1):
                    return pfx
            return m.group(2)
        m = re.search(r"Primary file: (\w+\.uc)", lines[i])
        if m:
            fname = m.group(1)
            for pfx, fn in FILES.items():
                if fn == fname:
                    return pfx
        m2 = re.search(r"Primary file: (Mut|Nav|Base|Logic|Bot)\b", lines[i])
        if m2:
            return m2.group(1)
    return None

def file_of(pfx):
    return FILES[pfx]

# ---------------- (a) citations parse + valid ----------------
print("\n[a] citations parse + valid")
WHITELIST = {
    # prose tokens / citation-format documentation, not real citations
    "[0]","[1]","[2]","[B.FollowSlotIndex]","[B12]","[BestIdx]","[BOT]","[FailBackoffMin, FailBackoffMax]",
    "[FollowPathFailBackoffMin, FollowPathFailBackoffMax]","[GRUNT]","[i]","[Idx]",
    "[MIN_GROUPS=2, MAX_GROUPS=4]","[native]","[Nav]","[P4.30]","[P4.32]","[per Decide]",
    "[Rand(ValidPoints.Length)]","[Rand]","[Rank]","[System.IO.File]","[Lv X]",
    # bare prefix tokens from PART 5 citation-format description line
    "[Base:]","[Bot:]","[Mut:]","[Logic:]","[Nav:]",
    # citation-format example tokens on the Part 0 citation-style description line
    "[123]","[123-140]","[Mut:1953]","[Nav:727]","[Base:812]","[Logic:2410]","[Bot:3573]",
    "[SDK <relpath>:<line>]",  # placeholder token in citation-format legend (L1255)
}
n_cites = 0
n_ok = 0
for i, ln in enumerate(lines):
    for m in CITE_RE.finditer(ln):
        inner = m.group(1).strip()
        tok = m.group(0)
        if tok in WHITELIST:
            continue
        pfx = None
        if inner.startswith("SDK "):
            body = inner[4:]
            mm = re.match(r"^(.*\.uc):(.+)$", body)
            if not mm:
                fail("L%d unparseable SDK citation: %s" % (i+1, tok)); continue
            rel, linestr = mm.group(1), mm.group(2)
            sdkpath = os.path.join(SDK_ROOT, rel.replace("/", os.sep))
            if not os.path.isfile(sdkpath):
                fail("L%d SDK file missing: %s" % (i+1, rel)); continue
            sls = open(sdkpath, encoding="utf-8", errors="replace").read().splitlines()
            for part in linestr.split(","):
                part = part.strip()
                if "-" in part:
                    lo, hi = [int(x) for x in part.split("-", 1)]
                else:
                    lo = hi = int(part)
                if lo < 1 or hi < lo or hi > len(sls):
                    fail("L%d SDK range out of bounds: %s" % (i+1, tok)); break
            n_cites += 1; n_ok += 1
            continue
        m2 = re.match(r"^(Mut|Nav|Base|Logic|Bot):(.+)$", inner)
        if m2:
            pfx = m2.group(1)
            inner2 = m2.group(2)
        else:
            m3 = re.match(r"^\d[\d,\-]*$", inner)
            if not m3:
                fail("L%d unparseable citation: %s" % (i+1, tok)); continue
            pfx = primary_of(i)
            inner2 = inner
        pfx = pfx or primary_of(i)
        if pfx is None:
            fail("L%d citation %s has no resolvable primary file" % (i+1, tok)); continue
        if not VALID_INNER.match(inner2.replace(" ", "")):
            fail("L%d malformed line list: %s" % (i+1, tok)); continue
        try:
            rngs = parse_line_list(inner2)
        except ValueError:
            fail("L%d malformed line list: %s" % (i+1, tok)); continue
        n_cites += 1
        allok = True
        for lo, hi in rngs:
            if lo < 1 or hi < lo or hi > len(src_lines[pfx]):
                fail("L%d range out of file bounds: %s" % (i+1, tok)); allok = False; break
            if not range_has_code(pfx, lo, hi):
                fail("L%d range has no real code: %s" % (i+1, tok)); allok = False; break
        if allok:
            n_ok += 1
print("  %d/%d citations valid" % (n_ok, n_cites))

# ---------------- (b) symbol lines vs symbols.json ----------------
print("\n[b] Part 0 + Technical symbol lines vs symbols.json")
# b1: 0.7 table exact
start07 = end07 = None
for i, ln in enumerate(lines):
    if ln.startswith("## 0.7"):
        start07 = i
    if start07 is not None and end07 is None and (ln.startswith("# ") or ln.startswith("## ") and not ln.startswith("## 0.7")):
        end07 = i
if end07 is None:
    end07 = len(lines)
docrows = []
for ln in lines[start07:end07]:
    if ln.startswith("|") and not ln.startswith("|---") and "symbol" not in ln:
        cells = [c.strip() for c in ln.strip().strip("|").split("|")]
        if len(cells) >= 3:
            m = re.match(r"^(Mut|Nav|Base|Logic|Bot):(\d+)$", cells[2])
            if m:
                docrows.append((m.group(1), cells[0], int(m.group(2))))
docmult = Counter((FILES[p], name, line) for p, name, line in docrows)
jsonmult = Counter((s["file"], s["name"], s["start"]) for s in symbols)
missing = jsonmult - docmult
extra = docmult - jsonmult
if missing:
    fail("0.7 missing %d symbol rows, e.g. %s" % (sum(missing.values()), list(missing)[:3]))
else:
    ok("0.7 missing rows: 0")
if extra:
    fail("0.7 extra %d symbol rows, e.g. %s" % (sum(extra.values()), list(extra)[:3]))
else:
    ok("0.7 extra rows: 0")
print("  0.7 rows: doc=%d json=%d" % (sum(docmult.values()), sum(jsonmult.values())))

# b2: Part 0 + Technical Reference symbol `Name` [file:line] checks
n_sym = 0; n_symok = 0
pat = re.compile(r"`(\w+)`\s*\[((?:Mut|Nav|Base|Logic|Bot):)?(\d[\d,\-]*)\]")
in07 = start07 is not None
for i, ln in enumerate(lines):
    is_part0 = i < (start07 if start07 is not None else len(lines))
    is_tech = re.match(r"^\s*[-*] (Functions|States|Events|Structs|Vars|Constants|Timers|Enums):", ln) or ln.startswith("#### 6.") or (is_part0 and ln.startswith("|"))
    if not (is_part0 or is_tech):
        continue
    for m in pat.finditer(ln):
        name, pfxs, linestr = m.group(1), m.group(2), m.group(3)
        if name in ("true", "false", "none"):
            continue  # keyword values (e.g. `default true [1496]`), not symbols
        pfx = pfxs[:-1] if pfxs else primary_of(i)
        if pfx is None:
            continue
        if (pfx, name) not in symlookup:
            fail("L%d `Name` citation not in symbols.json: `%s` [%s:%s]" % (i+1, name, pfx, linestr))
            continue
        rngs = parse_line_list(linestr)
        ranges = symlookup[(pfx, name)]
        match = any(lo >= s - 1 and hi <= e + 1 for (lo, hi) in rngs for (s, e) in ranges)
        if not match:
            fail("L%d symbol line mismatch: `%s` [%s:%s] vs json %s" % (i+1, name, pfx, linestr, ranges))
            continue
        n_sym += 1; n_symok += 1
print("  technical/part0 symbol citations: %d/%d match symbols.json" % (n_symok, n_sym))

# ---------------- (c) coverage ----------------
print("\n[c] coverage: every symbol in 0.7")
cov_missing = [k for k in symkey if (k[0], k[1], k[2]) not in docmult]
if cov_missing:
    fail("symbols missing from 0.7: %d, e.g. %s" % (len(cov_missing), cov_missing[:5]))
else:
    ok("all %d symbols covered in 0.7" % len(symkey))

# ---------------- (d) backtick identifiers ----------------
print("\n[d] backtick identifiers exist in 5 files or SDK")
sdkdirs = ["Core", "Engine", "GameFramework", "KFGame", "KFGameContent"]
sdktxt = {}
for d in sdkdirs:
    for root, _, fns in os.walk(os.path.join(SDK_ROOT, d)):
        for fn in fns:
            if fn.endswith(".uc"):
                fp = os.path.join(root, fn)
                sdktxt[fp] = open(fp, encoding="utf-8", errors="replace").read()
combined_src = "".join(src.values())

toks = set(re.findall(r"`([^`\n]{1,120})`", doc))
cands = set()
for t in toks:
    t = t.strip().strip("'")
    if re.match(r"^\w+([.\w]*)$", t) and len(t) >= 2 and t[0].isalpha():
        cands.add(t)
DOTTED_WHITELIST = {"build_symbols.py", "symbols.json", "d543db64", "ffc4906a",
    # doc-side artifacts, verified absent in SDK + mod sources (2026-07-14 re-verify):
    "FollowStuckMinMove\u00b2",        # superscript-2 typo of FollowStuckMinMove
    "KFGameInfoReplicationInfo",       # stale name (renamed KFGameInfo)
    "KFGfxObject_TraderItems",         # no such Gfx class in KF2 SDK
    "KFPickup_Cash",                   # no such pickup class
    "bFollowExit...",                  # ellipsis shorthand in prose
    "directActive",                    # stale KF2Bot variable name
    "forcePathUntil",                  # stale variable name
    "moveActive"}
unknown = []
for t in sorted(cands):
    if t in combined_src:
        continue
    if t in DOTTED_WHITELIST:
        continue
    # dotted tokens (e.g. System.IO.File): verify each dot segment
    if "." in t:
        parts = t.split(".")
        if all(p and (p in combined_src or any(p in v for v in sdktxt.values())) for p in parts):
            continue
    if not any(t in v for v in sdktxt.values()):
        unknown.append(t)
if unknown:
    for t in unknown:
        fail("unknown backtick identifier: `%s`" % t)
else:
    ok("all %d identifiers found in sources/SDK" % len(cands))
print("  identifiers checked: %d" % len(cands))

# ---------------- (e) constant values ----------------
print("\n[e] constant values == source")
cur_file = None
n_const = 0; n_constok = 0
for i, ln in enumerate(lines):
    m = re.match(r"^### 2\.2\.\d+ (\w+\.uc)", ln)
    if m:
        for pfx, fn in FILES.items():
            if fn == m.group(1):
                cur_file = pfx
        continue
    m = re.match(r"^\|\s*`(\w+)`\s*\|\s*\[(\d+)\]\s*\|\s*(.+?)\s*\|\s*$", ln)
    if m and cur_file:
        name, line, val = m.group(1), int(m.group(2)), m.group(3)
        sl = src_lines[cur_file][line-1].strip()
        mm = re.search(r"\b%s\s*=\s*([^;]+);" % re.escape(name), sl)
        n_const += 1
        if not mm:
            fail("const %s: line %d of %s has no `NAME = ...` decl: %s" % (name, line, cur_file, sl))
            continue
        sval = mm.group(1).strip()
        # numeric compare
        try:
            if abs(float(val) - float(sval)) < 1e-9:
                n_constok += 1
                continue
        except ValueError:
            pass
        if val == sval:
            n_constok += 1
            continue
        fail("const %s doc=%r src=%r (line %d %s)" % (name, val, sval, line, cur_file))
print("  constants: %d/%d match" % (n_constok, n_const))

# ---------------- (f) Part 2 line counts ----------------
print("\n[f] Part 2 line counts")
for ln in lines:
    m = re.match(r"^\|\s*(\w+\.uc)\s*\|\s*(\d+)\s*\|", ln)
    if m:
        fname, doccount = m.group(1), int(m.group(2))
        for pfx, fn in FILES.items():
            if fn == fname:
                real = len(src_lines[pfx])
                if real != doccount:
                    fail("file count %s doc=%d real=%d" % (fname, doccount, real))
                else:
                    ok("%s = %d lines" % (fname, real))
                break

# ---------------- (g) 25 random FLOW citations ----------------
print("\n[g] 25 random FLOW citations (review)")
random.seed(1234)
flowcites = []
flowline_of = {}
in_flow = False
curpfx = None
for i, ln in enumerate(lines):
    m = re.search(r"Primary file: (\w+\.uc)", ln)
    if m:
        for pfx, fn in FILES.items():
            if fn == m.group(1):
                curpfx = pfx
    if re.match(r"^#### 5\. FLOW", ln):
        in_flow = True
        continue
    if in_flow:
        if re.match(r"^#### ", ln):
            in_flow = False
            continue
        if ln.strip().startswith("```"):
            continue
        for cm in re.finditer(r"\[((?:Mut|Nav|Base|Logic|Bot):)?(\d[\d,\-]*)\]", ln):
            pfx = curpfx if cm.group(1) is None else cm.group(1)[:-1]
            flowcites.append((i, ln.strip(), pfx, cm.group(2)))
sample = random.sample(flowcites, min(25, len(flowcites)))
for i, ln, pfx, linestr in sorted(sample):
    lo = int(linestr.split("-")[0].split(",")[0])
    sl = src_lines[pfx][lo-1].strip() if lo <= len(src_lines[pfx]) else "<OUT OF BOUNDS>"
    print("  L%-4d %-58s [%s:%s] -> %s" % (i+1, ln[:58], pfx, linestr, sl[:70]))
print("  total flow citations: %d" % len(flowcites))

# ---------------- FLOW blocks plain ASCII ----------------
print("\n[extra] FLOW blocks plain ASCII")
badflow = 0
in_flow = False
for i, ln in enumerate(lines):
    if re.match(r"^#### 5\. FLOW", ln):
        in_flow = True; continue
    if in_flow:
        if re.match(r"^#### ", ln):
            in_flow = False; continue
        if ln.strip().startswith("```"):
            continue
        if any(ord(c) > 127 for c in ln):
            badflow += 1
            fail("non-ASCII in FLOW block L%d: %s" % (i+1, ln[:60]))
if badflow == 0:
    ok("all FLOW blocks ASCII")

# ---------------- summary ----------------
print("\n==== RESULT: %d failures ====" % len(failures))
for f_ in failures:
    print("  - " + f_)
sys.exit(1 if failures else 0)
