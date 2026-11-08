"""#150 trin 6d-1: ark for 1939's grene (entries) til slægtlinjer (lineage), til projektejerens afgørelse.

Én linje pr. gren i 1939-manifestet (I..VI og Stamme-<slug>) plus de allerede eksisterende entries (VI). Arket viser
fordelingen af modparternes 2018-20-linjer (kun afklarede samme_som-modparter i kilde 1) og grenens label (lever
under ~/.private). Token-filen har ét svar pr. gren: `L <gren> : <svar>`. Svar er kommaseparerede dele:
  C <kode>  canonical linje (kilde 1, 2018-20)        S <kode>  canonical linje i kilde 3 (1939's egen)
  A <kode>  tilføj historical_alias (kilde 1)         P         parkér grenen (hverken canonical eller alias)
Præcis én af C/S/P pr. gren; A må følge C/S. Forslag (forudfyldt `C <kode>`) gives kun ved flertalslinje >= 80 % og
ingen anden linje > 2 (memory forudfyldt-ark-skjuler-konflikt); ellers står svaret tomt. Eksisterende entries
(`VI`) står fast som `C VI` (betyder her kilde 3) og kan ikke ændres. `approvals` binder token-filen til arkets sha og afviser
ubesvarede linjer; den bærer kun label_sha256 (ingen tekst). stdout printer kun koder og tal.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import Counter
from pathlib import Path

from decision_sheet_core import SheetError
from spouse_exception_sheet import _write_private, check_private_path

THRESHOLD = 0.8
OTHER_MAX = 2
DIST_SOURCE = 1      # 2018-20
OWN_SOURCE = 3       # 1939's egen linje-nøgle (eksisterende entries)
L_RE = re.compile(r'^L (?P<code>\S+) : ?(?P<ans>.*)$')
SHA_RE = re.compile(r'^# ark-sha256 (?P<sha>[0-9a-f]{64})$')
KODE = r'[A-Za-z0-9_.-]+'
PART_RE = re.compile(rf'^(?P<t>[CAS]) (?P<kode>{KODE})$')


def _entries(m: dict, ex: dict) -> list[str]:
    seen: list[str] = []
    for p in m['placements']:
        c = p.get('entry_code')
        if c and c not in seen:
            seen.append(c)
    for c in ex.get('entries', []):
        if c not in seen:
            seen.append(c)
    return seen


def _header(m: dict, code: str) -> dict | None:
    for h in m['headers']:
        if h['kind'] != 'header_linje':
            continue
        pr = h.get('parsed', {})
        if pr.get('roman') == code or (pr.get('stamme_slug') and f"Stamme-{pr['stamme_slug']}" == code):
            return h
    return None


def _label_sha(h: dict | None) -> str | None:
    if h is None:
        return None
    return h.get('verbatim_sha256') or hashlib.sha256(h['verbatim_text'].encode('utf-8')).hexdigest()


def distribution(m: dict, ex: dict) -> dict[str, Counter]:
    code_of = {p['record_key']: p.get('entry_code') for p in m['placements']}
    d: dict[str, Counter] = {c: Counter() for c in _entries(m, ex)}
    for c in ex.get('counterparts', []):
        if c['source_id'] == DIST_SOURCE and code_of.get(c['record_key']) in d:
            d[code_of[c['record_key']]][c['lineage_kode']] += 1
    return d


def suggestion(cnt: Counter) -> str | None:
    total = sum(cnt.values())
    if not total:
        return None
    (top, n), rest = cnt.most_common(1)[0], cnt.most_common()[1:]
    if n / total >= THRESHOLD and all(k <= OTHER_MAX for _, k in rest):
        return top
    return None


def _existing(ex: dict) -> set[str]:
    return set(ex.get('entries', []))


def render(m: dict, ex: dict) -> tuple[str, str]:
    dist = distribution(m, ex)
    ark = ['# ============ GRENE I 1939 -> SLÆGTLINJER (#150 trin 6d-1) ============',
           '# Én linje pr. gren: antal modparter pr. 2018-20-linje (kode=antal) og grenens label.',
           '# Forslag gives kun ved flertalslinje >= 80 % og ingen anden linje > 2. Eksisterende entries står fast.']
    tok = ['# ============ SVAR: GRENE -> SLÆGTLINJER ============',
           '# Skriv svaret efter kolonet på hver »L«-linje. Alt med »#« er information.',
           '#   C <kode> = canonical 2018-20-linje · S <kode> = canonical linje i 1939 · A <kode> = tilføj alias · P = parkér',
           '#   Flere dele adskilles med komma, fx »C II, A III«. Præcis én af C/S/P pr. gren.']
    for code in _entries(m, ex):
        h, cnt = _header(m, code), dist[code]
        label = h['verbatim_text'] if h else '?'
        fordeling = ', '.join(f'{k}={n}' for k, n in sorted(cnt.items(), key=lambda kv: (-kv[1], kv[0]))) or 'ingen modparter'
        ark.append(f'# {code} ({label}): {fordeling}')
        if code in _existing(ex):
            ans = f'C {code}'
            ark[-1] += ' [eksisterende entry, står fast]'
        else:
            ans = f'C {suggestion(cnt)}' if suggestion(cnt) else ''
        tok.append(f'L {code} : {ans}')
    ark_text = '\n'.join(ark) + '\n'
    sha = hashlib.sha256(ark_text.encode('utf-8')).hexdigest()
    return ark_text, '\n'.join([f'# ark-sha256 {sha}'] + tok) + '\n'


def summary(m: dict, ex: dict) -> str:
    dist = distribution(m, ex)
    n = sum(1 for c in dist if c not in _existing(ex) and suggestion(dist[c]))
    return f'ARK_OK grene={len(dist)} forslag={n}'


def _parse(ans: str, code: str, fixed: bool) -> tuple[dict | None, list[dict], bool]:
    parts = [x.strip() for x in ans.split(',')]
    if not ans.strip():
        raise SheetError('SHEET_UNANSWERED')
    canonical, aliases, parkeret = None, [], False
    for x in parts:
        if x == 'P':
            if parkeret or canonical:
                raise SheetError('SHEET_TOKEN_NOT_ALLOWED')
            parkeret = True
            continue
        mm = PART_RE.match(x)
        if mm is None:
            raise SheetError('SHEET_TOKEN_NOT_ALLOWED')
        if mm['t'] == 'A':
            aliases.append({'source_id': DIST_SOURCE, 'kode': mm['kode']})
        elif canonical or parkeret:
            raise SheetError('SHEET_TOKEN_NOT_ALLOWED')
        else:
            canonical = {'source_id': DIST_SOURCE if mm['t'] == 'C' else OWN_SOURCE, 'kode': mm['kode']}
    if parkeret and aliases or (canonical is None and not parkeret):
        raise SheetError('SHEET_TOKEN_NOT_ALLOWED')
    return canonical, aliases, parkeret


def approvals(text: str, m: dict, ex: dict, sheet_sha256: str) -> dict:
    shas = [SHA_RE.match(l)['sha'] for l in text.splitlines() if SHA_RE.match(l)]
    if shas != [sheet_sha256]:
        raise SheetError('SHEET_SHA_MISMATCH')
    codes = _entries(m, ex)
    answers: dict[str, str] = {}
    for raw in text.splitlines():
        if not raw.startswith('L '):
            continue
        mm = L_RE.match(raw)
        if mm is None or mm['code'] not in codes or mm['code'] in answers:
            raise SheetError('SHEET_LINE_INVALID')
        answers[mm['code']] = mm['ans'].strip()
    for c in codes:
        if c in answers and not answers[c]:
            raise SheetError('SHEET_UNANSWERED')
    if set(answers) != set(codes):
        raise SheetError('SHEET_LINES_MISSING')
    entries = []
    for i, c in enumerate(codes, 1):
        fixed = c in _existing(ex)
        if fixed:   # eksisterende entry: kun den faste linje `C <kode>`, som betyder kilde 3
            if answers[c] != f'C {c}':
                raise SheetError('SHEET_TOKEN_NOT_ALLOWED')
            canonical, aliases, parkeret = {'source_id': OWN_SOURCE, 'kode': c}, [], False
        else:
            canonical, aliases, parkeret = _parse(answers[c], c, fixed)
        entries.append({'code': c, 'label_sha256': _label_sha(_header(m, c)), 'sort_order': i,
                        'canonical': canonical, 'aliases': aliases, 'parkeret': parkeret})
    return {'sheet_sha256': sheet_sha256, 'entries': entries}


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)
    r, a = sub.add_parser('render'), sub.add_parser('approvals')
    for x in (r, a):
        x.add_argument('--manifest', required=True)
        x.add_argument('--export', required=True)
        x.add_argument('--private-root', default=str(Path.home() / '.private'))
    r.add_argument('--out-ark', required=True)
    r.add_argument('--out-token', required=True)
    for opt in ('--ark', '--token', '--approved-ark-sha256', '--out'):
        a.add_argument(opt, required=True)
    args = ap.parse_args()
    root = Path(args.private_root)
    try:
        m = json.loads(check_private_path(Path(args.manifest), root).read_text(encoding='utf-8'))
        ex = json.loads(check_private_path(Path(args.export), root).read_text(encoding='utf-8'))
        if args.cmd == 'render':
            ark, tok = render(m, ex)
            _write_private(check_private_path(Path(args.out_ark), root), ark)
            _write_private(check_private_path(Path(args.out_token), root), tok)
            print(summary(m, ex))
            return 0
        ark = check_private_path(Path(args.ark), root).read_bytes()
        tok = check_private_path(Path(args.token), root).read_bytes()
        sha = hashlib.sha256(ark).hexdigest()
        if sha != args.approved_ark_sha256:
            raise SheetError('SHEET_SHA_MISMATCH')
        res = approvals(tok.decode('utf-8'), m, ex, sha)
        _write_private(check_private_path(Path(args.out), root), json.dumps(res, sort_keys=True) + '\n')
    except SheetError as exc:
        print(str(exc).split(' ')[0])
        return 1
    print(f"APPROVALS_OK grene={len(res['entries'])} parkeret={sum(e['parkeret'] for e in res['entries'])}")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
