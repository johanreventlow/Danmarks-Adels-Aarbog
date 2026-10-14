# Trin 5b del 1 — ægtefællers relationspersonas og maskinel bekræftelse: færdigbevis i restore (2018-20)

Beslutninger: `docs/decisions.md` 2026-10-06 (familie-forankret identitet, `family_corroboration`) og
2026-10-10 (kontrollen omdesignet til korte kort; børn og uoverensstemmelser til del 2). Spec:
`docs/superpowers/specs/2026-10-06-trin5b-relationspersonas-design.md` (§23 og errata §22). Planer:
`docs/superpowers/plans/2026-10-06-trin5b-del1-identitet.md` (Task 0-10) og tillægget
`docs/superpowers/plans/2026-10-10-trin5b-del1-kontrolkort.md` (Task 11-14). Merget 2026-10-11 (#237,
`ebf2022`). Kørt 2026-10-10—11 i en kopi af den fulde 2018-20-kørsels base, aldrig i prod. Rapporten
indeholder tal, hashes og basenavne — ingen navne, ingen kildetekst og ingen persona- eller person-id'er.

## Kort svar

Ægtefællerne i 2018-20 har nu egne personas med kildebundne navnepåstande, og identiteten kan bekræftes
maskinelt, når familien bærer den: ægtefællens kandidat er hovedpersonens partner i den kanoniske familie
med samme ægteskabsnummer. Før maskinen må bekræfte noget, afgør projektejeren et blindt, hash-bundet ark
med 30 ægtefællekort (alle 10 navnefæller + 20 tilfældige). Arket gav **0 afvigelser** ⇒ kontrolkørslen
`passed` ⇒ **173** personas bekræftet maskinelt (`family_corroboration`). 0 af 20 tilfældige kort giver
en øvre ensidig 95 %-grænse for fejlraten på **ca. 13,9 %** — en advarselslampe, ikke en validering.
Personerne er oprettet fra samme bog, så beviset er næsten selvbekræftende (spec §4); metoden prøves for
alvor først på en anden udgave.

Børn, de 31 uoverensstemmelser, nye personer og familiekorrektion er del 2.

## Grundlag

| | |
| --- | --- |
| Arbejdsbase | `daa5b_bevis_20261010093638` = kopi af `daa2018f_20261001133125` (den fulde 2018-20-kørsel), løftet med `db-migrations.sql` + `db-rls.sql` til `a575f6b` (= merge-træet): `VERIFY_OK`, db-verify-rester 0. **Bevares til del 2.** |
| Kilde | 1 (DAA 2018-20) |
| Udtræksprofil | `relation-persona-2018-20-v1`; kun navne (år står uden for påstandens spænd i 201/249 klausuler, errata §22.7) |
| Generator | `identity-candidates-1.1`, `familyNameMin` 0,95, `--top-k 10` |

## Udtræk og writer

| | |
| --- | --- |
| Elementer | 257: ægteskab 234, barn 13, forælder 10 |
| Parkeret | 15: `flere_klausuler` 1, `ikke_ordret` 6, `ingen_hovedperson` 1, `intet_navn` 6, `tvetydigt_spaend` 1 |
| Skrevet | 491 parter, 234 mentions, 234 ægtefælle-personas, 0 årsfortolkninger |
| Manifest | `9bd0bf14…` |

Børnepåstandene (13 udtrukne elementer) skrives, men indgår hverken i kontrol eller bekræftelse: 12 af
basens 14 målte børneudsagn havde 2–16 kandidater i samme familie, og arket kunne ikke vise barnets tekst (errata §22.9).

## Kandidater

| | |
| --- | --- |
| Kandidatkørsel | run 2: 234 personas, 2.327 kandidater, 203 egnede til familiebekræftelse |
| Hashes | config `2f3f71a3178e6465451abf17c459260ce62d306924bb9effbba7df8c8896d64d`, input `082a134a5dc34e1f6ffc40be09acee7ea79b3e2f543a938b5772d57e9298ab96`, kandidater `d2bf05e98418619efd5115f4ccb76c927349605191b43d6688ff440e9492c996` |
| Uoverensstemmelser | 31 (234 − 203): antal ægteskaber passer ikke 9, navn/rang 22 — til del 2 |
| Navnefæller | 10 personas med netop én navnefælle blandt kandidaterne, 0 med flere |

**Valg af `familyNameMin` 0,95** (højeste værdi, der holdt arket under 80 linjer): 0,85 gav 212 egnede /
22 uoverensstemmelser, 0,9 gav 208/26, 0,95 gav 203/31. Prisen er 9 flere sager til mennesket end ved 0,85.

Globale kandidater (uden for familien): 466, heraf 15 1939-personer uden dato (3,2 % < 10 %) — et åbent
punkt til trin 6, ikke til del 2 (spec §6.5).

## Kontrolkørsel og ark (spec §23)

| | |
| --- | --- |
| Udvalg | 30 ægtefællekort: navnefæller 10 + `K` = 20 tilfældige (én familie 16, flere familier 4); 9 forældrekort; 0 udelukket |
| Populationer | identitet `1a310b36ab1a90d6587a4156b6922d39f8399a989b13b187b6cc380d530e1a02`, relation `ac17aa8a2b57dd806b9e8b73689c0ed5900ec3bd1f24dab7319bd2d8312734d2`, inputliste `76fad21445d9fd8404de714d8557ed5eaded64c2dbd03018db73f6f29ce0c336`, udelukket `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| Rækkefil | `426989d69d4c37338b6580a69507375c0cdc5c0af372d483b0819707caa1e7d4` |
| Godkendt ark | `afe87f46e3afa2f84a53d1e6f1391602b8703772ce729b923efb01c37cdfac0c` |
| Hændelser | `sealed` → `passed` |

Alle kort viste 3 kandidater; maskinens eget svar stod på plads 1/2/3 i 10/12/8 kort (blandet, så
pladsen ikke afslører svaret). 52 af 147 viste personer manglede fødeår og 39 dødsår — ingen af dem har en
afklaret konklusion, så det er ægte ukendt, ikke en tom cache.

| Ægtefællekort | Plads 1 | Plads 2 | Plads 3 | Dublet (`1=2`) | Afvigelser |
| --- | --- | --- | --- | --- | --- |
| 30 | 9 | 12 | 8 | 1 | **0** |

| Forældrekort | `A` | `R` | `F` | `U` | `familie_aendret` |
| --- | --- | --- | --- | --- | --- |
| 9 | 7 | 1 | 1 | 0 | 0 |

**Dublet-kortet:** to ikke-sammenkædede personrækker for samme individ stod på samme kort. Svaret `1=2`
tæller som enighed, fordi maskinens kandidat er blandt de nævnte, og de to er navnefæller (§23.4).
Identiteten bindes til den laveste plads; `same_individual_person_ids` gemmes til del 2's `samme_som`-arbejde.

Arket blev lavet tre gange. Første udgave (med børn) og anden (63 linjer, uden hovedperson og bogens
sætning) blev forkastet uudfyldt, fordi projektejeren ikke kunne besvare linjerne uden bogen; det førte til
kortdesignet i §23 (decisions 2026-10-10). Svarene fra den delvist udfyldte tredje udgave blev overført
mekanisk, da forældrekortene fik markering af forældreudsagnet (ny rækkefil, ny hash).

## Negativtests (kopier i karantæne)

| # | Indgreb | Resultat |
| --- | --- | --- |
| 1 | Bekræftelse før forsegling | `IDENTITY_CONTROL_NOT_PASSED` |
| 2 | Ark med `U` på et ægtefællekort | `failed`, 0 bekræftet |
| 3 | Forkert mængde-hash til bekræftelsen | `IDENTITY_CORROBORATION_SET_DRIFT`; hændelser 2 → 2, bekræftet 0 → 0 |
| 4 | Udelukket persona | Ikke kørbar (kørslen har 0 udelukkelser); dækket af `test-family-corroboration.sql` (G-22) |
| 5 | `A`-forældrekort efter fjernet partner | `passed` + `familie_aendret` 1; påstanden forbliver `proposed` |

Det rigtige ark i en af kopierne gav `passed`. »Tilføjet familie« kan ikke opstå (én fødselsfamilie,
højst to partnere), derfor test 5 med fjernet partner.

## Webspor-paritet

Kørt i en transaktion med `ROLLBACK` (en ikke-truffet afgørelse må ikke ligge i den bevarede base).

| Evidensnøgler | |
| --- | --- |
| Webspor (`web_detail`) | `action, basis, candidate_id, candidate_rank, note, run_id` |
| Kun i arkspor | `control_run_id, display_position, line, rows_sha256, sheet_sha256` |
| Kun i webspor | — |

## Review

Spec: Claude + Codex runde 1, Codex runde 2-7 (konvergerende; runde 7 kun 2 MINOR). Plan: Codex runde 1
NO-GO (8 fund, 7 rettet; ét afvist pga. en godkendt ruling), runde 2 NO-GO (3 fund, alle rettet). §23:
design-review (Codex: omdesign) + Opus-genreview GO. Final review (Opus): 0 Critical, 3 Important — alle
rettet med regressionstest (kernen kræver gemt ægteskabsnummer ved flere familier; dublet-svar kun for
navnefæller; ny kontrolkørsel efter `failed` kræver årsag) — og 10 Minor, udskudt (M1-M10 nedenfor).
Opgraderingen af en eksisterende base fejlede på den ændrede registreringssignatur
(`EVIDENCE_PUBLIC_RED_ACL_UNCLASSIFIED`), som CI ikke ser, fordi CI bygger fra frisk schema; rettet og
afprøvet fra både `3bce5f3` og `main` (`796f603`). CI grøn på #237.

## Til del 2

Projektejerens beslutninger (decisions 2026-10-10) og fund fra kontrolarket:

1. **Børn** (`relation.child`) — kræver barnets tekst og søskende på kortet (§22.9).
2. **De 31 uoverensstemmelser** og forælderen uden kandidat; prioriteret som §23.5.
3. **Nye personer** for ægtefæller uden kandidat.
4. **Familiekorrektion** for `F`-kort (1) — særskilt workflow, kræver projektejerbeslutning.
5. **`samme_som` for dubletter** fra evidensens `same_individual_person_ids`.
6. **Udtrækkets fejllæsning:** »(F.: …)« efter en ægtefælle læses som hovedpersonens forældre ⇒ falske
   `relation.parent`-påstande. Mål antallet og ret udtrækket.
7. **Forældrekort med unavngiven forælder** (»faderen«) kan kun tjekkes mod stamtavlen — vis familiens
   øvrige børn på kortet.
8. **Final reviews Minor-fund:** M1 én kerneafvisning vælter hele bekræftelsen — registreringen skal
   udelukke kerne-afviselige personas (dobbelt mål, primær-tælling, NULL-kontekst, ordinal-drift); M2
   detalje-RPC/webkø viser familie, ordinal og rang for forseglede stikprøvesager (blindhed er procedure);
   M3 flere forseglede kørsler for samme persona vælges vilkårligt (fail-closed); M4 db-rls' masterliste
   mangler tre kontroltabeller; M5 casts i OR-kæder fejler lukket med forkert fejlkode; M6 kernen godtager
   NULL = NULL i familiekonteksten; M7 testhuller (»accepteret til anden person«, Focus 3 gennem RPC'en);
   M8 writeren godtager stadig årstal; M9 kernen ignorerer ordinal ved én familie (skal nævnes i decisions);
   M10 rækkefilen læser `private.*` som ejer, ikke gennem en rollegatet RPC.
9. **Ægtefællers år** (fødsel/død) — udeladt i del 1 (§22.7).
