import hashlib, os, sys, unittest
sys.path.insert(0, os.path.dirname(__file__))
import lineage_mapping_sheet as lms
from decision_sheet_core import SheetError


def hdr(cf, parsed, text):
    return {'element_id': f'header:{cf}', 'kind': 'header_linje', 'char_from': cf, 'verbatim_text': text,
            'verbatim_sha256': hashlib.sha256(text.encode()).hexdigest(), 'parsed': parsed}


def pl(key, code):
    return {'record_key': key, 'entry_code': code, 'status': 'machine_ok', 'reasons': [], 'header_ids': {}}


def manifest():
    """Grene: VI (eksisterende), I (klart flertal), II (70/30), III (ingen modparter), Stamme-alfa."""
    hs = [hdr(1, {'roman': 'I'}, 'Linje Aa'), hdr(2, {'roman': 'II'}, 'Linje Bb'), hdr(3, {'roman': 'III'}, 'Linje Cc'),
          hdr(4, {'roman': 'VI'}, 'Linje Dd'), hdr(5, {'stamme_slug': 'alfa'}, 'Stamme Ee')]
    ps = ([pl(f'I-{n}', 'I') for n in range(1, 11)] + [pl(f'II-{n}', 'II') for n in range(1, 11)]
          + [pl('III-1', 'III'), pl('VI-1', 'VI'), pl('A-1', 'Stamme-alfa')])
    return {'headers': hs, 'placements': ps}


def export():
    cps = [{'record_key': f'I-{n}', 'lineage_kode': 'X', 'source_id': 1} for n in range(1, 10)]
    cps += [{'record_key': 'I-10', 'lineage_kode': 'Y', 'source_id': 1}]
    cps += [{'record_key': f'II-{n}', 'lineage_kode': 'X', 'source_id': 1} for n in range(1, 8)]
    cps += [{'record_key': f'II-{n}', 'lineage_kode': 'Y', 'source_id': 1} for n in range(8, 11)]
    cps += [{'record_key': 'A-1', 'lineage_kode': 'Z', 'source_id': 2}]   # ikke 2018-20: tæller ikke
    return {'entries': ['VI'], 'records': [], 'parents': [], 'counterparts': cps}


def answered(token, answers):
    out = []
    for line in token.splitlines():
        if line.startswith('L '):
            code = line.split()[1]
            if code in answers:
                line = line.rstrip(' ') + ' ' + answers[code] if line.endswith(': ') or line.endswith(':') else line
        out.append(line)
    return '\n'.join(out) + '\n'


class TestRender(unittest.TestCase):
    def test_forslag_ved_klart_flertal(self):
        _, tok = lms.render(manifest(), export())
        self.assertIn('L I : C X', tok.splitlines())     # 9/10 = 90 %, anden linje 1 <= 2

    def test_intet_forslag_ved_70_30(self):
        _, tok = lms.render(manifest(), export())
        self.assertIn('L II : ', tok.splitlines())        # 7/10 og anden linje 3: intet forslag
        self.assertIn('L III : ', tok.splitlines())       # ingen modparter
        self.assertIn('L Stamme-alfa : ', tok.splitlines())  # kun kilde 2 -> ingen 2018-20-fordeling

    def test_fordeling_i_arket(self):
        ark, _ = lms.render(manifest(), export())
        self.assertIn('X=9', ark)
        self.assertIn('Y=3', ark)

    def test_vi_bevares(self):
        _, tok = lms.render(manifest(), export())
        self.assertIn('L VI : C VI', tok.splitlines())

    def test_grenrækkefølge_giver_sort_order(self):
        ark, tok = lms.render(manifest(), export())
        sha = hashlib.sha256(ark.encode()).hexdigest()
        res = lms.approvals(answered(tok, {'II': 'P', 'III': 'P', 'Stamme-alfa': 'P'}), manifest(), export(), sha)
        self.assertEqual([e['code'] for e in res['entries']], ['I', 'II', 'III', 'VI', 'Stamme-alfa'])
        self.assertEqual([e['sort_order'] for e in res['entries']], [1, 2, 3, 4, 5])


class TestApprovals(unittest.TestCase):
    def setUp(self):
        self.m, self.ex = manifest(), export()
        self.ark, self.tok = lms.render(self.m, self.ex)
        self.sha = hashlib.sha256(self.ark.encode()).hexdigest()

    def test_ubesvaret_linje_afvises(self):
        with self.assertRaises(SheetError) as e:
            lms.approvals(self.tok, self.m, self.ex, self.sha)
        self.assertEqual(str(e.exception).split()[0], 'SHEET_UNANSWERED')

    def test_parkering(self):
        res = lms.approvals(answered(self.tok, {'II': 'P', 'III': 'P', 'Stamme-alfa': 'P'}), self.m, self.ex, self.sha)
        ii = next(e for e in res['entries'] if e['code'] == 'II')
        self.assertTrue(ii['parkeret'])
        self.assertIsNone(ii['canonical'])
        self.assertEqual(ii['aliases'], [])
        self.assertEqual(res['sheet_sha256'], self.sha)

    def test_canonical_alias_og_kilde3(self):
        res = lms.approvals(answered(self.tok, {'II': 'C Y, A X', 'III': 'S IV', 'Stamme-alfa': 'P'}),
                            self.m, self.ex, self.sha)
        by = {e['code']: e for e in res['entries']}
        self.assertEqual(by['II']['canonical'], {'source_id': 1, 'kode': 'Y'})
        self.assertEqual(by['II']['aliases'], [{'source_id': 1, 'kode': 'X'}])
        self.assertFalse(by['II']['parkeret'])
        self.assertEqual(by['III']['canonical'], {'source_id': 3, 'kode': 'IV'})
        self.assertEqual(by['I']['canonical'], {'source_id': 1, 'kode': 'X'})   # forudfyldt forslag
        self.assertEqual(by['VI']['canonical'], {'source_id': 3, 'kode': 'VI'})
        self.assertEqual(by['VI']['label_sha256'], hashlib.sha256('Linje Dd'.encode()).hexdigest())

    def test_vi_kan_ikke_aendres(self):
        bad = answered(self.tok, {'II': 'P', 'III': 'P', 'Stamme-alfa': 'P'}).replace('L VI : C VI', 'L VI : P')
        with self.assertRaises(SheetError) as e:
            lms.approvals(bad, self.m, self.ex, self.sha)
        self.assertEqual(str(e.exception).split()[0], 'SHEET_TOKEN_NOT_ALLOWED')

    def test_ugyldigt_token_og_manglende_linje_og_forkert_ark(self):
        ok = answered(self.tok, {'II': 'P', 'III': 'P', 'Stamme-alfa': 'P'})
        for bad, code in ((ok.replace('L II : P', 'L II : Q'), 'SHEET_TOKEN_NOT_ALLOWED'),
                          (ok.replace('L II : P', 'L II : P, C X'), 'SHEET_TOKEN_NOT_ALLOWED'),
                          ('\n'.join(l for l in ok.splitlines() if not l.startswith('L III ')), 'SHEET_LINES_MISSING')):
            with self.assertRaises(SheetError) as e:
                lms.approvals(bad, self.m, self.ex, self.sha)
            self.assertEqual(str(e.exception).split()[0], code)
        with self.assertRaises(SheetError) as e:
            lms.approvals(ok, self.m, self.ex, 'f' * 64)
        self.assertEqual(str(e.exception).split()[0], 'SHEET_SHA_MISMATCH')

    def test_stdout_uden_navne(self):
        s = lms.summary(self.m, self.ex)
        for name in ('Linje', 'Stamme Ee', 'Aa'):
            self.assertNotIn(name, s)
        self.assertRegex(s, r'^ARK_OK grene=5 forslag=1$')


if __name__ == '__main__':
    unittest.main()
