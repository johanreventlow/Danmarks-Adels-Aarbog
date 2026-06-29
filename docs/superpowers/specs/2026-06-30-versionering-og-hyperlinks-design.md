# Design: Versionering (ændringshistorik + restore) og hyperlinks i tekster

**Dato:** 2026-06-30
**Status:** Godkendt design, hærdet efter Codex adversarisk review — klar til implementeringsplan
**Scope:** To additive features i den eksisterende evidensbaserede datamodel (Supabase/Postgres). PoC: Reventlow.

---

## 1. Formål

To redaktionelle features til følgesvend-appen:

1. **Hyperlinks i tekster** — redaktøren kan indsætte klikbare links fra fri-tekst (narrativer, noter) til personer og andre entiteter.
2. **Versionering** — en fuld ændringslog over *alt redaktionelt* (fakta, relationer, konfidens, narrativer, noter, kontekst-entiteter), med mulighed for at **fortryde** (restore) enhver ændring tilbage til tidligere tilstand. Det skal altid kunne ses **hvem** der har redigeret hvad og hvornår.

Begge er additive: ingen eksisterende tabel skifter betydning, intet brydes. De er synergiske — versionering gør hyperlinks robuste ved restore, og begge genbruger modellens eksisterende mønstre (polymorfe `(type,id)`, afledt projektion, evidens-som-historik).

---

## 2. Beslutninger

| # | Beslutning | Begrundelse |
|---|---|---|
| B1 | **Scope:** log på *alt redaktionelt* (ekshaustiv tabel-liste, §4.3.1), restore på *alt*. | Brugerønske: maksimal sporbarhed + fortrydelse. |
| B2 | **Fangst-mekanisme: hybrid** (DB-trigger gør tungt før/efter-snapshot; RPC åbner change_set via session-variabel). | Trigger = komplet + DRY; RPC-flag = ingen bulk-load-støj + semantisk etiket. |
| B3 | **Attribution snapshottes** (frosset `actor_navn`/`actor_rolle` på change_set; `actor_id`-FK er `ON DELETE SET NULL`, og de frosne felter er den autoritative kilde). | Audit-log skal forblive læsbar selv om brugeren senere omdøbes/slettes. |
| B4 | **Hyperlinks = inline-markup-token** i teksten (ikke offset-baseret annotation-tabel). | Tokenet bor i prosaen → versioneres gratis ved restore. |
| B5 | **`red_edit_oplysning` skifter til append** (ny påstand + re-peg konklusion). | Ærer invariant #1 (*påstande uforanderlige*). NB: kalder *ikke* `red_set_konklusion` som nested RPC — bruger en intern hjælper uden eget change_set (B7). |
| B6 | **Restore-konflikt: optimistisk verifikation + advar.** Ingen grene, ingen merge. | "Enklere end git", men sikkert (B9). |
| **B7** | **`begin_change_set` er re-entrant:** yderste RPC ejer change_set; indre kald genbruger det aktive (opretter ikke nyt, nulstiller ikke session-variablen). | Fjerner H1: nested `red_*` ville ellers splitte én handling over flere change_sets. |
| **B8** | **Per-tabel versionerbar-kolonne-projektion.** `person.visning_*` (ren cache) udelukkes fra både snapshot og inverse; cache regenereres én gang efter restore. `koen`/`privat`/`status`/`levende` ER redaktionelle → versioneres. | Fjerner H2: hele-række-snapshot ville ellers rulle forældet cache tilbage. |
| **B9** | **Optimistisk inverse-apply:** før hvert inverse sammenlignes den nuværende række med change_event'ets `efter`-snapshot. Divergens → afbryd og rapportér (også under `p_force`, som rapporterer divergensen frem for at overskrive blindt). | Fjerner H4: blind PK-baseret overskrivning kunne smadre en fremmed/genbrugt række. |
| **B10** | **Historik er kun synlig for redaktion i PoC** (deny-all RLS for medlemmer; al adgang via SECURITY DEFINER-API, ingen rå table-grants på `change_set`/`change_event`). | Neutraliserer C1+M4 (GDPR-læk via `foer`-snapshot) pragmatisk; medlems-vendt historik m. frosset synligheds-metadata er fremtids-sti (§7). |
| **B11** | **Eksplicit table→PK-registry** styrer `row_pk`-udtræk (kanonisk JSON-nøgleorden, type-bevarende). | Fjerner M2: sammensatte/forskelligt-navngivne PK'er (`family_member` 3-kol, `person_external_id` 2-kol, `vocab` 2-kol). |
| **B12** | **Hyperlinks er IKKE round-trip-bare ved eksport i PoC** (fladgøres til visningstekst; type/id tabes). Fremtidig GEDCOM SCHMA-extension kan bevare mål-identitet. | Lukker M6 som bevidst valg frem for skjult tab. |

---

## 3. Datamodel-invarianter respekteret

- **Evidens-som-historik:** fakta har allerede native versionering (uforanderlige påstande + foranderlig konklusion). Versioneringen her *supplerer* dette for de foranderlige dele og giver ét fælles, fortryd-bart change-set-lag ovenpå — restore re-peger fx konklusion til en tidligere påstand frem for at duplikere evidenslagets logik.
- **Afledt projektion:** `text_mention`-indekset (§5.3) og `person.visning_*` regenereres, redigeres/versioneres aldrig direkte (B8).
- **Polymorfe referencer:** hyperlink-token og change_event bruger `(type, id)`-par uden hård FK.

---

## 4. Versionering

### 4.1 `change_set` — ét "commit" (én redaktionel handling)

| felt | type | hvad |
|---|---|---|
| `id` | BIGINT PK | |
| `actor_id` | UUID → `auth.users` **ON DELETE SET NULL** | hvem (nullable; frosne felter er autoritative — B3) |
| `actor_navn` | TEXT | **frosset** navn-snapshot på commit-tidspunktet |
| `actor_rolle` | TEXT | frosset rolle |
| `created_at` | TIMESTAMPTZ DEFAULT now() | hvornår |
| `operation` | TEXT | maskin-etiket, fx `red_upsert_fakta` |
| `summary` | TEXT | menneske-tekst, fx "Rettede dødsdato på Chr. Ditlev Reventlow" |
| `subjekt_type` | TEXT | hint til filtrering ("historik for denne person") |
| `subjekt_id` | BIGINT | hint |
| `subjekt_synlighed` | TEXT | **frosset** synligheds-klasse (`offentlig`/`levende`/`privat`) på commit-tidspunktet → tillader RLS-autorisation efter at subjektet er slettet (C1-sti for fremtidig medlems-historik) |
| `reverteret` | BOOLEAN DEFAULT false | afledt cache; sandheden er reversal-kæden (B-felt nedenfor) |
| `reverterer_id` | BIGINT → change_set(id) | hvis dette change_set ER en fortrydelse: hvilket sæt det fortrød (immutabel reversal-kæde — M3) |

Undo-tilstand udledes af `reverterer_id`-kæden, ikke af en muterbar peger: et change_set er "aktivt" hvis intet senere, ikke-selv-reverteret sæt peger på det via `reverterer_id`. Gentaget undo/redo bliver dermed en kæde af reversaler (B7→fortryd→fortryd-af-fortryd …), og man kan afvise at fortryde et allerede-reverteret sæt.

### 4.2 `change_event` — én rørt række inden i et change_set

| felt | type | hvad |
|---|---|---|
| `id` | BIGINT PK | |
| `change_set_id` | BIGINT → change_set(id) | |
| `seq` | INT | rækkefølge inden for change_set (afgør baglæns inverse-apply) |
| `tabel` | TEXT | fx `assertion` |
| `row_pk` | JSONB | kanonisk PK-repræsentation via table→PK-registry (B11) |
| `op` | TEXT | `INSERT` / `UPDATE` / `DELETE` |
| `foer` | JSONB | versionerbare kolonner af OLD-rækken (NULL ved INSERT; ekskl. `visning_*` — B8) |
| `efter` | JSONB | versionerbare kolonner af NEW-rækken (NULL ved DELETE; ekskl. `visning_*` — B8) |

### 4.3 Plumbing (hybrid)

**`begin_change_set(operation, summary, subjekt_type, subjekt_id) RETURNS bigint` (re-entrant — B7):**
- Hvis `current_setting('app.change_set_id', true)` allerede er sat → returnér det eksisterende id (genbrug; opret intet nyt, nulstil intet).
- Ellers: slå `actor_navn`/`actor_rolle` op fra `profiles` for `auth.uid()` (email som fallback), beregn `subjekt_synlighed`, indsæt change_set-rækken, `PERFORM set_config('app.change_set_id', <id>::text, true)`, `app.change_seq=0`.
- Kaldes som **første linje** i hver `red_*`-RPC. Interne hjælpere (fx B5's re-peg) kalder ikke en anden change_set-åbnende RPC; de udfører rå DML, som triggeren fanger ind under det aktive sæt.

**Generisk trigger `log_change()`** (AFTER INSERT/UPDATE/DELETE, FOR EACH ROW):
- `cs := current_setting('app.change_set_id', true)`. **NULL/tom → RETURN** (bulk-load-sti).
- Slå tabellens versionerbare kolonner + PK-kolonner op i registry (B8/B11); byg `foer`/`efter`/`row_pk` ud fra projektionen (ikke rå `to_jsonb(OLD/NEW)`).
- For `person`: hvis kun `visning_*` ændrede sig → RETURN (cache-regenerering logges ikke).
- Inkrementér seq, indsæt change_event.

#### 4.3.1 Versioneret scope (ekshaustivt — B1, lukker C2+H3)

**Loggede tabeller:** `person` (ekskl. `visning_*`), `person_external_id`, `family`, `family_member`, `fact`, `relation`, `assertion`, `conclusion`, `citation`, `narrative`, `note`, `source`, `repository`, `place`, `organisation`, `estate`, `media`, `historical_event`, `coat_of_arms`, `lineage`, `vocab`.

**`profiles`:** versionér kun `reventlow_person_id`-bindingen (redaktionel relation til træet). `email`/`rolle`/`id` versioneres ikke (auth/PII). Dette sikrer at person-restore genskaber profil-bindingen (C2).

**Ikke logget:** `change_set`, `change_event`, `text_mention` (selv-reference / afledt), `suggestion` (staging).

### 4.4 Restore — fortryd et change_set (én transaktion — M1/H5)

`red_fortryd_change_set(p_change_set_id bigint, p_force boolean DEFAULT false)`:
1. Afvis hvis sættet allerede er reverteret (§4.1-kæde) eller er bulk/system.
2. Åbn et **nyt** change_set (`operation='fortryd'`, `reverterer_id=p_change_set_id`).
3. Gennemløb originalens events i **omvendt `seq`-orden**. For hvert event:
   - **Optimistisk tjek (B9):** hent nuværende række via `row_pk`; sammenlign med event'ets `efter`. Divergens (og ikke `p_force`) → `RAISE EXCEPTION` med rapport. Under `p_force`: log divergensen i summary, fortsæt.
   - Anvend inverse: `INSERT`→slet · `DELETE`→genindsæt `foer` · `UPDATE`→sæt tilbage til `foer`.
4. Regenerér afledte projektioner **én gang** til sidst: berørte personers `visning_*` (kald `regen_person_visning`) og `text_mention` for berørte narrativer/noter.
5. **Hele operationen er én transaktion.** Ingen per-event exception-swallowing; enhver fejl ruller hele inversen + det nye change_set tilbage.

**FK-sikkerhed (H5):** omvendt-seq giver FK-sikker genindsættelse, *fordi* destruktive RPC'er sletter børn før forældre (eksisterende invariant i `red_slet_person`/`red_slet_relation`). **Krav til implementeringen:** hver destruktiv RPC skal have en test der verificerer fuld restore af dens afhængighedsgraf. Fremtidig hærdning hvis cascades introduceres: `SET CONSTRAINTS ALL DEFERRED` i restore-transaktionen.

### 4.5 Restore-konflikt (B6/B9)

Konflikt = den optimistiske `efter`-sammenligning (§4.4 trin 3) fejler: den nuværende række matcher ikke hvad change_set'et efterlod. Det fanger både loggede *og* uloggede mellemliggende ændringer (B9 dækker H4's PK-genbrug, da en genbrugt PK giver en ikke-matchende `efter`). Uden `p_force`: afbryd + rapportér de afvigende rækker. Med `p_force`: last-write-wins, divergens noteret i audit-summary.

### 4.6 ID-tildeling

Følger basens `max(id)+1`-mønster (single-writer-PoC; eksisterende gæld). DELETE-restore genbruger oprindelig `id` fra `foer`. Den optimistiske `efter`-kontrol (B9) beskytter mod at en mellemtidig genbrugt PK overskrives blindt. Migrér til IDENTITY/sekvenser ved flerbruger-skrivning.

---

## 5. Hyperlinks

### 5.1 Token-grammatik (formel — M5)

Inline-token i fri-tekst (`narrative.tekst`, `note.indhold`):

```
[[<type>:<id>|<visningstekst>]]
```

- `type` ∈ fast vokabular: `person`, `estate`, `place`, `organisation`, `source`, `coat_of_arms`, `family`, `historical_event`, `media`, `lineage`. Ukendt type → behandles som almindelig tekst (ikke link).
- `id` = heltal uden foranstillede nuller.
- `visningstekst` = vilkårlig tekst; tegnene `|`, `[`, `]` escapes som `\|`, `\[`, `\]`. Parser læser ikke-escaped `]]` som token-slut.
- **Malformet token** (manglende felt, ikke-talt id, ukendt type, ubalanceret) → renderes som rå tekst, indekseres ikke, fejler ikke.
- Én delt parser-specifikation + conformance-fixtures bruges af editor, renderer, indekser og eksport (samme adfærd alle steder).

### 5.2 Rendering & eksport

- **App:** parser tokens → klikbart link til entitetens visning.
- **Eksport (GEDCOM/tekst):** fladgøres til `visningstekst` (escapes fjernes). **Links er ikke round-trip-bare i PoC (B12)** — type/id tabes; re-import genskaber ikke linket. Fremtidig SCHMA-extension kan bevare mål-identitet hvis det bliver et krav.

### 5.3 Afledt nævne-indeks `text_mention` (L1)

| felt | type |
|---|---|
| `kilde_type` | TEXT (`narrative`/`note`) |
| `kilde_id` | BIGINT |
| `maal_type` | TEXT |
| `maal_id` | BIGINT |
| **PK** | `(kilde_type, kilde_id, maal_type, maal_id)` — dedupliceret pr. kilde-række (gentagne nævnelser af samme mål = én række; positioner gemmes ikke) |

- **Ikke** sandhedskilde (tokenet er); ren projektion, regenereres. Trigger på `narrative`/`note` parser tokens og **erstatter hele projektionen for den kilde-række** (DELETE eksisterende for `(kilde_type,kilde_id)` + INSERT nye).
- Køber: baglæns-links ("hvor er X nævnt?") + døde-links-rapport (`maal_id` findes ikke længere).
- **RLS (M4):** en `text_mention` eksponeres kun hvis **både** kilde-teksten (`narrative`/`note` synlighed, inkl. `privat`-flag) **og** mål-entiteten er synlig for kalderen. Forældreløse kilde-ID'er afsløres ikke.

### 5.4 Indsættelse (UI — udskudt)

@-vælger i editoren der opslår entitet og producerer tokenet. Hører til app-lagets implementeringsplan.

---

## 6. Touchpoints i eksisterende kode

| Område | Ændring | Størrelse |
|---|---|---|
| Alle `red_*`-RPC'er | Tilføj `begin_change_set(...)` (re-entrant) som første linje | mekanisk |
| `red_edit_oplysning` | B5: append (ny påstand) via intern hjælper (ikke nested RPC — B7) | lille refactor |
| `profiles` | Tilføj `navn TEXT`; versionér kun `reventlow_person_id` (§4.3.1) | additivt ALTER |
| `schema.sql` + `db-migrations.sql` | Nye tabeller (`change_set`, `change_event`, `text_mention`), table→PK-registry, generisk trigger + tilknytninger (§4.3.1), `begin_change_set`, `red_fortryd_change_set`, mention-trigger, SECURITY DEFINER-historik-API | ny idempotent blok |
| **RLS** | Deny-all på historik-tabeller; redaktion-only adgang via API (B10); `text_mention`-gating (M4) | se §7 |
| App (TS) | Editor m. @-vælger, token-renderer (delt parser), historik-visning, fortryd-knap, døde-links-rapport | separat impl-plan |

---

## 7. RLS / synlighed

- **PoC (B10):** `change_set`/`change_event`/`text_mention` har deny-all RLS for ikke-redaktion. Al historik-læsning sker via SECURITY DEFINER-funktioner der kun returnerer til `current_rolle()='redaktion'`. Ingen rå `foer`/`efter` eksponeres til medlemmer. Dette neutraliserer C1+M4 for PoC.
- **Fremtid (medlems-vendt historik):** brug frosset `subjekt_synlighed` (§4.1) + mål/kilde-gating (§5.3) til at autorisere historiske rækker selv efter at subjektet er slettet. Aldrig rå table-grant.
- Historik-API-funktioner bruger samme `security_invoker`/SECURITY DEFINER-disciplin som `red_konflikt`-viewet for ikke at omgå person-synlighed.
- Konkret politik-SQL skrives sammen med det øvrige RLS-lag (endnu ikke skrevet — jf. CLAUDE.md §9). Dette spec fastlægger *reglerne*; politik-koden er en afhængighed.

---

## 8. Bevidst udeladt (YAGNI)

- **Grene/merge** — kun lineær log + optimistisk last-write-wins-restore.
- **Diff-UI på ord-niveau** — før/efter-tekst gemmes; pæn diff er senere pynt.
- **Medlems-vendt historik** — kun redaktion i PoC (B10).
- **Round-trip-bare hyperlinks i eksport** — udeladt (B12).
- **Logning af bulk-load** — bevidst tavs (B2).
- **IDENTITY/sekvens-migrering** — eksisterende gæld.
- **Deferred FK-constraints i restore** — kun hvis cascades introduceres (§4.4).

---

## 9. Åbne afhængigheder

1. **RLS-laget** (§7) skal eksistere før evt. medlems-vendt historik.
2. **App-impl-plan** for editor/renderer/historik-UI er separat (TS-spor).
3. **Table→PK-registry** (B11) skal defineres konkret i implementeringen (kan udledes fra `information_schema` eller hardcodes).

---

## Bilag A — Codex adversarisk review (2026-06-30)

16 findings (2 Critical, 6 High, 6 Medium, 1 Low), alle indarbejdet:

| ID | Severity | Lukket af |
|---|---|---|
| C1 historik-filtrering efter sletning | Critical | B10 (redaktion-only) + `subjekt_synlighed` (§4.1) |
| C2 person-restore mister ulogget tilstand | Critical | §4.3.1 (ekshaustiv scope inkl. `person_external_id`/`profiles`) |
| H1 nested RPC splitter change_set | High | B7 (re-entrant) |
| H2 snapshot ruller cache/`koen` tilbage | High | B8 (kolonne-projektion) |
| H3 scope mangler entitets-klasser | High | §4.3.1 |
| H4 konflikt-tjek usikkert | High | B9 (optimistisk `efter`-verifikation) |
| H5 baglæns-seq ikke FK-garanteret | High | §4.4 (RPC-invariant + restore-tests + deferred-constraints-sti) |
| H6 actor-FK blokerer sletning | High | B3 (`ON DELETE SET NULL`) |
| M1 restore-transaktionalitet | Medium | §4.4 (én txn) |
| M2 `row_pk`-udtræk udesignet | Medium | B11 (PK-registry) |
| M3 redo/undo tvetydig | Medium | §4.1 (reversal-kæde) |
| M4 nævne-indeks lækker | Medium | §5.3 (dobbelt-gating) + B10 |
| M5 token-grammatik | Medium | §5.1 (formel grammatik) |
| M6 eksport tabsgivende | Medium | B12 (eksplicit valg) |
| L1 `text_mention`-nøgle | Low | §5.3 (PK + replace-semantik) |
