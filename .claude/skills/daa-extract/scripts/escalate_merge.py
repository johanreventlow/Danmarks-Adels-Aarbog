#!/usr/bin/env python3
"""Eskalerings-merge (trin ④b-plumbing): re-validér Opus-gen-udtræk og merge.

Promote-kriterium: 0 blokerende brud OG ikke flere R8-misses end Sonnet-snapshottet.
Promoverede poster markeres _escalated=True (load_daa.R stamper blaastemplet_af).
REPLACE hvis nøglen allerede er i clean (R8-post der loadede); ellers APPEND.
Stadig-fejlende sikres i review.json. Diff-rapport: se gen_diff() (Task 3).
"""
import os, sys, json, argparse
sys.path.insert(0, os.path.dirname(__file__))
import validate


def _r8_types(advisory):
    """Mængden af R8-strenge i advisory-listen (stabil nøgle: den fulde besked)."""
    return {a for a in (advisory or []) if a.startswith('R8')}


def _key(rec):
    return (rec.get('linje'), rec.get('nr_label') or str(rec.get('nr')))


def decide(reextracted, snapshot, src, known_by_linje):
    """(promote, issues, advisory) for et Opus-gen-udtræk.

    Promote-kriterium:
      1. Ingen blokerende brud.
      2. Snapshot skal eksistere (mangler → afvis).
      3. Mængden af R8-typer i reextracted ⊆ snapshot (ingen ny type introduceres).
         Et swap (snapshot misser ægteskab; reext misser død) er 1==1 men IKKE delmængde
         → afvises korrekt. Kun fjernede/bevarede R8-typer → promote.
    """
    # Normaliser boern deterministisk FØR validering (som validate.main() gør).
    validate.normalize_record(reextracted, src)
    issues, advisory = validate.validate(reextracted, src, known_by_linje)
    if snapshot is None:
        # Mangler snapshot → kan ikke vurdere forbedring → afvis
        return False, issues, advisory
    _, snap_adv = validate.validate(snapshot, src, known_by_linje)
    # Tillad kun promote hvis ingen ny R8-type er introduceret ift. snapshottet
    promote = (not issues) and (_r8_types(advisory) <= _r8_types(snap_adv))
    return promote, issues, advisory


def field_diff(snapshot, reextracted):
    """{felt: (gammel, ny)} for felter der ændrede sig (ignorér _escalated/narrative)."""
    out = {}
    keys = set(snapshot or {}) | set(reextracted or {})
    keys -= {'_escalated', 'narrative'}
    for k in keys:
        old, new = (snapshot or {}).get(k), (reextracted or {}).get(k)
        if old != new:
            out[k] = (old, new)
    return out


def gen_diff(escalation, reext_by_key, snap_by_key, promoted, path):
    """Skriv eskalerings-diff-rapport (markdown) til path."""
    lines = ['# Eskalerings-diff (Sonnet → Opus)', '']
    for ent in escalation:
        key = (ent['linje'], ent['nr_label'])
        d = field_diff(snap_by_key.get(key), reext_by_key.get(key))
        status = 'PROMOVERET' if key in promoted else 'stadig i review'
        lines.append(f'## {ent["linje"]}-{ent["nr_label"]} ({status})')
        lines.append(f'Grunde: {", ".join(ent.get("grunde", []))}')
        if not d:
            lines.append('_ingen feltændring_')
        for felt, (old, new) in sorted(d.items()):
            lines.append(f'- **{felt}**: `{old}` → `{new}`')
        lines.append('')
    with open(path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))


def merge_escalated(escalation, reext_by_key, snap_by_key, src_by_key, known_by_linje, clean, review):
    """Returnér (new_clean, new_review, promoted_keys)."""
    clean_by_key = {_key(r): r for r in clean}
    review_keys = {(r.get('linje'), r.get('nr_label') or str(r.get('nr'))) for r in review}
    fail_diag = {}                              # key -> (issues, advisory) for fejlede eskaleringer
    promoted = []
    for ent in escalation:
        key = (ent['linje'], ent['nr_label'])
        reext = reext_by_key.get(key)
        if reext is None:
            continue
        snap = snap_by_key.get(key)  # None → decide() afviser (fail-closed)
        src = src_by_key.get(key)
        promote, issues, advisory = decide(reext, snap, src, known_by_linje)
        if promote:
            # flet autoritativ narrativ ind som validate.main() gør, + marker
            merged = dict(reext)
            if src:
                merged['narrative'] = src['raw_text']
            merged['_escalated'] = True
            clean_by_key[key] = merged          # REPLACE el. APPEND (samme operation på dict)
            review_keys.discard(key)
            promoted.append(key)
        else:
            review_keys.add(key)
            clean_by_key.pop(key, None)         # en R8-post der nu fejler må IKKE blive i clean
            fail_diag[key] = (issues, advisory)
    new_clean = list(clean_by_key.values())
    # genopbyg review: behold eksisterende der ikke blev promoveret + nye fejlende.
    # Fejlede eskaleringer skal have validate.main()-review-formen (brud/advisory),
    # så menneskets recovery-sti ser HVORFOR posten fejlede — ikke den rå reext.
    new_review = [r for r in review if _key(r) in review_keys]
    for key in review_keys:
        if not any(_key(r) == key for r in new_review):
            reext = reext_by_key.get(key)
            if reext is not None:
                issues, advisory = fail_diag.get(key, ([], []))
                new_review.append({
                    'fil': f"{reext.get('linje')}-{reext.get('nr_label') or reext.get('nr')}.json",
                    'linje': reext.get('linje'), 'nr': reext.get('nr'),
                    'nr_label': reext.get('nr_label') or str(reext.get('nr')),
                    'navn': reext.get('navn'),
                    'brud': issues, 'advisory': advisory,
                })
    return new_clean, new_review, promoted


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('posts'); ap.add_argument('reextracted_dir'); ap.add_argument('snapshot_dir')
    ap.add_argument('escalation'); ap.add_argument('clean'); ap.add_argument('review')
    ap.add_argument('--diff', help='skriv diff-rapport (markdown) hertil')
    args = ap.parse_args()
    posts = json.load(open(args.posts, encoding='utf-8'))
    src_by_key = {(p['linje'], p.get('nr_label', str(p['nr']))): p for p in posts}
    known_by_linje = {}
    for p in posts:
        known_by_linje.setdefault(p['linje'], set()).add(p['nr'])
    escalation = json.load(open(args.escalation, encoding='utf-8'))

    def load_dir(d):
        out = {}
        for fn in os.listdir(d):
            if fn.endswith('.sonnet.json'): continue
            if fn.endswith('.json'):
                r = json.load(open(os.path.join(d, fn), encoding='utf-8'))
                out[(r.get('linje'), r.get('nr_label') or str(r.get('nr')))] = r
        return out

    def load_snaps(d):
        out = {}
        for fn in os.listdir(d):
            if fn.endswith('.sonnet.json'):
                r = json.load(open(os.path.join(d, fn), encoding='utf-8'))
                out[(r.get('linje'), r.get('nr_label') or str(r.get('nr')))] = r
        return out

    reext = load_dir(args.reextracted_dir)
    snaps = load_snaps(args.snapshot_dir)
    clean = json.load(open(args.clean, encoding='utf-8'))
    review = json.load(open(args.review, encoding='utf-8'))
    new_clean, new_review, promoted = merge_escalated(escalation, reext, snaps, src_by_key, known_by_linje, clean, review)
    json.dump(new_clean, open(args.clean, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
    json.dump(new_review, open(args.review, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
    if args.diff:
        gen_diff(escalation, reext, snaps, set(promoted), args.diff)
    print(f'[escalate] {len(promoted)} promoveret, {len(new_review)} stadig i review', file=sys.stderr)


if __name__ == '__main__':
    main()
