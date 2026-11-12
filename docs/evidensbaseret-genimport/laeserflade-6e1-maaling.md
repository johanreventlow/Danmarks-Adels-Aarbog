# Måling: læserfladens fakta pr. udgave, trin 6e-1 (2026-11-12)

Spec: `docs/superpowers/specs/2026-11-12-trin6e-laeserflade-design.md` §5.1-5.5 (»plan-Task 0«). Plan:
`docs/superpowers/plans/2026-11-12-trin6e1-laeserflade-klient.md` Task 5. Kun antal; ingen navne, ingen værdier.

- **Base:** lokal stand-in `daa5ab_ddl_standin_20261111191901_slut` (kopi af prod efter 6d-3), kun læsning.
- **Kørsel:**
  `PGDATABASE=daa5ab_ddl_standin_20261111191901_slut npx tsx tools/maal-6e1/maal.ts --ark <scratchpad>/6e1-stikproeve.html`
  (≈10 s; heraf ≈9,3 s psql og RPC'er, ≈0,2 s core).
- **Metode:** den rigtige core-kode (`collapseSameAs`, `udgaverMedFakta`, `byggUdgaveFakta`, `byggUdgaveVaelger`)
  på data hentet som klienten gør: offentlige personrækker efter anon-reglen (`levende = false` og ikke `privat`),
  afklarede `samme_som`-kanter, `public_person_source_coordinates()`, `public_person_facts(...)`,
  `public_person_bio_source_versions_v2(...)` og `citation.citat_tekst` for valgte påstande uden `source_id`.
  En visning pr. komponent og valgbar udgave (chipsenes udgaver og udgaver med fakta).

## Grundtal

| | Antal |
|---|---|
| Offentlige personrækker | 1.739 (`privat = false` alene giver 1.809; 3 afklarede kanter rører en skjult række) |
| Afklarede `samme_som`-kanter | 768 |
| Karantænerede grupper (foldes ikke) | 12: 6 konkurrerende forældre, 3 fødsler for langt fra hinanden, 3 ufuldstændige (en skjult række) |
| Komponenter (kanoniske personer) | 983, heraf 720 med flere medlemmer |
| Komponenter med fakta i begge udgaver | 720 |
| Personrækker med mere end én koordinatrække | 0 |
| Fakta-rækker fra RPC'en / bio-rækker / fritekstcitater | 6.470 / 1.100 / 80 |

## Pr. faktatype

Linjer i den valgte udgave, linjer med »✓ også«, »skriver«-noter, »Kun i«-grupper (værdier i parentes).

**Valgt DAA 2018-20**

| Faktatype | Linjer | ✓ også | Skriver | Kun i |
|---|---:|---:|---:|---:|
| navn | 849 | 218 | 505 | 0 |
| død | 670 | 262 | 141 | 7 (7) |
| fødsel | 582 | 319 | 104 | 4 (4) |
| titel | 383 | 96 | 0 | 201 (245) |
| dåb | 200 | 12 | 40 | 2 (2) |
| begravelse | 174 | 5 | 39 | 5 (5) |
| dekoration | 131 | 0 | 0 | 0 |
| floruit | 104 | 0 | 0 | 0 |
| dødsårsag | 21 | 0 | 0 | 0 |
| klosterindgang | 8 | 0 | 0 | 0 |
| tilnavn | 5 | 0 | 0 | 0 |
| adling | 4 | 0 | 0 | 0 |
| overhoved | 1 | 0 | 0 | 0 |
| **I alt** | **3.132** | **912** | **829** | **219 (263)** |

**Valgt DAA 1939**

| Faktatype | Linjer | ✓ også | Skriver | Kun i |
|---|---:|---:|---:|---:|
| navn | 864 | 224 | 519 | 0 |
| død | 449 | 267 | 141 | 204 (204) |
| fødsel | 447 | 319 | 104 | 114 (114) |
| titel | 362 | 96 | 0 | 190 (254) |
| begravelse | 55 | 5 | 39 | 118 (118) |
| dåb | 55 | 12 | 40 | 127 (132) |
| floruit | 0 | 0 | 0 | 65 (65) |
| dekoration | 0 | 0 | 0 | 57 (128) |
| dødsårsag | 0 | 0 | 0 | 21 (21) |
| klosterindgang | 0 | 0 | 0 | 5 (5) |
| tilnavn | 0 | 0 | 0 | 4 (4) |
| adling | 0 | 0 | 0 | 4 (4) |
| **I alt** | **2.232** | **923** | **843** | **909 (1.049)** |

Titel og dekoration er flerværdi-typer: de får aldrig »skriver«, kun »✓ også« eller »Kun i«.

## Vælger, etiketter og tab

- **Vælgerform pr. komponent:** `ingen` 263 · `chips` 459 · `skift` 261.
- **Etiketter:** 7.090 synlige kildeetiketter skannet (fakta-linjernes kilder, »andre udsagn« og vælgerens chips):
  0 med `record-`, 0 med `legacy-source:`.
- **Tabstjek:** hver ikke-tom linje i en anden udgaves visning er genfundet som »✓ også«, i en »skriver«-note eller
  under »Kun i« — undtagen 1 linje, en redaktøroprettet `overhoved`-markering uden udgavens egen kilde (vises kun i
  sin egen udgave; afgørelse 3 i forløbet). 0 »✓ også«-noter uden et ens modstykke i den anden udgave.

## De 17 redaktørpåstande (spec §5.1)

17 personfakta-påstande har en citation uden `source_id` (ekskl. `forældrefamilie`/`forældre_ukendt`):
11 valgte på offentlige rækker, 1 ikke-valgt på en offentlig række (`navn`) og 5 `overhoved` på rækker, læseren ikke
ser. De 11:

| Gruppe | Antal | Typer |
|---|---:|---|
| Udgavens egen (valgt påstand vist) | 8 | 6 navn, 1 død, 1 dåb |
| Bøgernes ord vist (udgavens egen påstand i stedet) | 2 | 2 navn |
| Som i dag (ingen udgaveegen påstand) | 1 | 1 overhoved |

Afgørelsen bruger core: faktummets linje i personrækkens udgave viser enten en anden værdi end den valgte påstand
(»bøgernes ord«) eller den valgte; i sidste fald skelner en probe — en syntetisk tredje udgave med samme værdi —
mellem udgavens egen (linjen får »✓ også«) og »som i dag« (linjen indgår aldrig i noter).

**Kontrolkomponenten** (255, 392, 1198; kanonisk 392), valgt DAA 2018-20: to navnelinjer, begge med »DAA 1939
skriver: …«, den ene er 2018-20's egen påstand i stedet for redaktørens valg (spec §5.2's eksempel); fødsel og død »✓ også i DAA 1939«; titel
4 linjer, én med »✓ også«; ingen »Kun i«.

## Stikprøve

925 unikke »✓ også«-par (fødsel 320 · død 268 · navn 224 · titel 96 · dåb 12 · begravelse 5). 40 par trukket med
fast seed `6e1` (fødsel 13 · navn 11 · død 11 · titel 5; dåb og begravelse fik ingen) og sendt til projektejeren
som et ark med begge udgavers ord, udgave og side. Arket ligger uden for repo'et.

**Dom:** afventer projektejeren. Et falsk par sætter typen i `SLUKKET_ENIGHED` (Task 6), indtil reglen er rettet og en
ny stikprøve for typen er ren.
