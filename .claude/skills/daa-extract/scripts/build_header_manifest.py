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
import hashlib
import json
import os
import sys
from collections import Counter
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

import segment
from build_source_evidence_manifest import project_rendition
from ordinals import ordinal_to_int

HEADER_RULE_VERSION = 'header-2018-20-v1'
LEVELS = ('linje', 'slaegtled', 'kuld', 'aegteskab')
LEGACY_FIELDS = ('linje', 'nr', 'slaegtled_lokal', 'slaegtled_gennem', 'kuld')
ROMAN_VALUES = {'I': 1, 'V': 5, 'X': 10}


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


def _scan(text: str) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """Overskrifter og poster i dokumentorden; hver post bærer de aktive overskrifter."""
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
                          'active': dict(active)})
    return headers, posts


def _invariants(headers: list[dict[str, Any]], posts: list[dict[str, Any]],
                entry_codes: list[str]) -> dict[str, bool]:
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
    numbers: dict[str, list[int]] = {}
    keys = []
    for p in posts:
        if 'linje' in p['active']:
            numbers.setdefault(p['active']['linje']['element_id'], []).append(p['nr'])
        keys.append(p['record_key'])
    return {
        'linje_overskrifter_svarer_til_entries': linje_romans == list(entry_codes),
        'poster_har_linje': all(p['entry_code'] is not None for p in posts),
        'slaegtled_fortloebende': all(None not in seq and all(b == a + 1 for a, b in zip(seq, seq[1:]))
                                      for seq in ordinals.values()),
        'kuld_stigende': all(all(b > a for a, b in zip(seq, seq[1:])) for seq in kuld.values()),
        'nr_fortloebende': all(not seq or (seq[0] == 1 and all(b - a in (0, 1) for a, b in zip(seq, seq[1:])))
                               for key, seq in numbers.items() if key.startswith('header:')),
        'record_keys_unikke': len(keys) == len(set(keys)),
    }


def build_manifest(rendition_bytes: bytes, profile: dict[str, Any],
                   legacy: list[dict[str, Any]]) -> dict[str, Any]:
    expected_sha = profile.get('raw_text_sha256')
    if expected_sha is not None and hashlib.sha256(rendition_bytes).hexdigest() != expected_sha:
        raise HeaderManifestError('HEADER_RENDITION_SHA_MISMATCH')
    entry_codes = list(profile['entry_codes'])
    headers, posts = _scan(rendition_bytes.decode('utf-8'))
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
            'generation_local': values['slaegtled_lokal'],
            'generation_label_raw': slaegtled['parsed']['label_raw'] if slaegtled else None,
            'generation_global': values['slaegtled_gennem'],
            'kuld_label': values['kuld'],
            'section_path': [header_ids[level] for level in LEVELS if level in header_ids],
            'header_ids': header_ids,
            'status': 'unresolved' if reasons else 'machine_ok',
            'reasons': reasons,
        })

    rendered = {p['record_key'] for p in placements}
    for key in sorted(set(legacy_by_key) - rendered):
        disagreements.append({'record_key': key, 'field': 'mangler_i_rendition'})

    return {
        'header_rule_version': HEADER_RULE_VERSION,
        'headers': headers,
        'placements': placements,
        'invariants': _invariants(headers, posts, entry_codes),
        'disagreements': sorted(disagreements, key=lambda d: (str(d['record_key']), d['field'])),
    }


def canonical_sha256(value: Any) -> str:
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                     separators=(',', ':')).encode('utf-8')).hexdigest()


def summary(manifest: dict[str, Any]) -> dict[str, Any]:
    """Kun tal, nøgler og hashes — ingen overskrifts- eller posttekst."""
    return {
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


def _private_path(value: str) -> Path:
    path = Path(value).expanduser().resolve()
    private = (Path.home() / '.private').resolve()
    if private not in path.parents:
        raise HeaderManifestError('HEADER_MANIFEST_PATH_NOT_PRIVATE')
    return path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--rendition-text', required=True)
    parser.add_argument('--profile', required=True)
    parser.add_argument('--legacy-json', required=True)
    parser.add_argument('--out', required=True)
    args = parser.parse_args(argv)
    out = _private_path(args.out)
    profile = json.loads(Path(args.profile).read_text(encoding='utf-8'))
    legacy = json.loads(_private_path(args.legacy_json).read_text(encoding='utf-8'))
    # Renditionen (work/raw_full.txt) er sha-bundet af profilen; kun manifestet og legacy er private.
    manifest = build_manifest(Path(args.rendition_text).read_bytes(),
                              {'raw_text_sha256': profile['raw_text_sha256'], 'entry_codes': legacy['entries']},
                              legacy['rows'])
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
