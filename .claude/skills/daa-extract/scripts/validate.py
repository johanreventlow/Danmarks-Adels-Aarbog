#!/usr/bin/env python3
"""BLOKERENDE validering af struktureret DAA-udtræk (trin ④).

Brug:
  validate.py posts.json extracted_dir/ --clean clean.json --review review.json

Tjekker reglerne fra docs/daa-extraction-archetype.md §5. En post med ÉT
brud ryger i review.json og loades IKKE. Vi hellere mangler en post end
loader en forkert — narrativen bevarer alligevel det fulde indhold.

Reglerne (kan-tjekkes-deterministisk delmængde):
  R1  hver dato-værdi (date_raw / periode_raw / dato_raw) findes ordret i narrative
  R2  boern.nr_range ligger inden for kendte løbenumre i samme linje
  R3  boern.antal matcher nr_range-bredden
  R4  ægteskabs-ordinaler er strengt stigende (1,2,3...)
  R5  ingen tredjeparts-person oprettet (skema tillader det ikke; ekstra felt = brud)
  R6  narrative findes, er ikke-tom og matcher kilde-postens raw_text
  K   linje/nr i udtræk matcher kilde-posten
"""
import sys, os, re, json, argparse

ALLOWED_TOP = {"linje", "nr", "navn", "tilnavn", "koen", "facts", "godser",
               "embeder", "aegteskaber", "boern", "begivenheder", "narrative"}


def norm(s):
    return re.sub(r'\s+', ' ', (s or '')).strip()


def collect_dates(rec):
    out = []
    for f in rec.get('facts') or []:
        if f.get('date_raw'):
            out.append(f['date_raw'])
    for g in rec.get('godser') or []:
        if g.get('periode_raw'):
            out.append(g['periode_raw'])
    for e in rec.get('embeder') or []:
        if e.get('dato_raw'):
            out.append(e['dato_raw'])
    for b in rec.get('begivenheder') or []:
        if b.get('dato_raw'):
            out.append(b['dato_raw'])
    return out


def validate(rec, src, known_global):
    """Returnér liste af regelbrud (tom = ren).

    Narrativen er IKKE LLM'ens ansvar: den autoritative prosa er kilde-postens
    raw_text fra posts.json. Vi tjekker derfor alt mod kilden, og main() fletter
    raw_text ind i den rene record (LLM'en udtrækker kun struktureret rygrad)."""
    issues = []
    src_text = norm(src['raw_text']) if src else ''

    # K: linje/nr-konsistens
    if src is None:
        issues.append(f'K: ingen kilde-post for linje {rec.get("linje")} nr {rec.get("nr")}')

    # R6: autoritativ narrativ findes (fra kilden, ikke fra LLM)
    if src is not None and not src_text:
        issues.append('R6: kilde-postens raw_text er tom')

    # R1: dato-værdier findes ordret i den autoritative prosa
    hay = src_text
    for d in collect_dates(rec):
        if norm(d) not in hay:
            issues.append(f'R1: dato "{d}" findes ikke ordret i narrative')

    # R4: ægteskabs-ordinaler strengt stigende
    ords = [a.get('ordinal') for a in (rec.get('aegteskaber') or []) if a.get('ordinal') is not None]
    if ords != sorted(set(ords)) or len(ords) != len(set(ords)):
        issues.append(f'R4: ægteskabs-ordinaler ikke strengt stigende: {ords}')

    # R2 + R3: børn-reference. Løbenr er GLOBALT (på tværs af grene), så vi
    # tjekker mod den samlede nr-mængde — ikke per linje. Vi skelner et ÆGTE
    # hul (nr mangler INDEN i det segmenterede vindue = droppet post = blokér)
    # fra uden-for-scope (nr endnu ikke loadet i dette interval = ikke-blokerende;
    # load_daa.R springer manglende barn-refs over via exists()-guard).
    b = rec.get('boern')
    if b and b.get('nr_range'):
        rng = b['nr_range']
        if len(rng) == 2 and rng[0] <= rng[1]:
            lo, hi = min(known_global), max(known_global) if known_global else (0, 0)
            true_gaps = [n for n in range(rng[0], rng[1] + 1)
                         if n not in known_global and lo <= n <= hi]
            if true_gaps:
                issues.append(f'R2: børn-nr mangler inden i segmenteret vindue (droppet post?): {true_gaps}')
            if b.get('antal') is not None and b['antal'] != (rng[1] - rng[0] + 1):
                issues.append(f'R3: antal børn ({b["antal"]}) matcher ikke nr_range {rng}')
        else:
            issues.append(f'R2: ugyldigt nr_range {rng}')

    # R5: ingen ukendte topfelter (tredjeparts-person-oprettelse e.l.)
    extra = set(rec.keys()) - ALLOWED_TOP
    if extra:
        issues.append(f'R5: ukendte/ikke-tilladte felter (mulig tredjeparts-oprettelse): {sorted(extra)}')

    return issues


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('posts')
    ap.add_argument('extracted_dir')
    ap.add_argument('--clean', required=True)
    ap.add_argument('--review', required=True)
    args = ap.parse_args()

    posts = json.load(open(args.posts, encoding='utf-8'))
    src_by_key = {(p['linje'], p['nr']): p for p in posts}
    known_global = {p['nr'] for p in posts}     # løbenr er globalt på tværs af grene

    clean, review = [], []
    files = sorted(f for f in os.listdir(args.extracted_dir) if f.endswith('.json'))
    for fn in files:
        rec = json.load(open(os.path.join(args.extracted_dir, fn), encoding='utf-8'))
        src = src_by_key.get((rec.get('linje'), rec.get('nr')))
        issues = validate(rec, src, known_global)
        if issues:
            review.append({'fil': fn, 'linje': rec.get('linje'), 'nr': rec.get('nr'),
                           'navn': rec.get('navn'), 'brud': issues})
        else:
            # flet den AUTORITATIVE narrativ ind fra kilden (overskriver evt. LLM-narrativ)
            rec['narrative'] = src['raw_text']
            clean.append(rec)

    json.dump(clean, open(args.clean, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
    json.dump(review, open(args.review, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)

    print(f'[validate] {len(clean)} rene, {len(review)} flaggede (kræver review)', file=sys.stderr)
    for r in review:
        print(f'  FLAG linje {r["linje"]} nr {r["nr"]} ({r["navn"]}):', file=sys.stderr)
        for b in r['brud']:
            print(f'      - {b}', file=sys.stderr)
    # exit 0 altid: flagging er normal drift, ikke en scriptfejl


if __name__ == '__main__':
    main()
