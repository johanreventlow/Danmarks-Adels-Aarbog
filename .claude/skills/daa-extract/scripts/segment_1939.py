#!/usr/bin/env python3
"""Deterministisk narrative-segmentering for 1939-Reventlow-stamtavlen.

Binder hver post i linked_clean.json til dens ordrette prosa fra raw.txt.

Design (deterministisk — ingen manuelle passes og ingen genereret prosa):

1. RENSNING: 1939-sidehovedet fjernes, og bogstavspatierede ord samles.
   Begge dele er mekaniske rettelser af PDF-tekstlagets artefakter.
2. ANKER-SNIT: hver post proever sine ankre (navn, foedsel/doed/begravelse
   date_raw, partner-navne) i sit vindues side-region af raw.txt.
   Matching er OCR-normaliseret (whitespace fjernet, lowercase, dagger->t).
   Kun VINDUE-UNIKKE ankre bruges. Ankrede poster sorteres paa
   ankerposition i dokumentorden. Slutningen cappes ved naeste anker ELLER
   bogens naeste strukturelle post-/sektionsmarkoer, hvad der kommer foerst.
3. GRUPPE-FALLBACK: ankerloese poster faar gruppens lokale tekstblok.
   Gruppen noegles paa vindue, linje, gruppe og foraeldre-note, saa genbrugte
   romertal/bogstaver ikke samler hele slaegtsgrene i een blok.
4. VINDUE-FALLBACK: poster uden gruppe (eller gruppe uden ankrede
   medlemmer) faar hele vinduets side-region. Aldrig tom, aldrig fejl.

Output: work_1939_stamtavle/narrative_1939.json
  {_id (str): {"narrative": str, "side": int,
               "metode": "anker"|"struktur-fallback"|
                          "gruppe-fallback"|"nabo-fallback"|
                          "kollisions-fallback"|"vindue-fallback"}}
Log:    work_1939_stamtavle/narrative_1939.log (metode pr. _id + stats).

Konsumenter boer behandle "vindue-fallback" som "gruppe-fallback"
(begge er over-inklusive blok-tildelinger).
"""

import bisect
import hashlib
import json
import os
import re
import statistics
import sys

PAGE_RE = re.compile(r"### PAGE (\d+) ###")
WINDOW_FILE_RE = re.compile(r"(window-\d+)_p(\d+)-(\d+)\.txt$")
HEADER_LINE_RE = re.compile(r"(?m)^[ \t]*Reventlow\.[ \t]*(?:\n|$)")
LETTER_CHARS = "A-Za-z\xc6\xd8\xc5\xe6\xf8\xe5\xc4\xd6\xdc\xe4\xf6\xfc\xc9\xe9"
SPACED_LETTERS_RE = re.compile(
    rf"(?<!\w)(?:[{LETTER_CHARS}1][ \t]+){{3,}}[{LETTER_CHARS}1](?!\w)"
)
STRUCTURAL_BOUNDARY_RE = re.compile(
    # markoeren staar enten foran tekst paa samme linje eller alene ("III.")
    r"^[ \t]*(?:\d{1,3}[A-Za-z]?\.|[IVXLCDM]+\.|[A-Z\xc6\xd8\xc5]\.)(?=[ \t]|$)",
    re.MULTILINE,
)
RECORD_START_RE = re.compile(r"^[ \t]*\d{1,3}[A-Za-z]?\.[ \t]+", re.MULTILINE)
ROMAN_SECTION_RE = re.compile(r"^[ \t]*([IVXLCDM]+)\.[ \t]+", re.MULTILINE)
ORDINAL_WORDS = (
    "F\xf8rste", "Anden", "Andet", "Tredje", "Fjerde", "Femte", "Sjette",
    "Syvende", "Ottende", "Niende", "Tiende", "Ellevte", "Tolvte",
    "Trettende", "Fjortende", "Femtende", "Sekstende", "Syttende",
    "Attende", "Nittende", "Tyvende",
)
SLAEGTLED_RE = re.compile(
    r"^[ \t]*(?:%s)[ \t]+Sl[\xe6a]gtled\b" % "|".join(ORDINAL_WORDS),
    re.MULTILINE,
)
KULD_WORDS = r"B\xf8rn|D\xf8tre|S\xf8nner|Datter|S\xf8n"
# "<Navn>s Børn", "Hr. Ivens Sønner" — mindst ét stort forbogstav-ord der
# ender på "s" umiddelbart før kuld-ordet. Små ord ("hendes Datter") rammes ikke.
GROUP_NAME_RE = re.compile(
    rf"[A-Z\xc6\xd8\xc5][{LETTER_CHARS}\-]*s[ \t]+(?:{KULD_WORDS})\b")
# Samme, men forankret i linjestart: linjen skal BEGYNDE med en raekke
# stort-forbogstavs-ord (titler + navn). Det skiller overskriften
# "Johan Reventlows Døtre m. …" fra prosaen "… var Fader til
# Bertram Reventlows Børn …", hvor kaeden brydes af et lille ord.
GROUP_HEADER_LINE_RE = re.compile(
    rf"^[ \t]*(?:[A-Z\xc6\xd8\xc5][{LETTER_CHARS}.\-]*,?[ \t]+)*"
    rf"[A-Z\xc6\xd8\xc5][{LETTER_CHARS}\-]*s[ \t]+(?:{KULD_WORDS})"
    # efter kuld-ordet foelger enten linjeskift eller aegtefaelle-leddet;
    # fortsaetter linjen som almindelig prosa ("… Børn og som drev …"),
    # er det en saetning og ikke en overskrift
    rf"(?:[ \t]*$|[ \t]+(?:m\.|med\b|af\b))",
    re.MULTILINE,
)
# "af første Ægteskab" — OCR taber ofte det initiale Æ ("gteskab")
AEGTESKAB_RE = re.compile(r"gteskab\b")
# "— Børn:" sidst i en post er bogens krydshenvisning, ikke en overskrift
CROSSREF_COLON_RE = re.compile(rf"^[-–— \t]*(?:{KULD_WORDS})[ \t]*:$")
HEADER_BLOCK_MAX_LINES = 5
# Postens egen nummerlinje ligger taet paa ankeret; laengere tilbage snappes ikke
RECORD_SNAP_MAX = 400
# Linjer der ender sådan er prosa, ikke en overskriftslinje under opbygning
PROSE_LINE_ENDINGS = (".", ",", ";", ")", "\xbb", "!", "?")
LINE_SECTION_RE = re.compile(
    r"^[ \t]*(?:[IVXLCDM]+|[A-Z\xc6\xd8\xc5])\.[ \t]+", re.MULTILINE)
MIN_ANCHOR_LEN = 3  # normaliserede tegn; uniqueness-krav er den reelle vagt
MIN_NARRATIVE_LEN = 20  # kortere anker-snit = naesten sikkert daarligt snit
WINDOW_SIZED_FRAC = 0.9  # narrative >= denne andel af vindue-regionen = "vinduesstor" (fallback-diagnostik)
NAME_BEFORE_FACT_MAX = 500  # navn maa flytte start bagud, men ikke til fjern omtale
QUALITY_LIMITS = {
    "len_max": 5000,
    "duplikerede_poster": 30,
    "narrativer_med_flere_postmarkoerer": 15,
    "mistænkelig_bogstav_1_forekomster": 12,
    "fremmed_unik_dato_proxy_narrativer": 25,
}

WORK_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.dirname(os.path.abspath(__file__)))))),
    "work_1939_stamtavle",
)


# --------------------------------------------------------------- normalize

def clean_1939_text(text):
    """Fjern sikre 1939-PDF-artefakter uden at omskrive prosa.

    - den eksakte koerende sidehovedlinje ``Reventlow.`` fjernes;
    - sekvenser paa mindst fire enkelttegn paa samme linje samles;
    - cifferet ``1`` rettes kun til ``l`` inde i netop saadan en sekvens.

    Kravet om fire enkelttegn beskytter bl.a. ``N. N.``, ``f.``, ``g.`` og
    andre legitime initialer/forkortelser mod at blive limet sammen.
    """
    text = HEADER_LINE_RE.sub("", text)

    def despaced(match):
        tokens = re.split(r"[ \t]+", match.group(0).strip())
        return "".join("l" if token == "1" else token for token in tokens)

    return SPACED_LETTERS_RE.sub(despaced, text)

def normalize_with_map(text):
    """OCR-normaliser: lowercase, dagger->t, whitespace OG bindestreger fjernet.

    Bindestreger fjernes symmetrisk i baade anker og raatekst, saa et navn
    der er orddelt ved linjeskift ("Ana-\\nstasia") stadig matcher sin
    kompakte form — og omvendt, saa et aegte bindestregsnavn
    ("Brahe-Trolleborg") matcher ogsaa naar OCR har delt det ved sin egen
    bindestreg.

    Returnerer (norm_text, idx) hvor idx[i] er original-offset for
    norm_text[i], saa fund kan mappes tilbage til raw-offsets.
    """
    norm = []
    idx = []
    for i, ch in enumerate(text):
        c = ch.lower()
        if c == "†":  # dagger
            c = "t"
        if c in ("-", "\xad", "‐", "‑"):
            continue
        if c.isspace():
            continue
        norm.append(c)
        idx.append(i)
    return "".join(norm), idx


# --------------------------------------------------------------- pages

def parse_pages(raw):
    """[(offset, sidetal)] for hver ### PAGE N ###-markoer, i dokumentorden."""
    return [(m.start(), int(m.group(1))) for m in PAGE_RE.finditer(raw)]


def page_region(pages, raw_len, p_lo, p_hi):
    """Raw-offsets (lo, hi) der daekker siderne p_lo..p_hi inklusive."""
    nums = [p for _, p in pages]
    offs = [o for o, _ in pages]
    i = bisect.bisect_left(nums, p_lo)
    lo = offs[i] if i < len(offs) else 0
    j = bisect.bisect_right(nums, p_hi)
    hi = offs[j] if j < len(offs) else raw_len
    return lo, hi


def page_at(pages, offset):
    """Sidetal for et raw-offset (markoer paa eller foer offset)."""
    offs = [o for o, _ in pages]
    i = bisect.bisect_right(offs, offset) - 1
    if i < 0:
        i = 0
    return pages[i][1]


# --------------------------------------------------------------- anchors

def collect_anchors(post):
    """Ankerkandidater i prioriteret orden (foedsel foerst — 98,9% ordret)."""
    cands = []
    for field in ("foedsel", "doed", "begravelse"):
        v = (post.get(field) or {}).get("date_raw")
        if v:
            cands.append(v)
    for ae in post.get("aegteskaber") or []:
        d = ae.get("dato_raw")
        if d:
            cands.append(d)
        p = ae.get("partner_navn")
        if p:
            cands.append(p)
    return cands


def collect_name_anchors(post):
    """Navnevarianter fra mest kilde-naer til normaliseret."""
    out = []
    for field in ("navn_ocr_raw", "navn_raw", "navn"):
        value = post.get(field)
        if isinstance(value, str) and value.strip() and value not in out:
            out.append(value)
    return out


def collect_secondary_anchors(post):
    """Laengere strukturerede tekstfelter, kun brugt naar primaerankre fejler."""
    out = []
    values = [post.get("titel")]
    values.extend(post.get("erhverv") or [])
    values.extend(post.get("godser") or [])
    for value in values:
        if not isinstance(value, str) or not value.strip() or value in out:
            continue
        norm, _ = normalize_with_map(value)
        if len(norm) >= 8:
            out.append(value)
    return out


def find_unique_anchor(nraw, nidx, anchor, lo, hi):
    """Original-offset for anker hvis det findes PRAECIS een gang i
    raw[lo:hi] (normaliseret sammenligning); ellers None."""
    na, _ = normalize_with_map(anchor)
    if len(na) < MIN_ANCHOR_LEN:
        return None
    nlo = bisect.bisect_left(nidx, lo)
    nhi = bisect.bisect_left(nidx, hi)
    segment_text = nraw[nlo:nhi]
    first = segment_text.find(na)
    if first < 0:
        return None
    if segment_text.find(na, first + 1) >= 0:
        return None  # ikke unikt i vinduet
    return nidx[nlo + first]


# --------------------------------------------------------------- segmenting

def _strip_markers(text):
    return PAGE_RE.sub("", text).strip()


def _line_start(raw, pos):
    return raw.rfind("\n", 0, pos) + 1


def _first_unique_anchor(nraw, nidx, candidates, lo, hi):
    for candidate in candidates:
        pos = find_unique_anchor(nraw, nidx, candidate, lo, hi)
        if pos is not None:
            return pos
    return None


def _post_number(post):
    """Bogens lokale postnummer.

    ``_orig_nr`` foretraekkes: i 1939-artefaktet er ``nr`` en GLOBAL taeller
    (1-539), mens bogen selv nummererer lokalt inden for hvert kuld ("4."),
    og det er bogens tal der staar i teksten.
    """
    for key in ("_orig_nr", "nr"):
        value = post.get(key)
        if isinstance(value, bool):
            continue
        if isinstance(value, int) and 0 <= value <= 999:
            return value
        if isinstance(value, str) and re.fullmatch(r"\d{1,3}", value.strip()):
            return int(value.strip())
    return None


def _numbered_starts(raw, lo, hi, number):
    return [
        lo + match.start()
        for match in RECORD_START_RE.finditer(raw[lo:hi])
        if int(re.match(r"[ \t]*(\d{1,3})", match.group(0)).group(1)) == number
    ]


def _contextual_number_anchor(raw, nraw, nidx, post, lo, hi):
    """Entydigt postnummer, helst afgraenset af postens romertalslinje."""
    number = _post_number(post)
    if number is None:
        return None
    line = ((post.get("_ctx") or {}).get("linje") or "").strip()
    line_pos = None
    if line:
        line_pos = find_unique_anchor(nraw, nidx, line, lo, hi)
    if line_pos is not None:
        section_lo = _line_start(raw, line_pos)
        later_sections = [
            lo + match.start()
            for match in LINE_SECTION_RE.finditer(raw[lo:hi])
            if lo + match.start() > section_lo
        ]
        section_hi = later_sections[0] if later_sections else hi
        starts = _numbered_starts(raw, section_lo, section_hi, number)
        if len(starts) == 1:
            return starts[0]
    roman = re.match(r"^([IVXLCDM]+)\.", line)
    if roman:
        sections = [
            (lo + match.start(), match.group(1))
            for match in ROMAN_SECTION_RE.finditer(raw[lo:hi])
        ]
        matching = [i for i, (_, label) in enumerate(sections) if label == roman.group(1)]
        if len(matching) == 1:
            i = matching[0]
            section_lo = sections[i][0]
            section_hi = sections[i + 1][0] if i + 1 < len(sections) else hi
            starts = _numbered_starts(raw, section_lo, section_hi, number)
            if len(starts) == 1:
                return starts[0]
    starts = _numbered_starts(raw, lo, hi, number)
    return starts[0] if len(starts) == 1 else None


def _snap_to_own_record_start(raw, post, pos, lo):
    """Flyt starten tilbage til postens EGEN nummerlinje, hvis ankeret ligger
    inde i posten.

    Fail-closed: der snappes kun til den SIDSTE nummerlinje foer ankeret —
    saa der pr. konstruktion ikke ligger en fremmed postgraense imellem — og
    kun naar dens tal matcher bogens lokale nummer for posten.
    """
    number = _post_number(post)
    if number is None:
        return pos
    if RECORD_START_RE.match(raw, pos):
        return pos  # ankeret ER allerede en postgraense — intet at redde
    starts = [lo + m.start() for m in RECORD_START_RE.finditer(raw[lo:pos])]
    if not starts:
        return pos
    start = starts[-1]
    if pos - start > RECORD_SNAP_MAX:
        return pos
    match = re.match(r"[ \t]*(\d{1,3})", raw[start:])
    if not match or int(match.group(1)) != number:
        return pos
    return start


def _post_anchor(raw, nraw, nidx, post, lo, hi):
    """Vaelg et sikkert anker; et naert, tidligere navnetraef giver fuld start."""
    fact = _first_unique_anchor(nraw, nidx, collect_anchors(post), lo, hi)
    name = _first_unique_anchor(nraw, nidx, collect_name_anchors(post), lo, hi)
    if fact is not None and name is not None:
        fact_start = _line_start(raw, fact)
        name_start = _line_start(raw, name)
        if name_start <= fact_start and fact_start - name_start <= NAME_BEFORE_FACT_MAX:
            return name_start
        return _snap_to_own_record_start(raw, post, fact_start, lo)
    pos = fact if fact is not None else name
    if pos is None:
        pos = _first_unique_anchor(
            nraw, nidx, collect_secondary_anchors(post), lo, hi)
    if pos is None:
        pos = _contextual_number_anchor(raw, nraw, nidx, post, lo, hi)
    if pos is None:
        return None
    return _snap_to_own_record_start(raw, post, _line_start(raw, pos), lo)


def structural_boundaries(raw):
    """Linjestarter for bogens nummererede poster og romertalssektioner."""
    return [m.start() for m in STRUCTURAL_BOUNDARY_RE.finditer(raw)]


def record_starts(raw):
    """Linjestarter for nummererede personposter (ikke sektionsoverskrifter)."""
    return [m.start() for m in RECORD_START_RE.finditer(raw)]


def group_header_starts(raw):
    """Linjestarter for bogens kuld-overskrifter — de er ikke personposter.

    To former genkendes:

    1. Slaegtled-linjen alene ("Sjette Slægtled.").
    2. En overskriftsblok der slutter paa ":" og navngiver et kuld
       ("Bertram Reventlows Børn m. Christine Rantzau:") eller et aegteskab
       ("af første Ægteskab med ...:"). Blokken samles baglaens fra
       kolon-linjen, saa flerlinjede overskrifter snittes fra deres FOERSTE
       linje og ikke efterlader en stump paa den foregaaende post.

    Fail-closed: prosalinjer der tilfaeldigvis ender paa ":" bliver kun til
    en graense hvis blokken ogsaa navngiver et kuld eller et aegteskab, og
    bogens krydshenvisning ("— Børn:") er eksplicit undtaget.
    """
    starts = {m.start() for m in SLAEGTLED_RE.finditer(raw)}
    # Overskrifter uden kolon ("Johan Reventlows Døtre m. X (Lindenov).")
    starts |= {m.start() for m in GROUP_HEADER_LINE_RE.finditer(raw)}

    lines = []  # (offset, raatekst)
    offset = 0
    for line in raw.splitlines(keepends=True):
        lines.append((offset, line))
        offset += len(line)

    for i, (_, line) in enumerate(lines):
        stripped = line.strip()
        if not stripped.endswith(":") or CROSSREF_COLON_RE.match(stripped):
            continue
        block = [i]
        j = i - 1
        while j >= 0 and len(block) < HEADER_BLOCK_MAX_LINES:
            prev = lines[j][1].strip()
            if (not prev or prev.endswith(PROSE_LINE_ENDINGS)
                    or RECORD_START_RE.match(lines[j][1])
                    or PAGE_RE.search(lines[j][1])):
                break
            block.append(j)
            j -= 1
        text = " ".join(lines[k][1].strip() for k in sorted(block))
        if GROUP_NAME_RE.search(text) or AEGTESKAB_RE.search(text):
            starts.add(lines[min(block)][0])
    return sorted(starts)


def segment(posts, raw, winmap):
    """Kernefunktion (ren): posts + raw + {window-id: (p_lo, p_hi)} ->
    {_id_str: {"narrative", "side", "metode"}}. Hver post faar ikke-tom
    narrative — via fallback om noedvendigt."""
    raw = clean_1939_text(raw)
    pages = parse_pages(raw)
    nraw, nidx = normalize_with_map(raw)
    boundaries = sorted(set(structural_boundaries(raw))
                        | set(group_header_starts(raw)))
    entry_starts = record_starts(raw)

    regions = {}  # _id -> (lo, hi) vindue-region
    anchor_pos = {}  # _id -> original-offset
    collision_pos = {}  # _id -> allerede optaget ankerlinje
    seen_positions = set()

    for post in posts:
        pid = post["_id"]
        p_lo, p_hi = winmap[post["_window"]]
        regions[pid] = page_region(pages, len(raw), p_lo, p_hi)
        lo, hi = regions[pid]
        start = _post_anchor(raw, nraw, nidx, post, lo, hi)
        if start is None:
            continue
        if start in seen_positions:
            collision_pos[pid] = start
            continue
        seen_positions.add(start)
        anchor_pos[pid] = start

    # Snit i positionsorden (robust over for _id/dokument-ordens-afvigelser)
    ordered = sorted(anchor_pos.items(), key=lambda kv: kv[1])
    spans = {}  # _id -> (start, end) original-offsets
    for k, (pid, start) in enumerate(ordered):
        _, region_hi = regions[pid]
        end = region_hi
        if k + 1 < len(ordered):
            nxt = ordered[k + 1][1]
            if start < nxt < end:
                end = nxt
        bi = bisect.bisect_right(boundaries, start)
        if bi < len(boundaries) and start < boundaries[bi] < end:
            end = boundaries[bi]
        if end > start:
            spans[pid] = (start, end)
    span_by_start = {anchor_pos[pid]: span for pid, span in spans.items()}
    collision_spans = {
        pid: span_by_start[start]
        for pid, start in collision_pos.items()
        if start in span_by_start
    }

    # Entydige huller i postordenen: hvis et loeb paa N ankerloese poster er
    # afgraenset af ankre/vindue og indeholder praecis N nummererede bogposter,
    # kan de bindes 1:1 uden tekstfortolkning eller gaet.
    structure_spans = {}
    neighbor_spans = {}
    by_window = {}
    for post in posts:
        by_window.setdefault(post["_window"], []).append(post)
    for window_posts in by_window.values():
        i = 0
        while i < len(window_posts):
            if window_posts[i]["_id"] in spans:
                i += 1
                continue
            j = i
            while j < len(window_posts) and window_posts[j]["_id"] not in spans:
                j += 1
            run = window_posts[i:j]
            region_lo, region_hi = regions[run[0]["_id"]]
            left = spans[window_posts[i - 1]["_id"]][1] if i > 0 else region_lo
            right = anchor_pos[window_posts[j]["_id"]] if j < len(window_posts) else region_hi
            starts = [p for p in entry_starts if left <= p < right]
            if left < right and len(starts) == len(run):
                for post, start in zip(run, starts):
                    bi = bisect.bisect_right(boundaries, start)
                    end = right
                    if bi < len(boundaries) and start < boundaries[bi] < end:
                        end = boundaries[bi]
                    if end > start:
                        structure_spans[post["_id"]] = (start, end)
            # Ved vindueskanten kan overlappet rumme flere bogposter end dette
            # vindues egne records. Bind da kun nummererede kantposter udefra:
            # foerste match ved venstre kant, sidste match ved hoejre kant.
            if left < right and i == 0 and j < len(window_posts):
                cursor = left
                for post in run:
                    number = _post_number(post)
                    matches = ([p for p in starts if p >= cursor and
                                int(re.match(r"[ \t]*(\d{1,3})", raw[p:]).group(1))
                                == number] if number is not None else [])
                    if not matches:
                        continue
                    start = matches[0]
                    bi = bisect.bisect_right(boundaries, start)
                    end = boundaries[bi] if bi < len(boundaries) else right
                    structure_spans.setdefault(post["_id"], (start, min(end, right)))
                    cursor = start + 1
            if left < right and j == len(window_posts) and i > 0:
                cursor = right
                for post in reversed(run):
                    number = _post_number(post)
                    matches = ([p for p in starts if p < cursor and
                                int(re.match(r"[ \t]*(\d{1,3})", raw[p:]).group(1))
                                == number] if number is not None else [])
                    if not matches:
                        continue
                    start = matches[-1]
                    bi = bisect.bisect_right(boundaries, start)
                    end = boundaries[bi] if bi < len(boundaries) else right
                    structure_spans.setdefault(post["_id"], (start, min(end, right)))
                    cursor = start
            if left < right:
                for post in run:
                    neighbor_spans[post["_id"]] = (left, right)
            i = j

    # Gruppe-blokke: span over ankrede medlemmer pr. (linje, gruppe)
    def gkey(post):
        ctx = post.get("_ctx") or {}
        g = ctx.get("gruppe")
        if not g:
            return None
        return (
            post.get("_window") or "",
            ctx.get("linje") or "",
            g,
            ctx.get("foraeldre_note") or post.get("foraeldre_note") or "",
        )

    group_spans = {}
    for post in posts:
        pid = post["_id"]
        key = gkey(post)
        if key is None or pid not in spans:
            continue
        s, e = spans[pid]
        cur = group_spans.get(key)
        group_spans[key] = (min(cur[0], s), max(cur[1], e)) if cur else (s, e)

    out = {}
    for post in posts:
        pid = post["_id"]
        key = gkey(post)
        # Kaskade: anker -> entydig struktur -> lokal gruppe -> nabogab -> vindue.
        # For korte snit (naesten sikkert daarlige) demoteres nedad.
        candidates = []
        if pid in spans:
            candidates.append(("anker", spans[pid]))
        if pid in structure_spans:
            candidates.append(("struktur-fallback", structure_spans[pid]))
        if pid in collision_spans:
            candidates.append(("kollisions-fallback", collision_spans[pid]))
        if key is not None and key in group_spans:
            candidates.append(("gruppe-fallback", group_spans[key]))
        if pid in neighbor_spans:
            candidates.append(("nabo-fallback", neighbor_spans[pid]))
        candidates.append(("vindue-fallback", regions[pid]))

        metode, narrative, s = candidates[-1][0], "", candidates[-1][1][0]
        for m, (cs, ce) in candidates:
            text = _strip_markers(raw[cs:ce])
            exact = m in {"anker", "struktur-fallback", "kollisions-fallback"}
            if text.strip() and (exact or len(text) >= MIN_NARRATIVE_LEN):
                metode, narrative, s = m, text, cs
                break
        if not narrative:  # sidste vaern: aldrig tom (tag laengste kandidat)
            m, (cs, ce) = max(
                candidates, key=lambda c: len(_strip_markers(raw[c[1][0]:c[1][1]])))
            metode, narrative, s = m, _strip_markers(raw[cs:ce]), cs
        out[str(pid)] = {
            "narrative": narrative,
            "side": page_at(pages, s),
            "metode": metode,
        }
    return out


# --------------------------------------------------------------- CLI/stats

def _load_winmap(windows_dir):
    winmap = {}
    for name in os.listdir(windows_dir):
        m = WINDOW_FILE_RE.match(name)
        if m:
            winmap[m.group(1)] = (int(m.group(2)), int(m.group(3)))
    return winmap


def compute_stats(posts, result, winmap, raw):
    """Kvalitetstal (kun taellinger — ingen prosa)."""
    raw = clean_1939_text(raw)
    pages = parse_pages(raw)
    by_metode = {
        "anker": 0,
        "struktur-fallback": 0,
        "gruppe-fallback": 0,
        "nabo-fallback": 0,
        "kollisions-fallback": 0,
        "vindue-fallback": 0,
    }
    empty = 0
    r_hit = r_total = 0
    lengths = []
    short = []
    window_sized = []
    duplicate_groups = {}
    header_occurrences = 0
    header_narratives = 0
    spaced_occurrences = 0
    spaced_narratives = 0
    digit_one_occurrences = 0
    multi_record_narratives = 0
    foreign_unique_date_narratives = 0
    region_len = {}
    for wid, (lo, hi) in winmap.items():
        a, b = page_region(pages, len(raw), lo, hi)
        region_len[wid] = b - a
    date_owners = {}
    for post in posts:
        for field in ("foedsel", "doed"):
            value = (post.get(field) or {}).get("date_raw")
            if not value:
                continue
            normalized, _ = normalize_with_map(value)
            if len(normalized) >= 6:
                date_owners.setdefault(normalized, set()).add(str(post["_id"]))

    for post in posts:
        pid = str(post["_id"])
        rec = result[pid]
        by_metode.setdefault(rec["metode"], 0)
        by_metode[rec["metode"]] += 1
        n = rec["narrative"]
        if not n.strip():
            empty += 1
        nnorm, _ = normalize_with_map(n)
        digest = hashlib.sha256(n.encode("utf-8")).hexdigest()
        duplicate_groups.setdefault(digest, []).append(pid)
        headers = HEADER_LINE_RE.findall(n + ("\n" if not n.endswith("\n") else ""))
        header_occurrences += len(headers)
        header_narratives += bool(headers)
        spaced = SPACED_LETTERS_RE.findall(n)
        spaced_occurrences += len(spaced)
        spaced_narratives += bool(spaced)
        digit_one_occurrences += len(re.findall(
            rf"(?i)[{LETTER_CHARS}]\s+1(?=\s|$)", n))
        multi_record_narratives += len(record_starts(n)) > 1
        foreign_unique_date_narratives += any(
            owners == {owner} and owner != pid and date in nnorm
            for date, owners in date_owners.items()
            for owner in owners
        )
        for field in ("foedsel", "doed"):
            v = (post.get(field) or {}).get("date_raw")
            if not v:
                continue
            r_total += 1
            nv, _ = normalize_with_map(v)
            if nv and nv in nnorm:
                r_hit += 1
        lengths.append(len(n))
        if len(n) < MIN_NARRATIVE_LEN:
            short.append(pid)
        if len(n) >= WINDOW_SIZED_FRAC * region_len[post["_window"]]:
            window_sized.append(pid)
    duplicate_clusters = [ids for ids in duplicate_groups.values() if len(ids) > 1]
    lengths_sorted = sorted(lengths)
    p95_index = min(len(lengths_sorted) - 1, int(0.95 * len(lengths_sorted))) \
        if lengths_sorted else 0
    return {
        "metode": by_metode,
        "tomme": empty,
        "r_proxy_hit": r_hit,
        "r_proxy_total": r_total,
        "len_median": statistics.median(lengths) if lengths else 0,
        "len_mean": round(statistics.mean(lengths), 1) if lengths else 0,
        "len_p95": lengths_sorted[p95_index] if lengths_sorted else 0,
        "len_max": max(lengths, default=0),
        "korte_ids": short,
        "vinduesstore_ids": window_sized,
        "duplikerede_poster": sum(len(ids) for ids in duplicate_clusters),
        "duplikat_klynger": len(duplicate_clusters),
        "stoerste_duplikat_klynge": max(map(len, duplicate_clusters), default=0),
        "narrativer_med_flere_postmarkoerer": multi_record_narratives,
        "sidehoved_forekomster": header_occurrences,
        "narrativer_med_sidehoved": header_narratives,
        "bogstavspredning_forekomster": spaced_occurrences,
        "narrativer_med_bogstavspredning": spaced_narratives,
        "mistænkelig_bogstav_1_forekomster": digit_one_occurrences,
        "fremmed_unik_dato_proxy_narrativer": foreign_unique_date_narratives,
    }


def quality_gate_failures(stats):
    """Korpusgates der fanger kendte A3b-regressioner uden at laese prosa."""
    failures = []
    exact_zero = {
        "tomme": stats["tomme"],
        "vinduesstore": len(stats["vinduesstore_ids"]),
        "vindue-fallback": stats["metode"].get("vindue-fallback", 0),
        "sidehoved_forekomster": stats["sidehoved_forekomster"],
        "bogstavspredning_forekomster": stats["bogstavspredning_forekomster"],
    }
    failures.extend(f"{name}={value} (kræver 0)"
                    for name, value in exact_zero.items() if value != 0)
    failures.extend(
        f"{name}={stats[name]} (maks {limit})"
        for name, limit in QUALITY_LIMITS.items()
        if stats[name] > limit
    )
    if stats["r_proxy_total"] and stats["r_proxy_hit"] / stats["r_proxy_total"] < 0.90:
        failures.append(
            f"R1/R6-proxy={stats['r_proxy_hit']}/{stats['r_proxy_total']} (kræver >=90%)")
    return failures


def main():
    work = sys.argv[1] if len(sys.argv) > 1 else WORK_DIR
    with open(os.path.join(work, "raw.txt"), encoding="utf-8") as f:
        raw = f.read()
    with open(os.path.join(work, "linked_clean.json"), encoding="utf-8") as f:
        posts = json.load(f)
    winmap = _load_winmap(os.path.join(work, "windows"))

    result = segment(posts, raw, winmap)
    stats = compute_stats(posts, result, winmap, raw)
    failures = quality_gate_failures(stats)
    if failures:
        print("KVALITETSGATE FEJLEDE:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    out_path = os.path.join(work, "narrative_1939.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=1)

    log_path = os.path.join(work, "narrative_1939.log")
    with open(log_path, "w", encoding="utf-8") as f:
        for post in posts:
            pid = str(post["_id"])
            rec = result[pid]
            f.write(f"{pid}\t{rec['metode']}\tside={rec['side']}"
                    f"\tlen={len(rec['narrative'])}\n")
        f.write(f"\nSTATS: {json.dumps(stats)}\n")

    print(f"skrev {out_path} ({len(result)} poster)")
    print(f"metode: {stats['metode']}  tomme: {stats['tomme']}")
    print(f"R1/R6-proxy: {stats['r_proxy_hit']}/{stats['r_proxy_total']}")
    print(f"laengde median/mean: {stats['len_median']}/{stats['len_mean']}")
    print(f"korte (<20): {len(stats['korte_ids'])}  "
          f"vinduesstore (>=90% af region): {len(stats['vinduesstore_ids'])}")
    print("kvalitetsgates: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
