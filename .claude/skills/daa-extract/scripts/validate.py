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
import sys, os, re, json, argparse, hashlib

ALLOWED_TOP = {"linje", "nr", "nr_label", "usikker", "navn", "tilnavn", "koen",
               "facts", "godser", "embeder", "aegteskaber", "boern",
               "begivenheder", "narrative", "_escalated",
               "kuld", "aegteskab_kontekst",
               # Gravsten: posten er bevidst fjernet fra korpus (dublet/fejludtræk).
               # Værdien er begrundelsen. Konverteren tæller den med i nr-tildelingen
               # men udelader den fra output — se convert_1939_stamtavle.convert_all.
               "fjernet",
               # Id fra identitetsregisteret (data/identitet/). Bæres uændret
               # gennem konverteren til loaderen, som foretrækker det over den
               # beregnede `linje-nr`. Se record_key_of i load_helpers.R.
               "record_key",
               # Lokator — påhæftes deterministisk af paahaeft_lokator, ikke af modellen.
               "side", "lokal_id",
               # Kontrakt 2026-07-29: omtale-gate + afhugget-flag + køn-proveniens.
               # Uden dem her ville R5 flagge ethvert kontrakt-konformt udtræk.
               "er_omtale", "tekst_afhugget", "koen_kilde"}

# Kontrolleret vokabular (invariant #9): flag drift/fejl som advisory.
try:
    _vocab = json.load(open(os.path.join(os.path.dirname(__file__), '..', 'references', 'vocab.json'), encoding='utf-8'))
except Exception:
    _vocab = {}
FAKTATYPER = set(_vocab.get('faktatype', []))
REL_ROLLER = set(_vocab.get('relation_rolle', []))


def norm(s):
    return re.sub(r'\s+', ' ', (s or '')).strip()


def _strip_parens(txt):
    """Fjern parentes-indhold (også nested). Tredjeparts-data (slægtninge, gift-
    ind ægtefæller, kilde-refs) bor i parenteser; de skal ikke tælle som postens
    egne signaler. Itererer indtil stabil, så nested '(F.: Hans (af Kaden))' tømmes."""
    prev = None
    while prev != txt:
        prev = txt
        txt = re.sub(r'\([^()]*\)', ' ', txt)
    return txt


# Børne-reference er DETERMINISTISK tekst ("3 børn: Tiende slægtled, II, nr. 31-35"
# / "Søn: ... nr. 199." / "Datter: ... nr. 5."). LLM-trinnet (③) misser den ofte,
# så vi udleder den her i deterministisk kode (filosofi: trin ④ er fejlfri kode).
# Overskriver et evt. LLM-boern, så feltet altid er konsistent.
#
# OBS: den fangede `linje` er bogens INTERNE gren-tæller i slægtleddet, IKKE
# JSON-linjen (de matcher kun ~85%). Loaderen bruger den som "stated" hint med
# fallback til forælderens linje. Den genuine kryds-gren-tvetydighed (nr genbrugt
# på tværs af linjer) løses IKKE her — se docs/decisions.md (era-tie-break).
# Antal er valgfrit ("børn:" alene) og kan have parentes-kvalifikator ("5 (7?) børn").
# Den stærke anker er halen ": [X slægtled,] [gren,] nr. N" — en narrativ-omtale
# ("deres børn boede…") har ikke kolon+nr og matcher derfor ikke.
BOERN_RE = re.compile(
    r'(?:(\d+)\s*(?:\([^)]*\))?\s+)?'                        # valgfrit antal (+ "(7?)")
    r'(?:b(?:ø|o)rn|s(?:ø|o)nner|d(?:ø|o)tre|S(?:ø|o)n|Datter)'
    r'\s*\(?\??\)?\s*:\s*'                                   # valgfri "?"/"(?)" + kolon
    r'([\wÆØÅæøå]+(?:\s*\([^)]*\))?\s+slægtled)?[^.]*?'      # valgfrit "X slægtled"
    r'(?:\b(I{1,3}V?|VI?I?)\s*,\s*)?'                        # valgfri intern gren-tæller
    r'nr\.\s*(\d+)\s*[‑–-]?\s*(\d*)',                        # nr X[- Y] (tåler linjebrud)
    re.I)


def derive_boern(raw_text):
    """Udled boern {antal, slaegtled, linje, nr_range} fra postens prosa.
    Returnér None hvis ingen børne-reference findes."""
    m = BOERN_RE.search(raw_text or '')
    if not m:
        return None
    antal_str, slgt, lin, lo, hi = m.groups()
    lo = int(lo)
    hi = int(hi) if hi else lo
    # Eksplicit antal hvis angivet ("5 børn"); ellers bredden ("Søn"/bar "børn:")
    antal = int(antal_str) if antal_str else (hi - lo + 1)
    return {
        'antal': antal,
        'slaegtled': norm(slgt) if slgt else None,
        'linje': lin.upper() if lin else None,
        'nr_range': [lo, hi],
    }


# Ægteskabs-markører er faste i DAA-prosaen: "Gift"/"g." starter en klausul,
# ordinaler "1°/2°/3°" nummererer dem, "med"/"m." indleder partneren,
# "skilt" flagger opløsning.
#
# To split-strategier:
#   A) Hvis teksten har "Gift 1°... Gift 2°..." (separate Gift-klausuler per ægtefælle),
#      split på AEGT_SPLIT (Gift/g.) og håndtér hvert segment.
#   B) Hvis teksten har "Gift 1°... 2°..." (enkelt Gift med ordinal-markerede
#      under-klausuler), split de ordinaler internt i segmentet.
#
# Dato: Fanger dag-måned-år ("26. juli 1975"), år-kun ("1698"),
# "ca. ÅÅÅÅ", "senest ÅÅÅÅ", "før ÅÅÅÅ". Grundet DAA-prosaen opfanger regex'en
# altid et årstal som minimum. NB: dato_raw er fra norm()'et tekst, men da
# norm() blot normaliserer whitespace er det altid en substring af raw_text.
#
# Mønstre der IKKE fanges (dokumenteret):
#   - Separeret (separation, separeret) vs. skilsmisse (skilt) skelnes ikke
#   - Datums-spans som "1680-1720" fortolkes som to årstal; blot første fanges
#   - Tidlig/sen DAA-udgave skriver "trolovet" som forstadie; fanges som ægtefælle
#   - "g.m." (gift med) som sammentrækning i nyere ægteskabsregistre

_AEGT_SPLIT_RE = re.compile(r'(?:(?:^|\s)(?:Gift|g\.))\s*')
_ORD_SPLIT_RE = re.compile(r'(?<!\()(\d)\s*°')  # split "1° ... 2° ..." internt
# Partner-navn: stop ved sektions-separator " – ", parentes " (", komma+linje-skift,
# eller en sentence-grænse ". " efterfulgt af stor bogstav.
# Brug ikke-grådig match og negativ lookahead for sentence-grænse.
# INGEN re.I: [A-ZÆØÅ]-ankeret skal binde på store bogstaver (undgår "med hans datter").
_PARTNER_RE = re.compile(
    r'\bm(?:ed|\.)\s+([A-ZÆØÅ][^,;(–\n]*?)(?=\s*(?:,|\s–\s|\s\(|\.\s+[A-ZÆØÅ0-9]|$))')
_NAVN_STRIP_RE = re.compile(r'[.,;:]+$')   # fjern afsluttende tegnsætning
_DATE_RE = re.compile(
    r'(?:ca\.?\s*|senest\s*|før\s*|efter\s*)?'
    r'(?:\d{1,2}\.\s*\w+\.?\s*)?\d{4}')
_ORD_NUM_RE = re.compile(r'^\s*(\d)\s*°')


def derive_aegteskaber(raw_text):
    """Udled ægteskaber deterministisk fra prosaen.

    Returnér liste (evt. tom) af dicts med nøgler:
        ordinal (int), partner_navn (str|None), dato_raw (str|None), skilt (bool)
    """
    txt = norm(raw_text or '')

    # Trin 1: split på Gift/g. markører
    gift_parts = _AEGT_SPLIT_RE.split(txt)
    if len(gift_parts) < 2:
        return []          # ingen Gift/g. markør fundet

    out = []
    running_ordinal = 0

    for seg in gift_parts[1:]:   # gift_parts[0] = tekst før første markør
        # Trin 2: find om segmentet indeholder ordinal-markører (1°, 2°, 3°...)
        # Fx: "1° 1698 med Anna ..., 2° 1712 med Birgitte ..., skilt."
        ord_positions = list(_ORD_SPLIT_RE.finditer(seg))

        if ord_positions:
            # Split på ordinal-markørerne og behandl hvert sub-segment
            bounds = [(m.start(), m.group(1)) for m in ord_positions]
            for i, (start, ord_str) in enumerate(bounds):
                end = bounds[i + 1][0] if i + 1 < len(bounds) else len(seg)
                sub = seg[start:end]
                # Fjern selve ordinal-markøren fra starten inden videre parsning
                sub_stripped = _ORD_NUM_RE.sub('', sub, count=1).lstrip('° ')
                ordinal = int(ord_str)
                running_ordinal = ordinal
                pm = _PARTNER_RE.search(sub_stripped)
                pre_med = re.split(r'\bm(?:ed|\.)\s', sub_stripped)[0]
                dm = _DATE_RE.search(pre_med)
                navn = _NAVN_STRIP_RE.sub('', norm(pm.group(1))) if pm else None
                out.append({
                    'ordinal': ordinal,
                    'partner_navn': navn if navn else None,
                    'dato_raw': dm.group(0).strip() if dm else None,
                    'skilt': bool(re.search(r'\bskilt\b', sub, re.I)),
                })
        else:
            # Ingen interne ordinaler — dette Gift er ét ægteskab
            running_ordinal += 1
            mo = _ORD_NUM_RE.match(seg)
            ordinal = int(mo.group(1)) if mo else running_ordinal
            seg_body = _ORD_NUM_RE.sub('', seg, count=1).lstrip('° ') if mo else seg
            pm = _PARTNER_RE.search(seg_body)
            pre_med = re.split(r'\bm(?:ed|\.)\s', seg_body)[0]
            dm = _DATE_RE.search(pre_med)
            navn = _NAVN_STRIP_RE.sub('', norm(pm.group(1))) if pm else None
            out.append({
                'ordinal': ordinal,
                'partner_navn': navn if navn else None,
                'dato_raw': dm.group(0).strip() if dm else None,
                'skilt': bool(re.search(r'\bskilt\b', seg, re.I)),
            })

    # Dedupliker og sorter på ordinal (Guard mod dobbelt-split)
    seen = {}
    for a in out:
        o = a['ordinal']
        if o not in seen:
            seen[o] = a
    return [seen[k] for k in sorted(seen)]


# Månedsnavne matches på 3-tegns-prefix (lowercased). Dækker dansk
# (jan./januar/marts), ældre dansk/latiniseret (Octbr., Sept.) og tysk
# (Mai, März/Maerz, Jänner, Dezember).
_MDR = {'jan': 1, 'jän': 1, 'jaen': 1,
        'feb': 2,
        'mar': 3, 'mär': 3, 'maer': 3,
        'apr': 4,
        'maj': 5, 'mai': 5,
        'jun': 6, 'jul': 7, 'aug': 8,
        'sep': 9,
        'okt': 10, 'oct': 10,
        'nov': 11,
        'dec': 12, 'dez': 12}


def _month_from_name(name):
    """Slå måned op via prefix (4-tegns 'jaen'/'maer'-transskription først)."""
    for k in (name[:4], name[:3]):
        if k in _MDR:
            return _MDR[k]
    return None

# Romertals-årstal ("anno dni MCCCCXCIIII" = 1494). Form-regex tillader BÅDE
# subtraktiv (CM/XC/IV) og additiv middelalder-notation (CCCC, IIII), og
# afviser ikke-romerske ord af romertals-bogstaver ('mild', 'civil').
# Kun tokens ≥4 tegn prøves (undgår gren-tællere III/VI); plausibelt
# års-interval 1000-2100 håndhæves.
_ROMAN_VALS = {'m': 1000, 'd': 500, 'c': 100, 'l': 50, 'x': 10, 'v': 5, 'i': 1}
_ROMAN_SHAPE_RE = re.compile(
    r'^m{0,4}(?:cm|cd|d?c{0,4})(?:xc|xl|l?x{0,4})(?:ix|iv|v?i{0,4})$')
_ROMAN_TOKEN_RE = re.compile(r'\b[mdclxvi]{4,}\b')


def _roman_year(tok):
    """Parse ét romertals-token til år, eller None hvis ugyldigt/implausibelt."""
    if not _ROMAN_SHAPE_RE.match(tok):
        return None
    total = 0
    for idx, ch in enumerate(tok):
        v = _ROMAN_VALS[ch]
        if idx + 1 < len(tok) and v < _ROMAN_VALS[tok[idx + 1]]:
            total -= v
        else:
            total += v
    return total if 1000 <= total <= 2100 else None


# ---------------------------------------------------------------------------
# Kirkelige mærkedage (dato-hærdning runde 2). EMPIRISK sjældne i korpuset
# (~7 i 1939-udtrækket; ~0 i det eksisterende — resten var kirkeNAVNE), så
# dette er ROI-afgrænset backup: faste mærkedage (lookup) + de almindeligste
# påske-relative fester (computus). Ukendt/unavngiven fest → fallback til
# hele-år (forringer aldrig — invariant fra normalize_record).
#
# KALENDER: Danmark skiftede juliansk→gregoriansk 18. feb 1700 (→ 1. mar 1700).
# Regel (spec'et år-baseret): år < 1700 → juliansk computus + calendar=
# 'juliansk'; år >= 1700 → gregoriansk + calendar='gregoriansk'. Datoen gemmes
# SOM SKREVET i kildens egen kalender — ALDRIG proleptisk-gregoriansk
# omregning (forenkling: jan-feb 1700 var reelt stadig julianske, men korpuset
# rammer ikke det hjørne). calendar er PROVENANCE-ONLY: intet i app/core
# læser den endnu; den sættes kun når en mærkedag faktisk blev konverteret.

# Kalenderaritmetik via Julian Day Number (JDN) — håndterer begge kalendre
# og ugedage ensartet (JDN mod 7 == 6 er søndag; kalibreret mod
# JDN 2451545 = 1. jan 2000 gregoriansk = lørdag = 5).

def _jdn_fra_juliansk(y, m, d):
    a = (14 - m) // 12
    yy = y + 4800 - a
    mm = m + 12 * a - 3
    return d + (153 * mm + 2) // 5 + 365 * yy + yy // 4 - 32083


def _jdn_fra_gregoriansk(y, m, d):
    a = (14 - m) // 12
    yy = y + 4800 - a
    mm = m + 12 * a - 3
    return d + (153 * mm + 2) // 5 + 365 * yy + yy // 4 - yy // 100 + yy // 400 - 32045


def _juliansk_fra_jdn(jdn):
    c = jdn + 32082
    d2 = (4 * c + 3) // 1461
    e = c - 1461 * d2 // 4
    m2 = (5 * e + 2) // 153
    day = e - (153 * m2 + 2) // 5 + 1
    month = m2 + 3 - 12 * (m2 // 10)
    year = d2 - 4800 + m2 // 10
    return year, month, day


def _gregoriansk_fra_jdn(jdn):
    a = jdn + 32044
    b = (4 * a + 3) // 146097
    c = a - 146097 * b // 4
    d2 = (4 * c + 3) // 1461
    e = c - 1461 * d2 // 4
    m2 = (5 * e + 2) // 153
    day = e - (153 * m2 + 2) // 5 + 1
    month = m2 + 3 - 12 * (m2 // 10)
    year = 100 * b + d2 - 4800 + m2 // 10
    return year, month, day


def paaskedag(year, juliansk=False):
    """(måned, dag) for påskedag i årets EGEN kalender.

    Gregoriansk: Meeus/Jones/Butcher-algoritmen (verificeret mod kendte
    påskedage 1961/2000/2024/2025/2038). Juliansk: Meeus' julianske algoritme
    (verificeret mod ortodokse Pascha-tabeller O.S. 1900/1918/2000) — resultatet
    er den JULIANSKE kalenderdato, ikke en gregoriansk omregning."""
    if juliansk:
        a = year % 4
        b = year % 7
        c = year % 19
        d = (19 * c + 15) % 30
        e = (2 * a + 4 * b - d + 34) % 7
        month = (d + e + 114) // 31
        day = (d + e + 114) % 31 + 1
        return month, day
    a = year % 19
    b = year // 100
    c = year % 100
    d = b // 4
    e = b % 4
    f = (b + 8) // 25
    g = (b - f + 1) // 3
    h = (19 * a + b - d - g + 15) % 30
    i = c // 4
    k = c % 4
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) // 451
    month = (h + l - 7 * m + 114) // 31
    day = (h + l - 7 * m + 114) % 31 + 1
    return month, day


# Faste mærkedage: kun ægte dansk-kirkelige mærkedage med utvetydig
# kalenderdato. 'Vor Frue' er TVETYDIG (Kyndelmisse 2/2, Bebudelse 25/3,
# Besøgelse 2/7, Himmelfart 15/8, Fødsel 8/9) — bar 'vor frue' mappes ALDRIG;
# kun den specifikt navngivne fest. Rækkefølge betyder noget (mortensaften
# før mortensdag; mariæ himmelfart er FAST og må ikke forveksles med den
# bevægelige Kristi Himmelfart, som kræver 'kristi'-prefix).
_KIRKEDAG_FASTE = [
    (re.compile(r'kyndelmisse'), (2, 2)),
    (re.compile(r'san[ck]t\s*hans'), (6, 24)),
    (re.compile(r'(?:mikkels|mikaels|michaelis)dag'), (9, 29)),
    (re.compile(r'mortensaften'), (11, 10)),
    (re.compile(r'mortensdag'), (11, 11)),
    (re.compile(r'allehelgen'), (11, 1)),
    (re.compile(r'hellig\s*tre\s*konger\w*'), (1, 6)),
    (re.compile(r'valborg'), (5, 1)),
    (re.compile(r'(?:vor\s*frue|mari[æe]s?)\s*bebudelse|bebudelse'), (3, 25)),
    (re.compile(r'(?:vor\s*frue|mari[æe]s?)\s*besøgelse|besøgelse'), (7, 2)),
    (re.compile(r'(?:vor\s*frue|mari[æe]s?)\s*himmelfart'), (8, 15)),
    (re.compile(r'(?:vor\s*frue|mari[æe]s?)\s*fødsel'), (9, 8)),
]

# Bevægelige (påske-relative) fester: offset i dage fra påskedag.
# Rækkefølge: '2. påskedag'/'2. pinsedag' skal matches før den bare form.
_KIRKEDAG_BEVAEGELIGE = [
    (re.compile(r'fastelavn'), -49),
    (re.compile(r'palmes[øo]ndag'), -7),
    (re.compile(r'skj?ærtorsdag'), -3),
    (re.compile(r'langfredag'), -2),
    (re.compile(r'(?:2\.?|anden)\s*p(?:aa|å)skedag'), 1),
    (re.compile(r'p(?:aa|å)ske'), 0),
    (re.compile(r'(?:store\s*)?bededag'), 26),         # 4. fredag efter påske
    (re.compile(r'kristi\s*himmelfart'), 39),
    (re.compile(r'(?:2\.?|anden)\s*pinsedag'), 50),
    (re.compile(r'pinse'), 49),
    (re.compile(r'trinitatis'), 56),
]

_ORDINAL_ORD = {
    'første': 1, 'anden': 2, 'tredje': 3, 'tredie': 3, 'fjerde': 4, 'femte': 5,
    'sjette': 6, 'syvende': 7, 'ottende': 8, 'niende': 9, 'tiende': 10,
    'ellevte': 11, 'tolvte': 12, 'trettende': 13, 'fjortende': 14,
    'femtende': 15, 'sekstende': 16, 'syttende': 17, 'attende': 18,
    'nittende': 19, 'tyvende': 20,
}
# "N. søndag efter X" — N som tal ('14.') eller ord ('anden'). \b/lookbehind
# sikrer helt ord/tal ('enogtyvende' må ikke matche som 'tyvende').
_SOENDAG_EFTER_RE = re.compile(
    r'(?:(?<!\d)(\d{1,2})\.?|\b(' + '|'.join(_ORDINAL_ORD) + r'))\s+s[øo]ndag\s+efter\s+'
    r'(trinitatis|p(?:aa|å)ske|hellig\s*tre\s*konger\w*)')
_SOENDAG_EFTER_LOOSE_RE = re.compile(r's[øo]ndag\s+efter')


def _kirkedag_dato(t, year):
    """Konvertér en genkendt kirkelig mærkedag i t (lowercased) til
    ('YYYY-MM-DD', kalender, (match_start, match_end)) — eller None.

    Match-spannet returneres så kalderen kan maskere festnavnet før
    qualifier-detektion ('efter' i '14. søndag efter Trinitatis' er en del af
    festnavnet, ikke en after-qualifier)."""
    jul = year < 1700
    cal = 'juliansk' if jul else 'gregoriansk'
    til_jdn = _jdn_fra_juliansk if jul else _jdn_fra_gregoriansk
    fra_jdn = _juliansk_fra_jdn if jul else _gregoriansk_fra_jdn

    # Returformat: (iso|None, kalender|None, span). iso=None m. span betyder
    # "genkendt men uopløselig fest-frase — maskér den, brug hele-år-fallback".
    def _iso(jdn):
        yy, mm, dd = fra_jdn(jdn)
        return f"{yy:04d}-{mm:02d}-{dd:02d}"

    em, ed = paaskedag(year, juliansk=jul)
    paaske_jdn = til_jdn(year, em, ed)

    m = _SOENDAG_EFTER_RE.search(t)
    if m:
        n = int(m.group(1)) if m.group(1) else _ORDINAL_ORD[m.group(2)]
        base = m.group(3)
        if base.startswith('hellig'):
            # N. søndag efter Helligtrekonger = N'te søndag STRENGT efter 6. jan
            h3k = til_jdn(year, 1, 6)
            foerste = h3k + ((6 - h3k % 7) % 7 or 7)
            jdn = foerste + 7 * (n - 1)
        elif base.startswith('trinitatis'):
            jdn = paaske_jdn + 56 + 7 * n
        else:                                  # påske
            jdn = paaske_jdn + 7 * n
        return _iso(jdn), cal, m.span()
    lm = _SOENDAG_EFTER_LOOSE_RE.search(t)
    if lm:
        # 'søndag efter' til stede men uopløselig (ordinal uden for tabellen,
        # ukendt basisfest) → mærkedags-match må IKKE fyre på basisfesten
        # alene ('enogtyvende søndag efter trinitatis' ≠ Trinitatis-dag).
        # Returnér dato=None men MED span, så kalderen maskerer 'søndag efter'
        # væk fra qualifier-detektionen ('efter' er festnavn, ikke qualifier)
        # og falder tilbage til hele-år.
        return None, None, lm.span()
    for pat, off in _KIRKEDAG_BEVAEGELIGE:
        m = pat.search(t)
        if m:
            return _iso(paaske_jdn + off), cal, m.span()
    for pat, (mm, dd) in _KIRKEDAG_FASTE:
        m = pat.search(t)
        if m:
            return f"{year:04d}-{mm:02d}-{dd:02d}", cal, m.span()
    return None


# Qualifier-markører (dansk, ældre dansk, tysk). 'senest' = terminus ante quem
# → behandles som 'before'. 'o.' kræver punktum (bart 'o' er for tvetydigt).
_Q_BEFORE_RE = re.compile(r'\b(?:før|inden|senest)\b')
_Q_AFTER_RE = re.compile(r'\befter\b')
_Q_ABOUT_RE = re.compile(r'\b(?:ca|circa|omkr|omkring|um)\b|\bo\.')
_Q_BETWEEN_RE = re.compile(r'\bmellem\b')
# Bindestreg-flankeret nævnt-form '(-1223-1247-)' / '-1223-' = floruit
# (dokumenteret-aktiv span, invariant #5) — IKKE levetid.
_FLORUIT_FLANK_RE = re.compile(
    r'[-–]\s*\d{3,4}(?:\s*[-–]\s*\d{3,4})?\s*[-–](?!\s*\d)')

# Bar ISO-dato (YYYY-MM-DD) — redaktøren taster selv en eksakt dag i
# OCR-kildepanelet (TS-porten). Adskilt fra det bindestreg-flankerede
# levetids-span 'YYYY-YYYY' ved at kræve to-cifrede måned/dag-grupper (ikke
# endnu et 4-cifret år): '1712-1783' matcher IKKE dette mønster. Ingen
# kalender-validering (samme konvention som "31. april 1500"): dagen
# accepteres som skrevet.
_ISO_POINT_RE = re.compile(r'(?<!\d)(\d{4})-(\d{2})-(\d{2})(?!\d)')


def derive_date_info(date_raw):
    """Udled {date_min, date_max, qualifier, certainty, calendar} deterministisk fra rå dato.

    Grundregler (invariant #5 — fuzzy datoer): kun år -> hele året;
    dag-måned-år -> punkt; to årstal -> span. Uparsebart -> alle None;
    date_raw bevares altid andetsteds. LLM'en skal IKKE selv syntetisere disse.

    ÅR-GRÆNSE-KONVENTION for åbne grænser (dokumenteret valg):
    Grænsen er det KONSERVATIVE ydre hylster INKLUSIVE det nævnte år —
    qualifieren bærer den strikte semantik:
      'før 1261'   -> date_min=None,        date_max='1261-12-31', qualifier='before'
      'efter 1575' -> date_min='1575-01-01', date_max=None,        qualifier='after'
      'mellem N og M' -> N-01-01 .. M-12-31, qualifier='between'
      'ca./o./um N' -> hele året N,          qualifier='about'
    Ved fuld dato ('før 26. juli 1261') bruges dagpunktet som grænse — et bart
    ISO-punkt ('før 1645-01-01') tæller som fuld dato på samme måde (giver
    dagpunktet '1645-01-01' som grænse, ikke helåret '1645-12-31').

    Et bart ISO-punkt uden qualifier ('1645-01-01') giver EKSAKT dag
    (date_min=date_max=datoen) — redaktøren har tastet præcisionen selv, i
    modsætning til et bart årstal ('1645') der giver helår. Ingen
    kalender-validering (se nedenfor): '1500-04-31' accepteres som skrevet.

    KIRKELIGE MÆRKEDAGE (runde 2): 'Mikkelsdag 1712', 'Paaske 1650',
    '14. søndag efter Trinitatis 1712' m.fl. konverteres til præcis dag når
    date_raw indeholder genkendt fest + årstal — se _kirkedag_dato. calendar
    sættes KUN når konverteringen faktisk landede i bounds ('juliansk' <1700,
    'gregoriansk' ellers); alle andre stier giver calendar=None.

    BEVIDST UDELADT — s.å./s.m./s.d./s.st.-ankeropløsning: LLM'en opløser
    185/188 i korpuset; de 3 uopløste er sted-/dag-/måned-refs (ikke år-cases)
    og strukturelt uopløselige uden anker-faktum. Mekanisk år-tracking på
    tværs af facts ville risikere FORKERTE opløsninger og bryde "never
    degrade"-invarianten i normalize_record — bevidst fravalgt frem for
    halvfærdigt. (TODO kun hvis korpus-empirien ændrer sig.)
    """
    info = {'date_min': None, 'date_max': None, 'qualifier': None,
            'certainty': None, 'calendar': None}
    if not date_raw:
        return info
    t = date_raw.strip().lower()

    # --- Usikre cifre (kildens egen tvivl) → bedste læsning + 'uncertain' ---
    # '147(5?)' -> 1475: parentes-ciffer med '?' er kildens foreslåede læsning.
    t, n_paren = re.subn(r'\((\d{1,2})\s*\?\)', r'\1', t)
    # '1475?' -> 1475: spørgsmålstegn efter helt årstal.
    t, n_tail = re.subn(r'(\d{4})\s*\?', r'\1', t)
    if n_paren or n_tail:
        info['certainty'] = 'uncertain'
    # '14?8': ulæseligt ciffer → ydre hylster over alle læsninger (?=0..9).
    wm = re.search(r'(?<![\d?])(\d{1,3})\?(\d{0,2})(?![\d?])', t)
    if wm and len(wm.group(1)) + 1 + len(wm.group(2)) == 4:
        y_lo = wm.group(1) + '0' + wm.group(2)
        y_hi = wm.group(1) + '9' + wm.group(2)
        info['date_min'] = f"{y_lo}-01-01"
        info['date_max'] = f"{y_hi}-12-31"
        info['certainty'] = 'uncertain'
        return info

    years = re.findall(r'\d{4}', t)
    if not years:
        # Fallback: romertals-årstal (kun når intet arabisk årstal findes)
        roman = [y for y in (_roman_year(tok) for tok in _ROMAN_TOKEN_RE.findall(t))
                 if y is not None]
        if len(roman) == 1:
            years = [str(roman[0])]
    if not years or len(years) > 2:
        return info

    # Kirkelig mærkedag (kun enkelt-år). Festnavnets span maskeres i t FØR
    # qualifier-detektion — 'efter' i '14. søndag efter Trinitatis' er en del
    # af festnavnet, ikke en after-qualifier. Masken er længde-bevarende, så
    # positions-logikken (t.find(y) vs. qualifier-position) forbliver gyldig.
    kirkedag = _kirkedag_dato(t, int(years[0])) if len(years) == 1 else None
    if kirkedag:
        ks, ke = kirkedag[2]
        t = t[:ks] + ' ' * (ke - ks) + t[ke:]

    q_between = bool(_Q_BETWEEN_RE.search(t))
    q_before = bool(_Q_BEFORE_RE.search(t))
    q_after = bool(_Q_AFTER_RE.search(t))
    q_about = bool(_Q_ABOUT_RE.search(t))
    q_floruit = bool(_FLORUIT_FLANK_RE.search(t))

    if len(years) == 2:                       # span: bevar begge grænser
        info['date_min'] = f"{min(years)}-01-01"
        info['date_max'] = f"{max(years)}-12-31"
        if q_between or (q_before and q_after):   # "mellem N og M" / "efter N, før M"
            info['qualifier'] = 'between'
        elif q_floruit:                           # '(-1223-1247-)' ≠ levetid
            info['qualifier'] = 'floruit'
        elif q_about:                             # 'ca. 1484-1569' — omtrentligt interval
            info['qualifier'] = 'about'
        # NB: et bart span '1712-1783' (levetid) får bevidst INGEN qualifier.
        return info

    y = years[0]
    dm = re.search(r'(\d{1,2})\.\s*([a-zæøåäöü]+)', t)
    iso_point = None
    iso_cal = None
    if dm:
        mo = _month_from_name(dm.group(2))
        da = int(dm.group(1))
        if mo and 1 <= da <= 31:
            iso_point = f"{y}-{mo:02d}-{da:02d}"
    if iso_point is None:
        # Bar ISO-punkt ('YYYY-MM-DD') — samme prioritet som dd.-månedsnavn-formen.
        iso_m = _ISO_POINT_RE.search(t)
        if iso_m and iso_m.group(1) == y:
            iso_point = f"{iso_m.group(1)}-{iso_m.group(2)}-{iso_m.group(3)}"
    if iso_point is None and kirkedag and kirkedag[0]:
        iso_point, iso_cal = kirkedag[0], kirkedag[1]

    if q_floruit:                             # enkelt-års floruit '-1223-'
        info['date_min'] = f"{y}-01-01"
        info['date_max'] = f"{y}-12-31"
        info['qualifier'] = 'floruit'
    elif q_before:
        # Skel på årets POSITION ift. 'før'-ordet:
        #   'før 1261' / 'før 26. juli 1261' → året ER grænsen → min åben (None).
        #   '1496, før 10. okt.' → året er kendt begivenheds-år, kun dagen er
        #     'før' → min=år-start (mister ellers den kendte nedre grænse).
        m = _Q_BEFORE_RE.search(t)
        if m and t.find(y) < m.start():
            info['date_min'] = f"{y}-01-01"
        info['date_max'] = iso_point or f"{y}-12-31"
        info['qualifier'] = 'before'
    elif q_after:
        m = _Q_AFTER_RE.search(t)
        if m and t.find(y) < m.start():   # '1496, efter 10. okt.' → år kendt → max=år-slut
            info['date_max'] = f"{y}-12-31"
        info['date_min'] = iso_point or f"{y}-01-01"
        info['qualifier'] = 'after'
    elif q_about:
        # Approksimation: ét år -> hele års-spannet, uanset evt. dag-angivelse
        info['date_min'] = f"{y}-01-01"
        info['date_max'] = f"{y}-12-31"
        info['qualifier'] = 'about'
    elif iso_point:
        info['date_min'] = info['date_max'] = iso_point
    else:
        info['date_min'] = f"{y}-01-01"
        info['date_max'] = f"{y}-12-31"
    # calendar er provenance-only og sættes kun når mærkedags-konverteringen
    # faktisk landede i en grænse (about/floruit-grenene bruger hele-år → None).
    if iso_cal and iso_point in (info['date_min'], info['date_max']):
        info['calendar'] = iso_cal
    return info


def derive_date_bounds(date_raw):
    """Bagudkompatibel wrapper: kun (date_min, date_max) fra derive_date_info."""
    info = derive_date_info(date_raw)
    return (info['date_min'], info['date_max'])


# ISO-sammenligning der tolererer år-kun-strenge ('1363' ~ '1363-01-01'/'1363-12-31').
def _cmp_min(d):
    return None if d is None else (d if len(d) > 4 else d + '-01-01')


def _cmp_max(d):
    return None if d is None else (d if len(d) > 4 else d + '-12-31')


def _is_year_placeholder(mn, mx):
    """True hvis LLM'en kun kendte året/årene: et rent hele-års-span
    YYYY-01-01..YYYY-12-31 (evt. år-kun-strenge). Kun et SÅDANT placeholder må
    derive forfine til en præcis dag fra date_raw (fx III-124: date_raw har
    '12. nov.' men LLM satte år-kun bounds). Et span med præcise endepunkter
    ('1223-05-31'..'1247-02-22' floruit, eller '01-12'..'01-13' approx) er IKKE
    et placeholder — LLM satte det fra kontekst parseren ikke ser, så det bevares.
    """
    if mn is None or mx is None:
        return False
    # ÉT år: start-år == slut-år. Et MULTI-års-span (1924-01-01..1939-12-31, fx
    # '1924/39' = 'enten 1924 eller 1939') er IKKE et placeholder — at forfine det
    # til ét år ville tabe den anden mulighed.
    return (mn[:4] == mx[:4]
            and _cmp_min(mn).endswith('-01-01') and _cmp_max(mx).endswith('-12-31'))


def escalation_entry(rec, issues, advisory):
    """Worklist-post hvis posten skal eskaleres: blokerende brud ELLER R8-miss.
    V9/R2/R3-advisory udløser IKKE eskalering. Returnér None hvis ren."""
    r8 = [a for a in (advisory or []) if a.startswith('R8')]
    if issues or r8:
        return {
            'linje': rec.get('linje'),
            'nr': rec.get('nr'),
            'nr_label': rec.get('nr_label') or str(rec.get('nr')),
            'grunde': list(issues or []) + r8,
        }
    return None


# OCR-tolerance (Bobé 1939): † fejllæses som lille 't'. Kun i dødssignal-
# lignende kontekst: klausul-start (tekststart eller efter ,.;:) + dato
# umiddelbart efter ('t 1712' / 't. 30. marts 1712'). BEVIDST case-sensitiv
# (eget regex uden re.I): stort 'T' er navne-initial, ikke en †-fejllæsning,
# og 't' i almindelige ord ('skiftet', 'til') matcher ikke mønsteret.
_OCR_DOED_T_RE = re.compile(r'(?:^|[,.;:])\s*t\.?\s+(?=\d{1,2}\.|\d{4})')


def expected_signals(raw_text):
    """Udled forventede signaler fra prosaen.

    Returnér dict med booleans:
        venter_aegteskab  — prosa indeholder Gift/g.-markør
        venter_boern      — prosa indeholder børne-reference med nr.
        venter_doed       — prosa indeholder dødstegn (†/☩) eller "døde"/"d."
    """
    txt = norm(raw_text or '')
    # Parenteser bærer tredjeparts-data (slægtninge, gift-ind ægtefæller, kilde-
    # refs). Et tredjeparts † eller "(gift…)" må ikke flagge POSTEN — strip dem
    # før død/ægteskab-signal (pilot 2026-06-18: ellers falsk-eskaleres middelalder-
    # poster med parentes-slægtninge). Børn er ikke parentes-baseret -> rå txt.
    udenfor = _strip_parens(txt)
    return {
        'venter_aegteskab': bool(derive_aegteskaber(udenfor)),
        # venter_boern bruges ikke i R8 — børn håndteres deterministisk i main().
        'venter_boern': BOERN_RE.search(txt) is not None,
        'venter_doed': bool(re.search(r'[†☩]|\bdøde?\b|\bd\.\s*\d', udenfor, re.I)
                            or _OCR_DOED_T_RE.search(udenfor)),
    }


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


def validate(rec, src, known_by_linje):
    """Returnér liste af regelbrud (tom = ren).

    Narrativen er IKKE LLM'ens ansvar: den autoritative prosa er kilde-postens
    raw_text fra posts.json. Vi tjekker derfor alt mod kilden, og main() fletter
    raw_text ind i den rene record (LLM'en udtrækker kun struktureret rygrad)."""
    issues, advisory = [], []
    src_text = norm(src['raw_text']) if src else ''

    # K: linje/nr-konsistens
    if src is None:
        issues.append(f'K: ingen kilde-post for linje {rec.get("linje")} nr {rec.get("nr")}')

    # R9: lokator komplet — uden (side, lokal_id) kan posten ikke genfindes i
    # identitetsregisteret, og registeret afviser den selv. tjek_lokator var
    # tidligere en løs funktion INGEN kaldte, så poster uden lokator passerede
    # rene (Codex-review 2026-07-29, fund 1 — reproduceret).
    issues.extend(tjek_lokator(rec))

    # R10: omtale-påstand mod nummer-anker (kalibrering 2026-07-29) — spærrer
    # auto-gravsætning af rigtige personer, sender dem til review.
    issues.extend(tjek_omtale(rec, src))

    # R6: autoritativ narrativ findes (fra kilden, ikke fra LLM)
    if src is not None and not src_text:
        issues.append('R6: kilde-postens raw_text er tom')

    # R1: hvert ÅRSTAL i en udtrukket dato skal forekomme i prosaen. Fanger
    # hallucination (opdigtede år) uden at falsk-flagge AFLEDTE spans (floruit
    # "-1257-1272-" skrives aldrig ordret i bogen) eller dag/måned-reformatering.
    hay = src_text
    for d in collect_dates(rec):
        missing = [y for y in re.findall(r'\d{4}', d or '') if y not in hay]
        if missing:
            issues.append(f'R1: årstal {missing} i dato "{d}" findes ikke i prosaen (hallucination?)')

    # R7: felt-proveniens — hvert kilde_span SKAL være ordret substring af prosaen.
    spans = [f.get('kilde_span') for f in (rec.get('facts') or [])]
    spans += [a.get('kilde_span') for a in (rec.get('aegteskaber') or [])]
    for sp in spans:
        if sp and norm(sp) not in hay:
            issues.append(f'R7: kilde_span "{sp}" findes ikke ordret i prosaen (hallucination?)')

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
            lin = b.get('linje') or rec.get('linje')
            known = known_by_linje.get(lin, set())
            true_gaps = []
            if known:
                lo, hi = min(known), max(known)
                true_gaps = [n for n in range(rng[0], rng[1] + 1)
                             if n not in known and lo <= n <= hi]
            # ADVISORY: kan ikke skelne droppet post fra bogens sammenlagte interval
            # ("95.-97. Børn."). Ægte drops fanges af segment.py's contiguity-tjek.
            if true_gaps:
                advisory.append(f'R2: børn-basenr uden individuel post i linje {lin}: {true_gaps} (sammenlagt interval el. droppet?)')
            # R3 er ADVISORY: bogen er selv ofte inkonsistent ("5 (7?) børn"),
            # og load bygger børn fra nr_range uanset antal. Blokerer ikke.
            if b.get('antal') is not None and b['antal'] != (rng[1] - rng[0] + 1):
                advisory.append(f'R3: antal børn ({b["antal"]}) matcher ikke nr_range {rng} (bog-tvetydighed?)')
        else:
            issues.append(f'R2: ugyldigt nr_range {rng}')

    # R5: ingen ukendte topfelter (tredjeparts-person-oprettelse e.l.)
    extra = set(rec.keys()) - ALLOWED_TOP
    if extra:
        issues.append(f'R5: ukendte/ikke-tilladte felter (mulig tredjeparts-oprettelse): {sorted(extra)}')

    # V9 (advisory): kontrolleret vokabular — fang drift/fejl uden at blokere.
    for f in rec.get('facts') or []:
        ft = f.get('faktatype')
        if ft and FAKTATYPER and ft not in FAKTATYPER:
            advisory.append(f'V9: ukendt faktatype "{ft}" (ej i vocab)')
    for bv in rec.get('begivenheder') or []:
        rl = bv.get('rolle')
        if rl and REL_ROLLER and rl not in REL_ROLLER:
            advisory.append(f'V9: ukendt begivenheds-rolle "{rl}"')
    for em in rec.get('embeder') or []:
        rl = em.get('rolle') or ''
        if '(' in rl or ' og ' in rl or ' med ' in rl or len(rl.split()) > 4:
            advisory.append(f'V9: mistænkelig embede-rolle "{rl}" (sammensat/ikke-rolle?)')

    # R8 (advisory): mismatch mellem prosa-signaler og udtrukket rygrad.
    # Non-blocking — advisories er diagnostik, ikke blokér-kriteriet.
    if src_text:
        sig = expected_signals(src_text)
        if sig['venter_aegteskab'] and not (rec.get('aegteskaber')):
            advisory.append('R8: prosa nævner ægteskab, men intet udtrukket')
        if sig['venter_doed'] and not any(
                f.get('faktatype') == 'død' for f in (rec.get('facts') or [])):
            advisory.append('R8: prosa nævner død, men intet død-fakta')

    return issues, advisory


# ---------------------------------------------------------------- lokator
# Lokatoren (side, lokal_id) er postens fysiske adresse i den trykte bog og
# halvdelen af identitetsregisterets nøgle (data/identitet/). Den påhæftes
# DETERMINISTISK fra segmenteringens output — modellen spørges aldrig om
# identitet, ligesom den ikke spørges om narrative, boern eller record_key.
#
# Tørløb 2026-07-29: et kontrakt-konformt udtræk havde hverken felt, så
# reconcile() matchede 0 af 30 poster og meldte hele registeret bortfaldet.
# På en rigtig re-ekstraktion havde det mintet 515 nye identiteter og
# efterladt 613 samme_som-match forældreløse.

def _foerste(v):
    """segment.py skriver undertiden et side-INTERVAL; postens anker er den første."""
    if isinstance(v, (list, tuple)):
        v = v[0] if v else None
    if v is None:
        return None
    v = str(v).strip()
    return v or None


def paahaeft_lokator(rec, src):
    """Sæt `side` + `lokal_id` fra kilde-posten. Muterer og returnerer rec.

    Modellens egne værdier OVERSKRIVES — identitet udledes ikke af et skøn.
    Mangler kilden felterne, sættes None frem for et gæt; `tjek_lokator`
    fanger det som en blokerende fejl.
    """
    src = src or {}
    rec["side"] = _foerste(src.get("sider", src.get("side")))
    rec["lokal_id"] = _foerste(src.get("lokal_id"))
    return rec


def tjek_lokator(rec):
    """R9: uden lokator kan posten ikke genfindes ved en senere re-ekstraktion."""
    mangler = [f for f in ("side", "lokal_id") if not rec.get(f)]
    if mangler:
        return [f"R9: lokator ufuldstændig (mangler {', '.join(mangler)}) — "
                f"posten kan ikke genfindes i identitetsregisteret"]
    return []


def tjek_omtale(rec, src):
    """R10: er_omtale på en post med eget nummer-anker er en selvmodsigelse.

    Omtaler har intet eget løbenummer — så hvis segmenteringen har forankret
    posten til sin EGEN trykte nummerlinje (metode="anker"), kan den ikke være
    en omtale. Kalibreringen 2026-07-29 viste modellen kassere RIGTIGE
    personer med afhugget tekst som omtaler; gaten sender dem til menneskelig
    afgørelse i stedet for tavs gravsætning. Fail-soft: uden metode-signal kan
    vi ikke konkludere, og gaten tier."""
    if rec.get("er_omtale") and (src or {}).get("metode") == "anker":
        return ["R10: er_omtale=true, men kilde-posten er forankret til sit eget "
                "trykte nummer — omtaler har intet eget nummer. Menneskelig "
                "afgørelse påkrævet (auto-gravsætning spærret)"]
    return []


def normalize_record(rec, src):
    """Anvend deterministiske overrides (boern fra prosa) som validate.main gør.

    Muterer og returnerer rec. Kald FØR validering, så gaten ser den
    normaliserede post. NB: aegteskaber er IKKE deterministisk — LLM-udtræk
    er autoritativt; derive_aegteskaber() bruges kun advisory (R8).
    """
    paahaeft_lokator(rec, src)
    if src:
        derived = derive_boern(src['raw_text'])
        if derived:
            rec['boern'] = derived
        elif rec.get('boern') is not None:
            rec['boern'] = None   # LLM-hallucineret boern uden tekst-belæg
    # Deterministisk dato-udledning fra date_raw. EMPIRISK (korpus-diff 2026-07-17):
    # LLM'ens bounds er som regel bedre end en isoleret date_raw-parser, fordi LLM'en
    # har kontekst parseren mangler — prosa uden for date_raw, opløst s.å.-anker,
    # adskillelse af fødsels- og dødsår i samme streng ('* 1607 ... † 1670'). Derfor:
    #   (a) LLM efterlod bounds tomme (begge None) → udfyld deterministisk. Det fanger
    #       de ægte huller (147(5?), romertal, åbne før/efter-grænser) UDEN at røre
    #       LLM'ens arbejde.
    #   (b) LLM satte bounds → overskriv KUN hvis derive forfiner inden for intervallet
    #       (fx år→dag samme år). Ellers bevares LLM'ens bounds — parseren må aldrig
    #       udvide/åbne/lukke og dermed forringe (fx (1670-02-02) → (1607..1670)-span).
    for f in rec.get('facts') or []:
        if not f.get('date_raw'):
            continue
        info = derive_date_info(f['date_raw'])
        om, ox = f.get('date_min'), f.get('date_max')
        if om is None and ox is None:
            f['date_min'], f['date_max'] = info['date_min'], info['date_max']
            # qualifier skrives sammen med de nyudfyldte bounds — dog aldrig over et
            # eksisterende 'floruit' (LLM-sat, dokumenteret-aktiv ≠ levetid, invariant #5).
            if info['qualifier'] and f.get('date_qualifier') != 'floruit':
                f['date_qualifier'] = info['qualifier']
            # calendar (provenance-only): kun sat når parseren konverterede en
            # kirkelig mærkedag — og kun skrevet når dens bounds faktisk blev brugt.
            if info['calendar'] and not f.get('calendar'):
                f['calendar'] = info['calendar']
        elif info['date_min'] is not None and info['date_max'] is not None \
                and _is_year_placeholder(om, ox) \
                and om[:4] <= info['date_min'][:4] and info['date_max'][:4] <= ox[:4]:
            # LLM havde kun år-placeholder; derive forfiner til dag INDEN FOR de
            # samme år (fanger LLM-under-udtræk uden at flytte en år-grænse).
            f['date_min'], f['date_max'] = info['date_min'], info['date_max']
            if info['calendar'] and not f.get('calendar'):
                f['calendar'] = info['calendar']
        # date_certainty: opgradér altid None → 'uncertain' (ortogonal læse-sikkerhed,
        # pålideligt afledt af parentes/?-mønstre, uafhængig af bounds-beslutningen).
        if info['certainty'] and not f.get('date_certainty'):
            f['date_certainty'] = info['certainty']
    return rec


def merge_kontekst(rec, src):
    """Flet kuld + aegteskab_kontekst fra kilde-posten ind (loaderen bruger dem
    til union-binding). Begge kan være None."""
    rec['kuld'] = src.get('kuld') if src else None
    rec['aegteskab_kontekst'] = src.get('aegteskab_kontekst') if src else None
    return rec


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('posts')
    ap.add_argument('extracted_dir')
    ap.add_argument('--clean', required=True)
    ap.add_argument('--review', required=True)
    ap.add_argument('--escalate', help='skriv eskalerings-worklist (blokerende + R8) hertil')
    args = ap.parse_args()

    posts = json.load(open(args.posts, encoding='utf-8'))
    # nøgle på (linje, nr_label): nr resetter per linje OG 15a/15b deler basenr
    src_by_key = {(p['linje'], p.get('nr_label', str(p['nr']))): p for p in posts}
    known_by_linje = {}
    for p in posts:
        known_by_linje.setdefault(p['linje'], set()).add(p['nr'])    # basenr per linje

    clean, review, escalation, advisories = [], [], [], 0
    files = sorted(f for f in os.listdir(args.extracted_dir) if f.endswith('.json'))
    for fn in files:
        rec = json.load(open(os.path.join(args.extracted_dir, fn), encoding='utf-8'))
        src = src_by_key.get((rec.get('linje'), rec.get('nr_label') or str(rec.get('nr'))))
        # DETERMINISTISK boern: udled fra kilde-prosaen via normalize_record.
        normalize_record(rec, src)
        # NB: aegteskaber er IKKE deterministisk — se normalize_record().
        issues, advisory = validate(rec, src, known_by_linje)
        ent = escalation_entry(rec, issues, advisory)
        if ent:
            escalation.append(ent)
        if issues:
            review.append({'fil': fn, 'linje': rec.get('linje'), 'nr': rec.get('nr'),
                           'nr_label': rec.get('nr_label') or str(rec.get('nr')),
                           'navn': rec.get('navn'), 'brud': issues, 'advisory': advisory})
        else:
            # flet den AUTORITATIVE narrativ ind fra kilden (overskriver evt. LLM-narrativ)
            rec['narrative'] = src['raw_text']
            merge_kontekst(rec, src)
            clean.append(rec)
            for adv in advisory:
                advisories += 1
                print(f'[validate] ~ linje {rec.get("linje")} nr {rec.get("nr_label")}: {adv}', file=sys.stderr)

    # Serialisér én gang: samme bytes skrives til disk OG hashes, så manifestets
    # hash pr. konstruktion er hash af disk-indholdet (ingen genlæsning).
    clean_bytes = json.dumps(clean, ensure_ascii=False, indent=2).encode('utf-8')
    open(args.clean, 'wb').write(clean_bytes)
    json.dump(review, open(args.review, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
    if args.escalate:
        json.dump(escalation, open(args.escalate, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)

    # Gate-manifest (#126): bind valideringsresultatet kryptografisk til det
    # artefakt der senere loades. load_daa.R kræver manifestet og afviser load
    # ved hash-mismatch eller rød gate — kvalitetsgaten var før kun proces-
    # håndhævet (1939 blev loadet til prod med fejlende gate, changelog
    # 2026-07-26). Ingen timestamp: manifestet skal være deterministisk
    # reproducerbart fra samme input.
    total = len(clean) + len(review)
    manifest = {
        'artefakt': os.path.basename(args.clean),
        'sha256': hashlib.sha256(clean_bytes).hexdigest(),
        'rene': len(clean),
        'flaggede': len(review),
        'andel_rene': round(len(clean) / total, 4) if total else 0.0,
    }
    json.dump(manifest, open(args.clean + '.manifest.json', 'w', encoding='utf-8'),
              ensure_ascii=False, indent=2)

    print(f'[validate] {len(clean)} rene, {len(review)} flaggede (kræver review), {advisories} advisory', file=sys.stderr)
    for r in review:
        print(f'  FLAG linje {r["linje"]} nr {r["nr"]} ({r["navn"]}):', file=sys.stderr)
        for b in r['brud']:
            print(f'      - {b}', file=sys.stderr)
    # exit 0 altid: flagging er normal drift, ikke en scriptfejl


if __name__ == '__main__':
    main()
