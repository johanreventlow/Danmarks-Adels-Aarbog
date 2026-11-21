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
6. **Fortrydelse af genimport påvirkes ikke** (Codex runde 2). Genimportens kvittering (`post_activation_receipts`) er
   editor-kuvertens `state_sha256` for **kladden** lige efter aktivering, og `red_reverse_1939_v50_reimport`-vejen kræver
   netop den tilstand (`schema.sql:5823`). Er biografien siden publiceret, kan genimporten allerede ikke fortrydes ad
   den vej; er den stadig en kladde, ændrer hændelser intet (låsen gælder kun publicerede tekster). `red_reverse_reimport_
   publication` binder identitetsversion, ikke tilstand. Hændelser ændrer derfor ingen genimport-kvittering. *Undtagelse
   (punkt 6a, projektejeren 21/11):* ville fortrydelsen ændre en kladdes tekst under hændelser, afvises den som før A2.
6a. **Fortrydelse af narrativhændelser** (Codex kode-runde 1 og 2, projektejeren 2026-11-21). Før A2 stoppede
   hash-drift enhver fortrydelse efter en ny hændelse; nu læser `private.reverse_narrative_publication_event` og
   historikkens `can_reverse` låsen direkte. Med hændelser på narrativet afvises (`NARRATIVE_RECORD_DERIVED_EVENTS_PRESENT`)
   en fortrydelse, der **ændrer teksten**, eller som **gør en ikke-kladde til kladde igen** (fortrydelse af `published`:
   kladden kunne få ny tekst og publiceres under de gamle hændelser). Fortrydelse fra kladde til kladde **uden
   tekstændring** (fx genimport-fortrydelsen i personsletningens S26), af `withdrawn` (genpublicerer samme tekst), af
   `draft_created` og af legacy-hændelser er tilladt. Kladde→kladde med tekstændring afvises (projektejeren: som før A2).
   Kladde-gem efter en tilbagetrækning opretter et nyt narrativ, så de gamle hændelser følger ikke med.
   `red_upsert_narrativ` (legacy-vejen, ikke-DAA-kilder) har aldrig tjekket hændelser og er uberørt af A2.
7. **Udrulningsinvariant:** med 0 hændelser i prod er `text_editable` uændret for alle bindinger, så hverken
   `publication_state`, editor-tokens eller kvitteringer skifter hash ved udrulningen. Det bevises (§6).

### 4.2 Y3 — `public.public_haendelse_feed`

```
public.public_haendelse_feed(p_fortsaet text DEFAULT NULL,
                             p_max_narrativer int DEFAULT 150, p_max_raekker int DEFAULT 1000)
  RETURNS jsonb   -- {rows:[…], narrativer:[{id,source_id,side}], sources:[{id,udgave}], naeste: text | null}
  LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog
```

- **Rækkefiltre på hver returneret række** (samme regel som `haendelse.anon_read`): `subjekt_type='person'`,
  `feed_status<>'skjult'`, `entitet_offentlig(subjekt_type, subjekt_id)` **og** at rækkens eget narrativ er godkendt af
  gaten. Et narrativ gøres aldrig til »godkendt for alle dets rækker«: rækker, der falder på et filter, udelades, også når
  andre rækker på samme narrativ er med (Codex 1). `narrativer` og `sources` afledes kun af de returnerede rækker.
- **Uigennemsigtigt bladremærke** (Codex runde 2; projektejeren 2026-11-21): den interne cursor `(narrative_id, id)`
  kan pege på en skjult kandidat og må derfor aldrig udleveres i klartekst. `naeste` er
  `extensions.pgp_sym_encrypt(cursor-json, nøgle)` (base64), hvor nøglen ligger i en privat tabel
  (`private.feed_cursor_noegle`, én række, genereret med `gen_random_bytes(32)` ved DDL'en, ingen grants). pgp_sym's
  integritetskontrol (MDC) afviser et manipuleret mærke: dekrypteringsfejl eller ugyldig form → `FEED_CURSOR_INVALID`.
  Nøglen roteres ved at udskifte rækken (gamle mærker bliver ugyldige; klienten starter forfra).
  Nøglen beskytter kun mærkets uigennemsigtighed (ingen data er krypteret med den). Den ligger i `private`-data og
  følger derfor med i projektejerens private læsedumps; den er forskellig pr. base (genereres ved DDL'en). Lækkes den,
  afslører den højst interne positioner; rotation er én UPDATE (Task 2, 2026-11-21).
- **Intern cursor over `(narrative_id, id)`**, strengt stigende. Et kald tager kandidatrækker efter cursoren i den orden og
  stopper ved det første af: `p_max_raekker` rækker eller `p_max_narrativer` forskellige narrativer (et narrativ kan
  deles over to kald; cursoren peger midt i det). Begge lofter er bundne (fx ≤ 200 / ≤ 2000; ugyldig værdi → fejl), så
  arbejdet pr. kald er begrænset både i gate-kald og rækker (Codex 4).
- Gaten kaldes **én gang pr. forskelligt narrativ i bidden** (MATERIALIZED CTE). RLS-politikken bevares uændret som
  forsvar for direkte tabellæsning.
- `naeste` = cursoren efter den sidste **kandidat** (ikke den sidste returnerede række), når der kan være flere; ellers
  null. En bid kan derfor lovligt returnere `rows=[]` med `naeste` sat; **klienten stopper kun, når `naeste` er null**
  (Codex 3).
- Rækkernes felter er de samme, som klienten læser i dag (`haendelser.ts:44`), inkl. `fact_id`/`relation_id`.
- GRANT EXECUTE til anon og authenticated; redaktionens egne flader (`redaktionRead.ts`) ændres ikke.
- **Alle roller, også redaktøren, får anon-reglen** (projektejeren 2026-11-21, `decisions.md`). En redaktørgren som i
  `public_person_facts` blev implementeret og forelagt, men fravalgt: feedet er en læserflade, og redaktøren ser alt i
  redaktionsfladerne og via tabellens `redaktion_read`. Redaktørens feed bliver dermed snævrere end i dag. Funktionen
  afhænger ikke af kalderens rolle (db-verify).
- Cursor-scannet bruger det nye indeks `ix_haendelse_narrative_id (narrative_id,id)`. Nøgletabellen står på
  personsletningens undtagelsesliste (`person_purge_undtagelser`: teknik, ingen P-sti).
- `feedGrundlag.ts:34` (`haendelse.subjekt_id`) læser fra samme funktion i stedet for tabellen.
- Lofterne vælges ud fra målingen (§6): det tungeste kald skal holde sig under 1,5 s som anon på stand-in.
- **Kendt begrænsning (Codex r1 fund 2, projektejeren 2026-11-21):** bladremærket binder kun positionen
  `(narrative_id,id)`, og hvert kald læser sit eget snapshot. Udskiftes hændelsesprojektionen midt i en bladring (fx en
  genkørsel af #130), kan den ene sidevisning blande gamle og nye kort. Der lækkes intet (hver række gates), næste
  indlæsning er korrekt, og den gamle `range`-bladring havde samme egenskab. En revisionsværdi i mærket (triggere på
  `haendelse`) er fravalgt som uforholdsmæssig.

### 4.3 Klienter

- **web:** `fetchHaendelseRows` og `feedGrundlag` bladrer via RPC'en, til `naeste` er null.
  - `fetchHaendelseRows` (hændelseskort) forbliver **tolerant**: fejl → tom liste med advarsel, som i dag.
  - `fetchNaevntGrundlag` i `feedGrundlag.ts` forbliver **fail-closed**: enhver sidefejl kastes, også efter en vellykket
    side; et delvist resultat må aldrig gøre en person med hændelser til »kun nævnt« (Codex 2).
  - Tests (vitest): bladring over en tom side med `naeste` sat, stop ved `naeste=null`, fejl efter første side
    (kastes i `feedGrundlag`, tolereres i hændelseskort), tom tabel.
  - **Delt bladring (tilføjet Task 3, 2026-11-21):** feedet starter hændelseskort og »Nævnt«-grundlag samtidig;
    de deler én *igangværende* bladring pr. bruger (bruger-id, ellers gæst), så gaten ikke kører to gange over
    korpusset. Det er ikke en cache: når bladringen er afsluttet, henter næste kald forfra. Bindingen til brugeren
    er et værn: RPC'en er i dag ens for alle roller, men en senere rolleforskel må ikke kunne arves over logud/login. En fejl afviser begge kaldere (kortene tolererer, grundlaget
    kaster).
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

0a. **Bladremærket** — mærket indeholder ingen læsbare id'er; et ændret eller fremmed mærke afvises
   (`FEED_CURSOR_INVALID`); et mærke, der peger på en skjult kandidat, afslører den ikke.
0. **Rækkefiltre** — negativ fixture: ét synligt narrativ med både en tilladt række, en `skjult` række og en række med
   ikke-offentligt subjekt; kun den tilladte returneres, og `narrativer`/`sources` nævner kun dens kilde.
1. **Synlighed uændret** — mængden af anon-synlige narrativ-**id'er** (ikke antal; legacy med) er identisk ved fire
   punkter på en stand-in fra prod-dump: (a) før DDL, (b) efter DDL, (c) efter en syntetisk hændelses-load på alle
   publicerede narrativer (#130-volumen, fx 5 pr. narrativ), (d) efter sletning af den sidste hændelse på et udvalg.
2. **Hashes uændret ved udrulning** — for alle bindinger er `publication_state`-hash og editor-`state_sha256` ens før og
   efter DDL; alle `post_activation_receipts` matcher stadig.
3. **Låsen og kvitteringerne efter hændelsesændringer** (Codex 5) — for første og sidste hændelse:
   - `publication_state`-hashen er uændret (synligheden følger ikke hændelser);
   - på en publiceret, tilladt binding: `text_editable`/`allowed_actions` og editor-`state_sha256` skifter, og revise
     afvises med `NARRATIVE_RECORD_DERIVED_EVENTS_PRESENT`; uden hændelse tilladt;
   - på en kladde: editor-`state_sha256` og en kladdebetinget aktiveringskvittering er uændrede, og reversal virker;
   - R30-tilfældene i `test-person-purge.sql` (S26 ~884-980, ~2475) får konkrete nye forventninger efter det valgte
     prædikat (§4.1 pkt. 5);
   - fortrydelse af genimport (§4.1 pkt. 6): en kladde fra en aktiveret genimport får en hændelse, og
     `red_reverse_1939_v50_reimport` virker stadig.
4. **Y3** — efter (c): hvert RPC-kald som anon med `statement_timeout=3s` < 1,5 s, også med skæv fordeling (ét narrativ
   med den største forventede fan-out fra #130 og lange klausuler); samlet bladring giver præcis de hændelses-id'er,
   RLS-politikken ville give, **uden dubletter** (antal = antal forskellige); en bid, hvor alle kandidater afvises,
   efterfølges af en tilladt bid; den gamle direkte tabellæsning måles til sammenligning.
5. **Opgraderingsvej** — test fra en prod-formet base (ikke kun frisk `schema.sql`, jf. memory om signaturændringer).
6. CI grøn; prod-DDL via runner (standin → apply → efterkontrol → fortryd-definitioner gemt), projektejeren kører apply.

## 7. Udrulning

**Deploy-området** er blokkene `review37-a2` og `review37-y3` i `db-migrations.sql` + `db-rls.sql` i én transaktion
(prod-runneren udtrækker navngivne blokke; bevis: `tests/sql/test-review37-a2y3-upgrade.sh` fra 8bca497c).

DDL før merge: web-ændringen kalder en ny RPC; findes den ikke, giver hændelseskortene tom liste med advarsel, men
`feedGrundlag` kaster (fail-closed), og »Nævnt i Aarbogen«-kortene udebliver, til DDL'en er i prod. Derfor DDL → merge.
**Adgangskrav for #130** (Codex 6): A2 og Y3-RPC'en i prod, webklienten med den nye vej udrullet på Vercel, og et
efterkontrolleret anon-kald gennem klientens nye vej. Først derefter må #130 køres.

## 8. Roadmapets adgangskrav

1. **Mål:** review 37-backloggen (decisions 2026-11-20), forudsætning for #130; uden for genimportens aktive mål.
2. **Værdikædeled:** publicering → læser (synlighed og feed).
3. **Leverance:** generel (alle udgaver).
4. **Værdi:** #130 kan køres uden at biografier forsvinder; forsidens hændelseskort indlæses inden for anon-grænsen.
5. **Bevis:** §6.
6. **Erstatter:** `has_haendelse` som publiceringstilstand; feedets direkte tabellæsning af `haendelse`.
7. **Review-budget:** se hovedet.
