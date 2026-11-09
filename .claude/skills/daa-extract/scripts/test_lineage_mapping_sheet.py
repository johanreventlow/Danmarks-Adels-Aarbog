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
        self.assertIn('L VI : S VI', tok.splitlines())

    def test_grenrækkefølge_giver_sort_order(self):
        ark, tok = lms.render(manifest(), export())
        sha = hashlib.sha256(ark.encode()).hexdigest()
        res = lms.approvals(answered(tok, {'II': 'P', 'III': 'P', 'Stamme-alfa': 'P'}), manifest(), export(), sha)
        self.assertEqual([e['code'] for e in res['entries']], ['I', 'II', 'III', 'VI', 'Stamme-alfa'])
        self.assertEqual([e['sort_order'] for e in res['entries']], [1, 2, 3, 4, 5])


class TestRaekkefoelge(unittest.TestCase):
    def test_sort_order_er_bogens_orden(self):
        m = manifest()
        pos = {'IV': 50, 'I': 10, 'III': 40, 'II': 30, 'Stamme-alfa': 90, 'VI': 70}
        for h in m['headers']:
            pr = h['parsed']
            h['char_from'] = pos[pr.get('roman') or f"Stamme-{pr['stamme_slug']}"]
        m['headers'].append(hdr(50, {'roman': 'IV'}, 'Linje Ff'))
        m['placements'].append(pl('IV-1', 'IV'))
        m['placements'].insert(0, pl('VI-0', 'VI'))   # VI optræder først i placements, men står sent i bogen
        ex = export()
        ark, tok = lms.render(m, ex)
        sha = hashlib.sha256(ark.encode()).hexdigest()
        res = lms.approvals(answered(tok, {c: 'P' for c in ('II', 'III', 'IV', 'Stamme-alfa')}), m, ex, sha)
        self.assertEqual([(e['code'], e['sort_order']) for e in res['entries']],
                         [('I', 1), ('II', 2), ('III', 3), ('IV', 4), ('VI', 5), ('Stamme-alfa', 6)])
        self.assertIn('(rækkefølge 5;', ark)


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
        bad = answered(self.tok, {'II': 'P', 'III': 'P', 'Stamme-alfa': 'P'}).replace('L VI : S VI', 'L VI : P')
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

    def _ok(self):
        return answered(self.tok, {'II': 'P', 'III': 'P', 'Stamme-alfa': 'P'})

    def _fejl(self, text, code, sha=None):
        with self.assertRaises(SheetError) as e:
            lms.approvals(text, self.m, self.ex, sha or self.sha)
        self.assertEqual(str(e.exception).split()[0], code)

    def test_vi_c_afvises(self):
        self._fejl(self._ok().replace('L VI : S VI', 'L VI : C VI'), 'SHEET_TOKEN_NOT_ALLOWED')

    def test_alias_uden_canonical_og_alias_regler(self):
        self._fejl(answered(self.tok, {'II': 'A X', 'III': 'P', 'Stamme-alfa': 'P'}), 'SHEET_TOKEN_NOT_ALLOWED')
        self._fejl(answered(self.tok, {'II': 'C X, A X', 'III': 'P', 'Stamme-alfa': 'P'}), 'SHEET_TOKEN_NOT_ALLOWED')
        self._fejl(answered(self.tok, {'II': 'C Y, A X, A X', 'III': 'P', 'Stamme-alfa': 'P'}), 'SHEET_TOKEN_NOT_ALLOWED')

    def test_dobbelt_l_linje_og_vildfarne_linjer(self):
        self._fejl(self._ok() + 'L II : P\n', 'SHEET_LINE_INVALID')
        self._fejl(self._ok() + 'C II\n', 'SHEET_LINE_INVALID')

    def test_ark_sha_linje(self):
        no_sha = '\n'.join(l for l in self._ok().splitlines() if not l.startswith('# ark-sha256'))
        self._fejl(no_sha, 'SHEET_SHA_MISMATCH')
        self._fejl(self._ok().replace(self.sha, 'a' * 64), 'SHEET_SHA_MISMATCH')

    def test_forældet_ark_afvises(self):
        # Codex 9/11 fund 2: arket skal være det, det aktuelle manifest renderer; ellers har projektejeren godkendt en
        # anden rækkefølge eller fordeling end den, approvals bruger.
        import copy
        ok = self._ok()
        flyttet = copy.deepcopy(self.m)
        flyttet['placements'][0]['entry_code'] = None                 # fordelingen ændres (I: 10 → 9)
        with self.assertRaises(SheetError) as e:
            lms.approvals(ok, flyttet, self.ex, self.sha)
        self.assertEqual(str(e.exception).split()[0], 'SHEET_STALE')
        byttet = copy.deepcopy(self.m)
        byttet['headers'][0]['char_from'], byttet['headers'][1]['char_from'] = 2, 1   # rækkefølgen ændres
        with self.assertRaises(SheetError) as e:
            lms.approvals(ok, byttet, self.ex, self.sha)
        self.assertEqual(str(e.exception).split()[0], 'SHEET_STALE')

    def test_token_sha_med(self):
        txt = self._ok()
        self.assertEqual(lms.approvals(txt, self.m, self.ex, self.sha)['token_sha256'],
                         hashlib.sha256(txt.encode()).hexdigest())

    def test_gren_uden_label_afvises_ved_render(self):
        m = manifest()
        m['headers'] = [h for h in m['headers'] if h['parsed'].get('roman') != 'III']
        with self.assertRaises(SheetError) as e:
            lms.render(m, self.ex)
        self.assertEqual(str(e.exception).split()[0], 'LABEL_MANGLER')

    def test_cli_rundtur(self):
        import contextlib, io, json, tempfile
        from pathlib import Path
        with tempfile.TemporaryDirectory() as d:
            root = Path(d) / 'priv'
            root.mkdir(mode=0o700)
            (root / 'm.json').write_text(json.dumps(self.m))
            (root / 'e.json').write_text(json.dumps(self.ex))
            base = ['--manifest', str(root / 'm.json'), '--export', str(root / 'e.json'), '--private-root', str(root)]

            def run(argv):
                buf = io.StringIO()
                old = sys.argv
                sys.argv = ['x'] + argv
                try:
                    with contextlib.redirect_stdout(buf):
                        rc = lms.main()
                finally:
                    sys.argv = old
                return rc, buf.getvalue().strip()
            rc, out = run(['render'] + base + ['--out-ark', str(root / 'a.txt'), '--out-token', str(root / 't.txt')])
            self.assertEqual((rc, out), (0, 'ARK_OK grene=5 forslag=1'))
            tok = answered((root / 't.txt').read_text(), {'II': 'P', 'III': 'P', 'Stamme-alfa': 'P'})
            (root / 't.txt').write_text(tok)
            sha = hashlib.sha256((root / 'a.txt').read_bytes()).hexdigest()
            rc, out = run(['approvals'] + base + ['--ark', str(root / 'a.txt'), '--token', str(root / 't.txt'),
                                                  '--approved-ark-sha256', sha, '--out', str(root / 'o.json')])
            self.assertEqual((rc, out), (0, 'APPROVALS_OK grene=5 parkeret=3 delt_canonical=0'))
            res = json.loads((root / 'o.json').read_text())
            self.assertEqual(res['sheet_sha256'], sha)
            self.assertEqual(res['token_sha256'], hashlib.sha256(tok.encode()).hexdigest())

    def test_stdout_uden_navne(self):
        s = lms.summary(self.m, self.ex)
        for name in ('Linje', 'Stamme Ee', 'Aa'):
            self.assertNotIn(name, s)
        self.assertRegex(s, r'^ARK_OK grene=5 forslag=1$')


if __name__ == '__main__':
    unittest.main()
