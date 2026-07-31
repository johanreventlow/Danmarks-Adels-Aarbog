#!/usr/bin/env python3
"""Segmentér DAA-stamtavle (rå tekst) i enkelt-poster.

Input:  raw.txt fra extract_text.sh (med ### PAGE n ###-markører).
Output: JSON-array, én record per nummereret post:
  { linje, nr, kuld, slaegtled, aegteskab_kontekst, sider, raw_text }

Struktur i bogen (vigtigt):
  * Løbenummeret (nr) resetter pr. gren (linje I..V starter hver ved 1). Den unikke nøgle
    er (linje, nr) inden for én kilde — IKKE nr alene.
  * "linje" er gren-labelen (romertal I-V), sat af en gren-header som
    "I" + "DEN HOLSTENSKE LINJE". Et romertal er KUN en linje hvis næste
    betydende linje er en "DEN … LINJE"-header.
  * Fritstående romertal der IKKE efterfølges af en gren-header er KULD-markører
    (hvilken forælders børn der nu følger), typisk lige før "af X ægteskab med Y:".
    De ændrer IKKE linje — de gemmes som `kuld`.

Deterministisk. Edition-følsom: justér regexerne ved en ny udgave. Kvalitets-
rapporten (stderr) flagger manglende linje-kontekst og huller/dubletter i nr.
"""
import contextlib
import io
import sys, re, json
from ordinals import ordinal_to_int

PAGE_RE    = re.compile(r'^###\s*PAGE\s+(\d+)\s*###\s*$')
# Ægte post-start: valgfrit "?"-præfiks (bogens markør for usikkert/formodet
# medlemskab -> konfidens) + løbenummer (+ valgfrit bogstav-suffiks "15a") + ≥2
# mellemrum (kolonne-justeret i -layout). Skelner "1.  Gottschalk" fra ombrudt
# "1. af Holstens…" ("Gerhard 1."). Under-numre 15a./15b. = DISTINKTE personer.
POST_RE    = re.compile(r'^\s*(\?)?\s*(\d{1,4})([a-z]?)\.\s{2,}(\S.*)$')
ROMAN_RE   = re.compile(r'^\s*([IVX]{1,5})\s*$')
# Gren-header = versal-linje der indeholder "LINJE"/"LINJEN". Fanger både
# "DEN HOLSTENSKE LINJE", "DEN LENSGREVELIGE LINJE AF 1767" OG "LINJEN GALLENTIN".
# Krav om VERSALER undgår falsk match på små-bogstavs-krydsref "(se I. Den … linje nr. 29)".
LINJE_NAME = re.compile(r'^[A-ZÆØÅ0-9 .]*\bLINJEN?\b[A-ZÆØÅ0-9 .]*$')
SLGT_RE    = re.compile(r'^\s*(\w+)(?:\s*\((\w+)\))?\s+slægtled\s*$', re.I)
MARR_RE    = re.compile(r'^\s*((?:af [\w ]+ ægteskab )?med .+):[\s\-–—]*$', re.I)
NOISE_RE   = re.compile(r'^\s*(von\s+R\s*E.*|Ridder\s+.+sønner)\s*$', re.I)

# 1939 har en anden typografi og dermed andre sikre grænser. Regexerne bor
# samlet i udgaveprofilen nedenfor; de må ikke "forbedre" 2018-20-matchene.
# NB: bevidst \s{0,2} efter ?-præfikset — et \s* dér åd vilkårlig indrykning
# og gjorde indrykningskravet virkningsløst (indledningens dybt indrykkede
# oversigtslister "1. Geheimeraad D i 11 e v" slap ind som poster).
POST_1939_RE = re.compile(
    r'^\s{0,4}(\??)\s{0,2}(\d{1,3})\s*([a-z]?)\.\s+(\S.*)$',
    re.I | re.UNICODE,
)
SLGT_1939_RE = re.compile(r'^([a-zæøå]+)slægtled[,.]?$', re.I)
# Tolerer OCR-støj omkring romertallet — målt: "' i.", "II. .", "• IV.", "VIL".
AFSNIT_1939_RE = re.compile(r"^\s{10,}[•'‘’\s]*([ivxl]{1,6})[.,]?[\s.]*$", re.I)
# Gruppebeskrivelse ("Einert Carl Detlef Greve Reventlows Børn med …:") — kan
# være ombrudt over op til 3 linjer og er GRUPPEGRÆNSE i sig selv: mindst én
# gruppe (målt: IV.Sjette, s. 571) har INGEN centreret roman i OCR, kun
# beskrivelsen. 'Slægtled' i teksten udelukker (så pegepinde aldrig rammer).
GRUPPEBESKRIVELSE_1939_RE = re.compile(
    r"Reventlows?\s+(?:Børn|Døtre|Sønner|Søn|Datter)\b[^:]*:\s*$", re.I)
# Indledningens centrerede sektionsoverskrifter ("Den ældre meklenborgske
# Linje.") skiller fællesstammens undersektioner, som genbruger romertal.
# Må KUN bruges FØR første blok-linje-header — som generel linje-detektion
# fejlramte formen indledningens prosa (deraf fjernelsen ovenfor).
STAMME_SEKTION_1939_RE = re.compile(
    r'^\s{6,}(?:Den\s+(.{3,40}?)\s+Linje\w*|Linjen\s+(\w+))\.\s*$', re.I)
LINJE_NAMED_1939_RE = re.compile(r'^\s*Linjen\s+(.+?)\.\s*$', re.I)
LINJE_ROMAN_1939_RE = re.compile(r'^\s*([IVXL]+)\s+.+\bLinje\b.*$', re.I)
LINJE_ROMAN_PREFIX_1939_RE = re.compile(r'^\s*([IVXL]+)\s+\S.*$', re.I)
LINJE_WRAPPED_TAIL_1939_RE = re.compile(r'^\s*Linje\b.*$', re.I)
PAGE_NOISE_1939_RE = re.compile(r'^\s*(?:Reventlow\s*\.?|\d{1,4})[\s.•*]*$', re.I)
# Linje-header-blokken (målt: alle 6 linjer, øverst på frisk side):
# centreret romertal (evt. med .,-suffiks; OCR: IL=II) + navnelinje + "(S. nn).".
LINJE_BLOK_ROMAN_1939_RE = re.compile(r'^\s{15,}([IVXL]{1,6})[.,]?\s*$')
LINJE_NAVN_1939_RE = re.compile(r'\bLinjen?\b.*\.\s*$', re.I)
SIDEHENVISNING_1939_RE = re.compile(r'^\s*\(S\.\s*\d+\)\.?\s*$')
UNNUMBERED_1939_RE = re.compile(
    r"^\s{0,4}'?(?:[^\W\d_]|1)(?:\s+(?:[^\W\d_]|1)){1,}",
    re.UNICODE,
)
SPAERRET_NAVN_1939_RE = re.compile(
    r"'?(?:[^\W\d_]|1)(?:\s+(?:[^\W\d_]|1)){1,}",
    re.UNICODE,
)
DATO_FORTSAETTELSE_1939_RE = re.compile(r'^\d+\s+s\.\s*M\.', re.I)
KILDELINJE_1939_RE = re.compile(r': .*S\.\s*\d+\.?\s*$', re.I)
NAVNLOEST_BARN_1939_RE = re.compile(r'^(?:En Søn|en Datter)\b', re.I)
RENT_SPOERGSMAALSTEGN_1939_RE = re.compile(r'^\(\?\)\s*$')
INDLEDNING_OVERSIGT_1939_RE = re.compile(r'^\s*Fra ovennævnte\b', re.I)
UPLACERET_OVERSIGT_1939_RE = re.compile(
    r'^\s*Personer af Navnet Reventlow, der ikke kan anvises Plads\s*$', re.I)
OVERSIGT_NAVN_PREFIX_1939_RE = re.compile(
    r'^\s*(?:(?:[IVXL]+|[A-ZÆØÅ]|\d+)\s*[.)]\s+)?(?P<tekst>.*)$')
UNNUMBERED_NAME_START_1939_RE = re.compile(
    r"(?:[^\W\d_1][ \t]+){3,}[^\W\d_1]",
    re.UNICODE,
)
STAMME_POSITION_1939_RE = re.compile(
    r'^\s{10,}([IVXL1]+)(?:\s*([A-Z]))?\.\s*$', re.I)

ORDINALER_1939 = {
    ordinal: ordinal.capitalize()
    for ordinal in (
        'første', 'andet', 'tredje', 'fjerde', 'femte', 'sjette',
        'syvende', 'ottende', 'niende', 'tiende', 'ellevte', 'tolvte',
    )
}


def norm(s):
    return re.sub(r'\s+', ' ', s).strip()


def flush(posts, cur):
    if cur and cur.get('_lines'):
        cur['sider'] = (str(cur['_pages'][0]) if cur['_pages'][0] == cur['_pages'][-1]
                        else f"{cur['_pages'][0]}-{cur['_pages'][-1]}")
        # Lokator-halvdelen (identitetsregisteret): bogens egen strukturelle
        # adresse. (linje, nr_label) er bogens unikke nøgle (se docstring), så
        # lokal_id er unik pr. udgave — og TRYKT, ikke beregnet: en overset
        # post forskyder ingen naboers identitet. Mangler linje-konteksten
        # sættes None frem for et gæt; R9-gaten blokerer posten nedstrøms.
        cur['lokal_id'] = f"{cur['linje']}.{cur['nr_label']}" if cur.get('linje') else None
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


def _quality_report(posts):
    """Fang stille fejl. nr RESETTER per linje, så contiguity tjekkes PER LINJE
    ((linje,nr) er nøglen, jf. krydsref '(III, 37)')."""
    no_linje = [p['nr'] for p in posts if not p['linje']]
    if no_linje:
        print(f'[segment] ADVARSEL: {len(no_linje)} poster uden linje-kontekst '
              f'(gren-header før intervallet?): nr {no_linje}', file=sys.stderr)
    by_linje = {}
    for p in posts:
        by_linje.setdefault(p['linje'], []).append(p)
    for lin, ps in sorted(by_linje.items(), key=lambda kv: str(kv[0])):
        labels = [p.get('nr_label', str(p['nr'])) for p in ps]
        dupes = sorted({l for l in labels if labels.count(l) > 1})   # 15a≠15b; to rene "15" = dublet
        if dupes:
            print(f'[segment] ADVARSEL: dublet-poster i linje {lin}: {dupes}', file=sys.stderr)
        base = sorted({p['nr'] for p in ps})                          # basenr (15a/15b -> 15)
        gaps = [n for n in range(base[0], base[-1] + 1) if n not in set(base)]
        if gaps:
            print(f'[segment] ADVARSEL: hul i basenr i linje {lin} (droppet post?): mangler {gaps}',
                  file=sys.stderr)
        print(f'[segment] linje {lin}: {len(ps)} poster, basenr {base[0]}-{base[-1]}', file=sys.stderr)


def _segment_2018_20(lines, profile):
    """Den hidtidige state-maskine, holdt isoleret som default-profil."""
    linje = slaegtled = marr = kuld = page = cur = None
    slaegtled_lokal = slaegtled_gennem = None
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
            slaegtled_lokal = slaegtled_gennem = None
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
                slaegtled_lokal = slaegtled_gennem = None
            else:
                kuld = roman                  # ændrer IKKE linje
            i += 1; continue

        m = SLGT_RE.match(line)
        if m:
            flush(posts, cur); cur = None
            slaegtled = m.group(1)
            slaegtled_lokal = ordinal_to_int(m.group(1))
            slaegtled_gennem = ordinal_to_int(m.group(2)) if m.group(2) else None
            i += 1; continue

        m = MARR_RE.match(line)
        if m:
            flush(posts, cur); cur = None
            marr = norm(m.group(1)); i += 1; continue

        m = POST_RE.match(line)
        if m:
            flush(posts, cur)
            cur = {'linje': linje, 'nr': int(m.group(2)), 'nr_label': m.group(2) + m.group(3),
                   'usikker': bool(m.group(1)), 'kuld': kuld, 'slaegtled': slaegtled,
                   'slaegtled_lokal': slaegtled_lokal, 'slaegtled_gennem': slaegtled_gennem,
                   'aegteskab_kontekst': marr, '_lines': [m.group(4)], '_pages': [page]}
            i += 1; continue

        if cur is not None:
            cur['_lines'].append(line.strip())
        i += 1

    flush(posts, cur)
    json.dump(posts, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write('\n')
    print(f'[segment] {len(posts)} poster', file=sys.stderr)
    _quality_report(posts)
    return posts


def _normaliser_romertal_1939(roman, profile):
    """Ret kun dokumenterede OCR-forvekslinger; ingen fri romertalsfortolkning."""
    if roman is None:
        return None
    roman = roman.upper()
    return profile['roman_ocr'].get(roman, roman)


def _linje_header_1939(lines, i, profile):
    """Returnér (kort label, antal linjer) for en selvstændig linje-header.

    Bogens dominerende form (målt: alle 6 linjer, altid øverst på frisk side):

                                  IV.        <- centreret romertal = linjens nummer
        Den danske grevelige Linje af 1673.  <- navnelinje (indryk varierer, ned til 0)
                                (S. 43).     <- sidehenvisning, konsumeres

    Romertallet ER lokatorens linje-led. OCR-varianter: 'I', 'IL' (=II), 'III,',
    'IV.' — tegnsætning varierer og L/I forveksles (samme klasse som IIL->III).
    Denne form SKAL genkendes før afsnit-romanerne, ellers ædes romertallet som
    afsnit og navnelinjen som gruppekontekst.
    """
    line = lines[i]
    m = profile['linje_blok_roman_re'].match(line)
    if m and i + 1 < len(lines):
        naeste = lines[i + 1]
        if profile['linje_navn_re'].search(naeste):
            forbrug = 2
            if i + 2 < len(lines) and profile['sidehenvisning_re'].match(lines[i + 2]):
                forbrug = 3
            return _normaliser_romertal_1939(m.group(1).rstrip('.,'), profile), forbrug
    # Blok-formen er den ENESTE linje-header i 1939 (alle 6 verificeret mod
    # teksten). Løsere én-linjes-former blev fjernet igen: de matchede
    # indledningens PROSA-overskrifter ("Den holstenske Linje." s. 499) og
    # satte linje-state før stamtavlen — hvilket skjulte fællesstammen.
    return None


def _slaegtled_header_1939(line, profile):
    """OCR spreder bogstaverne; kun centreret sats må ændre gruppe-state.

    Venstrestillede ``Slægtled I.`` er ombrudte krydshenvisninger inde i
    poster og skal derfor aldrig nå denne parser.

    Indrykningen måles efter indledende OCR-støjtegn (anførselstegn m.m.) —
    målt: '"           T redje S læ g tled .' hvor anførselstegnet stjæler
    kolonne 0 og ellers skjuler en ægte centreret overskrift.
    """
    kerne = re.sub(r'^[\s"“”\'’•*^]+', '', line)
    indryk = len(line) - len(kerne)
    if indryk < 8:
        return None
    uden_mellemrum = re.sub(r'\s+', '', kerne)
    match = profile['slaegtled_re'].match(uden_mellemrum.lower())
    if not match:
        return None
    ordinal_raw = uden_mellemrum[:match.end(1)]
    ordinal = profile['ordinals'].get(match.group(1).lower())
    return ordinal or ordinal_raw, ordinal is None


def _post_start_1939(line, profile):
    """Validér nummerlinjen mod de tre målte posthoveder.

    Af-spærring er kun et detektionssignal. Returteksten er resten af
    kildelinjen uændret, så ``raw_text`` beholder OCR-satsen ordret.
    """
    match = profile['post_re'].match(line)
    if not match:
        return None
    rest = match.group(4)
    if (profile['dato_fortsaettelse_re'].match(rest)
            or profile['kildelinje_re'].search(rest)):
        return None

    efter_markoer = rest
    usikker = bool(match.group(1))
    if efter_markoer.startswith('(?)'):
        usikker = True
        efter_markoer = efter_markoer[3:].lstrip()

    gyldigt_hoved = (
        not efter_markoer and profile['rent_spoergsmaalstegn_re'].match(rest)
        or profile['navnloest_barn_re'].match(efter_markoer)
        or profile['spaerret_navn_re'].search(efter_markoer[:80])
    )
    if not gyldigt_hoved:
        return None
    return match, usikker


def _flush_1939(posts, cur, pre_linje_label=None):
    if not cur or not cur.get('_lines'):
        return
    cur['sider'] = (str(cur['_pages'][0]) if cur['_pages'][0] == cur['_pages'][-1]
                    else f"{cur['_pages'][0]}-{cur['_pages'][-1]}")
    # Lokatoren er kun bogens trykte struktur. Mangler et bærende led,
    # lukkes der bevidst: R9 skal standse posten frem for at acceptere et gæt.
    i_stammefasen = (pre_linje_label
                     and str(cur.get('linje') or '').startswith(pre_linje_label))
    if i_stammefasen:
        # Fællesstammen (før første linje-header, s. 496-510): sektionens
        # centrerede romaner ER slægtleddene. Navnerummet 'Stamme' (evt. +
        # sektions-slug) er bogens egne overskrifter, ikke en optælling.
        # Uden roman er posten uadresserbar — fail-closed.
        cur['lokal_id'] = (f"{cur['linje']}.{cur['afsnit']}.{cur['nr_label']}"
                           if cur.get('afsnit') else None)
    elif cur.get('linje') and cur.get('slaegtled'):
        dele = [cur['linje'], cur['slaegtled']]
        if cur.get('afsnit'):
            dele.append(cur['afsnit'])
        dele.append(cur['nr_label'])
        cur['lokal_id'] = '.'.join(dele)
    else:
        cur['lokal_id'] = None
    cur['raw_text'] = norm(' '.join(cur.pop('_lines')))
    cur.pop('_pages')
    posts.append(cur)


def _gruppe_label_1939(key):
    return '.'.join(str(del_) if del_ else '?' for del_ in key)


# Pegepind i en posts narrativ: "— Børn: Ottende Slægtled I." Whitespace-normen
# i raw_text har helet linjeombrud, så mønstret kan læses samlet.
PEGEPIND_1939_RE = re.compile(
    r'(?:Børn|Døtre|Søn|Sønner|Datter)\s*[:;]\s*([A-ZÆØÅ][a-zæøå]+)\s+Slægtled'
    r'(?:\s+([IVXL]+))?')


def _pegepind_krydstjek_1939(posts, profile):
    """Bogen dobbeltbogfører strukturen: forældrenes "Børn: X Slægtled Y"-
    pegepinde er en UAFHÆNGIG facitliste over hvilke grupper der skal findes.
    Enhver peget gruppe uden segmenteret modpart = misset markør → advarsel.
    Samme princip som reconciles "tvetydig frem for forkert", et niveau op."""
    grupper = {(p.get('linje'), p.get('slaegtled'), p.get('afsnit')) for p in posts}
    slaegtled_par = {(l, s) for l, s, _ in grupper}
    mangler = []
    for p in posts:
        for m in PEGEPIND_1939_RE.finditer(p.get('raw_text') or ''):
            ordinal = profile['ordinals'].get(m.group(1).lower())
            if ordinal is None:
                continue                      # prosa-sætning, ikke pegepind
            roman = _normaliser_romertal_1939(m.group(2), profile)
            maal = (p.get('linje'), ordinal, roman)
            fundet = maal in grupper if roman else (p.get('linje'), ordinal) in slaegtled_par
            if not fundet:
                mangler.append((p.get('lokal_id') or p.get('nr_label'),
                                _gruppe_label_1939(maal)))
    return mangler


def _quality_report_1939(posts, unummererede, kontekstlinjer,
                         ukendte_ordinals, slaegtled_fald, profile=None):
    """1939-numre kontrolleres pr. trykt gruppe, ikke på tværs af bogen."""
    if profile:
        mangler = _pegepind_krydstjek_1939(posts, profile)
        prefix = 'ADVARSEL: ' if mangler else ''
        print(f'[segment] {prefix}pegepind-krydstjek: {len(mangler)} pegede grupper '
              f'uden segmenteret modpart', file=sys.stderr)
        for fra, maal in mangler[:20]:
            print(f'[segment]    post {fra} peger på {maal} — findes ikke', file=sys.stderr)
    uden_lokal_id = [p['nr_label'] for p in posts if not p.get('lokal_id')]
    print(f'[segment] {len(uden_lokal_id)} poster uden lokal_id'
          f'{": " + str(uden_lokal_id) if uden_lokal_id else ""}', file=sys.stderr)
    print(f'[segment] {unummererede} unummererede poster udeladt', file=sys.stderr)
    print(f'[segment] {kontekstlinjer} gruppe-kontekstlinjer droppet', file=sys.stderr)
    ordinal_prefix = 'ADVARSEL: ' if ukendte_ordinals else ''
    fald_prefix = 'ADVARSEL: ' if slaegtled_fald else ''
    print(f'[segment] {ordinal_prefix}{len(ukendte_ordinals)} ukendte ordinalord: '
          f'{ukendte_ordinals}', file=sys.stderr)
    print(f'[segment] {fald_prefix}{slaegtled_fald} slægtled-fald uden linjeskift',
          file=sys.stderr)

    grupper = {}
    for post in posts:
        key = (post.get('linje'), post.get('slaegtled'), post.get('afsnit'))
        grupper.setdefault(key, []).append(post)
    for key, gruppeposter in sorted(grupper.items(), key=lambda item: str(item[0])):
        label = _gruppe_label_1939(key)
        labels = [post['nr_label'] for post in gruppeposter]
        dubletter = sorted({nr for nr in labels if labels.count(nr) > 1})
        if dubletter:
            print(f'[segment] ADVARSEL: dublet-poster i gruppe {label}: {dubletter}',
                  file=sys.stderr)
        basenumre = sorted({post['nr'] for post in gruppeposter})
        huller = [nr for nr in range(basenumre[0], basenumre[-1] + 1)
                  if nr not in set(basenumre)]
        if huller:
            print(f'[segment] ADVARSEL: hul i basenr i gruppe {label}: mangler {huller}',
                  file=sys.stderr)
        print(f'[segment] gruppe {label}: {len(gruppeposter)} poster, '
              f'basenr {basenumre[0]}-{basenumre[-1]}, '
              f'dubletter {dubletter}, huller {huller}', file=sys.stderr)

    lokal_ids = [post['lokal_id'] for post in posts if post.get('lokal_id')]
    dublet_ids = sorted({lokal_id for lokal_id in lokal_ids
                         if lokal_ids.count(lokal_id) > 1})
    print(f'[segment] lokal_id-dubletter: {dublet_ids}', file=sys.stderr)


def _gruppebeskrivelse_1939(lines, i, profile):
    """Match en (evt. ombrudt) gruppebeskrivelse; returnér (slug, forbrug).

    Beskrivelsen er bogens egen gruppeoverskrift ("…s Børn med …:") og den
    ENESTE markør hvor OCR har tabt den centrerede roman. 'Slægtled' i
    teksten diskvalificerer — så rammer pegepinde og prosa aldrig."""
    samlet = []
    for k in range(i, min(i + 3, len(lines))):
        if not lines[k].strip():
            break
        samlet.append(lines[k].strip())
        tekst = norm(' '.join(samlet))
        if 'slægtled' in tekst.lower():
            return None
        if profile['gruppebeskrivelse_re'].search(tekst):
            slug = re.sub(r'[^\wÆØÅæøå]+', '-', tekst.rstrip(':'),
                          flags=re.UNICODE).strip('-')
            return slug, k - i + 1
        if tekst.endswith(':'):
            return None            # anden slags kolon-linje (kuld/ægteskab)
    return None


def _unummereret_navn_start_1939(line, profile):
    """Sand hvis linjen har bogens udbredte navnesats ved poststart.

    Et eventuelt hierarkisk oversigtspræfiks (``II.``, ``A)`` eller ``1)``)
    fjernes kun til detektion. Kildelinjen returneres aldrig omskrevet.
    """
    match = OVERSIGT_NAVN_PREFIX_1939_RE.match(line)
    tekst = match.group('tekst') if match else line
    if not tekst or not tekst[0].isupper():
        return False
    return bool(UNNUMBERED_NAME_START_1939_RE.search(tekst[:80]))


def _unummereret_post_1939(lines, start, slut, *, lokal_id, postklasse,
                            dublet, linje=None, slaegtled=None, afsnit=None,
                            page=None):
    """Byg én verbatim unummereret post fra et allerede valideret interval."""
    tekstlinjer = []
    sider = []
    aktiv_side = page
    if aktiv_side is None:
        for tidligere in reversed(lines[:start]):
            side_match = PAGE_RE.match(tidligere)
            if side_match:
                aktiv_side = int(side_match.group(1))
                break
    for line in lines[start:slut]:
        side_match = PAGE_RE.match(line)
        if side_match:
            aktiv_side = int(side_match.group(1))
            continue
        if not line.strip() or PAGE_NOISE_1939_RE.match(line):
            continue
        tekstlinjer.append(line.strip())
        if aktiv_side is not None and (not sider or sider[-1] != aktiv_side):
            sider.append(aktiv_side)
    if not tekstlinjer:
        return None
    sidefelt = None
    if sider:
        sidefelt = str(sider[0]) if sider[0] == sider[-1] else f'{sider[0]}-{sider[-1]}'
    return {
        'linje': linje, 'nr': None, 'nr_label': lokal_id.rsplit('.', 1)[-1],
        'usikker': False, 'kuld': None, 'slaegtled': slaegtled, 'afsnit': afsnit,
        'slaegtled_lokal': ordinal_to_int(slaegtled) if slaegtled else None,
        'slaegtled_gennem': None, 'aegteskab_kontekst': None,
        'sider': sidefelt, 'lokal_id': lokal_id,
        'raw_text': norm(' '.join(tekstlinjer)), 'postklasse': postklasse,
        'dublet_af_stamtavle': dublet,
    }


def _segment_oversigter_1939(lines, profile):
    """Udskil de to eksplicit markerede oversigtsblokke fail-closed."""
    blokke = []
    aktiv = None
    for i, line in enumerate(lines):
        if profile['indledning_oversigt_re'].match(line):
            aktiv = {'label': 'Indledning', 'start': i + 1, 'dublet': True}
            continue
        if profile['uplaceret_oversigt_re'].match(line):
            aktiv = {'label': 'Uplacerede', 'start': i + 1, 'dublet': False}
            continue
        if aktiv and aktiv['label'] == 'Indledning':
            er_naeste_stammesektion = (
                i + 1 < len(lines)
                and profile['stamme_sektion_re'].match(lines[i + 1]))
            if (_linje_header_1939(lines, i, profile)
                    or profile['stamme_sektion_re'].match(line)
                    or er_naeste_stammesektion):
                aktiv['slut'] = i
                blokke.append(aktiv)
                aktiv = None
    if aktiv:
        aktiv['slut'] = len(lines)
        blokke.append(aktiv)

    poster = []
    brugte_linjer = set()
    for blok in blokke:
        starter = [
            i for i in range(blok['start'], blok['slut'])
            if _unummereret_navn_start_1939(lines[i], profile)
        ]
        for position, start in enumerate(starter, 1):
            slut = starter[position] if position < len(starter) else blok['slut']
            lokal_id = f"Oversigt.{blok['label']}.U{position}"
            post = _unummereret_post_1939(
                lines, start, slut, lokal_id=lokal_id,
                postklasse='oversigtspost', dublet=blok['dublet'])
            if post:
                poster.append(post)
                brugte_linjer.update(range(start, slut))
    return poster, brugte_linjer


def _segment_stamfaedre_1939(lines, profile, reserverede_linjer):
    """Find én entydig unummereret post i hver trykt strukturslot.

    Et slot åbnes af en linje-, slægtleds-, afsnits- eller gruppeoverskrift.
    Første nummererede post lukker slottet. Flere navnelignende starter i det
    samme slot er tvetydige og udskilles ikke.
    """
    linje = profile.get('pre_linje_label')
    slaegtled = afsnit = page = None
    slot = None
    poster = []
    tvetydige = []
    positioner = {}
    nummereret_aktiv = False

    def luk_slot(slut):
        nonlocal slot
        if not slot:
            return
        kandidater = slot['kandidater']
        if len(kandidater) == 1:
            start = kandidater[0]
            key = (slot['linje'], slot['slaegtled'], slot['afsnit'])
            positioner[key] = positioner.get(key, 0) + 1
            pos = positioner[key]
            if str(slot['linje'] or '').startswith(profile['pre_linje_label']):
                dele = [slot['linje'], slot['afsnit']]
            else:
                dele = [slot['linje'], slot['slaegtled']]
                if slot['afsnit']:
                    dele.append(slot['afsnit'])
            if not all(dele):
                tvetydige.append(start)
            else:
                lokal_id = '.'.join(dele + [f'U{pos}'])
                post = _unummereret_post_1939(
                    lines, start, slut, lokal_id=lokal_id,
                    postklasse='stamfader', dublet=False,
                    linje=slot['linje'], slaegtled=slot['slaegtled'],
                    afsnit=slot['afsnit'], page=slot['page'])
                if post:
                    poster.append(post)
        elif kandidater:
            tvetydige.extend(kandidater)
        slot = None

    def aabn_slot(start):
        nonlocal slot, nummereret_aktiv
        luk_slot(start)
        nummereret_aktiv = False
        slot = {'linje': linje, 'slaegtled': slaegtled, 'afsnit': afsnit,
                'page': page, 'kandidater': []}

    i = 0
    while i < len(lines):
        line = lines[i]
        side_match = profile['page_re'].match(line)
        if side_match:
            page = int(side_match.group(1))
            i += 1
            continue

        if (profile['indledning_oversigt_re'].match(line)
                or profile['uplaceret_oversigt_re'].match(line)):
            luk_slot(i)
            nummereret_aktiv = False
            i += 1
            continue

        linje_header = _linje_header_1939(lines, i, profile)
        if linje_header:
            luk_slot(i)
            linje, forbrug = linje_header
            slaegtled = afsnit = None
            i += forbrug
            aabn_slot(i)
            continue

        stamme_sektion = profile['stamme_sektion_re'].match(line)
        if stamme_sektion:
            luk_slot(i)
            slug = re.sub(
                r'[^\wÆØÅæøå]+', '-',
                stamme_sektion.group(1) or stamme_sektion.group(2),
                flags=re.UNICODE).strip('-')
            linje = f"{profile['pre_linje_label']}-{slug}"
            slaegtled = afsnit = None
            i += 1
            aabn_slot(i)
            continue

        slaegtled_header = _slaegtled_header_1939(line, profile)
        if slaegtled_header:
            luk_slot(i)
            slaegtled = slaegtled_header[0]
            afsnit = None
            i += 1
            aabn_slot(i)
            continue

        stamme_position = None
        if str(linje or '').startswith(profile['pre_linje_label']):
            stamme_position = STAMME_POSITION_1939_RE.match(line)
        if stamme_position:
            luk_slot(i)
            roman = stamme_position.group(1).upper().replace('1', 'I')
            afsnit = (_normaliser_romertal_1939(roman, profile)
                      + (stamme_position.group(2) or '').upper())
            i += 1
            aabn_slot(i)
            continue

        afsnit_match = profile['afsnit_re'].match(line)
        if afsnit_match:
            luk_slot(i)
            afsnit = _normaliser_romertal_1939(afsnit_match.group(1), profile)
            i += 1
            aabn_slot(i)
            continue

        gruppe = _gruppebeskrivelse_1939(lines, i, profile) if slot else None
        if gruppe:
            luk_slot(i)
            afsnit = afsnit or gruppe[0]
            i += gruppe[1]
            aabn_slot(i)
            continue

        if slot and _post_start_1939(line, profile):
            luk_slot(i)
            nummereret_aktiv = True
            i += 1
            continue

        if (slot and i not in reserverede_linjer
                and _unummereret_navn_start_1939(line, profile)):
            slot['kandidater'].append(i)
        elif (not slot and not nummereret_aktiv and i not in reserverede_linjer
              and _unummereret_navn_start_1939(line, profile)):
            tvetydige.append(i)
        i += 1
    luk_slot(len(lines))
    return poster, tvetydige


def _segment_1939_v2(lines, profile):
    """V1-nummererede poster plus deterministiske unummererede poster."""
    base_profile = profile['base_profile']
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        nummererede = _segment_1939(lines, base_profile)
    oversigter, reserverede = _segment_oversigter_1939(lines, profile)
    stamfaedre, tvetydige = _segment_stamfaedre_1939(lines, profile, reserverede)
    poster = nummererede + stamfaedre + oversigter
    lokal_ids = [post.get('lokal_id') for post in poster]
    dubletter = sorted({lokal_id for lokal_id in lokal_ids
                        if lokal_id and lokal_ids.count(lokal_id) > 1})
    json.dump(poster, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write('\n')
    print(f'[segment-v2] {len(nummererede)} nummererede poster', file=sys.stderr)
    print(f'[segment-v2] {len(stamfaedre)} stamfædre', file=sys.stderr)
    print(f'[segment-v2] {len(oversigter)} oversigtsposter; '
          f'{sum(post["dublet_af_stamtavle"] for post in oversigter)} dublet-markerede',
          file=sys.stderr)
    print(f'[segment-v2] tvetydige unummererede kandidater: {len(tvetydige)}',
          file=sys.stderr)
    for linjenummer in tvetydige:
        anker = norm(lines[linjenummer])[:80]
        print(f'[segment-v2]    linje {linjenummer + 1}: {anker}', file=sys.stderr)
    print(f'[segment-v2] lokal_id-dubletter: {dubletter}', file=sys.stderr)
    return poster


def _segment_1939(lines, profile):
    # Før første blok-linje-header er vi i fællesstammen; linje bærer dens
    # navnerum ("Stamme", evt. + sektions-slug) indtil stamtavlen begynder.
    linje = profile.get('pre_linje_label')
    slaegtled = afsnit = page = cur = None
    stamtavle_startet = False
    afsnit_frisk = False    # roman netop set og endnu ubrugt af en post
    posts = []
    unummererede = 0
    kontekstlinjer = 0
    ukendte_ordinals = []
    slaegtled_fald = 0
    sidste_slaegtled_nr = None
    side_naerhed = 0
    pre_label = profile.get('pre_linje_label')
    i = 0
    while i < len(lines):
        line = lines[i]

        m = profile['page_re'].match(line)
        if m:
            page = int(m.group(1))
            side_naerhed = profile['page_noise_window']
            if cur:
                cur['_pages'].append(page)
            i += 1; continue

        if not line.strip():
            i += 1; continue

        if side_naerhed:
            side_naerhed -= 1
            if profile['page_noise_re'].match(line):
                i += 1; continue

        linje_header = _linje_header_1939(lines, i, profile)
        if linje_header:
            _flush_1939(posts, cur, pre_label); cur = None
            linje, forbrug = linje_header
            stamtavle_startet = True
            slaegtled = afsnit = None
            afsnit_frisk = False
            sidste_slaegtled_nr = None
            i += forbrug; continue

        if not stamtavle_startet and pre_label:
            m = profile['stamme_sektion_re'].match(line)
            if m:
                _flush_1939(posts, cur, pre_label); cur = None
                slug = re.sub(r'[^\wÆØÅæøå]+', '-', (m.group(1) or m.group(2)),
                              flags=re.UNICODE).strip('-')
                linje = f"{pre_label}-{slug}"
                afsnit = None
                afsnit_frisk = False
                i += 1; continue

        slaegtled_header = _slaegtled_header_1939(line, profile)
        if slaegtled_header:
            _flush_1939(posts, cur, pre_label); cur = None
            slaegtled, ukendt = slaegtled_header
            afsnit = None
            afsnit_frisk = False
            if ukendt:
                ukendte_ordinals.append(slaegtled)
            else:
                slaegtled_nr = ordinal_to_int(slaegtled)
                if (sidste_slaegtled_nr is not None
                        and slaegtled_nr < sidste_slaegtled_nr):
                    slaegtled_fald += 1
                sidste_slaegtled_nr = slaegtled_nr
            i += 1; continue

        m = profile['afsnit_re'].match(line)
        if m:
            _flush_1939(posts, cur, pre_label); cur = None
            afsnit = _normaliser_romertal_1939(m.group(1), profile)
            afsnit_frisk = True
            i += 1; continue

        beskrivelse = _gruppebeskrivelse_1939(lines, i, profile)
        if beskrivelse:
            _flush_1939(posts, cur, pre_label); cur = None
            slug, forbrug = beskrivelse
            if not afsnit_frisk:
                # Roman mangler i OCR — beskrivelsen selv er gruppens trykte
                # id. Slug, ikke løbenummer: intet må tælles.
                afsnit = slug
            i += forbrug; continue

        post_start = _post_start_1939(line, profile)
        if post_start:
            m, usikker = post_start
            afsnit_frisk = False
            _flush_1939(posts, cur, pre_label)
            nr_label = m.group(2) + m.group(3)
            cur = {
                'linje': linje, 'nr': int(m.group(2)), 'nr_label': nr_label,
                'usikker': usikker, 'kuld': None, 'slaegtled': slaegtled,
                'afsnit': afsnit,
                'slaegtled_lokal': ordinal_to_int(slaegtled) if slaegtled else None,
                'slaegtled_gennem': None, 'aegteskab_kontekst': None,
                '_lines': [m.group(4)], '_pages': [page],
            }
            i += 1; continue

        if cur is None and profile['unnumbered_re'].match(line):
            unummererede += 1
            i += 1; continue

        if cur is not None:
            cur['_lines'].append(line.strip())
        else:
            # Mellem strukturheader og første nummererede post er teksten en
            # gruppebeskrivelse, ikke en del af nogen persons kildetekst.
            kontekstlinjer += 1
        i += 1

    _flush_1939(posts, cur, pre_label)
    json.dump(posts, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write('\n')
    print(f'[segment] {len(posts)} poster', file=sys.stderr)
    _quality_report_1939(
        posts, unummererede, kontekstlinjer, ukendte_ordinals, slaegtled_fald,
        profile)
    return posts


# Profilen er den eneste udgave-dispatch. Regexer og adfærdsforskelle er
# deklareret her, så nye boglayout ikke sniger sig ind som spredte årstals-if'er.
UDGAVE_PROFILER = {
    '2018-20': {
        'segmenter': _segment_2018_20,
        'page_re': PAGE_RE,
        'post_re': POST_RE,
        'slaegtled_re': SLGT_RE,
        'filter_page_noise': False,
        'post_requires_spaerret_navn': False,
        'lokal_id_dele': ('linje', 'nr_label'),
    },
    '1939': {
        'segmenter': _segment_1939,
        'page_re': PAGE_RE,
        'post_re': POST_1939_RE,
        'slaegtled_re': SLGT_1939_RE,
        'afsnit_re': AFSNIT_1939_RE,
        'linje_named_re': LINJE_NAMED_1939_RE,
        'linje_roman_re': LINJE_ROMAN_1939_RE,
        'linje_roman_prefix_re': LINJE_ROMAN_PREFIX_1939_RE,
        'linje_wrapped_tail_re': LINJE_WRAPPED_TAIL_1939_RE,
        'linje_blok_roman_re': LINJE_BLOK_ROMAN_1939_RE,
        'linje_navn_re': LINJE_NAVN_1939_RE,
        'sidehenvisning_re': SIDEHENVISNING_1939_RE,
        'gruppebeskrivelse_re': GRUPPEBESKRIVELSE_1939_RE,
        'stamme_sektion_re': STAMME_SEKTION_1939_RE,
        'pre_linje_label': 'Stamme',
        'page_noise_re': PAGE_NOISE_1939_RE,
        'unnumbered_re': UNNUMBERED_1939_RE,
        'spaerret_navn_re': SPAERRET_NAVN_1939_RE,
        'dato_fortsaettelse_re': DATO_FORTSAETTELSE_1939_RE,
        'kildelinje_re': KILDELINJE_1939_RE,
        'navnloest_barn_re': NAVNLOEST_BARN_1939_RE,
        'rent_spoergsmaalstegn_re': RENT_SPOERGSMAALSTEGN_1939_RE,
        'indledning_oversigt_re': INDLEDNING_OVERSIGT_1939_RE,
        'uplaceret_oversigt_re': UPLACERET_OVERSIGT_1939_RE,
        'ordinals': ORDINALER_1939,
        'roman_ocr': {'IIL': 'III', 'IL': 'II', 'VIL': 'VII'},   # L<->I-forveksling, kun kendte former
        'page_noise_window': 2,
        'filter_page_noise': True,
        'post_requires_spaerret_navn': True,
        'lokal_id_dele': ('linje', 'slaegtled', 'afsnit?', 'nr_label'),
    },
}

# V2 er bevidst en separat profil. Den kalder 1939-v1 som sort boks for de
# nummererede poster og kan derfor ikke ændre deres afgrænsning eller tekst.
UDGAVE_PROFILER['1939-v2'] = {
    **UDGAVE_PROFILER['1939'],
    'segmenter': _segment_1939_v2,
    'base_profile': UDGAVE_PROFILER['1939'],
    'lokal_id_dele_unummereret':
        ('linje', 'slaegtled', 'afsnit?', 'U-position'),
}


def main(path, udgave=None):
    profile = UDGAVE_PROFILER[udgave or '2018-20']
    lines = open(path, encoding='utf-8', errors='replace').read().splitlines()
    return profile['segmenter'](lines, profile)


if __name__ == '__main__':
    if len(sys.argv) == 2:
        main(sys.argv[1])
    elif (len(sys.argv) == 4 and sys.argv[2] == '--udgave'
          and sys.argv[3] in ('1939', '1939-v2')):
        main(sys.argv[1], udgave=sys.argv[3])
    else:
        sys.exit('brug: segment.py raw.txt [--udgave 1939|1939-v2] > posts.json')
