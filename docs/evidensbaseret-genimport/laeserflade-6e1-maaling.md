# Måling: læserfladens fakta pr. udgave, trin 6e-1 (2026-11-12)

Spec: `docs/superpowers/specs/2026-11-12-trin6e-laeserflade-design.md` §5.1-5.5 (»plan-Task 0«). Plan:
`docs/superpowers/plans/2026-11-12-trin6e1-laeserflade-klient.md` Task 5. Kun antal; ingen navne, ingen værdier.

- **Base:** lokal stand-in `daa5ab_ddl_standin_20261111191901_slut` (kopi af prod efter 6d-3), kun læsning.
- **Kørsel:**
  `PGDATABASE=daa5ab_ddl_standin_20261111191901_slut npx tsx tools/maal-6e1/maal.ts --ark <scratchpad>/6e1-stikproeve.html`
  (≈10 s; heraf ≈9,3 s psql og RPC'er, ≈0,2 s core).
- **Metode:** den rigtige core-kode (`collapseSameAs`, `udgaverMedFakta`, `byggUdgaveFakta`, `byggUdgaveVaelger`)
  på data hentet som anon-læseren ser dem: personrækker efter `person_offentlig` (`db-rls.sql`: `levende = false`, ikke
  `privat`, ikke `staged`), afklarede `samme_som`-kanter med begge endepunkter offentlige (relation-policyen skjuler
  resten, så de fjernes før foldningen), `public_person_source_coordinates()`, `public_person_facts(...)`,
  `public_person_bio_source_versions_v2(...)` og `citation.citat_tekst` for valgte påstande uden `source_id`.
  En visning pr. komponent og valgbar udgave (chipsenes udgaver og udgaver med fakta). Alle psql-kald kører med
  `default_transaction_read_only=on`.
- **Genkørt efter Task 7b** (relative datoer opløses, ledende tegn og sideform, spec §5.4a/§5.8) på samme stand-in;
  tabellerne nedenfor er tallene efter 7b, med tallet før 7b i parentes, hvor det har ændret sig.

## Grundtal

| | Antal |
|---|---|
| Offentlige personrækker | 1.732 (`privat = false` alene giver 1.809) |
| Afklarede `samme_som`-kanter | 768, heraf 763 synlige for anon (5 rører en skjult række og foldes ikke) |
| Karantænerede grupper (foldes ikke) | 9: 6 konkurrerende forældre, 3 fødsler for langt fra hinanden |
| Komponenter (kanoniske personer) | 978, heraf 720 med flere medlemmer |
| Komponenter med fakta i begge udgaver | 720 |
| Personrækker med mere end én koordinatrække | 0 |
| Fakta-rækker fra RPC'en / bio-rækker / fritekstcitater | 6.470 / 1.100 / 80 |

## Pr. faktatype

Linjer i den valgte udgave, linjer med »✓ også«, »skriver«-noter, »Kun i«-grupper (værdier i parentes).

**Valgt DAA 2018-20**

| Faktatype | Linjer | ✓ også | Skriver | Kun i |
|---|---:|---:|---:|---:|
| navn | 849 | 218 | 505 | 0 |
| død | 670 | 265 (262) | 138 (141) | 7 (7) |
| fødsel | 582 | 319 | 104 | 4 (4) |
| titel | 383 | 96 | 0 | 201 (245) |
| dåb | 200 | 12 | 40 | 2 (2) |
| begravelse | 174 | 4 (5) | 40 (39) | 5 (5) |
| dekoration | 131 | 0 | 0 | 0 |
| floruit | 104 | 0 | 0 | 0 |
| dødsårsag | 21 | 0 | 0 | 0 |
| klosterindgang | 8 | 0 | 0 | 0 |
| tilnavn | 5 | 0 | 0 | 0 |
| adling | 4 | 0 | 0 | 0 |
| overhoved | 1 | 0 | 0 | 0 |
| **I alt** | **3.132** | **914 (912)** | **827 (829)** | **219 (263)** |

**Valgt DAA 1939**

| Faktatype | Linjer | ✓ også | Skriver | Kun i |
|---|---:|---:|---:|---:|
| navn | 864 | 224 | 519 | 0 |
| død | 449 | 270 (267) | 138 (141) | 204 (204) |
| fødsel | 447 | 319 | 104 | 114 (114) |
| titel | 362 | 96 | 0 | 190 (254) |
| begravelse | 55 | 4 (5) | 40 (39) | 118 (118) |
| dåb | 55 | 12 | 40 | 127 (132) |
| floruit | 0 | 0 | 0 | 65 (65) |
| dekoration | 0 | 0 | 0 | 57 (128) |
| dødsårsag | 0 | 0 | 0 | 21 (21) |
| klosterindgang | 0 | 0 | 0 | 5 (5) |
| tilnavn | 0 | 0 | 0 | 4 (4) |
| adling | 0 | 0 | 0 | 4 (4) |
| **I alt** | **2.232** | **925 (923)** | **841 (843)** | **909 (1.049)** |

Titel og dekoration er flerværdi-typer: de får aldrig »skriver«, kun »✓ også« eller »Kun i«.

**Hvad 7b flyttede** (samme linjer; kun noterne skifter):

- **død +3 ✓ / −3 skriver pr. visning:** 4 nye ✓-par, hvor den ene udgaves værdi før viste samme dødsangivelse to
  gange (teksten og »† …«); med det ledende tegn fjernet før sammenligningen vises den én gang og er ens med den anden
  udgave. 1 tidligere ✓-par med ens »s.m.«-tekst på død er nu »skriver« (død opløses ikke og giver aldrig ✓).
- **begravelse −1 ✓ / +1 skriver pr. visning:** 1 tidligere ✓-par med ens »s.m.«-tekst kan ikke opløses, fordi
  dødsdatoen, den henviser til, selv er relativ — nu »skriver«. Parret var nr. 42 i det bedømte ark.
- **dåb uændret (12 ✓):** alle 12 dåbs-✓ og 2 af de 4 begravelses-✓ var før ens relativ tekst; nu hviler de på de
  opløste datoer, som stadig er ens. 4 af de 14 er bedømt i arket (nr. 43-46).

## Relative datoer (spec §5.4a)

Enhed: viste fakta i personrækkens egen udgave, hvis viste værdi før opløsningen indeholder »s.m.«/»s.d.«/»s.å.« (eller
»samme dag/måned/år«). Det er ikke det samme som spec'ens ~365 påstande (der tæller påstande, ikke viste fakta), men
tallene ligger tæt. Opløst / ikke opløst er core's egen afgørelse (`relativeDatoer`), ikke en genberegning.

| Udgave | Faktatype | Opløst | Ikke opløst | Årsag (ikke opløst) |
|---|---|---:|---:|---|
| DAA 2018-20 | dåb | 178 | 1 | ville ligge før fødslen |
| DAA 2018-20 | begravelse | 106 | 10 | 8 dødsdatoen er selv relativ · 1 usikker reference (skråstreg) · 1 flertydig i teksten |
| DAA 2018-20 | død | 0 | 12 | typen opløses ikke |
| DAA 2018-20 | titel | 0 | 4 | typen opløses ikke |
| DAA 2018-20 | dekoration | 0 | 3 | typen opløses ikke |
| DAA 1939 | dåb | 21 | 0 | |
| DAA 1939 | begravelse | 8 | 3 | dødsdatoen er selv relativ |
| DAA 1939 | død | 0 | 16 | typen opløses ikke |
| DAA 1939 | titel | 0 | 2 | typen opløses ikke |
| **I alt** | | **313** | **51** | |

Konservative regler ud over spec'en (*mit valg*; ikke opløst = bogens tekst, aldrig »✓«):

- **Usikker eller flertydig reference** (»ca.«, »o.«, »før«, »eller«, »?«, et interval, en skråstreg som »21./22. april«
  eller »1644/45«, to forskellige datoer, dage eller måneder (»21. og 22. april«), et andet år i parentes
  (»1644 (45)«)) opløses ikke: en sikker dato må ikke udledes af en usikker.
  Rammer 1 (skråstreg; den blev opløst før review-rettelsen).
- **Opløsning pr. del:** `vaerdi_tekst` og `date_raw` opløses hver for sig og derefter tjekkes for dobbelt værdi
  (spec §5.8). `date_raw` vises ikke igen, når den er lig `vaerdi_tekst`, eller når `vaerdi_tekst` slutter med den,
  og den er mere end et årstal (afgørelse 13). Kan én del ikke opløses, vises hele værdien som bogens tekst.
- **Flertydig i teksten:** bogen skriver også »s.d.«/»s.m.« om en dato tidligere i samme tekst (»bisat … s.å. og
  begravet s.d.« = bisættelsens dag). Giver den læsning et andet resultat end fødslen/døden, opløses intet. Rammer 1.
- **Forkortelser er ikke datoer:** initialer og forkortelseskæder (»i S. M. Kirke«, »R.S.A.O.«, »K.S.D.«, »S.D.-kors«,
  »p.s.d.«) regnes ikke som relative. 1939's »15 s. M.« (lille s) gør. Rammer 0 på stand-in'en, og formerne
  »s. Aa.«/»samme Aar« forekommer 0 gange blandt offentlige påstande.
- **Før referencen:** en dåb, der opløst ville ligge før fødslen (eller en begravelse før døden), opløses ikke.
  Rammer 1.

Kontrol af de 313 opløste værdier (kun antal): 0 ugyldige datoer (fx 31. april), 0 før referencen. 5 værdier
nævner flere datoer, alle forskellige hændelser i bogens tekst (bisat/begravet, hjemmedøbt/fremstillet, senere
bisat).

**Review-rettelsen (2026-11-12), før → efter:**

- Opløst/ikke opløst: 312/52 → 313/51. 1 dåb og 1 begravelse opløses nu (pr. del i stedet for hele værdien), og
  1 begravelse opløses ikke længere (skråstreg i dødsdatoen).
- Noterne er uændrede: ✓/skriver/»Kun i« og de 927 par er de samme.
- 3 visninger (komponent × udgave) viser en kortere værdi, fordi en dato ikke længere står to gange. I runde 1 var
  det 38 med reglen »står i teksten«; afgørelse 13 begrænser den til »slutter med«.
- Runde 2 (flere dage i referencen, år i parentes, »slutter med«) ændrer 0 noter og 0 opløsninger på stand-in'en.

## Vælger, etiketter og tab

- **Vælgerform pr. komponent:** `ingen` 258 · `chips` 459 · `skift` 261.
- **Etiketter:** 7.090 synlige kildeetiketter skannet (fakta-linjernes kilder, »andre udsagn« og vælgerens chips):
  0 med `record-`, 0 med `legacy-source:`.
- **Tabstjek:** hver ikke-tom linje i en anden udgaves visning er genfundet som »✓ også«, i en »skriver«-note eller
  under »Kun i« — undtagen 1 linje, en redaktøroprettet `overhoved`-markering uden udgavens egen kilde (vises kun i
  sin egen udgave; afgørelse 3 i forløbet).
- **Selvkonsistens:** 0 »✓ også«-noter uden en linje i den anden udgaves visning, som lighedsreglen kalder ens. Tjekket
  bruger samme regel som noterne og er **ikke bevis for, at intet ✓ er falsk** — kun projektejerens dom over arket er.

## De 17 redaktørpåstande (spec §5.1)

17 personfakta-påstande har en citation uden `source_id` (ekskl. `forældrefamilie`/`forældre_ukendt`):
11 valgte på offentlige rækker, 1 ikke-valgt på en offentlig række (`navn`) og 5 `overhoved` på rækker, læseren ikke
ser. De 11:

| Gruppe | Antal | Typer |
|---|---:|---|
| Udgavens egen (valgt påstand vist) | 8 | 6 navn, 1 død, 1 dåb (relativ, vist opløst) |
| Bøgernes ord vist (udgavens egen påstand i stedet) | 2 | 2 navn |
| Som i dag (ingen udgaveegen påstand) | 1 | 1 overhoved |

Afgørelsen bruger core: faktummets linje i personrækkens udgave viser enten en anden værdi end den valgte påstand
(»bøgernes ord«) eller den valgte (en relativ dato sammenlignes i core's opløste form); i sidste fald skelner en probe — en syntetisk tredje udgave med samme værdi —
mellem udgavens egen (linjen får »✓ også«) og »som i dag« (linjen indgår aldrig i noter).

**Kontrolkomponenten** (255, 392, 1198; kanonisk 392), valgt DAA 2018-20: to navnelinjer, begge med »DAA 1939
skriver: …«, den ene er 2018-20's egen påstand i stedet for redaktørens valg (spec §5.2's eksempel); fødsel og død »✓ også i DAA 1939«; titel
4 linjer, én med »✓ også«; ingen »Kun i«.

## Stikprøve

925 unikke »✓ også«-par (fødsel 320 · død 268 · navn 224 · titel 96 · dåb 12 · begravelse 5). 40 par trukket med
fast seed `6e1` (fødsel 13 · navn 11 · død 11 · titel 5), derefter 6 tillæg i samme blandede rækkefølge, så hver type
med ✓-par har mindst 3 (dåb 3 · begravelse 3; markeret »tillæg« i arket) — 46 par i alt, nummereret fortløbende.
Arket viser begge udgavers ord med udgave og side, sendes til projektejeren og ligger uden for repo'et.

Til projektejerens opmærksomhed: 5 af de 6 tillæg er relative datoer (»samme måned«-formen) med samme tekst i
begge udgaver. Teksten er ens, men datoen afhænger af det faktum, den henviser til (fødsel/død), i hver udgave.

**Dom:** Projektejeren 2026-11-12: alle 46 par korrekte → SLUKKET_ENIGHED tom.

**Efter 7b:** 927 unikke ✓-par (fødsel 320 · død 271 · navn 224 · titel 96 · dåb 12 · begravelse 4). Dommen gælder de
46 bedømte par: 45 er stadig ✓ (de 4 relative i nr. 43-46 nu på opløste datoer), nr. 42 er nu »skriver«. Ikke bedømt
er de 4 nye død-par (ledende tegn, se ovenfor) og de 10 dåb-/begravelsespar på opløste datoer, som ikke var i arket.
Genkørslen trækker et nyt ark med samme seed over de 927 par; det er ikke bedømt.

**Nye par til bedømmelse:** et eget ark uden for repo'et (`6e1-nye-par.html`) indeholder netop de 14 ✓-par, der er nye
eller hviler på en ændret værdi siden dommen:

- 4 nye død-par;
- 9 dåbs- og 1 begravelsespar på opløste datoer, med bogens oprindelige tekst og fødslen/døden, opløsningen bygger på,
  for begge udgaver.

Udeladt er 153 par, hvis værdi kun har mistet et ledende tegn (samme værdi efter lighedsreglen). Til orientering
viser arket også nr. 42 (nu »skriver«) og nr. 43-46 (bedømt på bogens tekst, nu opløst og stadig ✓).
