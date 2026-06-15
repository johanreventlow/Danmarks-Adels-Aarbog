#!/usr/bin/env python3
"""Validering af præsensliste-udtræk (trin ④).

Brug:
  validate_presens.py blocks.json extracted_dir/ --clean clean.json --review review.json

Kilden er OCR'et, så verbatim-dato-match er upålideligt og IKKE blokerende.
Vi fokuserer på STRUKTUR — det er der en svagere model fejler:
  S1  foraelder_lokal_id peger på et eksisterende lokal_id i samme blok
  S2  lokal_id er unikke i blokken
  S3  koen er sat (mand|kvinde|ukendt) og navn er ikke-tom
  S4  ægteskabs-ordinaler er strengt stigende per person
  S5  ingen ukendte topfelter (mulig tredjeparts-oprettelse)
  A1  (ADVISORY) dato_raw findes løst i blokkens raw_text efter OCR-normalisering
"""
import sys, os, re, json, argparse

ALLOWED = {"lokal_id", "foraelder_lokal_id", "relation_til_hoved", "titel",
           "navn", "koen", "foedsel", "doed", "erhverv", "bopael",
           "foraeldre_note", "aegteskaber"}


def ocr_norm(s):
    """Aggressiv normalisering så OCR-støj ikke giver falske dato-mismatch."""
    s = (s or '').lower()
    s = s.replace('†', '').replace(' ', ' ')
    s = re.sub(r'[^\wæøå]', '', s)        # kun alfanumerisk
    return s


def validate_block(blk, ext):
    issues, advisory = [], []
    persons = ext.get('personer') or []
    ids = [p.get('lokal_id') for p in persons]

    # S2: unikke lokal_id
    dupes = sorted({i for i in ids if ids.count(i) > 1})
    if dupes:
        issues.append(f'S2: dublet lokal_id: {dupes}')
    idset = set(ids)

    hay = ocr_norm(blk['raw_text'])
    for p in persons:
        who = p.get('lokal_id', '?')
        # S5: ukendte felter
        extra = set(p.keys()) - ALLOWED
        if extra:
            issues.append(f'S5 [{who}]: ukendte felter {sorted(extra)}')
        # S3: koen + navn
        if p.get('koen') not in ('mand', 'kvinde', 'ukendt'):
            issues.append(f'S3 [{who}]: koen mangler/ugyldig')
        if not (p.get('navn') or '').strip():
            issues.append(f'S3 [{who}]: navn tomt')
        # S1: forælder-link gyldigt
        par = p.get('foraelder_lokal_id')
        if par is not None and par not in idset:
            issues.append(f'S1 [{who}]: foraelder_lokal_id "{par}" findes ikke i blokken')
        # S4: ordinaler stigende
        ords = [a.get('ordinal') for a in (p.get('aegteskaber') or []) if a.get('ordinal') is not None]
        if ords != sorted(set(ords)) or len(ords) != len(set(ords)):
            issues.append(f'S4 [{who}]: ægteskabs-ordinaler ikke strengt stigende: {ords}')
        # A1 (advisory): dato løst i prosaen
        for fld in ('foedsel', 'doed'):
            d = p.get(fld) or {}
            raw = d.get('date_raw') if isinstance(d, dict) else None
            if raw and ocr_norm(raw) and ocr_norm(raw) not in hay:
                advisory.append(f'A1 [{who}]: {fld}.date_raw "{raw}" ikke fundet løst i prosaen (OCR?)')
    return issues, advisory


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('blocks'); ap.add_argument('extracted_dir')
    ap.add_argument('--clean', required=True); ap.add_argument('--review', required=True)
    a = ap.parse_args()

    blocks = {(b['linje'], b['gren']): b for b in json.load(open(a.blocks, encoding='utf-8'))}
    clean, review = [], []
    for fn in sorted(f for f in os.listdir(a.extracted_dir) if f.endswith('.json')):
        ext = json.load(open(os.path.join(a.extracted_dir, fn), encoding='utf-8'))
        blk = blocks.get((ext.get('linje'), ext.get('gren')))
        if blk is None:
            review.append({'fil': fn, 'brud': [f'K: ingen gren-blok for linje {ext.get("linje")} gren {ext.get("gren")}']})
            continue
        issues, advisory = validate_block(blk, ext)
        npers = len(ext.get('personer') or [])
        if issues:
            review.append({'fil': fn, 'gren': ext.get('gren'), 'personer': npers, 'brud': issues, 'advisory': advisory})
        else:
            clean.append(ext)
            if advisory:
                print(f'[validate_presens] gren {ext.get("gren")}: {len(advisory)} advisory (ej-blokerende):', file=sys.stderr)
                for adv in advisory:
                    print(f'      ~ {adv}', file=sys.stderr)

    json.dump(clean, open(a.clean, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
    json.dump(review, open(a.review, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
    npers = sum(len(b.get('personer') or []) for b in clean)
    print(f'[validate_presens] {len(clean)} rene blokke ({npers} personer), {len(review)} flaggede', file=sys.stderr)
    for r in review:
        print(f'  FLAG {r["fil"]}:', file=sys.stderr)
        for b in r['brud']:
            print(f'      - {b}', file=sys.stderr)


if __name__ == '__main__':
    main()
