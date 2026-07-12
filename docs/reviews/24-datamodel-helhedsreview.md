# Review 24 — Helhedsreview af datamodel + implementering

**Dato:** 2026-07-09
**Metode:** 3 parallelle read-only analyse-agenter (RLS/sikkerhed · app-datalag web+mobil · R-pipeline) + manuel gennemlæsning af `schema.sql` og `datamodel-oversigt.md`. De tungeste fund er verificeret ved selvsyn i koden (markeret ✅). Ingen ændringer foretaget — dette er en fund-liste til senere rettelse.

**Samlet vurdering:** Datamodellen er solid — påstand/konklusion-laget, den generiske relation og fuzzy-dato-modellen respekteres konsekvent i praksis (app + loadere). Implementeringsdisciplinen er høj. Men ét kritisk sikkerhedshul bør lukkes straks, og reload-stien er reelt forbudt terræn indtil tre fund er lukket.

---

## Status-oversigt

| # | Alvorlighed | Fund | Status |
|---|---|---|---|
| 1 | 🔴 KRITISK | `_delete_relation_evidence` ugated + ikke revoked | ☐ |
| 2 | 🟠 HIGH | Spøgelses-union-guard (navn≠ref) mangler i loader | ☐ |
| 3 | 🟠 HIGH | Manuelle prod-fixes replayes aldrig ved reload | ☐ |
| 4 | 🟠 HIGH | `supabase_load.R` uguarded TRUNCATE mod prod | ☐ |
| 5 | 🟡 MEDIUM | `getAll` uden `.order('id')` på >1000-rækkers tabeller | ☐ |
| 6 | 🟡 MEDIUM | Race i person-detalje (manglende cancelled-guard) | ☐ |
| 7 | 🟡 MEDIUM | Slugte `.error` i redaktions-reads | ☐ |
| 8 | 🟡 MEDIUM | Web/mobil-drift i redaktionslaget | ☐ |
| 9 | 🟡 MEDIUM | Påstands-uforanderlighed kun konvention | ☐ |
| 10 | 🟡 MEDIUM | Default-ACL-overgrants kun ryddet på `bookmark` | ☐ |
| 11 | 🟡 MEDIUM | Schema-drift: `narrative.fts` live i prod, ikke i SQL-filerne | ☐ |
| 12 | 🟡 MEDIUM | `db-verify.sql` mangler sikkerheds-asserts | ☐ |
| 13 | 🟡 MEDIUM | Multi-udgave-tvetydighed i fixup + `red_upsert_fakta` | ☐ |
| 14-20 | 🟢 LOW | Diverse mindre fund | ☐ |

---

## 🔴 KRITISK — luk straks

### 1. `_delete_relation_evidence` er en ugated SECURITY DEFINER-funktion uden REVOKE ✅

**Filer:** `db-migrations.sql:576`, `schema.sql:896` (definition); `db-rls.sql:546-548` (REVOKE-blok der mangler den)

Funktionen er SECURITY DEFINER **uden** `current_rolle()`-gate (bevidst — kalderne `red_slet_relation`/`red_fjern_samme_som` bærer gaten), men den optræder **ingen steder** i `db-rls.sql`'s REVOKE-blok. Hærdningen 2026-07-02 lukkede søskende-funktionerne `_subjekt_synlighed` og `begin_change_set`, men overså denne. Da Supabase default-granter EXECUTE til `anon`/`authenticated` (prod-verificeret tidligere, jf. review 13), kan enhver uindlogget klient formentlig kalde `POST /rpc/_delete_relation_evidence` og slette vilkårlige relationer **inkl. deres evidens-kæde** (citation → conclusion → assertion → note → relation) — udenom både RLS og rollegate.

**Fix:**
1. Bekræft eksponering mod prod:
   ```sql
   SELECT has_function_privilege('anon','public._delete_relation_evidence(bigint)','execute'),
          has_function_privilege('authenticated','public._delete_relation_evidence(bigint)','execute');
   ```
2. Revoke (navngiv rollerne eksplicit — FROM PUBLIC alene er dokumenteret utilstrækkeligt):
   ```sql
   REVOKE EXECUTE ON FUNCTION public._delete_relation_evidence(bigint)
     FROM PUBLIC, anon, authenticated;
   ```
   Kalderne er SECURITY DEFINER og kører som ejer → upåvirkede.
3. Kør `get_advisors(security)` efter (jf. memory-regel).
4. Grep for andre `_`-præfiksede SECURITY DEFINER-helpers uden REVOKE — pt. er denne den eneste, men tilføj verify-assert (fund 12) så det bliver maskinelt.

---

## 🟠 HIGH — reload-stien er regressiv (behandl `--force-reset` som forbudt indtil lukket)

### 2. Spøgelses-union-guard (navn≠ref) mangler stadig ✅ (fravær verificeret)

**Fil:** `.claude/skills/daa-extract/scripts/load_daa.R:283-288` (pass 2)

Partner-links oprettes alene via `parse_intern_ref`-opslag; `a$partner_navn` sammenlignes aldrig med den refererede persons navn. En forkert ekstraktions-ref gen-skaber ved reload de 26 "barn-gift-med-ane"-unioner der blev ryddet manuelt i change_sets 3-7. Var kendt udestående (jf. TNG-QA Etape 3+4) — bekræftet stadig åbent.

**Fix:** match-afvis (parkér + log, samme mønster som `match_barn_union`s parkering) når refereret persons navn-fakta ≉ `partner_navn`.

### 3. Manuelle prod-korrektioner replayes aldrig ved reload

**Filer:** `load_daa.R:222-227` (guard/TRUNCATE), `post_load_fixup.R`

`post_load_fixup.R` gendanner kun lineage/profiler/samme_som/slægtled-backfill — **ikke** datakorrektionerne fra change_sets 1-7, 20, 30 (børne-union-flyt, spøgelses-oprydning, 1↔104-fix). Kombineret med fund 2 er en reload garanteret tab af håndarbejde. Bemærk også: TRUNCATE CASCADE rammer `lineage`/`profiles`/`suggestion` via FK, og guarden tjekker kun `change_set.operation ~ '^red_'` — ikke om `suggestion` har indhold.

**Fix-retning:** enten replay-mekanisme for change_sets efter reload, eller dokumentér+håndhæv at reload kræver manuel re-anvendelse af korrektionslisten.

### 4. `supabase_load.R` er en ladt fodkanon mod prod ✅

**Fil:** `supabase_load.R:26,109-111`

Hardcodet `RESET <- TRUE`, `TRUNCATE ... CASCADE` over 19 tabeller inkl. `person`, ingen change_set-guard. Pga. R's `~/.Renviron`-adfærd (memory: r-env-renviron-override-farlig) kan scriptet ikke omdirigeres væk fra prod via shell-env — en kørsel sletter 922-personers base + redaktionel historik uden bekræftelse.

**Fix (billigst):** lad scriptet fejle ved start med henvisning til `load_daa.R`, eller portér `has_editorial_changes`-guarden.

---

## 🟡 MEDIUM — ret ved lejlighed

### App-datalag

### 5. `getAll` pager uden `.order('id')` på store tabeller ✅

**Filer:** `web/src/data/model.ts` (~l. 64-88), `mobile/src/data/load.ts` (~l. 145-197)

`family_member` (~1310 rækker), `relation`, `person_external_id`, `conclusion` pages uden ORDER BY — række-rækkefølge på tværs af separate `.range()`-requests er ikke garanteret stabil → grænse-rækker kan dubleres/tabes (potentielt forkerte forældre-kanter). `place`/`fact` fik `.order('id')` med forklarende kommentar (`model.ts:86-87`) — de øvrige blev glemt. Én linje pr. sted, begge platforme.

### 6. Race: person-detalje uden cancelled-guard ✅

**Fil:** `web/src/Folgesvend.tsx:170`

`fetchPersonDetail(...).then(setDetail)` uden guard — hurtige fokus-skift kan lade en sen resolver for person A overskrive person B's detalje. Estate-effekten lige ovenover (l. 150-163) fik netop denne guard i review 15 M3; person-detalje blev glemt. Kopiér mønsteret.

### 7. Slugte PostgREST-fejl i redaktions-reads

**Fil:** `web/src/data/redaktionRead.ts` + `web/src/data/public.ts`

- `fetchPersonEvidence` (l. 129-148): ingen af de 5 queries tjekker `.error` — en RLS-/nedbrudsfejl ligner "person uden evidens" → redaktøren kan genoprette allerede-eksisterende facts.
- `fetchSletPreview` (l. 256-269): `if (error || !data) return tom` → slet-modal viser "0 relationer / 0 facts" ved fejl og kan tilskynde en farligere sletning.
- `fetchSammeSomLinks` (l. 390-397): samme mønster + `as never`-cast; desuden NaN-injektion i `.or()`-strengen ved ikke-numerisk personId (l. 396).
- `public.ts`: `narr.error` ignoreres i `fetchPersonDetail` (l. 140-142); `fetchEstateInfo`/`resolveOrgEstateNames` samme — PostgREST-fejl kaster ikke, så `safe()`-løftet om synlig degradering holder ikke her.

**Fix:** `.error`-tjek med throw eller synlig degradering — redaktionsflows skal fejle højlydt, ikke ligne tomme data.

### 8. Web/mobil-drift i redaktionslaget

Mobil `redaktionWrite.ts` mangler webs `planCall`/`red_suggest`-fallback (ikke-redaktion kaster i stedet for at lande som forslag); web mangler mobiles `opretPerson/opretEstate/opretOrganisation/fortryd` + konflikt-/historik-læsning. Kernealgoritmer (collapseSameAs/relationship/generations/buildGeo m.fl.) er byte-identiske kopier — men "hold i sync"-markeringerne er allerede driftet i feature-sæt. **Anbefaling:** delt-pakke-ekstraktion før næste redaktions-feature.

### Database/model

### 9. Påstands-uforanderlighed er kun konvention ✅

`assertion.uforanderlig` håndhæves ikke af nogen trigger (verificeret: kolonnen refereres kun i INSERTs). RLS beskytter mod klienter, men ejer-kode/loadere/fremtidige RPC'er kan mutere frit. Desuden hard-deleter `red_slet_oplysning` faktisk påstande (dokumenteret PoC-valg, men i spænding med invariant 1 — versioneret via change_event, så genoprettelig).

**Fix:** `BEFORE UPDATE OR DELETE`-trigger på `assertion` der afviser når `OLD.uforanderlig = true` (med eksplicit bypass for redaktions-RPC'ernes append/slet-stier hvis de skal bevares).

### 10. Default-ACL-overgrants kun ryddet på `bookmark`

**Fil:** `db-rls.sql:416-424` (kommentaren siger det selv: "systemisk … kun rettet for bookmark her")

Supabase auto-granter fuld DML inkl. UPDATE/TRUNCATE til `authenticated` på hver ny tabel. DML er inert pga. RLS (ingen write-policy = deny), men **TRUNCATE bypasser RLS**. Ikke PostgREST-eksponeret → latent. **Fix:** `REVOKE UPDATE, TRUNCATE, REFERENCES, TRIGGER ... FROM anon, authenticated` i loop over alle datatabeller (spejl bookmark-fixet).

### 11. Schema-drift: `narrative.fts` live i prod, fraværende i SQL-filerne ✅

`narrative.fts` (GENERATED tsvector + GIN-indeks) er aktiv i prod (jf. `docs/changelog.md` l. 696-697), men står udkommenteret i `schema.sql` (l. 776-779) og findes slet ikke i `db-migrations.sql`. `schema.sql` er erklæret source of truth — den bør indhente prod, ellers mangler indekset ved næste base-genopbygning/lokal testbase.

### 12. `db-verify.sql` mangler sikkerheds-asserts

Verify-filen har ægte rollebaserede RLS-tests (media/storage/bookmark under `SET ROLE`), men ingen asserts af typen:
- `SET ROLE anon; SELECT count(*) FROM person WHERE levende` = 0
- alle SECURITY DEFINER-helpers med `_`-præfiks: `has_function_privilege('anon', ..., 'execute') = false`
- `pg_tables.rowsecurity = true` for alle public-tabeller
- default-ACL: ingen UPDATE/TRUNCATE-grants til anon/authenticated

En sådan blok ville have fanget fund 1 maskinelt.

### 13. Multi-udgave-tvetydighed (skal lukkes FØR DAA-udgave 2 loades)

- `post_load_fixup.R:31` (`ORDER BY id LIMIT 1`) + `:60-61` (`pid_of` uden source-filter): ved 2+ DAA-udgaver kan `(linje, nr)` matche forkert udgaves person → samme_som-links/lineage mod forkert kilde. `backfill_slaegtled.R` løser samme problem korrekt (fail-closed source-resolution) — portér mønsteret.
- `red_upsert_fakta` (`schema.sql:581-583`): find-or-create med `LIMIT 1` uden `ORDER BY` — nondeterministisk mål når en person har flere facts af samme faktatype (tilladt via `red_opret_fakta`).

---

## 🟢 LOW / design-observationer

14. **`vocab` er ikke FK-håndhævet nogen steder** ✅ — invariant 9 ("kontrolleret vokabular") er ren konvention; `relation.rolle`, `fact.faktatype` m.fl. er fri tekst. En CHECK/FK eller verify-assert ville fange tastefejl der stille brækker "samme slags"-forespørgsler.
15. **`max(id)+1`-id-tildeling overalt** (inkl. i `log_change`-triggeren, `schema.sql:1548`) — OK under single-writer-PoC (dokumenteret), skal migreres til IDENTITY/sekvenser før flere samtidige redaktører.
16. **`regen_person_visning` vælger `max(vaerdi_tekst)`** ved flere konkluderede titler/navne (`schema.sql:431-436`) — alfabetisk-arbitrær "primær titel". Samme tema i loaderen: `load_daa.R:390-398` cache-UPDATE med `LIMIT 1` uden `ORDER BY` og uden status-filter (en 'omstridt' konklusion projiceres også); efternavns-cache er NULL efter reload indtil `post_load_fixup.R` er kørt.
17. **`relationship.ts` label-baseret linje-merge** (`web/src/data/relationship.ts:286-304`, identisk mobil): etiketten er ikke injektiv (alle `rem>=2` → "Grandonkel & grandnevø") → linjer med forskellig reel afstand kan flettes med forkert multiplicitet. FORMODET (logisk udledt, ej reproduceret).
18. **Type-huller i web:** `Aux.linjeByPerson` er død kode med forkert form ift. mobil (`string` vs `string[]`); webs `types.ts` er bagud (mangler `visning_fuldt_navn`, `RawSource.aar`, rig `RawMedia`) og driften skjules af lokale skygge-typer + `as unknown as`-casts. Slet død kode; saml typerne.
19. **Loader-småting:** `work/load-unresolved.csv` skrives post-commit uden dir-guard (`load_daa.R:429`); `parse_intern_ref` hardcoder årstal 1800-1999 + linje-koder I-VIII (`load_helpers.R:33-35`) — knækker tavst ved næste slægt; enkelt-ægteskab springer union-match-kontekst-tjek over (`load_daa.R:326-328`); mobil narrativ-default `p_source_id ?? 1` vs web `?? null` (dokumenteret bevidst, men divergent).
20. **Accepterede trade-offs (til bevidsthed, ikke fix):** `person_offentlig()` som anon-oracle (arkitektonisk nødvendig, bounded boolean); facts på `subjekt_type='media'` anon-synlige (rettighedsmetadata, ikke PII); `red_konflikt`-view grantet til anon (security_invoker begrænser rækker — grant blot overflødig).

---

## ✅ Verificeret solidt (ingen handling)

- **Evidens-invarianter på skrivesiden:** app'en skriver kun via `red_*`-RPC'er (ingen direkte `.update()` på `person.visning_*`/`koen` fundet); loadere er append-only på assertions, `date_raw` bevares altid, narrativ loades ordret; omstridte datoer = to assertions + conclusion.
- **RLS-dækning:** alle 30 tabeller i `schema.sql` har RLS enabled; `profiles` har kun self-read (ingen selv-eskalering til redaktion); alle SECURITY DEFINER-funktioner sætter `search_path=public`; tidligere fund (version_pk_registry, `_subjekt_synlighed`/`begin_change_set`-revokes, anon-oracle-lukning) er ikke regredieret.
- **Collapse & konfidens:** `collapseSameAs` (fixed-point, karantæne) køres før `buildModel`, byte-identisk web/mobil, read-sites kanoniserer; konfidens vises i slægtskabsfinderen (`weakestKonfidens`).
- **Paginering:** `getAll` (PAGE=1000, error-throw, tom-side-stop) bruges konsekvent — kun ordering-hullet (fund 5) består.
- **Versionering/fortryd:** B9-divergens-tjek for alle op-typer, GENERATED-kolonne-eksklusion, reversal-kæde, no-op-skip for cache-kolonner — gennemarbejdet.
- **Loader append-mode:** transaktioner m. rollback i alle scripts; kendte bugs 6a (børn på 1. union), 6b (linje-kollision) og 6d (backfill-guard) er fikset med testdækning.
- **samme_som-invarianter:** håndhævet i TRIGGER (gælder alle insert-veje), advisory-lock-serialiseret, G3/G4-guards.

---

## Anbefalet rækkefølge

1. **Nu:** fund 1 (probe + REVOKE — ét statement mod prod efter bekræftelse, + `get_advisors`).
2. **Før nogen reload:** fund 2 + 4 (navn≈ref-guard; guard/deprecér `supabase_load.R`); afklar fund 3.
3. **Næste kode-session:** fund 5, 6, 7 (ordering, cancelled-guard, error-tjek).
4. **Ved lejlighed:** fund 9, 10, 11, 12 (uforanderligheds-trigger, ACL-loop, fts ind i SQL-filerne, verify-asserts).
5. **Før DAA-udgave 2:** fund 13 (kilde-pin fixup).
6. **Før næste redaktions-feature:** fund 8 (delt pakke).
