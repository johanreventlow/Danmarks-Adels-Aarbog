import hashlib, json, os, sys, unittest
from unittest import mock
sys.path.insert(0, os.path.dirname(__file__))
import build_header_manifest as bhm
import segment
from build_source_evidence_manifest import project_rendition

ENTRIES = ['I', 'II']


def rendition(*lines):
    return ('\n'.join(lines) + '\n').encode('utf-8')


# Opdigtede personer; layout som 2018-20 (centreret romertal + versal linjenavn, ordinal-slægtled,
# fritstående kuld-romertal, ægteskabskontekst »… med X:«, poster med nr. + to mellemrum).
BASIS = [
    '### PAGE 10 ###',
    '                         I',
    '                DEN TESTSKE LINJE',
    '                  Første slægtled',
    '1.  Anna Testesen, f. 1600.',
    '                  Andet (Tredje) slægtled',
    '                         I',
    '            af første ægteskab med Bodil Opdigt:',
    '1a.  Bent Testesen, f. 1630.',
    '2.  Carl Testesen, f. 1632.',
    '                         II',
    '3.  Dora Testesen, f. 1640.',
    '### PAGE 11 ###',
    '                         II',
    '                DEN PRØVENDE LINJE',
    '                  Første slægtled',
    '1.  Erik Prøvesen, f. 1650.',
]


def legacy_for(rows):
    return [dict(zip(('record_key', 'linje', 'nr', 'slaegtled_lokal', 'slaegtled_gennem', 'kuld'), r)) for r in rows]


LEGACY = legacy_for([
    ('I-1', 'I', 1, 1, None, None),
    ('I-1a', 'I', 1, 2, 3, 'I'),
    ('I-2', 'I', 2, 2, 3, 'I'),
    ('I-3', 'I', 3, 2, 3, 'II'),
    ('II-1', 'II', 1, 1, None, None),
])


def build(lines=BASIS, legacy=LEGACY, entries=ENTRIES):
    return bhm.build_manifest(rendition(*lines), {'entry_codes': entries}, legacy)


def placement(manifest, key):
    return next(p for p in manifest['placements'] if p['record_key'] == key)


class TestHeaderManifest(unittest.TestCase):
    def test_linje_overskrift_to_linjer(self):
        m = build()
        linjer = [h for h in m['headers'] if h['kind'] == 'header_linje']
        self.assertEqual([h['parsed']['roman'] for h in linjer], ['I', 'II'])
        h = linjer[0]
        self.assertEqual(h['verbatim_text'], 'I DEN TESTSKE LINJE')
        self.assertEqual((h['page_from'], h['page_to']), (10, 10))
        self.assertEqual(h['element_id'], f"header:{h['char_from']}")
        self.assertEqual(m['header_rule_version'], 'header-2018-20-v1')

    def test_slaegtled_og_kuld(self):
        m = build()
        p = placement(m, 'I-2')
        self.assertEqual(p['entry_code'], 'I')
        self.assertEqual(p['printed_number'], '2')
        self.assertEqual(p['generation_local'], 2)
        self.assertEqual(p['generation_global'], 3)
        self.assertEqual(p['generation_label_raw'], 'Andet')
        self.assertEqual(p['kuld_label'], 'I')
        self.assertEqual(set(p['header_ids']), {'linje', 'slaegtled', 'kuld', 'aegteskab'})
        self.assertEqual(p['section_path'], [p['header_ids'][k] for k in ('linje', 'slaegtled', 'kuld', 'aegteskab')])
        self.assertEqual(p['status'], 'machine_ok')
        self.assertEqual(placement(m, 'I-1a')['printed_number'], '1a')
        # Postens side (opslag i PDF'en for kontrolarket) — ikke en placeringsværdi.
        self.assertEqual((placement(m, 'I-1')['page'], placement(m, 'II-1')['page']), (10, 11))

    def test_hoejere_niveau_annullerer(self):
        lines = BASIS[:12] + [
            '                  Tredje (Fjerde) slægtled',
            '4.  Frida Testesen, f. 1670.',
        ] + BASIS[12:]
        legacy = LEGACY + legacy_for([('I-4', 'I', 4, 3, 4, None)])
        m = build(lines, legacy)
        p = placement(m, 'I-4')
        self.assertIsNone(p['kuld_label'])
        self.assertEqual(set(p['header_ids']), {'linje', 'slaegtled'})
        self.assertEqual(p['generation_local'], 3)
        # Kuld II fra slægtled 2 må heller ikke overleve ægteskabskonteksten fra kuld I.
        self.assertNotIn('aegteskab', placement(m, 'I-3')['header_ids'])
        self.assertEqual(p['status'], 'machine_ok')

    def test_umarkeret_slaegtledsfald(self):
        lines = BASIS[:3] + ['1.  Anna Testesen, f. 1600.'] + BASIS[5:]
        legacy = legacy_for([('I-1', 'I', 1, 1, None, None)]) + LEGACY[1:]
        m = build(lines, legacy)
        p = placement(m, 'I-1')
        self.assertEqual(p['status'], 'unresolved')
        self.assertEqual(p['reasons'], ['umarkeret_slaegtled'])
        self.assertIsNone(p['generation_local'])

    def test_uenighed_med_legacy(self):
        legacy = [dict(r) for r in LEGACY]
        legacy[2]['slaegtled_lokal'] = 5
        m = build(legacy=legacy)
        self.assertIn({'record_key': 'I-2', 'field': 'slaegtled_lokal'}, m['disagreements'])
        p = placement(m, 'I-2')
        self.assertEqual(p['status'], 'unresolved')
        self.assertIn('uenig:slaegtled_lokal', p['reasons'])
        # Generationen kommer fra overskriften, aldrig fra legacy.
        self.assertEqual(p['generation_local'], 2)
        self.assertEqual(placement(m, 'I-3')['status'], 'machine_ok')

    def test_mangler_legacy_eller_post(self):
        m = build(legacy=LEGACY[:-1] + legacy_for([('II-9', 'II', 9, 1, None, None)]))
        self.assertEqual(placement(m, 'II-1')['status'], 'unresolved')
        self.assertIn('mangler_legacy', placement(m, 'II-1')['reasons'])
        self.assertIn({'record_key': 'II-9', 'field': 'mangler_i_rendition'}, m['disagreements'])

    def test_invarianter(self):
        m = build()
        self.assertTrue(m['invariants'])
        self.assertTrue(all(m['invariants'].values()), m['invariants'])
        self.assertEqual(set(m['invariants']), {
            'linje_overskrifter_svarer_til_entries', 'poster_har_linje', 'slaegtled_fortloebende',
            'kuld_stigende', 'nr_fortloebende', 'record_keys_unikke'})
        brudt = {
            'linje_overskrifter_svarer_til_entries': build(entries=['I', 'II', 'III']),
            'slaegtled_fortloebende': build([l.replace('Andet (Tredje)', 'Tredje (Tredje)') for l in BASIS]),
            'kuld_stigende': build(BASIS[:10] + ['                         I'] + BASIS[11:]),
            'nr_fortloebende': build([l.replace('3.  Dora', '5.  Dora') for l in BASIS]),
            'poster_har_linje': build(['1.  Ulla Uden, f. 1590.'] + BASIS),
            'record_keys_unikke': build(BASIS[:10] + ['2.  Gert Testesen, f. 1641.'] + BASIS[10:]),
        }
        for navn, mm in brudt.items():
            self.assertFalse(mm['invariants'][navn], navn)

    def test_foraelder_generation_krydscheck(self):
        # 5b-bundne forælder-barn-par: barnet skal stå præcis ét slægtled under forælderen i samme linje.
        # Et skift uden overskrift midt i et slægtled ses ellers ikke (legacy er samme læsning).
        parents = [{'child': 'I-1a', 'parent': 'I-1'}, {'child': 'I-2', 'parent': 'I-1'},
                   {'child': 'I-3', 'parent': 'I-2'},          # samme slægtled → brud
                   {'child': 'II-1', 'parent': 'I-3'},         # anden linje → ikke sammenlignet
                   {'child': 'I-1', 'parent': 'X-9'}]          # forælder uden placering → ikke sammenlignet
        m = bhm.build_manifest(rendition(*BASIS), {'entry_codes': ENTRIES}, LEGACY, parents)
        p = placement(m, 'I-3')
        self.assertEqual(p['status'], 'unresolved')
        self.assertIn('uenig:foraelder_generation', p['reasons'])
        self.assertIn({'record_key': 'I-3', 'field': 'foraelder_generation'}, m['disagreements'])
        for key in ('I-1', 'I-1a', 'I-2', 'II-1'):
            self.assertEqual(placement(m, key)['status'], 'machine_ok', key)
        self.assertEqual(placement(build(), 'I-3')['status'], 'machine_ok')   # uden par: uændret

    def test_nr_hul_daekket_af_trykt_interval(self):
        # Bogen samler numre i ét kollektivt opslag (»95.-97. Ord.«); kun et hul, som et
        # interval dækker præcist, er tilladt. Andre huller bryder stadig invarianten.
        lines = [l.replace('3.  Dora', '6.  Dora') for l in BASIS]
        daekket = lines[:10] + ['            3.-5.   Sønner.'] + lines[10:]
        legacy = [dict(r, record_key='I-6', nr=6) if r['record_key'] == 'I-3' else r for r in LEGACY]
        self.assertTrue(build(daekket, legacy)['invariants']['nr_fortloebende'])
        for interval in ('3.-4.', '4.-5.', '3.-6.'):
            forkert = lines[:10] + [f'            {interval}   Sønner.'] + lines[10:]
            self.assertFalse(build(forkert, legacy)['invariants']['nr_fortloebende'], interval)
        efter = lines + ['            3.-5.   Sønner.']
        self.assertFalse(build(efter, legacy)['invariants']['nr_fortloebende'])

    def test_offsets_renditionsabsolutte(self):
        raw = rendition(*BASIS)
        text = raw.decode('utf-8')
        m = bhm.build_manifest(raw, {'entry_codes': ENTRIES}, LEGACY)
        self.assertEqual(len(m['headers']), 8)
        for h in m['headers']:
            self.assertEqual(project_rendition(text[h['char_from']:h['char_to']])[0], h['verbatim_text'])
            self.assertFalse(text[h['char_from']].isspace())
            self.assertFalse(text[h['char_to'] - 1].isspace())
        aeg = next(h for h in m['headers'] if h['kind'] == 'header_aegteskab')
        self.assertEqual(aeg['verbatim_text'], 'af første ægteskab med Bodil Opdigt:')

    def test_rendition_sha_vagt(self):
        with self.assertRaises(bhm.HeaderManifestError):
            bhm.build_manifest(rendition(*BASIS), {'entry_codes': ENTRIES, 'raw_text_sha256': '0' * 64}, LEGACY)

    def test_summary_uden_tekst(self):
        m = build()
        s = repr(bhm.summary(m))
        for ord_ in ('Anna', 'Bodil', 'Opdigt', 'TESTSKE', 'PRØVENDE', 'ægteskab'):
            self.assertNotIn(ord_, s)
        self.assertEqual(bhm.summary(m)['counts']['headers'], {'header_linje': 2, 'header_slaegtled': 3,
                                                             'header_kuld': 2, 'header_aegteskab': 1})


class Test2018_20ByteEns(unittest.TestCase):
    def test_2018_20_byte_ens(self):
        # sha'erne er målt FØR profil-refaktoreringen på de eksisterende fixtures
        self.assertEqual(bhm.canonical_sha256(build()),
                         'cce8d831e9d3f9e086e4c212f35ed7f682085f6f914d2daf2d0224b4cc33b852')
        parents = [{'child': 'I-1a', 'parent': 'I-1'}, {'child': 'I-2', 'parent': 'I-1'},
                   {'child': 'I-3', 'parent': 'I-2'}, {'child': 'II-1', 'parent': 'I-3'}]
        m = bhm.build_manifest(rendition(*BASIS), {'entry_codes': ENTRIES}, LEGACY, parents)
        self.assertEqual(bhm.canonical_sha256(m),
                         '1b77949a09cfbe0f0999d73c95137727c15ee9cee5f4c86850e21406d557e0af')

    def test_profilfiler(self):
        d = os.path.join(os.path.dirname(__file__), '..', 'references', 'header-profiles')
        p18 = bhm.load_header_profile(os.path.join(d, 'header-2018-20-v1.json'))
        p39 = bhm.load_header_profile(os.path.join(d, 'header-1939-v1.json'))
        self.assertEqual((p18['grammar'], p18['guide_text_sha256']), ('2018-20', None))
        self.assertEqual(p39['raw_text_sha256'], '020123a3588dacf80705a22fb021ab4f5da97b8de202e8664304ca01f9a6da37')
        self.assertEqual(p39['guide_text_sha256'], 'efab316b528eafc60074c21c877590b31ab8e960cd1adc14f5c79bf01f12dab7')
        self.assertEqual((p39['record_matching'], p39['stamme_afsnit_level']), ('earliest_occurrence', 'slaegtled'))
        with self.assertRaises(bhm.HeaderManifestError):      # 1939 kræver guiden
            bhm.build_manifest(rendition(*BASIS), p39, LEGACY)


# ---------------------------------------------------------------------------------------------
# 1939: centreret guide + ucentreret rendition (opdigtede personer)
# ---------------------------------------------------------------------------------------------
BESKRIVELSE = 'Anna Reventlows Børn med Bodil Opdigt:'
GUIDE = [
    '### PAGE 500 ###',
    '                                   I',
    '      Den testske Linje af 1500.',
    '                          (S. 5).',
    '                 Første Slægtled.',
    '1.  Anna, f. 1600.',
    '    Boede paa Testrup.',
    '                 Andet Slægtled.',
    '                                   I.',
    '                      ' + BESKRIVELSE,
    '1.  Bent, f. 1630.',
    '2.  Carl, f. 1632.',
    '                                   II.',
    '3.  Dora, f. 1640.',
    '### PAGE 501 ###',
    '                                   II',
    '      Den prøvende Linje af 1600.',
    '                          (S. 9).',
    '                 Første Slægtled.',
    '1.  Erik, f. 1650.',
]
PROFILE_1939 = {
    'header_rule_version': 'header-1939-v1', 'raw_text_sha256': None, 'grammar': '1939',
    'record_matching': 'earliest_occurrence', 'stamme_afsnit_level': 'slaegtled',
    'levels': {'linje': 'header_linje', 'slaegtled': 'header_slaegtled', 'kuld': 'header_kuld'},
    'guide_text_sha256': None,
}


def calamari(lines):
    return [l.strip() for l in lines]


def rec(rend_lines, needle, key, kind='person', legacy=None):
    """needle: postens navn (»1.  Anna« → 'Anna', findes som nummerlinjen) eller en tekst midt i en post."""
    import re
    text = '\n'.join(rend_lines) + '\n'
    m = re.search(r'^\d+[a-z]?\.\s+' + re.escape(needle.split()[-1].rstrip(',')), text, re.M) \
        if re.match(r'^\d', needle) else None
    return {'record_key': key, 'record_kind': kind, 'page_from': 500,
            'char_from': m.start() if m else text.index(needle), 'legacy': legacy}


def records_for(rend_lines):
    out = [rec(rend_lines, '1.  Anna', 'A'), rec(rend_lines, '1.  Bent', 'B'),
           rec(rend_lines, '2.  Carl', 'C'), rec(rend_lines, '3.  Dora', 'D'),
           rec(rend_lines, '1.  Erik', 'E')]
    return out


def build39(guide=GUIDE, rend=None, records=None, parents=(), profile=PROFILE_1939):
    rend = calamari(guide) if rend is None else rend
    records = records_for(rend) if records is None else records
    return bhm.build_manifest_by_offset(rendition(*rend), rendition(*guide), profile, records, list(parents))


def without(lines, *needles):
    return [l for l in lines if not any(n == l.strip() for n in needles)]


class Test1939(unittest.TestCase):
    def test_1939_niveauer(self):
        m = build39()
        self.assertEqual(m['header_rule_version'], 'header-1939-v1')
        kinds = sorted(h['kind'] for h in m['headers'])
        self.assertEqual(kinds, ['header_kuld'] * 2 + ['header_linje'] * 2 + ['header_slaegtled'] * 3)
        b = placement(m, 'B')
        self.assertEqual(b['entry_code'], 'I')
        self.assertEqual(b['generation_local'], 2)
        self.assertEqual(b['generation_label_raw'], 'Andet')
        self.assertIsNone(b['generation_global'])
        self.assertEqual(b['kuld_label'], 'I')
        self.assertEqual(b['status'], 'machine_ok', b['reasons'])
        self.assertEqual(len(b['section_path']), 3)
        self.assertEqual(b['section_path'], [b['header_ids'][k] for k in ('linje', 'slaegtled', 'kuld')])
        self.assertEqual(b['guide_lokal_id'], 'I.Andet.I.1')
        self.assertEqual(b['record_kind'], 'person')
        a = placement(m, 'A')
        self.assertEqual((a['generation_local'], a['kuld_label'], set(a['header_ids'])), (1, None, {'linje', 'slaegtled'}))
        self.assertEqual(placement(m, 'E')['entry_code'], 'II')
        self.assertEqual((placement(m, 'E')['page'], b['page']), (501, 500))
        self.assertTrue(all(m['invariants'].values()), m['invariants'])
        self.assertEqual(set(m['invariants']), {'record_keys_unikke', 'section_path_nr_unik',
                                                'en_overskrift_pr_gruppe', 'segmenter_paritet'})
        self.assertEqual(m['transfer'], {'linje': {'guide': 2, 'genfundet': 2, 'ikke_genfundet': 0},
                                         'slaegtled': {'guide': 3, 'genfundet': 3, 'ikke_genfundet': 0},
                                         'kuld': {'guide': 2, 'genfundet': 2, 'ikke_genfundet': 0}})

    def test_record_efter_offset(self):
        # postens koordinater er recordens egen char_from; to records på samme char_from deler dem lovligt
        rend = calamari(GUIDE)
        recs = records_for(rend) + [dict(rec(rend, '1.  Anna', 'A-fakta', kind='fact'), persona=False)]
        m = build39(records=recs)
        a, fact = placement(m, 'A'), placement(m, 'A-fakta')
        for k in ('printed_number', 'section_path', 'post_char_from', 'entry_code', 'generation_local'):
            self.assertEqual(a[k], fact[k], k)
        self.assertEqual(fact['record_kind'], 'fact')
        self.assertEqual(fact['status'], 'machine_ok')
        self.assertTrue(m['invariants']['section_path_nr_unik'])

    def test_poster_uden_linjeskift(self):
        rend = calamari(GUIDE)
        k = rend.index('1.  Bent, f. 1630.')
        rend[k:k + 2] = ['1.  Bent, f. 1630. 2.  Carl, f. 1632.']
        m = build39(rend=rend)
        b, c = placement(m, 'B'), placement(m, 'C')
        self.assertEqual((b['printed_number'], c['printed_number']), ('1', '2'))
        self.assertNotEqual(b['post_char_from'], c['post_char_from'])
        self.assertEqual((b['status'], c['status']), ('machine_ok', 'machine_ok'), (b['reasons'], c['reasons']))
        self.assertEqual((b['generation_local'], c['kuld_label']), (2, 'I'))
        self.assertTrue(all(m['invariants'].values()), m['invariants'])

    def test_record_uden_nummer_er_uden_post(self):
        rend = calamari(GUIDE)
        recs = records_for(rend) + [rec(rend, 'Boede paa', 'U')]
        m = build39(records=recs)
        u = placement(m, 'U')
        self.assertEqual((u['status'], u['reasons']), ('unresolved', ['uden_post']))
        self.assertIsNone(u['printed_number'])
        self.assertEqual(placement(m, 'A')['status'], 'machine_ok')

    def test_overskrift_ikke_fundet_er_unresolved(self):
        rend = calamari(GUIDE)       # kun den første slægtledslinje fjernes (den anden står på side 501)
        rend.remove('Første Slægtled.')
        m = build39(rend=rend)
        a = placement(m, 'A')
        self.assertEqual(a['status'], 'unresolved')
        self.assertEqual(a['reasons'], ['overskrift_ikke_fundet:slaegtled'])
        self.assertIsNone(a['generation_local'])
        self.assertEqual(placement(m, 'B')['status'], 'machine_ok')
        self.assertEqual(m['transfer']['slaegtled']['ikke_genfundet'], 1)
        self.assertTrue(all(m['invariants'].values()))

    def test_uden_post(self):
        rend = calamari(GUIDE)
        recs = records_for(rend) + [{'record_key': 'X', 'record_kind': 'person', 'page_from': 500,
                                     'char_from': 3, 'legacy': None}]
        m = build39(records=recs)
        self.assertEqual(placement(m, 'X')['reasons'], ['uden_post'])
        self.assertEqual(placement(m, 'X')['status'], 'unresolved')
        self.assertIsNone(placement(m, 'X')['printed_number'])

    def test_ikke_alignet(self):
        # en post kun i guiden: ingen record peger på den, øvrige placeringer er uændrede
        guide = GUIDE[:6] + ['2.  Extra, f. 1601.'] + GUIDE[6:]
        rend = calamari(GUIDE)
        m = build39(guide=guide, rend=rend)
        self.assertEqual(m['alignment'], {'guide_posts': 6, 'rendition_posts': 5, 'aligned': 5, 'unummererede': 0, 'unummererede_records': 0,
                                      'parret_stamfader': 0, 'parret_nummereret': 0, 'parret_oversigt': 0, 'uparret': 0})
        self.assertTrue(all(p['status'] == 'machine_ok' for p in m['placements']), m['placements'])
        # en post kun i renditionen: recorden i den kan ikke føres til guiden
        rend2 = calamari(GUIDE)
        rend2.insert(rend2.index('1.  Erik, f. 1650.'), '9.  Gert, f. 1700.')
        recs = records_for(rend2) + [rec(rend2, '9.  Gert', 'G')]
        m2 = build39(rend=rend2, records=recs)
        self.assertEqual(placement(m2, 'G')['reasons'], ['ikke_alignet'])
        self.assertEqual(placement(m2, 'E')['status'], 'machine_ok')

    def test_to_kandidater_er_ikke_fundet(self):
        rend = calamari(GUIDE)
        k = rend.index('Andet Slægtled.')
        rend.insert(k, 'Andet Slægtled.')
        m = build39(rend=rend)
        self.assertEqual(placement(m, 'B')['reasons'], ['overskrift_ikke_fundet:slaegtled'])
        self.assertEqual(placement(m, 'A')['status'], 'machine_ok')

    def test_gruppe_via_beskrivelse(self):
        rend = calamari(GUIDE)
        k = rend.index('I.')
        del rend[k]
        m = build39(rend=rend)
        b = placement(m, 'B')
        self.assertEqual(b['status'], 'machine_ok', b['reasons'])
        self.assertEqual(b['kuld_label'], 'Anna-Reventlows-Børn-med-Bodil-Opdigt')
        kuld = next(h for h in m['headers'] if h['element_id'] == b['header_ids']['kuld'])
        self.assertEqual(kuld['verbatim_text'], BESKRIVELSE)
        self.assertEqual(kuld['parsed']['guide']['value'], 'I')      # guidens romertal kun som sporbarhed
        self.assertEqual(len(kuld['parsed']['guide']['line_sha256']), 64)
        self.assertNotIn('Anna', json.dumps(kuld['parsed']['guide']))

    def test_linje_uden_romertal_kraever_samme_navn(self):
        rend = calamari(GUIDE)
        rend.remove('I')
        m = build39(rend=rend)
        a = placement(m, 'A')
        self.assertEqual((a['status'], a['entry_code']), ('machine_ok', 'I'))
        linje = next(h for h in m['headers'] if h['element_id'] == a['header_ids']['linje'])
        self.assertEqual(linje['parsed']['found_via'], 'navn')
        self.assertEqual(linje['verbatim_text'], 'Den testske Linje af 1500.')
        rend2 = [('Den atter testske Linje af 1500.' if l.startswith('Den testske') else l) for l in rend]
        m2 = build39(rend=rend2)
        self.assertEqual(placement(m2, 'A')['reasons'], ['overskrift_ikke_fundet:linje'])
        self.assertIsNone(placement(m2, 'A')['entry_code'])

    def test_stammesektion_er_entry(self):
        guide = ['### PAGE 499 ###',
                 '                          Den ældre testske Linje.',
                 '                                   I',
                 '1.  Urd, f. 1500.'] + GUIDE
        recs = records_for(calamari(guide)) + [rec(calamari(guide), '1.  Urd', 'U')]
        m = build39(guide=guide, records=recs)
        u = placement(m, 'U')
        self.assertEqual(u['status'], 'machine_ok', u['reasons'])
        self.assertEqual(u['entry_code'], 'Stamme-ældre-testske')
        self.assertEqual(u['generation_local'], 1)          # romertallet er slægtleddet i stammen
        self.assertEqual(u['guide_lokal_id'], 'Stamme-ældre-testske.I.1')
        self.assertNotIn('kuld', u['header_ids'])
        linje = next(h for h in m['headers'] if h['element_id'] == u['header_ids']['linje'])
        self.assertEqual(linje['kind'], 'header_linje')
        self.assertEqual(linje['parsed']['stamme_slug'], 'ældre-testske')
        self.assertEqual(next(h for h in m['headers'] if h['element_id'] == u['header_ids']['slaegtled'])['kind'],
                         'header_slaegtled')
        self.assertTrue(all(m['invariants'].values()), m['invariants'])

    def test_gruppebeskrivelse_efter_romertal_er_ikke_ny_overskrift(self):
        m = build39()
        self.assertEqual(len([h for h in m['headers'] if h['kind'] == 'header_kuld']), 2)   # I og II, ikke 3
        self.assertEqual(placement(m, 'B')['kuld_label'], 'I')

    def test_gruppebeskrivelse_alene_er_kuld(self):
        guide = without(GUIDE, 'I.')
        m = build39(guide=guide)
        b = placement(m, 'B')
        self.assertEqual(b['status'], 'machine_ok', b['reasons'])
        self.assertEqual(b['kuld_label'], 'Anna-Reventlows-Børn-med-Bodil-Opdigt')
        self.assertEqual(b['guide_lokal_id'], 'I.Andet.Anna-Reventlows-Børn-med-Bodil-Opdigt.1')
        self.assertEqual(len([h for h in m['headers'] if h['kind'] == 'header_kuld']), 2)
        self.assertTrue(m['invariants']['segmenter_paritet'])

    def test_nr_brud_og_slaegtled_fald(self):
        guide = [l.replace('2.  Carl', '4.  Carl') for l in GUIDE]
        m = build39(guide=guide)
        self.assertEqual(placement(m, 'C')['reasons'], ['nr_ikke_fortloebende'])
        self.assertEqual(placement(m, 'B')['status'], 'machine_ok')
        self.assertEqual(placement(m, 'D')['status'], 'machine_ok')     # første post i ny gruppe
        self.assertTrue(all(m['invariants'].values()), m['invariants'])
        # slægtled-fald i samme linje: Første efter Andet
        guide2 = GUIDE[:14] + ['                 Første Slægtled.', '2.  Frida, f. 1660.'] + GUIDE[14:]
        rend2 = calamari(guide2)
        recs = records_for(rend2) + [rec(rend2, '2.  Frida', 'F')]
        m2 = build39(guide=guide2, records=recs)
        self.assertEqual(placement(m2, 'F')['reasons'], ['slaegtled_ikke_monoton'])
        self.assertEqual(placement(m2, 'D')['status'], 'machine_ok')
        self.assertTrue(all(m2['invariants'].values()), m2['invariants'])

    def test_flere_personas_i_post_er_unresolved(self):
        rend = calamari(GUIDE)
        a = dict(rec(rend, '1.  Anna', 'A'), persona=True)
        a2 = dict(rec(rend, '1.  Anna', 'A2'), persona=True)       # samme fysiske post
        fact = dict(rec(rend, '1.  Anna', 'A-fakta', kind='fact'), persona=False)
        others = [dict(r, persona=True) for r in records_for(rend)[1:]]
        m = build39(records=[a, a2] + others)
        for key in ('A', 'A2'):
            self.assertEqual(placement(m, key)['status'], 'unresolved', key)
            self.assertIn('flere_personas_i_post', placement(m, key)['reasons'], key)
        self.assertEqual(placement(m, 'B')['status'], 'machine_ok')
        m2 = build39(records=[a, fact] + others)
        self.assertEqual(placement(m2, 'A')['status'], 'machine_ok')
        self.assertEqual(placement(m2, 'A-fakta')['status'], 'machine_ok')
        self.assertTrue(m2['invariants']['section_path_nr_unik'])

    def test_overskrift_paa_postlinje_er_ikke_fundet(self):
        rend = calamari(GUIDE)
        k = rend.index('Første Slægtled.')
        rend[k:k + 2] = ['Første Slægtled. 1.  Anna, f. 1600.']
        m = build39(rend=rend)
        a = placement(m, 'A')
        self.assertEqual((a['status'], a['reasons']), ('unresolved', ['overskrift_ikke_fundet:slaegtled']))
        self.assertTrue(all('Anna' not in h['verbatim_text'] for h in m['headers']))
        self.assertEqual(placement(m, 'B')['status'], 'machine_ok')

    def test_naermeste_overskrift_selvtjek(self):
        # kuld-romertallet står FØR slægtledsoverskriften i renditionen: den nærmeste kuld-overskrift
        # annulleres af den senere slægtledsoverskrift, men header_ids ville pege på den
        rend = calamari(GUIDE)
        i, j = rend.index('Andet Slægtled.'), rend.index('I.')
        rend[i], rend[j] = rend[j], rend[i]
        m = build39(rend=rend)
        b = placement(m, 'B')
        self.assertEqual(b['status'], 'unresolved')
        self.assertIn('uenig:naermeste_overskrift', b['reasons'])
        self.assertIn({'record_key': 'B', 'field': 'naermeste_overskrift'}, m['disagreements'])
        self.assertEqual(placement(build39(), 'B')['status'], 'machine_ok')

    def test_persona_guard_ogsaa_for_ikke_alignede(self):
        rend = calamari(GUIDE)
        rend.insert(rend.index('1.  Erik, f. 1650.'), '9.  Gert, f. 1700.')
        g1 = dict(rec(rend, '9.  Gert', 'G1'), persona=True)
        g2 = dict(rec(rend, '9.  Gert', 'G2'), persona=True)
        m = build39(rend=rend, records=records_for(rend) + [g1, g2])
        for key in ('G1', 'G2'):
            self.assertEqual(placement(m, key)['reasons'], ['ikke_alignet', 'flere_personas_i_post'])

    def test_guide_value_uden_tekst(self):
        m = build39()
        for h in m['headers']:
            v = h['parsed']['guide']['value']
            self.assertTrue(v is None or isinstance(v, int) or v in ('I', 'II'), v)
        ms = build39(guide=['### PAGE 499 ###', '                          Den ældre testske Linje.',
                            '                                   I', '1.  Urd, f. 1500.'] + GUIDE)
        self.assertNotIn('testske', json.dumps([h['parsed']['guide'] for h in ms['headers']]))

    def test_gruppe_flere_familier(self):
        parents = [{'child': 'B', 'parent': 'A'}, {'child': 'C', 'parent': 'E'}]
        m = build39(parents=parents)
        for key in ('B', 'C'):
            self.assertIn('gruppe_flere_familier', placement(m, key)['reasons'], key)
            self.assertEqual(placement(m, key)['status'], 'unresolved')
        for key in ('A', 'D', 'E'):
            self.assertEqual(placement(m, key)['status'], 'machine_ok', key)
        same = build39(parents=[{'child': 'B', 'parent': 'A'}, {'child': 'C', 'parent': 'A'}])
        self.assertEqual(placement(same, 'B')['status'], 'machine_ok')

    def test_foraelder_generation_og_legacy(self):
        m = build39(parents=[{'child': 'D', 'parent': 'B'}])         # samme slægtled → brud
        self.assertIn('uenig:foraelder_generation', placement(m, 'D')['reasons'])
        rend = calamari(GUIDE)
        recs = records_for(rend)
        recs[1]['legacy'] = {'linje': 'II', 'nr': 7}
        recs[2]['legacy'] = {'linje': '1939', 'nr': 7}                # '1939' er ikke en linje: ingen sammenligning
        m2 = build39(records=recs)
        self.assertEqual(placement(m2, 'B')['reasons'], ['uenig:legacy_linje', 'uenig:legacy_nr'])
        self.assertEqual(placement(m2, 'C')['status'], 'machine_ok')
        self.assertIn({'record_key': 'B', 'field': 'legacy_nr'}, m2['disagreements'])

    def test_segmenter_paritet(self):
        self.assertTrue(build39()['invariants']['segmenter_paritet'])
        orig = segment._segment_1939

        def afvigende(lines, profile):
            posts = orig(lines, profile)
            posts[0]['lokal_id'] = 'X.Y.1'
            return posts
        with mock.patch.object(segment, '_segment_1939', afvigende):
            self.assertFalse(build39()['invariants']['segmenter_paritet'])

    def test_sha_vagter(self):
        rend = rendition(*calamari(GUIDE))
        guide = rendition(*GUIDE)
        ok = dict(PROFILE_1939, raw_text_sha256=hashlib.sha256(rend).hexdigest(),
                  guide_text_sha256=hashlib.sha256(guide).hexdigest())
        bhm.build_manifest_by_offset(rend, guide, ok, [], [])
        with self.assertRaisesRegex(bhm.HeaderManifestError, 'HEADER_RENDITION_SHA_MISMATCH'):
            bhm.build_manifest_by_offset(rend, guide, dict(ok, raw_text_sha256='0' * 64), [], [])
        with self.assertRaisesRegex(bhm.HeaderManifestError, 'HEADER_GUIDE_SHA_MISMATCH'):
            bhm.build_manifest_by_offset(rend, guide, dict(ok, guide_text_sha256='0' * 64), [], [])

    def test_offsets_renditionsabsolutte(self):
        rend = ['Forord æøå'] + calamari(GUIDE)       # forskyder alle offsets
        text = '\n'.join(rend) + '\n'
        m = build39(rend=rend)
        self.assertEqual(len(m['headers']), 7)
        for h in m['headers']:
            self.assertEqual(project_rendition(text[h['char_from']:h['char_to']])[0], h['verbatim_text'])
            self.assertFalse(text[h['char_from']].isspace())
            self.assertFalse(text[h['char_to'] - 1].isspace())
            self.assertEqual(h['element_id'], f"header:{h['char_from']}")
        linje = next(h for h in m['headers'] if h['kind'] == 'header_linje')
        self.assertEqual(linje['verbatim_text'], 'I Den testske Linje af 1500.')
        self.assertEqual((linje['page_from'], linje['page_to']), (500, 500))

    def test_summary_uden_tekst(self):
        s = bhm.summary(build39())
        txt = repr(s)
        for ord_ in ('Anna', 'Bodil', 'Opdigt', 'testske', 'prøvende', 'Testrup', 'Reventlow'):
            self.assertNotIn(ord_, txt)
        self.assertEqual(s['counts']['headers'], {'header_linje': 2, 'header_slaegtled': 3, 'header_kuld': 2})
        self.assertEqual(s['transfer']['linje'], {'guide': 2, 'genfundet': 2, 'ikke_genfundet': 0})
        self.assertNotIn('transfer', bhm.summary(build()))      # 2018-20-summary uændret


# ---------------------------------------------------------------------------------------------
# 1939: unummererede records parres med raw.txt's v2-poster (Task 1b)
# ---------------------------------------------------------------------------------------------
OVERSIGT = '      Personer af Navnet Reventlow, der ikke kan anvises Plads'
GUIDE_U = [
    '### PAGE 600 ###',
    '                                   I',
    '      Den testske Linje af 1500.',
    '                          (S. 5).',
    '                 Første Slægtled.',
    'A n d e r s  T e s t e s e n ,  f. 1590.',
    '    Boede paa Testrup.',
    '                 Andet Slægtled.',
    '1.  Bent, f. 1630.',
    '2.  Carl, f. 1632.',
]
OVERSIGT_LINJER = [
    '### PAGE 601 ###',
    OVERSIGT,
    'P e r  U d e n  P l a d s ,  f. 1700.',
    'R a s m u s  U d e n ,  f. 1701.',
]


def unspace(guide):
    """Calamari-form: ucentreret, og de adskilte bogstaver i navnesatserne er samlet."""
    out = []
    for l in guide:
        t = l.strip()
        if t.startswith(('A n d', 'P e r', 'R a s', 'S v e', 'T o r')):
            t = ' '.join(x if x.startswith('f.') else x.replace(' ', '') for x in t.split('  '))
        out.append(t)
    return out


def recs_u(rend, extra=()):
    out = [rec(rend, '1.  Bent', 'B'), rec(rend, '2.  Carl', 'C')]
    for needle, key in extra:
        out.append(rec(rend, needle, key))
    return out


class Test1939Unummererede(unittest.TestCase):
    def test_stamfader_placeres_uden_nummer(self):
        rend = unspace(GUIDE_U)
        self.assertIn('Anders Testesen, f. 1590.', rend)
        m = build39(guide=GUIDE_U, rend=rend, records=recs_u(rend, [('Anders Testesen', 'S')]))
        s = placement(m, 'S')
        self.assertEqual((s['status'], s['reasons']), ('machine_ok', []))
        self.assertIsNone(s['printed_number'])
        self.assertEqual((s['entry_code'], s['generation_local'], s['guide_lokal_id']), ('I', 1, 'I.Første.U1'))
        self.assertEqual(set(s['header_ids']), {'linje', 'slaegtled'})
        self.assertEqual(placement(m, 'B')['generation_local'], 2)
        self.assertTrue(all(m['invariants'].values()), m['invariants'])
        self.assertEqual(m['alignment']['parret_stamfader'], 1)

    def test_nummer_tabt_i_rendition(self):
        rend = [l.replace('2.  Carl', 'Carl') for l in unspace(GUIDE_U)]
        m = build39(guide=GUIDE_U, rend=rend, records=[rec(rend, '1.  Bent', 'B'),
                    rec(rend, 'Carl, f. 1632', 'C'), rec(rend, 'Anders Testesen', 'S')])
        c = placement(m, 'C')
        self.assertEqual((c['status'], c['reasons']), ('unresolved', ['nummer_tabt_i_rendition']))
        self.assertEqual(c['guide_nr_label'], '2')
        self.assertIsNone(c['printed_number'])
        self.assertEqual(placement(m, 'S')['status'], 'machine_ok')
        self.assertEqual(m['alignment']['parret_nummereret'], 1)

    def test_oversigtspost_er_uden_post(self):
        guide = GUIDE_U + OVERSIGT_LINJER
        rend = unspace(guide)
        m = build39(guide=guide, rend=rend, records=recs_u(rend, [('Per Uden', 'O1'), ('Rasmus Uden', 'O2')]))
        for key in ('O1', 'O2'):
            self.assertEqual((placement(m, key)['status'], placement(m, key)['reasons']), ('unresolved', ['uden_post']))
        self.assertEqual(m['alignment']['parret_oversigt'], 2)
        self.assertEqual(placement(m, 'B')['status'], 'machine_ok')

    def test_uparret_hul_med_og_uden_persona(self):
        guide = GUIDE_U + OVERSIGT_LINJER[:3]            # kun én oversigtspost i guiden
        rend = unspace(GUIDE_U + OVERSIGT_LINJER)        # men to i renditionen
        recs = recs_u(rend, [('Per Uden', 'O1'), ('Rasmus Uden', 'O2')])
        recs[2]['persona'] = True
        m = build39(guide=guide, rend=rend, records=recs)
        o1, o2 = placement(m, 'O1'), placement(m, 'O2')
        self.assertEqual((o1['status'], o1['reasons']), ('unresolved', ['ikke_parret']))
        self.assertEqual(o1['guide_kandidater'], ['Oversigt.Uplacerede.U1'])
        self.assertEqual((o2['status'], o2['reasons']), ('unresolved', ['uden_post']))
        self.assertEqual(m['alignment']['uparret'], 2)

    def test_unummererede_samme_char_from_er_een_post(self):
        rend = unspace(GUIDE_U)
        recs = recs_u(rend, [('Anders Testesen', 'S1'), ('Anders Testesen', 'S2')])
        m = build39(guide=GUIDE_U, rend=rend, records=recs)
        s1, s2 = placement(m, 'S1'), placement(m, 'S2')
        for x in (s1, s2):
            self.assertEqual((x['status'], x['reasons'], x['printed_number']), ('machine_ok', [], None))
        self.assertEqual(s1['post_char_from'], s2['post_char_from'])
        a = m['alignment']
        self.assertEqual((a['unummererede'], a['unummererede_records'], a['parret_stamfader']), (1, 2, 1))
        for r in recs[2:]:
            r['persona'] = True
        m2 = build39(guide=GUIDE_U, rend=rend, records=recs)
        for key in ('S1', 'S2'):
            self.assertEqual(placement(m2, key)['reasons'], ['flere_personas_i_post'])

    def test_selvtjek_ogsaa_for_stamme_post_uden_afsnit(self):
        guide = ['### PAGE 499 ###', '                          Den ældre testske Linje.',
                 '                 Første Slægtled.', '1.  Urd, f. 1500.']
        rend = calamari(guide)
        m = build39(guide=guide, rend=rend, records=[rec(rend, '1.  Urd', 'U')])
        u = placement(m, 'U')
        self.assertIsNone(u['guide_lokal_id'])
        self.assertEqual((u['status'], u['reasons']), ('machine_ok', []))
        rend2 = [rend[0], rend[2], rend[1], rend[3]]       # slægtled FØR linjen: nærmeste-reglen brydes
        m2 = build39(guide=guide, rend=rend2, records=[rec(rend2, '1.  Urd', 'U')])
        self.assertIn('uenig:naermeste_overskrift', placement(m2, 'U')['reasons'])

    def test_kandidater_uden_none(self):
        guide = GUIDE_U + OVERSIGT_LINJER[:3]
        rend = unspace(GUIDE_U + OVERSIGT_LINJER)
        recs = recs_u(rend, [('Per Uden', 'O1'), ('Rasmus Uden', 'O2')])
        recs[2]['persona'] = True
        m = build39(guide=guide, rend=rend, records=recs)
        self.assertNotIn(None, placement(m, 'O1')['guide_kandidater'])

    def test_to_stamfaedre_samme_section_path_bryder_invariant(self):
        guide = GUIDE_U[:5] + ['                                   I.', 'A n d e r s  T e s t e s e n ,  f. 1590.',
                               '', '                      ' + BESKRIVELSE, 'S v e n d  T e s t e s e n ,  f. 1591.'] + GUIDE_U[7:]
        rend = unspace(guide)
        m = build39(guide=guide, rend=rend,
                    records=recs_u(rend, [('Anders Testesen', 'S1'), ('Svend Testesen', 'S2')]))
        s1, s2 = placement(m, 'S1'), placement(m, 'S2')
        self.assertEqual((s1['status'], s2['status']), ('machine_ok', 'machine_ok'), (s1['reasons'], s2['reasons']))
        self.assertEqual(s1['section_path'], s2['section_path'])
        self.assertFalse(m['invariants']['section_path_nr_unik'])

    def test_summary_uden_tekst(self):
        guide = GUIDE_U + OVERSIGT_LINJER
        rend = unspace(guide)
        m = build39(guide=guide, rend=rend, records=recs_u(rend, [('Anders Testesen', 'S'), ('Per Uden', 'O1')]))
        s = bhm.summary(m)
        a = s['alignment']
        for k in ('unummererede', 'parret_stamfader', 'parret_nummereret', 'parret_oversigt', 'uparret'):
            self.assertIsInstance(a[k], int, k)
        txt = repr(s)
        for ord_ in ('Oversigt', 'Uplacerede', 'U1', 'Anders', 'Testesen', 'Uden'):
            self.assertNotIn(ord_, txt)


if __name__ == '__main__':
    unittest.main()
