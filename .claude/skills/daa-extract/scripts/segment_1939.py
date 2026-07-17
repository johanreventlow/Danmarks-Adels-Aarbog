#!/usr/bin/env python3
"""Deterministisk narrative-segmentering for 1939-Reventlow-stamtavlen.

Binder hver post i linked_clean.json til dens ordrette prosa fra raw.txt.

Design (bevidst simpelt — ingen LIS-alignment, ingen manuelle passes):

1. ANKER-SNIT: hver post proever sine ankre (foedsel/doed/begravelse
   date_raw, partner-navne) i sit vindues side-region af raw.txt.
   Matching er OCR-normaliseret (whitespace fjernet, lowercase, dagger->t).
   Kun VINDUE-UNIKKE ankre bruges. Ankrede poster sorteres paa
   ankerposition i dokumentorden; teksten snittes ved linjestart af
   hvert anker, cappet ved postens vindue-region.
2. GRUPPE-FALLBACK: ankerloese poster faar hele gruppens (_ctx.gruppe)
   tekstblok (span over gruppens ankrede medlemmer). Over-inklusion er
   bevidst fail-safe: narrative er fidelity-felt, ikke load-bearing.
3. VINDUE-FALLBACK: poster uden gruppe (eller gruppe uden ankrede
   medlemmer) faar hele vinduets side-region. Aldrig tom, aldrig fejl.

Output: work_1939_stamtavle/narrative_1939.json
  {_id (str): {"narrative": str, "side": int,
               "metode": "anker"|"gruppe-fallback"|"vindue-fallback"}}
Log:    work_1939_stamtavle/narrative_1939.log (metode pr. _id + stats).

Konsumenter boer behandle "vindue-fallback" som "gruppe-fallback"
(begge er over-inklusive blok-tildelinger).
"""

import bisect
import json
import os
import re
import statistics
import sys

PAGE_RE = re.compile(r"### PAGE (\d+) ###")
WINDOW_FILE_RE = re.compile(r"(window-\d+)_p(\d+)-(\d+)\.txt$")
MIN_ANCHOR_LEN = 3  # normaliserede tegn; uniqueness-krav er den reelle vagt
MIN_NARRATIVE_LEN = 20  # kortere anker-snit = naesten sikkert daarligt snit
WINDOW_SIZED_FRAC = 0.9  # narrative >= denne andel af vindue-regionen = "vinduesstor" (fallback-diagnostik)

WORK_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.dirname(os.path.abspath(__file__)))))),
    "work_1939_stamtavle",
)


# --------------------------------------------------------------- normalize

def normalize_with_map(text):
    """OCR-normaliser: lowercase, dagger->t, al whitespace fjernet.

    Returnerer (norm_text, idx) hvor idx[i] er original-offset for
    norm_text[i], saa fund kan mappes tilbage til raw-offsets.
    """
    norm = []
    idx = []
    for i, ch in enumerate(text):
        c = ch.lower()
        if c == "†":  # dagger
            c = "t"
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
        p = ae.get("partner_navn")
        if p:
            cands.append(p)
    return cands


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


def segment(posts, raw, winmap):
    """Kernefunktion (ren): posts + raw + {window-id: (p_lo, p_hi)} ->
    {_id_str: {"narrative", "side", "metode"}}. Hver post faar ikke-tom
    narrative — via fallback om noedvendigt."""
    pages = parse_pages(raw)
    nraw, nidx = normalize_with_map(raw)

    regions = {}  # _id -> (lo, hi) vindue-region
    anchor_pos = {}  # _id -> original-offset
    seen_positions = set()

    for post in posts:
        pid = post["_id"]
        p_lo, p_hi = winmap[post["_window"]]
        regions[pid] = page_region(pages, len(raw), p_lo, p_hi)
        lo, hi = regions[pid]
        for cand in collect_anchors(post):
            pos = find_unique_anchor(nraw, nidx, cand, lo, hi)
            if pos is None:
                continue
            start = _line_start(raw, pos)
            if start in seen_positions:
                continue  # kollision: foerste post beholder ankeret
            seen_positions.add(start)
            anchor_pos[pid] = start
            break

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
        if end > start:
            spans[pid] = (start, end)

    # Gruppe-blokke: span over ankrede medlemmer pr. (linje, gruppe)
    def gkey(post):
        ctx = post.get("_ctx") or {}
        g = ctx.get("gruppe")
        if not g:
            return None
        return (ctx.get("linje") or "", g)

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
        # Kaskade (fail-safe, over-inklusiv): anker -> gruppe -> vindue.
        # For korte snit (naesten sikkert daarlige) demoteres nedad.
        candidates = []
        if pid in spans:
            candidates.append(("anker", spans[pid]))
        if key is not None and key in group_spans:
            candidates.append(("gruppe-fallback", group_spans[key]))
        candidates.append(("vindue-fallback", regions[pid]))

        metode, narrative, s = candidates[-1][0], "", candidates[-1][1][0]
        for m, (cs, ce) in candidates:
            text = _strip_markers(raw[cs:ce])
            if len(text) >= MIN_NARRATIVE_LEN:
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
    pages = parse_pages(raw)
    by_metode = {"anker": 0, "gruppe-fallback": 0, "vindue-fallback": 0}
    empty = 0
    r_hit = r_total = 0
    lengths = []
    short = []
    window_sized = []
    region_len = {}
    for wid, (lo, hi) in winmap.items():
        a, b = page_region(pages, len(raw), lo, hi)
        region_len[wid] = b - a
    for post in posts:
        pid = str(post["_id"])
        rec = result[pid]
        by_metode[rec["metode"]] += 1
        n = rec["narrative"]
        if not n.strip():
            empty += 1
        nnorm, _ = normalize_with_map(n)
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
    return {
        "metode": by_metode,
        "tomme": empty,
        "r_proxy_hit": r_hit,
        "r_proxy_total": r_total,
        "len_median": statistics.median(lengths) if lengths else 0,
        "len_mean": round(statistics.mean(lengths), 1) if lengths else 0,
        "korte_ids": short,
        "vinduesstore_ids": window_sized,
    }


def main():
    work = sys.argv[1] if len(sys.argv) > 1 else WORK_DIR
    with open(os.path.join(work, "raw.txt"), encoding="utf-8") as f:
        raw = f.read()
    with open(os.path.join(work, "linked_clean.json"), encoding="utf-8") as f:
        posts = json.load(f)
    winmap = _load_winmap(os.path.join(work, "windows"))

    result = segment(posts, raw, winmap)
    stats = compute_stats(posts, result, winmap, raw)

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


if __name__ == "__main__":
    main()
