# Designtour-testdata: bygger tmp/designtour/fixture.json fra stamtavleudtrækket. Kun personer født <= 1930 (eller, uden kendt fødsel, døde <= 1930
# eller med en forælder født <= 1880). Udskriver kun tællinger.
import json, glob, re, os, sys
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
SRC = os.path.join(ROOT, 'data', 'extracted-2026-06-18')
OUT = os.path.join(ROOT, 'tmp', 'designtour', 'fixture.json')
os.makedirs(os.path.dirname(OUT), exist_ok=True)
CUT = 1930
recs = {}
for p in glob.glob(SRC + '/*.json'):
    r = json.load(open(p)); recs[os.path.basename(p)[:-5]] = r
def year(s):
    if isinstance(s, dict): s = s.get('date_min') or s.get('date_raw') or s.get('date_max')
    if not isinstance(s, str): s = None
    m = re.search(r'(\d{4})', s or '');  return int(m.group(1)) if m else None
def fyear(r, types):
    for x in r['facts']:
        if x['faktatype'] in types:
            y = year(x.get('date_min') or x.get('date_max') or x.get('date_raw'))
            if y: return y
def anyyear(r):
    ys = [year(x.get('date_min') or x.get('date_raw')) for x in r['facts']]
    ys = [y for y in ys if y]; return min(ys) if ys else None
by_ln = {}
for k, r in recs.items(): by_ln.setdefault((r['linje'], r['nr']), []).append(k)
parent_of = {}; gen_of = {}
for k, r in recs.items():
    b = r.get('boern')
    if b and b.get('nr_range'):
        lo, hi = (b['nr_range'] + b['nr_range'])[:2] if len(b['nr_range']) == 1 else b['nr_range'][:2]
        for n in range(lo, hi + 1):
            for ck in by_ln.get((b.get('linje') or r['linje'], n), []):
                parent_of.setdefault(ck, k)
                g = re.search(r'\d+', b.get('slaegtled') or ''); gen_of[ck] = int(g.group()) if g else None
def born(k): return fyear(recs[k], ('fødsel', 'dåb'))
def died(k): return fyear(recs[k], ('død', 'begravelse', 'bisættelse'))
def allowed(k):
    b = born(k)
    if b is not None: return b <= CUT
    d = died(k)
    if d is not None: return d <= CUT
    a = anyyear(recs[k])
    if a is not None: return a <= 1890
    p = parent_of.get(k)
    if p:
        pb, pd = born(p), died(p)
        if pb is not None: return pb <= 1880
        if pd is not None: return pd <= 1910
        pa = anyyear(recs[p]);  return pa is not None and pa <= 1860
    return False
keep = [k for k in recs if allowed(k)]
pid = {k: i + 1 for i, k in enumerate(sorted(keep, key=lambda k: (k.split('-')[0], int(re.sub(r'\D', '', k.split('-')[1]) or 0))))}
T = {t: [] for t in ['person','family','family_member','fact','assertion','conclusion','citation','source','lineage','estate','relation','organisation','coords','coat_of_arms','narrative','place']}
T['source'].append({'id': 1, 'slags': 'DAA-udgave', 'titel': 'Danmarks Adels Aarbog', 'udgave': 'Reventlow, stamtavle', 'aar': 1939, 'ekstern': None})
LIN = {'I': 1, 'II': 2, 'III': 3, 'IV': 4, 'V': 5}
for code, i in LIN.items():
    T['lineage'].append({'id': i, 'source_id': 1, 'kode': code, 'navn': f'{code}. linje', 'canonical_label': f'{code}. linje', 'slaegt_id': 1, 'slaegtsnavn': 'Reventlow', 'parent_lineage_id': None, 'presens_kode': code})
ids = {'fact': 0, 'assertion': 0, 'family': 0, 'estate': 0, 'org': 0, 'rel': 0, 'person': len(pid)}
estates = {}; orgs = {}
def rawd(v):
    return (v.get('date_raw') or v.get('date_min')) if isinstance(v, dict) else v
def nid(t): ids[t] += 1; return ids[t]
def raw(r, types):
    for x in r['facts']:
        if x['faktatype'] in types: return x.get('date_raw') or x.get('vaerdi')
for k in keep:
    r = recs[k]; i = pid[k]
    titel = next((x['vaerdi'] for x in r['facts'] if x['faktatype'] == 'titel' and x.get('vaerdi')), None)
    T['person'].append({'id': i, 'visning_navn': r['navn'], 'visning_fuldt_navn': r['navn'] if re.search('reventl', r['navn'], re.I) else f"{r['navn']} Reventlow", 'visning_efternavn': 'Reventlow',
        'visning_foedt': raw(r, ('fødsel', 'dåb')), 'visning_doed': raw(r, ('død', 'begravelse')), 'visning_titel': titel,
        'koen': r.get('koen'), 'privat': False, 'levende': False})
    T['coords'].append({'person_id': i, 'source_id': 1, 'legacy_line_code': r['linje'], 'printed_number': r['nr'], 'printed_number_label': r.get('nr_label'),
        'generation_local': gen_of.get(k), 'generation_global': gen_of.get(k), 'kuld_label': None, 'provenance_kind': 'placement'})
    for x in r['facts']:
        f = nid('fact'); a = nid('assertion')
        T['fact'].append({'id': f, 'subjekt_type': 'person', 'subjekt_id': i, 'faktatype': x['faktatype'], 'sted_id': None})
        T['assertion'].append({'id': a, 'target_type': 'fact', 'target_id': f, 'objekt_id': None, 'vaerdi_tekst': x.get('vaerdi') or x.get('date_raw'),
            'date_min': x.get('date_min'), 'date_max': x.get('date_max'), 'date_qualifier': x.get('date_qualifier'), 'date_raw': x.get('date_raw'), 'uforanderlig': True})
        T['conclusion'].append({'id': f, 'target_type': 'fact', 'target_id': f, 'valgt_assertion_id': a, 'status': 'afklaret'})
        T['citation'].append({'id': a, 'assertion_id': a, 'source_id': 1, 'side': None, 'citat_tekst': x.get('date_raw') or x.get('vaerdi'), 'citat_dato': None})
    for g in r.get('godser') or []:
        if not g.get('navn'): continue
        e = estates.get(g['navn']) or nid('estate'); estates[g['navn']] = e
        T['relation'].append({'id': nid('rel'), 'subjekt_type': 'person', 'subjekt_id': i, 'objekt_type': 'estate', 'objekt_id': e, 'rolle': 'ejer', 'periode_raw': g.get('periode_raw'), 'kvalifikator': None})
    for em in r.get('embeder') or []:
        if not em.get('organisation'): continue
        o = orgs.get(em['organisation']) or nid('org'); orgs[em['organisation']] = o
        T['relation'].append({'id': nid('rel'), 'subjekt_type': 'person', 'subjekt_id': i, 'objekt_type': 'organisation', 'objekt_id': o, 'rolle': em.get('rolle'), 'periode_raw': em.get('dato_raw'), 'kvalifikator': None})
T['estate'] = [{'id': v, 'navn': n, 'slags': 'gods', 'sted_id': None} for n, v in estates.items()]
T['organisation'] = [{'id': v, 'navn': n} for n, v in orgs.items()]
# Familier: ægteskaber + børn
fam_of = {}
for k in keep:
    r = recs[k]; i = pid[k]
    for m in r.get('aegteskaber') or []:
        f = nid('family'); T['family'].append({'id': f, 'type': 'ægteskab'}); fam_of.setdefault(k, f)
        T['family_member'].append({'family_id': f, 'person_id': i, 'rolle': 'partner', 'ordinal': m.get('ordinal') or 1, 'konfidens': 'sikker'})
        pb = year(m.get('partner_foedsel')); b = born(k)
        ok = (pb is not None and pb <= CUT) or (pb is None and b is not None and b <= 1890)
        if ok and m.get('partner_navn'):
            p = nid('person')
            T['person'].append({'id': p, 'visning_navn': m['partner_navn'], 'visning_fuldt_navn': m['partner_navn'], 'visning_efternavn': None,
                'visning_foedt': rawd(m.get('partner_foedsel')), 'visning_doed': rawd(m.get('partner_doed')), 'visning_titel': None,
                'koen': 'kvinde' if r.get('koen') == 'mand' else 'mand', 'privat': False, 'levende': False})
            T['family_member'].append({'family_id': f, 'person_id': p, 'rolle': 'partner', 'ordinal': m.get('ordinal') or 1, 'konfidens': 'sikker'})
for ck, pk in parent_of.items():
    if ck in pid and pk in pid:
        f = fam_of.get(pk)
        if not f:
            f = nid('family'); T['family'].append({'id': f, 'type': 'ægteskab'}); fam_of[pk] = f
            T['family_member'].append({'family_id': f, 'person_id': pid[pk], 'rolle': 'partner', 'ordinal': 1, 'konfidens': 'sikker'})
        T['family_member'].append({'family_id': f, 'person_id': pid[ck], 'rolle': 'barn', 'ordinal': recs[ck]['nr'], 'konfidens': 'formodet' if recs[ck].get('usikker') else 'sikker'})
json.dump(T, open(OUT, 'w'), ensure_ascii=False)
print({t: len(v) for t, v in T.items()}, 'udeladt', len(recs) - len(keep))
