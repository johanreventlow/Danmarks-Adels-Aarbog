"""Trin 6d-1 Task 8 (decisions 2026-11-09): 1939's placeringskort som blinde opslag, som en model læser mod PDF-siden.

Alle kort er samme slags opslag: en post (side, gren, postens første ord uden nummer) og tre ting at læse af det trykte
sidebillede: slægtleddet, gruppens romertal og postens trykte nummer. Kortet sammenligner så de felter, det har en anden
læsning af (guiden raw.txt, Calamari eller maskinen):

  K  stikprøve (blind, maskinelt godkendte poster)      slægtled + gruppe      = manifestets placering
  GK gruppekort (overskrift ikke fundet i Calamari)      niveauets værdi        = guidens værdi
  SK strukturkort (ikke_parret/nummer_tabt/ikke_alignet) slægtled + gruppe + nr = nærmeste overskrifter + anden læsning
  SG stammegruppe (stamme_generation_usikker)            slægtled               = manifestets slægtled
  NK nummerkort (nr_ikke_fortloebende)                   nr                     = manifestets nummer

Enighed godkender kortet med læseren `model`. Uenighed, ulæselig side eller ingen anden læsning → undtagelseslisten, som
projektejeren besvarer (læser `human`); desuden slår han 5 tilfældige enige stikprøveposter op (V-linjer). Resultatet er
godkendelseskontrakt v3 til placement_ceremoni.sql.

Underkommandoer:
  job          manifest + records + rendition + PDF -> jobmappe (opslag.json, brief.md, sider/*.png) til modellen
  undtagelser  modelsvarene -> token-fil (U-/V-linjer) + lokal HTML med sidebillederne (under ~/.private)
  flet         HTML-sidens svarfil (kort-svar.json) -> tokens i token-filen
  approvals    modelsvar + besvaret token-fil -> approvals.json (kontrakt v3)
Jobmappen må ikke ligge under ~/.private eller i et git-repo; modellen læser kun den. Værktøjet printer kun tal og sha.
"""
from __future__ import annotations

import argparse
import hashlib
import html
import json
import random
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

from decision_sheet_core import SheetError
from spouse_exception_sheet import _write_private, check_private_path

ROMAN = re.compile(r'^[IVXLC]+$')
STRUKTUR = ('ikke_parret', 'nummer_tabt_i_rendition', 'ikke_alignet')
QUOTA = {'slaegtled': 4, 'kuld': 4}
SEED = 1939
V_ANTAL = 5
SIKKERHED = ('hoej', 'middel', 'lav')
NR_RE = re.compile(r'^\d+[a-z]?$')
LEAD_NR = re.compile(r'^\s*\??\s*\d+[a-z]?\s*[.,]\s*')
START_LEN = 160
KORT_TYPER = ('K', 'GK', 'SK', 'SG', 'NK')
# Records uden personpost (helpost) kan ikke placeres af ceremonien; de godkendes aldrig (generalprøven 9/11:
# en henvisningspost fik et strukturkort; projektejeren valgte ingen placement). Kortene vises stadig.
IKKE_PLACERBAR = ('cross_reference', 'structural_context')


def _sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def _roman(v: Any) -> str | None:
    return v if isinstance(v, str) and ROMAN.match(v) else None


def _norm_gruppe(v: Any) -> str | None:
    if v is None:
        return None
    s = str(v).strip().rstrip('.').upper()
    return '-' if s in ('-', '') else s


def _norm_nr(v: Any) -> str | None:
    if v is None:
        return None
    s = str(v).strip().rstrip('.').lower()
    return '-' if s in ('-', '') else s


def _gruppe(headers: dict[str, dict], hids: dict | None, kuld_label: Any) -> str:
    """Gruppens romertal, som bogen trykker det: Calamari-etiketten, når den er et romertal, ellers guidens romertal for
    gruppeoverskriften (kun kontrol, aldrig evidens), ellers '-' (ingen romertal over posten i slægtleddet)."""
    if _roman(kuld_label):
        return kuld_label
    hid = (hids or {}).get('kuld')
    if hid and hid in headers:
        gv = (headers[hid].get('parsed') or {}).get('guide', {}).get('value')
        if _roman(gv):
            return gv
    return '-'


def _book_order(p: dict) -> tuple:
    return (p['page'] if p['page'] is not None else 10**9, p.get('post_char_from') or 0, p['record_key'])


def sample_1939(m: dict, k: int = 20, seed: int = SEED) -> list[str]:
    """Blind, stratificeret stikprøve af maskinelt godkendte poster: første post efter hver linjeoverskrift, 4 efter
    slægtled, 4 efter gruppe, én af hver record_kind ≠ person, resten tilfældigt (fast seed); i bogens orden."""
    rng = random.Random(seed)
    ok = sorted((p for p in m['placements'] if p['status'] == 'machine_ok'), key=_book_order)
    keys = [p['record_key'] for p in ok]
    chosen: list[str] = []

    def take(cand: list[str], n: int | None) -> None:
        cand = [x for x in dict.fromkeys(cand) if x not in chosen]
        if n is not None and len(cand) > n:
            cand = rng.sample(cand, n)
        chosen.extend(cand)

    def first_after(level: str) -> list[str]:
        seen: set[str] = set()
        out = []
        for p in ok:
            hid = p['header_ids'].get(level)
            if hid is not None and hid not in seen:
                seen.add(hid)
                out.append(p['record_key'])
        return out

    take(first_after('linje'), None)
    take(first_after('slaegtled'), QUOTA['slaegtled'])
    take(first_after('kuld'), QUOTA['kuld'])
    for kind in sorted({p['record_kind'] for p in ok} - {'person'}):
        take([p['record_key'] for p in ok if p['record_kind'] == kind], 1)
    rest = [x for x in keys if x not in chosen]
    take(rest, max(0, min(k - len(chosen), len(rest))))
    chosen = chosen[:k]
    return sorted(chosen, key=keys.index)


def _kandidat_nr(lokal_id: str) -> str | None:
    last = str(lokal_id).rsplit('.', 1)[-1]
    return last.lower() if NR_RE.match(last.lower()) else None


def kort_1939(m: dict, k: int = 20, seed: int = SEED) -> list[dict]:
    """Kortene i fast orden (K, GK, SK, SG, NK). Hvert kort: kort_id, type, opslag (record_key for posten, der slås
    op), poster (de poster kortet dækker) og forventet (felterne, modellens læsning sammenlignes med; None = ingen anden
    læsning, så kortet går til projektejeren)."""
    headers = {h['element_id']: h for h in m['headers']}
    by = {p['record_key']: p for p in m['placements']}
    order = sorted(m['placements'], key=_book_order)
    out: list[dict] = []
    for key in sample_1939(m, k, seed):
        p = by[key]
        out.append({'kort_id': f'K:{key}', 'type': 'K', 'opslag': key, 'poster': [key],
                    'forventet': {'slaegtled': p['generation_local'],
                                  'gruppe': _gruppe(headers, p['header_ids'], p['kuld_label'])}})
    cards: dict[str, dict] = {}
    for p in order:
        if p['status'] != 'unresolved':
            continue
        for c in p.get('gruppekort') or []:
            cards.setdefault(c['id'], {'c': c, 'poster': []})['poster'].append(p['record_key'])
    for cid, g in sorted(cards.items(), key=lambda kv: kv[1]['c']['guide_char_from']):
        c = g['c']
        felt = 'gruppe' if c['niveau'] == 'kuld' else 'slaegtled'
        if felt == 'gruppe' and not _roman(c['guide_value']):
            felt = 'beskrivelse'                   # stammegruppe uden romertal: kun projektejerens J/N
        out.append({'kort_id': f'GK:{cid}', 'type': 'GK', 'opslag': g['poster'][0], 'poster': g['poster'],
                    'gk_id': cid, 'niveau': c['niveau'], 'forventet': {felt: c['guide_value']}})
    for p in order:
        if p['status'] != 'unresolved' or not set(p['reasons']) & set(STRUKTUR):
            continue
        nh = p.get('naermeste_header_ids') or {}
        if 'nummer_tabt_i_rendition' in p['reasons']:
            nr: Any = p.get('guide_nr_label')
        elif 'ikke_alignet' in p['reasons']:
            nr = p.get('printed_number')
        else:
            nrs = sorted({n for n in (_kandidat_nr(x) for x in (p.get('guide_kandidater') or [])) if n})
            nr = nrs[0] if len(nrs) == 1 else None
        out.append({'kort_id': f"SK:{p['record_key']}", 'type': 'SK', 'opslag': p['record_key'],
                    'poster': [p['record_key']],
                    'forventet': {'slaegtled': p.get('naermeste_generation_local') if 'slaegtled' in nh else None,
                                  'gruppe': _gruppe(headers, nh, p.get('naermeste_kuld_label')) if 'linje' in nh else None,
                                  'nr': _norm_nr(nr)}})
    groups: dict[str, list[dict]] = {}
    for p in order:
        if p['status'] == 'unresolved' and 'stamme_generation_usikker' in p['reasons']:
            groups.setdefault(p['header_ids'].get('kuld') or f"post:{p['record_key']}", []).append(p)
    for gid, ps in groups.items():
        gens = {q['generation_local'] for q in ps}
        out.append({'kort_id': f'SG:{gid}', 'type': 'SG', 'opslag': ps[0]['record_key'],
                    'poster': [q['record_key'] for q in ps],
                    'forventet': {'slaegtled': gens.pop() if len(gens) == 1 else None}})
    for p in order:
        if p['status'] == 'unresolved' and 'nr_ikke_fortloebende' in p['reasons']:
            out.append({'kort_id': f"NK:{p['record_key']}", 'type': 'NK', 'opslag': p['record_key'],
                        'poster': [p['record_key']], 'forventet': {'nr': _norm_nr(p['printed_number'])}})
    ids = [c['kort_id'] for c in out]
    if len(ids) != len(set(ids)):
        raise SheetError('KORT_DUBLET')
    return out


def _gren(m: dict, p: dict) -> str | None:
    return p['entry_code'] if p['entry_code'] is not None else p.get('naermeste_entry_code')


def opslag(m: dict, cards: list[dict], records: list[dict], rendition: str) -> list[dict]:
    """Det blinde input pr. kort: side, gren og postens første ord (uden trykt nummer). Ingen forventede værdier."""
    by = {p['record_key']: p for p in m['placements']}
    char = {r['record_key']: r['char_from'] for r in records}
    out = []
    for c in cards:
        p = by[c['opslag']]
        pos = p.get('post_char_from')
        pos = char[c['opslag']] if pos is None else pos
        start = ' '.join(rendition[pos:pos + START_LEN + 20].split())
        start = LEAD_NR.sub('', start)[:START_LEN]
        side = p['page']
        out.append({'kort_id': c['kort_id'], 'side': side, 'sider': [s for s in (side - 1, side) if s >= 1],
                    'gren': _gren(m, p), 'start_tekst': start})
    return out


BRIEF = """# Opslag i Danmarks Adels Aarbog 1939 (Reventlow-stamtavlen)

Du får en liste af opslag. Hvert opslag peger på én post i stamtavlen: `side` (PDF-sidetal), `gren` (grenens romertal
eller fællesstammens navn, fx `Stamme-holstenske`) og `start_tekst` (postens første ord efter det trykte nummer, fra en
OCR, der kan have fejl). Sidebillederne ligger i `sider/side-<NNN>.png` i samme mappe; brug kun disse filer.

For hvert opslag: find posten på siden (eller nederst på siden før, hvis den begynder der) og læs af **billedet**:

1. `slaegtled` (heltal): nærmeste overskrift »N. Slægtled« (fx »Tredie Slægtled« = 3) over posten inden for grenen.
   I fællesstammen, hvor afsnittene har romertal i stedet for slægtled-overskrifter, er det romertallet over afsnittet
   omregnet til tal (III = 3). Står der et bogstav efter romertallet (»IV A.«), er slægtleddet stadig romertallet
   (4); bogstavet er ikke et gruppe-romertal. `null`, hvis du ikke kan afgøre det.
2. `gruppe`: romertallet (I, II, III …), der står som gruppeoverskrift over posten *inden for samme slægtled*, eller `-`,
   hvis der ikke står noget romertal mellem slægtled-overskriften og posten. En beskrivende linje uden romertal (fx »Børn
   af …«) tæller ikke. `null`, hvis du ikke kan afgøre det.
3. `nr`: postens trykte nummer, som det står foran navnet (fx `3` eller `3a`), `-` hvis posten ikke har noget nummer.

Til hvert felt: skriv den linje, du har læst feltet ud fra, **ordret** fra billedet (`slaegtled_linje`, `gruppe_linje`,
`nr_linje`). Gæt ikke: kan du ikke se det sikkert, så skriv `null` og sæt `sikkerhed` til `lav`. Overskrifter kan stå
på siden før posten.

Svar med ét JSON-array, ét objekt pr. opslag, i samme rækkefølge:
`{"kort_id": "...", "fundet": true, "side": 512, "slaegtled": 3, "slaegtled_linje": "...", "gruppe": "II",
"gruppe_linje": "...", "nr": "4", "nr_linje": "...", "sikkerhed": "hoej|middel|lav", "note": ""}`
`fundet` = false, hvis posten ikke kan findes. Intet andet end JSON-arrayet i svaret.
"""


def _check_jobdir(jobdir: Path, private_root: Path) -> Path:
    j = jobdir.resolve()
    if private_root.resolve() in [j, *j.parents]:
        raise SheetError('KORT_JOBDIR_PRIVAT')
    for parent in [j, *j.parents]:
        if (parent / '.git').exists() or parent.name.startswith('work'):
            raise SheetError('KORT_JOBDIR_I_REPO')
    return j


def render_pages(pdf: Path, pages: list[int], outdir: Path, dpi: int = 150) -> None:
    outdir.mkdir(parents=True, exist_ok=True)
    for s in pages:
        dst = outdir / f'side-{s:03d}.png'
        if dst.exists():
            continue
        prefix = outdir / f'_tmp-{s:03d}'
        subprocess.run(['pdftoppm', '-f', str(s), '-l', str(s), '-r', str(dpi), '-png', '-singlefile', str(pdf),
                        str(prefix)], check=True, capture_output=True)
        Path(f'{prefix}.png').rename(dst)


def build_job(m: dict, records: list[dict], rendition: str, pdf: Path | None, jobdir: Path,
              k: int = 20, seed: int = SEED) -> dict:
    cards = kort_1939(m, k, seed)
    ops = opslag(m, cards, records, rendition)
    jobdir.mkdir(parents=True, exist_ok=True)
    (jobdir / 'brief.md').write_text(BRIEF, encoding='utf-8')
    (jobdir / 'opslag.json').write_text(json.dumps(ops, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    if pdf is not None:
        render_pages(pdf, sorted({s for o in ops for s in o['sider']}), jobdir / 'sider')
    return {'kort': len(cards), 'pr_type': {t: sum(c['type'] == t for c in cards) for t in KORT_TYPER},
            'sider': len({s for o in ops for s in o['sider']}),
            'brief_sha256': _sha(BRIEF.encode('utf-8')),
            'opslag_sha256': _sha((jobdir / 'opslag.json').read_bytes())}


# --- sammenligning ---------------------------------------------------------------------------------------------

def _svar_map(svar: list[dict], cards: list[dict]) -> dict[str, dict]:
    if not isinstance(svar, list):
        raise SheetError('KORT_SVAR_FORM')
    by: dict[str, dict] = {}
    for s in svar:
        if not isinstance(s, dict) or s.get('kort_id') in by:
            raise SheetError('KORT_SVAR_FORM')
        by[s['kort_id']] = s
    want = {c['kort_id'] for c in cards}
    if set(by) - want:
        raise SheetError('KORT_SVAR_UKENDT')
    if want - set(by):
        raise SheetError('KORT_SVAR_MANGLER')
    return by


def _laest(s: dict, felt: str) -> Any:
    v = s.get(felt)
    if felt == 'slaegtled':
        return v if isinstance(v, int) and not isinstance(v, bool) else None
    return _norm_gruppe(v) if felt == 'gruppe' else _norm_nr(v)


def vurder(card: dict, s: dict) -> str:
    """enig | uenig | ulaeselig | ingen_anden (kortet har ingen anden læsning for et felt)."""
    if 'beskrivelse' in card['forventet']:
        return 'ingen_anden'                       # briefen beder ikke modellen om gruppebeskrivelser
    if not s.get('fundet') or s.get('sikkerhed') not in SIKKERHED or s.get('sikkerhed') == 'lav':
        return 'ulaeselig'
    if any(v is None for v in card['forventet'].values()):
        return 'ingen_anden'
    for felt, v in card['forventet'].items():
        laest = _laest(s, felt)
        if laest is None:
            return 'ulaeselig'
        if laest != (_norm_gruppe(v) if felt == 'gruppe' else _norm_nr(v) if felt == 'nr' else v):
            return 'uenig'
    return 'enig'


def vurderinger(cards: list[dict], svar: list[dict]) -> dict[str, str]:
    by = _svar_map(svar, cards)
    return {c['kort_id']: vurder(c, by[c['kort_id']]) for c in cards}


def v_poster(cards: list[dict], vd: dict[str, str], seed: int = SEED) -> list[str]:
    enige = [c['kort_id'] for c in cards if c['type'] == 'K' and vd[c['kort_id']] == 'enig']
    rng = random.Random(seed + 1)
    valgt = rng.sample(enige, min(V_ANTAL, len(enige)))
    return [x for x in enige if x in valgt]


U_RE = re.compile(r'^U (?P<id>\S+) : ?(?P<tok>.*)$')
V_RE = re.compile(r'^V (?P<id>\S+) : ?(?P<tok>.*)$')
TOKEN_FORM = {'K': re.compile(r'^\d+ ([IVXLC]+|-)$'), 'GK': re.compile(r'^([IVXLC]+|\d+|J|N)$'),
              'SK': re.compile(r'^(\d+[a-z]?|N)$'), 'SG': re.compile(r'^(\d+|N)$'), 'NK': re.compile(r'^[JN]$'),
              'V': re.compile(r'^[JN]$')}


def forslag(card: dict, s: dict) -> tuple[str, str] | None:
    """Forudfyldt svar på et undtagelseskort (token, begrundelse) eller None (projektejeren skal svare).
    Strukturkort placeres ikke i 6d-1, når modellen ikke læste et almindeligt nummer (unummereret post, fx en
    stammeperson uden nummer; oversigtspunkterne er taget ud af oversigtszonerne) eller læste en anden
    gruppe/slægtled end de fundne nærmeste overskrifter (overskriften mangler i Calamari; posten ville miste den)."""
    if card['type'] != 'SK':
        return None
    nr = _norm_nr(s.get('nr'))
    if nr in (None, '-') or not NR_RE.match(nr):
        return 'N', 'unummereret post — kan ikke placeres uden trykt nummer i 6d-1 (Gate A; opfølgning)'
    return 'N', 'står under en overskrift, som mangler i Calamari — ville miste sin gruppe/sit slægtled (opfølgning)'


def render_token(cards: list[dict], vd: dict[str, str], svar: list[dict] | None = None, seed: int = SEED) -> str:
    by = _svar_map(svar, cards) if svar is not None else {}
    out = ['# ============ 6d-1 KORT 1939: UNDTAGELSER OG KONTROL ============',
           '# Besvares i HTML-siden ved siden af; `flet` skriver svarene her. Alt med »#« er information. Svarformer:',
           '#   U K:…  <slægtled> <romertal|->   (det, der står i bogen; afviger det fra maskinen, stopper kørslen)',
           '#   U GK:… værdien fra siden (romertal / slægtledstal) eller N = lad posterne stå uafklarede',
           '#   U SK:… postens trykte nummer (posten står under de viste overskrifter) eller N',
           '#   U SG:… slægtleddet som tal eller N        U NK:… J = nummeret står sådan i bogen · N',
           '#   V …    J = maskinens slægtled og gruppe passer med PDF\'en · N = afviger (stopper kørslen)']
    us = [c for c in cards if vd[c['kort_id']] != 'enig']
    out.append(f'# {len(us)} undtagelser')
    for c in us:
        f = forslag(c, by[c['kort_id']]) if by else None
        if f:
            out.append(f"# {c['kort_id']}: forudfyldt {f[0]} — {f[1]}")
            out.append(f"U {c['kort_id']} : {f[0]}")
        else:
            out.append(f"U {c['kort_id']} : ")
    vs = v_poster(cards, vd, seed)
    out.append(f'# {len(vs)} stikprøvekontroller af modellens enige svar')
    out += [f'V {x} : ' for x in vs]
    return '\n'.join(out) + '\n'


def _img(jobdir: Path, side: int) -> str:
    return (jobdir / 'sider' / f'side-{side:03d}.png').as_uri()


def _placering(f: dict) -> str:
    dele = []
    if 'slaegtled' in f:
        dele.append('slægtled ' + ('?' if f['slaegtled'] is None else str(f['slaegtled'])))
    if 'gruppe' in f:
        g = f['gruppe']
        dele.append('ingen gruppe-romertal' if g == '-' else ('gruppe ?' if g is None else f'gruppe {g}'))
    if 'nr' in f:
        dele.append('nummer ' + ('?' if f['nr'] is None else str(f['nr'])))
    return ', '.join(dele)


def _spoergsmaal(c: dict, art: str, o: dict) -> dict:
    """Kortets spørgsmål i klart sprog og svarmulighederne (knapper → token)."""
    f = c['forventet']
    find = f"Find posten på PDF-side {o['side']}, der begynder »{o['start_tekst'][:60]}…«."
    if art == 'V':
        return {'tekst': f"{find} Står den i bogen sådan: {_placering(f)}?",
                'hjaelp': 'Slægtled = nærmeste »N. Slægtled« over posten (i fællesstammen: romertallet over afsnittet). '
                          'Gruppe = romertallet over posten inden for slægtleddet.',
                'knapper': [['J', 'Ja, det passer'], ['N', 'Nej, det afviger']], 'felt': None}
    if c['type'] == 'K':
        return {'tekst': f"{find} Maskinen har placeret den: {_placering(f)}. Passer det med bogen?",
                'hjaelp': 'Modellen kunne ikke afgøre det sikkert (se dens note). Svarer du nej, skriv hvad der står; '
                          'en afvigelse stopper kørslen og sendes tilbage til scanneren.',
                'knapper': [[f"{f['slaegtled']} {f['gruppe']}", 'Ja, det passer']],
                'felt': {'label': 'Nej — det der står: slægtled og romertal (fx »6 -« eller »5 II«)', 'form': 'K'}}
    if c['type'] == 'GK' and 'beskrivelse' in f:
        besk = f['beskrivelse'].replace('-', ' ')
        return {'tekst': f"{find} Står den under gruppebeskrivelsen »{besk}« (fællesstammens gruppe uden romertal)?",
                'hjaelp': 'Ja godkender gruppen for alle kortets poster; nej lader dem stå uafklarede.',
                'knapper': [['J', 'Ja'], ['N', 'Nej / kan ikke se det']], 'felt': None}
    if c['type'] == 'GK':
        v = next(iter(f.values()))
        hvad = 'gruppe-romertal' if c['niveau'] == 'kuld' else 'slægtled'
        return {'tekst': f"{find} Står den under {hvad} {v}?",
                'hjaelp': 'Ja godkender overskriften for alle kortets poster; nej lader dem stå uafklarede.',
                'knapper': [[str(v), 'Ja'], ['N', 'Nej / kan ikke se det']], 'felt': None}
    if c['type'] == 'SK':
        return {'tekst': f"{find} Skal posten placeres i 6d-1? Nærmeste fundne overskrifter: {_placering(f)}.",
                'hjaelp': 'Forudfyldt »ingen placering« (se begrundelsen). Skift kun, hvis posten faktisk står under '
                          'de viste overskrifter med et almindeligt nummer.',
                'knapper': [['N', 'Ingen placering (forudfyldt)']],
                'felt': {'label': 'Placér med postens trykte nummer', 'form': 'SK'}}
    if c['type'] == 'NK':
        return {'tekst': f"{find} Har den det trykte nummer {f['nr']}?",
                'hjaelp': 'Guiden har et spring i nummereringen her.', 'knapper': [['J', 'Ja'], ['N', 'Nej']], 'felt': None}
    return {'tekst': f"{find} Står den i slægtled {f.get('slaegtled')}?", 'hjaelp': '',
            'knapper': [[str(f.get('slaegtled')), 'Ja'], ['N', 'Nej']], 'felt': None}


HTML_TPL = r"""<!doctype html><html lang="da"><head><meta charset="utf-8"><title>6d-1 kort 1939</title>
<meta name="viewport" content="width=device-width, initial-scale=1"><style>
:root{--bg:#fff;--fg:#1d1d1f;--mut:#666;--box:#f4f4f6;--acc:#1f5fbf;--ok:#1d7a3a;--line:#ddd}
@media (prefers-color-scheme: dark){:root{--bg:#161618;--fg:#eee;--mut:#aaa;--box:#232327;--acc:#7fb0ff;--ok:#6fd08c;--line:#333}}
body{background:var(--bg);color:var(--fg);font:16px/1.45 system-ui,sans-serif;margin:0 auto;max-width:1150px;padding:16px}
header{position:sticky;top:0;background:var(--bg);padding:8px 0;border-bottom:1px solid var(--line);z-index:2;display:flex;gap:12px;align-items:center;flex-wrap:wrap}
.q{font-size:19px;font-weight:600;margin:10px 0}.h{color:var(--mut);font-size:14px}.box{background:var(--box);border-radius:8px;padding:10px 12px;margin:8px 0}
button{font:inherit;padding:7px 12px;border-radius:7px;border:1px solid var(--line);background:var(--box);color:var(--fg);cursor:pointer;margin:3px}
button.valgt{background:var(--acc);color:#fff;border-color:var(--acc)}input{font:inherit;padding:6px;border-radius:6px;border:1px solid var(--line);background:var(--bg);color:var(--fg);width:9em}
img{max-width:100%;border:1px solid var(--line);margin:4px 0}.svar{color:var(--ok);font-weight:600}code{background:var(--box);padding:1px 4px;border-radius:4px}
</style></head><body>
<header><b>6d-1 kort 1939</b><span id="pos"></span><span id="frem" class="h"></span>
<button onclick="gaa(-1)">← Forrige</button><button onclick="gaa(1)">Næste →</button><button onclick="naeste()">Næste ubesvarede</button>
<button onclick="gem()"><b>Gem svar</b></button></header><main id="kort"></main>
<p class="h">Taster: ← → bladrer · 1/2 vælger knap · svarene gemmes i browseren, og »Gem svar« henter filen <code>kort-svar.json</code> til Overførsler.</p>
<script>
const DATA=/*__DATA__*/null; const KEY='6d1-kort-'+DATA.token_sha256; let svar={}, i=0;
try{svar=JSON.parse(localStorage.getItem(KEY)||'{}')||{}}catch(e){svar={}}
for(const k of DATA.kort){if(!(k.linje in svar)&&k.forudfyldt)svar[k.linje]=k.forudfyldt}
function husk(){try{localStorage.setItem(KEY,JSON.stringify(svar))}catch(e){}}
function esc(s){return String(s??'').replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]))}
function saet(t){svar[DATA.kort[i].linje]=t;husk();tegn()}
function gaa(d){i=Math.max(0,Math.min(DATA.kort.length-1,i+d));tegn();scrollTo(0,0)}
function naeste(){for(let j=1;j<=DATA.kort.length;j++){const n=(i+j)%DATA.kort.length;if(!svar[DATA.kort[n].linje]){i=n;tegn();scrollTo(0,0);return}}alert('Alle kort er besvaret — tryk »Gem svar«.')}
function felt(){const k=DATA.kort[i],v=document.getElementById('fv').value.trim();const re=new RegExp(k.sp.felt.re);if(!re.test(v)){alert('Formen passer ikke: '+k.sp.felt.label);return}saet(v)}
function tegn(){const k=DATA.kort[i],m=k.model,a=svar[k.linje]||'';let h='';
 h+=`<div class="h">${esc(k.art==='V'?'Kontrol af en enig stikprøve':'Undtagelse')} · ${esc(k.kort_id)} · ${k.poster} post(er)</div>`;
 h+=`<div class="q">${esc(k.sp.tekst)}</div><div class="h">${esc(k.sp.hjaelp)}</div>`;
 if(k.begrundelse)h+=`<div class="box">Forslag: ${esc(k.begrundelse)}</div>`;
 h+='<div>'+k.sp.knapper.map((b,n)=>`<button class="${a===b[0]?'valgt':''}" onclick="saet('${esc(b[0])}')">${n+1}. ${esc(b[1])}</button>`).join('');
 if(k.sp.felt)h+=` <span>${esc(k.sp.felt.label)}: <input id="fv" value="${esc(k.sp.knapper.some(b=>b[0]===a)?'':a)}"> <button onclick="felt()">Brug</button></span>`;
 h+='</div>'+(a?`<div>Dit svar: <span class="svar">${esc(a)}</span></div>`:'<div class="h">Ikke besvaret</div>');
 h+=`<div class="box"><b>Modellen læste</b> (sikkerhed ${esc(m.sikkerhed)}): slægtled ${esc(m.slaegtled??'?')}, gruppe ${esc(m.gruppe??'?')}, nummer ${esc(m.nr??'?')}`;
 for(const [f,l] of [['slaegtled_linje','slægtledslinje'],['gruppe_linje','gruppelinje'],['nr_linje','postens linje'],['note','note']])if(m[f])h+=`<br><span class="h">${l}:</span> ${esc(m[f])}`;
 h+='</div>';
 k.sider.forEach((s,n)=>{h+=`<div class="h">PDF-side ${s}</div><img loading="lazy" src="${esc(k.uris[n])}">`});
 document.getElementById('kort').innerHTML=h;
 document.getElementById('pos').textContent=`Kort ${i+1}/${DATA.kort.length}`;
 document.getElementById('frem').textContent=`${DATA.kort.filter(x=>svar[x.linje]).length} besvaret`}
function gem(){const mangler=DATA.kort.filter(x=>!svar[x.linje]).length;if(mangler&&!confirm(mangler+' kort er ikke besvaret. Gem alligevel?'))return;
 const b=new Blob([JSON.stringify({token_sha256:DATA.token_sha256,svar},null,1)],{type:'application/json'});
 const u=URL.createObjectURL(b),l=document.createElement('a');l.href=u;l.download='kort-svar.json';document.body.appendChild(l);l.click();l.remove()}
document.addEventListener('keydown',e=>{if(e.target.tagName==='INPUT'){if(e.key==='Enter')felt();return}
 if(e.key==='ArrowRight')gaa(1);else if(e.key==='ArrowLeft')gaa(-1);else if(/^[1-9]$/.test(e.key)){const b=DATA.kort[i].sp.knapper[+e.key-1];if(b)saet(b[0])}});
tegn();
</script></body></html>
"""


def render_html(cards: list[dict], vd: dict[str, str], svar: list[dict], ops: list[dict], jobdir: Path,
                token_text: str, seed: int = SEED) -> str:
    """Interaktiv lokal side: ét kort ad gangen med et eksplicit spørgsmål og svarknapper; »Gem svar« henter en
    JSON, som `flet` skriver ind i token-filen (bundet til token-filens sha)."""
    by = _svar_map(svar, cards)
    op = {o['kort_id']: o for o in ops}
    pre = {m['id']: m['tok'].strip() for m in (U_RE.match(l) for l in token_text.splitlines()) if m and m['tok'].strip()}
    grund = {mm[1]: mm[2] for mm in (re.match(r'^# (\S+): forudfyldt \S+ — (.*)$', l) for l in token_text.splitlines()) if mm}
    vs = v_poster(cards, vd, seed)
    rows = [('U', c) for c in cards if vd[c['kort_id']] != 'enig'] + [('V', c) for c in cards if c['kort_id'] in vs]
    data = []
    for art, c in rows:
        o, s = op[c['kort_id']], by[c['kort_id']]
        sp = _spoergsmaal(c, art, o)
        if sp['felt']:
            sp['felt']['re'] = TOKEN_FORM[sp['felt']['form']].pattern
        sider = [x for x in range(o['side'] - 2, o['side'] + 1) if (jobdir / 'sider' / f'side-{x:03d}.png').exists()]
        data.append({'linje': f"{art} {c['kort_id']}", 'art': art, 'kort_id': c['kort_id'], 'poster': len(c['poster']),
                     'sp': sp, 'forudfyldt': pre.get(c['kort_id']) if art == 'U' else None,
                     'begrundelse': grund.get(c['kort_id']) if art == 'U' else None,
                     'model': {k: s.get(k) for k in ('slaegtled', 'gruppe', 'nr', 'sikkerhed', 'slaegtled_linje',
                                                     'gruppe_linje', 'nr_linje', 'note')},
                     'sider': sider, 'uris': [_img(jobdir, x) for x in sider]})
    payload = {'token_sha256': _sha(token_text.encode('utf-8')), 'kort': data}
    return HTML_TPL.replace('/*__DATA__*/null', json.dumps(payload, ensure_ascii=False).replace('</', '<\\/'))


def flet(token_text: str, svar_json: dict, cards: list[dict]) -> str:
    """Skriver HTML-sidens svar ind i token-filen: kun tokens på U-/V-linjerne ændres, og kun i den form, linjens
    korttype tillader; svarfilen skal høre til netop denne token-fil."""
    if svar_json.get('token_sha256') != _sha(token_text.encode('utf-8')):
        raise SheetError('KORT_SVAR_ANDEN_TOKENFIL')
    sv = svar_json.get('svar') or {}
    typ = {c['kort_id']: c['type'] for c in cards}
    lines = token_text.split('\n')
    seen = set()
    for n, line in enumerate(lines):
        m = U_RE.match(line) or V_RE.match(line)
        if not m:
            continue
        key = f"{line[0]} {m['id']}"
        seen.add(key)
        tok = str(sv.get(key, '')).strip()
        if not tok:
            raise SheetError(f'SHEET_UNANSWERED {key}')
        form = TOKEN_FORM['V' if line[0] == 'V' else typ[m['id']]]
        if not form.match(tok):
            raise SheetError(f'SHEET_TOKEN_NOT_ALLOWED {key}')
        lines[n] = f"{line[0]} {m['id']} : {tok}"
    if set(sv) - seen:
        raise SheetError('KORT_SVAR_UKENDT')
    return '\n'.join(lines)


# --- approvals ---------------------------------------------------------------------------------------------------

def _parse_token(text: str, cards: list[dict], vd: dict[str, str], seed: int = SEED) -> tuple[dict, dict]:
    want_u = {c['kort_id'] for c in cards if vd[c['kort_id']] != 'enig'}
    want_v = set(v_poster(cards, vd, seed))
    u: dict[str, str] = {}
    v: dict[str, str] = {}
    for raw in text.splitlines():
        if raw.startswith('#') or not raw.strip():
            continue
        mu, mv = U_RE.match(raw), V_RE.match(raw)
        if mu and mu['id'] in want_u and mu['id'] not in u:
            u[mu['id']] = mu['tok'].strip()
        elif mv and mv['id'] in want_v and mv['id'] not in v:
            v[mv['id']] = mv['tok'].strip()
        else:
            raise SheetError('SHEET_LINE_INVALID')
    if set(u) != want_u or set(v) != want_v:
        raise SheetError('SHEET_LINES_MISSING')
    if any(not t for t in [*u.values(), *v.values()]):
        raise SheetError('SHEET_UNANSWERED')
    return u, v


def _human(card: dict, tok: str) -> Any:
    """Projektejerens svar på et undtagelseskort → godkendt værdi eller None (N). Stopper ved en ugyldig form, ved en
    afvigelse i stikprøven og ved en værdi, 6d-1 ikke kan skrive (≠ guiden/maskinen)."""
    t, f = card['type'], card['forventet']
    if t == 'K':
        mm = re.match(r'^(\d+) ([IVXLC]+|-)$', tok)
        if not mm:
            raise SheetError('SHEET_TOKEN_NOT_ALLOWED')
        if int(mm[1]) != f['slaegtled'] or mm[2] != _norm_gruppe(f['gruppe']):
            raise SheetError(f"KONTROL_AFVIGELSE {card['kort_id']}")
        return True
    if tok == 'N':
        return None
    if t == 'NK':
        if tok != 'J':
            raise SheetError('SHEET_TOKEN_NOT_ALLOWED')
        return True
    if t == 'SK':
        if not NR_RE.match(tok.lower()):
            raise SheetError('SHEET_TOKEN_NOT_ALLOWED')
        return tok.lower()
    if t == 'SG':
        if not tok.isdigit():
            raise SheetError('SHEET_TOKEN_NOT_ALLOWED')
        if int(tok) != f['slaegtled']:
            raise SheetError(f"KORT_ANDEN_VAERDI {card['kort_id']} (skriv N: 6d-1 kan kun bekræfte)")
        return True
    if t == 'GK' and 'beskrivelse' in f:
        if tok != 'J':
            raise SheetError(f"KORT_ANDEN_VAERDI {card['kort_id']} (svar J eller N)")
        return True
    if t == 'GK':
        val = int(tok) if card['niveau'] == 'slaegtled' and tok.isdigit() else _norm_gruppe(tok)
        if val is None or str(val) != str(next(iter(f.values()))):
            raise SheetError(f"KORT_ANDEN_VAERDI {card['kort_id']} (skriv N: 6d-1 kan kun bekræfte guidens værdi)")
        return True
    raise SheetError('SHEET_TOKEN_NOT_ALLOWED')


def approvals_1939(m: dict, cards: list[dict], svar: list[dict], token_text: str, *, manifest_sha256: str,
                   kontrol: dict, seed: int = SEED) -> dict:
    vd = vurderinger(cards, svar)
    by_svar = _svar_map(svar, cards)
    u, v = _parse_token(token_text, cards, vd, seed)
    for kid, tok in v.items():
        if tok == 'N':
            raise SheetError(f'KONTROL_AFVIGELSE {kid}')
        if tok != 'J':
            raise SheetError('SHEET_TOKEN_NOT_ALLOWED')
    # Afgørelse pr. kort: (værdi, læser); værdi None = ikke godkendt.
    afg: dict[str, tuple[Any, str]] = {}
    for c in cards:
        kid = c['kort_id']
        if vd[kid] == 'enig':
            val = _norm_nr(by_svar[kid]['nr']) if c['type'] == 'SK' else True
            afg[kid] = (val, 'model')
        else:
            afg[kid] = (_human(c, u[kid]), 'human')
    gk = {c['gk_id']: c for c in cards if c['type'] == 'GK'}
    gruppekort = [{'id': gid, 'value': next(iter(c['forventet'].values())),
                   'reviewer': afg[c['kort_id']][1]}
                  for gid, c in gk.items() if afg[c['kort_id']][0] is not None]
    ok_gk = {g['id'] for g in gruppekort}
    rec_kort: dict[str, dict[str, str]] = {}
    for c in cards:
        if c['type'] in ('SK', 'SG', 'NK'):
            for key in c['poster']:
                rec_kort.setdefault(key, {})[c['type']] = c['kort_id']
    appr = []
    for p in sorted(m['placements'], key=lambda q: q['record_key']):
        if p['status'] != 'unresolved' or p['record_kind'] in IKKE_PLACERBAR:
            continue
        o = {r.split(':', 1)[1] for r in p['reasons'] if r.startswith('overskrift_ikke_fundet:')}
        r = [x for x in p['reasons'] if not x.startswith('overskrift_ikke_fundet:')]
        if not r:
            continue                                   # kun gruppekort: ingen record-godkendelse
        if o - {c['niveau'] for c in p.get('gruppekort') or [] if c['id'] in ok_gk}:
            continue
        need = set()
        for reason in r:
            if reason in STRUKTUR:
                need.add('SK')
            elif reason == 'stamme_generation_usikker':
                need.add('SG')
            elif reason == 'nr_ikke_fortloebende':
                need.add('NK')
            else:
                need.add('-')                          # ikke godkendelig her
        mine = rec_kort.get(p['record_key'], {})
        if '-' in need or need - set(mine) or any(afg[mine[t]][0] is None for t in need):
            continue
        readers = {afg[mine[t]][1] for t in need}
        entry: dict[str, Any] = {'record_key': p['record_key'], 'reviewer': 'model' if readers == {'model'} else 'human'}
        if 'SK' in need:
            entry['printed_number'] = afg[mine['SK']][0]
        appr.append(entry)
    _check_unik(m, appr, gruppekort)
    return {'manifest_sha256': manifest_sha256, 'approvals': appr, 'gruppekort': gruppekort, 'kontrol': kontrol}


def _check_unik(m: dict, appr: list[dict], gruppekort: list[dict]) -> None:
    """Som ceremoniens PLC_PRE_UNIK: højst én post pr. (gren, slægtled, gruppe, nummer) over alt, der skrives."""
    gv = {g['id']: g['value'] for g in gruppekort}
    ap = {a['record_key']: a for a in appr}
    seen: dict[tuple, str] = {}
    for p in m['placements']:
        a = ap.get(p['record_key'])
        if p['status'] == 'machine_ok':
            key = (p['entry_code'], p['generation_local'], p['kuld_label'], p['printed_number'])
        elif a is not None and a.get('printed_number') is not None:
            key = (p.get('naermeste_entry_code'), p.get('naermeste_generation_local'), p.get('naermeste_kuld_label'),
                   a['printed_number'])
        elif a is not None or (p['status'] == 'unresolved' and p.get('gruppekort')
                               and all(c['id'] in gv for c in p['gruppekort'])
                               and all(x.startswith('overskrift_ikke_fundet:') for x in p['reasons'])):
            vals = {'kuld': p['kuld_label'], 'slaegtled': p['generation_local']}
            for c in p.get('gruppekort') or []:
                if c['id'] in gv:
                    vals[c['niveau']] = gv[c['id']]
            key = (p['entry_code'], vals['slaegtled'], vals['kuld'], p['printed_number'])
        else:
            continue
        key = tuple(None if x is None else str(x) for x in key)
        if key in seen:
            raise SheetError(f"KORT_UNIK {seen[key]} {p['record_key']}")
        seen[key] = p['record_key']


# --- CLI ---------------------------------------------------------------------------------------------------------

def _load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding='utf-8'))


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)
    j = sub.add_parser('job')
    u = sub.add_parser('undtagelser')
    a = sub.add_parser('approvals')
    for x in (j, u, a):
        x.add_argument('--manifest', required=True)
        x.add_argument('--jobdir', required=True)
        x.add_argument('--private-root', default=str(Path.home() / '.private'))
        x.add_argument('--k', type=int, default=20)
        x.add_argument('--seed', type=int, default=SEED)
    j.add_argument('--records-json', required=True)
    j.add_argument('--rendition-text', required=True)
    j.add_argument('--pdf')
    for x in (u, a):
        x.add_argument('--svar', required=True)
    u.add_argument('--out-token', required=True)
    u.add_argument('--out-html', required=True)
    u.add_argument('--pdf')
    f = sub.add_parser('flet')
    f.add_argument('--manifest', required=True)
    f.add_argument('--jobdir', required=True)
    f.add_argument('--private-root', default=str(Path.home() / '.private'))
    f.add_argument('--k', type=int, default=20)
    f.add_argument('--seed', type=int, default=SEED)
    f.add_argument('--token', required=True)
    f.add_argument('--html-svar', required=True)
    a.add_argument('--token', required=True)
    a.add_argument('--approved-token-sha256', required=True)
    a.add_argument('--model', required=True)
    a.add_argument('--out', required=True)
    args = ap.parse_args(argv)
    root = Path(args.private_root)
    try:
        mpath = check_private_path(Path(args.manifest), root)
        m = _load_json(mpath)
        jobdir = _check_jobdir(Path(args.jobdir), root)
        if args.cmd == 'job':
            records = _load_json(check_private_path(Path(args.records_json), root))['records']
            rendition = Path(args.rendition_text).read_text(encoding='utf-8')
            res = build_job(m, records, rendition, Path(args.pdf) if args.pdf else None, jobdir, args.k, args.seed)
            print('JOB_OK ' + ' '.join(f'{k}={v}' for k, v in res.items() if k != 'pr_type')
                  + ' ' + ' '.join(f'{t}={n}' for t, n in res['pr_type'].items()))
            return 0
        cards = kort_1939(m, args.k, args.seed)
        if args.cmd == 'flet':
            tpath = check_private_path(Path(args.token), root)
            ud = flet(tpath.read_text(encoding='utf-8'), _load_json(Path(args.html_svar)), cards)
            _write_private(tpath, ud)
            print(f"FLET_OK token_sha256={_sha(ud.encode('utf-8'))}")
            return 0
        svar_b = Path(args.svar).read_bytes()
        svar = json.loads(svar_b.decode('utf-8'))
        vd = vurderinger(cards, svar)
        if args.cmd == 'undtagelser':
            ops = _load_json(jobdir / 'opslag.json')
            if args.pdf:
                render_pages(Path(args.pdf), sorted({x for o in ops for x in range(o['side'] - 2, o['side'] + 1)
                                                     if x >= 1}), jobdir / 'sider')
            tok = render_token(cards, vd, svar, args.seed)
            _write_private(check_private_path(Path(args.out_token), root), tok)
            _write_private(check_private_path(Path(args.out_html), root),
                           render_html(cards, vd, svar, ops, jobdir, tok, args.seed))
            c = {k: list(vd.values()).count(k) for k in ('enig', 'uenig', 'ulaeselig', 'ingen_anden')}
            print('UNDTAGELSER_OK ' + ' '.join(f'{k}={v}' for k, v in c.items())
                  + f' kontrol={len(v_poster(cards, vd, args.seed))} token_sha256={_sha(tok.encode("utf-8"))}')
            return 0
        tb = check_private_path(Path(args.token), root).read_bytes()
        if _sha(tb) != args.approved_token_sha256:
            raise SheetError('SHEET_SHA_MISMATCH')
        kontrol = {'model': args.model, 'brief_sha256': _sha(BRIEF.encode('utf-8')), 'svar_sha256': _sha(svar_b),
                   'token_sha256': _sha(tb), 'opslag_sha256': _sha((jobdir / 'opslag.json').read_bytes())}
        res = approvals_1939(m, cards, svar, tb.decode('utf-8'), manifest_sha256=_sha(mpath.read_bytes()),
                             kontrol=kontrol, seed=args.seed)
        _write_private(check_private_path(Path(args.out), root), json.dumps(res, ensure_ascii=False, sort_keys=True) + '\n')
    except SheetError as exc:
        print(str(exc))
        return 1
    print(f"APPROVALS_OK godkendelser={len(res['approvals'])} gruppekort={len(res['gruppekort'])} "
          f"model={sum(x['reviewer'] == 'model' for x in res['approvals'] + res['gruppekort'])}")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
