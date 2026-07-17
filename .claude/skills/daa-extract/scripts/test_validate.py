import os, sys, json, tempfile, unittest
sys.path.insert(0, os.path.dirname(__file__))
import validate


class TestDeriveBoern(unittest.TestCase):
    def test_antal_og_range(self):
        raw = "Gottschalk, til Glasau. 3 børn: Tiende slægtled, II, nr. 31-35."
        self.assertEqual(validate.derive_boern(raw),
                         {"antal": 3, "slaegtled": "Tiende slægtled", "linje": "II", "nr_range": [31, 35]})

    def test_enkelt_barn_soen(self):
        raw = "N.N., til X. Søn: nr. 199."
        got = validate.derive_boern(raw)
        self.assertEqual(got["nr_range"], [199, 199])
        self.assertEqual(got["antal"], 1)

    def test_ingen_boerneklausul(self):
        self.assertIsNone(validate.derive_boern("Levede ugift, deres børn boede i udlandet."))

    def test_bar_boern_uden_antal(self):
        raw = "børn: nr. 12-14."
        got = validate.derive_boern(raw)
        self.assertEqual(got["nr_range"], [12, 14])
        self.assertEqual(got["antal"], 3)


class TestDeriveAegteskaber(unittest.TestCase):
    def test_enkelt_aegteskab(self):
        raw = "Frederik, til Brahetrolleborg. g. 26. juli 1975 m. Margrethe Holstein."
        got = validate.derive_aegteskaber(raw)
        self.assertEqual(len(got), 1)
        self.assertEqual(got[0]["ordinal"], 1)
        self.assertEqual(got[0]["partner_navn"], "Margrethe Holstein")
        self.assertFalse(got[0]["skilt"])

    def test_to_aegteskaber_ordinaler(self):
        raw = ("Christian, til Christianssæde. Gift 1° 1698 med Anna Sophie Reedtz, "
               "2° 1712 med Birgitte Restorff, skilt.")
        got = validate.derive_aegteskaber(raw)
        self.assertEqual([a["ordinal"] for a in got], [1, 2])
        self.assertEqual(got[0]["partner_navn"], "Anna Sophie Reedtz")
        self.assertTrue(got[1]["skilt"])

    def test_ingen_aegteskab(self):
        self.assertEqual(validate.derive_aegteskaber("Døde ugift 1701."), [])

    def test_dato_raw_findes_i_tekst(self):
        raw = "N.N. g. 1750 m. Sofie."
        got = validate.derive_aegteskaber(raw)
        self.assertIn(got[0]["dato_raw"].strip(), raw)


class TestExpectedSignals(unittest.TestCase):
    def test_venter_aegteskab_men_mangler(self):
        raw = "N.N. g. 1750 m. Sofie. † 1799."
        sig = validate.expected_signals(raw)
        self.assertTrue(sig["venter_aegteskab"])
        self.assertTrue(sig["venter_doed"])

    def test_ingen_signaler(self):
        raw = "N.N. levede ugift uden kendte børn."
        sig = validate.expected_signals(raw)
        self.assertFalse(sig["venter_aegteskab"])
        self.assertFalse(sig["venter_boern"])
        self.assertFalse(sig["venter_doed"])

    def test_venter_boern(self):
        raw = "N.N. 3 børn: Tiende slægtled, II, nr. 31-35."
        sig = validate.expected_signals(raw)
        self.assertTrue(sig["venter_boern"])
        self.assertFalse(sig["venter_aegteskab"])

    def test_doed_dagger_symbol(self):
        raw = "N.N. † 1801."
        sig = validate.expected_signals(raw)
        self.assertTrue(sig["venter_doed"])
        self.assertFalse(sig["venter_aegteskab"])
        self.assertFalse(sig["venter_boern"])

    # Pilot 2026-06-18: parenteser bærer tredjeparts-data (slægtninge, gift-ind,
    # kilde-refs). Et tredjeparts † eller (gift…) i parentes må IKKE flagge posten.
    def test_tredjeparts_doed_i_parentes_flagger_ikke(self):
        raw = "Lüder til X. Beseglede 1469. Gift med Mette (F.: Hans B., † før 1496)."
        sig = validate.expected_signals(raw)
        self.assertFalse(sig["venter_doed"])     # † er kun i parentes (svigerfar)

    def test_egen_doed_flagger_stadig(self):
        raw = "Lüder † 1500. Gift med Mette (F.: Hans B., † før 1496)."
        sig = validate.expected_signals(raw)
        self.assertTrue(sig["venter_doed"])      # postens egen † uden for parentes

    def test_tredjeparts_aegteskab_i_parentes_flagger_ikke(self):
        raw = "Lüder, søn af NN (gift 2° med Erik Schrandi)."
        sig = validate.expected_signals(raw)
        self.assertFalse(sig["venter_aegteskab"])  # ægteskab kun i parentes (tredjepart)

    def test_egen_aegteskab_uden_for_parentes_flagger(self):
        raw = "Lüder. Gift med Mette Breide (gift 2° med Erik Schrandi)."
        sig = validate.expected_signals(raw)
        self.assertTrue(sig["venter_aegteskab"])   # postens eget ægteskab uden for parentes

    def test_nestede_parenteser_strippes(self):
        raw = "Lüder til X (F.: Hans (af Kaden) † 1490)."
        sig = validate.expected_signals(raw)
        self.assertFalse(sig["venter_doed"])     # nested parentes-† tæller ikke

    # Punkt 8 (Bobé 1939): OCR fejllæser † som lille 't'. Tolereres KUN i
    # dødssignal-lignende kontekst (klausul-start + efterfølgende dato) —
    # 't' midt i ord eller som del af 'til' må ikke flagge.
    def test_ocr_t_for_dagger_ved_klausulstart(self):
        sig = validate.expected_signals("N.N. t 1712.")
        self.assertTrue(sig["venter_doed"])

    def test_ocr_t_med_punktum_og_dagdato(self):
        sig = validate.expected_signals("N.N., f. 1650, t. 30. marts 1712.")
        self.assertTrue(sig["venter_doed"])

    def test_ocr_t_efter_komma(self):
        sig = validate.expected_signals("N.N., f. 1650, t 1712.")
        self.assertTrue(sig["venter_doed"])

    def test_t_i_ord_flagger_ikke(self):
        # 'skiftet 1712' ender på t + årstal, men t'et er del af et ord
        sig = validate.expected_signals("N.N. skiftet 1712 gården.")
        self.assertFalse(sig["venter_doed"])

    def test_til_flagger_ikke(self):
        sig = validate.expected_signals("N.N. solgte gården til 1712-ejeren.")
        self.assertFalse(sig["venter_doed"])

    def test_stort_T_initial_flagger_ikke(self):
        # Stort 'T' (navne-initial) er ikke en OCR-†-variant
        sig = validate.expected_signals("N.N. T 1712.")
        self.assertFalse(sig["venter_doed"])

    def test_r8_advisory_i_validate(self):
        """validate() tilføjer R8-advisories (non-blocking) ved mismatch."""
        rec = {
            "linje": "I",
            "nr": 1,
            "nr_label": "1",
            "navn": "N.N.",
            "aegteskaber": [],
            "boern": None,
            "facts": [],
        }
        src = {"raw_text": "N.N. g. 1750 m. Sofie. † 1799.", "linje": "I", "nr": 1, "nr_label": "1"}
        issues, advisory = validate.validate(rec, src, {"I": {1}})
        self.assertEqual(issues, [], "R8 må ikke blokere (skal være advisory, ikke issue)")
        r8_lines = [a for a in advisory if a.startswith("R8:")]
        self.assertGreaterEqual(len(r8_lines), 2, f"Forventet mindst 2 R8-advisories, fik: {advisory}")
        aegt_flags = [a for a in r8_lines if "ægteskab" in a]
        doed_flags = [a for a in r8_lines if "død" in a]
        self.assertTrue(aegt_flags, "Mangler R8-advisory for ægteskab")
        self.assertTrue(doed_flags, "Mangler R8-advisory for død")


class TestProvenansGate(unittest.TestCase):
    def _run(self, rec, raw):
        src = {"raw_text": raw}
        issues, _ = validate.validate(rec, src, {})
        return issues

    def test_span_findes(self):
        rec = {"linje": "I", "nr": 1, "facts": [{"faktatype": "død", "kilde_span": "† 1300"}]}
        self.assertEqual([i for i in self._run(rec, "N.N. † 1300, til X.") if i.startswith("R7")], [])

    def test_span_hallucineret(self):
        rec = {"linje": "I", "nr": 1, "facts": [{"faktatype": "død", "kilde_span": "† 1399"}]}
        bad = [i for i in self._run(rec, "N.N. † 1300, til X.") if i.startswith("R7")]
        self.assertEqual(len(bad), 1)


class TestEscalationEntry(unittest.TestCase):
    def test_blokerende_eskaleres(self):
        rec = {"linje": "I", "nr": 5, "nr_label": "5"}
        e = validate.escalation_entry(rec, ["R1: årstal ..."], [])
        self.assertIsNotNone(e)
        self.assertEqual(e["nr_label"], "5")
        self.assertEqual(e["grunde"], ["R1: årstal ..."])

    def test_r8_miss_eskaleres(self):
        rec = {"linje": "I", "nr": 5, "nr_label": "5"}
        e = validate.escalation_entry(rec, [], ["R8: prosa nævner død, men intet død-fakta"])
        self.assertIsNotNone(e)
        self.assertEqual(e["grunde"], ["R8: prosa nævner død, men intet død-fakta"])

    def test_ren_post_eskaleres_ikke(self):
        self.assertIsNone(validate.escalation_entry({"linje": "I", "nr": 5}, [], []))

    def test_v9_vocab_eskalerer_ikke(self):
        e = validate.escalation_entry({"linje": "I", "nr": 5}, [], ["V9: ukendt faktatype"])
        self.assertIsNone(e)


class TestNormalizeRecord(unittest.TestCase):
    """C1: normalize_record() deler boern-logikken med validate.main()."""

    def test_udleder_boern_fra_prosa(self):
        rec = {"linje": "I", "nr": 1, "boern": None}
        src = {"raw_text": "N.N. 3 børn: Tiende slægtled, II, nr. 31-35."}
        validate.normalize_record(rec, src)
        self.assertIsNotNone(rec["boern"])
        self.assertEqual(rec["boern"]["nr_range"], [31, 35])
        self.assertEqual(rec["boern"]["antal"], 3)

    def test_nulstiller_hallucineret_boern(self):
        rec = {"linje": "I", "nr": 1, "boern": {"antal": 2, "nr_range": [10, 11]}}
        src = {"raw_text": "N.N. Levede ugift uden børn."}
        validate.normalize_record(rec, src)
        self.assertIsNone(rec["boern"])

    def test_ingen_src_bevaerer_boern(self):
        boern = {"antal": 1, "nr_range": [5, 5]}
        rec = {"linje": "I", "nr": 1, "boern": boern}
        validate.normalize_record(rec, None)
        self.assertEqual(rec["boern"], boern)


class TestValidateMainReviewNrLabel(unittest.TestCase):
    """C3: validate.main() skriver nr_label ind i review-recorden."""

    def test_review_record_har_nr_label(self):
        # Opsæt temp-mappe med én udtrukket post der fejler R1 (hallucination)
        with tempfile.TemporaryDirectory() as tmpdir:
            posts = [{"linje": "I", "nr": 15, "nr_label": "15a",
                      "raw_text": "Peter til X. † 1700."}]
            posts_path = os.path.join(tmpdir, "posts.json")
            json.dump(posts, open(posts_path, 'w', encoding='utf-8'), ensure_ascii=False)

            # Extracted post med hallucineret årstal → R1-brud
            rec = {"linje": "I", "nr": 15, "nr_label": "15a", "navn": "Peter",
                   "facts": [{"faktatype": "død", "date_raw": "† 1999"}],
                   "aegteskaber": [], "boern": None}
            ext_dir = os.path.join(tmpdir, "extracted")
            os.makedirs(ext_dir)
            json.dump(rec, open(os.path.join(ext_dir, "015a.json"), 'w', encoding='utf-8'),
                      ensure_ascii=False)

            clean_path = os.path.join(tmpdir, "clean.json")
            review_path = os.path.join(tmpdir, "review.json")

            sys.argv = ["validate.py", posts_path, ext_dir,
                        "--clean", clean_path, "--review", review_path]
            validate.main()

            review = json.load(open(review_path, encoding='utf-8'))
            self.assertEqual(len(review), 1)
            self.assertEqual(review[0].get("nr_label"), "15a",
                             "review-record mangler nr_label — C3-fix ikke anvendt")


class TestDateBounds(unittest.TestCase):
    def test_aar_kun(self):
        self.assertEqual(validate.derive_date_bounds("1698"), ("1698-01-01", "1698-12-31"))

    def test_fuld_dato(self):
        self.assertEqual(validate.derive_date_bounds("26. juli 1975"), ("1975-07-26", "1975-07-26"))

    def test_ca(self):
        lo, hi = validate.derive_date_bounds("ca. 1500")
        self.assertTrue(lo.startswith("1500") and hi.startswith("1500"))

    def test_uparsebar(self):
        self.assertEqual(validate.derive_date_bounds("ukendt"), (None, None))

    def test_to_aars_span_bevares(self):
        self.assertEqual(validate.derive_date_bounds("1257-1272"), ("1257-01-01", "1272-12-31"))

    def test_flere_end_to_aar_uparsebart(self):
        self.assertEqual(validate.derive_date_bounds("1500 1600 1700"), (None, None))


class TestDateInfoAabneGraenser(unittest.TestCase):
    """Punkt 1: før/inden/senest → åben mod fortiden; efter → åben mod fremtiden.

    Konvention (dokumenteret i derive_date_info): grænsen er det KONSERVATIVE
    ydre hylster inkl. det nævnte år — 'før 1261' → date_max=1261-12-31;
    'efter 1575' → date_min=1575-01-01. Qualifieren bærer den strikte semantik.
    """

    def test_foer_aaben_mod_fortiden(self):
        info = validate.derive_date_info("† før 1261")
        self.assertIsNone(info["date_min"])
        self.assertEqual(info["date_max"], "1261-12-31")
        self.assertEqual(info["qualifier"], "before")

    def test_efter_aaben_mod_fremtiden(self):
        info = validate.derive_date_info("† efter 1575")
        self.assertEqual(info["date_min"], "1575-01-01")
        self.assertIsNone(info["date_max"])
        self.assertEqual(info["qualifier"], "after")

    def test_inden_er_before(self):
        info = validate.derive_date_info("inden 1500")
        self.assertIsNone(info["date_min"])
        self.assertEqual(info["date_max"], "1500-12-31")
        self.assertEqual(info["qualifier"], "before")

    def test_foer_fuld_dato_bruger_dagen(self):
        info = validate.derive_date_info("før 26. juli 1261")
        self.assertIsNone(info["date_min"])
        self.assertEqual(info["date_max"], "1261-07-26")
        self.assertEqual(info["qualifier"], "before")

    def test_mellem(self):
        info = validate.derive_date_info("mellem 1500 og 1510")
        self.assertEqual(info["date_min"], "1500-01-01")
        self.assertEqual(info["date_max"], "1510-12-31")
        self.assertEqual(info["qualifier"], "between")

    def test_bounds_wrapper_bagudkompatibel(self):
        self.assertEqual(validate.derive_date_bounds("† før 1261"), (None, "1261-12-31"))
        self.assertEqual(validate.derive_date_bounds("† efter 1575"), ("1575-01-01", None))


class TestDateInfoAbout(unittest.TestCase):
    """Punkt 3: ca. (dansk), o. (ældre dansk), um (tysk) → qualifier='about',
    ét år → hele års-spannet."""

    def test_ca(self):
        info = validate.derive_date_info("ca. 1484")
        self.assertEqual((info["date_min"], info["date_max"]), ("1484-01-01", "1484-12-31"))
        self.assertEqual(info["qualifier"], "about")

    def test_o_aeldre_dansk(self):
        info = validate.derive_date_info("o. 1250")
        self.assertEqual((info["date_min"], info["date_max"]), ("1250-01-01", "1250-12-31"))
        self.assertEqual(info["qualifier"], "about")

    def test_um_tysk(self):
        info = validate.derive_date_info("um 1483")
        self.assertEqual((info["date_min"], info["date_max"]), ("1483-01-01", "1483-12-31"))
        self.assertEqual(info["qualifier"], "about")

    def test_ca_interval_bevarer_about(self):
        # 'ca. 1484-1569' = omtrentligt interval — about må ikke tabes på spans
        info = validate.derive_date_info("ca. 1484-1569")
        self.assertEqual((info["date_min"], info["date_max"]), ("1484-01-01", "1569-12-31"))
        self.assertEqual(info["qualifier"], "about")

    def test_normalize_record_saetter_qualifier(self):
        rec = {"linje": "I", "nr": 1,
               "facts": [{"faktatype": "fødsel", "date_raw": "um 1483"}]}
        src = {"raw_text": "N.N. født um 1483."}
        validate.normalize_record(rec, src)
        self.assertEqual(rec["facts"][0].get("date_qualifier"), "about")

    def test_normalize_record_saetter_before_qualifier(self):
        rec = {"linje": "I", "nr": 1,
               "facts": [{"faktatype": "død", "date_raw": "† før 1261"}]}
        src = {"raw_text": "N.N. † før 1261."}
        validate.normalize_record(rec, src)
        f = rec["facts"][0]
        self.assertIsNone(f["date_min"])
        self.assertEqual(f["date_max"], "1261-12-31")
        self.assertEqual(f.get("date_qualifier"), "before")

    def test_normalize_record_bevarer_qualifier_naar_derive_intet_finder(self):
        rec = {"linje": "I", "nr": 1,
               "facts": [{"faktatype": "død", "date_raw": "1750",
                          "date_qualifier": "until_event"}]}
        src = {"raw_text": "N.N. død 1750."}
        validate.normalize_record(rec, src)
        self.assertEqual(rec["facts"][0]["date_qualifier"], "until_event")


class TestDateInfoMaanedsnavne(unittest.TestCase):
    """Punkt 4: månedsnavne på tværs af sprog/epoke (dansk, ældre dansk, tysk)."""

    def test_dansk_marts(self):
        self.assertEqual(validate.derive_date_bounds("3. marts 1500"),
                         ("1500-03-03", "1500-03-03"))

    def test_tysk_mai(self):
        self.assertEqual(validate.derive_date_bounds("26. Mai 1975"),
                         ("1975-05-26", "1975-05-26"))

    def test_tysk_maerz_umlaut(self):
        self.assertEqual(validate.derive_date_bounds("3. März 1500"),
                         ("1500-03-03", "1500-03-03"))

    def test_tysk_dezember(self):
        self.assertEqual(validate.derive_date_bounds("24. Dezember 1600"),
                         ("1600-12-24", "1600-12-24"))

    def test_tysk_jaenner(self):
        self.assertEqual(validate.derive_date_bounds("12. Jänner 1700"),
                         ("1700-01-12", "1700-01-12"))

    def test_aeldre_dansk_octbr(self):
        self.assertEqual(validate.derive_date_bounds("5. Octbr. 1750"),
                         ("1750-10-05", "1750-10-05"))

    def test_forkortet_sept(self):
        self.assertEqual(validate.derive_date_bounds("9. sept. 1800"),
                         ("1800-09-09", "1800-09-09"))


class TestDateInfoRomertal(unittest.TestCase):
    """Punkt 5: romertals-årstal, både additiv (CCCC, IIII — middelalderform)
    og subtraktiv (XC, IV) notation."""

    def test_additiv_middelalderform(self):
        self.assertEqual(validate.derive_date_bounds("anno dni MCCCCXCIIII"),
                         ("1494-01-01", "1494-12-31"))

    def test_subtraktiv_notation(self):
        self.assertEqual(validate.derive_date_bounds("MCMXCIV"),
                         ("1994-01-01", "1994-12-31"))

    def test_blandet_form(self):
        self.assertEqual(validate.derive_date_bounds("anno MDCCLXXVI"),
                         ("1776-01-01", "1776-12-31"))

    def test_kort_romertal_ignoreres(self):
        # Gren-tællere (III, VI) og småtal må ikke fejltolkes som år
        self.assertEqual(validate.derive_date_bounds("III"), (None, None))

    def test_ikke_roman_ord_ignoreres(self):
        # 'mild' består kun af romertals-bogstaver men er ugyldig romersk form
        self.assertEqual(validate.derive_date_bounds("mild"), (None, None))

    def test_arabertal_vinder_over_romertal(self):
        # findes et arabisk årstal, bruges det (romertal kun som fallback)
        self.assertEqual(validate.derive_date_bounds("MCCCCXCIIII (1494)"),
                         ("1494-01-01", "1494-12-31"))


class TestDateInfoUsikreCifre(unittest.TestCase):
    """Punkt 6: usikre cifre ('147(5?)', '14?8', '1475?') → bedste læsning som
    bounds + certainty='uncertain'."""

    def test_parentes_ciffer_med_spoergsmaalstegn(self):
        info = validate.derive_date_info("† 147(5?)")
        self.assertEqual((info["date_min"], info["date_max"]),
                         ("1475-01-01", "1475-12-31"))
        self.assertEqual(info["certainty"], "uncertain")

    def test_wildcard_ciffer(self):
        # '14?8': tredje ciffer ulæseligt → ydre hylster over alle læsninger
        info = validate.derive_date_info("14?8")
        self.assertEqual((info["date_min"], info["date_max"]),
                         ("1408-01-01", "1498-12-31"))
        self.assertEqual(info["certainty"], "uncertain")

    def test_helaars_spoergsmaalstegn(self):
        info = validate.derive_date_info("1475?")
        self.assertEqual((info["date_min"], info["date_max"]),
                         ("1475-01-01", "1475-12-31"))
        self.assertEqual(info["certainty"], "uncertain")

    def test_sikker_dato_har_ingen_certainty(self):
        self.assertIsNone(validate.derive_date_info("1475")["certainty"])

    def test_normalize_record_skriver_certainty(self):
        rec = {"linje": "I", "nr": 1,
               "facts": [{"faktatype": "død", "date_raw": "147(5?)"}]}
        src = {"raw_text": "N.N. † 147(5?)."}
        validate.normalize_record(rec, src)
        self.assertEqual(rec["facts"][0].get("date_certainty"), "uncertain")

    def test_normalize_record_bevarer_llm_certainty(self):
        # LLM-sat 'ambiguous' (flere lige gyldige tolkninger) må ikke nedgraderes
        rec = {"linje": "I", "nr": 1,
               "facts": [{"faktatype": "død", "date_raw": "147(5?)",
                          "date_certainty": "ambiguous"}]}
        src = {"raw_text": "N.N. † 147(5?)."}
        validate.normalize_record(rec, src)
        self.assertEqual(rec["facts"][0]["date_certainty"], "ambiguous")


class TestDateInfoFloruit(unittest.TestCase):
    """Punkt 7: bindestreg-flankeret nævnt-form '(-1223-1247-)' er floruit
    (dokumenteret-aktiv, invariant #5), IKKE levetid. Et LLM-sat
    qualifier='floruit' må derive aldrig overskrive."""

    def test_flankeret_form_er_floruit(self):
        info = validate.derive_date_info("(-1223-1247-)")
        self.assertEqual((info["date_min"], info["date_max"]),
                         ("1223-01-01", "1247-12-31"))
        self.assertEqual(info["qualifier"], "floruit")

    def test_flankeret_uden_parens(self):
        info = validate.derive_date_info("-1223-1247-")
        self.assertEqual(info["qualifier"], "floruit")

    def test_almindeligt_span_er_ikke_floruit(self):
        # '1712-1783' (levetid) må IKKE fejlmærkes som floruit
        info = validate.derive_date_info("1712-1783")
        self.assertEqual((info["date_min"], info["date_max"]),
                         ("1712-01-01", "1783-12-31"))
        self.assertIsNone(info["qualifier"])

    def test_normalize_record_bevarer_llm_floruit(self):
        # LLM satte floruit på et span uden flanker — derive må ikke ødelægge det
        rec = {"linje": "I", "nr": 1,
               "facts": [{"faktatype": "floruit", "date_raw": "1257-1272",
                          "date_qualifier": "floruit"}]}
        src = {"raw_text": "N.N. nævnt 1257-1272."}
        validate.normalize_record(rec, src)
        self.assertEqual(rec["facts"][0]["date_qualifier"], "floruit")
        self.assertEqual(rec["facts"][0]["date_min"], "1257-01-01")

    def test_normalize_record_floruit_vinder_over_derived_qualifier(self):
        # selv når derive udleder en anden qualifier, står LLM-floruit
        rec = {"linje": "I", "nr": 1,
               "facts": [{"faktatype": "floruit", "date_raw": "ca. 1250",
                          "date_qualifier": "floruit"}]}
        src = {"raw_text": "N.N. nævnt ca. 1250."}
        validate.normalize_record(rec, src)
        self.assertEqual(rec["facts"][0]["date_qualifier"], "floruit")

    def test_normalize_record_saetter_floruit_fra_flankeret_form(self):
        rec = {"linje": "I", "nr": 1,
               "facts": [{"faktatype": "floruit", "date_raw": "(-1223-1247-)"}]}
        src = {"raw_text": "N.N. (-1223-1247-)."}
        validate.normalize_record(rec, src)
        self.assertEqual(rec["facts"][0].get("date_qualifier"), "floruit")


class TestNormalizeRecordDateOverride(unittest.TestCase):
    """normalize_record: LLM'ens bounds er PRIMÆRE (den har kontekst — prosa uden
    for date_raw, s.å.-anker, fødsel/død-adskillelse — som den isolerede parser
    mangler). Derive UDFYLDER kun tomme bounds og FORFINER kun et rent enkelt-års-
    placeholder til dag; den forringer aldrig et span/præcis range LLM satte.
    Empirisk grundlag: korpus-diff 2026-07-17 (nul forringelser på 998 date-fakta)."""

    def test_respekterer_llm_bounds(self):
        # LLM satte præcise bounds → parseren rører dem ikke (ingen 'overskriv altid')
        rec = {"linje": "I", "nr": 1,
               "facts": [{"faktatype": "død", "date_raw": "1750",
                          "date_min": "1750-03-04", "date_max": "1750-03-04"}]}
        validate.normalize_record(rec, {"raw_text": "N.N. død 4. marts 1750."})
        self.assertEqual((rec["facts"][0]["date_min"], rec["facts"][0]["date_max"]),
                         ("1750-03-04", "1750-03-04"))

    def test_forfiner_aar_placeholder_til_dag(self):
        # LLM kendte kun året (hele-års-span), date_raw har dagen → forfin (korpus III-124)
        rec = {"linje": "I", "nr": 1,
               "facts": [{"faktatype": "fødsel", "date_raw": "* 12. nov. 1709",
                          "date_min": "1709-01-01", "date_max": "1709-12-31"}]}
        validate.normalize_record(rec, {"raw_text": "N.N. * 12. nov. 1709."})
        self.assertEqual((rec["facts"][0]["date_min"], rec["facts"][0]["date_max"]),
                         ("1709-11-12", "1709-11-12"))

    def test_multi_aar_span_bevares(self):
        # '1924/39' = enten 1924 eller 1939; må ikke indsnævres til ét år (korpus IV-47)
        rec = {"linje": "I", "nr": 1,
               "facts": [{"faktatype": "død", "date_raw": "† 1924/39",
                          "date_min": "1924-01-01", "date_max": "1939-12-31"}]}
        validate.normalize_record(rec, {"raw_text": "N.N. † 1924/39."})
        self.assertEqual((rec["facts"][0]["date_min"], rec["facts"][0]["date_max"]),
                         ("1924-01-01", "1939-12-31"))

    def test_floruit_span_fra_kontekst_bevares(self):
        # date_raw viser kun startåret; LLM satte hele floruit-spannet fra kontekst
        # → parseren må ikke indsnævre til startpunktet (korpus I-1)
        rec = {"linje": "I", "nr": 1,
               "facts": [{"faktatype": "floruit", "date_raw": "1223 (31. maj)",
                          "date_qualifier": "floruit",
                          "date_min": "1223-05-31", "date_max": "1247-02-22"}]}
        validate.normalize_record(rec, {"raw_text": "N.N. nævnt 1223 (31. maj) ... 1247."})
        self.assertEqual((rec["facts"][0]["date_min"], rec["facts"][0]["date_max"]),
                         ("1223-05-31", "1247-02-22"))

    def test_uparsebar_dato_forringer_ikke_eksisterende_bounds(self):
        """Punkt 2: derive må FORBEDRE, aldrig forringe. Uparsebar date_raw
        (fx kirkelig mærkedag) må ikke nulstille allerede-udfyldte bounds."""
        rec = {"linje": "I", "nr": 1,
               "facts": [{"faktatype": "død", "date_raw": "Michaelisdag s.å.",
                          "date_min": "1500-09-29", "date_max": "1500-09-29"}]}
        src = {"raw_text": "N.N. død Michaelisdag s.å."}
        validate.normalize_record(rec, src)
        self.assertEqual(rec["facts"][0]["date_min"], "1500-09-29")
        self.assertEqual(rec["facts"][0]["date_max"], "1500-09-29")

    def test_uparsebar_dato_uden_eksisterende_giver_none(self):
        rec = {"linje": "I", "nr": 1,
               "facts": [{"faktatype": "død", "date_raw": "ukendt"}]}
        src = {"raw_text": "N.N. død ukendt."}
        validate.normalize_record(rec, src)
        self.assertIsNone(rec["facts"][0].get("date_min"))
        self.assertIsNone(rec["facts"][0].get("date_max"))

    def test_span_bevares_ved_normalize(self):
        rec = {"linje": "I", "nr": 1,
               "facts": [{"faktatype": "floruit", "date_raw": "1257-1272"}]}
        src = {"raw_text": "N.N. floruit 1257-1272."}
        validate.normalize_record(rec, src)
        self.assertEqual(rec["facts"][0]["date_min"], "1257-01-01")
        self.assertEqual(rec["facts"][0]["date_max"], "1272-12-31")


class TestKontekstMerge(unittest.TestCase):
    def test_merge_kuld_og_kontekst(self):
        rec = {"linje": "I", "nr": 66, "nr_label": "66", "navn": "X"}
        src = {"linje": "I", "nr": 66, "nr_label": "66",
               "raw_text": "X, til Y. 1700.", "kuld": "I",
               "aegteskab_kontekst": "af første ægteskab med Anna von Ahlefeldt"}
        out = validate.merge_kontekst(dict(rec), src)
        self.assertEqual(out["kuld"], "I")
        self.assertEqual(out["aegteskab_kontekst"], "af første ægteskab med Anna von Ahlefeldt")

    def test_merge_haandterer_manglende_src(self):
        out = validate.merge_kontekst({"linje":"I","nr":1,"nr_label":"1","navn":"X"}, None)
        self.assertIsNone(out["kuld"])


if __name__ == "__main__":
    unittest.main()
