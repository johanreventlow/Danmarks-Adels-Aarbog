# Dual-review: loader append-sikkerhed (review 12, punkt 3)

**Dato:** 2026-07-02
**Diff under review:** commit `aafd7c1` (`.claude/skills/daa-extract/scripts/load_daa.R` + `SKILL.md`).
**Formål:** Lukker to KRITISK-fund: (1) `nid()` allokerede altid id'er fra 1 uanset basens indhold — append-forsøg mod en befolket base gav garanteret PK-kollision. (2) `RESET` var default TRUE (`--no-reset` som opt-out) — en glemt flag TRUNCATE'r 17 tabeller inkl. redaktionel historik.

## Phase 1 — Claude draft-review

### H1 [HIGH, verificeret] — nid() læste aldrig basen; fix porteret fra load_presens.R

**Lokation:** `.claude/skills/daa-extract/scripts/load_daa.R:49-58` (før: linje 41-43)

**Symptom (før):**
```r
.seq <- new.env(parent = emptyenv())
nid <- function(t) { v <- (if (is.null(.seq[[t]])) 0L else .seq[[t]]) + 1L; .seq[[t]] <- v; v }
```
Kommentaren hævdede "start fra max(id) i basen", men `.seq[[t]]` var altid `NULL` ved scriptstart (frisk environment) — `nid()` startede altid fra 1.

**Verifikation (empirisk, isoleret mod lokal Postgres-kopi):** seedede syntetisk "eksisterende slægt"-data inkl. `person.id=1`. Gammel `nid("person")` → `1` (ville PK-violere mod den eksisterende række). Ny `seed_seq()`-baseret `nid("person")` → `13` (korrekt fortsættelse fra `MAX(id)=12`).

**Fix:** porteret `load_presens.R`'s allerede-i-prod-brugte `seed_seq()`-mønster (linje 43-47 i den fil): `SELECT COALESCE(MAX(id),0) FROM <tabel>` pr. tabel i `id_tables`, kørt EFTER en evt. RESET-TRUNCATE, FØR første `nid()`-kald.

**Ikke fuldt end-til-ende-verificeret:** et forsøg på at køre HELE `load_daa.R` (inkl. `flush_all()`/`dbAppendTable`) mod en lokal Postgres-kopi via `RPostgres` stødte på et miljø-specifikt persistens-problem — den EGNE R-forbindelse så sine skrivninger (også efter `dbCommit()` returnerede `TRUE`), men en SEPARAT forbindelse (psql) så intet, hverken via TCP eller socket. **Reproducerede IDENTISK med det uændrede, git-HEAD~1 (prod-bevist, 925 rigtige personer loadet) script** — dvs. ikke en regression fra denne fix, men en lokal RPostgres/DBI/Postgres-version-kombination der ikke matcher hvordan koden faktisk opfører sig mod ægte Supabase. Blev IKKE forsøgt rettet (ude for scope); i stedet blev `seed_seq()`/`nid()`-logikken isoleret og testet direkte (uden om `flush_all()`/den fulde transaktion).

### H2 [MEDIUM, verificeret] — RESET flippet til opt-in (--reset), bekræftet af bruger

**Lokation:** `load_daa.R:6,27` + `SKILL.md:159-163`

Ændrer default fra "RESET=TRUE, --no-reset opt-out" til "RESET=FALSE, --reset opt-in", matcher `load_presens.R`'s eksisterende, allerede-i-prod-brugte konvention. **Dette er en behavior-default-ændring, ikke en ren bugfix** — eksplicit bekræftet med bruger via spørgsmål før implementering (ikke stiltiende ændret).

**Verifikation:** `Rscript`-argv-parsing testet isoleret: intet flag → `RESET=FALSE`; `--reset` → `RESET=TRUE`.

### Uafklarede punkter (kandidater til Codex)

**U1 — er `id_tables`-listen (14 tabeller) komplet og korrekt?** Listen blev konstrueret ved at grep'e efter alle `nid("...")`-literal-kald PLUS de tre indirekte kald via `get_or_create(tabel, ...)` (estate/organisation/historical_event). Er der andre steder i scriptet der allokerer et id til en tabel IKKE i denne liste (ville give `.seq[[t]]` = `NULL` → falder tilbage til at starte fra 1 for netop DEN tabel, reintroducerer bugget for et enkelt-tabel-blindt-punkt)?

**U2 — findes der en race/timing-fejl i PLACERINGEN af `seed_seq()`-kaldet** (linje ~185, efter `if (RESET) {...TRUNCATE...}`, før `seed_vocab()`)? Læser `seed_vocab()` eller noget mellem `seed_seq()` og første `nid()`-kald (`src <- nid("source")`, linje ~192) fra nogen af `id_tables`-tabellerne på en måde der kunne ændre `MAX(id)` FØR `nid()` bruger den cachede værdi (fx hvis `seed_vocab()` selv indsætter rækker i en af de 14 tabeller)?

**U3 — `flush_all()`'s FK-rækkefølge (`ord`-array, linje ~62-63 uændret af denne fix) — er den korrekt UAFHÆNGIGT af om id'erne nu starter fra et højere tal end 1?** (Burde være ja — id-VÆRDIER påvirker ikke FK-INDSÆTTELSESRÆKKEFØLGEN — men værd at få bekræftet, da det er tæt kode.)

## Phase 2-3 — Codex adversarial-review (2026-07-02)

**Trigger:** JA — R-eksekverbar kode, empiriske claims, KRITISK-severity-fund, ufuldstændig end-til-ende-verifikation (miljøkvirk).
**Verdict:** `needs-attention` — **"Do not ship yet."**

## Phase 4 — Reconcile

| Fund | Codex-dom | Klassifikation | Handling |
|---|---|---|---|
| H1 (nid/seed_seq) | confirmed, men "fix is only single-writer safe" | **verified** | Se M1 nedenfor — accepteret, ikke rettet denne omgang |
| H2 (RESET opt-in) | confirmed | **verified** | Ingen ændring |
| U1 (id_tables komplet) | dismissed | **verified** (jeg reproducerede selv: enumererede alle 11 literale + 3 indirekte `nid()`-kald via `get_or_create`, matcher `id_tables` 1:1) | Ingen fix nødvendig |
| U2 (seed_vocab-interferens) | dismissed for selve seed_vocab, **recalibreret til en bredere concurrency-bekymring** | **verified** (jeg reproducerede selv: `seed_vocab()` skriver KUN til `vocab`, som bruger komposit-nøgle `(scheme,code)`, ikke `nid()` — ingen af de 14 `id_tables` berøres) | Ingen fix for U2 som stillet; den bredere concurrency-bekymring dækkes af M2 nedenfor |
| U3 (FK-rækkefølge id-uafhængig) | confirmed | **verified** (Codex bekræfter: `flush_all()`'s `ord`-array styrer INDSÆTTELSESRÆKKEFØLGE via tabelnavn, ikke id-værdier — uændret af denne fix) | Ingen fix nødvendig |

**Nye fund (Codex, ikke i mit draft):**

**H1-ny [HIGH, verificeret + RETTET] — Append-mode duplikerede fælles-entiteter i stedet for at genbruge dem.**
`.cache` (bruges af `get_place`/`get_or_create` til at deduplikere sted/gods/organisation/begivenhed — datamodellens invariant om FÆLLES entiteter) er en frisk, tom `new.env()` ved hver scriptkørsel (`load_daa.R:97`, uændret af den oprindelige fix). Den populeres UDELUKKENDE fra poster behandlet I DENNE kørsel — læser aldrig eksisterende rækker fra basen. Konsekvens: hvis slægt B's `clean.json` nævner et gods/sted/organisation der allerede findes fra slægt A's load (fx et fælles gods to slægter begge har ejet), opretter append-mode en DUPLIKAT-række med nyt id i stedet for at genbruge den eksisterende — stille semantisk datakorruption af netop de entitetstyper datamodellen definerer som fælles (datamodel §5).
**Reproduktion (verified, egen isoleret test mod lokal DB):** seedede en eksisterende `estate`-række ("Eksisterende Gods", id=2). Uden fix: ville `get_or_create("estate", "Eksisterende Gods")` allokere et NYT id (`.cache` tom → cache-miss). Med fix: `preload_cache()` forudindlæser `.cache` fra `SELECT id, navn FROM place/estate/organisation/historical_event` (samme nøgleformat som `get_or_create` selv bruger — `tabel::lowercase(navn)`), kørt lige efter `seed_seq()`. Testet 3 tilfælde: eksisterende navn → genbrugt id=2 (`was_new=FALSE`); samme navn med anden bogstavering → stadig genbrugt (case-insensitiv match bevaret); genuint nyt navn → korrekt behandlet som nyt (`was_new=TRUE`). No-op i RESET-mode (tomme tabeller efter TRUNCATE).
**Status:** RETTET i samme commit-serie (se `preload_cache()`, `load_daa.R:98-110`, kaldt `load_daa.R:202`).

**M2 [MEDIUM, verificeret, IKKE rettet denne omgang] — MAX(id) race mellem samtidige loader-kørsler.**
`seed_seq()` læser et ulåst `MAX(id)` ind i proces-lokale tællere; to samtidige loader-kørsler kunne seede identiske ranges før nogen af dem flusher, hvilket ville give PK-kollision ved commit (fanges af transaktionen — ingen delvis-skrivning, men kørslen fejler). **Vurdering: legitimt, men bevidst udskudt** — (a) dette er en EKSISTERENDE egenskab ved det allerede-i-prod-brugte `load_presens.R`-mønster jeg porterede, ikke noget nyt jeg introducerer; (b) loaderen er et manuelt, operatør-kørt CLI-værktøj (ikke en server/API), hvor samtidige kørsler kræver at et menneske eksplicit starter to `Rscript`-processer samtidig; (c) den rigtige fix (Postgres-sekvenser/IDENTITY i stedet for `max(id)+1`-mønsteret) er ALLEREDE et separat, planlagt punkt i review 12 §5 (punkt 4, "sekvens-migrering — redaktør #2") som dækker præcis denne klasse af race også for `red_*`-RPC'erne. Retro-fitte en advisory-lock kun i denne loader, adskilt fra den planlagte sekvens-migrering, ville være en delvis/inkonsistent fix. **Deferred til punkt 4.**

**Mindre korrektion (Codex):** min egen tidligere kommunikation (chat + commit-besked) sagde "TRUNCATE'r 17 tabeller" — `model_tables`-arrayet har faktisk 18 elementer (talt: note, citation, conclusion, assertion, relation, fact, family_member, family, person_external_id, narrative, person, coat_of_arms, historical_event, media, estate, organisation, place, source). Ren dokumentations-unøjagtighed, ingen kode-konsekvens. Rettes fremadrettet (ikke i allerede-committede commit-beskeder, jf. no-amend-uden-eksplicit-anmodning).

**Læring:** Min oprindelige fix løste PK-kollisions-krascet (H1) korrekt, men overså en RELATERET men DISTINKT konsekvens af "genindfør append-mode": enhver in-memory dedup-cache der bygges op fra-scratch pr. kørsel (ikke kun id-tælleren) skal preloades fra basen for at append-semantik reelt holder. Generelt mønster at huske ved fremtidig append-mode-arbejde: "hvad AF DET SCRIPTET HOLDER I HUKOMMELSEN antager stiltiende at det er den FØRSTE kørsel?" — id-tælleren var det ÅBENLYSE tilfælde (allerede i reviewet); entity-cachen var det SKJULTE tilfælde Codex fandt.
