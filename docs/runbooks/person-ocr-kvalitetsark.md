# Runbook — Personers OCR-kvalitetsark

> **Formål:** Sikker, trinvis idriftsættelse af OCR-kvalitetsarket. Hvert
> produktionstrin kræver en frisk, eksplicit godkendelse fra brugeren. Denne runbook
> beskriver, hvad der er verificeret, og hvad der endnu ikke er.

**Feature:** Redaktør-værktøj der viser hver importeret person som én række i et
regneark-lignende grid, med et sidepanel hvor navn, fødsel, død og køn kan rettes uden
at OCR-oprydning bliver til nye historiske påstande.

**Branch:** `feat/person-spreadsheet-design` (lokal, ikke pushet, ingen PR)
**Plan:** `docs/superpowers/plans/2026-07-26-person-ocr-kvalitetsark.md`
**Design:** `docs/superpowers/specs/2026-07-26-person-ocr-kvalitetsark-design.md`

---

## 1. Tilstand

| Tilstand | Status | Evidens |
|---|---|---|
| `code_ready` | **OPNÅET** | Se §2 (alle automatiske gates grønne) |
| `local_db_verified` | **OPNÅET** | Se §3 (frisk base, opgraderingssti, rolleadgang) |
| `production_db_migrated` | **OPNÅET (2026-07-27)** | Se §5.1 — migreret, verificeret mod rigtig prod |
| `web_deployed` | **OPNÅET (2026-07-27)** | PR #103 merget til `main` af brugeren; Vercel auto-deploy verificeret (feature-strenge fundet i live JS-bundle) |
| `smoke_verified` | **IKKE OPNÅET** | Kræver manuel redaktør-røgtest i browser mod prod — se §4 |

Produktionsdatabasen ER migreret (§5.1). Web-laget ER deployet (§5.2). Eneste
udestående er den manuelle redaktør-røgtest (§4).

**Identitet (2026-07-28):** DAA 2018-20 (591 personer, `source.id=1`) har nu stabil
`record_key`/`import_key` via en tilføjende backfill, ikke en genindlæsning — se §5.1
punkt 6. 1939-udgaven (staged, `source.id=3`) er stadig uden stabil identitet.

---

## 2. Automatiske gates (kørt på committet HEAD)

| Gate | Resultat |
|---|---|
| `Rscript run-tests.R` | 475 passed, 1 bevidst skip (DB-smoke, opt-in) |
| `DAA_RUN_LOCAL_DB_SMOKE=1` loader-smoke | 124 passed, 0 warn |
| `npm test -w @daa/core` | 358 passed |
| `npm run typecheck -w @daa/core` | ren |
| `npm test -w @daa/feed` | 120 passed |
| `npm test -w web` | 613 passed (52 filer) |
| `npm run build -w web` | ren |
| `npm test -w mobile` | 399 passed |
| `python3 .claude/skills/daa-extract/scripts/test_validate.py` | 130 passed |
| `git diff --check` | ren |
| Placeholder-scan (TODO/FIXME/TBD) i feature-diff | 0 fund |

---

## 3. Lokal databaseverifikation

Kørt mod engangsbaser på PostgreSQL **17.10 (Homebrew)**, aldrig mod prod.
Supabases `auth`-lag findes ikke i `schema.sql` og shimmes lokalt (roller
`anon`/`authenticated`/`service_role`, `auth.users`, `auth.uid()` med Supabases egen
definition).

| Kontrol | Resultat |
|---|---|
| Frisk base: `schema.sql` → `db-migrations.sql` ×2 → `db-rls.sql` | alle OK; migrationerne er idempotente (kørt to gange) |
| Opgraderingssti: nye migrationer + RLS oven på præ-feature base (`2c8f3b6`) | OK |
| Legacy-person uden `person_external_id` | **synlig** i grid, `import_key` NULL, `kan_rettes.navn=false`, blokårsag `ingen_importanker` |
| `red_person_grid()` som **anon** | afvist (`Kun redaktion`) |
| `red_person_grid()` som **medlem** | afvist (`Kun redaktion`) |
| `red_person_grid()` som **redaktion** | rækker returneret |
| Rettelse → reset-load → genafspilning | dækket af loader-smoken: rettede værdier overlever, journal-id uændret, nyt fysisk `person.id` |
| Ændret OCR-kontekst | korrektionen markeres `stale` og genafspilles ikke |
| Fejlet load | journalstatus rulles tilbage (ingen status-fremskrivning) |

Rolletjek er udført med efterlignede JWT-claims
(`set_config('request.jwt.claim.sub', ...)`), ikke som funktionsejer.

### 3.1 Rehearsal mod prods rigtige data

Ud over den syntetiske engangsbase blev der kørt en fuld rehearsal mod prods
**faktiske** data: `pg_dump --data-only` af prod (read-only), genoprettet i en lokal
engangsbase med prods faktiske pre-feature-struktur, hvorefter feature-migrationerne
blev lagt oven på og verificeret mod de 1757 rigtige personer.

Dette fandt et reelt fund, som den syntetiske base ikke kunne afsløre: griddets
`navn`/`foedsel`/`doed`-visningskolonner delte anker-gate med redigerbarheden, så
**alle** 1757 eksisterende personer viste tomme felter — ikke kun ikke-redigerbare.
Rettet (commit `4d041bf`): visningsværdien falder nu tilbage til den allerede
afklarede evidens (`selected_assertions`, samme kilde field_candidates selv bruger
før anker-gaten), uafhængigt af redigerbarhed. `kan_rettes`/`blokarsager`/fingerprint
er urørt. Efter fix: 0/1757 personer har `navn IS NULL` (var 1757 før).

| Kontrol mod rigtige data | Resultat |
|---|---|
| Data genoprettet | person=1757, assertion=8619, citation=8173, person_external_id=1130 — matcher prod |
| `db-verify.sql` OCR-blokke mod rigtige data | 3/4 bestod; 4. springer sig selv over (kræver `dblink`, kendt vilkår) |
| `navn IS NULL` efter fix | 0/1757 (via ægte PostgREST+RLS-kald, ikke kun rå SQL) |

### 3.2 Skala-måling

Syntetisk datasæt på **2001 personer** med evidenskomplette navn/fødsel/død-fakta:

| Mål | Værdi |
|---|---|
| `red_person_grid()` varighed | 285–301 ms (tre kørsler) |
| Svarstørrelse (JSON) | 3.470 kB |

**Forbehold:** de syntetiske OCR-kontekster er korte (~20 tegn), mens produktionens
`citation.citat_tekst` er reel udtræksprosa. 3,47 MB er derfor et **gulv**, ikke et
estimat. Browserens rendertid er **ikke målt** — se §4.

Beslutning: griddet går i v1 uden rækkevirtualisering. Hvis den manuelle røgtest (§4)
viser træg rendering ved fuld datamængde, skal virtualisering eller server-side
cursor-paginering designes som en **selvstændig opfølgning** — ikke som en stille
ændring af v1.

---

## 4. Manuel redaktør-røgtest — UDFØRT (2026-07-29)

**Udført af brugeren i browseren, meldt OK.** `smoke_verified` er dermed opnået, og
kvalitetsarket er i fuld drift for de poster der har et importanker (se §4.1).

- [x] Skift Liste ↔ Kvalitetsark; bekræft at "Alle personer" er valgt fra start
- [x] Kombinér QA-preset, fritekstsøgning og kilde-/linjefilter
- [x] Sortér hver redigerbar kolonne, begge retninger; tjek at tomme datoer lander sidst
- [x] Åbn en blokeret række i den eksisterende editor via "Åbn person"
- [x] Ret ét felt; godkend ét felt; udskyd ét felt
- [x] Genindlæs browseren og bekræft at tilstanden holder
- [x] Læs panelets ordlyd: skal sige "OCR-kontekst" og indeholde noten om at det ikke
      er en gengivelse af den trykte side
- [x] **Prøvekørsel:** bekræft at panelet nægter at gemme, mens prøvekørsel er slået
      til, og forklarer hvorfor (se §6)
- [x] Notér browserens rendertid ved fuld datamængde (§3.2)

### 4.1 Hvor langt rækker arket i dag

Målt mod prod 2026-07-29 (1733 personer efter dubletoprydningen):

| Bånd | Personer | Redigerbare |
|---|---|---|
| **DAA 2018-20 hovedposter** | 591 | **591 (100 %)** |
| DAA 2018-20 ægtefæller | 331 | 0 |
| DAA 1939 hovedposter | 515 | 0 |
| DAA 1939 ægtefæller | 296 | 0 |
| **I alt** | **1733** | **591 (34 %)** |

Alle 1142 blokerede har samme rod: `red_ret_ocr_felt` forankrer på
`(import_key, record_key)`, og de mangler det ene eller begge. To udestående planer
dækker resten — ingen af dem er skrevet:

1. **1939-identitet** (811 personer: 515 hovedposter + 296 ægtefæller). Blokeret af en
   åben beslutning, se `docs/decisions.md` → "1939-posternes permanente løbenummer".
   Rækkefølge: dubletgennemgangen først.
2. **Ægtefælle-forankring** (627 personer). Nøglen skulle være forælderens `record_key`
   + indeks i `aegteskaber`, og `linje` SKAL være NULL — ellers påhæfter
   `regen_person_visning()` slægtsnavnet til indgifte ægtefæller. Ikke blokeret af
   noget andet.

De to overlapper: de 296 1939-ægtefæller rammes af **begge**, og løses kun den ene,
forbliver de blokerede.

---

## 5. Idriftsættelse — obligatorisk rækkefølge

Hvert trin kræver en **frisk, eksplicit godkendelse**. Stop ved første afvigelse.

### 5.1 Database — UDFØRT (2026-07-27), brugergodkendt

1. **Backup.** Fuld krypteret `pg_dump` (AES256/gpg) af prod taget og
   gendannelses-verificeret (restore til lokal engangsbase, `person`/`assertion`-tal
   matchede). Fil: `daa-prod-pre-ocr-kvalitetsark-20260727-214752.dump.gpg`.
   Passphrase ligger **kun** i en lokal fil under sessionens scratchpad — flyt den til
   en adgangskode-manager, den er ikke i git eller chatlog.
2. **Migration.** De to navngivne blokke anvendt mod `xjnvdhajfyrcytatnzos` via
   Supabase migrationshistorik: `person_ocr_kvalitetsark` (20260727215750,
   identitet+grid+rettelse) og `person_ocr_kvalitetsark_rls` (20260727215816).
3. **Verifikation mod rigtig prod:**
   - `anon`-kald til `red_person_grid` afvist (ægte REST-kald, HTTP 401,
     `permission denied for function`).
   - `get_advisors(security)`: 130 → 133 lints, **+3** (nøjagtigt de tre nye
     SECURITY DEFINER-funktioner), ingen nye lint-kategorier.
   - Data uændret: 1756 personer, 8716 assertions (samme før/efter migration).
4. **Importnøgle-beslutning (brugervalg):** migrér nu, genindlæs senere. Ingen
   udgave er genindlæst med `--import-key=` endnu — alle eksisterende personer er
   derfor synlige (navn/fødsel/død vises) men ikke-redigerbare (`record_key_mangler`).
5. **`--reset`-genindlæsning afvist som vej (2026-07-28).** `has_reset_blocking_
   editorial_changes()` (`load_helpers.R`) blokerer på enhver `red_%`-operation
   undtagen `red_ret_ocr_felt`. Prods `change_set` har 482 `red_samme_som` plus
   dusinvis andre redaktørrettelser (slettede personer, forældre-fixes,
   medie-/narrativoperationer) — en `--reset` ville enten blive nægtet af spærren
   eller, hvis tvunget igennem, slette den historik. Vejen forkastet uden at røre
   prod.
6. **Backfill af `record_key`/`import_key` for DAA 2018-20 (2026-07-28),
   brugergodkendt.** Alternativ til genindlæsning: en smal, kun-tilføjende
   `UPDATE` der stempler eksisterende rækker med den identitet en fremtidig
   genindlæsning ville have givet dem — uden at røre `--reset`-spærren, person-,
   fact- eller family-data.
   - **Grundlag:** de 591 JSON-filer i `data/extracted-2026-06-18/` er selv
     navngivet med `record_key` (fx `I-15a.json`); `citation.source_id` på
     eksisterende navn/fødsel/død-påstande verificeret til at pege på samme
     `source`-række (id 1) som blev stemplet.
   - **To `(linje,nr)`-kollisioner** (basenr 15 delt af I-15a/b/c; basenr 41 delt
     af I-41a/b) løst entydigt ved navnematch mod prods faktiske data — 591/591
     dækning, ingen gæt, ingen rækker efterladt tvetydige.
   - **Rehearsal:** kørt mod en lokal kopi af prods rigtige data (samme stack som
     §3.1) inde i en transaktion, rullet tilbage. Resultat: 591/591 fik
     `record_key`, 0 `record_key_mangler` tilbage, 588/591 blev `kan_rettes.navn`.
   - **Prod:** frisk krypteret backup taget og gendannelses-verificeret
     (`daa-prod-pre-record-key-backfill-20260728-074303.dump.gpg`), scriptet
     kørt i én transaktion med indbygget verifikations-`SELECT` før `COMMIT`.
     Resultat mod ægte prod (via `red_person_grid()` som redaktør): identisk med
     rehearsal — 591/591, 0 mangler, 588 `kan_rettes.navn`. `get_advisors
     (security)` uændret på 133 lints (ren DML, ingen ny DDL). Persontal
     uændret af backfillen (kun `UPDATE` af to eksisterende NULL-felter).

**Hændelse under migrationen (ingen skade, men værd at kende):** første forsøg på at
anvende migrationen fejlede, fordi jeg manuelt genskrev SQL'en fra hukommelsen i
værktøjskaldet i stedet for at bruge den allerede verificerede, udtrukne fil ordret —
en linje fik forkerte kolonnenavne (`pk_kolonner`/`generated_kolonner` i stedet for
prods faktiske `pk_cols`/`skip_cols`). Transaktionen rullede atomisk tilbage; et
efterfølgende tjek bekræftede at intet var delvist anvendt. Genforsøgt med filens
eksakte, læste indhold — lykkedes.

### 5.2 Web — UDFØRT (2026-07-27), brugerhandling

5. **Web-deploy.** PR #103 (merge-konflikt mod 51 samtidige `main`-commits løst,
   enkelt konflikt i `docs/changelog.md`) merget til `main` af brugeren direkte via
   GitHub. Vercel auto-deploy bekræftet ved at hente det live JS-bundle og finde
   feature-strenge (`Kvalitetsark`, `record_key_mangler`, `Prøvekørsel`,
   `OCR-kontekst`).
6. **Røgtest.** Udestående — kør §4 mod prod (kræver en redaktør i browseren).
7. **Ophæv evt. skrivefrys.** Ikke relevant — der blev ikke indført skrivefrys for
   denne feature.

**Rollback:** Featuren tilføjede kun nye objekter (journal-tabel, tre RPC'er, to
kolonner) — intet eksisterende kald er ændret. Web-laget kan rulles tilbage
uafhængigt ved at redeploye forrige commit.

---

## 6. Kendte begrænsninger (bevidste, ikke fejl)

1. **Prøvekørsel dækker ikke OCR-rettelser.** `red_ret_ocr_felt` har ingen dry-run-
   parameter, og `retOcrFelt` går uden om `submitChange`. Panelet **nægter derfor at
   gemme**, mens den globale prøvekørsel er slået til, frem for at simulere en
   skrivning der ikke findes. Rettelser er til gengæld fortrydbare via `change_set`.
2. **Kirkelige mærkedage er ikke portet til TypeScript.** `Mikkelsdag 1712` giver
   helår i browseren mod præcis `1712-09-29` i Python-udtrækket. Afvigelsen er grov,
   ikke forkert, og rammer kun datoer en redaktør selv indtaster. Lukkes som separat
   opgave, hvis behovet opstår.
3. **Ingen kalendervalidering.** `1500-04-31` accepteres som skrevet. Det er den
   eksisterende udtræksadfærd og ændres ikke her.
4. **`onRefreshRow` genhenter hele griddet.** Der findes ingen enkelt-række-RPC.
   Kaldet sker kun ved stale-fingerprint-retry, altså sjældent.
5. **Ingen mobil-flade.** Bevidst afgrænset til web ved skrivebordsbredde.
6. **Tema-tokens er kopieret tre steder** (`Redaktion.tsx`, `PersonKvalitetsark.tsx`,
   `OcrKildepanel.tsx`). Oprydning afventer en beslutning om et fælles redaktør-tema.
7. **To præeksisterende `db-verify`-fejl** på en tom base ("forventede 1 person-event"
   og `lineage_ancestors(I)`). Verificeret identiske på præ-feature-baselinen
   `2c8f3b6` — de er miljøbetingede, ikke regressioner.

---

## 7. Udskudte review-punkter — eksplicit afgjort

Reviewrunderne under task 1-4 efterlod fire mindre punkter. De er afgjort her, så de
ikke sejler videre som løse noter.

| Punkt | Afgørelse |
|---|---|
| Ingen test for at en ændret **importeret værdi** (ikke kun ændret OCR-kontekst) giver `stale` | **LUKKET.** Test tilføjet i `tests/testthat/test-load-daa.R`. Den asserter begge polariteter — uændret værdi giver `anvendt`, ændret værdi giver `stale` — og er derfor ikke tom. Punktet dækkede en fail-closed-garanti og var det eneste af de fire, der kunne skjule en reel fejl. |
| `db-verify` katalog-asserter ikke, at de to unikke indekser er **partielle** | **ACCEPTERET.** Prædikaterne `WHERE ... IS NOT NULL` blev bekræftet direkte i kataloget under task 1. En assert ville teste PostgreSQL' DDL-semantik, ikke vores invariant. |
| Dato-payload-validering afviser ikke **enhver** inkonsistent felt-kombination | **ACCEPTERET for v1.** Validering er fail-closed på de kombinationer der kan nå databasen gennem panelet; panelet sender ét felt ad gangen med faste former. En udtømmende kombinatorisk validering hører til, hvis payloaden nogensinde bliver åben for andre klienter. |
| Historik-test asserter ikke eksakt frossen aktør/tidsstempel/indhold og nyeste-først-identitet | **ACCEPTERET.** Rækkefølgen er fastlagt i SQL (`ORDER BY cs.created_at DESC, cs.id DESC, ce.seq DESC`) og dækket funktionelt. En test på eksakte tidsstempler ville være tidsafhængig uden at beskytte en invariant. |

---

**Oprettet:** 2026-07-26
