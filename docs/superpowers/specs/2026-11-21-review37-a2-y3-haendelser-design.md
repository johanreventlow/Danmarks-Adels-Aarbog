# Review 37 A2 + Y3 — hændelser skjuler ikke biografier, og feedet holder anon-grænsen

**Status:** spec, afventer projektejerens godkendelse
**Review-budget:** 2 Codex-runder (gpt-6.1-sol) på spec'en, 2 på implementeringen; derefter foreslås en regel frem for
flere runder (erfaring fra P1+P2). Overskridelse kræver én linje i `docs/decisions.md` (B13).
**Gren:** `fix/review37-haendelse-db` · **Issue:** #397 (A2, Y3) · **Blokerer:** #130

## 1. Problem

**A2.** En publiceret biografi vises kun, hvis dens nuværende `narrative_publication_state` er identisk med den
tilstand, publiceringshændelsen attesterede (`person_daa_narrative_publication_allowed`, `schema.sql:17263`). Tilstanden
rummer `has_haendelse` (top-niveau og `narrative.has_haendelse`). Den første kørsel af `/daa-haendelser` (#130) vender
feltet fra false til true for alle narrativer, der får hændelser, så de forsvinder lydløst fra personsiden. Legacy-tekster
(`grandfathered_publication`) har ingen genvalideringsvej.

**Y3.** `haendelse.anon_read` (`db-rls.sql:494-499`) indeholder `EXISTS (SELECT … FROM narrative)`, som udløser
narrativets RLS, dvs. hele publiceringsgaten, **pr. hændelsesrække**. Feedet (`web/src/data/haendelser.ts:44`,
`feedGrundlag.ts:34`) henter alle rækker side for side. Ved 1000 rækker pr. side ≈ 5 s > anon-grænsen 3 s; kaldet fejler,
og feedet udelader stille kortene.

## 2. Målt i prod (2026-11-21, læse-kun, kun antal)

| Mål | Værdi |
|---|---|
| `haendelse`-rækker | **0** |
| Publiceringshændelser: `after_state.has_haendelse` / `narrative.has_haendelse` | false/false 4.686, false/null 11 (alle false) |
| Bindinger | published 1.094, draft 46, withdrawn 11 |
| Legacy-grundlinjer (`baseline_state.has_haendelse`) | alle false (grandfathered 7, migrated 541, withdrawn 2) |
| Narrativer i alt / gaten siger ja | 1.166 / 1.102 |
| Gaten for alle 1.166 narrativer (som postgres) | 6,28 s ≈ **5,4 ms pr. narrativ** |

## 3. Beslutninger (projektejeren 2026-11-21)

**A2 — feltet låses til `false`.** `has_haendelse` bliver i `publication_state` (top-niveau og `narrative`), men har
altid værdien `false` og dokumenteres som udfaset. Fordi alle gemte tilstande i prod har `false`, forbliver hver
attesteret tilstand identisk ved udrulning, og gaten røres ikke. *Fravalgt:* at sammenligne tilstande uden feltet (ændrer
den sikkerhedskritiske gate og dens hash-sammenligninger flere steder); at fjerne feltet (gør alle 4.697 attesterede
tilstande forskellige fra nutiden og skjuler alt).

**Y3 — ny feed-funktion i bidder.** En SECURITY DEFINER-RPC returnerer hændelser for højst N narrativer pr. kald og kører
gaten én gang pr. narrativ. Klienterne (web og mobil) bladrer, til der ikke er flere. Ingen cache af
synlighedsbeslutningen. *Fravalgt:* server-side udvælgelse af forsidens kort (større omlægning); gemt
synlighedsbeslutning (cache med mange indgange, kan drive).

## 4. Design

### 4.1 A2 — `has_haendelse` er ikke publiceringstilstand

1. **`private.narrative_publication_state`** (`schema.sql:15260`): begge `has_haendelse`-nøgler sættes til konstant
   `false`; `EXISTS(haendelse)`-beregningen fjernes. Kommentar: udfaset (review 37 A2), altid false; hændelser påvirker
   ikke synlighed.
2. **Legacy-tilstanden:** den levende krop er `private.narrative_legacy_candidate_publication_state` (`schema.sql:17698`;
   `narrative_legacy_publication_state` ved 17779 kalder den og afløser den døde kopi ved 15819, jf. A13). Samme ændring.
   Den døde kopi ved 15819 får samme ændring, så ingen tekst i filen viser den gamle regel (fjernes ikke her, A13).
3. **Ny hjælper `private.narrative_har_haendelse(p_narrative_id bigint) RETURNS boolean`** (STABLE, `EXISTS` på
   `haendelse`), REVOKE fra PUBLIC/anon/authenticated. Den er den eneste kilde til hændelseslåsen.
4. **Låsen bevares, læst direkte:**
   - `narrative_record_state` (`schema.sql:15776`): `v_text_editable := v_publication_allowed AND NOT
     private.narrative_har_haendelse(<narrativ>)`.
   - `mutate_person_narrative_record` revise (`schema.sql:16458`): `NARRATIVE_RECORD_DERIVED_EVENTS_PRESENT`, hvis
     hjælperen siger true.
5. **Kvitteringer og R30.** `text_editable`/`allowed_actions` indgår i editor-kuvertens `state_sha256`
   (`schema.sql:15796-15812`), som også er genimportens `post_activation_receipts`. Tilføjes eller fjernes den sidste hændelse
   på en publiceret, tilladt binding, ændres kvitteringen fortsat; for kladder ændres den ikke længere. R30-prædikatet i
   `private.person_purge_fortrydelse` (`schema.sql:~23759`) skal være en **overmængde** af de faktiske ændringer
   (fail-closed). Implementeringen vælger mellem at beholde prædikatet (overmængde, kan melde tab for kladder) og at
   indsnævre det til aktive `published`-bindinger; valget og begrundelsen skrives i planen. Kommentaren opdateres.
6. **Udrulningsinvariant:** med 0 hændelser i prod er `text_editable` uændret for alle bindinger, så hverken
   `publication_state`, editor-tokens eller kvitteringer skifter hash ved udrulningen. Det bevises (§6).

### 4.2 Y3 — `public.public_haendelse_feed`

```
public.public_haendelse_feed(p_efter_narrative_id bigint DEFAULT NULL, p_antal_narrativer int DEFAULT 150)
  RETURNS jsonb   -- {rows:[…], narrativer:[{id,source_id,side}], sources:[{id,udgave}], naeste: bigint|null}
  LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog
```

- Kandidater: `DISTINCT narrative_id` fra `haendelse` med `subjekt_type='person'`, `feed_status<>'skjult'`,
  `entitet_offentlig(subjekt_type, subjekt_id)` og `narrative_id > coalesce(p_efter, -∞)`, ordnet stigende, højst
  `p_antal_narrativer` (loft fx 200; ugyldig værdi → fejl).
- Gaten kaldes **én gang pr. kandidat** (MATERIALIZED CTE): `public.person_daa_narrative_publication_allowed(id)`.
  Samme regel som RLS-politikken; politikken bevares uændret som forsvar for direkte tabellæsning.
- Rækkernes felter er de samme, som klienten læser i dag (`haendelser.ts:44`). Feltet `fact_id`/`relation_id`
  med som i dag. `naeste` = sidste kandidat-id, når der kan være flere, ellers null.
- GRANT EXECUTE til anon og authenticated; redaktionens egne flader (`redaktionRead.ts`) ændres ikke.
- `feedGrundlag.ts:34` (`haendelse.subjekt_id`) læser fra samme funktion i stedet for tabellen.
- Bidstørrelsen vælges ud fra målingen (§6): det tungeste kald skal holde sig under 1,5 s som anon på stand-in.

### 4.3 Klienter

- **web:** `fetchHaendelseRows` og `feedGrundlag` bladrer via RPC'en; fejl i ét kald giver som i dag tom feed med
  advarsel (tolerant). Tests (vitest) for bladring og tom tabel.
- **mobil:** samme ændring i `mobile/src/data/haendelser.ts` (dev-only, paritet).
- Delt logik i `packages/core` kun hvis den allerede deles; ellers ingen ny flytning.

## 5. Berørte filer

`schema.sql` (§4.1-4.2), `db-migrations.sql` (idempotent kopi af alle ændrede funktioner + den nye), `db-rls.sql`
(GRANT/REVOKE for de nye funktioner), `db-verify.sql` (asserts), `tests/sql/test-narrative-record-contract.sql`
(has_haendelse-fixturer og task5-revalideringstesten skal afspejle udfasningen), `tests/sql/test-person-purge.sql`
(R30-tilfældene ~884-980, ~2475-2506), Python-definitionsvagten (`test_identity_guard_static.py` ALLOWLIST tæller
definitioner pr. fil), `web/src/data/{haendelser,feedGrundlag}.ts`, `mobile/src/data/haendelser.ts`, docs
(`database-current-state.md`, `changelog.md`, `decisions.md`).

## 6. Færdigbevis

1. **Synlighed uændret** — mængden af anon-synlige narrativ-**id'er** (ikke antal; legacy med) er identisk ved fire
   punkter på en stand-in fra prod-dump: (a) før DDL, (b) efter DDL, (c) efter en syntetisk hændelses-load på alle
   publicerede narrativer (#130-volumen, fx 5 pr. narrativ), (d) efter sletning af den sidste hændelse på et udvalg.
2. **Hashes uændret ved udrulning** — for alle bindinger er `publication_state`-hash og editor-`state_sha256` ens før og
   efter DDL; alle `post_activation_receipts` matcher stadig.
3. **Låsen virker** — revise af en publiceret tekst med hændelse afvises (`NARRATIVE_RECORD_DERIVED_EVENTS_PRESENT`);
   uden hændelse tilladt.
4. **Y3** — efter (c): hvert RPC-kald som anon med `statement_timeout=3s` < 1,5 s; samlet bladring giver præcis de
   hændelser, RLS-politikken ville give (mængdesammenligning som postgres med gaten); den gamle direkte tabellæsning
   måles til sammenligning.
5. **Opgraderingsvej** — test fra en prod-formet base (ikke kun frisk `schema.sql`, jf. memory om signaturændringer).
6. CI grøn; prod-DDL via runner (standin → apply → efterkontrol → fortryd-definitioner gemt), projektejeren kører apply.

## 7. Udrulning

DDL før merge eller samtidig: web-ændringen kalder en ny RPC; findes den ikke, giver `haendelser.ts` tom feed med
advarsel (tabellen er alligevel tom). Derfor kan merge ske før DDL uden nedetid, men rækkefølgen DDL → merge
foretrækkes. #130 må først køres, når A2 er i prod.

## 8. Roadmapets adgangskrav

1. **Mål:** review 37-backloggen (decisions 2026-11-20), forudsætning for #130; uden for genimportens aktive mål.
2. **Værdikædeled:** publicering → læser (synlighed og feed).
3. **Leverance:** generel (alle udgaver).
4. **Værdi:** #130 kan køres uden at biografier forsvinder; forsidens hændelseskort indlæses inden for anon-grænsen.
5. **Bevis:** §6.
6. **Erstatter:** `has_haendelse` som publiceringstilstand; feedets direkte tabellæsning af `haendelse`.
7. **Review-budget:** se hovedet.
