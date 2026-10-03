# Trin 4 — hele 2018-20's forslag, afgørelser og bindinger i prod (samlet overførsel)

**Status:** designudkast, godkendt sektion for sektion i brainstorm 2026-10-03. Ikke reviewet endnu
(reviewbudget 2 + 2, decisions 2026-09-23). Specen er ikke et prod-GO; kørslen kræver sit eget GO
efter §6.

Bygger på `docs/superpowers/specs/2026-09-24-trin4-pilot-prod-vej-design.md` (branch
`docs/147-pilot-prod-vej`, to Codex-runder), som beslutningen 2026-10-01 udpeger som kerne: den
nøglede pakke (`interpretation_key`, `decision_fingerprint`, `pack_sha256`). Hvor intet andet står,
gælder 24/9-designets regler. Afsnit, der ændres, er markeret **(ændret fra 24/9)**.

## 1. Adgangskrav (roadmap)

| Krav | Svar |
| --- | --- |
| Roadmapmål | Trin 4 (#147), efter den fulde kørsel i restoren (`2018-20-fuld-koersel.md`) |
| Værdikædeled | Proposed-ingest → afgørelse (menneske + kontrolmodel) → promotion (binding) i prod |
| Leverancetype | Generel overførselsvej (pakke, digests, runbook, scripts); ingen ny DB-mekanik og ingen DDL |
| Redaktionel værdi | Projektejerens 74 afgørelser og kontrolmodellens 602 gemmes i prod og skal ikke gøres om; 622 kildehenvisninger fra 2018-20 bindes til eksisterende fakta |
| Færdigbevis | `REHEARSAL_OK` på dagens dump og `VERIFY_OK` i prod med alle tre digests lig pakken (§8) |
| Erstatter | 4.4's parkerede GO-pakke (#196-projektionen som verifier) og 24/9-designets særskilte pilotoverførsel (bortfaldet 2026-10-01) |

## 2. Udgangspunkt

- **Restoren er facit.** `daa2018f_20261001133125` (restore af prod-dump `9844dae3…` fra 2026-10-01)
  har 3.739 forslag fra forslagsmanifestet `80f3e5c1…`, 676 afgørelser (74
  `human-sheet-kontrol-v1`: 61 `accepted`, 13 `unresolved`; 602 `machine-corroboration-v1`:
  `accepted`) og 622 bindinger i batch `66e4d11d…`. Kanonisk delta 0.
- **Alt skrives i det private lag** med de eksisterende writere og RPC'er: 4.4's writer for forslag,
  `red_decide_interpretation` for afgørelser, `red_preview_interpretation_promotions` +
  `red_promote_interpretations_batch` for bindinger. Intet kanonisk delta, intet `anon`-synligt.
- **`interpretation_key` er deterministisk** (`private.interpretation_proposal_key` over kilde, post,
  prædikat, distinkte klausulordinaler og værdi) og unik for alle 3.739. Den er ens i restore og prod,
  fordi begge har samme `source_id` og samme manifest. `interpretation_id` er tilfældig.
- **Kontrolmodellen kan ikke køres om i prod.** Stikprøven trækkes på `interpretation_id`
  (`control_model._sample_key`), så prod ville få en anden stikprøve end den, projektejeren har
  afgjort. Også maskinens afgørelser skal derfor overføres.
- **Maskinens accept hviler på databasens fakta.** `machine-corroboration-v1` betyder »matcher
  assertion X i restoren«. Fingeraftrykket binder klausulteksten, ikke fakta; præmissen holdes af
  driftkontrollen (§4.3).
- **Hvad prod mangler i dag:** #196's fortolkningsprojektion er ikke deployet, og
  `compare_interpretation_proposal_projection.py` afviser manifester i current-tilstand. 24/9-planens
  pakkebygger, `07-decide` og `08-bind` er aldrig bygget. 4.4's driftsscripts
  (`~/.private/147-44-prod/`) findes og er rehearsed 2026-09-23.

## 3. Beslutninger fra brainstormen (2026-10-03)

1. **Drift: skrivepause + stop (C + A).** Projektejeren redigerer ikke i prod, før overførslen er kørt.
   Afviger prod alligevel fra dumpet 2026-10-01, overføres intet; kæden (ingest, kontrolmodel — ikke
   modelkald) køres om på et nyt dump. Fravalgt: delvis overførsel af det, der stadig holder.
2. **Tilgang B: 4.4's driftsskal, ny verifikation.** Skrivepause, preflight, dump, rolleprobe,
   nonce-bundet autorisation, R-writer og recover genbruges. #196's projektion og komparator
   erstattes af én nøglet digest-fil for alle tre lag (§5). Fravalgt: (A) deploy af #196 og ombygning
   af komparatoren — en ekstra DDL og to verifikationssystemer; (C) direkte kopi af rækker — omgår
   writernes og RPC'ernes kontroller (som 24/9).
3. **Afgørelser bevarer deres oprindelige metode** **(ændret fra 24/9)**, hvor alle blev
   `decision-pack`. Ellers kan prod ikke skelne menneskelige fra maskinelle afgørelser (decisions
   2026-09-27: metodefeltet skal kunne tælles, efterprøves og fortrydes for sig).
4. **Bindinger er ikke rækker i pakken.** De findes igen i prod af målfindingen, afgrænset til
   pakkens nøgler, og sammenlignes på en semantisk digest.
5. **Ingen pilotdom** **(ændret fra 24/9)**: §6.2 i 24/9 (`pilot-verdict`, `pilot_verdict.py`,
   `PILOT_TRANSFER_BLOCKED`) udgår. Det er den fulde kørsel; levende-gaten består.
6. **Ét forslagsmanifest** **(ændret fra 24/9)**: ingest køres én gang; 24/9's fase 2-baseline udgår.

## 4. Pakken

### 4.1 Lokalt arkiv og genafspilningspakke

- **Lokalt evidensarkiv:** `~/.private/2018-20-fuld/` som den er (ark, rækkefiler, manifester,
  klassifikation, plan). Rummer kildetekst og claim-værdier. Flyttes og kopieres ikke; slettes kun
  efter oprydningsgaten.
- **Genafspilningspakke:** `~/.private/2018-20-overfoersel/pack/` (0700, filer 0600), bygget maskinelt
  af `build_transfer_pack.py` mod restoren:
  - `decisions-keyed.json`: én post pr. afgørelse (676), sorteret på `interpretation_key`:
    `interpretation_key`, `expected_version` (1), `status`, `decision_fingerprint` (§4.2),
    `evidence` (den oprindelige `decision_evidence` uændret).
  - `pack-manifest.json`: forslagsmanifestets indholdshash (`80f3e5c1…`), `clause_set_sha256`
    (§4.2), dump-kvitteringens `dump_sha256`, `state` og `kanonisk_md5`, antal pr. (metode, status),
    de tre forventede digests og antal fra restoren (§5), SHA-256 af `decisions-keyed.json` og
    `pack_sha256` = SHA-256 over manifestets kanoniske JSON (sorterede nøgler, UTF-8, ingen
    mellemrum) med `pack_sha256`-feltet selv udeladt.
- **Notekontrakt** (som 24/9 §4.1): det eneste fritekstfelt er `evidence.note` (13 udfyldte).
  Pakken forlader ikke maskinen; byggeren printer kun tal og hashes, aldrig noter eller værdier.

### 4.2 Fingeraftryk og klausulsæt

- **`decision_fingerprint`** som 24/9 §4.2: SHA-256 over kanonisk JSON
  `{fp_version: 1, interpretation_key, record_key, predicate, value_sha256, clauses: [[clause_ordinal,
  verbatim_sha256], …]}`, beregnet af én delt SQL-fil (`interpretation_decision_fingerprint.sql`),
  som både pakkebyggeren og `07-decide` kører.
- **`clause_set_sha256`** **(ændret fra 24/9)**: efter omsegmenteringen har hver post et versioneret
  klausulsæt. Pakkens værdi er SHA-256 over den sorterede liste `(record_key, aktuel seq,
  private.clause_set_sha256(parent, aktuel seq))` for alle 2018-20's poster — databasens egen
  funktion, ikke en ny hash.

### 4.3 Driftkontrol

`01-preflight` (prod), `03-rehearsal` og `07-decide` kræver:

- `state`, `kanonisk_md5` og `clause_set_sha256` i basen = pakkens (dumpet 2026-10-01). `state` og
  `kanonisk_md5` beregnes af præcis den forespørgsel, dump-kvitteringen 2026-10-01 brugte
  (funktionerne `kanonisk_md5` og tilstandsstrengen i `~/.private/omseg-prod/lib.zsh`, som
  `dump-laesekun.zsh` bruger); forespørgslerne flyttes uændret til en repo-fil, så restore, rehearsal og
  prod kører samme bytes. Afvigelse ⇒
  STOP (`TRANSFER_DRIFT` / `CLAUSE_SET_DRIFT`); efter beslutning 1 køres kæden om på et nyt dump.
- Pr. afgørelse: genberegnet fingeraftryk = pakkens (`DECISION_FINGERPRINT_MISMATCH`).

### 4.4 Kontrol af pakken (før ceremonien, lokalt)

1. 676 unikke nøgler; nøglemængden = restorens afgjorte fortolkninger; antal pr. (metode, status) =
   61/13/602.
2. **Genafspilning mod en frisk restore af dumpet 2026-10-01:** ingest via writeren → `07-decide` →
   `08-bind` → alle tre digests og antal = pakkens. Dette er integrationstesten og kan køres så tit,
   det er nødvendigt.

## 5. Digest-filen (verifikationen)

**Én læse-kun SQL-fil i repoet** (`interpretation_transfer_digests.sql`) med samme bytes i restoren
(ved pakkebygning), rehearsalen og prod. Den afgrænses til 2018-20's kilde. Ordnet hashning med
`COLLATE "C"`; rækker hashes som `to_jsonb(…)::text`, aldrig `x::text` (locale-afhængig citering).

| Digest | Over (sorteret på `interpretation_key`) | Udelader bevidst |
| --- | --- | --- |
| `proposal_digest` | version 1: prædikat, `interpretation_kind`, værdi-hash, konfidens, persona-nøgle, `schema_version`, metode, model- og promptversion; observationslinks (ordinal, `clause_ordinal`, `verbatim_sha256`, evidensrolle); klausuldispositionerne for de citerede klausuler | id'er, `created_at`, batch- og kørsels-id |
| `decision_digest` | aktuel version, status, `decision_evidence` minus nøglen `pack_sha256`, `decided_by` | `decided_at`, id'er |
| `binding_digest` | `target_type`, `target_id`, `rule_key`, `rule_version` | `evidence.preview_hash`, `batch_id`, `promoted_at`, id'er |

Ved siden af hver digest: antal (3.739 / 676 fordelt 61·13·602 / 622).

**Ud over indholdet:**
- **Kanonisk delta 0:** antal `fact` og `assertion` og en hash over alle assertions (`to_jsonb`, ordnet
  på `id`) — før og efter, i samme base.
- **Uberørt:** 4.4's `untouched-hash.sql` før og efter.
- **`anon`:** grants uændrede, og `anon` ser 0 fortolkninger, observationer og bindinger.

**Tilstande:**
- *Før:* 0 fortolkninger for 2018-20's kilde. Har basen fortolkninger, og er alle tre digests lig
  pakkens, er overførslen `already_applied`, og intet skrives. Alt andet ⇒ STOP.
- *Efter:* alle tre digests og antal = pakkens, kanonisk hash uændret.

**Tre baser, én sandhed:** restoren sætter pakkens forventede værdier; rehearsalen og prod
sammenlignes hver for sig med pakken, aldrig kun med hinanden.

## 6. Kørslen

### 6.1 Ceremonien

Én session, ét GO. Private scripts i `~/.private/2018-20-overfoersel/`, tilpasset fra
`~/.private/147-44-prod/` (samme konventioner: `/bin/zsh -f`, `--jeg-mener-det`, afvisning af ukendte
argumenter, lukket R-miljø, kun Session pooleren, private filer 0600, intet aktør-id på stdout).

| Trin | Handling | Skriver i prod |
| --- | --- | --- |
| 1 | `00-freeze begin` — skrivepause (beslutning 1) | nej |
| 2 | `01-preflight`: rolleprobe; levende-gate; driftkontrol (§4.3); 0 fortolkninger for 2018-20 | nej |
| 3 | `02-dump` | nej |
| 4 | `03-rehearsal`: restore af netop dette dump; `04` → `07` → `08` → digests; alt = pakken ⇒ `REHEARSAL_OK` | kun lokalt |
| 5 | GO-pakke (§7.1). Ét GO. Omsegmenteringens fortrydelsesvindue lukker her (decisions 2026-10-01) | — |
| 6 | Prod: `04-apply` → `07-decide` → `08-bind`; hvert trin tjekker sit lags digest mod pakken, før det næste starter | privat lag |
| 7 | `05-verify` (§5 fuldt); derefter `00-freeze end` | nej |

**Levende-gaten** (som runbookens 4.4-gate over hele manifestet): alle personaer i forslagsmanifestet
har én primær persona, accepteret identitet, eksisterende person og `levende IS FALSE`; NULL ⇒ STOP.

### 6.2 Trinene i prod

- **`04-apply`**: 4.4's writer-vej uændret — én nonce-bundet autorisation for manifestet `80f3e5c1…`,
  R i lukket miljø. Afbrydelse ⇒ `06-recover`, aldrig `04` igen. Efter `04`: `proposal_digest` =
  pakkens, ellers STOP.
- **`07-decide`** (én transaktion, `ON_ERROR_STOP`, rolle `authenticated`, `request.jwt.claim.sub` =
  redaktionsprofilen):
  1. driftkontrol (§4.3);
  2. tilstandsklassifikation over hele pakken før første RPC (som 24/9 §4.4): alle `proposed`
     version 1 ⇒ skriv; alle version 2 med evidens og status lig pakkens ⇒ `already_applied`; alt
     andet ⇒ `DECISION_STATE_MIXED`; ingen eller flere aktuelle rækker for en nøgle ⇒
     `DECISION_KEY_UNRESOLVED`;
  3. pr. post: fingeraftryk; derefter `red_decide_interpretation(id, 1, status, evidence ∪
     {pack_sha256})`;
  4. til sidst: `decision_digest` i basen = pakkens, ellers rulles alt tilbage.
- **`08-bind`** (én transaktion, samme rolle og claim): målfindingen
  (`interpretation_promotion_targets.sql`) får pakkens `accepted`-nøgler (663) som obligatorisk
  input og kører ikke uden; i transaktionen kræves aktuelle `accepted` for pakkens nøgler = pakkens
  (`BIND_SCOPE_DRIFT`); alle items skal være `eligible` i RPC'ens preview; preview og batch i samme
  transaktion; til sidst `binding_digest` = pakkens, ellers rulles alt tilbage. Genkørsel: præcis de
  forventede bindinger findes ⇒ `already_applied`.

### 6.3 Stop undervejs

- `07` og `08` skrives helt eller slet ikke. En fejl før commit efterlader laget uændret; trinnet kan
  køres igen efter rettelse (dets tilstandsklassifikation fanger en delvis tilstand).
- En digest-afvigelse efter commit, eller et STOP mellem trin, som ikke kan rettes ved at køre det
  atomare trin igen ⇒ fortrydelse (§7.2). En delvis overførsel er aldrig en accepteret sluttilstand.

## 7. GO og fortrydelse

### 7.1 GO-pakken

GO-hashfilen binder: dump-hash, forslagsmanifestets hash, `pack_sha256`, `clause_set_sha256`,
rehearsal-rapporten og dens forventede digests og antal, repoets commit — samt et **eksakt
filinventar**, kontrolleret som mængde. Inventaret er 4.4-runbookens liste minus #196's filer
(`interpretation_proposal_projection.{psql,sql}`, `interpretation_proposal_anon_projection.sql`,
`compare_interpretation_proposal_projection.py`) plus de nye: i repoet
`interpretation_transfer_digests.sql`, `interpretation_decision_fingerprint.sql`,
`build_transfer_pack.py`, `transfer_decide.sql` (07's SQL), `interpretation_promotion_targets.sql`
(med pakkescope); privat `07-decide.sh`, `08-bind.sh`, `decisions-keyed.json`, `pack-manifest.json`
og forslagsmanifestet. Det præcise antal fastlægges i planen; en manglende eller ekstra linje er STOP.
Clean-tree-kontrollen omfatter alle repo-stier i inventaret.

### 7.2 Fortrydelse (vej A)

Backuppen fra trin 3 gendannes, og ceremonien køres igen efter rettelse. Projektejerens afgørelser
ligger i pakken og genafspilles; intet skal afgøres igen. Skrivepausen sikrer, at intet andet går
tabt. Backuppen bliver det nye restorepunkt.

## 8. Færdigbevis og modenhed

- **Før ceremonien:** pakken bygget og kontrolleret (§4.4), inkl. genafspilning mod dumpet
  2026-10-01 med alle digests lig restoren.
- **Ceremonien:** `REHEARSAL_OK` på dagens dump; `VERIFY_OK` i prod med alle tre digests og antal lig
  pakken, kanonisk delta 0, uberørte tabeller og `anon` uændret.
- **Modenhed:** ingest og afgørelse ⇒ `produktionsverificeret` for 2018-20; promotion kun for
  bindingsdelen og markeret sådan (som 24/9 §7).

## 9. Test (test først)

- **pytest** for `build_transfer_pack.py`: 676 poster; dublet-nøgle; nøgle uden afgørelse; afgørelse
  uden nøgle; antal pr. metode og status; kanonisk `pack_sha256`; ingen noter eller værdier på stdout;
  ingen felter ud over de specificerede.
- **SQL-test** for fingeraftrykket: ændres ved ændret klausultekst, ordinal eller værdi; uændret ved nye
  tilfældige id'er.
- **SQL-test** for digest-filen: ens i to baser med samme indhold og forskellige id'er; ændres ved
  ændret status, evidens (uden for `pack_sha256`), mål-assertion eller klausuldisposition.
- **SQL-test** for `07`: `TRANSFER_DRIFT`/`CLAUSE_SET_DRIFT`; ukendt nøgle; to rækker for samme nøgle;
  forkert version; `already_applied` kun ved eksakt evidens; **ombyttet status mellem to nøgler med samme
  fordeling ⇒ STOP**; blandet tilstand ⇒ STOP; digest-afvigelse ruller tilbage; menneskelig og maskinel
  metode bevares.
- **SQL-test** for `08`: en accepteret, promoverbar fortolkning uden for pakken bliver ikke item;
  `BIND_SCOPE_DRIFT`; `binding_digest` ens i to baser.
- **Shell-tests** for `07`/`08`: flag, ukendte argumenter, GO-hash-mismatch.
- **Integration:** genafspilningen mod dumpet 2026-10-01 (§4.4) og ceremoniens rehearsal.

## 10. Afgrænsning

Ikke med: nye kanoniske fakta for de 41 accepterede uoverensstemmelser (trin 4-spec §11.3);
navneregel og ny promptversion (decisions 2026-10-03, kontraktfrys); oprydning af 138
navne-assertions med titelord; runnerens kvotefix; normaliseringsregel for `SKRIVEMAADE`;
fortrydelsesfunktion i databasen; deploy af #196; fejlmatrix (privat lag, decisions 2026-09-23).
