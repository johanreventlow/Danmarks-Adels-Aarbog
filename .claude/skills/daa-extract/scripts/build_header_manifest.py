#!/usr/bin/env python3
"""Overskriftsmanifest for 2018-20 (#150, trin 5c-1): overskrifter som kildebundne observationer.

2018-20's overskrifter (linje: romertal + »DEN … LINJE«; slægtled; kuld-romertal; ægteskabskontekst
»… med X:«) står mellem posterne. Manifestet giver hver overskrift et renditionsabsolut tegnspænd
(samme offset-kontrakt som build_source_evidence_manifest: code points i den dekodede tekst, og
project_rendition(text[char_from:char_to]) = verbatim_text) og hver post et placeringsforslag efter
reglen »nærmeste foregående overskrift pr. niveau, hvor et højere niveau annullerer de lavere«
(linje > slægtled > kuld > ægteskab). Det er strengere end segment.py, der kun nulstiller ved
linjeskift; uenighed med legacy går derfor til review (status unresolved), aldrig »legacy vinder«.

Deterministisk; ingen netværk, ingen model. Manifestet rummer overskrifternes tekst (ægteskabs-
overskrifter nævner levende ægtefæller) og må kun ligge under ~/.private; summary() er det eneste,
der må vises i chat eller rapporter.
"""
from __future__ import annotations

import argparse
import bisect
import contextlib
import difflib
import hashlib
import io
import json
import math
import os
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

import segment
from build_source_evidence_manifest import project_rendition
from ordinals import ordinal_to_int
from rendition_occurrences_1939 import CALAMARI_R6_TO_PDF_V1, _map_pdf_page

PAGE_MAPS = {'CALAMARI_R6_TO_PDF_V1': CALAMARI_R6_TO_PDF_V1}
# Fællesstammens romertal med familiebogstav (»IV A.«), centreret som stammens øvrige romertal.
STAMME_BOGSTAV_1939_RE = re.compile(r'^\s{10,}([IVXLivxl]{1,6})\s+([A-D])\.?\s*$')

HEADER_RULE_VERSION = 'header-2018-20-v1'
LEVELS = ('linje', 'slaegtled', 'kuld', 'aegteskab')
LEGACY_FIELDS = ('linje', 'nr', 'slaegtled_lokal', 'slaegtled_gennem', 'kuld')
ROMAN_VALUES = {'I': 1, 'V': 5, 'X': 10}
# Bogens kollektive opslag over flere numre (»95.-97. Ord.«): ingen person, men det dækker et nr-hul.
RANGE_RE = re.compile(r'^\s*(\d{1,4})\.\s*[-–]\s*(\d{1,4})\.\s')


class HeaderManifestError(ValueError):
    pass


def roman_to_int(roman: str) -> int:
    total = 0
    for char, nxt in zip(roman, roman[1:] + ' '):
        value = ROMAN_VALUES[char]
        total += -value if ROMAN_VALUES.get(nxt, 0) > value else value
    return total


def _span(line: str, base: int) -> tuple[int, int]:
    stripped = line.lstrip()
    start = base + len(line) - len(stripped)
    return start, start + len(stripped.rstrip())


def _is_branch(lines: list[str], i: int) -> bool:
    """Samme afgørelse som segment._segment_2018_20: et romertal er en linje, kun hvis
    linjenavnet følger."""
    j = segment.significant(lines, i + 1)
    nxt = lines[i + 1] if i + 1 < len(lines) else ''
    return bool(segment.LINJE_NAME.search(nxt)) or (
        j is not None and any(segment.LINJE_NAME.search(lines[k]) for k in range(i + 1, j + 1)))


def _header(kind: str, text: str, char_from: int, char_to: int, page_from: int | None,
            page_to: int | None, parsed: dict[str, Any]) -> dict[str, Any]:
    if page_from is None or page_to is None:
        raise HeaderManifestError('HEADER_PAGE_MISSING')
    verbatim = project_rendition(text[char_from:char_to])[0]
    return {
        'element_id': f'header:{char_from}', 'kind': kind,
        'page_from': page_from, 'page_to': page_to, 'char_from': char_from, 'char_to': char_to,
        'verbatim_text': verbatim,
        'verbatim_sha256': hashlib.sha256(verbatim.encode('utf-8')).hexdigest(),
        'parsed': parsed,
    }


def _scan(text: str) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    """Overskrifter, poster og nr-intervaller i dokumentorden; hver post bærer de aktive overskrifter."""
    lines = text.split('\n')
    bases, pages, cursor, page = [], [], 0, None
    for line in lines:
        bases.append(cursor)
        cursor += len(line) + 1
        m = segment.PAGE_RE.match(line)
        if m:
            page = int(m.group(1))
        pages.append(page)

    headers: list[dict[str, Any]] = []
    posts: list[dict[str, Any]] = []
    ranges: list[dict[str, Any]] = []
    active: dict[str, dict[str, Any]] = {}
    consumed: set[int] = set()

    def activate(level: str, header: dict[str, Any]) -> None:
        for lower in LEVELS[LEVELS.index(level):]:
            active.pop(lower, None)
        active[level] = header
        headers.append(header)

    for i, line in enumerate(lines):
        if i in consumed or segment.PAGE_RE.match(line) or not line.strip() \
                or segment.NOISE_RE.match(line):
            continue
        char_from, char_to = _span(line, bases[i])
        if segment.LINJE_NAME.search(line):          # linjenavn uden romertal: intet entry
            activate('linje', _header('header_linje', text, char_from, char_to, pages[i], pages[i],
                                      {'roman': None}))
            continue
        m = segment.ROMAN_RE.match(line)
        if m:
            if _is_branch(lines, i):
                j = segment.significant(lines, i + 1)
                last = max(k for k in range(i + 1, (j if j is not None else len(lines)))
                           if segment.LINJE_NAME.search(lines[k]))
                consumed.update(k for k in range(i + 1, last + 1) if segment.LINJE_NAME.search(lines[k]))
                activate('linje', _header('header_linje', text, char_from, _span(lines[last], bases[last])[1],
                                          pages[i], pages[last], {'roman': m.group(1)}))
            else:
                activate('kuld', _header('header_kuld', text, char_from, char_to, pages[i], pages[i],
                                         {'kuld': m.group(1)}))
            continue
        m = segment.SLGT_RE.match(line)
        if m:
            activate('slaegtled', _header('header_slaegtled', text, char_from, char_to, pages[i], pages[i], {
                'ordinal': ordinal_to_int(m.group(1)), 'label_raw': m.group(1),
                'gennem': ordinal_to_int(m.group(2)) if m.group(2) else None}))
            continue
        if segment.MARR_RE.match(line):
            activate('aegteskab', _header('header_aegteskab', text, char_from, char_to, pages[i], pages[i], {}))
            continue
        m = segment.POST_RE.match(line)
        if m:
            posts.append({'nr': int(m.group(2)), 'nr_label': m.group(2) + m.group(3),
                          'page': pages[i], 'active': dict(active)})
            continue
        m = RANGE_RE.match(line)
        if m and 'linje' in active:
            ranges.append({'lo': int(m.group(1)), 'hi': int(m.group(2)),
                           'linje': active['linje']['element_id'], 'after_posts': len(posts)})
    return headers, posts, ranges


def _numbers_consecutive(seq: list[tuple[int, int]]) -> bool:
    """seq = (fra, til) i dokumentorden: en post er (nr, nr), et interval (lo, hi). Start i 1;
    en post må gentage forrige nr (15a/15b); et interval skal begynde lige efter forrige nr."""
    prev, prev_is_post = 0, False
    for lo, hi in seq:
        is_post = lo == hi
        if not (lo == prev + 1 or (is_post and prev_is_post and lo == prev)) or hi < lo:
            return False
        prev, prev_is_post = hi, is_post
    return True


def _invariants(headers: list[dict[str, Any]], posts: list[dict[str, Any]],
                ranges: list[dict[str, Any]], entry_codes: list[str]) -> dict[str, bool]:
    linje_romans = [h['parsed']['roman'] for h in headers if h['kind'] == 'header_linje']
    ordinals: dict[str, list] = {}
    kuld: dict[str, list] = {}
    linje = None
    slaegtled = None
    for h in headers:
        if h['kind'] == 'header_linje':
            linje, slaegtled = h['element_id'], None
        elif h['kind'] == 'header_slaegtled':
            slaegtled = h['element_id']
            ordinals.setdefault(linje, []).append(h['parsed']['ordinal'])
        elif h['kind'] == 'header_kuld':
            kuld.setdefault(f'{linje}/{slaegtled}', []).append(roman_to_int(h['parsed']['kuld']))
    numbers: dict[str, list[tuple[int, int, int]]] = {}
    keys = []
    for index, p in enumerate(posts):
        if 'linje' in p['active']:
            numbers.setdefault(p['active']['linje']['element_id'], []).append((index, p['nr'], p['nr']))
        keys.append(p['record_key'])
    for r in ranges:  # et interval efter post k står før post k+1
        numbers.setdefault(r['linje'], []).append((r['after_posts'] - 0.5, r['lo'], r['hi']))
    return {
        'linje_overskrifter_svarer_til_entries': linje_romans == list(entry_codes),
        'poster_har_linje': all(p['entry_code'] is not None for p in posts),
        'slaegtled_fortloebende': all(None not in seq and all(b == a + 1 for a, b in zip(seq, seq[1:]))
                                      for seq in ordinals.values()),
        'kuld_stigende': all(all(b > a for a, b in zip(seq, seq[1:])) for seq in kuld.values()),
        'nr_fortloebende': all(_numbers_consecutive([(lo, hi) for _, lo, hi in sorted(seq)])
                               for seq in numbers.values()),
        'record_keys_unikke': len(keys) == len(set(keys)),
    }


def build_manifest(rendition_bytes: bytes, profile: dict[str, Any],
                   legacy: list[dict[str, Any]],
                   parents: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    """parents: 5b-bundne forælder-barn-par som {child, parent} record_keys. Barn og forælder i samme linje
    skal stå præcis ét slægtled fra hinanden; ellers unresolved (et skift uden overskrift midt i et slægtled
    ses ikke af legacy, der er samme læsning af teksten)."""
    if profile.get('grammar', '2018-20') != '2018-20':
        raise HeaderManifestError('HEADER_GRAMMAR_NEEDS_GUIDE')   # 1939: build_manifest_by_offset
    expected_sha = profile.get('raw_text_sha256')
    if expected_sha is not None and hashlib.sha256(rendition_bytes).hexdigest() != expected_sha:
        raise HeaderManifestError('HEADER_RENDITION_SHA_MISMATCH')
    entry_codes = list(profile['entry_codes'])
    headers, posts, ranges = _scan(rendition_bytes.decode('utf-8'))
    legacy_by_key = {row['record_key']: row for row in legacy}

    placements = []
    disagreements = []
    for post in posts:
        active = post['active']
        linje = active.get('linje', {}).get('parsed', {}).get('roman')
        slaegtled = active.get('slaegtled')
        kuld = active.get('kuld')
        record_key = f"{linje}-{post['nr_label']}" if linje else None
        post['record_key'] = record_key
        post['entry_code'] = linje if linje in entry_codes else None
        reasons = []
        if post['entry_code'] is None:
            reasons.append('mangler_linje')
        if slaegtled is None:
            reasons.append('umarkeret_slaegtled')
        values = {
            'linje': post['entry_code'], 'nr': post['nr'],
            'slaegtled_lokal': slaegtled['parsed']['ordinal'] if slaegtled else None,
            'slaegtled_gennem': slaegtled['parsed']['gennem'] if slaegtled else None,
            'kuld': kuld['parsed']['kuld'] if kuld else None,
        }
        row = legacy_by_key.get(record_key)
        if row is None:
            reasons.append('mangler_legacy')
        else:
            # Uden slægtledsoverskrift er generationen ukendt (allerede unresolved); den
            # sammenlignes ikke, så legacy-værdien aldrig bliver et argument.
            for field in LEGACY_FIELDS:
                if slaegtled is None and field.startswith('slaegtled_'):
                    continue
                if row.get(field) != values[field]:
                    reasons.append(f'uenig:{field}')
                    disagreements.append({'record_key': record_key, 'field': field})
        header_ids = {level: active[level]['element_id'] for level in LEVELS if level in active}
        placements.append({
            'record_key': record_key,
            'entry_code': post['entry_code'],
            'printed_number': post['nr_label'],
            'page': post['page'],
            'generation_local': values['slaegtled_lokal'],
            'generation_label_raw': slaegtled['parsed']['label_raw'] if slaegtled else None,
            'generation_global': values['slaegtled_gennem'],
            'kuld_label': values['kuld'],
            'section_path': [header_ids[level] for level in LEVELS if level in header_ids],
            'header_ids': header_ids,
            'status': 'unresolved' if reasons else 'machine_ok',
            'reasons': reasons,
        })

    by_key = {p['record_key']: p for p in placements}
    flagged: set[str] = set()
    for pair in parents or []:
        child, parent = by_key.get(pair['child']), by_key.get(pair['parent'])
        if child is None or parent is None or child['entry_code'] != parent['entry_code'] \
                or child['generation_local'] is None or parent['generation_local'] is None:
            continue
        if child['generation_local'] != parent['generation_local'] + 1 and child['record_key'] not in flagged:
            flagged.add(child['record_key'])
            child['reasons'].append('uenig:foraelder_generation')
            child['status'] = 'unresolved'
            disagreements.append({'record_key': child['record_key'], 'field': 'foraelder_generation'})

    rendered = {p['record_key'] for p in placements}
    for key in sorted(set(legacy_by_key) - rendered):
        disagreements.append({'record_key': key, 'field': 'mangler_i_rendition'})

    return {
        'header_rule_version': profile.get('header_rule_version', HEADER_RULE_VERSION),
        'headers': headers,
        'placements': placements,
        'invariants': _invariants(headers, posts, ranges, entry_codes),
        'disagreements': sorted(disagreements, key=lambda d: (str(d['record_key']), d['field'])),
    }


# ---------------------------------------------------------------------------------------------
# 1939 (trin 6d-1): overskrifter findes i en GUIDE-tekst (centreret OCR, hvor segment.py's 1939-
# grammatik virker) og genfindes i RENDITIONEN (ucentreret Calamari, som basen gemmer som evidens)
# mellem de samme alignede naboposter. Værdier udledes af renditionen; guiden er kun sporbarhed.
# ---------------------------------------------------------------------------------------------
ROMAN_VALUES_1939 = {'I': 1, 'V': 5, 'X': 10, 'L': 50}
ROMAN_ALONE_1939_RE = re.compile(r'^([IVXL]{1,6})[.,]?$', re.I)
ROMAN_PREFIX_1939_RE = re.compile(r'^([IVXL]{1,6})[.,]?\s+\S', re.I)
GUIDE_LEVELS_1939 = ('linje', 'slaegtled', 'kuld')


def _letters(value: str) -> str:
    return ''.join(c for c in value.lower() if c.isalpha())


def _roman_value_1939(roman: str) -> int | None:
    if not roman or any(c not in ROMAN_VALUES_1939 for c in roman):
        return None
    total = 0
    for char, nxt in zip(roman, roman[1:] + ' '):
        value = ROMAN_VALUES_1939[char]
        total += -value if ROMAN_VALUES_1939.get(nxt, 0) > value else value
    return total


def load_header_profile(path: str | Path) -> dict[str, Any]:
    profile = json.loads(Path(path).read_text(encoding='utf-8'))
    if profile.get('grammar') not in segment.UDGAVE_PROFILER:
        raise HeaderManifestError('HEADER_PROFILE_GRAMMAR_UNKNOWN')
    return profile


def _text_table(text: str) -> dict[str, Any]:
    """Linjer (som segment: str.splitlines), linjestart, side pr. linje. Offsets er code points."""
    lines = text.splitlines()
    bases, cursor = [], 0
    for raw in text.splitlines(True):
        bases.append(cursor)
        cursor += len(raw)
    pages, page = [], None
    for line in lines:
        m = segment.PAGE_RE.match(line)
        if m:
            page = int(m.group(1))
        pages.append(page)
    return {'lines': lines, 'bases': bases, 'pages': pages, 'size': len(text)}


def _lokal_id_1939(linje, slaegtled, afsnit, nr_label, pre_label) -> str | None:
    """Samme regel som segment._flush_1939."""
    if pre_label and str(linje or '').startswith(pre_label):
        return f'{linje}.{afsnit}.{nr_label}' if afsnit else None
    if linje and slaegtled:
        dele = [linje, slaegtled]
        if afsnit:
            dele.append(afsnit)
        dele.append(nr_label)
        return '.'.join(dele)
    return None


def _scan_1939(text: str, gp: dict[str, Any], stamme_afsnit_level: str | None) -> dict[str, Any]:
    """Overskrifter og poster i dokumentorden. Tilstandsovergangene spejler segment._segment_1939
    (samme rækkefølge, samme hjælpere); kun det, der ikke påvirker state, er udeladt."""
    tab = _text_table(text)
    lines, bases, pages = tab['lines'], tab['bases'], tab['pages']
    pre_label = gp.get('pre_linje_label')
    linje = pre_label
    slaegtled = afsnit = None
    stamtavle_startet = False
    afsnit_frisk = False
    side_naerhed = 0
    h_linje = h_slg = h_grp = None
    posts_since_roman = 0          # poster under det nuværende stamme-romertal
    headers: list[dict[str, Any]] = []
    posts: list[dict[str, Any]] = []
    visited: list[int] = []
    snapshots: list[tuple[Any, Any, Any]] = []

    def guide_ref(i_from: int, i_to: int) -> dict[str, Any]:
        cf = _span(lines[i_from], bases[i_from])[0]
        ct = _span(lines[i_to], bases[i_to])[1]
        joined = segment.norm(' '.join(lines[k].strip() for k in range(i_from, i_to + 1)))
        return {'char_from': cf, 'line_sha256': hashlib.sha256(joined.encode('utf-8')).hexdigest()}

    def add(level: str, i_from: int, i_to: int, **kw: Any) -> int:
        h = {'gid': len(headers), 'level': level, 'line_from': i_from, 'line_to': i_to,
             'posts_before': len(posts), 'guide': guide_ref(i_from, i_to), **kw}
        headers.append(h)
        return h['gid']

    i = 0
    while i < len(lines):
        line = lines[i]
        visited.append(i)
        snapshots.append((h_linje, h_slg, h_grp))
        m = gp['page_re'].match(line)
        if m:
            side_naerhed = gp['page_noise_window']
            i += 1
            continue
        if not line.strip():
            i += 1
            continue
        if side_naerhed:
            side_naerhed -= 1
            if gp['page_noise_re'].match(line):
                i += 1
                continue

        linje_header = segment._linje_header_1939(lines, i, gp)
        if linje_header:
            linje, forbrug = linje_header
            stamtavle_startet = True
            slaegtled = afsnit = None
            afsnit_frisk = False
            h_linje = add('linje', i, i + 1, roman=linje, stamme_slug=None, entry_code=linje,
                          name_norm=_letters(lines[i + 1]))
            h_slg = h_grp = None
            posts_since_roman = 0
            i += forbrug
            continue

        if not stamtavle_startet and pre_label:
            m = gp['stamme_sektion_re'].match(line)
            if m:
                slug = re.sub(r'[^\wÆØÅæøå]+', '-', (m.group(1) or m.group(2)), flags=re.UNICODE).strip('-')
                linje = f'{pre_label}-{slug}'
                afsnit = None
                afsnit_frisk = False
                h_linje = add('linje', i, i, roman=None, stamme_slug=slug, entry_code=linje, name_norm=None)
                h_grp = None
                if h_slg is not None and headers[h_slg].get('stamme_roman'):
                    h_slg = None                 # stammens romertal gælder kun inden for sektionen (som afsnit=None)
                posts_since_roman = 0
                i += 1
                continue

        slaegtled_header = segment._slaegtled_header_1939(
            line, gp, fresh_page=(i > 0 and bool(gp['page_re'].match(lines[i - 1]))))
        if slaegtled_header:
            slaegtled, _ukendt = slaegtled_header
            afsnit = None
            afsnit_frisk = False
            h_slg = add('slaegtled', i, i, label=slaegtled, ordinal=ordinal_to_int(slaegtled),
                        stamme_roman=False)
            h_grp = None
            i += 1
            continue

        m = gp['afsnit_re'].match(line)
        if m:
            afsnit = segment._normaliser_romertal_1939(m.group(1), gp)
            afsnit_frisk = True
            if stamme_afsnit_level == 'slaegtled' and str(linje or '').startswith(pre_label or '\0'):
                # stammens romertal er slægtleddet: det ligger i slægtleds-sporet, så en senere kuld-beskrivelse
                # (der erstatter h_grp) ikke fjerner det
                h_slg = add('slaegtled', i, i, label=afsnit, ordinal=_roman_value_1939(afsnit),
                            stamme_roman=True)
                h_grp = None
                posts_since_roman = 0
            else:
                h_grp = add('kuld', i, i, roman=afsnit, slug=None, desc_norm=None, desc_i=None)
            i += 1
            continue

        beskrivelse = segment._gruppebeskrivelse_1939(lines, i, gp)
        if beskrivelse:
            slug, forbrug = beskrivelse
            kb = next((k for k in range(i, i + forbrug - 1) if STAMME_BOGSTAV_1939_RE.match(lines[k])), None)
            if (kb is not None and stamme_afsnit_level == 'slaegtled'
                    and str(linje or '').startswith(pre_label or '\0')):
                # Segmenteren læser »IV A.« + beskrivelsen (evt. med postens sidste prosalinje foran, når der ikke
                # står en tom linje) som én beskrivelse (afsnit = slug, uændret nedenfor); overskriftssporet deler
                # den: bogstavlinjen er stammens slægtled, linjerne efter den er gruppen, prosaen foran ignoreres.
                mb = STAMME_BOGSTAV_1939_RE.match(lines[kb])
                roman = segment._normaliser_romertal_1939(mb.group(1).upper(), gp)
                h_slg = add('slaegtled', kb, kb, label=roman, ordinal=_roman_value_1939(roman), stamme_roman=True,
                            bogstav=mb.group(2))
                h_grp = None
                posts_since_roman = 0
                tekst = segment.norm(' '.join(lines[k].strip() for k in range(kb + 1, i + forbrug)))
                if not afsnit_frisk:
                    afsnit = slug
                    h_grp = add('kuld', kb + 1, i + forbrug - 1, roman=None, slug=slug, desc_norm=_letters(tekst),
                                desc_i=kb + 1, usikker=False)
                i += forbrug
                continue
            tekst = segment.norm(' '.join(lines[k].strip() for k in range(i, i + forbrug)))
            if not afsnit_frisk:
                afsnit = slug
                # stammen: en beskrivelse efter poster under romertallet uden nyt romertal kan være samme eller næste
                # generation (romertal tabt i OCR) -> generationen er usikker
                usikker = (str(linje or '').startswith(pre_label or '\0') and posts_since_roman >= 1)
                h_grp = add('kuld', i, i + forbrug - 1, roman=None, slug=slug,
                            desc_norm=_letters(tekst), desc_i=i, usikker=usikker)
            elif h_grp is not None and headers[h_grp]['level'] == 'kuld':
                headers[h_grp].update(slug=slug, desc_norm=_letters(tekst), desc_i=i,
                                      desc_to=i + forbrug - 1)
            i += forbrug
            continue

        post_start = segment._post_start_1939(line, gp)
        if post_start:
            pm, _usikker = post_start
            afsnit_frisk = False
            posts_since_roman += 1
            nr_label = pm.group(2) + pm.group(3)
            gid_slg = h_slg
            gid_kuld = h_grp if h_grp is not None and headers[h_grp]['level'] == 'kuld' else None
            posts.append({
                'nr': int(pm.group(2)), 'nr_label': nr_label, 'page': pages[i], 'line': i,
                'char_from': bases[i], 'linje': linje, 'slaegtled': slaegtled, 'afsnit': afsnit,
                'lokal_id': _lokal_id_1939(linje, slaegtled, afsnit, nr_label, pre_label),
                'h_linje': h_linje, 'h_slg': gid_slg, 'h_kuld': gid_kuld,
            })
        i += 1
    return {'tab': tab, 'headers': headers, 'posts': posts, 'visited': visited, 'snapshots': snapshots}


def _guide_v2_posts_1939(text: str) -> list[dict[str, Any]]:
    """raw.txt's v2-poster (nummererede + stamfædre + oversigtsposter) i guide-orden."""
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        posts = segment._segment_1939_v2(text.splitlines(), segment.UDGAVE_PROFILER['1939-v2'])
    out = [{'fra': p['linjer']['fra'], 'klasse': p.get('postklasse', 'nummereret'),
            'lokal_id': p.get('lokal_id'), 'nr_label': p.get('nr_label')} for p in posts]
    return sorted(out, key=lambda x: x['fra'])


def _guide_state_at(guide: dict[str, Any], line: int) -> dict[str, Any]:
    """Overskrifts-gid'er (linje, slægtled, kuld) gældende ved guide-linje `line`."""
    k = bisect.bisect_right(guide['visited'], line) - 1
    h_linje, h_slg, h_grp = guide['snapshots'][k] if k >= 0 else (None, None, None)
    grp = guide['headers'][h_grp] if h_grp is not None else None
    return {'h_linje': h_linje,
            'h_slg': h_slg,
            'h_kuld': h_grp if grp and grp['level'] == 'kuld' else None}


def _segmenter_lokal_ids_1939(text: str, gp: dict[str, Any]) -> list[str | None]:
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        posts = segment._segment_1939(text.splitlines(), gp)
    return [p.get('lokal_id') for p in posts]


def _next_sig(lines: list[str], i: int) -> int | None:
    j = i + 1
    while j < len(lines) and not lines[j].strip():
        j += 1
    return j if j < len(lines) else None


RECORD_NR_1939_RE = re.compile(r'^\s{0,6}\??\s{0,2}(\d{1,3})\s*([a-z]?)\s*[.,]\s')


def _record_inside_line(tab: dict[str, Any], i: int, rec_starts: list[int]) -> bool:
    """Starter en record midt i linjen (efter linjestart)? Så deler en overskrift linje med posttekst."""
    base = tab['bases'][i]
    k = bisect.bisect_right(rec_starts, base)
    return k < len(rec_starts) and rec_starts[k] < base + len(tab['lines'][i])


def _window_1939(tab: dict[str, Any], w0: int, w1: int) -> list[int]:
    """Linjeindeks for linjer der skærer [w0, w1), uden tomme linjer og sidemarkører."""
    out = []
    i = max(bisect.bisect_right(tab['bases'], w0) - 1, 0)
    while i < len(tab['lines']) and tab['bases'][i] < w1:
        line = tab['lines'][i]
        if line.strip() and not segment.PAGE_RE.match(line):
            out.append(i)
        i += 1
    return out


def _single(cands: list) -> Any:
    """Præcis én kandidat, ellers ingen (aldrig gæt)."""
    return cands[0] if len(cands) == 1 else None


def _locate_1939(h: dict[str, Any], tab: dict[str, Any], idxs: list[int], gp: dict[str, Any]
                 ) -> dict[str, Any] | None:
    lines, bases = tab['lines'], tab['bases']

    def hit(i_from: int, i_to: int, parsed: dict[str, Any]) -> dict[str, Any]:
        return {'i_from': i_from, 'i_to': i_to, 'parsed': parsed}

    def roman_of(m) -> str:
        return segment._normaliser_romertal_1939(m.group(1).upper(), gp)

    def linje_name_follows(i: int) -> bool:
        j = _next_sig(lines, i)
        return j is not None and 'linje' in lines[j].lower() and len(lines[j].strip()) < 120

    level = h['level']
    if level == 'linje':
        if h['roman'] is not None:
            cands = []
            for i in idxs:
                s = lines[i].strip()
                m = ROMAN_ALONE_1939_RE.match(s)
                if m and roman_of(m) == h['roman'] and linje_name_follows(i):
                    cands.append((i, _next_sig(lines, i)))
                    continue
                m = ROMAN_PREFIX_1939_RE.match(s)
                if m and roman_of(m) == h['roman'] and len(s) <= 80 and 'linje' in s.lower():
                    cands.append((i, i))
            if len(cands) > 1:
                return None
            if cands:
                return hit(*cands[0], {'roman': h['roman'], 'stamme_slug': None,
                                       'entry_code': h['entry_code'], 'found_via': 'roman'})
            if h['name_norm']:
                name = _single([i for i in idxs if _letters(lines[i]) == h['name_norm']])
                if name is not None:       # romertallet mangler: kun navnet bærer beviset
                    return hit(name, name, {'roman': h['roman'], 'stamme_slug': None,
                                            'entry_code': h['entry_code'], 'found_via': 'navn'})
            return None
        words = [_letters(w) for w in h['stamme_slug'].split('-') if _letters(w)]
        cands = []
        for i in idxs:
            ln = _letters(lines[i])
            if len(lines[i].strip()) < 60 and 'linje' in ln and all(w in ln for w in words):
                cands.append(i)
        c = _single(cands)
        if c is None:
            return None
        return hit(c, c, {'roman': None, 'stamme_slug': h['stamme_slug'],
                          'entry_code': h['entry_code'], 'found_via': 'stamme'})

    if level == 'slaegtled' and not h['stamme_roman']:
        want = _letters(h['label'])
        cands = []
        for i in idxs:
            ln = _letters(lines[i])
            if (ln.startswith(want) and 'slægtled' in ln and len(ln) < 30
                    and not segment._post_start_1939(lines[i], gp)):
                cands.append(i)
        c = _single(cands)
        if c is None:
            return None
        return hit(c, c, {'ordinal': h['ordinal'], 'label_raw': h['label'], 'gennem': None})

    if level == 'slaegtled' and h.get('bogstav'):
        cands = []
        for i in idxs:
            mb = STAMME_BOGSTAV_1939_RE.match(' ' * 10 + lines[i].strip())
            if mb and roman_of(mb) == h['label'] and mb.group(2) == h['bogstav']:
                cands.append(i)
        c = _single(cands)
        if c is None:
            return None
        return hit(c, c, {'ordinal': h['ordinal'], 'label_raw': f"{h['label']} {h['bogstav']}", 'gennem': None,
                          'roman': h['label']})

    # romertal-grupper (kuld, eller stammens slægtled-romertal) og gruppebeskrivelser
    roman = h['label'] if level == 'slaegtled' else h['roman']
    if roman is not None:
        cands = []
        for i in idxs:
            m = ROMAN_ALONE_1939_RE.match(lines[i].strip())
            if m and roman_of(m) == roman and not linje_name_follows(i):
                cands.append(i)
        c = _single(cands)
        if c is not None:
            if level == 'slaegtled':
                return hit(c, c, {'ordinal': h['ordinal'], 'label_raw': roman, 'gennem': None,
                                  'roman': roman})
            return hit(c, c, {'kuld': roman, 'found_via': 'roman'})
    if level == 'kuld' and h.get('desc_norm'):
        return _locate_beskrivelse_1939(h, tab, idxs)
    return None


def _locate_beskrivelse_1939(h: dict[str, Any], tab: dict[str, Any], idxs: list[int]
                             ) -> dict[str, Any] | None:
    lines = tab['lines']
    chars: list[str] = []
    owner: list[int] = []
    for i in idxs:
        for c in lines[i].lower():
            if c.isalpha():
                chars.append(c)
                owner.append(i)
    a = h['desc_norm'][:60]
    need = max(15, math.ceil(0.6 * len(a)))
    if len(a) < need:
        return None
    b = ''.join(chars)
    best = difflib.SequenceMatcher(None, a, b, autojunk=False).find_longest_match(0, len(a), 0, len(b))
    if best.size < need:
        return None
    masked = b[:best.b] + '\x00' * best.size + b[best.b + best.size:]
    second = difflib.SequenceMatcher(None, a, masked, autojunk=False).find_longest_match(
        0, len(a), 0, len(masked))
    if second.size >= need:
        return None                      # to steder: aldrig gæt
    i_from, i_to = owner[best.b], owner[best.b + best.size - 1]
    return {'i_from': i_from, 'i_to': i_to,
            'parsed': {'kuld': _beskrivelse_slug(lines, i_from, i_to), 'found_via': 'beskrivelse'}}


def _beskrivelse_slug(lines: list[str], i_from: int, i_to: int) -> str:
    tekst = segment.norm(' '.join(lines[k].strip() for k in range(i_from, i_to + 1)))
    return re.sub(r'[^\wÆØÅæøå]+', '-', tekst.rstrip(':'), flags=re.UNICODE).strip('-')


def _guide_value(h: dict[str, Any]) -> str | int | None:
    """Sporbarhedsværdi uden tekst: romertal (linje/kuld) eller ordinaltal (slægtled), ellers None."""
    if h['level'] == 'slaegtled':
        return h['ordinal']
    return h['roman']


def _align_1939(g_posts: list[dict[str, Any]], r_posts: list[dict[str, Any]]) -> dict[int, int]:
    sm = difflib.SequenceMatcher(None, [p['nr_label'] for p in g_posts],
                                 [p['nr_label'] for p in r_posts], autojunk=False)
    pairs = {}
    for a, b, n in sm.get_matching_blocks():
        for k in range(n):
            pairs[a + k] = b + k
    return pairs


def _v2_slaegtled_ordinal(lokal_id: str | None) -> int | None:
    """Slægtleddet i en v2-lokal_id (»Stamme-x.I.U1« → 1, »I.Første.U1« → 1); None hvis det ikke kan læses."""
    parts = (lokal_id or '').split('.')
    if len(parts) < 3:
        return None
    value = _roman_value_1939(parts[1])
    return value if value is not None else ordinal_to_int(parts[1])


def _oversigtszoner(text: str, zoner: list[dict[str, Any]]) -> list[tuple[int, int]]:
    """Nedstigningsoversigternes tegnintervaller [start, slut) i `text`.

    Hvert anker er en ordfølge, der skal forekomme præcis én gang (vilkårligt mellemrum/linjeskift mellem ordene);
    slut-ankeret er inklusivt og skal ligge efter start-ankeret. Ellers HEADER_OVERSIGTSZONE_ANKER (fail-closed)."""
    out = []
    for z in zoner:
        hits = []
        for anker in (z['start'], z['slut']):
            pat = re.compile(r'\s+'.join(re.escape(w) for w in anker.split()))
            found = list(pat.finditer(text))
            if len(found) != 1:
                raise HeaderManifestError('HEADER_OVERSIGTSZONE_ANKER')
            hits.append(found[0])
        if hits[1].start() <= hits[0].start():
            raise HeaderManifestError('HEADER_OVERSIGTSZONE_ANKER')
        out.append((hits[0].start(), hits[1].end()))
    return out


def _i_zone(char_from: int, zoner: list[tuple[int, int]]) -> bool:
    return any(a <= char_from < b for a, b in zoner)


def _check_sha(data: bytes, expected: str | None, code: str) -> None:
    if expected is not None and hashlib.sha256(data).hexdigest() != expected:
        raise HeaderManifestError(code)


def build_manifest_by_offset(rendition_bytes: bytes, guide_bytes: bytes, profile: dict[str, Any],
                             records: list[dict[str, Any]], parents: list[dict[str, Any]]
                             ) -> dict[str, Any]:
    """1939: overskrifter fra guiden genfundet i renditionen mellem alignede naboposter.

    records: {record_key, record_kind, persona (bool), page_from, char_from, legacy:{linje,nr}|None} (char_from =
    tidligste accepterede forekomst i renditionen). parents: {child, parent} record_keys."""
    _check_sha(rendition_bytes, profile.get('raw_text_sha256'), 'HEADER_RENDITION_SHA_MISMATCH')
    _check_sha(guide_bytes, profile.get('guide_text_sha256'), 'HEADER_GUIDE_SHA_MISMATCH')
    gp = segment.UDGAVE_PROFILER[profile['grammar']]
    stamme_level = profile.get('stamme_afsnit_level')
    levels = profile['levels']
    rtext, gtext = rendition_bytes.decode('utf-8'), guide_bytes.decode('utf-8')
    guide = _scan_1939(gtext, gp, stamme_level)
    g_posts, g_headers = guide['posts'], guide['headers']
    rtab = _text_table(rtext)
    if profile.get('page_map') is not None:
        # Calamari-sider -> PDF-sider: databasens forekomster i renditionen bruger PDF-sider, så overskrifter og
        # placeringer skal også (rendition_occurrences_1939.CALAMARI_R6_TO_PDF_V1, verificeret mod PDF'en 9/11).
        pmap = PAGE_MAPS.get(profile['page_map'])
        if pmap is None:
            raise HeaderManifestError('HEADER_PAGE_MAP_UNKNOWN')
        cache: dict[int, int] = {}
        rtab['pages'] = [None if p is None else cache.setdefault(p, _map_pdf_page(p, 'calamari', pmap))
                         for p in rtab['pages']]
    # Nedstigningsoversigter (1939: PDF 504-505 og 508-510) nævner personer i kort form, som har en detaljepost senere
    # i bogen. Deres nummererede punkter (»1. Geheimeraad Ditlev«) må hverken indgå i alignmentet eller i
    # hulparringen; records, der begynder i en zone, får ingen placement (decisions 2026-11-08 Gate A pkt. 3).
    zoner_spec = profile.get('oversigtszoner') or []
    r_zoner = _oversigtszoner(rtext, zoner_spec)
    g_zoner = _oversigtszoner(gtext, zoner_spec)
    # Renditionens "post" er recorden selv: en record begynder ved sin char_from med postnummeret.
    r_posts: list[dict[str, Any]] = []
    unnumbered: set[str] = set()
    in_zone: set[str] = set()
    post_index: dict[str, int] = {}
    rec_starts = sorted({r['char_from'] for r in records})
    for rec in sorted(records, key=lambda r: (r['char_from'], r['record_key'])):
        if _i_zone(rec['char_from'], r_zoner):
            in_zone.add(rec['record_key'])
            continue
        m = RECORD_NR_1939_RE.match(rtext[rec['char_from']:rec['char_from'] + 40])
        if m is None:
            unnumbered.add(rec['record_key'])
            continue
        if not r_posts or r_posts[-1]['char_from'] != rec['char_from']:   # records på samme sted = én post
            r_posts.append({'nr': int(m.group(1)), 'nr_label': m.group(1) + m.group(2),
                            'char_from': rec['char_from']})
        post_index[rec['record_key']] = len(r_posts) - 1
    g_keep = [gi for gi, p in enumerate(g_posts) if not _i_zone(p['char_from'], g_zoner)]
    align = {g_keep[a]: b for a, b in _align_1939([g_posts[gi] for gi in g_keep], r_posts).items()}
    rev_align = {r: g for g, r in align.items()}

    # --- unummererede records: parres med v2-posterne i hullet mellem alignede nummererede records ---
    gbases = guide['tab']['bases']
    v2_posts = [v for v in _guide_v2_posts_1939(gtext) if not _i_zone(gbases[v['fra']], g_zoner)]
    unnum_recs = sorted((r for r in records if r['record_key'] in unnumbered),
                        key=lambda r: (r['char_from'], r['record_key']))
    aligned_r = sorted(rev_align)
    aligned_from = [r_posts[k]['char_from'] for k in aligned_r]
    # records på samme char_from er én fysisk post (som for de nummererede)
    unnum_posts: dict[int, list[dict[str, Any]]] = {}
    for r in unnum_recs:
        unnum_posts.setdefault(r['char_from'], []).append(r)
    gaps: dict[int, list[list[dict[str, Any]]]] = {}
    for cf, group in unnum_posts.items():
        gaps.setdefault(bisect.bisect_left(aligned_from, cf), []).append(group)
    unnum_outcome: dict[str, dict[str, Any]] = {}
    for g, rn in gaps.items():
        lo = g_posts[rev_align[aligned_r[g - 1]]]['line'] if g > 0 else -1
        hi = g_posts[rev_align[aligned_r[g]]]['line'] if g < len(aligned_r) else float('inf')
        gn = [v for v in v2_posts if lo < v['fra'] < hi]
        if len(rn) == len(gn):
            for group, v in zip(rn, gn):
                for r in group:
                    unnum_outcome[r['record_key']] = {'kind': v['klasse'], 'v2': v}
        else:
            for group in rn:
                for r in group:
                    unnum_outcome[r['record_key']] = {'kind': 'uparret',
                                                      'kandidater': [v['lokal_id'] or v['nr_label'] for v in gn]}

    # --- genfind hver guide-overskrift i renditionen mellem alignede naboposter ---
    located: dict[int, dict[str, Any] | None] = {}
    used_from: set[int] = set()
    collisions = 0
    aligned_idx = sorted(align)
    for h in g_headers:
        k = h['posts_before']
        pos = bisect.bisect_left(aligned_idx, k)
        prev = aligned_idx[pos - 1] if pos > 0 else None
        nxt = aligned_idx[pos] if pos < len(aligned_idx) else None
        w1 = rtab['size'] if nxt is None else r_posts[align[nxt]]['char_from']
        w0 = 0 if prev is None else r_posts[align[prev]]['char_from']
        idxs = [i for i in _window_1939(rtab, w0, w1) if not _record_inside_line(rtab, i, rec_starts)]
        hit = _locate_1939(h, rtab, idxs, gp)
        if hit is not None and any(_record_inside_line(rtab, i, rec_starts)
                                   for i in range(hit['i_from'], hit['i_to'] + 1)):
            hit = None
        if hit is None:
            located[h['gid']] = None
            continue
        i_from, i_to = hit['i_from'], hit['i_to']
        cf = _span(rtab['lines'][i_from], rtab['bases'][i_from])[0]
        ct = _span(rtab['lines'][i_to], rtab['bases'][i_to])[1]
        if cf in used_from:
            collisions += 1
            located[h['gid']] = None
            continue
        used_from.add(cf)
        kind = levels[h['level']]
        parsed = dict(hit['parsed'])
        parsed['guide'] = {'value': _guide_value(h), 'char_from': h['guide']['char_from'],
                           'line_sha256': h['guide']['line_sha256']}
        header = _header(kind, rtext, cf, ct, rtab['pages'][i_from], rtab['pages'][i_to], parsed)
        located[h['gid']] = header
    headers = sorted((v for v in located.values() if v is not None), key=lambda x: x['char_from'])

    # --- guide-strukturelle årsager (nr-brud, slægtled-fald) ---
    post_reasons: dict[int, list[str]] = {}
    groups: dict[tuple, int] = {}
    for gi, p in enumerate(g_posts):
        key = (p['linje'], p['slaegtled'], p['afsnit'])
        prev_nr = groups.get(key)
        if prev_nr is not None and p['nr'] not in (prev_nr, prev_nr + 1):
            post_reasons.setdefault(gi, []).append('nr_ikke_fortloebende')
        groups[key] = p['nr']
    falling: set[int] = set()
    # slægtled-fald pr. linje i guidens rækkefølge (som segment: kun strengt fald tæller)
    order: list[tuple[int, str, int | None]] = []
    for h in g_headers:
        if h['level'] == 'linje':
            order.append((h['gid'], 'linje', None))
        elif h['level'] == 'slaegtled' and not h['stamme_roman']:
            order.append((h['gid'], 'slaegtled', h['ordinal']))
    last = None
    for gid, kind, ordinal in order:
        if kind == 'linje':
            last = None
        else:
            if last is not None and ordinal is not None and ordinal < last:
                falling.add(gid)
            if ordinal is not None:
                last = ordinal
    for gi, p in enumerate(g_posts):
        if p['h_slg'] in falling:
            post_reasons.setdefault(gi, []).append('slaegtled_ikke_monoton')

    # --- legacy-løbenumre: 1939's legacy-nøgle for en linje (fx VI-514) tæller poster i bogens orden og er ikke
    # gruppens trykte nummer; uenighed = et løbenummer, der ikke stiger i forhold til forrige post med samme linje ---
    legacy_nr_brud: set[str] = set()
    forrige_nr: dict[str, Any] = {}
    for rec in sorted(records, key=lambda r: (r['char_from'], r['record_key'])):
        lg = rec.get('legacy') or {}
        if lg.get('linje') in (None, '1939') or lg.get('nr') is None:
            continue
        prev = forrige_nr.get(lg['linje'])
        if prev is not None and not lg['nr'] > prev:
            legacy_nr_brud.add(rec['record_key'])
        forrige_nr[lg['linje']] = lg['nr']

    # --- records → placeringer (struktur fra den alignede guide-post) ---
    placements: list[dict[str, Any]] = []
    disagreements: list[dict[str, Any]] = []
    persona_keys: set[str] = set()
    for rec in sorted(records, key=lambda r: r['record_key']):
        reasons: list[str] = []
        base = {
            'record_key': rec['record_key'], 'entry_code': None, 'printed_number': None,
            'page': rec.get('page_from'), 'generation_local': None, 'generation_label_raw': None,
            'generation_global': None, 'kuld_label': None, 'section_path': [], 'header_ids': {},
            'record_kind': rec.get('record_kind'), 'post_char_from': None, 'guide_lokal_id': None,
            'guide_nr_label': None, 'guide_kandidater': None,
            'gruppekort': [], 'human_header_levels': [], 'naermeste_header_ids': None,
            'naermeste_entry_code': None, 'naermeste_generation_local': None, 'naermeste_kuld_label': None,
        }
        if rec['record_key'] in in_zone:
            placements.append({**base, 'status': 'unresolved', 'reasons': ['uden_post', 'oversigtszone']})
            continue
        outcome = unnum_outcome.get(rec['record_key'])
        if rec['record_key'] in unnumbered and outcome['kind'] != 'stamfader':
            kind = outcome['kind']
            if kind == 'nummereret':
                placements.append({**base, 'status': 'unresolved', 'reasons': ['nummer_tabt_i_rendition'],
                                   'guide_nr_label': outcome['v2']['nr_label']})
            elif kind == 'uparret' and rec.get('persona'):
                placements.append({**base, 'status': 'unresolved', 'reasons': ['ikke_parret'],
                                   'guide_kandidater': outcome.get('kandidater', [])})
            else:
                placements.append({**base, 'status': 'unresolved', 'reasons': ['uden_post']})
            continue
        if rec['record_key'] in unnumbered:        # parret med en stamfader: placeres uden nummer
            rpost = {'nr': None, 'nr_label': None, 'char_from': rec['char_from']}
            gi = None
            gpost = {'lokal_id': outcome['v2']['lokal_id'],
                     **_guide_state_at(guide, outcome['v2']['fra'])}
        else:
            ri = post_index[rec['record_key']]
            rpost = r_posts[ri]
            gi = rev_align.get(ri)
        line_i = max(bisect.bisect_right(rtab['bases'], rpost['char_from']) - 1, 0)
        base.update(printed_number=rpost['nr_label'], post_char_from=rpost['char_from'],
                    page=rtab['pages'][line_i] if rtab['pages'] and rtab['pages'][line_i] is not None
                    else rec.get('page_from'))
        if rec.get('persona'):
            persona_keys.add(rec['record_key'])
        if gi is None and rec['record_key'] not in unnumbered:
            placements.append({**base, 'status': 'unresolved', 'reasons': ['ikke_alignet']})
            continue
        if gi is not None:
            gpost = g_posts[gi]
        base['guide_lokal_id'] = gpost['lokal_id']
        header_ids: dict[str, str] = {}
        parsed_of: dict[str, dict[str, Any]] = {}
        cards: list[dict[str, Any]] = []
        for level, gid in (('linje', gpost['h_linje']), ('slaegtled', gpost['h_slg']),
                           ('kuld', gpost['h_kuld'])):
            if gid is None:
                if level != 'kuld':
                    reasons.append(f'overskrift_ikke_fundet:{level}')
                    v2 = (outcome or {}).get('v2') if gi is None else None
                    ordinal = _v2_slaegtled_ordinal(v2['lokal_id']) if level == 'slaegtled' and v2 else None
                    if ordinal is not None:
                        # stamfader uden guidens slægtledsoverskrift (PDF 505: »I.« læst som »1.«): v2-segmenteringen
                        # kender slægtleddet; gruppekortet lader det bekræfte mod siden
                        i = v2['fra']
                        ref = {'char_from': _span(guide['tab']['lines'][i], gbases[i])[0],
                               'line_sha256': hashlib.sha256(segment.norm(guide['tab']['lines'][i].strip())
                                                             .encode('utf-8')).hexdigest()}
                        cards.append({'id': f"slaegtled:{ref['char_from']}", 'niveau': 'slaegtled',
                                      'guide_value': ordinal, 'guide_char_from': ref['char_from'],
                                      'guide_line_sha256': ref['line_sha256']})
                continue
            header = located.get(gid)
            if header is None:
                reasons.append(f'overskrift_ikke_fundet:{level}')
                if level != 'linje':           # gruppekort: guide-overskriften, uden tekst
                    gh = g_headers[gid]
                    value = _guide_value(gh)
                    if value is None and level == 'kuld' and gh.get('desc_i') is not None:
                        # fællesstammens gruppe er en beskrivelse uden romertal (»VII C. / Lyder Reventlows Søn:«):
                        # værdien er beskrivelsens slug, som en fundet beskrivelsesoverskrift ville have givet
                        value = _beskrivelse_slug(guide['tab']['lines'], gh['desc_i'], gh['line_to'])
                    cards.append({'id': f"{level}:{gh['guide']['char_from']}", 'niveau': level,
                                  'guide_value': value, 'guide_char_from': gh['guide']['char_from'],
                                  'guide_line_sha256': gh['guide']['line_sha256']})
                continue
            header_ids[level] = header['element_id']
            parsed_of[level] = header['parsed']
        slg = parsed_of.get('slaegtled')
        base.update(
            entry_code=parsed_of['linje']['entry_code'] if 'linje' in parsed_of else None,
            generation_local=slg['ordinal'] if slg else None,
            generation_label_raw=slg['label_raw'] if slg else None,
            kuld_label=parsed_of['kuld']['kuld'] if 'kuld' in parsed_of else None,
            section_path=list(header_ids.values()), header_ids=header_ids)
        base['gruppekort'] = cards
        reasons.extend(post_reasons.get(gi, []))
        if gpost['h_kuld'] is not None and g_headers[gpost['h_kuld']].get('usikker'):
            reasons.append('stamme_generation_usikker')
        if gi is None and gpost['h_slg'] in falling:
            reasons.append('slaegtled_ikke_monoton')
        legacy = rec.get('legacy')
        if legacy and legacy.get('linje') not in (None, '1939'):
            if base['entry_code'] is not None and legacy.get('linje') != base['entry_code']:
                reasons.append('uenig:legacy_linje')
                disagreements.append({'record_key': rec['record_key'], 'field': 'legacy_linje'})
            if rec['record_key'] in legacy_nr_brud:
                reasons.append('uenig:legacy_nr')
                disagreements.append({'record_key': rec['record_key'], 'field': 'legacy_nr'})
        placements.append({**base, 'status': 'unresolved' if reasons else 'machine_ok',
                           'reasons': reasons})

    # hver persona-record er en egen person: flere i samme fysiske post = missed postgrænse
    persona_posts: dict[int, list[dict[str, Any]]] = {}
    for p in placements:
        if p['record_key'] in persona_keys and p['post_char_from'] is not None:
            persona_posts.setdefault(p['post_char_from'], []).append(p)
    for members in persona_posts.values():
        if len(members) > 1:
            for p in members:
                p['reasons'].append('flere_personas_i_post')
                p['status'] = 'unresolved'

    # selvtjek mod DB's nærmeste-regel (private.placement_header_violations) over manifestets egne overskrifter
    rank = {level: n for n, level in enumerate(('linje', 'slaegtled', 'kuld'), 1)}
    kind_level = {kind: level for level, kind in levels.items()}
    hdrs = [(rank[kind_level[h['kind']]], kind_level[h['kind']], h) for h in headers]
    def db_expected(post_from: int) -> dict[str, tuple[str, dict[str, Any]]]:
        """DB-reglens forventede overskrift pr. niveau ved post_from (nærmeste foregående; højere niveau efter annullerer)."""
        before = [(rk, lv, h) for rk, lv, h in hdrs if h['char_to'] <= post_from]
        out: dict[str, tuple[str, dict[str, Any]]] = {}
        for lv in rank:
            cand = [(rk, h) for rk, l2, h in before if l2 == lv]
            if not cand:
                continue
            rk, near = max(cand, key=lambda x: x[1]['char_from'])
            if any(rk2 < rk and h2['char_from'] > near['char_from'] for rk2, _l, h2 in before):
                continue
            out[lv] = (near['element_id'], near)
        return out

    rec_char = {r['record_key']: r['char_from'] for r in records}
    for p in placements:
        is_kort = any(r in p['reasons'] for r in ('ikke_alignet', 'ikke_parret', 'nummer_tabt_i_rendition'))
        post_from = p['post_char_from'] if p['post_char_from'] is not None else (
            rec_char[p['record_key']] if is_kort else None)
        if post_from is None:
            continue
        expected = db_expected(post_from)
        if is_kort:
            if 'linje' in expected:              # strukturkort: nærmeste overskrifter efter DB-reglen
                p['naermeste_header_ids'] = {lv: eid for lv, (eid, _h) in expected.items()}
                p['naermeste_entry_code'] = expected['linje'][1]['parsed']['entry_code']
                if 'slaegtled' in expected:
                    p['naermeste_generation_local'] = expected['slaegtled'][1]['parsed']['ordinal']
                if 'kuld' in expected:
                    p['naermeste_kuld_label'] = expected['kuld'][1]['parsed']['kuld']
            continue
        if any(r in p['reasons'] for r in ('uden_post',)):
            continue
        missing = {r.split(':', 1)[1] for r in p['reasons'] if r.startswith('overskrift_ikke_fundet:')}
        if missing - {c['niveau'] for c in p['gruppekort']}:
            continue                              # linje (eller guide uden overskrift) mangler: ingen selvtjek
        human = set(missing)
        if missing:
            # bekræftede niveauer annullerer intet; et lavere niveau uden id, som DB-reglen tildeler, er også bekræftet
            human |= {lv for lv in ('slaegtled', 'kuld') if lv not in p['header_ids'] and lv in expected}
            p['human_header_levels'] = [lv for lv in ('slaegtled', 'kuld') if lv in human]
        if {lv: eid for lv, (eid, _h) in expected.items() if lv not in human} != p['header_ids']:
            p['reasons'].append('uenig:naermeste_overskrift')
            p['status'] = 'unresolved'
            disagreements.append({'record_key': p['record_key'], 'field': 'naermeste_overskrift'})

    by_key = {p['record_key']: p for p in placements}
    flagged: set[str] = set()
    for pair in parents or []:
        child, parent = by_key.get(pair['child']), by_key.get(pair['parent'])
        if child is None or parent is None or child['entry_code'] is None \
                or child['entry_code'] != parent['entry_code'] \
                or child['generation_local'] is None or parent['generation_local'] is None:
            continue
        if child['generation_local'] != parent['generation_local'] + 1 and child['record_key'] not in flagged:
            flagged.add(child['record_key'])
            child['reasons'].append('uenig:foraelder_generation')
            child['status'] = 'unresolved'
            disagreements.append({'record_key': child['record_key'], 'field': 'foraelder_generation'})

    # to forældrefamilier i én gruppe: sammenhængskomponenter over (barn, forælder)-par
    group_members: dict[str, list[dict[str, Any]]] = {}
    for p in placements:
        if 'kuld' in p['header_ids']:
            group_members.setdefault(p['header_ids']['kuld'], []).append(p)
    for members in group_members.values():
        keys = {p['record_key'] for p in members}
        root: dict[str, str] = {}

        def find(x: str) -> str:
            root.setdefault(x, x)
            while root[x] != x:
                root[x] = root[root[x]]
                x = root[x]
            return x
        children = set()
        for pair in parents or []:
            if pair['child'] in keys:
                children.add(pair['child'])
                root[find(pair['child'])] = find(pair['parent'])
        if len({find(c) for c in children}) > 1:
            for p in members:
                if 'gruppe_flere_familier' not in p['reasons']:
                    p['reasons'].append('gruppe_flere_familier')
                    p['status'] = 'unresolved'

    # --- invarianter og overførselstal ---
    nr_slots: dict[tuple, set[int]] = {}
    for p in placements:
        if p['status'] == 'machine_ok':
            nr_slots.setdefault((tuple(p['section_path']), p['printed_number']), set()).add(p['post_char_from'])
    keys = [r['record_key'] for r in records]
    invariants = {
        'record_keys_unikke': len(keys) == len(set(keys)),
        'section_path_nr_unik': all(len(v) == 1 for v in nr_slots.values()),
        'en_overskrift_pr_gruppe': collisions == 0
        and len({h['element_id'] for h in headers}) == len(headers),
        'segmenter_paritet': [p['lokal_id'] for p in g_posts] == _segmenter_lokal_ids_1939(gtext, gp),
        # hver manglende slægtleds-/kuld-overskrift har et gruppekort (linje har intet kort)
        'gruppekort_daekker_overskriftsaarsager': all(
            lv in {c['niveau'] for c in p['gruppekort']} and lv in p['human_header_levels']
            for p in placements for r in p['reasons'] if r.startswith('overskrift_ikke_fundet:')
            for lv in [r.split(':', 1)[1]] if lv in ('slaegtled', 'kuld')),
    }
    transfer = {}
    for level in GUIDE_LEVELS_1939:
        total = [h for h in g_headers if h['level'] == level]
        found = [h for h in total if located.get(h['gid']) is not None]
        transfer[level] = {'guide': len(total), 'genfundet': len(found),
                           'ikke_genfundet': len(total) - len(found)}
    return {
        'header_rule_version': profile['header_rule_version'],
        'headers': headers,
        'placements': placements,
        'invariants': invariants,
        'disagreements': sorted(disagreements, key=lambda d: (str(d['record_key']), d['field'])),
        'transfer': transfer,
        'kort': {'gruppekort': len({c['id'] for p in placements for c in p['gruppekort']}),
                 'gruppekort_poster': sum(1 for p in placements if p['gruppekort']),
                 'strukturkort_poster': sum(1 for p in placements if any(
                     r in p['reasons'] for r in ('ikke_alignet', 'ikke_parret', 'nummer_tabt_i_rendition'))),
                 'strukturkort_med_linje': sum(1 for p in placements if p['naermeste_header_ids'] is not None)},
        'alignment': {'guide_posts': len(g_posts), 'rendition_posts': len(r_posts), 'aligned': len(align),
                      'unummererede': len(unnum_posts), 'unummererede_records': len(unnumbered),
                      'oversigtszone_records': len(in_zone),
                      **{key: len({r['char_from'] for r in unnum_recs
                                  if unnum_outcome[r['record_key']]['kind'] == kind})
                         for key, kind in (('parret_stamfader', 'stamfader'), ('parret_nummereret', 'nummereret'),
                                           ('parret_oversigt', 'oversigtspost'), ('uparret', 'uparret'))}},
    }


def canonical_sha256(value: Any) -> str:
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                     separators=(',', ':')).encode('utf-8')).hexdigest()


def summary(manifest: dict[str, Any]) -> dict[str, Any]:
    """Kun tal, nøgler og hashes — ingen overskrifts- eller posttekst."""
    result = {
        'header_rule_version': manifest['header_rule_version'],
        'manifest_sha256': canonical_sha256(manifest),
        'counts': {
            'headers': dict(Counter(h['kind'] for h in manifest['headers'])),
            'placements': dict(Counter(p['status'] for p in manifest['placements'])),
            'reasons': dict(Counter(r for p in manifest['placements'] for r in p['reasons'])),
            'disagreements': len(manifest['disagreements']),
        },
        'header_sha256s': canonical_sha256([h['verbatim_sha256'] for h in manifest['headers']]),
        'invariants': manifest['invariants'],
        'disagreements': manifest['disagreements'],
    }
    if 'transfer' in manifest:      # 1939: kun tal
        result['transfer'] = manifest['transfer']
        result['alignment'] = manifest['alignment']
        result['kort'] = manifest['kort']
    return result


def _private_path(value: str) -> Path:
    path = Path(value).expanduser().resolve()
    private = (Path.home() / '.private').resolve()
    if private not in path.parents:
        raise HeaderManifestError('HEADER_MANIFEST_PATH_NOT_PRIVATE')
    return path


DEFAULT_PROFILE = (Path(__file__).resolve().parent.parent / 'references' / 'header-profiles'
                   / 'header-2018-20-v1.json')


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--rendition-text', required=True)
    parser.add_argument('--header-profile', '--profile', dest='header_profile', default=str(DEFAULT_PROFILE))
    parser.add_argument('--guide-text')
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument('--legacy-json')
    source.add_argument('--records-json')
    parser.add_argument('--out', required=True)
    args = parser.parse_args(argv)
    out = _private_path(args.out)
    profile = json.loads(Path(args.header_profile).read_text(encoding='utf-8'))
    grammar = profile.get('grammar', '2018-20')
    rendition = Path(args.rendition_text).read_bytes()
    if profile.get('guide_text_sha256') is not None and not args.guide_text:
        raise HeaderManifestError('HEADER_GUIDE_TEXT_REQUIRED')
    # Renditionen er sha-bundet af profilen; kun manifestet og eksporten er private.
    if grammar == '2018-20':
        if not args.legacy_json:
            raise HeaderManifestError('HEADER_LEGACY_JSON_REQUIRED')
        legacy = json.loads(_private_path(args.legacy_json).read_text(encoding='utf-8'))
        manifest = build_manifest(rendition, {
            'raw_text_sha256': profile['raw_text_sha256'], 'entry_codes': legacy['entries'],
            'header_rule_version': profile.get('header_rule_version', HEADER_RULE_VERSION)},
            legacy['rows'], legacy.get('parents'))
    else:
        if not args.records_json:
            raise HeaderManifestError('HEADER_RECORDS_JSON_REQUIRED')
        export = json.loads(_private_path(args.records_json).read_text(encoding='utf-8'))
        manifest = build_manifest_by_offset(
            rendition, Path(args.guide_text).read_bytes(), profile,
            export['records'], export.get('parents', []))
    fd = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'w', encoding='utf-8') as fh:
        json.dump(manifest, fh, ensure_ascii=False, sort_keys=True, indent=1)
        fh.write('\n')
    result = summary(manifest)
    result['manifest_file_sha256'] = hashlib.sha256(out.read_bytes()).hexdigest()
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == '__main__':
    sys.exit(main())
