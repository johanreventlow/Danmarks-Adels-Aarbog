# Design: Versionering (ændringshistorik + restore) og hyperlinks i tekster

**Dato:** 2026-06-30
**Status:** Godkendt design — klar til implementeringsplan
**Scope:** To additive features i den eksisterende evidensbaserede datamodel (Supabase/Postgres). PoC: Reventlow.

---

## 1. Formål

To redaktionelle features til følgesvend-appen:

1. **Hyperlinks i tekster** — redaktøren kan indsætte klikbare links fra fri-tekst (narrativer, noter) til personer og andre entiteter.
2. **Versionering** — en fuld ændringslog over *alt redaktionelt* (fakta, relationer, konfidens, narrativer, noter), med mulighed for at **fortryde** (restore) enhver ændring tilbage til tidligere tilstand. Det skal altid kunne ses **hvem** der har redigeret hvad og hvornår.

Begge er additive: ingen eksisterende tabel skifter betydning, intet brydes. De er synergiske — versionering gør hyperlinks robuste ved restore, og begge genbruger modellens eksisterende mønstre (polymorfe `(type,id)`, afledt projektion, evidens-som-historik).

---

## 2. Beslutninger truffet under brainstorm

| # | Beslutning | Begrundelse |
|---|---|---|
| B1 | **Scope:** log på *alt redaktionelt*, restore på *alt*. | Brugerønske: maksimal sporbarhed + fortrydelse. |
| B2 | **Fangst-mekanisme: hybrid** (DB-trigger gør tungt før/efter-snapshot; RPC åbner change_set via session-variabel). | Trigger = komplet + DRY; RPC-flag = ingen bulk-load-støj + semantisk etiket. Se §4.3. |
| B3 | **Attribution snapshottes** (frosset `actor_navn` på change_set, ikke kun FK). | Audit-log skal forblive læsbar selv om brugeren senere omdøbes/slettes. |
| B4 | **Hyperlinks = inline-markup-token** i teksten (ikke offset-baseret annotation-tabel). | Tokenet bor i prosaen → versioneres gratis ved restore. Offsets ville brække ved hver redigering/tilbagerulning. Se §5. |
| B5 | **`red_edit_oplysning` skifter til append** (ny påstand + re-peg konklusion) frem for direkte `UPDATE assertion`. | Ærer invariant #1 (*påstande uforanderlige*); versionering gør append billigt. Se §6. |
| B6 | **Restore-konflikt: detektér + advar, last-write-wins ved bekræftelse.** Ingen grene, ingen merge. | "Enklere end git." Se §4.5. |

---

## 3. Datamodel-invarianter respekteret

- **Evidens-som-historik:** fakta har allerede native versionering (uforanderlige påstande + foranderlig konklusion). Versioneringen her *supplerer* dette for de foranderlige dele (narrativer, relationer, flag) og giver ét fælles, fortryd-bart change-set-lag ovenpå — den re-peger fx konklusion til en tidligere påstand ved restore frem for at duplikere evidenslagets logik.
- **Afledt projektion:** `text_mention`-indekset (§5.3) regenereres fra teksten, redigeres aldrig direkte — samme envejs-mønster som `person.visning_*`-cachen.
- **Polymorfe referencer:** hyperlink-token og change_event bruger `(type, id)`-par uden hård FK, som resten af modellen.

---

## 4. Versionering

### 4.1 `change_set` — ét "commit" (én redaktionel handling)

| felt | type | hvad |
|---|---|---|
| `id` | BIGINT PK | |
| `actor_id` | UUID → `auth.users` | hvem (FK, nullable for system) |
| `actor_navn` | TEXT | **frosset** navn-snapshot på commit-tidspunktet |
| `actor_rolle` | TEXT | frosset rolle |
| `created_at` | TIMESTAMPTZ DEFAULT now() | hvornår |
| `operation` | TEXT | maskin-etiket, fx `red_upsert_fakta` |
| `summary` | TEXT | menneske-tekst, fx "Rettede dødsdato på Chr. Ditlev Reventlow" |
| `subjekt_type` | TEXT | hint til filtrering ("historik for denne person") |
| `subjekt_id` | BIGINT | hint |
| `reverted_by` | BIGINT → change_set(id) | nullable; peger på det change_set der fortrød dette (giver redo) |

### 4.2 `change_event` — én rørt række inden i et change_set

| felt | type | hvad |
|---|---|---|
| `id` | BIGINT PK | |
| `change_set_id` | BIGINT → change_set(id) | |
| `seq` | INT | rækkefølge inden for change_set (afgør korrekt baglæns inverse-apply) |
| `tabel` | TEXT | fx `assertion` |
| `row_pk` | JSONB | sammensat PK håndteres (`family_member` har 3-kolonne PK) |
| `op` | TEXT | `INSERT` / `UPDATE` / `DELETE` |
| `foer` | JSONB | hele OLD-rækken (NULL ved INSERT) |
| `efter` | JSONB | hele NEW-rækken (NULL ved DELETE) |

### 4.3 Plumbing (hybrid)

1. **`begin_change_set(operation, summary, subjekt_type, subjekt_id) RETURNS bigint`**
   - Indsætter change_set-rækken (slår `actor_navn`/`actor_rolle` op fra `profiles` for `auth.uid()`, email som fallback).
   - Sætter session-variabel: `PERFORM set_config('app.change_set_id', <id>::text, true)` (txn-local).
   - Sætter `app.change_seq` = 0.
   - Kaldes som **første linje** i hver `red_*`-RPC.

2. **Generisk trigger-funktion `log_change()`** (AFTER INSERT/UPDATE/DELETE, FOR EACH ROW):
   - `cs := current_setting('app.change_set_id', true)`. **Hvis NULL/tom → RETURN** (bulk-load-sti: ingen logning).
   - Ellers: inkrementér seq, indsæt change_event med `TG_TABLE_NAME`, `TG_OP`, `to_jsonb(OLD)`, `to_jsonb(NEW)`, og PK udtrukket til `row_pk`.
   - Én funktion, genbrugt på alle loggede tabeller.

3. **Triggere tilknyttes:** `assertion`, `conclusion`, `citation`, `fact`, `relation`, `family`, `family_member`, `narrative`, `note`, `person`.
   - **`person`:** cache-kolonnerne (`visning_*`) regenereres af eksisterende triggere og udelukkes fra logning (de er afledte, ikke redaktionelle). Implementeres ved kun at logge når ikke-cache-kolonner ændrer sig (sammenlign OLD/NEW på `koen`/`privat`/`status`/`levende`), ellers RETURN.

4. **Bulk-load** (`/daa-extract`, `load_daa.R`) sætter aldrig `app.change_set_id` → seed forbliver tavst og loggen ren. Ingen ændring nødvendig i loaderen.

### 4.4 Restore — fortryd et change_set

`red_fortryd_change_set(p_change_set_id bigint)`:
1. Åbn et **nyt** change_set (`operation='fortryd'`, summary="Fortrød: <original summary>") — fortrydelsen logges også og er selv fortryd-bar (= redo).
2. Gennemløb originalens change_events i **omvendt `seq`-orden** og anvend inverse:
   - `INSERT` → `DELETE` rækken (by `row_pk`)
   - `DELETE` → genindsæt `foer`
   - `UPDATE` → sæt rækken tilbage til `foer`
3. Markér originalen: `reverted_by = <nyt change_set id>`.

Restore på fakta falder naturligt ud af dette: en re-peget konklusion er bare en `UPDATE conclusion` der rulles tilbage.

### 4.5 Restore-konflikt (B6)

Hvis en *nyere* change_set har rørt en af de samme rækker (match på `tabel`+`row_pk` i et change_event med højere `created_at`), kan fortrydelse af den ældre overskrive den nyere.

- **Adfærd:** `red_fortryd_change_set` får parameter `p_force boolean DEFAULT false`. Uden force: hvis konflikt detekteres → `RAISE EXCEPTION` med besked om hvilke nyere change_sets der rører samme data. UI viser advarsel; bruger bekræfter → kald igen med `p_force=true` → last-write-wins.
- Ingen grene, ingen merge, ingen tre-vejs-fletning.

### 4.6 ID-tildeling

Følger basens nuværende `max(id)+1`-mønster (race-følsomt, accepteret under single-writer-PoC — samme klasse som de eksisterende RPC'er). Re-indsættelse ved DELETE-restore genbruger den oprindelige `id` fra `foer`-snapshottet. Migrér til IDENTITY/sekvenser når flerbruger-skrivning aktiveres (eksisterende kendt gæld).

---

## 5. Hyperlinks

### 5.1 Format

Inline-token i fri-tekst-felter (`narrative.tekst`, `note.indhold`):

```
[[person:482|Christian Ditlev Reventlow]]
  type   id   visningstekst
```

`type` ∈ { `person`, `estate`, `place`, `organisation`, `source`, `coat_of_arms`, `family`, `historical_event`, `media`, `lineage` } — samme polymorfe entitetssæt som resten af modellen.

### 5.2 Rendering & eksport

- **App:** parser tokens → klikbart link til entitetens visning.
- **GEDCOM/tekst-eksport:** fladgøres til ren `visningstekst` (linket droppes). Visningsteksten bor i tokenet → eksport forbliver læsbar.

### 5.3 Referentiel integritet (ingen FK i fri-tekst)

Et token kan pege på en slettet entitet. To greb:

1. **Visningsteksten er gemt i tokenet** → et dødt link viser stadig læsbar tekst, brækker ikke siden.
2. **Afledt nævne-indeks `text_mention`** (regenereret af trigger ved narrativ/note-gem):

   | felt | type |
   |---|---|
   | `kilde_type` | TEXT (`narrative`/`note`) |
   | `kilde_id` | BIGINT |
   | `maal_type` | TEXT |
   | `maal_id` | BIGINT |

   - **Ikke** sandhedskilde (tokenet er) — ren projektion, som `visning_*`. Versioneres ikke; regenereres.
   - Køber: **baglæns-links** ("hvor er person X nævnt?") + **døde-links-rapport** til redaktions-dashboardet (mention hvor `maal_id` ikke længere findes).
   - Genereres af en trigger på `narrative`/`note` der parser tokens ud af teksten (regex på `[[type:id|...]]`) og opdaterer indekset for den række.

### 5.4 Indsættelse (UI — udskudt)

@-vælger i editoren der opslår entitet og producerer tokenet. Datamodel-uafhængigt; hører til implementeringsplanen for app-laget.

---

## 6. Touchpoints i eksisterende kode

| Område | Ændring | Størrelse |
|---|---|---|
| Alle `red_*`-RPC'er | Tilføj `begin_change_set(...)` som første linje | mekanisk |
| `red_edit_oplysning` | **B5:** skift fra direkte `UPDATE assertion` til append (ny påstand + `red_set_konklusion`-re-peg). Honorerer invariant #1. | lille refactor |
| `profiles` | Tilføj `navn TEXT` (kilde til frosset `actor_navn`; email fallback) | additivt ALTER |
| `schema.sql` + `db-migrations.sql` | Nye tabeller (`change_set`, `change_event`, `text_mention`), generisk trigger + tilknytninger, `begin_change_set`, `red_fortryd_change_set`, mention-trigger, historik-views | ny idempotent blok |
| **RLS** | Politikker for `change_set`/`change_event`/`text_mention`. Se §7. | afhænger af RLS-lag |
| App (TS) | Editor m. @-vælger, token-renderer, historik-visning, fortryd-knap, døde-links-rapport | separat impl-plan |

---

## 7. RLS / synlighed (skal lukkes mod det kommende RLS-lag)

Historik kan lække ellers-skjulte data (en fortrudt privat-biografi ligger i `change_event.foer`). Regler:

- **Redaktion:** ser al historik.
- **Medlem/anonym:** ser kun historik for entiteter de i forvejen må se. Historik for en levende/privat person følger **samme synlighed som personen selv**.
- **Implementering:** `change_event` indeholder rå `foer`/`efter`-JSONB af potentielt private rækker → må aldrig eksponeres bredt. Historik-views skal bruge `security_invoker = true` (samme fælde som `red_konflikt`-viewet) og filtrere på personens synlighed.
- Konkret politik-SQL skrives sammen med det øvrige RLS-lag (endnu ikke skrevet — jf. CLAUDE.md §9). Dette spec fastlægger *reglen*; politik-koden er en afhængighed.

---

## 8. Bevidst udeladt (YAGNI)

- **Grene/merge** i versioneringen — kun lineær log + last-write-wins-restore.
- **Diff-visning på ord-niveau** for narrativer — før/efter-tekst gemmes; pæn diff-UI er senere pynt.
- **Offset-baserede annotationer** for hyperlinks — afvist (B4).
- **Logning af bulk-load** — bevidst tavs (B2).
- **IDENTITY/sekvens-migrering** — eksisterende gæld, ikke en del af dette.

---

## 9. Åbne afhængigheder

1. **RLS-laget** (§7) skal eksistere før multi-bruger-eksponering af historik.
2. **App-impl-plan** for editor/renderer/historik-UI er separat (TS-spor).
