"""#150 trin 5c-1 (spec §4.2 pkt. 3): blind, stratificeret kontrolstikprøve og token-fil for placement.

Kontrolarket (K poster, fast seed) viser kun postens nøgle og side; projektejeren slår posten op i PDF'en og
skriver selv slægtled (tal) og kuld (romertal eller -). `approvals` sammenligner med manifestet: én afvigelse
stopper (KONTROL_AFVIGELSE). Token-filen samler de unresolved poster i grupper pr. slægtled og årsag, uden
forudfyldte svar: kuld (J = ingen kuld-markør i slægtleddet, accepter uden kuld · N = lad stå). Forælder-
generation (barnet i forælderens slægtled) godkendes ikke her: posten står uafklaret i 5c-1 (projektejeren
2026-10-27). `approvals` kræver, at kontrolarket er netop stikprøven (nøgler, rækkefølge, sider) og skriver
afgørelsesfilen {manifest_sha256, sheet_sha256, kontrolark_sha256, record_keys}, som fix_150_placement.sql læser.
Manifest, ark og token-fil hører under ~/.private (ægteskabsoverskrifter nævner levende); værktøjet printer kun tal.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import random
import re
from pathlib import Path

from decision_sheet_core import SheetError
from private_io import (check_private_path, write_private_new_many,
                        write_private_replace)

QUOTA = {'slaegtled': 4, 'kuld': 4, 'laengste': 3, 'side': 2}
# Kun disse årsager kan godkendes i token-filen; fix_150_placement.sql håndhæver samme liste (FIX150_PRE_APPROVALS).
GROUP_KINDS = {'uenig:kuld': 'kuld'}
TOKENS = {'kuld': {'J', 'N'}}
APPROVE = {'kuld': 'J'}
K_RE = re.compile(r'^K (?P<key>\S+) side (?P<page>\d+) : ?(?P<ans>.*)$')
ANS_RE = re.compile(r'^(?P<gen>\d+) (?P<kuld>[IVX]+|-)$')
G_RE = re.compile(r'^G (?P<kind>[a-z_]+):(?P<hid>header:\d+) : ?(?P<tok>\S*)\s*$')


def _ok(m: dict) -> list[dict]:
    return [p for p in m['placements'] if p['status'] == 'machine_ok']


def _first_after(m: dict, level: str) -> list[str]:
    """Første maskinelt accepterede post under hver overskrift af niveauet (i dokumentorden)."""
    seen, out = set(), []
    for p in _ok(m):
        hid = p['header_ids'].get(level)
        if hid is not None and hid not in seen:
            seen.add(hid)
            out.append(p['record_key'])
    return out


def sample(m: dict, k: int = 20, seed: int = 150) -> list[str]:
    rng = random.Random(seed)
    ok = [p['record_key'] for p in _ok(m)]
    chosen: list[str] = []

    def take(keys: list[str], n: int | None) -> None:
        cand = [x for x in keys if x not in chosen]
        if n is not None and len(cand) > n:
            cand = sorted(rng.sample(cand, n), key=ok.index)
        chosen.extend(cand)

    take(_first_after(m, 'linje'), None)
    take(_first_after(m, 'slaegtled'), QUOTA['slaegtled'])
    take(_first_after(m, 'kuld'), QUOTA['kuld'])
    by_slaegtled: dict[str, list[str]] = {}
    for p in _ok(m):
        by_slaegtled.setdefault(p['header_ids'].get('slaegtled', ''), []).append(p['record_key'])
    longest = sorted(by_slaegtled.values(), key=len, reverse=True)[:QUOTA['laengste']]
    take([keys[-1] for keys in longest], None)
    pages = _ok(m)
    take([b['record_key'] for a, b in zip(pages, pages[1:]) if b['page'] != a['page']], QUOTA['side'])
    rest = [x for x in ok if x not in chosen]
    chosen.extend(sorted(rng.sample(rest, max(0, min(k - len(chosen), len(rest)))), key=ok.index))
    return chosen[:k] if len(chosen) > k else chosen


def render_kontrolark(m: dict, keys: list[str]) -> str:
    by = {p['record_key']: p for p in m['placements']}
    out = ['# ============ KONTROLSTIKPRØVE: PLACEMENT 2018-20 (#150) ============',
           '# Slå hver post op i PDF\'en (linje og nr. står i nøglen, fx II-15 = linje II, nr. 15). »side« er PDF-filens',
           '# sidenummer (som PDF-læseren viser det), ikke bogens trykte sidetal; posten kan begynde nederst på siden.',
           '# Skriv efter kolonet: slægtleddet som tal (lokalt i linjen, fx 3 for »Tredje slægtled«) og kuld-markøren',
           '# over posten som romertal, eller - hvis posten ikke står under nogen kuld-markør i sit slægtled.',
           '#   Eksempel:  K II-15 side 412 : 3 II        K I-1 side 10 : 1 -',
           '# Alt med »#« er information. Én afvigelse fra maskinen stopper kørslen.',
           f'# {len(keys)} poster']
    out += [f"K {k} side {by[k]['page']} : " for k in keys]
    return '\n'.join(out) + '\n'


def check_kontrolark(text: str, m: dict, expected: list[str]) -> list[str]:
    """expected = stikprøven (sample(m, k, seed)); arket skal have netop de nøgler, i den rækkefølge, med sider."""
    by = {p['record_key']: p for p in m['placements']}
    keys = []
    for raw in text.splitlines():
        if not raw.startswith('K '):
            continue
        mm = K_RE.match(raw)
        if mm is None or mm['key'] not in by or by[mm['key']]['status'] != 'machine_ok' or mm['key'] in keys:
            raise SheetError('SHEET_LINE_INVALID')
        if int(mm['page']) != by[mm['key']]['page']:
            raise SheetError('SHEET_SAMPLE_MISMATCH')
        ans = mm['ans'].strip()
        if not ans:
            raise SheetError('SHEET_UNANSWERED')
        a = ANS_RE.match(ans)
        if a is None:
            raise SheetError('SHEET_TOKEN_NOT_ALLOWED')
        p = by[mm['key']]
        if int(a['gen']) != p['generation_local'] or (None if a['kuld'] == '-' else a['kuld']) != p['kuld_label']:
            raise SheetError(f"KONTROL_AFVIGELSE {mm['key']}")
        keys.append(mm['key'])
    if keys != list(expected):
        raise SheetError('SHEET_SAMPLE_MISMATCH')
    return keys


def groups(m: dict) -> list[dict]:
    hpos = {h['element_id']: h['char_from'] for h in m['headers']}
    g: dict[tuple[str, str], list[str]] = {}
    for p in m['placements']:
        if p['status'] != 'unresolved':
            continue
        for r in p['reasons']:
            if r in GROUP_KINDS:
                g.setdefault((GROUP_KINDS[r], p['header_ids'].get('slaegtled', '')), []).append(p['record_key'])
    order = list(GROUP_KINDS.values())
    return [{'kind': kind, 'header_id': hid, 'record_keys': keys}
            for (kind, hid), keys in sorted(g.items(), key=lambda kv: (order.index(kv[0][0]), hpos.get(kv[0][1], -1)))]


def render_token(m: dict) -> str:
    hs = {h['element_id']: h for h in m['headers']}
    by = {p['record_key']: p for p in m['placements']}
    out = ['# ============ UAFKLAREDE PLACERINGER 2018-20 (#150) ============',
           '# Kun linjerne, der starter med »G«, kan ændres — skriv bogstavet efter kolonet. Alt med »#« er information.',
           '# KULD: legacy har et kuld fra forrige slægtled; overskrifterne giver intet kuld i dette slægtled.',
           '#   J = slægtleddet har ingen kuld-markør før disse poster (accepter uden kuld) · N = lad stå uafklaret']
    for g in groups(m):
        h = hs.get(g['header_id'], {})
        p0 = by[g['record_keys'][0]]
        out += ['#', f"# {g['kind'].upper()}: linje {p0['entry_code']}, {h.get('parsed', {}).get('ordinal', '?')}. slægtled"
                     f" (overskrift side {h.get('page_from', '?')}): {len(g['record_keys'])} poster "
                     f"{', '.join(g['record_keys'])} (sider {by[g['record_keys'][0]]['page']}-{by[g['record_keys'][-1]]['page']})",
                f"G {g['kind']}:{g['header_id']} : "]
    rest = [p['record_key'] for p in m['placements'] if p['status'] == 'unresolved'
            and not all(r in GROUP_KINDS for r in p['reasons'])]
    out += ['#', f'# Står uafklaret uden afgørelse her ({len(rest)}; fx barn i forælderens slægtled — opfølgning): '
                 + ', '.join(rest)]
    return '\n'.join(out) + '\n'


def approvals(text: str, m: dict, sheet_sha256: str) -> dict:
    want = {(g['kind'], g['header_id']): g for g in groups(m)}
    answers: dict[tuple[str, str], str] = {}
    for raw in text.splitlines():
        if not raw.startswith('G '):
            continue
        mm = G_RE.match(raw)
        key = (mm['kind'], mm['hid']) if mm else None
        if key not in want or key in answers:
            raise SheetError('SHEET_LINE_INVALID')
        if not mm['tok']:
            raise SheetError('SHEET_UNANSWERED')
        if mm['tok'] not in TOKENS[mm['kind']]:
            raise SheetError('SHEET_TOKEN_NOT_ALLOWED')
        answers[key] = mm['tok']
    if set(answers) != set(want):
        raise SheetError('SHEET_LINES_MISSING')
    ok_groups = {(k, h) for (k, h), t in answers.items() if t == APPROVE[k]}
    keys = []
    for p in m['placements']:
        if p['status'] != 'unresolved' or not p['reasons']:
            continue
        sl = p['header_ids'].get('slaegtled', '')
        if all(r in GROUP_KINDS and (GROUP_KINDS[r], sl) in ok_groups for r in p['reasons']):
            keys.append(p['record_key'])
    return {'sheet_sha256': sheet_sha256, 'record_keys': keys}


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)
    r = sub.add_parser('render')
    a = sub.add_parser('approvals')
    for x in (r, a):
        x.add_argument('--manifest', required=True)
        x.add_argument('--private-root', default=str(Path.home() / '.private'))
    for x in (r, a):
        x.add_argument('--k', type=int, default=20)
        x.add_argument('--seed', type=int, default=150)
    r.add_argument('--out-kontrolark', required=True)
    r.add_argument('--out-token', required=True)
    for opt in ('--kontrolark', '--token', '--approved-token-sha256', '--out'):
        a.add_argument(opt, required=True)
    args = ap.parse_args()
    root = Path(args.private_root)
    try:
        m = json.loads(check_private_path(Path(args.manifest), root).read_text(encoding='utf-8'))
        if args.cmd == 'render':
            keys = sample(m, args.k, args.seed)
            # Kontrolark + token er et par: begge nægtes, før noget skrives, hvis én findes.
            write_private_new_many([
                (check_private_path(Path(args.out_kontrolark), root), render_kontrolark(m, keys)),
                (check_private_path(Path(args.out_token), root), render_token(m))])
            print(f"ARK_OK kontrol={len(keys)} grupper={len(groups(m))}")
            return 0
        ark = check_private_path(Path(args.kontrolark), root).read_bytes()
        tok = check_private_path(Path(args.token), root).read_bytes()
        tok_sha = hashlib.sha256(tok).hexdigest()
        if tok_sha != args.approved_token_sha256:
            raise SheetError('SHEET_SHA_MISMATCH')
        kontrol = check_kontrolark(ark.decode('utf-8'), m, sample(m, args.k, args.seed))
        res = approvals(tok.decode('utf-8'), m, tok_sha)
        res['kontrolark_sha256'] = hashlib.sha256(ark).hexdigest()
        res['manifest_sha256'] = hashlib.sha256(Path(args.manifest).read_bytes()).hexdigest()
        write_private_replace(check_private_path(Path(args.out), root), json.dumps(res, sort_keys=True) + '\n')
    except SheetError as exc:
        print(str(exc).split(' ')[0])
        return 1
    print(f"APPROVALS_OK kontrol={len(kontrol)} godkendt={len(res['record_keys'])}")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
