# Cycle 07 — Plan 2C-2b familie-redigering (partner+barn+konfidens)

**Dato:** 2026-06-29
**Scope:** `3eeea5e..a167d1e` (2C-2b: 4 familie-RPC'er, fetchPersonFamilie/mapFamilieRows, eraAdvarsel,
buildRpcCall-cases, PersonPicker, redigerbar familie-sektion). Ekskl. urelaterede tng-qa-docs-commits.
**Reviewers:** Claude (code-analyzer Phase 1) + Codex (Phase 3, adversarial).

## Sammenfatning

| ID | Severity | Status |
|----|----------|--------|
| H1 React key-kollision (multi-rolle barn) | LOW | ✅ Rettet (key inkl. rolle) |
| H2 shared ordinal i opret_union | LOW | by-design → SQL-kommentar anvendt |
| H3 both-partner-and-barn mis-bucket | LOW→MEDIUM (Codex) | ✅ Rettet (mapFamilieRows bucket-all + test) |
| H4 slet_familie_link uden ROW_COUNT-guard | LOW | idempotent tilsigtet → SQL-kommentar anvendt |
| NEW1 "afkobl forælder" fjerner BEGGE forældre | MEDIUM (Codex) | ✅ Rettet (relabel + dry-run-gate) |
| NEW2 concurrent cyklus-skew | LOW (PoC single-writer) | SQL-kommentar (= max(id)+1-debt) |

Spec-niveau Codex-review (pre-impl) fangede de 3 HIGH design-fejl (H1 family-slet, H2 dedup, H3 cyklus)
— alle verificeret live i rollback-tests. Final whole-branch review fangede era-fokus-forælder-bug.
Denne kode-niveau-cycle fandt KUN LOW edge-cases. Lavt risiko-niveau forventet.

---

## H1 [LOW] — React key-kollision ved multi-rolle barn

**Lokation:** `mobile/src/app/redaktion/person/[id].tsx:489`

**Symptom:** Børn-listen renderede `<View key={b.personId}>`. family_member-PK er
`(family_id, person_id, rolle)`, så samme person kan have to barn-roller i samme familie (fx 'barn' +
'adopteret_barn'). To FamilieBarn-entries m. identisk personId → kolliderende React-keys.
`red_tilfoej_barn` blokerer kun samme præcise triple, ikke en anden rolle; legacy DAA/TNG-import har
ingen guard.

**Verifikation (grep):** kun linje 489 ramt. partnere (478, `key={pt.personId}`) + foraeldre (511) er
PK-unikke (én partner-rolle pr. person pr. familie); union-keys (475/509, familyId) unikke.

**Konsekvens:** edge-case UI-korruption (React drop/dup-row) for multi-rolle børn. LOW.

**Fix (anvendt):** `key={`${b.personId}-${b.rolle}`}`.

---

## H2 [LOW] — `red_opret_union` skriver samme `p_ordinal` til begge partnere

**Lokation:** `schema.sql` red_opret_union (begge family_member-INSERTs).

**Symptom:** Når hans 2. ægteskab er hendes 1., er den lagrede ordinal forkert for den ene partner.

**Konsekvens:** by-design (union-niveau ordinal, ikke per-partner ægteskabstal). Fremtidig
ordinal-baseret rapportering ("første/andet ægteskab") ville være upræcis for den symmetriske række.
LOW, ingen kode-ændring.

**Fix:** SQL-kommentar der klargør at `p_ordinal` er unionens sekvensnummer, ikke hver partners
individuelle ægteskabstal. Per-partner-ordinal = fremtidig additiv udvidelse hvis behov.

---

## H3 [LOW] — person som BÅDE partner og barn i samme familie mis-buckets

**Lokation:** `mobile/src/data/redaktionRead.ts` mapFamilieRows (`rows.find(r => String(r.person_id) === personId)`).

**Symptom:** `rows.find` vælger fokus-personens FØRSTE række efter query-orden (ordinal nullsFirst:false →
partner-række m. non-null ordinal sorterer før barn-række m. null). En person registreret som både
partner og barn i samme familie lander i somPartner OG i egen unions boern-liste (fremstår som sit eget
barn). `red_tilfoej_barn` SQL-guard blokerer ny oprettelse; legacy-import gør ikke.

**Konsekvens:** forvirrende visning KUN for importerede legacy-familier. Ingen data korrumperes. LOW.

**Fix:** kendt begrænsning. Anbefalet post-import-validering der rapporterer familier hvor samme
person_id har både partner- og barn-rolle (= datakvalitets-tjek, uden for 2C-2b-scope).

---

## H4 [LOW] — `red_slet_familie_link` mangler ROW_COUNT-guard

**Lokation:** `schema.sql` red_slet_familie_link.

**Symptom:** Modsat `red_set_familie_konfidens` (som RAISE'r ved 0 ramte rækker) no-op'er slet stille på
en forkert triple. Alle UI-triples kommer fra friskt-hentet DB-state, så forkerte triples kan ikke opstå
fra nuværende UI. Idempotent-delete er rimeligt (matcher red_slet_relation/red_slet_familie-mønster).

**Konsekvens:** defensiv-programmerings-asymmetri; en hypotetisk forkert-rolle-kalder ville se RPC'en
lykkes uden fejl-signal. LOW.

**Fix:** SQL-kommentar der forklarer at idempotent-delete er tilsigtet (matcher øvrige red_slet_*).

---

## Verificeret sikkert (code-analyzer Phase 1)

- byFamily Map-upsert-idiom korrekt (`Map.set()` returnerer Map, `.get(k)` henter just-sat værdi).
- fetchPersonFamilie tom-famIds eksplicit guarded (redaktionRead.ts:268) — `.in()` aldrig kaldt m. tom array.
- eraAdvarsel call-site: fokus-personens datoer prepended (merged, commit b78fea7); born/died = number|null matcher.
- buildRpcCall 4 cases: param-navne/typer/null-håndtering matcher SQL-signaturer (tests dækker).
- onApplied re-fetcher familie for ALLE 4 write-typer (alle rører family_member).
- red_set_familie_konfidens m. null konfidens: `IS NOT NULL AND NOT IN` korrekt; ryd virker.
- red_tilfoej_barn cyklus-CTE: UNION-dedup, korrekt retning (barns efterkommere), termininerer (pre-insert = DAG).
- Hooks ubetinget før early-returns; ingen conditional-hook-brud.
- max(id)+1 = hus-konvention (14 forekomster: fact/assertion/citation/conclusion/narrative/relation); ikke 2C-2b-regression.

---

## Codex adversarial-review konsekvens (2026-06-29)

**Verdict:** needs-attention. Codex bekræftede H1, recalibrerede H3↑, fandt 2 nye + korrigerede doc-nøjagtighed.

**NEW1 [MEDIUM] — CONFIRMED (verificeret).** `mobile/src/app/redaktion/person/[id].tsx:515`: "🗑 afkobl
forælder"-knappen sender `personId: id!` (barnet selv) + `rolle: sb.rolle` → `red_slet_familie_link`
fjerner barnets membership i HELE forældre-familien = afkobler BEGGE forældre, ikke én. En redaktør der
retter ÉN forkert forælder ville miste den korrekte forælder-link. Modellen kan ikke afkoble én partner
uden at flytte barnet (family_member er barn↔familie, ikke barn↔forælder). **Fix:** relabel til
"🗑 fjern fra denne forældre-familie" + kommentar; dry-run-preview = bekræftelses-gate.
Bucket: **semantic-drift / data-tab-adjacent** (misvisende label → utilsigtet korrekt-forælder-tab).

**H3 [LOW→MEDIUM] — RECALIBRERET (verificeret).** Codex: mit H3 var ikke begrænset til legacy
partner+barn-data. `mapFamilieRows` `rows.find` (redaktionRead.ts:241) tog ÉN focus-membership pr.
familie → barn under to subtyper i samme familie (PK tillader, `red_tilfoej_barn` blokerer ikke
forskellig rolle) → andet link usynligt/uredigerbart (kan ikke ændre konfidens el. afkoble). **Fix:**
bucket ALLE focus-rows (`filter` ikke `find`); emit somPartner én gang + somBarn pr. barn-rolle; ekskludér
focus fra egen unions boern (data-fejl-guard). 2 regression-tests (16/16). Bucket: **silent-data-skjul.**

**NEW2 [LOW] — CONFIRMED men PoC-kalibreret (verificeret).** Cyklus-CTE er pre-INSERT uden lås → to
samtidige txn'er kan tilsammen lukke en cyklus. Teknisk korrekt, men = samme klasse som projektets
dokumenterede `max(id)+1`-TOCTOU under single-writer-PoC-antagelsen (redaktion = én editor). **Fix:**
SQL-kommentar der noterer antagelsen + advisory-lock som fremtidig multi-writer-hærdning. Ikke kode-ændring
(advisory-lock = over-engineering for PoC). Bucket: **sub-optimal/cleanup (PoC-accepteret).**

**H4-korrektion [LOW] — CONFIRMED.** Codex fangede at draftens H2/H4 påstod "SQL-kommentar" som anvendt,
men kommentarerne fandtes ikke endnu. **Fix:** kommentarerne nu faktisk tilføjet (ordinal-semantik,
idempotent-delete) i schema.sql + db-migrations.sql; statusser rettet.

**H1 [LOW] — CONFIRMED** (allerede rettet før Codex; key inkl. rolle).

**Codex impact (verified, bucket-distingveret):**
- Semantic-drift/data-tab-adjacent: **1** (NEW1 afkobl-forælder mislabel).
- Silent-data-skjul: **1** (H3/mapFamilieRows multi-rolle-barn).
- Sub-optimal/cleanup (PoC): **1** (NEW2 concurrent-cyklus).
- Doc-nøjagtighed: **1** (H4 ikke-anvendte kommentarer).

**Læring:** (1) En "slet-link"-knap på en afledt relation skal beskrive HVILKEN side den fjerner — barn↔familie
≠ barn↔forælder; misvisende label = data-tab-risiko. (2) `find`-baseret bucketing skjuler multi-rolle-links
i junction-tabeller hvor PK inkluderer rolle — brug `filter`. (3) Marker aldrig en fix som anvendt i
review-doc før den faktisk er committet (Codex H4 fangede præcis dét).
