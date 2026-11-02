# Trin 6c-1: runneren på 1939 og 1939's identiteter — design

**Status:** GODKENDT af projektejeren 2026-11-01, efter Codex-runden på spec+plan (§10: NO-GO, 11 fund, afvejet og
indarbejdet). §8 pkt. 1 og 2 afgjort samme dag: (a) og (a). Udførelse: subagent-drevet efter planen.
**Tillæg 2026-11-02 (retning 2):** øvelsen af C gav 550 kort; projektejeren valgte retning 2 (§4.8), som afgør §8
pkt. 3 og 4 og ændrer 6b §4.3 pkt. 3-6 for 1939's C. A og B er i prod 2026-11-02.
Projektejeren besluttede 2026-11-01 at dele 6c i to med identiteterne først og bad om bedste skøn uden afklarende
spørgsmål. Valg, der ikke står i den overordnede spec, er markeret *mit valg*. Afgørelserne til projektejeren står i §8.
**Gren:** `docs/trin6c1-spec` fra `main` (`f928b1de`).
**Overordnet spec:** `docs/superpowers/specs/2026-10-29-trin6-1939-gennem-kaeden-design.md` (§5 6c, §6 pkt. 1 og 6).
**Delspec 6b:** `docs/superpowers/specs/2026-10-31-trin6b-identitet-design.md` (§4.3, §5 »6c's forudsætninger«, §6 C).
**Review-budget (B13):** 1 Codex-runde på spec+plan (`gpt-6.1-sol`, Opus dømmer), 1 på diffen før prod. Delingen af 6c
giver 6c-2 sit eget budget (`docs/decisions.md` 2026-11-01).
**Grundlag:** trin 4's fulde kørsel af 2018-20 (`docs/evidensbaseret-genimport/2018-20-fuld-koersel.md`), overførslen
(`2026-10-03-trin4-2018-20-prod-overfoersel-design.md`), review 35 P1 (sandbox), `udestaaende-raa.md` pkt. 38, 40, 42,
54, 57; 6b-ledgeren (`~/.private/6b/sdd-ledger/progress.md`: de punkter, der er parkeret til Task 15).

## 1. Roadmap-kobling

1. **Roadmapmål:** trin 6, færdigbevis (a): 1939's fortolkning og identitet går gennem samme runner, writer og
   identitetsvej som 2018-20's.
2. **Værdikædeled:** extractor-runner og proposed-ingest (trin 4's første halvdel) for 1939; derefter 6b's ceremoni C
   (identitet, målarkitekturens gate 5).
3. **Leverancetype:** generelle rettelser (forslagswriteren følger 6a's helpost-regel; eksporterne kobler persona
   gennem den primære mention; runnerens kvotefejl), én 1939-udgaveprofil (prompt, model, eligibility-politik) og to
   ceremonier. Ingen editionsnavngiven permanent overflade.
4. **Værdi:** 1939's ~500 tilladte poster får forslag (navn, datoer, titler, relationer) i evidenslaget, og 1939's
   personas får en identitet. Det er forudsætningen for 6c-2, hvor bindingerne gør 1939-fakta synlige for læseren.
5. **Færdigbevis:** §7.
6. **Erstatter:** at 1939's eneste maskinelle udtræk er den gamle v50-indlæsning; at 1939's identitet kun bæres af
   C3's postbinding.

## 2. Målt udgangspunkt

Stand-in `daa5ab_ddl_standin_20261101101631_6bm` (= prod efter 6b's B, tilstand `b`), kun antal, 2026-11-01. Tallene
genmåles mod prod i ceremoniernes `maal`.

### 2.1 Personas og poster

| | Antal |
|---|---|
| Kilde 3-personas | 563 (555 fra 6b-B + 8 fra v50), alle med published binding gennem `publication_persona_binding` |
| — bindingspersonen `staged` | 2 (`levende`/`privat` er `false` for alle 563) |
| Fortolkninger for kilde 3 | 0 |
| Helposter med flere forankringer | 235 af 584 (6b §2.1) |

### 2.2 Hvad der ikke virker for 1939 i dag

1. **Forslagswriteren** (`private.write_interpretation_proposal`, `schema.sql:5002-5008`) kræver præcis én accepteret
   forankring og én topobservation. 235 af 1939's helposter afvises (`REIMPORT_WRITER_CLAUSE_FOREIGN_POST`). Personaen
   findes allerede gennem den primære mention (`:5051-5055`); kun forankringskravet er forkert.
2. **Runner-inputtet** (`export_43b_runner_input.R`) kobler personaen på `persona_key = record_key` (`:59-66`). 6b's
   nøgle er `'1939:' || record_key`, så alle 555 får tom `persona_id`, og preflighten afviser hvert `person.*`-claim.
   Poster med flere forankringer giver flere rækker pr. `record_key`, og `records[[key]]` beholder den sidste
   (`:88-103`): teksten afhænger af rækkefølgen.
3. **Eligibility-ledgeren** (`export_model_eligibility.R`) finder hovedpersonen gennem
   `person_external_id.record_key = source_record.record_key`. For 1939 matcher 8 (6b §2.2); de øvrige får
   `COALESCE(principal.hit, TRUE)` og udelukkes. Tekstfilteret (`f.` + år ≥ 1950) rammer 0 poster i 1939.
4. **Runneren** klassificerer codex' kvotefejl (`turn.failed` uden `error.type`) som `unknown`
   (`evidence_runner.py:450-460`), så kvotestoppet ikke udløses (pkt. 42; 2018-20's bundt_18 blev forsøgt 3 gange).
5. **Profilen** `daa-1939-v1` har `prompt_file: null`. Prompten `evidence-extract-prompt-1.0.0.md` har hverken
   navnereglen (titel og »til <gods>« ude af navnet, decisions 2026-10-03) eller »var †[dato], da …«-reglen (pkt. 38).
6. **Sandbox-grænsen** blev tunet og bevist på codex-cli 0.155.1 (`runner-gate.sb.template:93`); installeret er nu
   ≥ 0.164. Review 35 P1's retning (1), (3), (4) og (5) er gennemført (`tool_use`-afvisning, spærrede stier og begge
   veje til Postgres, version i manifestet, adgangstest med psql). (2) `scram-sha-256` er ikke: den lokale Postgres kører
   stadig `trust`; den er i dag kun ufarlig, fordi profilen spærrer netværket til den.

### 2.3 Eligibility for 1939 (målt med en prøveregel)

Hovedperson gennem `publication_persona_binding`, slægtninge gennem `family_member` på kilde 3-rækken og på dens
afklarede `samme_som`-partnere:

| Regel | Poster ramt |
|---|---|
| hovedpersonen `levende`/`privat` ≠ `false` eller `staged` | 2 |
| en `samme_som`-partner `levende`/`privat` ≠ `false` | 3 |
| en slægtning (direkte eller gennem partneren) `levende` ≠ `false` | 11 |
| tekst: et årstal ≥ 1915 et vilkårligt sted i posten | 60 |
| tekst (alternativ): et årstal ≥ 1915 højst 25 tegn efter `f.`, `født` eller `*` | 22 |
| **udelukket i alt / tilladt** (streng tekstregel) | **63 / 500** |
| udelukket i alt / tilladt (alternativ tekstregel) | 28 / 535 |

155 af de 563 har hverken en dateret dødspåstand på kilde 3-rækken eller et `†` i posten; 41 af dem nævner et årstal
≥ 1890. 1939's ældste generationer skriver årstal fra 1600-tallet, og 147 poster har intet årstal 1600-1999.

## 3. Afgrænsning

**I 6c-1:** runnerhygiejne (§4.1), prompt og profil (§4.2), eligibility (§4.3), runner-input og forslagswriter (§4.4),
pilot og fuld kørsel (§4.5), forslagene i prod (§4.6), 6b's ceremoni C med de parkerede punkter (§4.7).

**Ikke i 6c-1 (→ 6c-2):** kontrolmodellen på 1939's forslag, rettelsesvejen, bindinger, vej B, A6b-resten for
2018-20's 10 poster, en normaliseringsregel for `SKRIVEMAADE`. **Alle 1939-forslag står `proposed` efter 6c-1.**
Intet kanonisk delta; intet nyt for `anon`.

**Ikke i trin 6:** 2018-20's 13 `U`-kort og de 138 navne-assertions med titelord (pkt. 39-40); en genkørsel af 2018-20
med den nye prompt (A6b-restens 10 poster afgøres i 6c-2).

## 4. Design

### 4.1 Runnerhygiejne (før ethvert modelkald)

1. `classify_failure` kender codex' kvotefejl: `turn.failed` uden `error.type` og med en kendt kvotetekst →
   `quota_exhausted`. Ukendte fejl forbliver `unknown`. Fixture fra 2018-20's bundt_18 (kun fejlteksten, ingen
   kildetekst).
2. `gate-access-test.sh` og kanarien køres på den installerede codex-cli. Fejler et kald, tilføjes kun den sti, der
   er målt nødvendig (templatens egen regel). Versionen bindes i manifestet, som i dag.
3. `trust` → `scram-sha-256` er projektejerens valg før piloten (§8 pkt. 2). Min anbefaling er at beholde `trust` i
   6c-1: profilen spærrer socket og TCP til Postgres, og adgangstesten beviser det før hvert rigtigt kald; skiftet
   ville ændre adgangen for alle lokale scripts og ceremonier midt i trin 6.
4. `~/.codex/auth.json` forbliver læsbar for modellen (kendt restpunkt siden 2026-09-11); ingen ændring.

### 4.2 Prompt 1.1.0 og profilen `daa-1939-v2`

1. **Prompt `evidence-extract-prompt-1.1.0.md`:** 1.0.0 plus de to besluttede regler: titler og »til <gods>« holdes ude
   af `person.name` (de bærer `person.title` og ejerskab); »var †[dato], da …« siger kun, at personen senest
   da var død (en grænse, ikke dødsdagen; kontrolmodel-kørslen 2018-20, I-7 og I-11), og giver derfor intet
   `person.death`-claim (datoer gengives ordret, så grænsen kan ikke udtrykkes i værdien). Rettet 2026-11-01 under Task 3:
   udkastet sagde »dødsdato for den nævnte«. Ingen 1939-specifik tekst i prompten. Prompten er udgaveneutral; 2018-20's profil peger fortsat på
   1.0.0.
2. **Profilen `daa-1939-v2`** (ny version, `daa-1939-v1` bevares): prompt 1.1.0 med sha, model, skemaer som 2018-20.
3. *Mit valg:* modellen er `gpt-5.6-terra`, samme som 2018-20's målte kørsel. Prompten ændres alligevel, men et
   modelskift ville give to ukendte på én gang. Findes modellen ikke længere i codex' modelcache ved kørslen, stopper
   planen og tager valget op.
4. **Kontraktfrys:** S4-spærren (`schema.sql:5020-5040`) tillader nye forslag på en post kun efter en
   kildetekst-revision. Den prompt og model, 6c-1 ingester med i prod, er dem, 1939 lever med. Derfor piloten (§4.5).

### 4.3 Eligibility: politikken `exclusion-1939-v1`

`export_model_eligibility.R` får en politik pr. udgave (`--policy`), så 2018-20's `exclusion-2018-20-v1` er
byte-uændret (regressionstest på dens ledger-hash i en stand-in).

Politikken `exclusion-1939-v1` (*mit valg* af form) udelukker en post, hvis mindst én af disse gælder:

1. posten har ingen persona med en published binding (`publication_persona_binding`), eller bindingspersonen er
   `levende`/`privat` ≠ `false` eller `staged`;
2. en afklaret `samme_som`-partner til bindingspersonen er `levende`/`privat` ≠ `false`;
3. en person i en family med bindingspersonen eller med en af dens partnere er `levende` ≠ `false`;
4. **tekst:** et årstal ≥ 1915 står et vilkårligt sted i helpostens gældende tekst. Årstallet læses OCR-tolerant:
   et firetegnsord, der begynder med `1` eller `l`/`I` og ellers kun består af cifre og de typiske OCR-forvekslinger
   (`O`, `o`, `S`, `B`, `l`, `I`), tolkes med forvekslingerne rettet. Reglen er foreningen af den tolerante læsning og
   den strenge (`1[6-9][0-9]{2}` hvor som helst, også klistret til et ord). Målt på `_6bm`: den tolerante tilføjer 0
   poster, og den strenge alene finder 60; foreningen beholder begge, så en ny OCR-variant ikke er afhængig af én af dem.

*Mit valg* af tekstregel: den strenge (63 udelukket, 500 tilladt), ikke den smalle (28/535). En person født 1915 er 111
år i dag; en slægtning, der kun står i prosaen, findes ikke som person, og hverken `levende` eller en dødspåstand kan
frikende den. Den smalle regel misser år, der står efter et navn eller en titel. Reglen er fail-closed og rejser tvivl,
den afgør den ikke. Følgen for C står i §4.7 pkt. 4 og §8 pkt. 4.

**Hvad reglerne ikke kan bevise (Codex fund 1).** Ingen af reglerne frikender en person, som kun står i prosaen uden
årstal. Argumentet for, at tekstreglen alligevel dækker: DAA nævner en person i en stamtavle med fødselsdato
(»f. …«) eller som afdød, og den eneste gruppe, der kan leve i dag, er født 1915 eller senere; deres årstal står i
posten. Restrisikoen er en person nævnt uden dato eller med et årstal, OCR'en har ødelagt ud over den tolerante
læsning. Samme risikoklasse blev accepteret for 2018-20's 488 poster med en svagere tekstregel (`f.` + år ≥ 1950).
Positiv frikendelse af hver personomtale kræver navneudtræk, dvs. netop det modelkald, gaten skal beskytte; det er
fravalgt. Restrisikoen forelægges projektejeren (§8 pkt. 1).

Ledgeren har samme form som 2018-20's: én række pr. record, `eligible` eller `excluded` med alle årsager, ingen tekst,
ingen navne, regelfilens sha. Fravær er ikke tilladelse. Årsagskoderne er politikkens egne; Python-forbrugerne
(`evidence_runner.load_ledger` og udvalgsscripts) validerer dem pr. politik (Codex fund 5).

### 4.4 Runner-input og forslagswriter

1. **Runner-inputtet** vælger helposten med `private.record_helpost_observation` og udgavens helpost-slags fra
   writerprofilen (`private.writer_config_helpost_kind`: `person` for 1939, standard `person_post` for 2018-20; Codex
   fund 2), samme regel som klausul-writeren og personaen gennem helpostens primære mention. En post uden præcis én helpost eller
   uden præcis én primær persona afvises ved eksporten med en kode, ikke ved preflighten. Eligibility-ledgerens
   `input_sha` bruger samme helpost, så de to fortsat følges ad.
2. **Forslagswriteren** (`write_interpretation_proposal`) vælger helposten med samme regel og batchprofilens
   helpost-slags i stedet for »præcis én forankring«. 1939 får sin egen writerprofil
   `daa-1939-interpretation-proposal-v1` (kilde 3, `helpost_observation_kind` `person`, ellers som
   `daa-2018-20-interpretation-proposal-v1`'s `writer_config`), seedet i `schema.sql`/`db-migrations.sql` og som fil
   under `references/reimport-profiles/` med denylist og rollekort (Codex fund 4). Alt andet er uændret: personaen gennem den primære mention, S4-spærren, kvitteringen, nøglen
   (`private.interpretation_proposal_key`) og klausulregnskabet. For 2018-20's poster (én forankring) er udfaldet
   identisk; det bevises på en 2018-20-genafspilning i CI.
3. DDL'en er additiv i virkning (en funktion erstattes, en profilrække tilføjes) og går i prod som ceremoni A (§6).
4. **Kilde og kode bindes** (Codex fund 3 og 8): runner-manifestet bærer `source_id` fra runner-inputtet, og
   forslagsmanifestet kræver det (ingen standardværdi for nye manifester; historiske 2018-20-manifester genbygges som
   i dag). Nye kørsler (kontrakt `evidence-runner-1.4`) kræver `runner_code_sha256` i manifestet; et manglende felt er
   en fejl. Kontrakt 1.3 forbliver registreret, så 2018-20's cache kan læses (fund 6).

### 4.5 Pilot og fuld kørsel (lokalt, aldrig mod prod)

Modelkaldene kører på en maskine med en stand-in restoret fra A-dumpet (§6) og kun på `eligible` poster. Svarene
caches pr. record (runnerens cache), så den fulde kørsel genbruger pilotens svar.

1. **Pilot, *mit valg*:** 30 poster, trukket deterministisk (seed i manifestet) og stratificeret på postlængde og
   forankringsantal, af samme udvalgsscript som den fulde kørsel (`build_eligible_selection.py` med `--limit` og
   `--seed`), så alle 30 ligger i bundter, og bundterne dækker præcis udvalget (Codex fund 7). Gate før den fulde kørsel, kun tal: dækning (0 fejlede poster efter genforsøg), andel afviste
   claims højst som 2018-20's (203 af 3.961 rå), 0 `tool_use`, andel `person.name` med titelord 0, og et
   forslagsregnskab, der går op (rå − afviste − H1 − dubletter = skrevne). Ingen menneskelig læsning af claims:
   præcisionen måles af kontrollen i C (§4.7) og af kontrolmodellen i 6c-2. Fejler gaten, stopper planen, og
   prompt eller profil rettes, før noget er ingestet nogen steder.
2. **Fuld kørsel:** alle `eligible` poster i bundter som 2018-20's. Kvotestop er et stop, ikke et forsøg. Et bundt
   med vedvarende fejl på én post: posten udelades med et reservemanifest (2018-20's STOP-regel) og tælles.
3. **Ingest i stand-in'en:** forslagsmanifestet bygges af `build_43b_proposal_manifest.py` fra cachen; dry-run, så
   apply gennem R-gatewayen med `expected_counts`. Forventningen skrives før kørslen. `db-verify.sql` på en engangskopi.
   Tal pr. prædikat og rolle, citerede klausuler (`fortolkning_foreslaaet`/`afventer_identitet`), kanonisk delta 0.

### 4.6 Forslagene i prod (ceremoni B)

Samme manifest som stand-in'en (`interpretation_key` er deterministisk, nøglematerialet indeholder ingen id'er), skrevet
med den generelle writer gennem R-gatewayen. Før skrivningen i samme transaktion: eligibility-ledgeren og
klausulsættets hash genberegnes mod prod og skal være lig manifestets (prod kan have ændret `levende` eller en
kildetekst efter dumpet). Efter: et nøglet forslagsdigest (`interpretation_transfer_digests.sql`'s forslagsdel) lig
stand-in'ens. Runneren nægter at skrive, hvis en 6b-fortrydelse er i gang (`~/.private/…/fortryd-b-*.igang`, 6b-ledgeren).

**To minutter pr. statement (Codex fund 9).** Gatewayen kører hele batchen i én transaktion: autorisation, ét kald pr.
post, finalize og digest er hver sit statement. Øvelsen måler maksimum pr. statement for hver af dem og omregner med
27×. Er et anslået over 60 s, deles B i flere batches (hver med egen autorisation og finalize, samme manifest
opdelt deterministisk) før GO.

### 4.7 6b's ceremoni C (6b-planens Task 15-16)

C kører som designet i 6b §4.3 og §6, når B er i prod. 6c-1 lukker de punkter, 6b parkerede til Task 15:

1. `red_publication_control` optimeres, så kontrollen af 561 personas holder sig klart under 2 min i prod. Måles på
   stand-in og omregnes med den målte faktor for mange små kald (27×, `database-current-state.md` §18), ikke 55×.
2. 6b-reviewets I4: de fire sætninger, der ikke var målt mod 2 min, måles på stand-in og omregnes som pkt. 1.
3. `publication_identity_sheet.py manifest` kræver `--details` (6B-03); runbook og plan bruger det.
4. **Poster uden forslag:** de 61 ikke-staged personas, hvis post er `excluded`, får ingen `person.name`-fortolkning.
   Generatoren falder tilbage på den primære mentions tekst (hele posten) og giver dem typisk `ingen kandidat` eller
   `svag`: de bliver kort. *Mit valg:* de går på arket som alle andre. Kortet viser bindingens person og postreferencen
   (6b §4.3 pkt. 5); mennesket afgør dem uden model. Kortantallet måles i øvelsen; stopreglen over 90 (6b §4.3 pkt. 6)
   gælder, og overskrides den, forelægges tallet (§8 pkt. 4).
5. Task 12's `OUTCOME_MISSING` for eksisterende personas med null-udfald afklares i øvelsen (fail-closed i dag).
6. Kalibreringens andet ben (6b §4.3 pkt. 7) køres på stand-in'en efter forslagsingesten.
7. **Partnerreglen** (6b-reviewets I3, spec »højere«, kode `≥`) afgøres af projektejeren efter kortmålingen (§8 pkt. 3).

### 4.8 Tillæg 2026-11-02: retning 2 for C (C3-bindingen er identiteten)

**Hvorfor.** Øvelsen af C som designet i 6b §4.3 gav 550 kort mod et loft på 90 (plan Task 9). Årsagerne er målt:
191 `svag/partner_hoejere` er bindingspersonens egen `samme_som`-partner fra 2018-20 (det forventede tilfælde), og 164
personas har intet navneforslag (61 fra `excluded` poster). Prompten er ikke årsagen (navnedækning 82 % mod 2018-20's
55 %). Projektejeren valgte 2026-11-01 retning 2 blandt tre: C3's publicerede binding bliver identiteten, og generatoren
bruges kun til at finde konkurrenter.

**Målt på stand-in'en `…_t9a` (kandidatkørslen fra øvelsen, kun antal), 561 ikke-staged personas:**

| Udfald (6b-klassifikator) | Antal | Konkurrent | Retning 2 |
|---|---|---|---|
| `enig` | 31 | — | automatisk |
| `svag/partner_hoejere` | 191 | egen `samme_som`-partner | automatisk |
| `svag/under_margin` | 18 | egen `samme_som`-partner i en anden række (alle 18 målt) | automatisk |
| `svag/under_auto` | 64 | — | automatisk |
| `ingen_kandidat` uden kandidatrækker | 153 | ingen | automatisk |
| `ingen_kandidat` med kandidatrækker, bindingspersonen fraværende | 45 (42 med navneforslag) | anden person, score < 0,7 (44) eller 0,7-0,9 (1) | **kort** (projektejeren 2026-11-02) |
| `navnefaelle` | 51 | anden person, lige score | kort |
| `uenig` | 8 | anden person, højere score | kort |

Kernens strukturkrav for oprindelsen `publication_binding` (`decide_source_persona_identity`: præcis ét
`person_external_id` for kilden på bindingspersonen, ingen anden persona med mention i helposten) holder for alle 561
(0 fejl begge veje). De blev før kun brugt på de enige.

**Regler (erstatter 6b §4.3 pkt. 3-6 for C):**

1. **Klassifikatoren:** findes der kandidatrækker for personaen, men er bindingspersonen ikke i nogen af dem, er udfaldet
   `uenig` med `reason='egen_ikke_kandidat'` (en anden person scorer højere end bindingspersonen, der ikke er med).
   `ingen_kandidat` betyder herefter kun: ingen kandidatrækker. De øvrige udfald og deres rækkefølge er uændrede.
2. **Automatisk på bindingen** (`enig`, `svag` med alle årsager, `ingen_kandidat`): identitet med oprindelsen
   `publication_binding`, `accepted`, uden svar. Evidensen bærer udfaldet som i dag (`outcome`), så 6c-2 kan finde dem,
   der ikke blev bekræftet af generatoren. Kernens strukturkrav er uændrede og er værnet.
3. **Kort** (`uenig` inkl. `egen_ikke_kandidat`, `navnefaelle`): S/F/U med oprindelsen `human` som i 6b §4.3 pkt. 5.
4. **Stikprøven:** 20 blinde kort trukket med 6b's hashnøgle blandt de automatiske (ikke længere kun de enige), dvs.
   overvejende `svag` og `ingen_kandidat`. Den prøver antagelsen »bindingen alene er rigtig«. Ét F eller U stopper C
   (`PUBLICATION_SAMPLE_FAILED`), før noget skrives. 20 af 20 rigtige udelukker ikke en fejlrate op til ca. 14 % (95 %).
   Stikprøvens S giver oprindelsen `publication_binding` som før.
5. **Kortloftet** hæves fra 90 til 125 (højst 30 pr. ark, dvs. 5 ark). Forventet: 8 + 45 + 51 + 20 = 124. Over 125
   stopper arket som før (`PUBLICATION_SHEET_TOO_MANY_CARDS`).
6. **De 61 personas fra `excluded` poster** (§4.7 pkt. 4) følger reglerne ovenfor: uden navneforslag giver de typisk
   `ingen_kandidat` og accepteres på C3-bindingen uden kort; giver klassifikatoren `uenig`/`navnefaelle`, får de kort.
   Ingen af deres tekst har været hos en model.
7. **§8 pkt. 3 og 4 er afgjort af retning 2:** partnerreglen (`≥`) bevares, men `svag` er automatisk, så den giver
   ingen kort; over-90-reglen erstattes af pkt. 5.

**Konsekvens for prod:** C får sin egen DDL-ceremoni (de ændrede funktioner) før dataceremonien. Retning 2 ændrer ingen
læsevej; den planlagte læse-kun-måling af `identity_candidate_input` i prod afgør stadig faktoren for C's tider (§6).

**Review-budget:** 6c-1's to B13-runder er brugt. Retning 2 får én ekstra Codex-runde på diffen (overskridelse noteret
i `docs/decisions.md`).

## 5. Følger

- `write_interpretation_proposal` ændres for alle udgaver; 2018-20's genafspilning skal give identiske nøgler og
  kvitteringer.
- `export_model_eligibility.R` og `export_43b_runner_input.R` får nye parametre. For 2018-20 er afgørelser, årsager
  og `input_sha` pr. record og runner-inputtet identiske (regressionstest); ledgerens `rules_script_sha256` ændres,
  fordi scriptet ændres, og det er forventet provenance (Codex fund 10).
- 6b's B kan ikke længere fortrydes, når B i 6c-1 har skrevet (fortolkningerne refererer personaerne og er
  append-only; 6b §6). Det står i runbooken.
- Når C er skrevet, venter 6c-2 på kontrolmodellen. 1939's forslag ses ikke af `anon` og ikke i webkøen
  (`proposed` er privat).

## 6. Prod

Tre ceremonier i 6a's form: dump med ekstern kopi (B1), kørsel fra projektejerens shell med `--jeg-mener-det` og GO,
`maal` før og efter, øvelse på en frisk stand-in med prods `statement_timeout` (2 min) før hvert GO.

| Ceremoni | Indhold | Fortrydelse |
|---|---|---|
| **A (DDL)** | `write_interpretation_proposal` med helpost-reglen; writerprofilen `daa-1939-interpretation-proposal-v1`; `red_publication_control` optimeret, hvis målingen kræver det | restore af A-dumpet i vinduet, som 6a/6b A |
| **B (data)** | ~500 posters forslag gennem writeren | restore af B-dumpet, så længe vinduet holder (ingen skrivning efter dumpet); forslag er append-only, så ingen writer kan slette dem |
| **C (data)** | 6b's ceremoni C (kandidater, ark, `publication_identity`) | 6b's `reversal` → `superseded`; C kan genkøres (decisions 2026-10-31) |

**De fire prod-spørgsmål** (memory `raad-upfront-og-prod-spoergsmaal`):

1. *Genspil:* modelkald én gang lokalt; svarene ligger i cachen og manifestet. Stand-in og prod får samme manifest.
2. *Tilfældige id'er:* `interpretation_id` er tilfældig og bruges ikke som nøgle i noget, der overføres. C's kandidater,
   kontrol, stikprøve og ark laves mod prod (personaerne er prods egne fra 6b-B). Øvelsesarket fra stand-in'en kan
   ikke genbruges i prod.
3. *Menneskelige godkendelser:* kun C's ark, bundet til prods kontroloutput og arkets hash (6b §4.3.1).
4. *DDL og fortrydelse:* tabellen ovenfor. B lukker 6b-B's fortrydelsesvindue (§5).

Skrivepause fra A-dumpet til B er skrevet. Tidsoverslag fra stand-in omregnes med 27× for writer-kald.

## 7. Færdigbevis

- Pilotgaten (§4.5 pkt. 1) bestået og rapporteret med tal.
- Ledger `exclusion-1939-v1` med antal `eligible`/`excluded` og årsager; ledger-hash i manifestet.
- Prod: forslag for alle `eligible` poster (eller et talt reservemanifest), digest lig stand-in'ens, kanonisk delta 0,
  2018-20's fortolkninger uændrede (hash).
- C finaliseret i prod: udfald pr. persona, stikprøve uden F/U, S/F/U-tal, `persona_awaiting_control` falsk for de 555.
- Tjekliste (overordnet §8 a): samme runner, writer, identitetsvej; ingen ny editionsnavngiven overflade.
- `status.md`: 1939 »Extractor-runner« og »Identitet (identiteter)« → `produktionsverificeret` med dato; »Forslag og
  afgørelse« → forslag i prod, afgørelse i 6c-2.

## 8. Afgørelser til projektejeren

**Før piloten** (afgjort af projektejeren 2026-11-01: pkt. 1 (a) og pkt. 2 (a), »som foreslået«):

1. **Restrisikoen i eligibility** (§4.3): en levende slægtning, der kun står i prosaen uden et årstal, som reglen kan
   finde, kan nå modellen. Valgene er (a) at acceptere restrisikoen som for 2018-20, (b) en strengere grænse (årstal
   ≥ 1900 et vilkårligt sted: 93 poster ramt i stedet for 60), eller (c) ingen modelkørsel for 1939 (så kan 6b's C ikke
   køres som designet). *Min anbefaling:* (a), fordi DAA's form giver levende personer et årstal, og (b) kun flytter
   grænsen uden at lukke hullet.
2. **Lokal Postgres med `trust`** (§4.1 pkt. 3; review 35 P1 (2), som reviewet bad om før næste modelkørsel): (a)
   behold `trust` med Seatbelt-profilens spærring af begge veje til Postgres og adgangstesten før hvert kald som
   værn, eller (b) skift til `scram-sha-256` med `~/.pgpass` før piloten; det berører alle lokale scripts, CI-lignende
   kørsler og ceremoniernes stand-ins. *Min anbefaling:* (a) i 6c-1, (b) som egen opgave efter trin 6. Argumentet for
   (a) er mit eget og sparer arbejde; det er derfor lagt frem her og ikke afgjort af mig.

**Efter øvelsen af C** (plan Task 9 stopper for dem, med tallene). *Afgjort 2026-11-02 af retning 2 (§4.8 pkt. 7).*

3. **Partnerreglen i C** (6b-review I3): når bindingspersonens egen `samme_som`-partner scorer *lige så højt* som den
   selv, er udfaldet i dag `svag` (kort). Specen sagde »højere«. Med »højere« bliver de sager `enig` (maskinelt).
   *Min anbefaling:* behold `≥` (kort), medmindre tallet presser arket over 90; lighed betyder, at generatoren ikke kan
   skelne de to rækker.
4. **Over 90 kort:** viser øvelsen mere end 90 kort, især på grund af de udelukkede poster (§4.7 pkt. 4), er valgene
   (a) flere ark (4 ark à ~30), (b) den smalle tekstregel (§4.3), som sender ~35 poster mere til modellen og giver
   færre kort, eller (c) at udelukkede poster står uafklarede uden kort til en senere runde. *Min anbefaling:* (a),
   fordi (b) sender tekst om mulige levende slægtninge til en model, og (c) efterlader personas uden identitet.

Alt andet i specen er mine valg og kan rettes ved godkendelsen.

## 9. Uden for scope

Se §3. Desuden: `trust` → `scram-sha-256` (§4.1 pkt. 3), `auth.json` (§4.1 pkt. 4), de 21 helposter uden binding og
de 8 uden helpost (ingen persona; opret-benet), de 2 staged (disposition som i 6b).

## 10. Reviewlog

### Codex-runde på spec+plan (2026-11-01, `gpt-6.1-sol`, B13-runden): NO-GO, 11 fund

Afvejning (Opus); fund 2-8 er bekræftet mod koden.

| # | Alvor | Fund | Afvejning | Indarbejdet |
|---|---|---|---|---|
| 1 | BLOCKER | Eligibility beviser ikke, at prosaen er fri for levende slægtninge | delvis: hullet er reelt, men positiv frikendelse kræver modelkald; tolerant årstalslæsning tilføjet, restrisiko til projektejeren | §4.3, §8 pkt. 1 |
| 2 | HIGH | Hardkodet `'person'` bryder 2018-20 (`person_post`) | nødvendig (`schema.sql:3540-3542`) | §4.4 pkt. 1-2; plan Task 1, 4 |
| 3 | HIGH | Forslagsmanifestet falder tilbage på kilde 1 | nødvendig (`build_43b_proposal_manifest.py:392`) | §4.4 pkt. 4; plan Task 2 |
| 4 | HIGH | Ingen 1939-writerprofil til forslag | nødvendig | §4.4 pkt. 2; plan Task 1 |
| 5 | HIGH | Nye årsagskoder afvises af `load_ledger` | nødvendig (`evidence_runner.py:716-721`) | §4.3; plan Task 5 |
| 6 | HIGH | Kontrakt 1.4 kan fjerne 1.3 fra cache-opslaget | nødvendig | §4.4 pkt. 4; plan Task 2 |
| 7 | HIGH | `build_43b_selection --count 30` bundter kun 10 | nødvendig (`build_43b_selection.py:135-136`) | §4.5 pkt. 1; plan Task 6 |
| 8 | HIGH | Standard-`--dagsvaerk` udelader runner-kodens sha | nødvendig (`build_43b_manifest.py:136`) | §4.4 pkt. 4; plan Task 2 |
| 9 | HIGH | Intet bevis for 2 min pr. statement i B | nødvendig | §4.6; plan Task 10 |
| 10 | MEDIUM | Byte-uændret 2018-20-ledger umulig (scriptets sha) | rettelse af formulering | §5; plan Task 5 |
| 11 | MEDIUM | `run-tests.R` kører ikke `tests/integration` | nødvendig | plan Task 4-5 (pg-job som `test-reimport-source-text-revision.R`) |

Codex bekræftede: writeren antager ikke andre steder én forankring; B → C følger 6b; S4 er forstået rigtigt.
