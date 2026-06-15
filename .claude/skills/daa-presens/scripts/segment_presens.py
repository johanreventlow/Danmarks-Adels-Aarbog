#!/usr/bin/env python3
"""Grov-segmentér en DAA-præsensliste i GREN-blokke.

Input:  raw.txt fra pdftotext -layout (med ### PAGE n ###-markører).
Output: JSON-array, én record per gren:
  { linje, gren, sider, raw_text }

Modsat stamtavlen segmenterer vi IKKE per person — strukturen er et inline
relations-træ med nesting (a./1)/a)) og slægtskabs-sektioner (SØSTRE, FARFARS
FARBROR …). Den rekonstruktion overlades til LLM'en i trin ③; her giver vi
bare små, veldefinerede blokke (én pr. gren) med linje/gren-kontekst.

Brug:  segment_presens.py raw.txt --family Reventlow > blocks.json
"""
import sys, re, json, argparse

PAGE_RE  = re.compile(r'^###\s*PAGE\s+(\d+)\s*###\s*$')
LINJE_RE = re.compile(r'^\s*([IVX]+)\s+LINJE\s*$')
GREN_RE  = re.compile(r'^\s*(\d+)\.\s*GREN\s*$')


def norm(s):
    return re.sub(r'\s+', ' ', s).strip()


def flush(blocks, cur):
    if cur and cur.get('_lines'):
        cur['sider'] = (str(cur['_pages'][0]) if cur['_pages'][0] == cur['_pages'][-1]
                        else f"{cur['_pages'][0]}-{cur['_pages'][-1]}")
        cur['raw_text'] = norm(' '.join(cur.pop('_lines')))
        cur.pop('_pages')
        blocks.append(cur)


def main(path, family):
    # løbende sidehoved = slægtsnavnet alene (evt. med OCR-mellemrum) -> støj
    fam_key = re.sub(r'\s+', '', family).lower()
    lines = open(path, encoding='utf-8', errors='replace').read().splitlines()
    linje = page = cur = None
    blocks = []

    for line in lines:
        m = PAGE_RE.match(line)
        if m:
            page = int(m.group(1))
            if cur:
                cur['_pages'].append(page)
            continue
        s = line.strip()
        if not s:
            continue
        if s.isdigit():                                   # sidetal
            continue
        if re.sub(r'\s+', '', s).lower() == fam_key:      # løbende slægts-sidehoved
            continue

        # struktur-headers FØR versal-støjfilteret (ellers spiser det "II LINJE")
        if LINJE_RE.match(line):
            linje = LINJE_RE.match(line).group(1)
            continue
        m = GREN_RE.match(line)
        if m:
            flush(blocks, cur)
            cur = {'linje': linje, 'gren': int(m.group(1)),
                   '_lines': [], '_pages': [page]}
            continue

        # NB: slægtskabs-sektions-headers (SØSTRE, FARFARS FARBROR, SØSKENDE) er
        # versaler men BEVARES i blokken — LLM'en bruger dem som slægtskabs-kontekst.
        # Slægtsnavnet REVENTLOW fjernes allerede af family-filteret ovenfor.
        if cur is not None:
            cur['_lines'].append(s)

    flush(blocks, cur)
    json.dump(blocks, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write('\n')
    print(f'[segment_presens] {len(blocks)} gren-blokke', file=sys.stderr)
    if not blocks:
        print('[segment_presens] ADVARSEL: ingen GREN-headers fundet — '
              'tjek sideinterval / OCR af "N. GREN"', file=sys.stderr)


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('raw')
    ap.add_argument('--family', required=True, help='slægtsnavn til at fjerne løbende sidehoved')
    a = ap.parse_args()
    main(a.raw, a.family)
