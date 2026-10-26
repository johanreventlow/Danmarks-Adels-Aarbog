import os, sys, unittest
sys.path.insert(0, os.path.dirname(__file__))
import build_header_manifest as bhm
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


if __name__ == '__main__':
    unittest.main()
