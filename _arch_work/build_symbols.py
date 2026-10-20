import json, hashlib, os, re, sys

ROOT = r"c:\Users\AnhBaSing\Documents\My Games\KillingFloor2\KFGame\Src\KF2Bots\Classes"
FILES = ["KF2BotsMut.uc", "KF2BotsFollowNavBase.uc", "KF2BotBase.uc", "KF2BotLogic.uc", "KF2Bot.uc"]

def strip_code(line, in_block):
    """Return (code_with_strings_blanked, in_block_after)."""
    out = []
    i, n = 0, len(line)
    in_str = None
    while i < n:
        c = line[i]
        if in_block:
            if c == '*' and i + 1 < n and line[i+1] == '/':
                in_block = False
                i += 2
                continue
            i += 1
            continue
        if in_str:
            if c == '\\':
                i += 2
                continue
            if c == in_str:
                in_str = None
            i += 1
            continue
        if c == '"' or c == "'":
            in_str = c
            i += 1
            continue
        if c == '/' and i + 1 < n and line[i+1] == '/':
            break
        if c == '/' and i + 1 < n and line[i+1] == '*':
            in_block = True
            i += 2
            continue
        out.append(c)
        i += 1
    return ''.join(out), in_block

def net_braces(s):
    return s.count('{') - s.count('}')

MODS = r'(?:static\s+|local\s+|final\s+|private\s+|public\s+|simulated\s+|reliable\s+|native\s+|config\s+|hidden\s+|exec\s+)*'
RE_CLASS = re.compile(r'^class\s+(\w+)\s+extends\s+(\w+)')
RE_STATE = re.compile(r'^' + MODS + r'state\s+(\w+)\s*(?:extends\s+(\w+))?\s*$')
RE_FUNC  = re.compile(r'^' + MODS + r'function\s+([\w<>,.\s]*?)(\w+)\s*\(')
RE_EVENT = re.compile(r'^' + MODS + r'event\s*(\(\s*\))?\s*$|^' + MODS + r'event\s+((?:\w+\s+)*)?(\w+)\s*\(')
RE_STRUCT= re.compile(r'^' + MODS + r'struct\s+(\w+)')
RE_ENUM  = re.compile(r'^' + MODS + r'enum\s+(\w+)')
RE_CONST = re.compile(r'^' + MODS + r'const\s+(.*)$')
RE_VAR   = re.compile(r'^' + MODS + r'var\s+(.*)$')
RE_DEFP  = re.compile(r'^defaultproperties\s*$')

def parse_var_body(body):
    body = body.strip().rstrip(';').strip()
    no_gen = re.sub(r'<[^<>]*(?:<[^<>]*>[^<>]*)*>', ' ', body)
    eq = no_gen.find('=')
    if eq >= 0:
        head = no_gen[:eq]
        default = no_gen[eq+1:].strip().rstrip(';').strip()
        m = re.match(r'^((?:\w+\s+)*?)(\w+)\s*(\[[^\]]*\])?\s*$', head)
        names = [m.group(2)] if m else [None]
    else:
        m = re.match(r'^((?:\w+\s+)*?)([\w\s,\[\]]+)$', no_gen)
        if not m:
            return None, body, ''
        names = []
        for chunk in m.group(2).split(','):
            chunk = re.sub(r'\[[^\]]*\]', '', chunk)
            ws = re.findall(r'\w+', chunk)
            if ws:
                names.append(ws[-1])
        default = ''
    return names, body, default

def parse_const_body(body):
    body = body.strip().rstrip(';').strip()
    if '=' in body:
        left, right = body.split('=', 1)
        left = left.strip()
        parts = left.split()
        name = parts[-1] if parts else body
        return name, right.strip()
    return body, ''

def main():
    out = {"files": {}, "symbols": []}
    for fname in FILES:
        path = os.path.join(ROOT, fname)
        raw = open(path, 'r', encoding='utf-8', errors='replace').read().splitlines()
        lines = raw
        n = len(lines)
        sha = hashlib.sha256(open(path, 'rb').read()).hexdigest()[:8]
        out["files"][fname] = {"lines": n, "sha256_8": sha}

        # pass 1: depth
        in_block = False
        stripped = []
        depth_before = []
        depth_after = []
        d = 0
        for ln in lines:
            code, in_block = strip_code(ln, in_block)
            stripped.append(code)
            depth_before.append(d)
            d += net_braces(code)
            depth_after.append(d)

        syms = []
        open_blocks = []  # dicts with kind baseline etc.

        def close_blocks_at(line_i, d_before, d_after):
            # remove blocks whose depth returned to baseline
            still = []
            for b in open_blocks:
                if d_after <= b['baseline'] and d_before > b['baseline']:
                    b['end'] = line_i + 1
                    syms.append(b)
                else:
                    still.append(b)
            open_blocks.clear()
            open_blocks.extend(still)

        pending = []  # brace blocks awaiting open
        for i, ln in enumerate(lines):
            code = stripped[i].strip()
            d_before, d_after = depth_before[i], depth_after[i]
            close_blocks_at(i, d_before, d_after)

            def enclosing(kind, depth):
                for b in reversed(open_blocks):
                    if b['kind'] == kind and depth > b['baseline']:
                        return b['name']
                return None

            depth_decl = d_before
            if not code:
                continue

            m = RE_CLASS.match(code)
            if m:
                syms.append({"name": m.group(1), "kind": "class", "file": fname,
                             "start": i+1, "end": n, "extends": m.group(2)})
                continue
            m = RE_STATE.match(code)
            if m:
                sym = {"name": m.group(1), "kind": "state", "file": fname,
                       "start": i+1, "extends": m.group(2),
                       "enclosing_state": None, "enclosing_struct": None,
                       "baseline": depth_decl}
                pending.append(sym)
                open_blocks.append(sym)
                continue
            m = RE_FUNC.match(code)
            if m:
                sym = {"name": m.group(2), "kind": "function", "file": fname,
                       "start": i+1, "return_type": m.group(1).strip(),
                       "enclosing_state": enclosing('state', depth_decl),
                       "enclosing_struct": enclosing('struct', depth_decl),
                       "baseline": depth_decl}
                pending.append(sym)
                open_blocks.append(sym)
                continue
            m = RE_EVENT.match(code)
            if m:
                name = m.group(3) if m.group(3) else 'event'
                sym = {"name": name, "kind": "event", "file": fname,
                       "start": i+1,
                       "enclosing_state": enclosing('state', depth_decl),
                       "enclosing_struct": None,
                       "baseline": depth_decl}
                pending.append(sym)
                open_blocks.append(sym)
                continue
            m = RE_STRUCT.match(code)
            if m:
                sym = {"name": m.group(1), "kind": "struct", "file": fname,
                       "start": i+1, "baseline": depth_decl,
                       "enclosing_state": None, "enclosing_struct": None}
                pending.append(sym)
                open_blocks.append(sym)
                continue
            m = RE_ENUM.match(code)
            if m:
                sym = {"name": m.group(1), "kind": "enum", "file": fname,
                       "start": i+1, "baseline": depth_decl}
                pending.append(sym)
                open_blocks.append(sym)
                continue
            m = RE_CONST.match(code)
            if m:
                name, val = parse_const_body(m.group(1))
                syms.append({"name": name, "kind": "const", "file": fname,
                             "start": i+1, "end": i+1, "value": val,
                             "enclosing_struct": enclosing('struct', depth_decl)})
                continue
            m = RE_VAR.match(code)
            if m:
                names, body, default = parse_var_body(m.group(1))
                for vname in names:
                    syms.append({"name": vname or ('?var@%d' % (i+1)), "kind": "var",
                                 "file": fname, "start": i+1, "end": i+1,
                                 "declaration": body, "default": default,
                                 "enclosing_state": enclosing('state', depth_decl),
                                 "enclosing_struct": enclosing('struct', depth_decl)})
                continue
            m = RE_DEFP.match(code)
            if m:
                sym = {"name": "defaultproperties", "kind": "defaultproperties",
                       "file": fname, "start": i+1, "baseline": depth_decl}
                pending.append(sym)
                open_blocks.append(sym)
                continue

        # end of file: close anything still open
        for b in open_blocks:
            if 'end' not in b:
                b['end'] = n
                syms.append(b)

        # prune helper keys
        for s in syms:
            s.pop('baseline', None)
        # sort by start line
        syms.sort(key=lambda s: (s['start'], s['end']))
        out["symbols"].extend(syms)
        counts = {}
        for s in syms:
            counts[s['kind']] = counts.get(s['kind'], 0) + 1
        print("%-28s lines=%-5d sha=%s  %s" % (fname, n, sha, counts))

    out_path = os.path.join(ROOT, "_arch_work", "symbols.json")
    json.dump(out, open(out_path, 'w', encoding='utf-8'), indent=1)
    print("total symbols:", len(out["symbols"]))
    print("written:", out_path)

if __name__ == '__main__':
    main()
