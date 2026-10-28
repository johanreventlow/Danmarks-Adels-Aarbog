# Udestående — rå indsamling til helhedsreview (2026-10-27)

> **Note fra hovedsessionen:** Eksporten er taget før docs-PR #271 (5c-1 i prod 2026-10-27: `database-current-state.md` §13, changelog, `status.md` → `produktionsverificeret`). Kortets »forældet«-bemærkninger om 5c-1 skyldes det tidspunkt og er ikke et fund.

Ingen vurdering, ingen prioritering. Format: **punkt** · kilde `fil:linje` · type · dato.
Stier er relative til eksportmappen. Forkortelser: DEC = `docs/decisions.md`, ST = `docs/evidensbaseret-genimport/status.md`,
RM = `docs/evidensbaseret-genimport/roadmap.md`, BEV = `docs/evidensbaseret-genimport/`, SPEC = `docs/superpowers/specs/`,
DBS = `docs/database-current-state.md`, RB = `docs/runbooks/`, LEDGER = `_ledger-rulings.txt`, ISS = `_issues.txt`, HUK = hukommelse.
Typer: ikke udviklet / udskudt / parkeret / ubevist / syntetisk bevist / kendt begrænsning / åbent issue.
Linjenumre er, hvor det kunne findes; ST-tabellen har lange rækker (linje = rækkens start).
Bemærk: ST-rækkerne for "Klausulgranularitet" (`specificeret`) og "Placement og membership" (`isoleret implementeret`) er ikke opdateret efter trin 4/5c-1 (se punkt under Tværgående).

## A. Forarbejde (trin 1-3: #152, #153, #149, C3, 1939 v50, datamodel)

1. **Hel-person-sletning er blokeret for personer med publication-events (#152)**; granulær withdrawal løser kun offentlig nedtagning · ST:241 · kendt begrænsning/åben tombstone-retentionsbeslutning · 2026-09
2. **Person, der én gang har været mål for en accepteret identitetsbeslutning, kan aldrig hard-slettes** (`source_persona_identity(_event)`-FK uden ON DELETE; append-only) · DEC:1901 · åbent (redaktionel afgørelse ikke truffet) · 2026-08-20
3. **De fire `unresolved_text`-records (I-133, II-35, III-129, IV-94) er ikke tekstrettet**; tre står `grandfathered_publication`, én ubundet · ST:248; BEV/legacy-migration-149b-rehearsal.md:181 · udskudt (tekstrettelse for 2018-20 ikke besluttet) · 2026-09-04
4. **13 mulige `NOISE_RE`-prosalinjer (støjfilter fjerner op til 13 prosalinjer) er ikke rettet** · ST:248; BEV/legacy-migration-149b-rehearsal.md:187 · kendt begrænsning · 2026-09-04
5. **Batch-reversalens `--apply` (149b) er kun bevist syntetisk**, ikke mod rehearsal-basen (kun dry-run på 587 elementer) · BEV/legacy-migration-149b-rehearsal.md:192 · syntetisk bevist · 2026-09-04
6. **149b: deferred minors M-1..M-7 (Task 5) og flerdelte fund for Task 6/7 er ikke rettet** · BEV/legacy-migration-149b-rehearsal.md:195 · udskudt · 2026-09-04
7. **#156: historiske fase-kørsler kan kun efterdokumenteres, ikke mekanisk bindes retroaktivt** (reconciler: `EVIDENCE_RECONCILIATION_INCOMPLETE`, 8 INCOMPLETE) · BEV/evidence-phase-reconciliation-156-2026-09-03.md:48 · kendt begrænsning (lukket med restpunkt) · 2026-09-03
8. **C3 reversal er `integreret ende-til-ende`, men aldrig udført i produktion** · ST:177 · ubevist i prod
9. **C3-opfølgning #158: 16 `[NY]`-records, 7 staged records, 16 tomme unioner, narrative grænsekandidater, bindingen af C0f-receipt til flags_sha256, fortryd af bindinger** · ISS:#158,#159,#160,#161,#162,#163 · åbent issue (#160-#163 markeret `parkeret`, DEC:1357)
10. **`[NY]`, C1, C2 og nye 1939-specialfaser er parkeret** · ST:289; RM:78-81 · parkeret
11. **C1 (promovering af 1.078 literal fakta + 212 ægteskaber til fortolkningslaget) bygges ikke; `interpretation`/`interpretation_promotion` var tomme på målingstidspunktet** · DEC:2066 · udskudt · 2026-08-19 (delvist overhalet af trin 4/5: tomme-status ikke genmålt her)
12. **Spor H (heraldik) og M (mobil redaktør) er parkeret**, får ingen issues før kernen står · RM:80; DEC:1686 · parkeret · 2026-08-22
13. **Merge-sagerne 1017/1021, 929/930, 1013/1014, 1791 er parkeret/uden for C3's scope** (1017 senere flyttet til C3 i C0-efterkørsel, de øvrige ikke) · DEC:1666 · parkeret · 2026-08
14. **12 narrativer begynder midt i en sætning (929, 930, 956, 977, 1013, 1014, 1021, 1308, 1413, 1771, 1772, 1791); "ikke fikset, kun talt"** · DEC:1763 · åbent · 2026-08-20 (status siden ikke genverificeret her)
15. **De 7 staged personer (933, 935, 940, 963, 967, 1014, 1135) har 0 published bindinger**; 963/967 er `[KOBL]`-mål der selv er staged (synligheds-/RLS-spørgsmål uafklaret); 1014 afventer C0 · DBS:125-140; ISS:#161 · åbent · 2026-08
16. **16 tomme unioner i prod (familie 396/715-731), loader-guard (`navn ≠ ref`) udestår, så oprydning kan gøres om ved reload** · DEC:1815; ISS:#163 · åbent issue · 2026-08-20
17. **Slutarkets store occurrence (side 597-598) resegmenteres ikke** · DEC:2146 · udskudt backlog · 2026-08
18. **1939-publicering er pauset** indtil nyt OCR-udtræk, nyt artefakt og fornyet komplethedsgate · DBS:(§3, række "1939-publicering" ~linje 300) · udskudt
19. **Grundårsagen til dobbeltfamilier (indlæseren `load_daa.R`) er ikke rettet**; en genindlæsning med den gamle indlæser ville genskabe dem · DEC:122 · kendt begrænsning · 2026-10-26
20. **Hændelsesudtrækket (`/daa-haendelser`) ikke kørt — 0 hændelsesrækker; #130 åbent**; 1939-narrativer 166.518 tegn prosa ikke udtrukket til struktur · DEC:1693; ISS:#130; DBS:297 · ikke udviklet/ikke kørt · 2026-08-20
21. **Strukturerede fakta (fødsel, dåb, død m.fl.) vises ikke i læserfladen; ikke besluttet om en fakta-sektion skal bygges** (datalag/visning mangler til appen) · DEC:1786 · ikke udviklet · 2026-08-20
22. **Levende feed fase 4 (LLM-assist/Edge Function) udskudt** · DEC:3319; DBS:297 · udskudt · 2026-07-20
23. **`person_offentlig`/RLS 120-års-regel site-bredt ikke besluttet** · DEC:2437 · åben backlog · 2026-07
24. **RLS `authenticated`-tier (medlem/forsker ser levende m. samtykke) kun skitseret; `samtykke_offentlig` ikke designet** (forretningsmodel/invariant 8) · DBS:290-295 · ikke udviklet
25. **`max(id)+1` -> IDENTITY/sekvenser udskudt** (kritisk før flerbruger-skrivning; `family.id` er IDENTITY i prod men `schema.sql` har BIGINT uden default) · DBS:293; SPEC/2026-10-17-trin5b-2b-ii-nye-personer-og-disposition-design.md:67 · udskudt
26. **Vocab-håndhævelse: `rolle`/`faktatype`/`konfidens` er fritekst uden FK til `vocab`** (invariant 9 kun konventionel) · DBS:~294 · kendt begrænsning
27. **Polymorf døde-link-integritetsrapport findes kun for `text_mention`** · DBS:~295 · ikke udviklet
28. **Import-sikkerhed: stabil import-run/checksum/udgavenøgle og source-scoped replace mangler; `--reset` er farlig nødvej** · DBS:~301 · kendt begrænsning
29. **Skalering: klienter materialiserer hele grafen; server-slices/keyset-pagination mangler** (datalag mangler til appen) · DBS:~302 · ikke udviklet
30. **627 gift-ind-ægtefæller har intet `person_external_id` og er ikke redigerbare i kvalitetsarket; egen plan udestår** · DBS:232-236 · ikke udviklet
31. **Medie-oprydning: `--slet` og `--backfill-sha` ikke kørt; mediehåndtering fase 5 (dokumenttransskription) ikke designet** · DBS:188-190, ~300 · udskudt
32. **Leaked password protection kan ikke slås til på Free tier** · DEC:896 · parkeret (tier) · 2026-09-20
33. **Supabase free tier: ingen backup, pause efter 7 dage** · CLAUDE.md (Faldgruber); DEC:896 · kendt begrænsning
34. **TNG-spor: DNA afvist; medie-rigdom udskudt samlet; navnekomponentering (von/af) udskudt; gemte rapporter/smart-lister "næste fokus"; flersproget stamtræ ikke designet** · DEC:3258-3285 · udskudt · 2026-07
35. **Geo: 6.788 TNG-koordinater klar, geo-enrich-pipelinen ikke kørt (#131); fuldtekstsøgning i narrativer + `fts` schema-drift (#132); suggestion-apply (#128)** · ISS:#131,#132,#128 · åbent issue
36. **samme_som: automatisk detektion i skala (crosswalk for støjende), kryds-slægt-broer kræver server-side privacy-klasse** · DEC:3236 · udestår · 2026-07
37. **DB-hærdning: Supabase-advisors og RPC-ACL-drift (#164/#158) ikke disponeret; Codex' `~/.codex/auth.json` stadig læsbar for modellen (sandbox-restpunkt)** · ISS:#164; DEC:1198 · åbent issue / kendt begrænsning

## B. Trin 4 (fortolkningskæde og klausulgranularitet, #147/#148) — afsluttet for 2018-20

38. **Næste promptversion (»var †[dato], da …«-regel og titel/gods-regel) er ikke lavet; erstatter de 13 `U`-kort; kræver egen GO** · DEC:497; ST:271; BEV/kontrolmodel-koersel-2018-20.md:73; BEV/genbind-44-pilot-2018-20.md:103 · udskudt · 2026-10-03
39. **De 13 `U`-kort (navne med titel/godsbetegnelse) står som `unresolved` — endestation for RPC'en, genåbnes ikke** · DEC:507-540; BEV/2018-20-fuld-koersel.md:108 · kendt begrænsning
40. **Oprydning af 138 navne-assertions med titelord i databasen** · DEC:542; ST:271; BEV/2018-20-fuld-koersel.md:114 · ikke udviklet (egen opgave) · 2026-10-03
41. **III-15's gods (ejerskab) findes ikke som `person.estate`-forslag eller faktum** · BEV/2018-20-fuld-koersel.md:116 · kendt begrænsning (narrativet bærer det)
42. **Runnerens håndtering af Codex' nye kvotefejl (`turn.failed` uden `error.type`) er ikke rettet**; STOP for `quota_exhausted` udløses ikke · BEV/2018-20-fuld-koersel.md:122; DEC:497; ST:271 · ikke udviklet · 2026-10-03
43. **HTML-fladens eksport bevarer ikke originalarkets overskrift; delfiler kan ikke sættes sammen byte for byte** · BEV/2018-20-fuld-koersel.md:125 · kendt begrænsning
44. **Oprettelse af nye kanoniske mål (fakta, assertions, personer) fra fortolkninger er ikke designet — RPC'en binder kun** (åbent punkt 11.3); 4 accepterede uoverensstemmelser (I-24, I-43, V-18, IV-19) står accepteret og ubundet · SPEC/2026-09-06-trin4-…-design.md:669-685; BEV/genbind-44-pilot-2018-20.md:61 · ikke udviklet
45. **Promotion-regler for embede, hofstilling, militær rang, erhverv, uddannelse, dekoration afventer faktatype-afklaring** (åbent punkt 11.2) · SPEC/2026-09-06-trin4-…-design.md:672 · ikke udviklet
46. **Prod-fortrydelse for `interpretation_proposal` og menneskelige afgørelser er ikke designet — kun restore** (åbent punkt 11.5; afgjort som restore i DEC) · SPEC/2026-09-06-trin4-…-design.md:679; DEC:834 · kendt begrænsning
47. **1939's klausulregler (OCR, orddelinger) og 1939-kæden er trin 6** (åbent punkt 11.4) · SPEC/2026-09-06-trin4-…-design.md:681; ST:25 · ikke udviklet
48. **Persona-oprettelse for andre aktører end hovedpersonen (§13) er trin 5** · SPEC/2026-09-06-trin4-…-design.md:686 · henvist
49. **Bindingen i fortolkningslaget er usynlig for læseren** (review 35 §2.3, U1); normaliseringsregel for skrivemåde (16 af 27 `NO_MATCH`) kræver egen beslutning · DEC:763 · ikke udviklet · 2026-09-27
50. **Kontrolmodellen fanger kun fejl, model og database ikke deler (kun stikprøven)**; efter `SAMPLE_FAILED` håndhæver værktøjet ikke projektejerens afklaring; godkendt plan kan ikke genbruges i anden base (stikprøve på nyt forslags-id) · BEV/kontrolmodel-koersel-2018-20.md:73-111; BEV/genbind-44-pilot-2018-20.md:117 · kendt begrænsning
51. **Præcision på de 180 ikke-promoverbare forslag og de 16 `SKRIVEMAADE` er hverken set af et menneske eller bundet** · BEV/genbind-44-pilot-2018-20.md:117 · ubevist
52. **De 17 uciterede klausuler (`afventer_fortolkning`) er ikke systematisk gennemlæst; dækning hviler på én læsning** · BEV/interpretation-pilot-2018-20.md:183 · kendt begrænsning
53. **Fuld kørsel af 4.5-afgørelsesmodellen NO-GO (menneskelig kapacitet); afløst af kontrolmodel** · BEV/interpretation-pilot-2018-20.md:160; ST:63 · løst via DEC 2026-09-27 (medtaget som historik)
54. **Sandbox-grænsens huller (review 35 P1); `pilot_verdict.py` planlagt, ikke implementeret** · ST:160; BEV/interpretation-pilot-2018-20.md:283 · kendt begrænsning
55. **4.4: `44-apply.R` ikke prod-klar (ingen `--jeg-mener-det`-guard, forældreløs authorization pr. kørsel); `writer_config`s otte arvede nøgler; issue #189 (4.1b-segmentering klipper `VI.` og splitter midt i sætning)** · BEV/proposal-ingest-147-4-4-rehearsal.md:245-262 · kendt begrænsning/åbent issue (#189 ikke i ISS-listen)
56. **Fase-pakke-gaten mangler klausul-/fortolkningsprojektion (åbent punkt 11.1; #196 afløst af tre nøglede digests, DDL aldrig deployet)** · SPEC/2026-09-06-trin4-…-design.md:671; DEC:486 · kendt begrænsning
57. **Runner-evidens: præcision 99-99,6 % målt på 34 poster; ikke kørt mod 1939** · ST:160 · ubevist for 1939
58. **Trin 4 er kun `produktionsverificeret` for 2018-20, hovedpersonens persona; promotion kun bindingsdelen** · ST:159-161 · afgrænsning

## C. Trin 5a (én identitetsvej, #151)

59. **`samme_som`-klynger (719 relationer) kendes ikke af kandidatgeneratoren** (konkurrerende kandidater for samme historiske person) · BEV/identitetsvej-5a-bevis.md:107 · kendt begrænsning (overgivet til 5b/trin 6)
60. **1939-personers årstal: kun 18 af 370 fødselsassertions har `date_min/max` — kandidater får næsten kun navnesignal** · BEV/identitetsvej-5a-bevis.md:111 · kendt begrænsning (trin 6)
61. **Kandidatvisningen viser kun navn og leveår (ikke embede, titel, post)** · BEV/identitetsvej-5a-bevis.md:116 · ikke udviklet
62. **5a's 31 kalibreringsafgørelser overføres ikke til prod; webkøens `web_detail`-spor er ubrugt i prod** · DEC:230-245; ST:170 · udskudt/besluttet · 2026-10-21
63. **Webkøen blev ikke startet mod arbejdsbasen (ingen lokal API)** · BEV/identitetsvej-5a-bevis.md:94 · ubevist (web-spor kun via parity)
64. **Én identitetsvej for 1939 (den reelle 1939-identitetsvej er fortsat parallel)** · ST:204-207 · ikke udviklet (trin 6)
65. **Åbent issue #151: én identitetsvej — token-fil-review skriver proposed, webkøen bekræfter** · ISS:#151 · åbent issue
66. **Tupel-digest i 2a (`structural_family`-bindinger) dækker kun de 210 ældste promotion-rækker** · HUK (ikke fundet i dokumenter) · kendt begrænsning

## D. Trin 5b (relationspersonas, #151)

67. **Oprettelse af nye kanoniske personer (`relation_person_create`) er kun syntetisk bevist — 0 nye personer i hele kæden; forbliver `isoleret implementeret` også efter GO 2** · ST:166; BEV/relationspersonas-5b-navneregel-v3-bevis.md:167; DEC:~190 (punkt 7) · syntetisk bevist · 2026-10-25
68. **`existing`-placering (ny person i hovedpersonens eksisterende familie, skjuler familien indtil aktivering): 0 forekomster, ubevist; overførsel skal aktivere `relation_person_create`-personer i samme transaktion** · BEV/relationspersonas-5b-2b-ii-bevis.md:142; BEV/relationspersonas-5b-navneregel-v3-bevis.md:168 · ubevist
69. **P-identiteten (`new_person_needed`) bag den afviste 1314-fortolkning kan ryddes (identitet står uændret; writeren afviser oprettelse via `RELATION_PERSON_CREATE_INTERPRETATION_STALE`)** · BEV/relationspersonas-5b-navneregel-v3-bevis.md:165; BEV/relationspersonas-5b-2b-i-bevis.md:56,169; ST:166 · kendt begrænsning/oprydning · 2026-10-20
70. **Ordinal-rodfejl: `relation_marriage_ordinals` giver NULL-position, når bogens tekst ikke står ordret i klausulen (klausulopdelingsfejl); 4 falske `ordinal_afvigelse`; rettet i funktionen via ordvindue (#244), men NULL ved flertydigt vindue består; 6 øvrige ægte bog≠familie-afvigelser (ikke #244)** · BEV/relationspersonas-5b-navneregel-v3-bevis.md:131-137; BEV/aegteskabsnumre-244-bevis.md:98; DEC:311-333 · kendt begrænsning · 2026-10-20
71. **#244's rettelsesvej (`red_ret_aegteskabsnummer`) er deployet, men ubrugt i prod; genbinding med `supersedes` ikke øvet i prod** · ST:168; DEC:~190 punkt 3 · ubevist i prod
72. **Prod-genspil af #244: payloads med gammelt nummer afvises `SPAN_INVALID`; synlighedshul mellem rettelse og genbinding** · BEV/aegteskabsnumre-244-bevis.md:99 · løst via at fejlnumre aldrig opstod i prod (DEC 2026-10-25 pkt 3)
73. **Én påstand bundet til flere familier er udskudt (børneflok i to ægteskaber, »17 børn« 6+10); 2 børnehenvisninger står `proposed`** · BEV/relationspersonas-5b-2b-iii-bevis.md:117; DEC:309; ST:169 · udskudt
74. **Familiekorrektion for `F`-kortet er parkeret (kræver projektejerbeslutning)** · DEC:402; BEV/relationspersonas-5b-del1-bevis.md:132 · parkeret
75. **`samme_som` for dubletter fra `same_individual_person_ids` ikke udviklet (parkeret)** · DEC:402; BEV/relationspersonas-5b-del1-bevis.md:133 · parkeret
76. **Udtrækkets fejllæsning af »(F.: …)« som hovedpersonens forældre ⇒ falske `relation.parent`-påstande: ikke målt/rettet** · BEV/relationspersonas-5b-del1-bevis.md:134; ST:266 · ikke udviklet
77. **Forældrekort med unavngiven forælder (»faderen«) kan kun tjekkes mod stamtavlen; vis familiens øvrige børn** · BEV/relationspersonas-5b-del1-bevis.md:136 · ikke udviklet
78. **Final review M1-M10 fra del 1 (udskudt)**: M1 én kerneafvisning vælter hele bekræftelsen; M2 detalje-RPC/webkø viser familie/ordinal/rang for forseglede stikprøvesager; M3 flere forseglede kørsler vælges vilkårligt; M4 db-rls-masterliste mangler tre kontroltabeller; M5 casts i OR-kæder fejler med forkert kode; M6 NULL=NULL i familiekonteksten; M7 testhuller; M8 writeren godtager årstal; M9 kernen ignorerer ordinal ved én familie; M10 rækkefilen læser `private.*` som ejer · BEV/relationspersonas-5b-del1-bevis.md:138; ST:266 · udskudt · 2026-10-11
79. **Ægtefællers fødsel/død som promotionregel (hovedspec åbent punkt 3) ikke designet; nye personer har kun navn** · BEV/relationspersonas-5b-del1-bevis.md:146; SPEC/2026-10-17-trin5b-2b-ii-…-design.md:54,298 · ikke udviklet
80. **`mention.place` udsat: 246 klausuler i `afventer_identitet` (stedaktørforslag mangler persona); stedsentiteter ikke bygget** · DEC:311; BEV/relationspersonas-5b-2b-ii-bevis.md · udskudt · 2026-10-18
81. **Aldersregel v2 (udelad årstal i DAA-henvisning) er designet, men ubrugt; aldersreglen v1 tæller henvisningsår med (fejler lukket til N, koster dækning)** · DEC:321; BEV/relationspersonas-5b-2b-ii-bevis.md:~132 · udskudt · 2026-10-18
82. **Navneregel-fund fra 2b-ii**: titler inde i navne, partikler, partnersammenligning — rettet i v3; fem mindre fund udskudt (partnerens nummer fra ægteskabets egen række, P-forespørgsel kan give dubletrækker, fortolkningstjek i `write_relation_person_create` ikke bundet til nummerrækken, partnernavn med bogstaver i parentes giver `U`, `sheet_line` udokumenteret) · BEV/relationspersonas-5b-navneregel-v3-bevis.md:145-151 · udskudt · 2026-10-20
83. **Klausulopdelingens tre fejltyper (afsluttes for tidligt, starter midt i sætning, løber ind i overskrift; ét ægteskab citerer to klausuler) — hypotese ikke bevist, hører til segmenteringen** · BEV/relationspersonas-5b-2b-ii-bevis.md:134-140 · ubevist/åbent
84. **De tre `U` i navneregel v3 (afskåret klausul, manglende hovedperson, to klausuler) er uafklaret** · BEV/relationspersonas-5b-navneregel-v3-bevis.md:169-172 · åbent
85. **2b-ii dækning lav i første runde (2 af 14); mekanik bevist** · BEV/relationspersonas-5b-2b-ii-bevis.md:148 · historik
86. **Ét ægteskab forbliver forslag efter dubletreglen (GO 2); rettet i prod 2026-10-26 (PR #263)** · ST:34,168; DEC:125-158 · løst (medtaget)
87. **2b-i: 8 Minor udskudt; kendte begrænsninger (spec §12 pkt 1-8, errata §15.3-4): samtidige familieredigeringer, ingen kvittering, `F` via operatørens script, familievisning ved dubletter; Playwright-test udeladt** · BEV/relationspersonas-5b-2b-i-bevis.md:158-169 · kendt begrænsning/udskudt
88. **Dubletreglen: ingen ny webflade for uafklarede dubletter; reglen om »samme udgave« fravalgt; fravalgt at rette svaret `1=2`** · DEC:125-158 · kendt begrænsning · 2026-10-25
89. **Dubletreglen rettet i prod 2026-10-26, men 1939 har langt flere navnefæller (latent)** · DEC:193 (pkt 6); DEC:125 · bevidst åben backlog (delvist løst)
90. **#248: genåbning af forælder- og barnerelationer ikke bygget; ingen web-vej til genåbning; `family_member.ordinal`'s semantik uafklaret (pr. familie vs. pr. person; 92 personer med én familie og ordinal > 1)** · SPEC/2026-10-26-248-genaabning-ved-familieskift-design.md:119-124 · udskudt · 2026-10-26
91. **#248 skridt 1: ingen fortryd-vej (dump er nødudvej); to ordinal_afvigelser uden binding** · DEC:~78 (pkt 5); RB/fix-248-identitet-prod.md:53-56 · kendt begrænsning
92. **#240: 2018-20's kontrolkørsel beregnes nu `failed` (`kandidatinput_aendret`); fortryd kun indtil ægteskaberne afgjort; anonyme læsere ser ikke længere parrets vielse/noter for par 2** · DEC:110-120; RB/fix-240-dobbeltfamilier-prod.md:85-90 · kendt begrænsning
93. **Overførsel: fravalgt rettelse af reglen før GO 2; kandidatkørsel 1 og dens kontrolkørsel genskabes ikke (H3); aktørforskel i 2a's bevisbase** · DEC:160-201 · kendt begrænsning
94. **Ægtefællearket forudfyldte »S = kandidat 1« uden at vise navnefælle-konflikt; flere kontroller (`post_rivals`) først tilføjet efter fejl** · DEC:50-87 (pkt 4, 6) · løst, men et kendt mønster for fremtidige ark
95. **Familie-forankret maskinel bekræftelse: øvre 95 %-grænse ca. 13,9 %; ikke genmålt på 1939** · ST:166; BEV/relationspersonas-5b-del1-bevis.md · kendt begrænsning

## E. Trin 5c (placement/membership, #150)

96. **5c-2: læserne (web/mobil/packages) skifter til placement/membership — ikke specificeret endnu** (kontrakter navngivet i 5c-1 Task 6: `GridPlacementSummary`, `MatchPlacementPayload`, `PlacementCoordinates`, `PresensSchemeProjection`) · SPEC/2026-10-26-trin5c-placement-membership-design.md:54; DEC:~44 (pkt 5) · ikke udviklet (datalag mangler til appen)
97. **V-82..V-92: 11 børn i forælderens slægtled (diff=0 under V-70, slægtled 6) — mulig umarkeret slægtledsfald eller forkert relation; uafklaret i 5c-1, kan ikke godkendes i token-filen** · DEC:26; LEDGER (5c Task 1 opfølgning); ISS:#270 · åbent issue · 2026-10-27
98. **37 poster med uenighed om kuld (legacy arvede kuld over slægtledsgrænser; 6 gruppelinjer i token-filen)** · DEC:24-27 · kendt begrænsning/token-fil · 2026-10-27
99. **Membership gælder kun ved passende tilstand; 5c-2's læsere SKAL filtrere på gældende; vagter i identitetsvejene mod ikke-gældende memberships er uden for scope** · DEC:~43-46; SPEC/2026-10-26-trin5c-…-design.md:207-209 · kendt begrænsning
100. **Uden for scope i 5c: 1939's placering (trin 6), fjernelse af legacy-kolonner, præsenslistens scheme-scopede opslag, `founder`/`claimant`-roller, ægtefællers og børns placering** · SPEC/2026-10-26-trin5c-…-design.md:207 · udskudt
101. **De 4 sidste poster i linje I-IV (I-133, II-35, III-129, IV-94) har ingen hovedperson-persona: kun record-placement, ingen persona-placement/membership** · RB/150-placement-prod.md:140; LEDGER (5c Task 7 forarbejde) · kendt begrænsning
102. **Kilde 1 og 3 er asymmetriske (placement mod `existing_exact_binding`) indtil trin 6; kilde 3's 576 legacy-rækker får `retained_legacy`** · RB/150-placement-prod.md:~145; DEC:~38 · kendt begrænsning
103. **`red_slet_person` sletter memberships uden om promotions-RPC'ens reversal** (587 allerede blokeret af `PERSON_HAR_KILDEIDENTITET`) · RB/150-placement-prod.md:~143 · kendt begrænsning
104. **`backfill_slaegtled.R` frosset for kilder med dispositioner; `post_load_fixup.R` arver vagten** · RB/150-placement-prod.md:~146 · kendt begrænsning
105. **Blind kontrolstikprøve K=20: aflæst i dialog med agenten; ny blind stikprøve fravalgt** · DEC:~30-36 · kendt begrænsning · 2026-10-27
106. **Supabase DEFAULT PRIVILEGES giver `service_role` EXECUTE på nye funktioner (ACL-drift `EVIDENCE_PUBLIC_RED_ACL_DRIFT`); ny `red_*` skal fratage også `service_role`** · DEC:~47-48; LEDGER (5c Task 7) · kendt begrænsning (generel; jf. #164)
107. **Erklæret `placement` er `isoleret implementeret` i ST** (ikke opdateret efter 5c-1; 5c-1 i prod 2026-10-27 iflg. charter) · ST:173; SPEC/2026-10-27-review-trin-1-5-design.md · dokumentationsdrift

## F. Trin 6 (kæden ende-til-ende på begge referenceudgaver) og Trin 7 (tredje årbog)

108. **Trin 6: 1939's kæde (klausuler, fortolkning, identitet, promotion, publicering) ikke kørt gennem den fælles kæde** · RM:34-36; ST:25; SPEC/2026-09-06-trin4-…-design.md:681 · ikke udviklet
109. **Trin 6: 1939-klausulregler (OCR, orddelinger) ikke designet** · SPEC/2026-09-06-trin4-…-design.md:681 · ikke udviklet
110. **Trin 6: 1939-kandidater uden årstal og dubletter (navnefæller) skal håndteres; åbent punkt fra 5b §6.5 (1939-personer uden udfyldt dato)** · SPEC/2026-10-06-trin5b-relationspersonas-design.md:368; BEV/relationspersonas-5b-del1-bevis.md:58 · ikke udviklet
111. **Trin 6: fjernelse af legacy-kolonner først når begge udgaver er migreret** · SPEC/2026-10-26-trin5c-…-design.md:54 · udskudt
112. **Trin 7: tredje-årbogsprøve `specificeret`, ikke gennemført (generaliseringsbevis; kun lille profil + vokabularudvidelser)** · ST:179; RM:37-38 · ikke udviklet
113. **Den fælles flerudgavekæde er ikke integreret ende-til-ende; genimporten samlet NO-GO som generel leverance (pr. 2026-09-06-dommen)** · ST:127-135, 181 · kendt begrænsning
114. **Flere DAA-udgaver: roadmap uden kode — afventer en konkret PDF af en anden udgave** · docs/flere-daa-udgaver-roadmap.md:5 · ikke udviklet

## G. Tværgående

115. **Fable-review af trin 1-5 (konsistens og kodekvalitet) udestår før trin 6; `docs/review-trin-1-5` (charter + plan)** · ST:264; SPEC/2026-10-27-review-trin-1-5-design.md · åbent
116. **Mobilappen er kun dev (ikke prod); kun web + DB er prod-live** (mobil har tsc i CI men ingen prod-deploy) · HUK · kendt begrænsning/afgrænsning
117. **ST er ikke afstemt: række "Klausulgranularitet og coverage" står `specificeret` (trin 4 er produktionsverificeret); "Aktivt programmål" i tidlig tekst peger på #152; to hjælpetekster refererer GO 4-restpunkter som aktuelle** · ST:159, 129-133, 248; SPEC/2026-09-06-trin4-…-design.md:683 (åbent punkt 11.6) · dokumentationsdrift
118. **CI-håndhævelse af styringsmodellen (model 2) bevidst udskudt til den manuelle model er stabil** · DEC:1556 · udskudt · 2026-08-25
119. **CI kører kun på PR'er og manuelt (ikke ved push til main) — Actions-minutter begrænsede; ikke-testede grene/nodejobs først på PR** · CLAUDE.md; LEDGER (248 Task 3) · kendt begrænsning
120. **Tests i `tests/sql/`, `db-verify.sql` og en fuld prod-lignende `db-verify` kører ikke mod prod (muterende fixtures); `db-verify` mod prod-kopi viser ACL-drift** · DBS:448; LEDGER (5c Task 7) · kendt begrænsning
121. **Lokal diskoprydning: 718 lokale baser / 14,6 GB, `daa44_rehearsal_*` 66 baser m.fl.; sletning kræver måling først** · LEDGER (4.5 Task 8); BEV/2018-20-fuld-koersel.md:~160 · udskudt
122. **Ikke-pushede docs-grene og memory-noter om prod-tilstand (fx `docs/151-go2-dublet-i-prod`, `docs/248-skridt1-i-prod`, `docs/248-rute-a-i-prod`, `docs/240-i-prod`)** · HUK (trin5-opdeling) · udestående dokumentation
123. **Restore uden planner-statistik: ANALYZE + materialiserede view-joins kræves i ceremonier (ellers 21 min vs 70 s)** · DEC:~48 (pkt 8); HUK · kendt begrænsning
124. **Prods `statement_timeout` er 2 min, lokale baser har ingen grænse; øvelser skal efterligne** · ST:~165; HUK · kendt begrænsning
125. **Prod er ICU, lokale baser libc: hashes/ordning skal bruge `COLLATE "C"`/ICU-genspilsbaser** · ST:~167; HUK · kendt begrænsning
126. **`datamodel`: kompleks flytning `person.visning_*` cache (invariant 4) — ingen kendte åbne punkter fundet i kilderne; `levende` GDPR-gate uden samtykke-flag (se A.24)** · CLAUDE.md; DBS:290 · (ingen yderligere fund)

## Slået sammen (dubletter)

Antal dubletter slået sammen: 20 (angivet nedenfor) — hver er ét punkt ovenfor med flere kilder.
- P-identitet `new_person_needed`: ST:166 + v3-bevis:165 + 2b-i-bevis:56,169 + HUK -> punkt 69
- Ordinal-rodfejl: DEC:311-333 + v3-bevis:131-137 + 244-bevis + HUK -> punkt 70
- Personoprettelse syntetisk: ST:166 + v3-bevis:167 + DEC 2026-10-25 pkt 7 + 2b-ii-bevis:142 + HUK -> punkt 67
- `existing`-familie: 2b-ii-bevis:142 + v3-bevis:168 + HUK -> punkt 68
- V-82..V-92: DEC:26 + LEDGER + ISS #270 + HUK -> punkt 97
- 5c-2: SPEC 5c:54 + DEC + HUK -> punkt 96
- Mobil dev-only: HUK (kun) -> punkt 116
- 138 navne-assertions: DEC:497 + DEC:542 + ST:271 + 2018-20-fuld-koersel:114 -> punkt 40
- Promptversion »var †«: DEC:497 + ST:271 + kontrolmodel-bevis + genbind-bevis + 2018-20-fuld -> punkt 38
- Kvotefejl i runner: DEC:497 + ST:271 + 2018-20-fuld-koersel:122 -> punkt 42
- Familiekorrektion `F` + `samme_som`: DEC:402 + del1-bevis:132-133 + ST:266 -> punkt 74/75
- Børn i to ægteskaber: 2b-iii-bevis:117 + DEC:309 + ST:169 -> punkt 73
- 4 unresolved_text: ST:248 + 149b-rehearsal + LEDGER -> punkt 3
- NOISE_RE: ST:248 + 149b-rehearsal -> punkt 4
- Dubletregel/1939-navnefæller: DEC:125 + DEC:193 + ST:34 -> punkt 86/89
- #244 rettelsesvej ubrugt: ST:168 + DEC 2026-10-25 pkt 3 + 244-bevis -> punkt 71
- samme_som-klynger: 5a-bevis:107 + 5b-del1 + HUK -> punkt 59
- 16 tomme unioner: DEC:1815 + ISS #163 -> punkt 16
- Hel-person-sletning: ST:241 + DEC:1901 + DEC:1198 -> punkt 1/2
- Hændelsesudtræk: DEC:1693 + ISS #130 + DBS:297 -> punkt 20

## Læste filer (helt eller delvist)

Alle under `eksport/`:
1. `_issues.txt` (helt)
2. `_ledger-rulings.txt` (helt, via grep/uddrag)
3. `docs/evidensbaseret-genimport/status.md` (helt)
4. `docs/evidensbaseret-genimport/roadmap.md` (helt)
5. `docs/decisions.md` (linje 1-420 helt, resten via grep + udvalgte afsnit: 470-545, 590-605, 655-770, 896-912, 1000-1010, 1190-1202, 1398-1405, 1660-1935, 2066-2156, 2433-2440, 3236-3330)
6. `docs/evidensbaseret-genimport/relationspersonas-5b-del1-bevis.md` (delvist)
7. `docs/evidensbaseret-genimport/relationspersonas-5b-2b-i-bevis.md` (delvist)
8. `docs/evidensbaseret-genimport/relationspersonas-5b-2b-ii-bevis.md` (delvist)
9. `docs/evidensbaseret-genimport/relationspersonas-5b-2b-iii-bevis.md` (delvist)
10. `docs/evidensbaseret-genimport/relationspersonas-5b-navneregel-v3-bevis.md` (delvist)
11. `docs/evidensbaseret-genimport/aegteskabsnumre-244-bevis.md` (delvist)
12. `docs/evidensbaseret-genimport/identitetsvej-5a-bevis.md` (delvist)
13. `docs/evidensbaseret-genimport/interpretation-pilot-2018-20.md` (delvist)
14. `docs/evidensbaseret-genimport/2018-20-fuld-koersel.md` (delvist)
15. `docs/evidensbaseret-genimport/kontrolmodel-koersel-2018-20.md` (delvist)
16. `docs/evidensbaseret-genimport/omsegmentering-rehearsal-2018-20.md` (delvist)
17. `docs/evidensbaseret-genimport/genbind-44-pilot-2018-20.md` (delvist)
18. `docs/evidensbaseret-genimport/legacy-migration-149b-rehearsal.md` (delvist)
19. `docs/evidensbaseret-genimport/source-evidence-149a-rehearsal.md` (delvist)
20. `docs/evidensbaseret-genimport/proposal-ingest-147-4-4-rehearsal.md` (delvist)
21. `docs/evidensbaseret-genimport/runner-rehearsal-147-4-3a.md` (delvist)
22. `docs/evidensbaseret-genimport/evidence-phase-reconciliation-156-2026-09-03.md` (delvist)
23. `docs/evidensbaseret-genimport/clause-evidence-148-rehearsal.md`, `runner-rehearsal-147-4-3b.md`, `proposal-ingest-147-4-4-projection-rehearsal.md`, `interpretation-predicate-147-rehearsal.md`, `c3-production-apply-2026-08-29.md`, `c3-task9-rehearsal-2026-08-29.md`, `reimport-writer-153-rehearsal.md`, `narrative-record-key-152-rehearsal.md`, `legacy-migration-149b-phase-package-contribution.md` (kun grep efter nøgleord)
24. `docs/evidensbaseret-genimport/teknisk-maalarkitektur.md`, `vision.md` (kun grep)
25. `docs/database-current-state.md` (delvist: 125-140, 188-236, 286-312)
26. `docs/runbooks/150-placement-prod.md`, `248-genaabning-prod.md`, `fix-240-dobbeltfamilier-prod.md`, `fix-248-identitet-prod.md` (afsnit "Kendte følger")
27. `docs/superpowers/specs/2026-10-26-trin5c-placement-membership-design.md`, `2026-10-26-248-genaabning-ved-familieskift-design.md`, `2026-09-06-trin4-fortolkningskaede-og-klausulgranularitet-design.md`, `2026-10-27-review-trin-1-5-design.md` (delvist); `2026-10-21-trin5ab-…`, `2026-10-17-trin5b-2b-ii-…`, `2026-10-11-trin5b-2b-i-…`, `2026-10-06-trin5b-…`, `2026-09-27-trin4-omsegmentering-…` m.fl. (kun grep)
28. `docs/flere-daa-udgaver-roadmap.md`, `docs/plan-1939-produktionsklar.md`, `docs/moed-en-slaegtning-roadmap.md` (kun grep)

Ikke læst: work/, work_1939_stamtavle/, work_presens/, ~/.private/, dumps, manifest*, kontrolark*, token*, aktoer*, .env*.

Usikkerheder: (a) enkelte linjenumre er angivet med ~ (omtrentlige); (b) punkt 66 og 116 hviler kun på projektets hukommelse; (c) punkterne 14-16 og 30 stammer fra 2026-08-20 og er ikke genmålt, så status kan være overhalet; (d) punkt 126 er en bekræftelse af fravær, ikke et fund.
