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

ALLOWED_TOP = {"linje", "nr", "nr_label", "usikker", "navn", "tilnavn", "koen",
               "facts", "godser", "embeder", "aegteskaber", "boern",
               "begivenheder", "narrative", "_escalated",
               "kuld", "aegteskab_kontekst"}

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


def derive_date_info(date_raw):
    """Udled {date_min, date_max, qualifier, certainty} deterministisk fra rå dato.

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
    Ved fuld dato ('før 26. juli 1261') bruges dagpunktet som grænse.

    TODO(runde 2): kirkelige mærkedage ('Paaske', 'Michaelisdag' m.fl.) kræver
    computus — falder indtil da tilbage til hele-år/None (forringer ikke).
    TODO(runde 2): calendar (juliansk/gregoriansk) sættes først ved
    mærkedags-konvertering.
    TODO(runde 2): s.å./s.m./s.d.-ankeropløsning kræver kontekst fra
    foregående fakta (arkitektur-ændring); LLM opløser de fleste allerede.
    """
    info = {'date_min': None, 'date_max': None, 'qualifier': None, 'certainty': None}
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
    if dm:
        mo = _month_from_name(dm.group(2))
        da = int(dm.group(1))
        if mo and 1 <= da <= 31:
            iso_point = f"{y}-{mo:02d}-{da:02d}"

    if q_floruit:                             # enkelt-års floruit '-1223-'
        info['date_min'] = f"{y}-01-01"
        info['date_max'] = f"{y}-12-31"
        info['qualifier'] = 'floruit'
    elif q_before:
        info['date_max'] = iso_point or f"{y}-12-31"
        info['qualifier'] = 'before'
    elif q_after:
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
    return info


def derive_date_bounds(date_raw):
    """Bagudkompatibel wrapper: kun (date_min, date_max) fra derive_date_info."""
    info = derive_date_info(date_raw)
    return (info['date_min'], info['date_max'])


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


def normalize_record(rec, src):
    """Anvend deterministiske overrides (boern fra prosa) som validate.main gør.

    Muterer og returnerer rec. Kald FØR validering, så gaten ser den
    normaliserede post. NB: aegteskaber er IKKE deterministisk — LLM-udtræk
    er autoritativt; derive_aegteskaber() bruges kun advisory (R8).
    """
    if src:
        derived = derive_boern(src['raw_text'])
        if derived:
            rec['boern'] = derived
        elif rec.get('boern') is not None:
            rec['boern'] = None   # LLM-hallucineret boern uden tekst-belæg
    # Deterministisk dato-udledning: date_min/date_max sættes fra date_raw.
    # LLM'en må ikke selv syntetisere disse (fri ISO-syntese var kilden til
    # fejl-attribuering). MEN: derive må FORBEDRE, aldrig forringe — kan den
    # ikke parse date_raw (begge bounds None), bevares en evt. eksisterende
    # værdi frem for at nulstille den (fx kirkelige mærkedage, runde 2-TODO).
    for f in rec.get('facts') or []:
        if f.get('date_raw'):
            info = derive_date_info(f['date_raw'])
            if info['date_min'] is not None or info['date_max'] is not None:
                f['date_min'], f['date_max'] = info['date_min'], info['date_max']
            else:
                f.setdefault('date_min', None)
                f.setdefault('date_max', None)
            # date_qualifier: udledt qualifier skrives på fact'et — MEN et
            # eksisterende 'floruit' (LLM-sat, dokumenteret-aktiv ≠ levetid,
            # invariant #5) må aldrig overskrives/ødelægges. Finder derive
            # intet, bevares eksisterende qualifier.
            if info['qualifier'] and f.get('date_qualifier') != 'floruit':
                f['date_qualifier'] = info['qualifier']
            # date_certainty: kun opgradér None → 'uncertain'; en LLM-sat
            # certainty ('ambiguous'/'uncertain') bevares.
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

    json.dump(clean, open(args.clean, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
    json.dump(review, open(args.review, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
    if args.escalate:
        json.dump(escalation, open(args.escalate, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)

    print(f'[validate] {len(clean)} rene, {len(review)} flaggede (kræver review), {advisories} advisory', file=sys.stderr)
    for r in review:
        print(f'  FLAG linje {r["linje"]} nr {r["nr"]} ({r["navn"]}):', file=sys.stderr)
        for b in r['brud']:
            print(f'      - {b}', file=sys.stderr)
    # exit 0 altid: flagging er normal drift, ikke en scriptfejl


if __name__ == '__main__':
    main()
