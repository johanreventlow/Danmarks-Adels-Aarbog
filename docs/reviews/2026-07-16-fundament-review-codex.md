# Fundament-review — Danmarks Adels Aarbog

**Dato:** 2026-07-16
**Scope:** database, RLS/GDPR, R-ETL, app-datalag, redaktionel skrivevej og CI.
**Metode:** read-only review af repoet; read-only katalog- og aggregatqueries mod prod; en midlertidig PostgreSQL 17-base under `/tmp` til at anvende `schema.sql` + `db-migrations.sql` + `db-rls.sql`; lokale tests og typechecks. Ingen DDL/DML eller `red_*`-kald blev kørt mod prod. Ingen data om identificerbare levende personer er gengivet.

## Kort svar

Fundamentets centrale idéer er gode: evidenslaget, den polymorfe fact/relation-model, server-side anon-RLS, versionering og det nu delte `packages/core` er langt stærkere end en typisk PoC. Det er også empirisk verificeret, at anon i prod ser 853 personer og 0 levende, og at de stikprøvede FK-/orphan-invarianter aktuelt har 0 databrud.

Men fundamentet er **ikke sikkert eller skalerbart nok til foreningens samlede data endnu**. Der er tre P0'er: en intern `SECURITY DEFINER`-slettehelper kan eksekveres af `anon`; enhver authenticated-bruger kan læse alle 70 ikke-private levende personer; og den normale reset-loader kan kaskadeslette bruger-/redaktionsdata, som den ikke genskaber. Hertil kommer en klient-side helgraf, en ikke-idempotent import, manglende slægts-/udgavenamespace og flere steder hvor evidens/usikkerhed udglattes.

## Prioriteret fundliste

Dette er den eneste fundliste. Faseafsnittene længere nede tilføjer ikke nye fund; de samler evidensen og refererer til numrene her.

### P0 — farligt nu

#### F-01 · Fase 2 · `anon` kan kalde en intern SECURITY DEFINER-helper, der hard-sletter relationer og evidens

**Evidens: verificeret.** Prod-katalogqueryen

```sql
SELECT p.proname,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_exec,
       p.prosecdef,
       p.proconfig
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname='_delete_relation_evidence';
```

gav `anon_exec=true`, `prosecdef=true`, `search_path=public`. Funktionen har bevidst **ingen** rolle-gate og sletter `citation`, `conclusion`, `assertion`, `note` og selve `relation`: `schema.sql:946-959`. `db-rls.sql:436-446` giver authenticated adgang til `red_*`, men revokerer ikke default `PUBLIC EXECUTE` fra denne interne helper. `db-verify.sql` søger ikke efter funktions-ACL'er eller denne helper.

**Fejlscenarie:** en klient med den offentlige anon-nøgle kalder `/rest/v1/rpc/_delete_relation_evidence` med et kendt/gættet relations-id. Funktionen kører som ejer, omgår tabel-RLS og sletter relationens evidens uden rollecheck og uden `change_set`.

**Anbefaling:** **lille, akut.** `REVOKE ALL ... FROM PUBLIC, anon, authenticated` på alle interne mutatorer; grant kun til funktions-/ejerrollen. Tilføj en katalogassert, der kræver, at kun en eksplicit allowlist er API-eksekverbar. Overvej også at flytte interne helpers ud af det eksponerede `public`-schema.

#### F-02 · Fase 2 · authenticated-tier lækker alle ikke-private levende personer uden samtykkegate

**Evidens: verificeret.** Følgende blev kørt i `BEGIN READ ONLY`:

```sql
SET LOCAL ROLE anon;
SELECT count(*), count(*) FILTER (WHERE levende), count(*) FILTER (WHERE privat) FROM person;
-- 853, 0, 0

SET LOCAL ROLE authenticated;
SELECT count(*), count(*) FILTER (WHERE levende), count(*) FILTER (WHERE privat) FROM person;
-- 923, 70, 0
```

De aktive policies matcher resultatet: authenticated filtrerer kun `privat`, ikke `levende` eller samtykke (`db-rls.sql:349-406`). Samme tier åbner facts, relationer, narrativer og evidens for disse personer. Dette modsiger den autoritative privatlivsmodel (`CLAUDE.md:35`, `datamodel-oversigt.md:108-112`) og operatørguidens påstand om, at authenticated-tier ikke er live og at levende er skjult uden redaktørrolle (`docs/database-current-state.md:65-73`). App-loaderne har heller ingen ekstra levende-filter (`web/src/data/model.ts:57-63`, `mobile/src/data/load.ts:128-136`), men fejlen er server-side.

**Fejlscenarie:** enhver konto med Supabase-rollen `authenticated` — ikke nødvendigvis et godkendt medlem af den rette slægt — henter person-, familie- og evidensdata for alle 70 levende, så længe `privat=false`.

**Anbefaling:** **lille/mellem, akut.** Luk authenticated-tier fail-closed til samme regel som anon, indtil en eksplicit medlems-/samtykke-/slægtsautorisation findes. Tilføj rollebaserede prod-smoketests med forventet `visible_living=0` for alle ikke-privilegerede roller.

#### F-03 · Fase 4 · dokumenteret `--reset` kan kaskadeslette brugerdata uden at guarden opdager det

**Evidens: verificeret.** Reset-listen indeholder bl.a. `person` og `source` (`.claude/skills/daa-extract/scripts/load_daa.R:71-78`), og `--reset` udfører `TRUNCATE ... CASCADE` (`load_daa.R:235-255`). Guarden ser kun efter `change_set.operation` med prefix `red_` (`load_helpers.R:13-18`). `profiles` og `bookmark` refererer `person`, mens `suggestion` refererer `source` (`schema.sql:281-311`). Fixup genskaber kun én hardkodet profil (`post_load_fixup.R:57-60`), ikke øvrige profiler, bogmærker eller forslag.

**Fejlscenarie:** basen har flere brugere/bogmærker/forslag, men ingen `red_*`-change-set. Operatøren følger den dokumenterede reset-vej; guarden godkender; `CASCADE` tømmer de afhængige tabeller; data kommer ikke tilbage. På free tier kan tabet være uigenkaldeligt.

**Anbefaling:** **mellem/stor.** Fjern prod-reset som normal ingestion-strategi. Importér i source-scoped staging og reconcile atomisk. Som straksværn: fail-closed hvis nogen ikke-loader-ejede afhængige tabeller er ikke-tomme, kræv verificeret backup/run-id, og gør reset til en særskilt controller-gated procedure.

### P1 — skaleringsklipper og dyre fundamentfejl

#### F-04 · Fase 1 · prod, `schema.sql` og migrationsfilen er ikke én reproducerbar sandhed

**Evidens: verificeret.** En katalogsammenligning mellem prod og en lokal PostgreSQL 17-base bygget fra `schema.sql` + `db-migrations.sql` + `db-rls.sql` fandt den komplette driftliste i Fase 1 nedenfor. Kort fortalt mangler prod to assertion-kolonner, to constraints, to indekser, ét view, fem funktioner og de aktuelle bodies for 12 eksisterende funktioner; prod har omvendt `narrative.fts` + GIN-indeks, som kun står udkommenteret i `schema.sql:829-832`.

Deploy-stien er heller ikke reproducerbar: `schema.sql` blev anvendt rent, men `db-migrations.sql` aborterede ved `:2344-2384`, fordi en indlejret data-backfill bruger `SELECT ... INTO STRICT` og kræver præcis én eksisterende `DAA 2018-20`-source. Efter en syntetisk lokal source kunne resten anvendes. Dette strider mod filens erklærede idempotente afstemningskontrakt (`db-migrations.sql:1-8`).

**Fejlscenarie:** en operatør tror, at migrationsfilen atomisk afstemmer en base. Den stopper midtvejs på en frisk/anderledes base; uden single transaction kan basen være delvist opgraderet, og app/RPC-kontrakter kan ligge mellem versioner.

**Anbefaling:** **mellem.** Skil schema-DDL, prod-data-backfills og verify i tre artifacts; generér og gate et kanonisk katalogmanifest; gør `schema.sql` komplet inkl. FTS; kræv `--single-transaction` og en clean-schema + current-prod migrationstest i CI.

#### F-05 · Fase 2/4 · redaktørrollen er global, ikke slægts-/source-scoped

**Evidens: verificeret.** `current_rolle()` returnerer kun `redaktion|medlem` fra profilen (`schema.sql:566-570`). `redaktion_read` giver en redaktør alle private/personbundne rækker (`db-rls.sql:457-510`), og de skrivende RPC'er tester kun `current_rolle()='redaktion'`, fx `schema.sql:583-588`. `profiles` har `reventlow_person_id`, men ingen redaktør→slægt/source-rettighed (`schema.sql:281-287`).

**Fejlscenarie:** efter import af Ahlefeldt bliver en redaktør, der kun skal vedligeholde Reventlow, i stand til at læse og ændre begge slægters levende personer, relationer og evidens via samme RPC'er.

**Anbefaling:** **stor, før redaktørudvidelse.** Indfør en egentlig slægts-/collection-entitet, redaktør-scope og server-side authorization helper; alle read-policies og muterende RPC'er skal validere scope på både subjekt og objekt.

#### F-06 · Fase 4 · append-import er ikke idempotent pr. udgave

**Evidens: verificeret.** Append er default (`load_daa.R:10-15`); hver kørsel opretter en ny `source` (`load_daa.R:263-265`) og nye personer (`:273-280`). `source` har ingen stabil unik udgave/importnøgle (`schema.sql:32-40`). Fixup stopper først bagefter, hvis flere sources har samme udgave (`post_load_fixup.R:31-40`).

**Fejlscenarie:** et importjob genkøres efter timeout eller uklar operatørstatus. Hele udgaven dubleres og committes; fixup fejler derefter, men ruller ikke importen tilbage.

**Anbefaling:** **mellem.** Tilføj import-run-ledger, checksum og unik stabil edition/import-key. Gør genkørsel til no-op eller source-scoped replace/upsert i én transaktion.

#### F-07 · Fase 4 · apps materialiserer hele grafen; pagination kan returnere en tavst trunkeret delgraf

**Evidens: verificeret for arkitekturen; skalaeffekten er ekstrapoleret.** Web henter hele `person`, `family_member`, `person_external_id` m.fl. (`web/src/data/model.ts:57-84`); mobil henter endnu flere tabeller (`mobile/src/data/load.ts:99-183`). `getAll` laver sekventielle offset-sider á 1.000, stopper efter 400 iterationer og returnerer derefter uden fejl (`packages/core/src/getAll.ts:4-22`). Hovedqueries mangler stabil `.order(...)`.

**Fejlscenarie:** ved 50× PoC er person alene ca. 46.000 rækker og kræver 47 roundtrips; medlemskabs-/evidenstabeller er større. Over 400.000 rækker returnerer helperen en delgraf som om den var komplet. Samtidige writes under offset-paging kan også flytte rækker mellem sider.

**Anbefaling:** **stor.** Bevar de rene modelbyggere, men fodr dem med bounded slices: server-side søgning, neighborhood/path-RPC og keyset/snapshot-pagination. Straksværn: deterministisk order og exception ved side-loftet.

#### F-08 · Fase 4 · slægt og lineage mangler et end-to-end namespace

**Evidens: verificeret.** Den generelle slægtsbeskrivelse har ingen entity/FK; begge klienter hardcoder sentinel `SLAEGT_SUBJEKT_ID=1` (`web/src/data/redaktionRead.ts:289-293`, `mobile/src/data/redaktionRead.ts:305-308`). Skemaet identificerer lineage som `(source_id,kode)` (`schema.sql:148-163`), men web og mobil grupperer counts, hovedperson og navn alene på kode som `I` (`web/src/data/lineage.ts:18-40`, `mobile/src/data/buildAux.ts:68-99`).

**Fejlscenarie:** en anden slægt/udgave har også linje `I`. Counts og stamfader blandes, sidste navn vinder, og slægtsbeskrivelsen kan kun adressere den globale sentinel.

**Anbefaling:** **stor.** Opret `slaegt`/collection som rigtig entitet og bær `slaegt_id`/lineage-id gennem source, narrativer, app-state, selectors og redaktørrettigheder. Nøgl aldrig runtime-data alene på linjekode.

#### F-09 · Fase 3 · generiske redaktør-relationer omgår evidensmodellen

**Evidens: verificeret.** `red_relation` og `red_tilfoej_relation` indsætter rå `relation`-rækker uden assertion, citation eller conclusion (`schema.sql:922-944`, `:1113-1133`). Web/mobil bruger denne vej til bl.a. gods/hverv (`web/src/data/redaktionWrite.ts:143-159`; mobil har samme kontrakt). Loaderen har derimod en evidens-komplet `rel_value`-vej (`load_daa.R:394-410`). `samme_som` er også evidens-komplet (`schema.sql:1005-1037`), hvilket viser at modellen kan bære det.

**Fejlscenarie:** to DAA-udgaver er uenige om ejerskab eller embede. Første redaktørs rå kant kan ikke suppleres med en konkurrerende kildepåstand og adjudikeres uden efterfølgende migration.

**Anbefaling:** **mellem/stor.** Gør alle autoritative relation-writes til assertion+citation+conclusion; behold relation som den valgte projektion eller gør læselaget conclusion-aware.

#### F-10 · Fase 3 · assertion-edit kan skifte autoritet; delete fjerner kildens udsagn fysisk

**Evidens: verificeret.** Edit appenderer positivt en ny assertion (`schema.sql:712-739`), men hvis den gamle ikke var valgt, re-peger `ON CONFLICT` alligevel conclusion til den nye (`:741-750`). Delete sletter citation+assertion og vælger automatisk den ældste resterende assertion (`:755-786`). Apps eksponerer begge handlinger (`web/src/data/redaktionWrite.ts:61-70`, `mobile/src/data/redaktionWrite.ts:66-75`). Versionering gør dem potentielt fortrydbare, men den aktuelle evidenssamling er ikke uforanderlig som krævet af invariant 1 (`CLAUDE.md:28`).

**Fejlscenarie:** redaktøren retter en ikke-valgt alternativ kilde, som dermed bliver autoritativ uden “gør til konklusion”; eller sletter en valgt påstand og gør en vilkårlig ældste kilde gældende.

**Anbefaling:** **mellem.** Edit af ikke-valgt assertion må ikke ændre conclusion. Erstat hard-delete med retraktion/tombstone og kræv et separat, eksplicit adjudikationskald.

#### F-11 · Fase 3 · fuzzy datoens rå tekst og interval kan divergere

**Evidens: verificeret.** Apps sender ved edit kun ny `date_raw` (`web/src/data/redaktionWrite.ts:61-66`, `mobile/src/data/redaktionWrite.ts:66-71`). SQL kopierer gammel `date_min`, `date_max` og `date_qualifier` til den nye assertion (`schema.sql:729-734`). Skemaet mangler checks for `min<=max`, qualifier-kombinationer og sammenhæng med raw (`schema.sql:369-380`).

**Fejlscenarie:** “1644” rettes til “ca. 1650”. Visning viser ny raw-tekst, mens matching og intervalqueries stadig bruger 1644.

**Anbefaling:** **mellem.** Parse og validér raw/min/max/qualifier atomisk server-side; afvis inkonsistente kombinationer og test redaktørvejen end-to-end.

#### F-12 · Fase 3 · konfidensens fravær og konflikter udglattes til sikkerere kanter

**Evidens: verificeret.** `family_member.konfidens` er nullable (`schema.sql:320-327`), og `red_tilfoej_barn` default'er til NULL. Core markerer kun `formodet|omstridt` som usikkert (`packages/core/src/relationship.ts:17-26`, `:345-347`). Efter identity-collapse reducerer `buildModel` konfidens til `child|parent` og beholder den stærkeste værdi på tværs af familier (`packages/core/src/buildModel.ts:90-100`).

**Fejlscenarie:** et nyt link uden vurdering vises uden advarsel; eller to udgaver har `sikker` og `omstridt`, hvorefter den viste sti bliver `sikker` uden kilde-/familieproveniens.

**Anbefaling:** **mellem.** Gør “ikke vurderet” synligt/fail-closed; behold family/source-proveniens pr. kant og vis den mest usikre relevante evidens, ikke kun den stærkeste.

#### F-13 · Fase 4 · loaderen committer trods uopløste barnereferencer

**Evidens: verificeret.** Uopløste child keys logges og springes over (`load_daa.R:362-374`); tvetydige unioner parkeres og logges (`:375-389`). Transaktionen committes (`:447-455`), og CSV/advarsel skrives først bagefter med succes-exit (`:457-460`). De lokale loader-tests er DB-frie helpertests, ikke en import-integritetstest.

**Fejlscenarie:** ekstraktionsformatet ændres, og mange referencer bliver uopløselige. Jobbet er grønt, men slægtskabsgraphen mangler kanter.

**Anbefaling:** **mellem.** Persistér import-run og unresolved-metrics i DB; afvis commit ved kritiske fejl eller over en eksplicit godkendt tærskel.

#### F-14 · Fase 1/2 · multi-writer-skrivning er race-følsom

**Evidens: verificeret.** Operatørguiden dokumenterer, at redaktions-RPC'er bruger `max(id)+1` (`docs/database-current-state.md:41-46`). Det giver samme id til to samtidige transaktioner; familiecyklus-/eksistenschecks er også check-then-insert-kode uden en generel serialiseringsgrænse. PoC'en antager én redaktør, mens målet er mange.

**Fejlscenarie:** to redaktører opretter fakta/relationer samtidigt. Den ene transaktion fejler sent på PK, eller to separate prechecks passerer på samme gamle graf og tilsammen bryder den tilsigtede struktur.

**Anbefaling:** **mellem.** Migrér alle surrogate PK'er til identity/sekvenser. Brug constraints eller målrettede advisory locks/serializable transaktioner for graf-invarianter før multi-editor åbnes.

#### F-15 · Fase 4 · `samme_som`-preflight har et konkret kvadratisk skaleringspunkt

**Evidens: verificeret.** `validateGroups` itererer aktive identitetsgrupper og filtrerer hele `rawDb.parentChild` for gruppemedlemmer, eventuelt i flere fixed-point-runder (`packages/core/src/collapseSameAs.ts:131-163`).

**Fejlscenarie:** mange udgaver skaber identity-links for en stor del af populationen. Både gruppetal og kanttal vokser lineært, men valideringen nærmer sig `O(G×E)` på klientens main thread og fryser før `buildModel`.

**Anbefaling:** **lille/mellem.** Indeksér `parentsByRawChild` én gang; benchmark med realistisk multi-edition-volumen og en tids-/størrelsesgate i CI.

#### F-16 · Fase 4 · CI gater ikke de risikofyldte lag og overser allerede en typefejl

**Evidens: verificeret.** Workflowet kører core-vitest, web-test/build og mobil-tsc/jest, men ingen R-test, core-typecheck, schema/migration-test, `db-verify.sql`, RLS-test eller loaderintegration (`.github/workflows/ci.yml:26-72`). `packages/core` har et typecheck-script, som CI ikke bruger (`packages/core/package.json:7`). Lokalt 2026-07-16:

- `Rscript run-tests.R`: 254 pass.
- core vitest: 254 pass.
- **core typecheck: exit 2**, `packages/core/src/__tests__/tree.test.ts:367` — `string` kan ikke tildeles `Koen | undefined`.
- web: 161 tests og build grøn.
- mobil: tsc grøn og 190 tests grøn.

**Fejlscenarie:** core-testtyper, migrationer, RLS eller loaderkontrakt brydes; nuværende CI er stadig grøn. Den aktuelle typefejl demonstrerer hullet.

**Anbefaling:** **lille** for core-typecheck + R-job; **mellem** for ephemeral Postgres-job, der anvender schema/migration/RLS og kører read-only strukturelle asserts.

### P2 — arkitektur og vedligeholdbarhed

#### F-17 · Fase 1 · `db-verify.sql` er bredt, men tester adfærd mere end fundamentintegritet

**Evidens: verificeret.** Filen tester mange vigtige happy/negative paths, cache, RLS, versionering, media og aktuelle Problem-2-RPC'er (`db-verify.sql:28-1389`). Men den tester ikke funktions-ACL/allowlist, generelle polymorfe orphans, vocab-dækning, `NOT NULL`/CHECK-komplethed, source-idempotens, schema/prod-drift eller helgrafs-/loaderskalering. Flere happy paths kræver funktionsejer/redaktørsession, og flere blokke udfører seed-DML; den kunne derfor ikke køres mod prod under dette reviews no-DML-grænse (`db-verify.sql:8-24`).

**Fejlscenarie:** alle funktionsadfærdstests er grønne, mens `_delete_relation_evidence` fortsat er anon-eksekverbar, eller prod mangler en constraint/har en orphan, som ingen task tæller.

**Anbefaling:** **mellem.** Del i (a) ren read-only drift/integritetsrapport, (b) rolle-/ACL/RLS-smoke og (c) muterende rollback-integration mod ephemeral DB.

#### F-18 · Fase 3 · cache- og kønsautoritet er indbyrdes modstridende

**Evidens: verificeret.** `red_set_koen` skriver direkte til `person.koen` (`schema.sql:836-843`), og begge apps bruger den. `regen_person_visning` regenererer visningsfelter, men ikke køn (`schema.sql:431-475`). `CLAUDE.md:31` siger, at `person.koen` afledes og aldrig redigeres direkte, mens `datamodel-oversigt.md:25` kalder køn en direkte arbejdsværdi. Derudover projicerer cachefunktionen conclusions uden filter på `status='afklaret'`, mens `red_tilbagetraek_fakta` kan sætte status til `tilbagetrukket` (`schema.sql:797-810`).

**Fejlscenarie:** kønsevidens og arbejdsværdi divergerer; eller et tilbagetrukket navn/fødselsfact fortsætter i `visning_*`.

**Anbefaling:** **mellem.** Beslut én autoritet for køn og ret både invariant og kode. Filtrér cacheprojektion til aktive conclusions og tilføj retraktions-tests for alle cachebærende faktatyper.

#### F-19 · Fase 3 · “én generisk mekanisme” har dobbelte autoriteter og manglende DB-håndhævelse

**Evidens: verificeret.** `lineage.parent_lineage_id` bærer forgrening samtidig med, at kommentaren foreskriver en `gren_af`-relation uden sync-trigger (`schema.sql:148-168`). `estate.sted_id` er direkte FK, mens modellen også beskriver placering som relation (`schema.sql:57-62`, `datamodel-oversigt.md:59-65`). Polymorfe `fact`/`relation` target-par har bevidst ingen FK (`schema.sql:339-365`). Den aktuelle prod-data havde 0 i de kørte orphanchecks, men sikkerheden ligger i loader/RPC-konvention, ikke skemaet.

**Fejlscenarie:** lineage-FK og `gren_af` peger på forskellige forældre, eller en ny import skriver en relation til en ikke-eksisterende polymorf target; forskellige læsere får forskellige sandheder.

**Anbefaling:** **mellem.** Dokumentér et lille eksplicit sæt tilladte cache/shortcut-kolonner og deres sync-invariant. Tilføj central type/target-validering samt periodisk orphan-assert.

#### F-20 · Fase 3 · vocab og narrativets ordrethed er overvejende aspirationelle

**Evidens: verificeret.** `vocab` har en PK, men `fact.faktatype`, `relation.rolle`, de fleste `slags/type` og relationens konfidens har ingen vocab-FK/check (`schema.sql:18-23`, `:32-61`, `:339-365`); statusdokumentet erkender dette (`docs/database-current-state.md:65-74`). `narrative` kan bære source/side/tekst, men `red_upsert_narrativ` overskriver teksten for samme subjekt/source; versionering bevarer historik, men den aktuelle “ordrette” transskription er mutabel (`schema.sql:413-420`, `:901-919`).

**Fejlscenarie:** ETL skriver `sandsynilg`, så queries mister rækken; eller en redaktør parafraserer en transskription, så kildeprosa og redaktionel tekst ikke længere kan skelnes.

**Anbefaling:** **mellem.** Central vocab-validation/komposite FK hvor muligt. Skil kildetransskription fra redaktionel tekst eller kræv eksplicit revisions-/retraktionshandling.

#### F-21 · Fase 4 · core-delingen er god, men domænelogik driver allerede mellem web og mobil

**Evidens: verificeret.** `buildModel`, `collapseSameAs`, matcher og `getAll` er reelt delt. Men parent-order og rå rækker→graf er spejlet (`web/src/data/model.ts:38-52,106-128`, `mobile/src/data/load.ts:83-97,211-251`); lineage-projektionen er også spejlet og har samme namespace-fejl. Konkret divergens: web sender manglende narrativ-source som `null`, mobil som hardkodet `1` (`web/src/data/redaktionWrite.ts:127-132`, `mobile/src/data/redaktionWrite.ts:132-139`). Mobil er kun dev, så dette er ikke en prod-gate.

**Fejlscenarie:** et multi-source edge case uden `sourceId` giver forskellige logiske narrativrækker afhængigt af klient.

**Anbefaling:** **mellem.** Flyt rene `rowsToGraph`, lineage-, arbejdslist- og RPC-argumenttransformer til core; behold kun platform-I/O og state lokalt.

## Fase 1 — databaseintegritet og drift

### Driftinventar: lokal autoritativ base vs. prod

Katalogerne blev sammenlignet for tabeller/views, kolonner, constraints, indekser, user-triggere, funktionssignaturer+bodies, policies og RLS-flags. Policies, RLS-flags og user-triggere matchede. Følgende var hele den fundne public-schema-drift:

| Retning | Drift |
|---|---|
| Forventet, mangler i prod | `assertion.objekt_type`, `assertion.objekt_id` (`schema.sql:369-380`) |
| Forventet, mangler i prod | `person_koen_check` (`schema.sql:122-135`) |
| Forventet, mangler i prod | `family_member_en_foedselsfamilie` + backing index (`schema.sql:320-336`) |
| Forventet, mangler i prod | `ix_assertion_objekt` (`schema.sql:813-827`) |
| Forventet, mangler i prod | view `red_foraeldre_konflikt` (`db-migrations.sql:2321-2332`) |
| Forventet, mangler i prod | `_ensure_foraeldrefamilie_redaktionel`, `red_fjern_ikke_samme_som`, `red_ikke_samme_som`, `red_tilfoej_foraeldre_paastand`, `red_vaelg_foraeldre` |
| Body afviger i prod | `red_edit_oplysning`, `red_flyt_barn`, `red_opret_fakta`, `red_relation`, `red_samme_som`, `red_set_konklusion`, `red_slet_familie_link`, `red_slet_oplysning`, `red_tilbagetraek_fakta`, `red_tilfoej_barn`, `red_tilfoej_oplysning`, `red_upsert_fakta` |
| Kun i prod | generated `narrative.fts` + `narrative_fts_idx`; i `schema.sql` kun udkommenteret (`schema.sql:829-832`) |

Det betyder ikke, at data aktuelt er korrupte. Read-only integritetsqueries gav 0 for: manglende person/source i `person_external_id`; manglende family/person i `family_member`; dublet fødselsfamilier; assertion uden fact/relation-target; conclusion med manglende/mismatchet assertion; citation uden assertion/source; ugyldig nuværende køn/familierolle/konfidens; `date_min>date_max`; media_variant uden media. Disse er snapshots, ikke erstatning for constraints.

**Fase 1-fund:** F-04, F-14 og F-17. Laget er datamæssigt rent i den aktuelle snapshot, men deploy-sandheden og flere centrale constraints er ikke reproducerbart håndhævet.

## Fase 2 — RLS, GDPR og adgangsmodel

- Anon-RLS er reelt server-side og fungerede i prod: 853 synlige personer, 0 levende, 0 private. Synlige relationer/facts/narrativer med person-target havde 0 endpoints, der var skjult for samme rolle.
- Authenticated-tier er også reelt live: 923 synlige, heraf 70 levende. Det er ikke en klientfilterfejl; policyen siger eksplicit “levende tilladt for login” (`db-rls.sql:349-406`).
- Alle inspicerede `red_*`-funktioner er `SECURITY DEFINER` med `search_path=public` og et internt authorization-check (`redaktion` for editorwrites; login for `red_suggest`). Den kritiske undtagelse er den interne slettehelper i F-01, som er API-eksekverbar uden gate.
- `redaktion` er en global rolle. Der findes ingen slægts-/source-scope, og redaktøren ser alle levende/private rækker.
- De fleste public-tabeller har direkte brede Supabase-default grants, også write/TRUNCATE. RLS blokerer normal tabel-DML, og PostgRESTs normale tabelendpoints tilbyder ikke TRUNCATE, men grantfladen er unødigt bred. Bookmark er den dokumenterede undtagelse, hvor grants indsnævres (`db-rls.sql:414-434`).

**Fase 2-fund:** F-01, F-02 og F-05. `search_path`-hygiejnen er god; ACL-allowlisten og authenticated/privacy-modellen er ikke.

## Fase 3 — de ni invarianter

| # | Status | Faktisk håndhævelse |
|---|---|---|
| 1 Evidensbaseret | **Delvis** | Schemaform og dele af loader/RPC er gode. Generiske editor-relationer mangler evidens; assertion-delete og editens conclusion-adfærd bryder uforanderligheden. F-09, F-10. |
| 2 Generisk relation | **Delvis** | Polymorf relation findes, men enkelte dobbeltautoriteter/specialveje kræver eksplicit sync-kontrakt. F-19. |
| 3 Alt er fact | **Delvis/aspirationel** | Polymorf fact findes; flere direkte kolonner er bevidste shortcuts, men grænsen er ikke stringent håndhævet. F-19. |
| 4 Envejs-cache | **Overvejende, med brud** | Triggere regenererer `visning_*`; `koen` er direkte write trods modstridende specifikation, og tilbagetrukne conclusions kan fortsat projiceres. F-18. |
| 5 Fuzzy datoer | **Repræsenteret, ikke konsistent håndhævet** | Felterne findes, men schema/edit-path kan skabe stale interval vs. raw. F-11. |
| 6 Narrativ vs. struktur | **Schema + redaktionel konvention** | Narrativ findes; ordrethed og selektiv udtrækning kan ikke skelnes/håndhæves robust. F-20. |
| 7 Konfidens | **Delvis** | Felt og finderpropagation findes; NULL og strongest-wins udglatter usikkerhed. F-12. |
| 8 GDPR | **Anon håndhævet; authenticated brudt ift. specifikationen** | Server-side anon er solid. Logged-in tier viser levende uden samtykke. F-02. |
| 9 Vocab | **Overvejende aspirationel** | Tabel findes; kun få lokale checks/RPC-valideringer binder værdierne. F-20. |

**Fase 3-fund:** F-09 til F-12 samt F-18 til F-20. Invarianterne er nyttige designregler, men kun 4 og 8 har et stærkt server-side skelet — og begge har konkrete undtagelser.

## Fase 4 — skalering, ETL og arkitektur

- `buildModel` er en ren, testet transformation og kan bevares, hvis inputtet bliver bounded. Det er hel-dataset-fetch, offset-pagination og identity-preflighten rundt om den, der udgør skaleringsklippen.
- Flere DAA-udgaver er konceptuelt understøttet via `source`, men import-idempotens, slægtsidentitet og runtime-lineage-keys er ikke klar til gentagne koder/udgaver.
- ETL er transaktionel og bulk-baseret — godt — men reset-ejerskab, dublet-import og unresolved-policy er ikke produktionssikre.
- `packages/core` har flyttet de vigtigste rene algoritmer til ét hjem, men flere spejlede domænetransformer driver allerede.
- Testmængden er stor og grøn, bortset fra core-typecheck. CI gater ikke R/SQL/RLS/import, hvor de dyreste fejl ligger.

**Fase 4-fund:** F-03, F-06 til F-08, F-13, F-15, F-16 og F-21.

## Samlet vurdering

Nej — ikke endnu fra 923 personer til foreningens samlede data. Datamodellens kerne er værd at bygge videre på; en omskrivning af hele fundamentet er ikke nødvendig. Men adgangs- og ingestion-grænserne er stadig PoC-grænser, og de bliver dyrere for hver ny slægt, udgave og redaktør.

De første tre ting skal være:

1. **Luk P0-adgangsstierne:** revoke den interne helper, luk authenticated levende-læsning indtil samtykke/scope findes, og fjern normal prod-reset.
2. **Gør ingestion og deploy reproducerbar:** source-scoped/idempotent import, separat DDL/backfill/verify, katalogdiff og ephemeral DB-gate i CI.
3. **Indfør slægts-/source-scope og en server-side læsekontrakt:** rigtig slægtsidentitet, scoped redaktørrettigheder, server-side søgning/path/neighborhood og kildebevarende usikkerhed.

Når de tre er løst, kan den eksisterende evidensmodel, versionering og core-algoritmer bære en kontrolleret udvidelse. Uden dem vil flere data først forstærke GDPR-risikoen, derefter importdrift og til sidst klientens skaleringsloft.
