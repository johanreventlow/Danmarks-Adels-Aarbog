# Trin 4 — hele 2018-20's forslag, afgørelser og bindinger i prod (samlet overførsel)

**Status:** designudkast, godkendt sektion for sektion i brainstorm 2026-10-03; **revideret efter
review runde 1** (uafhængig Opus-agent 2026-10-04: NO-GO, 2 BLOCKER, 4 MAJOR, 4 MINOR — alle godtaget,
to af dem ved projektejerens valg; se §12) **og runde 2** (ny Opus-agent 2026-10-04: GO med rettelser,
2 MAJOR, 5 MINOR — alle indarbejdet her; se §13). Reviewbudgettets to specrunder er brugt (decisions
2026-09-23); resten efterprøves i koderunderne. Specen er ikke et prod-GO; kørslen kræver sit eget GO efter §7.

Bygger på `docs/superpowers/specs/2026-09-24-trin4-pilot-prod-vej-design.md` (branch
`docs/147-pilot-prod-vej`, to Codex-runder), som beslutningen 2026-10-01 udpeger som kerne: den
nøglede pakke (`interpretation_key`, `decision_fingerprint`, `pack_sha256`). Hvor intet andet står,
gælder 24/9-designets regler for pakke og fingeraftryk. Afsnit, der ændres, er markeret **(ændret fra
24/9)**. 4.4's kørselsmotor genbruges **ikke** (§3.2).

## 1. Adgangskrav (roadmap)

| Krav | Svar |
| --- | --- |
| Roadmapmål | Trin 4 (#147), efter den fulde kørsel i restoren (`2018-20-fuld-koersel.md`) |
| Værdikædeled | Proposed-ingest → afgørelse (menneske + kontrolmodel) → promotion (binding) i prod |
| Leverancetype | Generel overførselsvej (pakke, digests, tynd kørselsmotor, runbook); ingen ny DB-mekanik, ingen DDL |
| Redaktionel værdi | Projektejerens 74 afgørelser og kontrolmodellens 602 gemmes i prod og skal ikke gøres om; 622 kildehenvisninger fra 2018-20 bindes til eksisterende fakta |
| Færdigbevis | `REHEARSAL_OK` på dagens dump inkl. øvet fortrydelse, og `VERIFY_OK` i prod med alle tre digests lig pakken (§9) |
| Erstatter | 4.4's parkerede GO-pakke og kørselsmotor (#196-projektionen som verifier, 06-recover) og 24/9-designets særskilte pilotoverførsel (bortfaldet 2026-10-01) |

## 2. Udgangspunkt

- **Restoren er facit.** `daa2018f_20261001133125` = prod-dump `9844dae3…` (2026-10-01) +
  `db-migrations.sql` + `db-rls.sql`. Den har 3.739 forslag fra forslagsmanifestet `80f3e5c1…` (478
  elementer), 676 afgørelser (74 `human-sheet-kontrol-v1`: 61 `accepted`, 13 `unresolved`; 602
  `machine-corroboration-v1`: `accepted`) og 622 bindinger i batch `66e4d11d…`. Kanonisk delta 0.
- **Alt skrives i det private lag** med de eksisterende writere og RPC'er: den generelle writers
  `interpretation_proposal`-operation (via R-gatewayen `04-proposal-apply-prod.R`, der tager
  `expected_counts` fra manifestet), `red_decide_interpretation` for afgørelser,
  `red_preview_interpretation_promotions` + `red_promote_interpretations_batch` for bindinger. Intet
  kanonisk delta, intet `anon`-synligt.
- **`interpretation_key` er deterministisk** (`private.interpretation_proposal_key`; nøglematerialet
  indeholder ingen id'er) og unik for alle 3.739. Den er ens i restore og prod, fordi begge har samme
  `source_id` og samme manifest. `interpretation_id` er tilfældig.
- **`red_decide_interpretation` validerer kun, at evidensen er et ikke-tomt objekt**; metoden
  kopieres fra version 1. Den oprindelige evidens kan derfor skrives for begge metoder.
- **Kontrolmodellen kan ikke trækkes om i prod.** Stikprøven trækkes på `interpretation_id`
  (`control_model._sample_key`). Maskinens og menneskets afgørelser overføres derfor begge som pakke;
  klassifikationen (ikke stikprøven) køres igen som driftkontrol (§4.3).
- **Hvad prod mangler i dag:** #196's projektion er ikke deployet. 4.4's kørselsmotor
  (`~/.private/147-44-prod/lib.zsh`) bygger på den i alle trin og har pilotens tal hardkodet
  (`validate_manifest`: 84 claims, 88 links, 68/16 roller; preflight `8|8|8|8|8`), så den kan ikke
  genbruges uændret.

## 3. Beslutninger

### 3.1 Fra brainstormen (2026-10-03)

1. **Drift: skrivepause + stop (C + A).** Projektejeren redigerer ikke i prod, før overførslen er kørt.
   Afviger prod alligevel fra dumpet 2026-10-01, overføres intet; kæden (ingest, kontrolmodel — ikke
   modelkald) køres om på et nyt dump. Fravalgt: delvis overførsel.
2. **Ny verifikation: tre nøglede digests** (§5) i stedet for #196's projektion og komparator.
   Fravalgt: deploy af #196 + ombygget komparator (ekstra DDL, to verifikationssystemer); direkte kopi
   af rækker (omgår writernes og RPC'ernes kontroller, som 24/9).
3. **Afgørelser bevarer deres oprindelige metode** **(ændret fra 24/9**, hvor alle blev
   `decision-pack`), så prod kan tælle, efterprøve og fortryde menneskelige og maskinelle afgørelser
   hver for sig (decisions 2026-09-27).
4. **Bindinger er ikke rækker i pakken**; de findes igen af målfindingen, afgrænset til pakkens nøgler.
5. **Ingen pilotdom** **(ændret fra 24/9)**: 24/9 §6.2 udgår.
6. **Ét forslagsmanifest** **(ændret fra 24/9)**: ingest én gang; ingen fase 2-baseline.

### 3.2 Efter review runde 1 (projektejeren 2026-10-04)

7. **Tynd kørselsmotor + restore.** Et nyt, kort `04`: dry-run → apply med én autorisation gennem den
   eksisterende R-gateway → `proposal_digest`. Der findes kun to lovlige ingest-tilstande: intet
   skrevet, eller alt lig pakken; alt andet ⇒ fortrydelse ved restore. **Intet `06-recover` og ingen
   genoptagelig trinmotor.** Fortrydelsen øves i rehearsalen mod en befolket kopi (§6.1 trin 4).
   Holder, fordi overførslen ikke indeholder DDL, og skrivepausen gælder fra før dumpet — de to
   forudsætninger, under hvilke en restore er trofast (memory 2026-09-17: ændrede funktioner og
   forældreløse rækker er de kendte fælder). Fravalgt: ombygning af 4.4's motor med digests i alle
   trin og genindført fejlmatrix for et nyt `06`.
8. **Levende-gate = ledger + persona.** Hvert element skal ligge som `eligible` i eligibility-ledgeret
   `e620073c…` (som allerede udelukker hele poster med levende hovedperson, slægtning eller ægtefælle,
   spec §9.2 — samme grundlag som modelkaldet); hvert element med persona skal desuden have accepteret
   identitet til en person med `levende IS FALSE` (NULL ⇒ STOP). II-35 (ingen persona) og alle
   `other`-claims går med på ledgerets grundlag. Ledger-hashen bindes i pakken og GO. Fravalgt: at
   udelade II-35 (ny ingest og restore for 3 claims).

## 4. Pakken

### 4.1 Lokalt arkiv og genafspilningspakke

- **Lokalt evidensarkiv:** `~/.private/2018-20-fuld/` som den er. Rummer kildetekst og claim-værdier.
  Flyttes og kopieres ikke; slettes kun efter oprydningsgaten.
- **Genafspilningspakke:** `~/.private/2018-20-overfoersel/pack/` (0700, filer 0600), bygget maskinelt
  af `build_transfer_pack.py` mod restoren:
  - `decisions-keyed.json`: én post pr. afgørelse (676), sorteret på `interpretation_key`:
    `interpretation_key`, `restore_interpretation_id` (så arkets `D <id>`-linjer og maskinens
    plan-/klassifikationsfiler kan efterprøves fra prod, også når restoren er slettet),
    `expected_version` (1), `status`, `decision_fingerprint` (§4.2), `evidence` (den oprindelige
    `decision_evidence` uændret).
  - `pack-manifest.json`: forslagsmanifestets indholdshash (`80f3e5c1…`), ledger-hash (`e620073c…`),
    `clause_set_sha256` (§4.2), dump-kvitteringens `dump_sha256`, driftsbaselinen (§4.3), restorens
    skema-fingeraftryk (§4.3), den nøglede klassifikation (§4.3: nøgle → klasse og `assertion_id` for
    alle 1.276 promoverbare). **Errata 2026-10-04:** restoren kan ikke klassificere igen — 676 af
    forslagene er afgjort, og klassifikationen ser kun `proposed`. Den nøglede klassifikation tages derfor
    fra kørslens egen fil `~/.private/2018-20-fuld/kontrol/klassifikation.json` (`ded0de56…`; kun id,
    prædikat, klasse og `assertion_id`), oversættes id → nøgle via restorens version 1-rækker, og filens
    hash bindes. Genafspilningen (§4.4) klassificerer i tilstand `PROPOSED` og skal give det samme, SHA-256 af aktørens uuid (`decided_by`), antal pr. (metode, status), de
    tre forventede digests og antal fra restoren (§5), SHA-256 af `decisions-keyed.json` og
    `pack_sha256` = SHA-256 over manifestets kanoniske JSON (sorterede nøgler, UTF-8, ingen
    mellemrum) med `pack_sha256`-feltet selv udeladt.
- **Notekontrakt** (som 24/9 §4.1): det eneste fritekstfelt er `evidence.note` (13 udfyldte).
  Pakken forlader ikke maskinen; byggeren printer kun tal og hashes, aldrig noter eller værdier.

### 4.2 Fingeraftryk og klausulsæt

- **`decision_fingerprint`** som 24/9 §4.2, beregnet af én delt SQL-fil
  (`interpretation_decision_fingerprint.sql`), som pakkebyggeren og `07-decide` kører.
- **`clause_set_sha256`** **(ændret fra 24/9)**: SHA-256 over den sorterede liste `(record_key, aktuel
  seq, private.clause_set_sha256(parent, aktuel seq))` for alle 2018-20's poster. Poster uden klausuler
  (funktionen giver NULL) indgår med den literale værdi `"none"`, så deres antal også er bundet.

### 4.3 Driftkontrol — faseopdelt **(ændret efter review)**

Driftkontrollen måler to forskellige ting i to faser:

- **Dumptilstand (kun i `01-preflight` og `03-rehearsal`, før noget er skrevet):** basens
  driftsbaseline = pakkens. Baselinen er en repo-fil (`transfer_baseline.sql`, ingen
  shell-interpolation) med: indholdshash over `public.assertion`, `public.fact`, `public.person`,
  `private.source_persona_identity` (accepterede), placeringerne bag `private.source_persona_placement_current`
  (ordnet på `placement.id`) og `private.interpretation_promotion_rule` (`to_jsonb`, ordnet på
  primærnøgle) — de data, klassifikationen og målfindingen hviler på; antal i de
  øvrige kanoniske tabeller (som `kanonisk_md5`); `clause_set_sha256`; 0 rækker i
  `private.interpretation` for 2018-20; skema-fingeraftryk (sorteret liste over funktioners og
  tabellers definition i `public`/`private`, så restore og prod beviseligt kører samme DDL). Afvigelse ⇒
  `TRANSFER_DRIFT` / `CLAUSE_SET_DRIFT` / `SCHEMA_DRIFT`, og efter beslutning 1 køres kæden om på et nyt
  dump. Tællinger af autorisationer og fortolkninger indgår ikke, fordi dry-run og ingest ændrer dem
  lovligt. Pakkens baseline og skema-fingeraftryk måles på en **ren restore af dumpet 2026-10-01 uden
  migrationer** og kræves lig restorens (som har kørt `db-migrations.sql`/`db-rls.sql`), så det er
  bevist, at migrationerne er no-op mod prods tilstand, og rehearsal og prod kan måles uden dem.
- **Ingen skrivning siden dumpet (i `02` og ved `04`'s indgang før dry-run'en)** **(ændret efter
  review runde 2)**: en restore-hash over alle tabeller og sekvenser i `private`+`public` (som 4.4's
  `restore-hash.sql`, men med `to_jsonb(…)::text`, fordi hashen også sammenlignes med den lokale
  rehearsal) måles i prod lige efter dumpet og igen ved `04`'s indgang; de skal være ens, og ingen
  `change_set` må have `created_at` ≥ dumpets start (`NO_WRITE_SINCE_DUMP`). Det er beviset bag
  §8.2's »intet andet går tabt«, og »uberørt-før« (§5) er netop denne måling.
- **Præmis for afgørelserne (i `07-decide`, i dens egen transaktion):** før første RPC køres
  `interpretation_control_classification.sql` over den aktuelle tilstand, hvor alle 3.739 er
  `proposed` — som i restoren før afgørelserne. Den nøglede klassifikation (nøgle → klasse og
  `assertion_id`) skal være lig pakkens for alle 1.276 promoverbare; ellers `MACHINE_PREMISE_DRIFT`, og
  intet skrives. Det dækker de 602 maskinelle, de 20 i stikprøven og præmissen for de 54 menneskeligt
  afgjorte uoverensstemmelser i én sammenligning.
- **Pr. afgørelse:** genberegnet fingeraftryk = pakkens (`DECISION_FINGERPRINT_MISMATCH`).

### 4.4 Kontrol af pakken (før ceremonien, lokalt)

1. 676 unikke nøgler; nøglemængden = restorens afgjorte fortolkninger; antal pr. (metode, status) =
   61/13/602; præcis én `decided_by`.
2. **Genafspilning mod en frisk, ren restore af dumpet 2026-10-01** (uden migrationer, som rehearsal og
   prod): driftkontrol → `04` → `07` → `08` → alle tre digests og antal = pakkens. Dette er
   integrationstesten og kan køres så tit, det er nødvendigt.

## 5. Digest-filen (verifikationen)

**Én læse-kun SQL-fil i repoet** (`interpretation_transfer_digests.sql`) med samme bytes i restoren
(ved pakkebygning), rehearsalen og prod. Den afgrænses til 2018-20's kilde. Ordnet hashning med
`COLLATE "C"`; rækker hashes som `to_jsonb(…)::text`, aldrig `x::text` (locale-afhængig citering).
**`interpretation_key` indgår i hver hashet række**, ikke kun i sorteringen.

| Digest | Rækker | Over | Udelader bevidst |
| --- | --- | --- | --- |
| `proposal_digest` | alle 3.739 nøgler, version 1 | nøgle, prædikat, `interpretation_kind`, værdi-hash, konfidens, persona-nøgle, `schema_version`, metode, model- og promptversion; observationslinks (ordinal, `clause_ordinal`, `verbatim_sha256`, evidensrolle); for de citerede klausuler dispositionens art (ikke dens `evidence`) | id'er, `created_at`, batch- og kørsels-id, dispositions-`evidence` (indeholder `batch_id`/`extraction_run_id`) |
| `decision_digest` | alle 3.739 nøgler, aktuel version (så også de 3.063 uafgjorte er bundet som `proposed`) | nøgle, version, status, `decision_evidence` minus nøglen `pack_sha256`, SHA-256 af `decided_by` | `decided_at`, id'er |
| `binding_digest` | alle bindinger for 2018-20, sorteret på (nøgle, `target_type`, `target_id`) | nøgle, `target_type`, `target_id`, `rule_key`, `rule_version` | `evidence.preview_hash`, `batch_id`, `promoted_at`, id'er |

Ved siden af hver digest: antal (3.739 / 676 afgjorte fordelt 61·13·602 og 3.063 `proposed` / 622).

**Ud over indholdet:**
- **Kanonisk delta 0:** indholdshashen fra driftsbaselinen (§4.3) før og efter, i samme base.
- **Uberørt** **(ændret efter review)**: en ny repo-fil (`transfer_untouched_hash.sql`) bygget som 4.4's
  `untouched-hash.sql`, men hvis eksklusionsliste også rummer `private.interpretation_promotion_batch` og
  `private.interpretation_promotion` (og sekvenser ejet af dem). Bindingerne dækkes af
  `binding_digest`. »Før« er målingen ved `04`'s indgang (§4.3).
- **`anon`:** grants uændrede, og `anon` ser 0 fortolkninger, observationer og bindinger.

**Tilstande pr. lag** **(ændret efter review)**:

| Forslag | Afgørelser | Bindinger | Tilstand | Næste skridt |
| --- | --- | --- | --- | --- |
| 0 | 0 | 0 | `EMPTY` | `04` |
| = pakken | alle `proposed` | 0 | `PROPOSED` | `07` |
| = pakken | = pakken | 0 | `DECIDED` | `08` |
| = pakken | = pakken | = pakken | `COMPLETE` | ingen (`already_applied`) |
| alt andet | | | `MIXED` | fortrydelse (§8.2) |

Hvert script kører klassifikationen først. I sin indgangstilstand skriver det; i sin udgangstilstand
(fx `08` i `COMPLETE`) melder det `already_applied` og skriver intet; i enhver anden tilstand stopper
det.

**Tre baser, én sandhed:** restoren sætter pakkens forventede værdier; rehearsalen og prod
sammenlignes hver for sig med pakken, aldrig kun med hinanden.

## 6. Kørslen

### 6.1 Ceremonien

Én session, ét GO. Nye private scripts i `~/.private/2018-20-overfoersel/`. De arver 4.4's
konventioner, men ikke dens motor: `/bin/zsh -f`, `emulate -R zsh`, `--jeg-mener-det` for skrivende
scripts, afvisning af ukendte argumenter, `set -euo pipefail`, `umask 077`, lukket R-miljø (`env -i`,
`Rscript --vanilla`), kun Session pooleren, rydning af nedarvede `PG*`, private filer 0600, intet
aktør-id på stdout, rolleproben (`01-role-probe-prod.R`). De genbrugte R-filers miljøkontrakt
(`DAA_EXPECTED_TARGET`, `DAA_PREVIEW_SHA256`, `DAA_REPO`, `DAA_CONNECTION_MODE`, `DAA_LOCAL_*`, frisk
runmappe med O_EXCL-intent, det lokale basenavnsmønster) opfyldes af de nye scripts; ændres en R-fil,
er det de nye bytes, der bindes.

| Trin | Handling | Skriver i prod |
| --- | --- | --- |
| 1 | `00-freeze begin` — skrivepause (beslutning 1) | nej |
| 2 | `01-preflight`: rolleprobe; driftkontrol, dumptilstand og skema-fingeraftryk (§4.3); tilstand `EMPTY`; levende-gate (beslutning 8); **restore-forudsætninger**: 0 forældreløse rækker i tabeller med fremmednøgler, `rollback-preflight.sql`'s værdier asserteret (ikke kun kørt), og et katalogfingeraftryk af prod (`pg_constraint`, `pg_policy`, `pg_proc`, sekvenser) | nej |
| 3 | `02-dump` (backuppen og fortrydelsespunktet) og straks restore-hashen (§4.3) | nej |
| 4 | `03-rehearsal` på en restore af netop dette dump: (a) driftkontrol → `04` → `07` → `08` → `05`; alt = pakken; (b) **fortrydelsesøvelse** med netop den kommando, §8.2 bruger: restore af samme dump oven på den befolkede rehearsal-base; hele `pg_restore`-fejllisten læses (ikke kun exitkoden); bagefter er tilstanden `EMPTY`, restore-hashen er lig prods måling fra trin 3, og katalogfingeraftrykket er lig **prods eget** fra trin 2 (ikke en anden restore, som kunne mangle de samme fremmednøgler); (c) `04`'s transaktionsvarighed måles og skal ligge under en grænse fastsat i planen (pooler-sessionen er risikoen, ikke autorisationens TTL, som kun tjekkes ved `begin`). Alt bestået ⇒ `REHEARSAL_OK` | kun lokalt |
| 5 | GO-pakke (§8.1). Ét GO. Omsegmenteringens fortrydelsesvindue lukker her (decisions 2026-10-01) | — |
| 6 | Prod: `04-apply` → `07-decide` → `08-bind`; hvert trin klassificerer tilstanden først (§5) og tjekker sit lags digest mod pakken, før det næste starter | privat lag |
| 7 | `05-verify` (§5 fuldt, tilstand `COMPLETE`); derefter `00-freeze end` | nej |

### 6.2 Trinene

- **`04-apply`** (tynd motor): indgangstilstand `EMPTY`; validering af manifestet mod pakken
  (indholdshash; antal elementer, claims, links og roller læses af manifestet og sammenlignes med
  pakkens — intet hardkodet); restore-hash = trin 3's (`NO_WRITE_SINCE_DUMP`); dry-run gennem
  R-gatewayen (`03-proposal-dryrun-prod.R`: status `finalized`, ikke committet — antallene håndhæves af
  serverens `finalize` mod autorisationens `expected_counts`, som er taget af manifestet); apply med én
  nonce-bundet autorisation (`04-proposal-apply-prod.R`); `proposal_digest` = pakkens ⇒ tilstand
  `PROPOSED`. Gatewayen skriver alt i én transaktion; kun writer-profilrækken (`ON CONFLICT DO
  NOTHING`) og udstedte autorisationer overlever et afbrud, og begge er idempotente. Efter afbrud
  klassificeres tilstanden: `EMPTY` ⇒ `04` køres igen; `PROPOSED` (committet, men digesten nåede ikke
  at køre) ⇒ digesten køres og derefter `07`; alt andet ⇒ fortrydelse.
- **`07-decide`** (én transaktion, `ON_ERROR_STOP`): klassifikation, fingeraftryk og digests læser
  `private` og kører som forbindelsens ejerrolle; kun RPC-kaldene kører under `SET LOCAL ROLE
  authenticated` med `request.jwt.claim.sub` = redaktionsprofilen (uuid-hash = pakkens), efterfulgt af
  `RESET ROLE` før digesten. Indgangstilstand `PROPOSED`; `clause_set_sha256`;
  maskinens præmis (§4.3); tilstandsklassifikation over hele pakken før første RPC (som 24/9 §4.4:
  alle `proposed` v1 ⇒ skriv; ingen eller flere aktuelle rækker for en nøgle ⇒
  `DECISION_KEY_UNRESOLVED`); pr. post fingeraftryk og `red_decide_interpretation(id, 1, status,
  evidence ∪ {pack_sha256})`; til sidst `decision_digest` = pakkens, ellers rulles alt tilbage.
  Genkørsel i tilstand `DECIDED` er `already_applied` kun, når evidensen er pakkens evidens plus
  netop dette `pack_sha256`.
- **`08-bind`** (én transaktion, samme rollemønster som `07`): indgangstilstand `DECIDED`; en wrapper-fil
  (`interpretation_promotion_targets_scoped.sql`) giver den delte målfinding pakkens 663
  `accepted`-nøgler som obligatorisk input — den delte `interpretation_promotion_targets.sql` er
  uændret, så kontrolmodellens `verify-sql` og SQL-testene fortsat virker; i transaktionen kræves
  aktuelle `accepted` for pakkens nøgler = pakkens (`BIND_SCOPE_DRIFT`), 622 items, alle `eligible` i
  RPC'ens preview; preview og batch i samme transaktion; til sidst `binding_digest` = pakkens, ellers
  rulles alt tilbage ⇒ tilstand `COMPLETE`.

### 6.3 Stop undervejs

- `07` og `08` skrives helt eller slet ikke; en fejl før commit efterlader tilstanden uændret, og
  trinnet kan køres igen efter rettelse.
- `04` er atomar gennem gatewayens ene transaktion (§6.2); efter et afbrud er tilstanden `EMPTY` eller
  `PROPOSED`.
- Enhver `MIXED`-tilstand eller digest-afvigelse efter commit ⇒ fortrydelse (§8.2). En delvis
  overførsel er aldrig en accepteret sluttilstand.

## 7. GO

GO-hashfilen binder: dump-hash, forslagsmanifestets hash, ledger-hash, `pack_sha256`,
`clause_set_sha256`, driftsbaselinen, skema-fingeraftrykket, rehearsal-rapporten (inkl.
fortrydelsesøvelsen og den målte varighed af `04`) med dens digests og antal, repoets commit — samt
et **eksakt filinventar**, kontrolleret som mængde: de nye private scripts (`00-freeze`, `01-preflight`,
`02-dump`, `03-rehearsal`, `04-apply`, `05-verify`, `07-decide`, `08-bind`, deres fælles lib), de
genbrugte R-filer (`01-role-probe-prod.R`, `03-proposal-dryrun-prod.R`, `04-proposal-apply-prod.R`),
pakkens to filer, forslagsmanifestet, eligibility-ledgeret (`e620073c…`) og writer-profilens JSON; i
repoet `restore-hash`- og katalogforespørgslerne, `interpretation_transfer_digests.sql`,
`transfer_baseline.sql`, `transfer_untouched_hash.sql`, `interpretation_decision_fingerprint.sql`,
`build_transfer_pack.py`, `transfer_decide.sql`, `interpretation_promotion_targets_scoped.sql`,
`interpretation_promotion_targets.sql`, `interpretation_control_classification.sql` og
`apply_reimport_helpers.R`. Det præcise antal fastlægges i planen; en manglende eller ekstra linje er
STOP. Clean-tree-kontrollen omfatter alle repo-stier i inventaret.

## 8. Fortrydelse

### 8.1 Hvornår

Tilstand `MIXED`, en digest-afvigelse efter commit, eller et STOP mellem trin, som ikke kan rettes ved
at køre et atomart trin igen.

### 8.2 Hvordan (vej A)

Backuppen fra trin 3 gendannes med den kommando, rehearsalen har øvet (§6.1 trin 4b), og tilstanden
skal derefter klassificeres `EMPTY` med driftsbaselinen lig pakkens. Ceremonien køres igen efter
rettelse. Projektejerens afgørelser ligger i pakken og genafspilles; intet skal afgøres igen.
Skrivepausen sikrer, at intet andet går tabt. Backuppen bliver det nye restorepunkt.

## 9. Færdigbevis og modenhed

- **Før ceremonien:** pakken bygget og kontrolleret (§4.4), inkl. genafspilning mod dumpet
  2026-10-01 med alle digests lig restoren.
- **Ceremonien:** `REHEARSAL_OK` (§6.1 trin 4 a-c); `VERIFY_OK` i prod: tilstand `COMPLETE`, alle tre
  digests og antal lig pakken, kanonisk delta 0, uberørte tabeller og `anon` uændret.
- **Modenhed:** ingest og afgørelse ⇒ `produktionsverificeret` for 2018-20; promotion kun for
  bindingsdelen og markeret sådan (som 24/9 §7).

## 10. Test (test først)

- **pytest** for `build_transfer_pack.py`: 676 poster; dublet-nøgle; nøgle uden afgørelse; afgørelse
  uden nøgle; antal pr. metode og status; præcis én aktør; kanonisk `pack_sha256`; ingen noter eller
  værdier på stdout; ingen felter ud over de specificerede.
- **SQL-test** for fingeraftrykket: ændres ved ændret klausultekst, ordinal eller værdi; uændret ved nye
  tilfældige id'er.
- **SQL-test** for digest-filen: ens i to baser med samme indhold og forskellige id'er; ændres ved
  **ombyttet status mellem to nøgler med samme fordeling**, ændret evidens (uden for `pack_sha256`),
  ændret mål-assertion, to mål for samme nøgle, ændret dispositionsart; uændret ved ændret
  dispositions-`evidence`.
- **SQL-test** for tilstandsklassifikationen: hver af de fem tilstande, inkl. `MIXED` ved delvis
  ingest.
- **SQL-test** for driftsbaselinen: ændres ved en rettet assertion-værdi og en ændret identitet; uændret
  af autorisationer og private fortolkninger.
- **SQL-test** for restore-hashen: ændres ved én ændret række og ved en sekvens; ens på tværs af
  locale (`to_jsonb`).
- **SQL-test** for `07`: `CLAUSE_SET_DRIFT`; `MACHINE_PREMISE_DRIFT` (en maskinel nøgle, hvis assertion
  er ændret, og en REAL_DIFF-nøgle, der er blevet MATCH); ukendt nøgle; to rækker for samme nøgle; forkert version; `already_applied` kun ved
  eksakt evidens; digest-afvigelse ruller tilbage; menneskelig og maskinel metode bevares.
- **SQL-test** for `08`: en accepteret, promoverbar fortolkning uden for pakken bliver ikke item;
  `BIND_SCOPE_DRIFT`; `binding_digest` ens i to baser; den delte målfinding er uændret (eksisterende
  tests grønne).
- **Shell-tests** for `04`/`07`/`08`: flag, ukendte argumenter, GO-hash-mismatch, forkert
  indgangstilstand.
- **Integration:** genafspilningen mod dumpet 2026-10-01 (§4.4) og ceremoniens rehearsal med
  fortrydelsesøvelse.

## 11. Afgrænsning

Ikke med: nye kanoniske fakta for de 41 accepterede uoverensstemmelser (trin 4-spec §11.3);
navneregel og ny promptversion (decisions 2026-10-03, kontraktfrys); oprydning af 138
navne-assertions med titelord; runnerens kvotefix; normaliseringsregel for `SKRIVEMAADE`;
fortrydelsesfunktion i databasen; deploy af #196; genoptagelig trinmotor og `06-recover`
(beslutning 7); fejlmatrix (privat lag, decisions 2026-09-23 — og uden `06` er der ingen
genoptagelsessti at injicere fejl i; fortrydelsen øves i stedet).

## 12. Revision efter review runde 1 (2026-10-04)

Uafhængig Opus-agent uden samtalekontekst; påstandene om 4.4-motoren, tilstandsforespørgslen,
`kanonisk_md5` og »uberørt«-listen er efterprøvet mod koden, før de blev godtaget.

| Fund | Ændring |
| --- | --- |
| BLOCKER 1 — 4.4's motor bygger på #196 og pilotens hardkodede tal | §3.2 beslutning 7: tynd motor + restore; §6.2 `04` uden hardkodede tal; §6.1 trin 4b fortrydelsesøvelse |
| BLOCKER 2 — driftkontrol i forkert fase (tæller fortolkninger og autorisationer) og for svag (kun antal) | §4.3 faseopdelt: indholdshash af de data, maskinens accept hviler på, kun før skrivning; `07` klassificerer igen (`MACHINE_PREMISE_DRIFT`) |
| MAJOR 3 — levende-gaten og II-35 | §3.2 beslutning 8: ledger + persona |
| MAJOR 4 — »uberørt« fejler efter binding | §5: `transfer_untouched_hash.sql` udelader promotion-tabellerne |
| MAJOR 5 — genoptagelse modsagde »før«-tilstanden | §5: tilstande pr. lag; scripts kører kun i deres indgangstilstand |
| MAJOR 6 — skemaparitet ikke påstået | §4.3: skema-fingeraftryk; §4.4: samme opskrift som restoren; writerens funktionskontrol (`DDL_196_MISSING`) bevares (udgår i runde 2, §13) |
| MINOR 7 — digest-detaljer | §5: nøgle i hver række, sekundær sortering, dispositions-`evidence` udeladt, `decision_digest` over alle 3.739, `already_applied` med `pack_sha256` |
| MINOR 8 — pakkescope i den delte målfinding | §6.2: wrapper-fil; den delte fil er uændret |
| MINOR 9 — efterprøvelighed fra prod | §4.1: `restore_interpretation_id` pr. nøgle; aktør-hash |
| MINOR 10 — TTL ved 478 elementer | §6.1 trin 4c: varigheden måles i rehearsalen |

## 13. Revision efter review runde 2 (2026-10-04)

Ny Opus-agent uden kontekst; dom GO med rettelser. Påstandene om gatewayens ene transaktion
(`apply_reimport_helpers.R` `begin`/`commit`), 4.4's `GATE_DATA` og dry-run-kvitteringens indhold er
efterprøvet mod koden.

| Fund | Ændring |
| --- | --- |
| MAJOR N1 — intet beviste »ingen skrivning siden dumpet« (regression fra runde 1) | §4.3: restore-hash i `02` og ved `04`'s indgang + `change_set` siden dumpet = 0 (`NO_WRITE_SINCE_DUMP`); »uberørt-før« forankret |
| MAJOR N2 — fortrydelsesøvelsen sammenlignede restore med restore | §6.1 trin 2 og 4b: prods katalogfingeraftryk, 0 forældreløse rækker, `rollback-preflight.sql` asserteret, restore-hash som databevis |
| B2 delvist — 54 REAL_DIFF-præmisser og regeltabellen | §4.3: nøglet klassifikation for alle 1.276; `interpretation_promotion_rule` og placeringer i baselinen |
| MINOR N3 — dry-run-kvitteringen har ingen antal | §6.2: antallene håndhæves af serverens `finalize` |
| MINOR N4 — rollerækkefølgen i `07`/`08` | §6.2: ejerrolle til læsning, `authenticated` kun om RPC'erne |
| MINOR N5 — `PROPOSED` efter afbrud; `already_applied` mod indgangstilstand | §5, §6.2, §6.3 |
| MINOR N6 — ledger og profil-JSON uden for inventaret | §7 |
| MINOR N7 — migrationer kunne give falsk drift | §4.3, §4.4: baseline målt på ren restore uden migrationer og krævet lig restorens |
| M10 delvist — TTL målte det forkerte | §6.1 trin 4c: transaktionsvarighed mod en grænse |
| Enkelhed | `DDL_196_MISSING` udgår (skema-fingeraftrykket dækker det); »`04` ikke atomar« rettet; maskinpræmis og stikprøve samlet i én nøglet sammenligning |
