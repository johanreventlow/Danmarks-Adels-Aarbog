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
| `production_db_migrated` | **IKKE OPNÅET** | Kræver godkendelse — se §5 |
| `web_deployed` | **IKKE OPNÅET** | Kræver godkendelse — se §5 |
| `smoke_verified` | **IKKE OPNÅET** | Kræver manuel redaktør-røgtest i browser — se §4 |

Produktionsdatabasen er **ikke** rørt. Ingen push, ingen PR, ingen deploy.

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

## 4. Udestående: manuel redaktør-røgtest (blokeret uden browser)

Følgende kan ikke afgøres automatisk og mangler før `smoke_verified`. Køres ved
skrivebordsbredde af en redaktør:

- [ ] Skift Liste ↔ Kvalitetsark; bekræft at "Alle personer" er valgt fra start
- [ ] Kombinér QA-preset, fritekstsøgning og kilde-/linjefilter
- [ ] Sortér hver redigerbar kolonne, begge retninger; tjek at tomme datoer lander sidst
- [ ] Åbn en blokeret række i den eksisterende editor via "Åbn person"
- [ ] Ret ét felt; godkend ét felt; udskyd ét felt
- [ ] Genindlæs browseren og bekræft at tilstanden holder
- [ ] Læs panelets ordlyd: skal sige "OCR-kontekst" og indeholde noten om at det ikke
      er en gengivelse af den trykte side
- [ ] **Prøvekørsel:** bekræft at panelet nægter at gemme, mens prøvekørsel er slået
      til, og forklarer hvorfor (se §6)
- [ ] Notér browserens rendertid ved fuld datamængde (§3.2)

---

## 5. Idriftsættelse — obligatorisk rækkefølge

Hvert trin kræver en **frisk, eksplicit godkendelse**. Stop ved første afvigelse.

1. **Backup.** Tag en krypteret dump af prod og bekræft, at den kan gendannes.
   Free tier har ingen indbygget backup.
2. **Skrivefrys.** Aftal at ingen redaktør skriver, mens migrationen kører.
3. **Migration.** Kør kun de nye, navngivne blokke i `db-migrations.sql` mod prod.
   Blokkene er idempotente og verificeret kørt to gange lokalt.
4. **RLS.** Kør `db-rls.sql`.
5. **Verifikation.** Kør de relevante `db-verify.sql`-blokke mod prod. Kør derefter
   `get_advisors(security)` — DDL-migrationer kan indføre RLS-/`search_path`-fund,
   som `db-verify` ikke tester for.
6. **Rolletjek mod prod.** Gentag §3's anon/medlem/redaktion-kontrol med efterlignede
   claims mod den reelle base.
7. **Importnøgle-beslutning.** Eksisterende personer har ingen stabil
   `(import_key, record_key)`. De forbliver **læsbare men ikke-redigerbare**, indtil
   deres udgave genindlæses med `--import-key=`. Beslut per udgave, om og hvornår en
   genindlæsning skal køres — det er ikke en forudsætning for at tage griddet i brug.
8. **Web-deploy.** Vercel. Husk at `VITE_`-variabler bages ind ved build.
9. **Røgtest.** Kør §4 mod prod.
10. **Ophæv skrivefrys.**

**Rollback:** Featuren tilføjer kun nye objekter (journal-tabel, tre RPC'er, to
kolonner). Web-laget kan rulles tilbage uafhængigt ved at redeploye forrige commit;
databaseobjekterne kan blive stående uden effekt, da intet eksisterende kald rører dem.

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
