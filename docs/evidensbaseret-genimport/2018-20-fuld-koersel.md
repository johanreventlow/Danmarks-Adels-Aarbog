# Hele 2018-20 gennem fortolkningskæden (#147)

Beslutning: `docs/decisions.md` 2026-10-01 (»ingen særskilt prod-overførsel af piloten«), 2026-10-02
(terra) og 2026-10-03 (titler og »til <gods>« i navne). Plan:
`docs/superpowers/plans/2026-10-01-trin4-2018-20-fuld-koersel.md`. Kørt 2026-10-01—03 i en lokal kopi af
et frisk prod-dump, aldrig i prod. Rapporten indeholder record-nøgler, tal og hashes — ingen klausultekst
og ingen claim-værdier.

## Kort svar

Alle 488 tilladte poster i 2018-20 er kørt gennem hele kæden i én base: **488/488 dækket, 3.739
forslag, 74 kort for projektejeren og 622 bindinger** uden kanonisk delta. Projektejeren afgjorde
**61 A, 0 R, 13 U**; stikprøven på 20 blev fuldt accepteret, så 602 forslag blev accepteret maskinelt.
Pilotens 34 poster kom tilbage fra cachen med **identiske** claims (230 af 230, også claim-id), og alle
46 af pilotens bindinger går igen blandt de 622.

Arket afslørede én systematisk fejl i modellens navne: **12 af 22 navne-uoverensstemmelser har en titel
i værdien og én en godsbetegnelse.** Det er nu besluttet, at begge holdes ude af navnet (decisions
2026-10-03); de 13 er afgjort `U` og venter på næste promptversion.

**Dette er ikke klar til prod.** Overførslen kræver sin egen spec med den nøglede pakke, og
omsegmenteringens fortrydelsesvindue står åbent, til den overførsels GO er givet.

## Grundlag

| | |
| --- | --- |
| Prod-dump (læse-kun) | `9844dae3036ca15e55aa46c12f5f01232dd5da5de0b04ca474d55bdd0de49076` (2026-10-01 13:30 UTC); tilstand `591\|984\|591\|1\|0\|0\|1`; kanonisk md5 `3dfdc1ef…` |
| Arbejdsbase | `daa2018f_20261001133125` (restore af dumpet + `db-migrations.sql`/`db-rls.sql`) |
| Ledger | `e620073c…` — 591 records, **488 `eligible`** / 103 `excluded` (principal 47, relative 56, spouse 68, text 2) |
| Udvalg | `eligible-all-v1` (#228), strata `1aed8eff…`; 488 poster i 20 bundter |
| Runner-input | `0b51ed9aeef8993d82a8eabef5c961a2f234201d7118216395d3ca653ccf8bab` (591 records, 787 klausuler) |
| Kontrakt | profil `daa-2018-20-v2` 1.4.0, prompt `d46cda80…`, skema `904c903c…`, model `gpt-5.6-terra`, `runner_code_sha256` `2c411820…`, codex-cli 0.155.1 |
| Pre-run-manifest (GO) | `f5a76e1b6e42ee7fbd6693d4b5c7781e5dcb172382b4473fef14972a118fc4bd` |
| Forslagsmanifest | indhold `80f3e5c1e3f16058ce7292e2ce8258239c4efee897a8299aa6630cf52064e3e5` (fil `a5aa8e67…`) |
| Klassifikation | `ded0de56…` |
| Stikprøve (seed `kontrolmodel-v1`, 20) | `3b499103f963219eb8a9d99a47aa868bc24b8b71e8f092d2ca88e6ea166d5724` — noteret før arket blev bygget |
| Menneskets rækkefil / maskinplan | `4d12c6a88f84c541ecac38798492e825172ac9fe8addda892712977b35352c56` / `18b96d8a…` |
| Ark før afgørelse | `ed6083ca…` (74 kort, 4 forudfyldt) |
| Godkendt ark | `25d47d5bc0dbdb208ea64f59d4fd633ad22f1c0be4dfad6e19f600738521c22e` (projektejeren 2026-10-03) |
| Bindingsbatch | `66e4d11d-9b7c-484f-9bc0-3d35705d529c` |

## Kørslen

1. **Modelkald** (Task 1): 20 bundter fra manifest `f5a76e1b…`. **488/488 dækket** (346 hele, 142
   delvise), 3.758 gyldige claims, 203 afviste. 10 poster gav 0 claims (I-29, I-30, I-35, I-41b, II-22,
   III-104, III-129, III-29, III-45, V-15) — korte poster og henvisninger, som i piloten. Ingen post
   endte med en fejl; `tool_use` optrådte ikke i noget forsøg.
   - **Genkørsler:** bundt_06 ×1 (II-26), bundt_08 ×2 (III-21), bundt_09 ×1 (III-52) — alle
     `validation_failed` på én post, som gik igennem ved næste forsøg; bundt_18 ×3 (V-61—V-64,
     `unknown`), se fund 4. Et reservemanifest uden III-21 (`d3adc653…`, planens STOP-regel for
     vedvarende `BATCH_PENDING`) blev bygget, men ikke brugt.
   - **Forbrug:** 365 nye kald: 6.226.916 input-tokens (heraf 4.163.840 fra cache), 274.291
     output-tokens (98.405 tænkning). 123 poster kom fra runnerens cache (pilotens 34 og poster, der var
     gennemført i et tidligere forsøg af et genkørt bundt): deres oprindelige forbrug var 2.088.544
     input-tokens.
2. **Ingest** (Task 2): regnskabet 3.961 rå − 203 kontrakt − 18 H1 − 0 dubletter − 0 ukendt rolle − 1
   principal uden persona = **3.739** (2.767 om hovedpersonen, 972 om andre) i 478 elementer.
   Forventningen blev skrevet før kørslen og ramt på alle tal: 478 hændelser, 566 citerede klausuler (390
   `afventer_identitet`, 176 `fortolkning_foreslaaet`), kanonisk delta 0. Dry-run før apply.
   `db-verify.sql` på en engangskopi: 121 OK. Det ene frasorterede claim er et `event.marriage` på II-35,
   en post uden persona (#229); postens 3 øvrige claims kom med.
3. **Kontrolmodellen** (Task 3): 1.276 promoverbare — **622 `MATCH`, 570 `SKRIVEMAADE`, 54
   `REAL_DIFF`, 30 `NO_FACT`**. Arket = 20 stikprøve + 54 uoverensstemmelser = **74 kort** (variant a:
   loft 80), udleveret som tre delfiler à 25/24/25. 4 kort var forudfyldt fra pilotens ark
   (`2500531c…`).
4. **Negativtest:** den maskinelle accept kørt før menneskets afgørelser ⇒ `SAMPLE_NOT_APPLIED`, 0
   skrevet.
5. **Skrivning:** 74 (`human-sheet-kontrol-v1`: 61 `accepted`, 13 `unresolved`), derefter 602
   (`machine-corroboration-v1`).
6. **Mængdekontrol og binding:** `CONTROL_TARGETS_OK 622`; 622 bundet i ét batch; `fact` 7.197 og
   `assertion` 9.306 og en hash over alle assertions uændrede; en ny målfinding giver 0 `MATCH` og 622
   `ALREADY_PROMOTED`.

**Regnskab:** 3.739 forslag = 622 bundet + 41 accepteret og ubundet + 13 `unresolved` + 3.063
`proposed`. De 41 er de accepterede uoverensstemmelser (9 `person.name`, 32 `person.title`); de står som
I-7 i kontrolmodel-kørslen — accepteret, ubundet, og kan ikke genåbnes via RPC'en. De 3.063 er
ikke-promoverbare prædikater (2.463), `SKRIVEMAADE` (570) og `NO_FACT` (30).

| Bindinger pr. prædikat | |
| --- | ---: |
| `person.name` | 241 |
| `person.title` | 226 |
| `person.death` | 88 |
| `person.birth` | 67 |
| **I alt** | **622** |

## Sammenligning med piloten

| | Pilot 28/9 (34 poster) | Nu (488 poster) |
| --- | ---: | ---: |
| Forslag | 230 | 3.739 |
| `MATCH` / `REAL_DIFF` / `SKRIVEMAADE` / `NO_FACT` | 46 / 4 / 16 / 3 | 622 / 54 / 570 / 30 |
| Kort for mennesket | 24 | 74 |
| Afgørelser på kortene | 24 A | 61 A / 13 U |
| Maskinelt accepteret | 26 | 602 |
| Bindinger | 46 | 622 |

**Pilotens 34 poster er identiske.** De 32, der gav claims, har de samme 230 claims (prædikat, værdi,
konfidens, citerede klausuler, rolle og claim-id; hash `f78607ba…` i begge), og alle 46 bindinger fra
`daa44g_20260928170311` går igen, på samme (post, prædikat, mål-assertion). Cachen ramte; prod kan
få netop disse forslag.

Andelen af uoverensstemmelser er faldet fra 4 af 69 promoverbare i piloten til 54 af 1.276, men
`SKRIVEMAADE` er steget fra 16 til 570 (45 %). Det er den største rest: forslag, der sandsynligvis er
rigtige, men hverken set af et menneske eller bundet, fordi en normaliseringsregel ikke er besluttet.

## Fund

**1. Titler og godser i navne.** 12 af de 22 `person.name`-uoverensstemmelser har en titel i værdien
(»greve«, »komtesse«, »friherreinde«): III-58, IV-41, IV-42, IV-49, IV-53, V-5, V-18, V-38, V-51,
V-74, V-80, V-143. III-15 har en godsbetegnelse (»til …«). Prompten siger ikke, at titler holdes ude af
navnet. Ingen af de 241 `MATCH`-navne har titelord, så fejlen er fanget, ikke bundet. Afgjort `U`
(decisions 2026-10-03); reglen venter på næste promptversion sammen med »var †«-reglen.
**Databasen selv har 138 navne-assertions med titelord** fra tidligere indlæsninger — egen oprydning.

**2. Et overset ejerskab.** III-15's gods findes kun i navneforslaget: intet `person.estate`-forslag og
intet faktum. Det er ikke tabt — narrativet bærer det — men det er et udsagn, modellen burde have
fundet.

**3. En krydshenvisning, der er håndteret.** III-58 er en »se V. …«-henvisning. Postens hovedperson
(person 255) har allerede `samme_som` til V-1 (person 392), så den er ikke en dublet. Det er det eneste
henvisningskort i arket.

**4. Runneren kender ikke codex' nye kvotefejl.** bundt_18's fire fejl (V-61—V-64) var en opbrugt
kvote, ikke et nedbrud: codex svarer nu med `turn.failed` uden `error.type` og teksten »You've hit your
usage limit«. `classify_failure` klassificerer det som `unknown`, så `STOP` for `quota_exhausted`
udløses ikke, og bundtet blev forsøgt tre gange forgæves. Rettelsen ændrer runnerens kode og dermed
manifestet; den hører til næste kørsel.

**5. Delfilerne kunne ikke sættes sammen byte for byte.** Planen siger `cat` af delfilerne. HTML-fladens
eksport skriver sin egen overskrift (»del X af 3«; del 2 og 3 fik fire nye linjer), så de udfyldte filer
var ikke længere skiver af originalarket. De 74 D-linjer blev i stedet flettet ind i originalarket
`ed6083ca…`, efter at det var kontrolleret, at alt andet end overskriften var identisk, og at id og
version stod i samme rækkefølge. Enten skal eksporten bevare originalens overskrift, eller også skal
planen sige »flet D-linjerne«.

**Hvad kørslen ikke beviser:** præcision på de 3.063 forslag, der ikke er afgjort — især de 570
`SKRIVEMAADE`. Stikprøven dækker nu 20 af 622 (piloten: 20 af 46). Forbeholdet fra kontrolmodellen står
ved magt: en fejl, som model og database deler, fanges kun, hvis den er i stikprøven.

## Privatliv

Under målingen af fund 1 blev fire navneord fra claim-værdier (fra linjerne I—III, historiske personer)
skrevet i en chat-session, i strid med reglen om kun tal og hashes. Resten af målingen viste kun tal og
record-nøgler. Ingen kildetekst i repoet. Private artefakter: `~/.private/2018-20-fuld/` (0600),
herunder arket før U-rettelsen (`AFGØR-fuld-udfyldt.alle-A.txt`).

## Backlog

- Navneregel i prompten (titel og »til <gods>« ude af navnet), sammen med »var †«-reglen — kræver ny
  promptversion (kontraktfrys).
- Oprydning af de 138 navne-assertions med titelord i databasen.
- `classify_failure` skal kende codex' nye kvotefejl (nyt manifest).
- `compare_interpretation_proposal_projection.py` afviser manifester i current-tilstand (eksakte
  `PROVENANCE_KEYS`/`REGNSKAB_KEYS`) — hører til overførsels-spec'en.
- HTML-fladens eksport: bevar originalens overskrift; hjælpeteksten peger stadig på
  `~/.private/45-pilot/` (`decision_sheet_html.js:127`).
- Normaliseringsregel for `SKRIVEMAADE` (570 forslag).

## Oprydning (ikke udført — måles og forelægges først)

- `daa44g_20260928170311` — bevaret til den bortfaldne pilot-overførsel; dens 46 bindinger er nu
  reproduceret i arbejdsbasen.
- Engangskopien `daa2018f_verify_20261002112131` er allerede slettet efter `db-verify`.
- Den lokale PostgreSQL har mange ældre test- og rehearsal-baser (`daa153_*`, `daa1939_*`,
  `daa44_rehearsal_*`, `daa_omseg_*` m.fl.).

## Næste

Spec for den samlede prod-overførsel med den nøglede pakke: de 3.739 forslag fra cachen, de 676
afgørelser og de 622 bindinger. Omsegmenteringens fortrydelsesvindue lukker ved den overførsels GO.
