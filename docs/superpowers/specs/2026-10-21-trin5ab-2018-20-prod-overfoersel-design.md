# Trin 5a + 5b — 2018-20's identitetsvej, relationspersonas og bindinger i prod (overførsel)

**Status:** designudkast. Godkendt afsnit for afsnit i brainstormen 2026-10-20/21 (§3 grundidé, §5-§8 kontroller
og faser, §9-§11 test og afgrænsning). Afventer Fable-review med dom pr. afsnit. Spec'en er ikke et prod-GO:
hver ceremoni kræver sit eget GO (§8).

**Forudsætning:** forudsætningsleddet i §4 (»id'er af indholdet«) får sin egen spec, sit eget review og bliver
merget, før planen for denne overførsel skrives.

**Bygger på:** trin 4's overførsel (`docs/superpowers/specs/2026-10-03-trin4-2018-20-prod-overfoersel-design.md`,
`VERIFY_OK` 2026-10-05). Dens konventioner for ceremoni, private scripts, digests (`to_jsonb(…)::text`,
`COLLATE "C"`), tilstandsklassifikation og fortrydelse ved restore gælder, hvor intet andet står. Afsnit, der
afviger, er markeret **(ændret fra trin 4)**.

## 1. Adgangskrav (roadmap)

| Krav | Svar |
| --- | --- |
| Roadmapmål | Trin 5 (#150/#151), delspec 5a og 5b for 2018-20 |
| Værdikædeled | Identitetsafstemning (source persona → kanonisk person) og promotion af relationer (binding til familien) i prod |
| Leverancetype | Generel overførselsvej med DDL: forudsætningsled (deterministiske id'er), DDL-ceremoni, arbejdskørsel, genspilspakke og verifikation |
| Redaktionel/læserrettet værdi | Projektejerens ark og webkø-afgørelser fra 5a/5b bliver gældende i prod. Læseren ser kildehenvisningen for ægteskaber, forældrelinjer og børneflokke (253 kilderækker i beviset). Redaktørens identitetskø virker i prod. |
| Færdigbevis | `REHEARSAL_OK` for begge ceremonier og `VERIFY_OK` i prod med tabelhashes lig arbejdskørslens (§9) |
| Erstatter | De 8 led i restore-beviskæden som eneste bærer af 5a/5b (5a, 5b del 1, 2a, 2b-i, 2b-ii, navneregel v3, 2b-iii, #244). Spec'en for #244 §10's to genspilsveje bortfalder (§3, beslutning 4). |

## 2. Udgangspunkt

- **Beviskæden.** Roden er `daa2018f_20261001133125` (prod-dump 2026-10-01 + den fulde 2018-20-kørsel = prods
  indhold efter overførslen 2026-10-05). Herfra 8 led, hvert en kopi af det forrige, løftet med de da aktuelle
  migrationer. Sidste base er `daa244_bevis_20261020222244` (253 bindinger, 0 kanonisk delta i alle led).
- **Prod er uændret siden 2026-10-05** og står under skrivepause (projektejeren 2026-10-20). Prod har ingen
  5a/5b-DDL.
- **Prod og beviskæden har forskellige tilfældige id'er** (Fable-kortlægningen 2026-10-20, efterprøvet):
  - Prods `interpretation.id`, kørsels-, batch- og bindings-id'er stammer fra prods egen ingest 2026-10-05.
    Kun kanoniske id'er, klausulobservationer og 149b-personas er fælles.
  - Nye ægtefællepersonas får `gen_random_uuid()` (`schema.sql:15188`). Kandidat-, kontrol-, stikprøve-,
    batch- og bindings-id'er er tilfældige.
  - Kontrolprøven i 5b del 1 trækkes efter `sha256(candidate_run_id ‖ persona_id)` og kortenes visning efter
    `sha256(control_run_id ‖ candidate_id)` (`schema.sql:16140`, `:16188`). Prod ville trække en anden prøve.
  - Hashes som `set_sha256`, `preview_sha256` og `state_sha256` indeholder `interpretation_id` og/eller
    databasens identitet.
- **Deterministiske nøgler:** `interpretation_key`, ægtefællens `persona_key`
  (`record_key#rel-marriage-<post_offset>-<længde>`, uden ægteskabsnummer; `post_offset` er uændret af #244),
  `interpretation_party` (nøgle, rolle, version) og klassifikationshændelser (nøgle, løbenummer).
- **Web-fladen kører allerede `main`** (Vercel auto-deploy). Læserens kildelinje giver en tom liste, når
  `public_family_sources` mangler (`web/src/data/familySources.ts`). Redaktørens identitetskø fejler, indtil
  DDL'en er deployet, hvilket er uden betydning under skrivepausen. Der kræves ingen koordineret web-deploy.

## 3. Beslutninger (brainstorm 2026-10-20/21)

1. **Skrivepause og ingen drift.** Prod redigeres ikke, før overførslen er kørt. Afviger prod fra tilstanden
   2026-10-05 eller fra D0/D1 (§5), overføres intet.
2. **Kontrolprøven: id'er af indholdet (valg C).** Fravalgt:
   - **A:** ny kontrolprøve direkte i prod. Øvelsen kan ikke forudsige prøven, så en fejlet kontrol ville
     stoppe prod halvvejs, og alle ark skulle godkendes to gange.
   - **B:** genbrug af restore-kontrollen som pakke-afgørelser. Prod ville miste mærket »bekræftet maskinelt«
     (`family_corroboration`) for de maskinelt bekræftede ægtefæller.
3. **Øvelsen er facit (ændret fra trin 4).** Facit er ikke beviskæden. Det er en arbejdskørsel med den
   endelige kode på en restore af prods eget dump efter DDL'en (D1). Beviskæden bruges kun som
   indholdskontrol (§6.3).
4. **#244 opstår ikke i prod.** Den endelige kode skriver ægteskabsnumrene rigtigt fra start. Der er ingen
   rettelse, intet synlighedshul og ingen gamle payloads at genspille. Rettelsesvejen (`red_ret_aegteskabsnummer`)
   deployes, men bruges ikke. En beslutningspost noterer, at prod aldrig har haft de 4 fejlnumre.
5. **To ceremonier, hver med sit fortrydelsespunkt (ændret fra trin 4).** DDL-ceremonien har D0 som
   fortrydelsespunkt. Data-ceremonien har D1 og indeholder ingen DDL, så trin 4's forudsætning for en trofast
   restore gælder igen.
6. **Ingen menneskelig afgørelse gøres om.** Svar overføres fra beviskæden via deterministiske nøgler til de
   regenererede ark. Projektejeren godkender hvert regenereret ark (mekanisk). Den eneste nye menneskelige
   opgave er ét nyt kontrolark i arbejdskørslen.

## 4. Forudsætningsleddet: id'er af indholdet (egen spec)

Leddet skal levere følgende. Dets spec fastlægger mekanikken og efterprøver listen mod koden.

1. **Deterministiske id'er** for hver række, som 5a/5b's writere og RPC'er indsætter, og som indgår i en hash,
   et ark eller en senere skrivning. Mindst: ægtefællepersonas og deres omtaler, kandidatkørsler og
   kandidater, kontrolkørsel, stikprøve og hændelser, relationsafgørelsessæt, bindingsbatches og bindinger.
   Id'et afledes af kilde-id'et og rækkens indholdsnøgle (fx `persona_key`), aldrig af tid eller tilfældighed.
2. **Stikprøve og kortvisning** trækkes efter hashes af indhold og konfiguration (fx `input_sha256 ‖
   config_sha256 ‖ persona_key`), ikke efter tilfældige id'er.
3. **Hashes, som et menneske godkender** (rækkefiler, ark), indeholder ikke databasens identitet
   (`system_identifier`) og ingen tilfældige id'er. Maskinelle preview-/sæt-hashes må gerne indeholde den;
   de genberegnes i prod (§7).
4. **Kollision fejler lukket.** Et deterministisk id, der allerede findes med andet indhold, giver en
   fejlkode, aldrig en stille genbrug.
5. **Ingen ændring af eksisterende rækker.** 149b-personas, prods `interpretation.id` og alt fra trin 4
   beholder deres id'er.
6. **Opgraderingstest fra prods træ 2026-10-05.** De eksisterende opgraderingstests starter fra senere
   træer. Leddet tilføjer en test, der starter fra det træ, prod faktisk har.

## 5. Fase 0: før DDL

Måles i prod, læse-kun:

- **Ingen ændring siden 2026-10-05:** trin 4's tre digests (`interpretation_transfer_digests.sql`) er lig
  pakkens fra 2026-10-05, og der er 0 `change_set` med `created_at` efter overførslen.
- **Det kanoniske lag** er lig rodbasens (driftsbaselinen `transfer_baseline.sql`).
- **Ingen 5a/5b-spor:** de nye tabeller findes ikke. Postgres er version 15 eller nyere (`family.id` identity,
  2b-ii). `narrative_record_contract_version()` er 2. Der er 587 accepterede 149b-identiteter. Der findes en
  redaktionsprofil.
- **Dump D0** tages krypteret (Supabase free tier har ingen backup) og gendannelses-verificeres.
  Restore-hashen (`transfer_restore_hash.sql`) og katalogfingeraftrykket måles straks.

## 6. Faserne

### 6.1 DDL-ceremonien (GO 1)

| Trin | Handling | Skriver i prod |
| --- | --- | --- |
| 1 | Fase 0 (§5) | nej |
| 2 | **Øvelse** på en restore af D0: endelig `db-migrations.sql` + `db-rls.sql` i én transaktion, derefter én gang til (idempotens); `db-verify.sql` grøn; varigheden måles | kun lokalt |
| 3 | **Fortrydelsesøvelse:** D0 gendannes oven på den løftede øvelsesbase med netop den kommando, §8 bruger. Hele `pg_restore`-fejllisten læses. Bagefter: restore-hash og katalogfingeraftryk lig prods egne fra fase 0, og ingen 5a/5b-objekter tilbage. Restore er ikke trofast for nye objekter og standardrettigheder (memory 2026-09-17), så netop det øves, og fortrydelseskommandoen indeholder eksplicit fjernelse af de nye objekter. ⇒ `REHEARSAL_OK` (DDL) | kun lokalt |
| 4 | GO 1 | — |
| 5 | **Prod:** DDL i én transaktion; `get_advisors` (kun kendte mønstre, delta mod fase 0); `db-verify.sql` grøn; `anon` ser 0 nye rækker | DDL |
| 6 | **Dump D1** (krypteret, gendannelses-verificeret); restore-hash måles | nej |

### 6.2 Arbejdskørslen (lokalt, på en restore af D1)

Kæden køres igen led for led med den endelige kode, i beviskædens rækkefølge: 5a → 5b del 1 → 2a → 2b-i →
2b-ii → navneregel v3 (inkl. P-linjens afvisning) → 2b-iii. #244 udgår (beslutning 4).

- **Ark:** hvert ark regenereres. Projektejerens svar fra beviskæden overføres via `interpretation_key` og
  `persona_key` af et script, der kun printer tal og hashes. Kan et svar ikke overføres entydigt, stopper
  scriptet. Projektejeren åbner hvert regenereret ark og godkender det med en hash (hash-bundet som altid).
- **Kontrolarket (5b del 1)** er nyt: ny stikprøve trukket efter indholdet. Projektejeren svarer blindt.
  Fejler kontrollen, stopper overførslen, og det forelægges som en sag for sig.
- **Pakken:** hvert skrivende skridt gemmes i en ordnet pakke: dets SQL eller R-gateway-kald, dets
  inputartefakter (rækkefil og ark med hashes), den forventede indgangstilstand og den forventede rækkehash
  efter skridtet for hver tabel, skridtet rører (§7). Kørselstiden måles pr. skridt.
- **Levende-gaten:** kæden opretter 0 nye personer. Opretter arbejdskørslen alligevel en person, skal den
  have `levende IS FALSE`, og projektejeren forelægges den før pakken lukkes.

### 6.3 Indholdskontrol mod beviskæden

Arbejdskørslen skal reproducere beviskædens indhold på nøgleniveau, bortset fra en på forhånd opregnet liste
af forventede forskelle:

| Mål | Forventet |
| --- | --- |
| Bindinger (nøgle, familie) | Samme 253 par som `daa244_bevis_…`; ingen bindinger med `supersedes` fra #244 |
| Ægteskabsnumre i ægtefælleparter | Lig `daa244_bevis_…`'s gældende numre (de 4 er rigtige fra start) |
| Accepterede identiteter (persona_key → person) | Samme mængde |
| Klassifikationshændelser | Uden de 4 falske `ordinal_afvigelse` og de svar (`ordinal_beholdt`), der kun fandtes for dem; de 6 ægte afvigelser er uændrede |
| Kontrolkørslen | Ny stikprøve; resultatet skal bestå |
| Kanonisk delta | 0 |
| Nye personer | 0 |
| Kildevisning for `anon` | Samme rækker som `daa244_bevis_…` efter genbindingen |

Enhver anden forskel stopper arbejdskørslen og forelægges projektejeren. Den løses aldrig stiltiende.

### 6.4 Genspilsprøven (lokalt)

- Pakken genspilles på en **anden, frisk restore af D1** af genspilleren alene, uden menneskelig handling.
  Alle rækkehashes skal være identiske med arbejdskørslens efter hvert skridt. Det beviser, at id'erne er
  afledt af indholdet, og at prod vil give samme rækker.
- **Fortrydelsesøvelse:** D1 gendannes oven på den genspillede base. Bagefter er restore-hashen lig D1's.
  Data-ceremonien indeholder ingen DDL, så trin 4's restore-forudsætninger gælder (0 forældreløse rækker,
  `transfer_restore_preconditions.sql` asserteret).
- Alt bestået ⇒ `REHEARSAL_OK` (data).

### 6.5 Data-ceremonien (GO 2)

| Trin | Handling | Skriver i prod |
| --- | --- | --- |
| 1 | Indgang: restore-hash i prod = D1's, 0 `change_set` siden D1 (`NO_WRITE_SINCE_DUMP`) | nej |
| 2 | GO 2 | — |
| 3 | Genspil af pakken skridt for skridt. Hvert skridt er én transaktion, klassificerer sin indgangstilstand først og sammenligner sine rækkehashes med pakkens, før det næste starter | privat lag + kildevisning |
| 4 | `VERIFY_OK` (§9); derefter ophører skrivepausen | nej |

## 7. Verifikation

**Rækkehash pr. tabel.** En ny læse-kun repo-fil hasher hver 5a/5b-tabel (og de eksisterende tabeller, kæden
skriver i: `interpretation`, `interpretation_party`, `interpretation_promotion*`, `source_persona*`,
`source_mention`, klassifikations-, kandidat- og kontroltabeller) som `to_jsonb(række) - <tidsstempelkolonner>`
ordnet på primærnøgle med `COLLATE "C"`. Tidsstempler (`created_at`, `decided_at`, `promoted_at` m.fl.)
udelades. Evidensfelter med tidsstempler eller databasens identitet udelades efter en eksplicit liste i
filen. Planen fastlægger listen. Alt andet, også id'er, indgår.

**Ud over rækkehashene:**
- **Kanonisk delta 0:** driftsbaselinen før og efter i samme base.
- **Uberørt:** `transfer_untouched_hash.sql` udvides med alle tabeller, kæden skriver i. De øvrige skal være
  uændrede.
- **`anon`:** rettigheder uændrede ud over de nye funktioner; `anon` ser 0 private rækker og præcis de
  forventede rækker i `public_family_sources`.

**Tilstande pr. skridt (som trin 4 §5):** skridtets tabeller er lig pakkens indgangshash ⇒ skriv; lig
udgangshashen ⇒ `already_applied`; alt andet ⇒ `MIXED` og fortrydelse (§8). En delvis overførsel er aldrig
en accepteret sluttilstand.

## 8. GO og fortrydelse

**GO 1** binder: D0's hash, fase 0's målinger, katalogfingeraftrykket, DDL-øvelsens rapport (idempotens,
varighed, fortrydelsesøvelse), repoets commit og hashes for `db-migrations.sql`, `db-rls.sql` og
`db-verify.sql`.

**GO 2** binder: D1's hash og restore-hash, pakkens hash (over skridtenes kanoniske JSON), alle forventede
rækkehashes, arkhashes, genspilsprøvens rapport (inkl. fortrydelsesøvelse og varighed pr. skridt), repoets
commit og et eksakt filinventar for scripts og repo-filer, kontrolleret som mængde.

**Fortrydelse:**
- **DDL-ceremonien:** fejler transaktionen, er intet skrevet. Opdages et problem efter commit, gendannes D0
  med den øvede kommando (§6.1 trin 3), og fase 0's målinger skal derefter holde.
- **Data-ceremonien:** `MIXED`, en hash-afvigelse efter commit eller et STOP, der ikke kan rettes ved at køre
  et atomart skridt igen, ⇒ D1 gendannes med den øvede kommando. Pakken genspilles efter rettelse.
  Projektejerens svar ligger i pakken, så intet skal afgøres igen.

## 9. Færdigbevis og modenhed

- **Før ceremonierne:** forudsætningsleddet merget; overførslens scripts og tests grønne i CI.
- **DDL:** `REHEARSAL_OK` (DDL) og en verificeret DDL i prod (`get_advisors`, `db-verify`).
- **Data:** arbejdskørslen bestået inkl. indholdskontrollen (§6.3), `REHEARSAL_OK` (data) og `VERIFY_OK` i
  prod: alle rækkehashes lig arbejdskørslens, kanonisk delta 0, uberørte tabeller uændrede, `anon` som
  forventet, 0 nye personer.
- **Modenhed:** 5a og 5b for 2018-20 ⇒ `produktionsverificeret`. #244 noteres som »opstod aldrig i prod«.

## 10. Test (test først)

- **Forudsætningsleddet** (i dets egen spec): samme indhold i to baser med forskelligt `system_identifier`
  giver samme id'er, samme stikprøve og samme kortrækkefølge; ændret indhold giver nye id'er; kollision
  fejler lukket; opgradering fra prods træ 2026-10-05.
- **Rækkehashen:** ens i to baser med samme indhold; ændres ved én ændret værdi og ved ombytning af to
  rækker; uafhængig af tidsstempler og locale.
- **Svaroverførslen til regenererede ark:** entydig overførsel; et svar uden mål og et mål uden svar stopper.
- **Pakkebygger og genspiller:** forkert indgangstilstand, ukendt skridt, hash-afvigelse, afbrud midt i et
  skridt (ruller tilbage), `already_applied`, GO-hash-mismatch, ukendte argumenter og manglende
  `--jeg-mener-det`.
- **Integration:** genspilsprøven (§6.4) og begge fortrydelsesøvelser.

## 11. Afgrænsning

Ikke med:
- **#240** (dobbelte familier; 7 ægteskaber står fortsat fejlet lukket);
- **#248** (2 familienumre modsagt af bogens »N°«);
- **5c** (placement/membership);
- de 2 børnepåstande, der står `proposed`;
- `mention.place`;
- nye kanoniske personer (0 i kæden);
- 1939.

**Kendt risiko:** arbejdskørslen kan afsløre afvigelser fra beviskæden, som ikke står i §6.3. Hver af dem
stopper kørslen og forelægges projektejeren.

**Rækkefølge:**
1. Forudsætningsleddets spec, review, implementering og merge.
2. Overførslens plan, scripts og tests.
3. Fase 0 og GO 1.
4. Arbejdskørslen med projektejerens ark.
5. Genspilsprøven og GO 2.
