# Dagsværk 4.4 (#147) · proposed-ingest — rapport

**Kørt:** 2026-09-14/15 mod 4.3b's restore `daa43b_20260912192527`. **Ingen prod-mutation.**
Trin 4's migrationer er fortsat ikke kørt mod produktionsdatabasen.

Kun tal, hashes og record-nøgler. Ingen kildetekst og ingen claim-værdier — hverken her
eller i manifestet, som holder sig til nøgler, hashes og tal. Artefakterne ligger i
`~/.private/` (0700-mapper, 0600-filer) og committes aldrig.

**Hvad dagsværket flytter:** kæden fra prosa til struktureret påstand er hel for første
gang. 84 af 4.3b's claims står nu som `proposed` i databasen, bundet til de klausuler, de
citerer. Intet er promoveret, og intet kanonisk er rørt — afgørelsen er 4.5's.

## 1. Regnskabet

Planen forlangte fem tal. Der blev seks, fordi Task 5's `persona_role_map` er fail-closed
og derfor har sin egen afvisningsgrund.

| Led | Antal |
| --- | ---: |
| Rå claims i 4.3b's cache | **93** |
| − kontrakt-afviste | **7** |
| − H1-afviste (relation uden modpart) | **2** |
| − dubletter | **0** |
| − ukendt rolle (fail-closed) | **0** |
| = **ingestible** | **84** |

93 − 7 − 2 − 0 − 0 = 84. Builderen asserterer selv den ligning og rejser, hvis den ikke
går op.

**De 7 kontrakt-afviste er målt, ikke sluttet.** Task 0's måling 2 kunne ikke svare —
`afviste`-feltet kom ind i kørselsscriptet efter bundt 2, så IV-34's tal var aldrig gemt.
Task 4 Step 3's re-validering mod cachens rå svar genskabte det, og en efterfølgende
read-only probe har fordelt det pr. record:

| Record | Rå | Gyldige | Kontrakt-afviste |
| --- | ---: | ---: | ---: |
| IV-34 | 18 | 11 | **7** |
| alle øvrige ni | 75 | 75 | 0 |

Alle syv er altså IV-34's — den post, 4.3b markerede `delvis`. Ingen anden post bidrog.

**De 2 H1-afviste** er begge fra `I-11`: `relation.marriage` med værdien `NN.` og
`relation.child` med en ren mængdeangivelse. Begge er sande og formelt gyldige, men
identificerer ingen modpart at binde til. De afvises i **builderen**, ikke i writeren —
ét writer-element er én record, så en writer-exception ville have rullet I-11's fem
øvrige, korrekte claims tilbage. Det er præcis den fejl, projektejeren afgjorde imod
efter 4.3b's bundt 1.

**8 elementer, ikke 10.** `I-29` og `III-104` er krydshenvisninger uden biografisk
indhold; modellen gav nul claims for begge, og det var korrekt tilbageholdenhed. De
bliver derfor ikke til writer-elementer.

### Claims pr. element

| Element | Claims | | Element | Claims |
| --- | ---: | --- | --- | ---: |
| I-11 | 5 | | I-120 | 25 |
| I-21 | 4 | | IV-19 | 25 |
| I-100 | 4 | | IV-34 | 11 |
| I-101 | 5 | | **I alt** | **84** |
| I-112 | 5 | | | |

Afstemt mod `private.reimport_event.payload->>'interpretations_written'` pr. element:
**nul afvigelser**.

### Fordeling

| `interpretation_kind` | Antal | | `persona_role` | Antal |
| --- | ---: | --- | --- | ---: |
| `property` | 60 | | `principal` | 68 |
| `mention` | 12 | | `other` | 16 |
| `event` | 8 | | | |
| `relation` | 4 | | | |

`interpretation_observation`-links: **88** (et claim kan citere flere klausuler).

### Forbrug

175.840 input-tokens, 7.568 output, 2.163 reasoning, 55.040 cached input. Tallene er
4.3b's — 4.4 foretog **ingen modelkald**.

## 2. Hashes

| Artefakt | SHA-256 |
| --- | --- |
| Forslags-manifest | `a328ede946140a1223be3077d18579d94f763812875a55d67abed00645313cf8` |
| 4.3b's runner-manifest | `56a57a56222951409d832771e3eeceb90ad270a2a93b1076a231cc1ea7fcf248` |
| Genimport-profil | `4e39fff44db0cdab7ff35d59fe852f317dc608e818c4b2dd8ff060190fdc625c` |
| Eligibility-ledger | `e41348bd6f5abed41fd780f075505e7b6d501dd983819fcf3ef807dec87849d1` |
| Prædikatfil | `5e51c55b6217a75000a3d37e1130f31cc47b5e8d2d7451a54fc6f4616986fe2d` |
| Prompt | `d46cda80177cf3b6c327842ceff0f1e32b589748055537f7f3af6fabfd11abbb` |

Desuden hash-bindes alle **ti cachefiler** enkeltvis i manifestets `provenance`, så det
kan efterprøves mod netop de svar, det blev bygget af. Builderen afviser at køre, hvis
4.3b's manifest-hash ikke er den, der blev givet GO til (`RUNNER_MANIFEST_DRIFT`).

Versionerede vokabularer: `nn-denylist-2018-20-v1`, `persona-role-2018-20-v1`,
`evidence-runner-1.0`, `interpretation-proposal-manifest-1.0`. Model: `gpt-5.6-terra`.

## 3. Kørslen

| Fase | Status | Committet | Efterkontrol |
| --- | --- | --- | --- |
| Dry-run | `finalized` | nej, rullet tilbage | 0 forslag i basen efter rollback |
| Apply | `finalized` | ja | 84 forslag, 8 `reimport_event`, 1 `extraction_run` |
| Replay | `already_applied` | ja | 0 nye rækker |

**Kanonisk delta: 0.** Aggregathashen er uændret før og efter apply. Ingen `person_creates`,
ingen `source_evidence`.

**Læsersiden kan ikke være flyttet.** Målt strukturelt frem for som før/efter-hash, fordi
apply allerede var committet, da spørgsmålet blev stillet: `anon` og `authenticated` har
`SELECT = f` på `private.interpretation`, `interpretation_observation`,
`clause_disposition`, `clause_disposition_current`, `extraction_run` og `reimport_event`;
der findes **0** public views, der læser dem, og **0** `anon`-eksekverbare public
funktioner, der gør det.

### Idempotens har to niveauer — sig hvilket

`already_applied` kom fra **batch**-niveauet: `red_reimport_batch_result` kortslutter på
`manifest_content_sha256`, så writeren blev slet ikke kaldt. Writerens egen guard er en
anden ting: `REIMPORT_WRITER_INTERPRETATION_PROPOSAL_EXISTS` pr. `interpretation_key`,
fail-closed og aldrig en stille no-op.

**Praktisk konsekvens:** en dry-run kan kun køre mod en base **uden** forslagene. Kør
dry-run før apply — bagefter afvises den, og det er ikke en fejl.

## 4. Dispositionsfordeling — forventet vs. målt

Forventningen blev skrevet ned **før** kørslen (`~/.private/43b-kørsel/task7-forventning.json`),
ellers er »som forventet« ingen kontrol.

| Tal | Forventet | Målt | |
| --- | ---: | ---: | --- |
| Elementer | 8 | 8 | ✅ |
| Interpretationer | 84 | 84 | ✅ |
| `principal` | 68 | 68 | ✅ |
| `other` | 16 | 16 | ✅ |
| Dispositionerede klausuler | 19 | 19 | ✅ |
| `fortolkning_foreslaaet` | 13 | 13 | ✅ |
| `afventer_identitet` | 6 | 6 | ✅ |
| Kanonisk delta | 0 | 0 | ✅ |

**Ingen afvigelser.** Alle otte tal ramte.

De 19 klausuler dækker 19 citeret af `principal`-claims og 6 citeret af `other`-claims —
**de 6 er en delmængde**. Hvor samme klausul citeres af begge roller, vinder
`afventer_identitet` (writerens temp-tabel), og den forrang var en del af forventningen,
ikke en efterrationalisering. `clause_disposition` står nu i max version 2: 4.1c skrev
version 1, 4.4 lagde version 2 ovenpå uden at overskrive noget.

## 5. Task 5's udfald — `persona_role` bor i profilen

Spec §7.2 havde et hul: den kender kun claims om recordens persona (`person.*`) og claims i
form `mention`/`relation`. Task 0 målte **8 `event.*`-claims** — `event.appointment` (6),
`event.dismissal` (1), `event.acquisition` (1) — som handler om hovedpersonen uden at have
`person.`-præfiks. En naiv »ikke `person.*` → `other`«-regel ville have givet dem persona
`NULL` og stemplet deres klausuler `afventer_identitet`: claims om hovedpersonen ville se
ud som claims om en uidentificeret tredjepart.

**Valgt:** et eksplicit, versioneret `persona_role_map` i genimportprofilen frem for en
rollekolonne i `private.interpretation_predicate`. Rollen er ikke en egenskab ved
prædikatet globalt, men ved *hvis record* claimet sidder i — `relation.marriage` og
`event.marriage` kan beskrive samme begivenhed og have hver sin rolle. Kortet er
fail-closed: ukendt prædikat giver ingen rolle, og builderen afviser claimet frem for at
gætte. Det tal var **0**.

Skrevet som errata til §7.2. Prisen: kortet er udgavespecifikt og skal skrives igen for
1939, og matchningen er præfiksbaseret (længste præfiks vinder), så et nyt prædikat under
et kendt præfiks arver rollen stiltiende.

## 6. Task 6's udfald — reviewsignalet bor i menneskearket

Valget stod mellem en additiv `proposal_flags jsonb` på `private.interpretation` og
bedømmelsesarkets forudfyldte anbefalingskolonne som eneste kanal. **Projektejeren valgte
arket** (2026-09-15). Ingen DDL i dette dagsværk.

Det afgørende var **rækkefølgen, ikke designet.** Task 7 var allerede kørt, så de 84
forslag stod i den restore, 4.3b-4.5 deler (spec §3). En kolonne skulle ind via writerens
lukkede payload-nøglesæt, men guarden er fail-closed pr. `interpretation_key` og replay
kortslutter på batch-niveau — kolonnen ville derfor koste enten en genkørsel af hele 4.4 på
en frisk base (altså kassere den base, 4.5 skal bruge) eller et `UPDATE` uden om
`private.reimport_event` og uden om tabellens versionsdisciplin. Havde Task 6 ligget før
Task 7, havde kolonnen været billig.

Dertil: spec §8.2 foreskriver allerede arket, og efter at H2 er opgivet som maskinel regel
er alt, et flag kunne bære, afledeligt af eksisterende kolonner — `confidence`,
`persona_role`, antal citerede klausuler, klausulens `clause_flags`, `value_kind`
(invariant 4).

**Ingen maskinel H2-regel.** 4.3b's ene usande claim var en *sproglig* fejl: en
konstruktion af typen »var død [årstal] ([dato]), **da** [begivenhed]« blev læst som en
dødsdato, skønt datoen tilhørte begivenheden — en *terminus ante quem*. Begge dødsclaims
stod ordret i teksten; modellen udledte intet. De to detektorer, tidligere planudgaver
foreslog, var derfor blinde: den ene sammenligner modeloutput med modeloutput, den anden
refererer til `date_min`/`date_max`, som `date_raw`-claims ikke har. Builderen bærer nu en
note om, at fraværet er et valg og ikke en mangel.

Skrevet som errata til §8.2, med genåbningskriterium: viser 4.5 et behov for signalet
forespørgbart *efter* afgørelsen, er `proposal_flags` additiv og kan komme til på en base,
der alligevel skal bygges om.

## 7. Negativ test

Record `III-129` — 0 primary personaer, 12 klausuler, én af de fire persona-løse records,
Task 0 målte.

| Variant | Resultat |
| --- | --- |
| A: claimet som `principal` | afvist med `REIMPORT_WRITER_PRINCIPAL_WITHOUT_PERSONA` |
| B: samme claim som `other` | `finalized`, rullet tilbage |

B er pointen: uden den kunne A's afvisning skyldes hvad som helst i payloaden. Med den er
afvisningen bevist **persona-specifik**. Intet blev committet; 84 forslag før og efter.

Testen kunne ikke køres inde i batchen — alle ti records har persona, og eksporten afviser
persona-løse. Den krævede en separat autorisation med rollback.

## 8. Gates

| Gate | Resultat |
| --- | --- |
| R-suite (`run-tests.R`) | FAIL 0 / PASS 2995 |
| pytest (pipeline-jobbets filer) | 202 passed |
| `db-verify.sql` mod restoren med 84 live forslag | exit 0, 119 OK-asserts |

**Miljøfælde, der kostede en kørsel:** `db-verify.sql` fejlede først med
`CLAUSE_SCHEMA_ACL_INVALID`, fordi ACL-revoke'en for klausullagets triggerfunktioner bor i
**`db-rls.sql`**, ikke i `db-migrations.sql`. Restoren manglede desuden `dblink`, som
db-verifys samtidighedstest kræver. Rækkefølgen er: migrations → rls →
`CREATE EXTENSION dblink` → verify. En migreret base er ikke en verificerbar base.

## 9. Prod-fortrydelse findes ikke

**Dette skal stå, før nogen overvejer et prod-GO for operationen.** Der er ingen
fortrydelsesvej for `interpretation_proposal` i produktionen (spec §7.4). Fortrydelse sker
ved restore af basen — hvilket i prod betyder tab af alt, der er skrevet siden. Det er
spec'ens åbne punkt 11.5 og er **ikke** designet i dette dagsværk.

Konsekvensen i hverdagssprog: kører man ingesten mod prod, kan man ikke fortryde den uden
at rulle hele databasen tilbage. Derfor er hele dagsværket kørt mod en restore.

## 10. Udestående

1. **`44-apply.R` er ikke prod-klar.** Den re-autoriserer ved hver kørsel (en forældreløs
   authorization-række pr. kørsel) og har ingen `--jeg-mener-det`-guard. Begge dele skal
   rettes, før scriptet bliver til en prod-wrapper.
2. **`writer_config`s otte nøgler er arvet** fra clause-evidence-profilen
   (`citation_label_template`, `observation_extraction_method`, `rendition_*`).
   Forslags-writeren læser ingen af dem, men de hashes ind i `profile_sha256`. Hører
   sammen med §7.2's errata og bør ryddes ved næste profilversion.
3. **Prod-fortrydelse** (punkt 9 ovenfor) — åbent punkt 11.5.
4. **Issue #189:** 4.1b's segmentering klipper `VI.` som en 3-tegns klausul og splittede en
   biografi midt i en sætning. Modellen fik altså sønderdelt tekst. Hører til 4.1b's motor,
   ikke til 4.4.
5. **Grenen er umerget** og har ingen PR.

## 11. Artefakter — skal bevares

**Restoren `daa43b_20260912192527` må ikke ryddes.** 4.5 bruger den: klausul-id'erne er
database-genererede, så en ny restore ville give andre id'er, og de 84 forslag skulle
bygges om (spec §3). Sletning er en gate **efter** 4.5.

Rehearsal-scripts i `~/.private/44-rehearsal-scripts/` (`44-dryrun.R`, `44-apply.R`,
`44-negativ.R`). Kørselsartefakter i `~/.private/43b-kørsel/`: manifest, cache,
forventnings- og resultatfil.
