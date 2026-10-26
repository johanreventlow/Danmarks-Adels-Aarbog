import hashlib, os, sys, unittest
sys.path.insert(0, os.path.dirname(__file__))
import placement_control_sheet as pcs
from decision_sheet_core import SheetError


def h(kind, cf, page, parsed):
    return {'element_id': f'header:{cf}', 'kind': kind, 'char_from': cf, 'page_from': page, 'page_to': page,
            'verbatim_text': 'x', 'parsed': parsed}


def p(key, ids, gen, label, kuld=None, status='machine_ok', reasons=(), page=10):
    linje, nr = key.split('-')
    return {'record_key': key, 'entry_code': linje, 'printed_number': nr, 'generation_local': gen,
            'generation_label_raw': label, 'generation_global': None, 'kuld_label': kuld, 'page': page,
            'header_ids': ids, 'status': status, 'reasons': list(reasons)}


def manifest():
    """Linje I og II; I har to slægtled (det andet med to kuld), II ét slægtled uden kuld, hvor tre poster er
    unresolved på kuld, og to på forælder-generation."""
    hs = [h('header_linje', 100, 10, {'roman': 'I'}), h('header_slaegtled', 200, 10, {'ordinal': 1, 'label_raw': 'Første'}),
          h('header_slaegtled', 400, 11, {'ordinal': 2, 'label_raw': 'Andet'}), h('header_kuld', 500, 11, {'kuld': 'I'}),
          h('header_kuld', 700, 12, {'kuld': 'II'}), h('header_linje', 1000, 20, {'roman': 'II'}),
          h('header_slaegtled', 1100, 20, {'ordinal': 1, 'label_raw': 'Første'})]
    L1, S1, S2, K1, K2, L2, T1 = (f'header:{c}' for c in (100, 200, 400, 500, 700, 1000, 1100))
    ps = [p('I-1', {'linje': L1, 'slaegtled': S1}, 1, 'Første')]
    ps += [p(f'I-{n}', {'linje': L1, 'slaegtled': S2, 'kuld': K1}, 2, 'Andet', 'I', page=11) for n in range(2, 12)]
    ps += [p(f'I-{n}', {'linje': L1, 'slaegtled': S2, 'kuld': K2}, 2, 'Andet', 'II', page=12) for n in range(12, 30)]
    ps += [p('II-1', {'linje': L2, 'slaegtled': T1}, 1, 'Første', page=20)]
    ps += [p(f'II-{n}', {'linje': L2, 'slaegtled': T1}, 1, 'Første', status='unresolved', reasons=['uenig:kuld'], page=20)
           for n in (2, 3, 4)]
    ps += [p('II-5', {'linje': L2, 'slaegtled': T1}, 1, 'Første', status='unresolved',
             reasons=['uenig:kuld', 'uenig:foraelder_generation'], page=21),
           p('II-6', {'linje': L2, 'slaegtled': T1}, 1, 'Første', status='unresolved',
             reasons=['uenig:foraelder_generation'], page=21)]
    return {'header_rule_version': 'header-2018-20-v1', 'headers': hs, 'placements': ps,
            'invariants': {}, 'disagreements': []}


class TestKontrolark(unittest.TestCase):
    def test_stratificeret_og_deterministisk(self):
        m = manifest()
        a, b = pcs.sample(m, k=12, seed=150), pcs.sample(m, k=12, seed=150)
        self.assertEqual(a, b)
        self.assertEqual(len(a), 12)
        self.assertEqual(len(set(a)), 12)
        ok = {x['record_key'] for x in m['placements'] if x['status'] == 'machine_ok'}
        self.assertTrue(set(a) <= ok)                     # kun poster, der accepteres maskinelt
        for first in ('I-1', 'II-1', 'I-2', 'I-12'):      # første efter linje, slægtled og kuld
            self.assertIn(first, a)
        self.assertIn('I-29', a)                          # sidste post i det længste slægtled

    def test_ark_er_blindt(self):
        m = manifest()
        text = pcs.render_kontrolark(m, pcs.sample(m, k=12, seed=150))
        lines = [l for l in text.splitlines() if l.startswith('K ')]
        self.assertEqual(len(lines), 12)
        for l in lines:
            self.assertRegex(l, r'^K [IV]+-\d+[a-z]? side \d+ : $')   # intet forudfyldt, ingen maskinværdi
        self.assertNotIn('Andet', text)

    def test_kontrol_sammenligner(self):
        m = manifest()
        keys = ['I-1', 'I-12']
        text = pcs.render_kontrolark(m, keys)
        svar = text.replace('K I-1 side 10 : ', 'K I-1 side 10 : 1 -').replace('K I-12 side 12 : ', 'K I-12 side 12 : 2 II')
        self.assertEqual(pcs.check_kontrolark(svar, m), keys)
        forkert = svar.replace('K I-12 side 12 : 2 II', 'K I-12 side 12 : 2 I')
        with self.assertRaises(SheetError) as e:
            pcs.check_kontrolark(forkert, m)
        self.assertEqual(str(e.exception).split()[0], 'KONTROL_AFVIGELSE')
        with self.assertRaises(SheetError) as e:
            pcs.check_kontrolark(text, m)
        self.assertEqual(str(e.exception).split()[0], 'SHEET_UNANSWERED')


class TestTokenfil(unittest.TestCase):
    def test_grupper(self):
        g = pcs.groups(manifest())
        self.assertEqual([(x['kind'], x['record_keys']) for x in g],
                         [('kuld', ['II-2', 'II-3', 'II-4', 'II-5']), ('foraelder_generation', ['II-5', 'II-6'])])

    def test_token_uden_forudfyldte_svar(self):
        text = pcs.render_token(manifest())
        g = [l for l in text.splitlines() if l.startswith('G ')]
        self.assertEqual(g, ['G kuld:header:1100 : ', 'G foraelder_generation:header:1100 : '])

    def test_godkendelser(self):
        m = manifest()
        text = pcs.render_token(m)
        both = text.replace('G kuld:header:1100 : ', 'G kuld:header:1100 : J').replace(
            'G foraelder_generation:header:1100 : ', 'G foraelder_generation:header:1100 : A')
        sha = hashlib.sha256(both.encode()).hexdigest()
        self.assertEqual(pcs.approvals(both, m, sha)['record_keys'], ['II-2', 'II-3', 'II-4', 'II-5', 'II-6'])
        kun_kuld = both.replace('foraelder_generation:header:1100 : A', 'foraelder_generation:header:1100 : U')
        # II-5 har begge årsager; den godkendes kun, når begge grupper godkendes.
        self.assertEqual(pcs.approvals(kun_kuld, m, sha)['record_keys'], ['II-2', 'II-3', 'II-4'])
        self.assertEqual(pcs.approvals(kun_kuld, m, sha)['sheet_sha256'], sha)
        for bad, code in ((text, 'SHEET_UNANSWERED'), (both.replace(': J', ': A'), 'SHEET_TOKEN_NOT_ALLOWED')):
            with self.assertRaises(SheetError) as e:
                pcs.approvals(bad, m, sha)
            self.assertEqual(str(e.exception).split()[0], code)


if __name__ == '__main__':
    unittest.main()
