#!/usr/bin/env python3
"""Segmentér DAA-stamtavle (rå tekst) i enkelt-poster.

Input:  raw.txt fra extract_text.sh (med ### PAGE n ###-markører).
Output: JSON-array, én record per nummereret post:
  { linje, nr, kuld, slaegtled, aegteskab_kontekst, sider, raw_text }

Struktur i bogen (vigtigt):
  * Løbenummeret (nr) er GLOBALT — løber sammenhængende gennem hele stamtavlen
    på tværs af grene. Det er den primære identitet.
  * "linje" er gren-labelen (romertal I-V), sat af en gren-header som
    "I" + "DEN HOLSTENSKE LINJE". Et romertal er KUN en linje hvis næste
    betydende linje er en "DEN … LINJE"-header.
  * Fritstående romertal der IKKE efterfølges af en gren-header er KULD-markører
    (hvilken forælders børn der nu følger), typisk lige før "af X ægteskab med Y:".
    De ændrer IKKE linje — de gemmes som `kuld`.

Deterministisk. Edition-følsom: justér regexerne ved en ny udgave. Kvalitets-
rapporten (stderr) flagger manglende linje-kontekst og huller/dubletter i nr.
"""
import sys, re, json

PAGE_RE    = re.compile(r'^###\s*PAGE\s+(\d+)\s*###\s*$')
# Ægte post-start: løbenummer + ≥2 mellemrum (kolonne-justeret i -layout).
# Skelner "1.  Gottschalk" (post) fra ombrudt "1. af Holstens…" ("Gerhard 1.").
POST_RE    = re.compile(r'^\s*(\d{1,4})\.\s{2,}(\S.*)$')
ROMAN_RE   = re.compile(r'^\s*([IVX]{1,5})\s*$')
LINJE_NAME = re.compile(r'DEN\s+\S.*LINJE', re.I)             # gren-header
SLGT_RE    = re.compile(r'^\s*(\w+)\s+slægtled\s*$', re.I)
MARR_RE    = re.compile(r'^\s*((?:af [\w ]+ ægteskab )?med .+):\s*$', re.I)
NOISE_RE   = re.compile(r'^\s*(von\s+R\s*E.*|Ridder\s+.+sønner)\s*$', re.I)


def norm(s):
    return re.sub(r'\s+', ' ', s).strip()


def flush(posts, cur):
    if cur and cur.get('_lines'):
        cur['sider'] = (str(cur['_pages'][0]) if cur['_pages'][0] == cur['_pages'][-1]
                        else f"{cur['_pages'][0]}-{cur['_pages'][-1]}")
        cur['raw_text'] = norm(' '.join(cur.pop('_lines')))
        cur.pop('_pages')
        posts.append(cur)


def significant(lines, k):
    """Indeks for første betydende linje fra k (spring blanke/støj/page over)."""
    while k < len(lines):
        ln = lines[k]
        if not (PAGE_RE.match(ln) or not ln.strip() or NOISE_RE.match(ln)
                or LINJE_NAME.search(ln)):
            return k
        k += 1
    return None


def main(path):
    lines = open(path, encoding='utf-8', errors='replace').read().splitlines()
    linje = slaegtled = marr = kuld = page = cur = None
    posts = []
    i = 0
    while i < len(lines):
        line = lines[i]

        m = PAGE_RE.match(line)
        if m:
            page = int(m.group(1))
            if cur:
                cur['_pages'].append(page)
            i += 1; continue

        if not line.strip() or NOISE_RE.match(line):
            i += 1; continue

        if LINJE_NAME.search(line):          # gren-header uden forudgående romertal
            flush(posts, cur); cur = None
            slaegtled = marr = kuld = None
            i += 1; continue

        m = ROMAN_RE.match(line)
        if m:
            roman = m.group(1)
            j = significant(lines, i + 1)
            # romertal er en LINJE kun hvis selve header-teksten lige fulgte;
            # ellers er det en kuld-markør (forælder-enumerering)
            nxt = lines[i + 1] if i + 1 < len(lines) else ''
            is_branch = bool(LINJE_NAME.search(nxt)) or (
                j is not None and any(LINJE_NAME.search(lines[k])
                                      for k in range(i + 1, j + 1)))
            flush(posts, cur); cur = None
            if is_branch:
                linje = roman; slaegtled = marr = kuld = None
            else:
                kuld = roman                  # ændrer IKKE linje
            i += 1; continue

        m = SLGT_RE.match(line)
        if m:
            flush(posts, cur); cur = None
            slaegtled = m.group(1); i += 1; continue

        m = MARR_RE.match(line)
        if m:
            flush(posts, cur); cur = None
            marr = norm(m.group(1)); i += 1; continue

        m = POST_RE.match(line)
        if m:
            flush(posts, cur)
            cur = {'linje': linje, 'nr': int(m.group(1)), 'kuld': kuld,
                   'slaegtled': slaegtled, 'aegteskab_kontekst': marr,
                   '_lines': [m.group(2)], '_pages': [page]}
            i += 1; continue

        if cur is not None:
            cur['_lines'].append(line.strip())
        i += 1

    flush(posts, cur)
    json.dump(posts, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write('\n')
    print(f'[segment] {len(posts)} poster', file=sys.stderr)
    _quality_report(posts)


def _quality_report(posts):
    """Fang stille fejl. nr er GLOBALT -> tjek contiguity samlet, ikke per linje."""
    no_linje = [p['nr'] for p in posts if not p['linje']]
    if no_linje:
        print(f'[segment] ADVARSEL: {len(no_linje)} poster uden linje-kontekst '
              f'(gren-header før intervallet?): nr {no_linje}', file=sys.stderr)
    nrs = [p['nr'] for p in posts]
    dupes = sorted({n for n in nrs if nrs.count(n) > 1})
    if dupes:
        print(f'[segment] ADVARSEL: dublet-løbenumre: {dupes}', file=sys.stderr)
    s = sorted(set(nrs))
    if s:
        gaps = [n for n in range(s[0], s[-1] + 1) if n not in set(s)]
        if gaps:
            print(f'[segment] ADVARSEL: hul i løbenumre (droppet post?): mangler {gaps}',
                  file=sys.stderr)


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit('brug: segment.py raw.txt > posts.json')
    main(sys.argv[1])
