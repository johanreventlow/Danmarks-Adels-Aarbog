import json, os, sys, tempfile, unittest
from pathlib import Path
sys.path.insert(0, os.path.dirname(__file__))
import placement_kort_1939 as pk
from decision_sheet_core import SheetError


def hd(kind, cf, page, **parsed):
    return {'element_id': f'header:{cf}', 'kind': kind, 'char_from': cf, 'page_from': page, 'page_to': page,
            'parsed': parsed}


def pl(key, cf, *, entry='I', nr='1', gen=1, kuld=None, ids=None, status='machine_ok', reasons=(), kind='person',
       page=500, **extra):
    base = {'record_key': key, 'entry_code': entry, 'printed_number': nr, 'generation_local': gen,
            'kuld_label': kuld, 'header_ids': ids or {}, 'status': status, 'reasons': list(reasons),
            'record_kind': kind, 'page': page, 'post_char_from': cf, 'gruppekort': [], 'human_header_levels': [],
            'naermeste_header_ids': None, 'naermeste_entry_code': None, 'naermeste_generation_local': None,
            'naermeste_kuld_label': None, 'guide_nr_label': None, 'guide_kandidater': None}
    base.update(extra)
    return base


L1, S1, S2, K1, K2, L2, T1 = (f'header:{c}' for c in (10, 20, 200, 210, 400, 1000, 1010))
GKID = 'kuld:5000'
GKS = 'slaegtled:5100'


def manifest():
    """Gren I: slægtled 1 (A, B), slægtled 2 med gruppe I (romertal) og gruppe 'Børn af …' (guide: II). Gren II:
    gruppekort-poster, strukturposter, en stammegruppe og et nummerspring. Alle navne er opdigtede."""
    hs = [hd('header_linje', 10, 500, entry_code='I'), hd('header_slaegtled', 20, 500, ordinal=1),
          hd('header_slaegtled', 200, 501, ordinal=2), hd('header_kuld', 210, 501, roman='I', guide={'value': 'I'}),
          hd('header_kuld', 400, 502, guide={'value': 'II'}),
          hd('header_linje', 1000, 510, entry_code='II'), hd('header_slaegtled', 1010, 510, ordinal=1)]
    ps = [pl('A', 30, ids={'linje': L1, 'slaegtled': S1}),
          pl('B', 60, nr='2', ids={'linje': L1, 'slaegtled': S1}, kind='fact'),
          pl('C', 220, gen=2, kuld='I', ids={'linje': L1, 'slaegtled': S2, 'kuld': K1}, page=501),
          pl('D', 410, gen=2, kuld='Børn af Testo', ids={'linje': L1, 'slaegtled': S2, 'kuld': K2}, page=502,
             kind='marriage'),
          pl('E', 1020, entry='II', ids={'linje': L2, 'slaegtled': T1}, page=510)]
    gk = {'id': GKID, 'niveau': 'kuld', 'guide_value': 'III', 'guide_char_from': 5000, 'guide_line_sha256': 'x'}
    gks = {'id': GKS, 'niveau': 'slaegtled', 'guide_value': 2, 'guide_char_from': 5100, 'guide_line_sha256': 'y'}
    ps += [pl('G1', 1100, entry='II', nr='1', gen=1, ids={'linje': L2, 'slaegtled': T1}, status='unresolved',
              reasons=['overskrift_ikke_fundet:kuld'], gruppekort=[gk], human_header_levels=['kuld'], page=511),
           pl('G2', 1150, entry='II', nr='2', gen=1, ids={'linje': L2, 'slaegtled': T1}, status='unresolved',
              reasons=['overskrift_ikke_fundet:kuld', 'nr_ikke_fortloebende'], gruppekort=[gk],
              human_header_levels=['kuld'], page=511),
           pl('G3', 1180, entry='II', nr='1', gen=None, ids={'linje': L2}, status='unresolved',
              reasons=['overskrift_ikke_fundet:slaegtled'], gruppekort=[gks], human_header_levels=['slaegtled'],
              page=512)]
    near = {'linje': L2, 'slaegtled': T1}
    ps += [pl('S1', None, entry=None, nr=None, gen=None, status='unresolved', reasons=['ikke_parret'], page=513,
              naermeste_header_ids=near, naermeste_entry_code='II', naermeste_generation_local=1,
              guide_kandidater=['II.Testsen.7']),
           pl('S2', None, entry=None, nr=None, gen=None, status='unresolved', reasons=['ikke_parret'], page=513,
              naermeste_header_ids=near, naermeste_entry_code='II', naermeste_generation_local=1,
              guide_kandidater=['II.A.3', 'II.B.4']),
           pl('S3', 1300, entry='II', nr='9', gen=None, status='unresolved', reasons=['ikke_alignet'], page=514,
              naermeste_header_ids=near, naermeste_entry_code='II', naermeste_generation_local=1),
           pl('S4', None, entry=None, nr=None, gen=None, status='unresolved', reasons=['nummer_tabt_i_rendition'],
              page=514, naermeste_header_ids=near, naermeste_entry_code='II', naermeste_generation_local=1,
              guide_nr_label='11'),
           pl('U1', 1400, entry='Stamme-test', nr='1', gen=3, kuld='Børn af Testo', ids={'kuld': 'header:1390'},
              status='unresolved', reasons=['stamme_generation_usikker'], page=515),
           pl('U2', 1450, entry='Stamme-test', nr='2', gen=3, kuld='Børn af Testo', ids={'kuld': 'header:1390'},
              status='unresolved', reasons=['stamme_generation_usikker'], page=515),
           pl('N1', 1500, entry='II', nr='5', gen=1, ids={'linje': L2, 'slaegtled': T1}, status='unresolved',
              reasons=['nr_ikke_fortloebende'], page=516),
           pl('X', None, status='unresolved', reasons=['uden_post'], page=517)]
    return {'headers': hs, 'placements': ps}


def records(m):
    return [{'record_key': p['record_key'], 'char_from': p['post_char_from'] if p['post_char_from'] is not None else 1600}
            for p in m['placements']]


RENDITION = ''.join(f'{i % 10}' for i in range(1700))


def svar_for(cards, **over):
    """Modelsvar, der er enige med hvert korts forventede værdier (en anden læsning, hvor None)."""
    out = []
    for c in cards:
        f = c['forventet']
        s = {'kort_id': c['kort_id'], 'fundet': True, 'side': 500, 'sikkerhed': 'hoej',
             'slaegtled': f.get('slaegtled') if f.get('slaegtled') is not None else 1,
             'gruppe': f.get('gruppe') if f.get('gruppe') is not None else '-',
             'nr': f.get('nr') if f.get('nr') is not None else '7'}
        s.update(over.get(c['kort_id'], {}))
        out.append(s)
    return out


def card(cards, kid):
    return next(c for c in cards if c['kort_id'] == kid)


class TestKort(unittest.TestCase):
    def setUp(self):
        self.m = manifest()
        self.cards = pk.kort_1939(self.m, k=4)

    def test_stikproeve_strata_og_kun_machine_ok(self):
        s = pk.sample_1939(self.m, k=20)
        self.assertEqual(s, ['A', 'B', 'C', 'D', 'E'])          # alle 5 machine_ok, i bogens orden
        s4 = pk.sample_1939(self.m, k=4)
        self.assertIn('A', s4)                                 # første efter linje I
        self.assertIn('E', s4)                                 # første efter linje II
        self.assertTrue({'B', 'D'} & set(s4))                  # record_kind ≠ person er med
        self.assertEqual(s4, pk.sample_1939(self.m, k=4))      # fast seed

    def test_korttyper_og_forventninger(self):
        types = [c['type'] for c in self.cards]
        self.assertEqual({t: types.count(t) for t in pk.KORT_TYPER}, {'K': 4, 'GK': 2, 'SK': 4, 'SG': 1, 'NK': 2})
        all20 = pk.kort_1939(self.m)
        self.assertEqual(card(all20, 'K:D')['forventet'], {'slaegtled': 2, 'gruppe': 'II'})   # guidens romertal
        self.assertEqual(card(all20, 'K:C')['forventet'], {'slaegtled': 2, 'gruppe': 'I'})
        self.assertEqual(card(all20, 'K:A')['forventet'], {'slaegtled': 1, 'gruppe': '-'})
        gk = card(self.cards, f'GK:{GKID}')
        self.assertEqual((gk['poster'], gk['forventet'], gk['opslag']), (['G1', 'G2'], {'gruppe': 'III'}, 'G1'))
        self.assertEqual(card(self.cards, f'GK:{GKS}')['forventet'], {'slaegtled': 2})
        self.assertEqual(card(self.cards, 'SK:S1')['forventet'], {'slaegtled': 1, 'gruppe': '-', 'nr': '7'})
        self.assertIsNone(card(self.cards, 'SK:S2')['forventet']['nr'])      # to kandidatnumre: ingen anden læsning
        self.assertEqual(card(self.cards, 'SK:S3')['forventet']['nr'], '9')  # Calamaris nummer
        self.assertEqual(card(self.cards, 'SK:S4')['forventet']['nr'], '11')  # guidens nummer
        sg = card(self.cards, 'SG:header:1390')
        self.assertEqual((sg['poster'], sg['forventet']), (['U1', 'U2'], {'slaegtled': 3}))
        self.assertEqual(card(self.cards, 'NK:G2')['forventet'], {'nr': '2'})
        self.assertNotIn('X', [p for c in self.cards for p in c['poster']])  # uden_post: intet kort

    def test_opslag_er_blinde(self):
        rend = RENDITION[:1300] + '9.  Testo Testesen, f. 1700.' + RENDITION[1328:]
        ops = pk.opslag(self.m, self.cards, records(self.m), rend)
        self.assertEqual({tuple(sorted(o)) for o in ops}, {('gren', 'kort_id', 'side', 'sider', 'start_tekst')})
        s3 = next(o for o in ops if o['kort_id'] == 'SK:S3')
        self.assertTrue(s3['start_tekst'].startswith('Testo Testesen'))      # det trykte nummer er fjernet
        self.assertEqual((s3['gren'], s3['sider']), ('II', [513, 514]))
        self.assertEqual(next(o for o in ops if o['kort_id'] == 'SK:S1')['gren'], 'II')   # nærmeste gren

    def test_vurder(self):
        sk = card(self.cards, 'SK:S3')
        ok = {'fundet': True, 'sikkerhed': 'middel', 'slaegtled': 1, 'gruppe': '-', 'nr': '9.'}
        self.assertEqual(pk.vurder(sk, ok), 'enig')
        self.assertEqual(pk.vurder(sk, dict(ok, nr='8')), 'uenig')
        self.assertEqual(pk.vurder(sk, dict(ok, sikkerhed='lav')), 'ulaeselig')
        self.assertEqual(pk.vurder(sk, dict(ok, fundet=False)), 'ulaeselig')
        self.assertEqual(pk.vurder(sk, dict(ok, slaegtled=None)), 'ulaeselig')
        self.assertEqual(pk.vurder(card(self.cards, 'SK:S2'), ok), 'ingen_anden')
        gk = card(self.cards, f'GK:{GKID}')
        self.assertEqual(pk.vurder(gk, {'fundet': True, 'sikkerhed': 'hoej', 'gruppe': 'iii.'}), 'enig')

    def test_svar_skal_daekke_kortene(self):
        sv = svar_for(self.cards)
        with self.assertRaisesRegex(SheetError, 'KORT_SVAR_MANGLER'):
            pk.vurderinger(self.cards, sv[1:])
        with self.assertRaisesRegex(SheetError, 'KORT_SVAR_UKENDT'):
            pk.vurderinger(self.cards, sv + [dict(sv[0], kort_id='K:Z')])


class TestApprovals(unittest.TestCase):
    def setUp(self):
        self.m = manifest()
        self.cards = pk.kort_1939(self.m, k=4)
        self.kontrol = {'model': 'claude-opus-5-5', 'brief_sha256': 'b', 'svar_sha256': 's'}

    def run_(self, svar, answers=None, v='J'):
        vd = pk.vurderinger(self.cards, svar)
        tok = pk.render_token(self.cards, vd)
        lines = []
        for line in tok.splitlines():
            if line.startswith('U '):
                kid = line.split()[1]
                line += (answers or {})[kid]
            elif line.startswith('V '):
                line += v
            lines.append(line)
        return pk.approvals_1939(self.m, self.cards, svar, '\n'.join(lines) + '\n', manifest_sha256='m' * 64,
                                 kontrol=self.kontrol)

    def test_alle_enige_kun_S2_til_projektejeren(self):
        sv = svar_for(self.cards)
        vd = pk.vurderinger(self.cards, sv)
        self.assertEqual([k for k, v in vd.items() if v != 'enig'], ['SK:S2'])
        res = self.run_(sv, {'SK:S2': '4'})
        self.assertEqual(sorted((g['id'], g['value'], g['reviewer']) for g in res['gruppekort']),
                         [(GKID, 'III', 'model'), (GKS, 2, 'model')])
        ap = {a['record_key']: a for a in res['approvals']}
        self.assertEqual(sorted(ap), ['G2', 'N1', 'S1', 'S2', 'S3', 'S4', 'U1', 'U2'])   # G1/G3: kun gruppekort
        self.assertEqual(ap['S1'], {'record_key': 'S1', 'reviewer': 'model', 'printed_number': '7'})
        self.assertEqual(ap['S2'], {'record_key': 'S2', 'reviewer': 'human', 'printed_number': '4'})
        self.assertEqual(ap['G2'], {'record_key': 'G2', 'reviewer': 'model'})
        self.assertEqual(res['kontrol'], self.kontrol)

    def test_projektejerens_N_lader_poster_staa(self):
        sv = svar_for(self.cards, **{f'GK:{GKID}': {'gruppe': 'IV'}, 'SG:header:1390': {'slaegtled': 4}})
        res = self.run_(sv, {f'GK:{GKID}': 'N', 'SG:header:1390': 'N', 'SK:S2': 'N'})
        self.assertNotIn(GKID, [g['id'] for g in res['gruppekort']])
        ap = {a['record_key'] for a in res['approvals']}
        self.assertFalse(ap & {'G2', 'U1', 'U2', 'S2'})        # G2 kræver også gruppekortet

    def test_projektejeren_bekraefter_guidens_vaerdi(self):
        sv = svar_for(self.cards, **{f'GK:{GKID}': {'gruppe': 'IV'}})
        res = self.run_(sv, {f'GK:{GKID}': 'III', 'SK:S2': '4'})
        self.assertIn((GKID, 'III', 'human'), [(g['id'], g['value'], g['reviewer']) for g in res['gruppekort']])
        # G2's record-godkendelse dækker kun nummerkortet (model); ceremonien kombinerer den med gruppekortets
        # menneskelige læser til reviewer_kind blandet / human_group_review.
        self.assertEqual({a['record_key']: a['reviewer'] for a in res['approvals']}['G2'], 'model')
        with self.assertRaisesRegex(SheetError, 'KORT_ANDEN_VAERDI'):
            self.run_(sv, {f'GK:{GKID}': 'IV', 'SK:S2': '4'})

    def test_stikproeve_afvigelse_stopper(self):
        sv = svar_for(self.cards, **{'K:A': {'slaegtled': 2}})
        self.assertEqual(self.run_(sv, {'K:A': '1 -', 'SK:S2': '4'})['gruppekort'][0]['reviewer'], 'model')
        with self.assertRaisesRegex(SheetError, 'KONTROL_AFVIGELSE K:A'):
            self.run_(sv, {'K:A': '2 -', 'SK:S2': '4'})
        with self.assertRaisesRegex(SheetError, 'KONTROL_AFVIGELSE'):
            self.run_(svar_for(self.cards), {'SK:S2': '4'}, v='N')

    def test_token_form(self):
        sv = svar_for(self.cards)
        vd = pk.vurderinger(self.cards, sv)
        tok = pk.render_token(self.cards, vd)
        self.assertEqual(sum(l.startswith('V ') for l in tok.splitlines()), min(pk.V_ANTAL, 4))
        with self.assertRaisesRegex(SheetError, 'SHEET_UNANSWERED'):
            pk.approvals_1939(self.m, self.cards, sv, tok, manifest_sha256='m', kontrol=self.kontrol)
        with self.assertRaisesRegex(SheetError, 'SHEET_LINES_MISSING'):
            pk.approvals_1939(self.m, self.cards, sv, '# tom\n', manifest_sha256='m', kontrol=self.kontrol)
        with self.assertRaisesRegex(SheetError, 'SHEET_TOKEN_NOT_ALLOWED'):
            self.run_(sv, {'SK:S2': 'fire'})

    def test_unik(self):
        # S3 får S1's nummer (7) under samme nærmeste overskrifter → to poster på samme koordinat.
        self.m['placements'][[p['record_key'] for p in self.m['placements']].index('S3')]['printed_number'] = '7'
        cards = pk.kort_1939(self.m, k=4)
        self.cards = cards
        sv = svar_for(cards)
        with self.assertRaisesRegex(SheetError, 'KORT_UNIK'):
            self.run_(sv, {'SK:S2': '4'})


class TestGruppebeskrivelse(unittest.TestCase):
    """Fællesstammens gruppe er en beskrivelse uden romertal (PDF 503: »VII C. / Lyder Reventlows Søn:«). Kortet kan
    kun bekræftes af projektejeren (J/N); værdien er guidens slug, som ceremonien kræver."""
    def setUp(self):
        self.m = manifest()
        gkb = {'id': 'kuld:6000', 'niveau': 'kuld', 'guide_value': 'Lyder-Testsens-Søn', 'guide_char_from': 6000,
               'guide_line_sha256': 'z'}
        self.m['placements'].append(pl('B1', 1550, entry='Stamme-test', nr=None, gen=7,
                                       ids={'linje': L2, 'slaegtled': T1}, status='unresolved',
                                       reasons=['overskrift_ikke_fundet:kuld'], gruppekort=[gkb],
                                       human_header_levels=['kuld'], page=503))
        self.cards = pk.kort_1939(self.m, k=4)
        self.c = card(self.cards, 'GK:kuld:6000')

    def test_kort_og_vurdering(self):
        self.assertEqual(self.c['forventet'], {'beskrivelse': 'Lyder-Testsens-Søn'})
        sv = svar_for(self.cards)
        self.assertEqual(pk.vurderinger(self.cards, sv)['GK:kuld:6000'], 'ingen_anden')
        sp = pk._spoergsmaal(self.c, 'U', {'side': 503, 'start_tekst': 'Dr. Testo'})
        self.assertIn('»Lyder Testsens Søn«', sp['tekst'])
        self.assertEqual([k[0] for k in sp['knapper']], ['J', 'N'])

    def test_J_godkender_med_guidens_slug(self):
        sv = svar_for(self.cards)
        ta = TestApprovals()
        ta.m, ta.cards, ta.kontrol = self.m, self.cards, {}
        res = ta.run_(sv, {'SK:S2': '4', 'GK:kuld:6000': 'J'})
        self.assertIn(('kuld:6000', 'Lyder-Testsens-Søn', 'human'),
                      [(g['id'], g['value'], g['reviewer']) for g in res['gruppekort']])
        res_n = ta.run_(sv, {'SK:S2': '4', 'GK:kuld:6000': 'N'})
        self.assertNotIn('kuld:6000', [g['id'] for g in res_n['gruppekort']])
        with self.assertRaises(SheetError):
            ta.run_(sv, {'SK:S2': '4', 'GK:kuld:6000': 'III'})


class TestHtmlOgFlet(unittest.TestCase):
    def setUp(self):
        self.m = manifest()
        self.cards = pk.kort_1939(self.m, k=4)
        # S2 uden anden læsning, S3 læst uden nummer (unummereret post), K:A uenig
        self.sv = svar_for(self.cards, **{'SK:S3': {'nr': 'B)'}, 'K:A': {'slaegtled': 2}})
        self.vd = pk.vurderinger(self.cards, self.sv)

    def test_forslag_kun_for_strukturkort(self):
        tok = pk.render_token(self.cards, self.vd, self.sv)
        self.assertIn('U SK:S3 : N', tok)
        self.assertIn('# SK:S3: forudfyldt N — unummereret post — kan ikke placeres uden trykt nummer', tok)
        self.assertIn('U SK:S2 : N', tok)                     # nummer, men ingen anden læsning: forudfyldt N
        self.assertIn('U K:A : \n', tok)                       # stikprøven: projektejeren svarer
        self.assertEqual(pk.render_token(self.cards, self.vd).count(': N'), 0)   # uden svar: intet forslag

    def test_html_har_spoergsmaal_og_binder_tokenfilen(self):
        tok = pk.render_token(self.cards, self.vd, self.sv)
        ops = pk.opslag(self.m, self.cards, records(self.m), RENDITION)
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / 'sider').mkdir()
            (Path(d) / 'sider' / 'side-500.png').write_bytes(b'x')
            h = pk.render_html(self.cards, self.vd, self.sv, ops, Path(d), tok)
        data = json.loads(h.split('const DATA=', 1)[1].split('; const KEY', 1)[0])
        self.assertEqual(data['token_sha256'], pk._sha(tok.encode('utf-8')))
        k = next(x for x in data['kort'] if x['linje'] == 'U K:A')
        self.assertIn('Maskinen har placeret den: slægtled 1, ingen gruppe-romertal', k['sp']['tekst'])
        self.assertEqual(k['sp']['knapper'][0][0], '1 -')
        self.assertEqual(k['sider'], [500])
        s3 = next(x for x in data['kort'] if x['linje'] == 'U SK:S3')
        self.assertEqual((s3['forudfyldt'], s3['begrundelse'][:11]), ('N', 'unummereret'))
        self.assertEqual(sum(x['art'] == 'V' for x in data['kort']), len(pk.v_poster(self.cards, self.vd)))

    def test_flet(self):
        tok = pk.render_token(self.cards, self.vd, self.sv)
        keys = [l.split(' : ')[0] for l in tok.splitlines() if l[:2] in ('U ', 'V ')]
        svar = {k: ('1 -' if k == 'U K:A' else 'J' if k.startswith('V ') else 'N') for k in keys}
        ud = pk.flet(tok, {'token_sha256': pk._sha(tok.encode('utf-8')), 'svar': svar}, self.cards)
        self.assertIn('U K:A : 1 -', ud)
        self.assertEqual([l for l in ud.splitlines() if not l[:2] in ('U ', 'V ')],
                         [l for l in tok.splitlines() if not l[:2] in ('U ', 'V ')])   # kun tokens ændret
        res = pk.approvals_1939(self.m, self.cards, self.sv, ud, manifest_sha256='m', kontrol={})
        self.assertNotIn('S3', [a['record_key'] for a in res['approvals']])
        with self.assertRaisesRegex(SheetError, 'KORT_SVAR_ANDEN_TOKENFIL'):
            pk.flet(tok, {'token_sha256': 'x', 'svar': svar}, self.cards)
        with self.assertRaisesRegex(SheetError, 'SHEET_TOKEN_NOT_ALLOWED'):
            pk.flet(tok, {'token_sha256': pk._sha(tok.encode('utf-8')), 'svar': dict(svar, **{'U K:A': 'ja'})},
                    self.cards)
        with self.assertRaisesRegex(SheetError, 'SHEET_UNANSWERED'):
            pk.flet(tok, {'token_sha256': pk._sha(tok.encode('utf-8')), 'svar': {}}, self.cards)


class TestJob(unittest.TestCase):
    def test_jobmappe(self):
        m = manifest()
        with tempfile.TemporaryDirectory() as d:
            priv = Path(d) / 'priv'
            priv.mkdir()
            with self.assertRaisesRegex(SheetError, 'KORT_JOBDIR_PRIVAT'):
                pk._check_jobdir(priv / 'job', priv)
            job = Path(d) / 'job'
            res = pk.build_job(m, records(m), RENDITION, None, job, k=4)
            self.assertEqual(res['kort'], 13)
            self.assertEqual(res['brief_sha256'], pk._sha(pk.BRIEF.encode('utf-8')))
            ops = json.loads((job / 'opslag.json').read_text(encoding='utf-8'))
            self.assertEqual(len(ops), 13)
            self.assertNotIn('forventet', (job / 'opslag.json').read_text(encoding='utf-8'))


if __name__ == '__main__':
    unittest.main()
