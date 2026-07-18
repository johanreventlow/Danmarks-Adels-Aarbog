# Plan: 1939-stamtavlen produktionsklar + dato-hærdning + cutover

**Status:** Aktiv styringsplan. **Oprettet:** 2026-07-17. **Sidst afstemt mod kode:** 2026-07-18
(v1.3.0-sideprojektion tilføjet siden sidste opdatering; A4-status rettet, se A3c/A4 nedenfor).
**Formål:** Samle alle udestående tråde (Fase 4-cutover, 1939-load, dato-hærdning, Wave 3-backlog)
i ét prioriteret overblik, så intet tabes undervejs.

**Sådan læses den:** Arbejdet er delt i tre spor efter **prod-gate**:

- **Spor A** kan startes NU — rører aldrig prod, venter ikke på nogen. Rent lokalt.
- **Spor B** er gated på **eksplicit bruger-godkendelse der navngiver prod-målet** + prod-dump.
- **Konvergens** kræver at både A og B er færdige.

Efter sporene: **Wave 3-backlog** (efter 1939 er live) og **åbne beslutninger**.

---

## Kontekst: hvor står vi (destilleret)

To reviews er modtaget og **empirisk verificeret** (2026-07-17). Genbrug verifikationen — lav den ikke om:

1. **Codex NO-GO for 1939-load.** Alle tal-påstande holder 1:1 mod artefakterne. Konklusion bekræftet:
   1939-datasættet er **ikke** load-klart. To ting er dog mildere end reviewet antog:
   - **Git-sync (Codex min-krav #1): allerede løst.** Worktree-HEAD er på niveau med `origin/main`
     (0 commits bagud). Kun lokal `main`-ref er 2 commits bagud — irrelevant.
   - **Problem 2-migrationen er et *deploy*-gap, ikke et *kode*-gap.** `assertion.objekt_type`,
     `family_member`-slot-constraint og vokabular er skrevet, idempotent og med rollback i
     `db-migrations.sql` (~2001-2022). `source.aar` self-corrector til **2020** ved fuld migration
     (linje 1874 retter 1284). Prod mangler dem, men koden er klar til Trin 1.

2. **Dato-analyse + løsningsmodel.** Empirisk verificeret (7/7 problem-eksempler + overskrivnings-bug):
   - **Datamodellen er allerede rig nok** — rigere end analysens foreslåede "4 flade felter".
     `assertion` har `date_raw`, `date_min`, `date_max`, `date_qualifier` OG `calendar` (`schema.sql:369-379`).
     **Vi erstatter IKKE modellen med en flad dato-model** (det ville miste åbne grænser + intervaller).
   - **Dato-parseren har ægte huller** (bekræftet ved kørsel af `derive_date_bounds()`):
     `† før 1261`→hele 1261, `† efter 1575`→hele 1575, `† 147(5?)`→ingen dato,
     `anno dni MCCCCXCIIII`→ingen dato, `3. S. e. Paaske 1488`→hele 1488, floruit `(-1223-1247-)`
     ikke skelnet fra levetid `1712-1783`. Plus: normaliseringen **overskriver ubetinget**
     eksisterende `date_min`/`date_max` ved genkørsel (`validate.py:385`) → kan forringe korrekte grænser.

3. **Det eksisterende Reventlow-korpus (591 poster → ~923 personer, live i dev) er stort set uskadt.**
   Kun **~6 materielle dato-fejl af 591 poster (~1%)** — moderne, præcise datoer. **Ingen re-load nødvendig.**
   Parser-hærdningen er for **1939's skyld** (ældre, fuzzy korpus: nævnt-form, kirkedage, romertal, `o.`/`um`
   optræder massivt), ikke for at redde eksisterende data.

4. **Pre-launch-kontekst (bruger-bekræftet 2026-07-17):** Data i basen er kun offentliggjort til brugeren selv;
   ingen medlemmer/forskere har adgang endnu. GDPR-blockere skal løses **før nogen inviteres ind**, men
   eksponerer ikke tredjepart nu → hastegraden er "gør det rigtigt før go-live", ikke "brand at slukke".

**Overskriften på 1939-arbejdet:** Det er primært et **ødelagt-artefakt-problem**, ikke et dato-problem.
Den nuværende `work_1939_stamtavle/stamtavle_load.json` er ad-hoc, i forkert (præsens-blok) format, mangler
~90% af træet (kun 61/539 forælder-barn-links), al prosa (0 narrativer) og gods/begravelse/børn/kryds.
**Den kasseres som artefakt.** Kernearbejdet er at re-ekstrahere 1939 gennem en rigtig, versioneret pipeline
til `load_daa.R`-kontrakten. Parser-hærdning er en *forudsætning*, ikke hovedopgaven.

---

## SPOR A — Ubblokeret nu (rører aldrig prod)

Sekvens er bevidst: **model + parser hærdes FØR re-ekstraktion**, ellers bages fejlene ind i stor skala.

### A1. Additive modelændringer ✅ DONE (commit 1f7726b, 2026-07-17)
Verificeret mod frisk isoleret DB (kopi af daa_test2-struktur, prod-frit): ADD COLUMN-sti + idempotens 2× + db-verify-asserts grønne.
- [x] **A1a — Kobl `calendar` til import.** `add_assertion`/`fact_value` bærer nu `cal` (default `'gregoriansk'`
      så DB-default aldrig nulles) + `certainty` gennem R-kæden; `calendar` tilføjet til extraction-schema.
- [x] **A1b — `date_certainty` (ny kolonne, CHECK certain/uncertain/ambiguous).** **Beslutning truffet:**
      `date_precision` UDLEDES af min/max ved læsning (ikke persisteret) — kun `date_certainty` blev ny kolonne.
- [x] **A1c — Faktavokabular seedet:** `fødsel/dåb/død/begravelse`(kanonisk)/`floruit/adling/naturalisering/introduktion_ridderhus` (idempotent).
- [~] **A1d — qualifier-synonymer:** normaliseret fremadrettet i parser + extraction-schema-guidance (`about`, ikke
      `circa`/`approx`). **Bevidst INGEN hård DB-CHECK** — ville afvise de 3+3 eksisterende `circa`/`approx`
      (`assertion.uforanderlig=TRUE`, invariant #1 påstande overskrives aldrig). Synonym-mapping ved skrivetid.

### A2. Qualifier-aware parser — RUNDE 1 ✅ DONE (commit cbe65a7, 2026-07-17)
Fable-subagent + orkestrator-review; TDD, 62→108 python-tests grønne (verificeret uafhængigt).
- [x] **A2a — Stop ubetinget overskrivning.** `derive_date_bounds`→`derive_date_info` (qualifier-aware): åbne
      grænser bevaret; `normalize_record` nuller ALDRIG en eksisterende bound når parseren intet kan udlede.
- [x] **A2b (runde 1-del) — regler for:** da/ældre-da/tyske månedsnavne · `ca./o./um`→about (også på spans) ·
      før/efter/mellem · floruit-notation (`(-ÅÅÅÅ-ÅÅÅÅ-)` ≠ levetid) · usikre cifre (`147(5?)`)→certainty · romertal.
- [x] **A2c — OCR lille `t` for `†`** (case-sensitiv + kontekst-gated i dødssignalet).
- [x] **A2d — TDD** (rød→grøn pr. punkt; regression-frihed bevist).

### A2. Qualifier-aware parser — RUNDE 2 ✅ DONE (commit 24c0a35, 2026-07-17)
Fable-subagent + orkestrator-review; computus UAFHÆNGIGT bevist (0 mismatches vs egen Meeus-impl over 700 år). 111→152 python-tests, korpus-diff DEGRADATION 0.
- [x] **Kirkelige mærkedage → dato via computus:** faste (lookup: Michaeli/Mortens/Kyndelmisse/Sankt Hans/
      Allehelgen/Helligtrekonger/Valborg) + bevægelige (påske-relative: fastelavn..trinitatis + "N. søndag
      efter X"). "Vor Frue" kun m. specifikt festnavn (bar form tvetydig → hele-år). Ukendt fest → hele-år.
- [x] **`calendar`-sætning:** år<1700 → juliansk computus + `calendar='juliansk'` (dato gemt som-skrevet,
      aldrig proleptisk omregnet); ≥1700 → gregoriansk. Provenance-only (ingen læser i app/core).
- [~] **`s.å./s.m./s.d.`-ankeropløsning: BEVIDST SKIPPET** — empirisk: LLM opløser 185/188 i korpuset; de 3
      tomme er sted-/dag-refs (ikke år-cases), strukturelt uopløselige; mekanisk år-tracking ville risikere
      FORKERTE opløsninger og bryde never-degrade. Dokumenteret som TODO-begrundelse i `derive_date_info`.

**Kendt forenkling (noteret):** 1700-kalendergrænsen er skarp (tysk-dansk kalenderskift var reelt rodet i
Slesvig-Holsten-området) — provenance-only, nul matcher-impact; kan forfines hvis en konsument opstår.

### A3. Versioneret 1939-konverter + re-ekstraktion
**A3-ARKITEKTUR (fastlagt 2026-07-17 efter gap-analyse + advisor + 2 målinger):** Genbrug den eksisterende
ekstraktion (`work_1939_stamtavle/linked_clean.json`, 539 poster) — **INGEN re-ekstraktion** (re-ekstraktion løser
ikke narrative; skemaet forbyder LLM-genereret narrative — det kommer altid fra en deterministisk segmenter).
Hybrid: konverter + billig segmenter, INGEN ændring af delt `load_daa.R`.
- **Måling 1:** A2-parseren håndterer 92% af 1939's OCR-datoer (~100% af fødsler — alle har årstal) → **ingen A2 runde 3**; rut datoer gennem A2, omskriv ikke dato-logik i konverteren. GDPR-datagrundlag solidt.
- **Måling 2:** `boern.linje` er udfyldt+inkonsistent i eksisterende korpus (63/82 ≠ rec.linje, værdier som "IV, nr. 118") → advisor's foreslåede loader-ændring er **FARLIG**, forkastet. **Rør ikke `load_daa.R`.**

- [x] **A3a — Versioneret deterministisk konverter** ✅ DONE (commit f903f1c): `convert_1939_stamtavle.py`
      (v1.0.0). ÉT syntetisk linje="1939" + globale nr 1..539; `nr_label=str(nr)` (originale løbenumre er
      gruppe-lokale, 22 distinkte → ville kollidere; original i passthrough). facts via A2; godser/aegteskaber
      mappet. Struktur-facit: 539 poster, 0 nøgle-dubletter, dato-parse 92%, GDPR-flag 7 (født ≥1926 u. død).
      165 python-tests. Åbent: struktureret kryds_ref når ikke DB (bevares i narrative-prosa via A3b).
- [x] **A3b — Billig narrative-segmenter** ✅ DONE (commit c88f526): `segment_1939.py` — anker-snit 81,6%,
      gruppe/vindue-fallback (aldrig manuel, aldrig tom), ordret prosa. R1-proxy 92%. Integreret i konverter
      (narrative flettet pr. _id → alle 539 poster har narrative, NOT NULL opfyldt).
- [x] **A3c — Forældre-graf (fail-closed)** ✅ CODE DONE (v1.2.0): gruppe-for-gruppe nummerering
      (kontinuert nr-blok by construction) + tiered opløsning (Tier1 `_foraelder_id` 17 grupper + Tier2
      `foraeldre_note`-navnematch, ægtefælle-disambiguering). Tier2 kræver nu samme konservativt
      normaliserede `_ctx.linje`; ukendt/modstridende linje parkeres. Det lukker cross-gren-falsk-matchen,
      men invaliderer det gamle 364-link-facit: kode-preview giver **180/539 linkede**, 346 uopløste.
      `clean_1939.json` skal regenereres og A4 gentages før prod-vurdering.
- [x] **A3c — v1.3.0-opfølgning: sikker sideprojektion** ✅ CODE DONE (commit `d1351c3`/`0d7105b`,
      2026-07-17): v1.2.0's linje-krav fail-closed *parkerede* poster hvor `_ctx.linje` var
      fraværende/tvetydig, selvom siden entydigt lå i én ubrudt linje-sektion (`_SIDE_LINJE_SCOPE`,
      kun de ikke-overlappende sideintervaller II–VI — 490-523 og 592 er bevidst udeladt fra
      side-projektion pga. flere/overlappende sektioner). `canonical_linje()`/`build_linje_scopes()`
      giver hver post en `{key, provenance, side, conflict}`: eksplicit linje vinder ALTID over
      sideprojektion; kun ved fravær bruges siden; `Uplacerede`/usikker/ukendt blokerer projektion
      helt. `_tier2_resolve` bruger nu denne scope i stedet for rå `normalize_linje` på `_ctx.linje`.
      165→225 python-tests (56 i `test_convert_1939.py` alene), alle grønne (verificeret i denne
      session). **CONVERTER_VERSION nu 1.3.0.** Forventet effekt: flere af de 346 v1.2.0-uopløste
      poster genvinder et Tier2-link via sideprojektion, uden at genåbne H1s cross-gren-risiko — men
      det er en *forventning fra kodelæsning*, ikke et målt tal: **ingen opdateret facit findes endnu**
      (kræver kørsel mod den rigtige `linked_clean.json`, se A4-status nedenfor).

**CODE-REVIEW (2026-07-17):** #4 **fikset** (ægteskab-datoer bevarer qualifier/certainty/calendar).
**#1 cross-gren Tier2 er nu fikset fail-closed i v1.2.0, udvidet i v1.3.0** (samme normaliserede linje
påkrævet — enten eksplicit eller via sikker sideprojektion; ukendt linje parkeres). #2 selvreference-
vagten er efterfølgende afkræftet som defensiv dead code. #3 struktureret `kryds_ref` når fortsat ikke
DB (PoC-grænse, bevaret i narrative-prosa).
- [x] **18 review.json-poster:** forbliver karantæne (16 ufuldstændig + 5 mangler navn) — fail-closed udeladt af
      konverteren (disjunkte _id, ikke i clean_1939.json). Dokumenteret; manuel efterbehandling hvis ønsket.
- [x] **A3d — Bibliografisk source-identiteter** ✅ DONE (decisions.md): 1939=Bobé (aar=1939), 2018-20=Holstein
      (aar=2020; "2024" = trykke-år, ikke dæknings-benævnelse — bekræft mod titelblad), 1893=Thiset (uafklaret).
      Forfatter bæres i `titel` (source har ingen forfatter-kolonne). Holstein "vinder" ikke auto — kanonisk = redaktionel.

### A4. Dry-run + facit-validering ⚠️ IKKE GENTAGET — udestår stadig efter v1.2.0 OG v1.3.0
`load_daa.R` kørt mod `clean_1939.json` på en frisk DB (schema-kopi af daa_test2 + A1-migration, socket via
`R_ENVIRON_USER`-override). **Tallene nedenfor er fra det ORIGINALE v1.1.0-artefakt** (før Tier2-linje-scopet
i v1.2.0/v1.3.0 ændrede forældregrafen) — de er superseded, ikke et facit for den nuværende konverter.
Checkboksene stod fejlagtigt som "done" i en tidligere version af denne plan; rettet her, da de kunne
læses som at v1.2.0/v1.3.0 var re-verificeret, hvilket de ikke er.
- [ ] **A4a — Facit fra faktisk load (v1.1.0-tal, SUPERSEDED, skal genmåles):** 835 personer (539 hoved + 296
      partner-stubs); 539 narrative, 0 NULL/tom; **364 family_member barn-links** — dette tal er netop det
      v1.2.0/v1.3.0 invaliderer (ny kode-preview: 180/539 for v1.2.0, ukendt/forventet højere for v1.3.0);
      612 partner-links; 471 rødder; 73 uopløste barn-opslag (`union_tom_kontekst`).
- [ ] **A4b — GDPR/levende (v1.1.0-tal, bør genbekræftes):** loaderens sweep satte `levende=TRUE` på præcis de
      7 født ≥1926 uden dødsfakta; 828 afdøde offentlige. GDPR-logikken selv er urørt af v1.2.0/v1.3.0 (kun
      forældre-link-tælling ændrede sig), så denne del er lavere risiko, men er ikke re-kørt mod nyt artefakt.
- [x] **Bagud-kompatibilitet:** gammelt-format clean.json (uden calendar/date_certainty) loader uændret (835
      personer, alle assertions `calendar='gregoriansk'` via DB-default) → A1's `load_daa.R`-ændring er sikker.
      (Dette er en egenskab af `load_daa.R`/A1, ikke af 1939-konverterens forældregraf — upåvirket af v1.2/v1.3.)

**Miljø-begrænsning (2026-07-18, denne session):** A4 kan IKKE genkøres i dette remote-miljø — kilde-
artefaktet `work_1939_stamtavle/linked_clean.json` (levende-PII, git-ignoreret) findes ikke i denne
container, og der er hverken R/Rscript, DB-forbindelse eller `.Renviron` til stede. Det eneste der KUNNE
verificeres her var konverterens/parserens **enhedstests** (Python, ingen rigtig data nødvendig):
`pytest` i `.claude/skills/daa-extract/scripts/` → **225/225 grønne** (56 i `test_convert_1939.py`), inkl.
de nye v1.3.0-sideprojektionstests. Regenerering af `clean_1939.json` + `load_daa.R`-dry-run mod en frisk
DB skal køres af nogen med adgang til `work_1939_stamtavle/` og en Postgres-instans — kommandoerne er
uændrede fra tidligere kørsler (se A3/A4-historikken ovenfor).

**KENDT BEGRÆNSNING (noteret):** de 73 `union_tom_kontekst` er børn af forældre med 2+ ægteskaber placeret i
FØRSTE union (konverteren udleder ikke `aegteskab_kontekst` pr. barn). **Forbedring:** gruppe-noterne HAR "af
første/andet Ægteskab" → kan udledes til korrekt union-placering (A3c-udvidelse, ikke load-blokerende — fail-closed logget).

---

## SPOR B — Gated på eksplicit prod-godkendelse + prod-dump

⚠️ Må IKKE påbegyndes uden bruger-godkendelse der **navngiver prod-målet**. Prod har INGEN backup.
Følger `docs/fase4-runbook.md`.

- [ ] **B1 — GATE 0: rehearsal mod test-restore af rigtigt prod-dump** + rollback-øvelse (runbook Trin, OBLIGATORISK).
      Kun lokal syntetisk rehearsal er kørt hidtil (2026-07-16).
- [ ] **B2 — Trin 0: BACKUP** (`pg_dump`) — eneste rollback-kilde.
- [ ] **B3 — Trin 1: Deploy `db-migrations.sql`** (Problem 2-skema: `objekt_type`, `family_member`-slot,
      vokabular; additiv/idempotent). `source.aar` ender på 2020.
- [ ] **B4 — Trin 1b: Deploy `db-rls.sql`** (F-01 + F-02 sikkerhedsfixes; gen-anvendes ikke af Trin 1).
- [ ] **B5 — Trin 2: Backfill `db-backfill-foraeldrefamilie.sql`** (fail-closed, single-edition-only).
- [ ] **B6 — Trin 3: Verificér `db-verify.sql`** + kør `get_advisors(security)` efter DDL (jf. memory-regel).
      Bekræft forældrefamilie-slots + P1-invariant.

---

## KONVERGENS — kræver Spor A + Spor B færdige

- [ ] **K1 — Rehearsal-load af re-ekstraheret 1939 mod prod-KOPI.** Test RLS, matcher, kollaps, offentlig UI.
      Verificér at matcheren nu faktisk får `date_min`/`date_max` (den læser kun dem — `matchUdgaver.ts:304`;
      uden normaliserede datoer reduceres tværudgave-matching til navn+køn).
- [x] **K2 — Staging-/publiceringsstrategi implementeret i kode:** loader `--staged` sætter
      `person.staged=TRUE`; `person_offentlig` og de direkte anon/authenticated-personpolitikker skjuler staged;
      `red_publicer_udgave(source_id)` rydder samlet efter match-gennemgang. **Ikke deployet til prod** — indgår
      i B3/B4 + GATE 0.
- [ ] **K3 — Rigtig 1939-load mod prod** (efter separat bruger-godkendelse) + verificér slots/P1/RLS/UI.

---

## WAVE 3-backlog (efter 1939 er live — ikke gating for 1939)

Fra Codex-fundament-review, triageret:
- [ ] **Media-write-audit** (noteret fra tidligere session).
- [ ] **F-05: slægts-scope** (RLS/adgang på tværs af slægter).
- [ ] **F-09/10/11: evidens-integritet.**
- [ ] **F-07/15: skalering.**
- [ ] **Redaktions-UI udnytter kun lille del af modellen** (dato-analyse fund #5):
      `redaktionRead.ts:98` læser kun navn/fødsel/død/titel; `redaktionWrite.ts:54` sender kun rå tekst
      (ikke grænser/qualifier). Dåb/begravelse/floruit/naturalisation kan ligge i DB uden at kunne
      vedligeholdes i UI. Udvid UI + kommende tidslinjelæsning til at bruge intervaller + kvalifikatorer.
- [ ] **Valgfri punktrettelse af ~6 eksisterende dato-fejl** (I-18, I-38 åbne grænser; I-45 `147(5?)`;
      I-98/III-57/III-118 uopløste relative). Kosmetisk, lav prioritet — ingen re-load.

---

## Åbne beslutninger (afgøres i Spor A / Konvergens)

1. **`date_precision` egen kolonne eller udledt?** Delvist afledeligt af min/max-spænd (min=max=dag →
   dagspræcision; hele-år-span → årspræcision). `date_certainty` er den ægte manglende dimension.
   → afgør i A1b, måske kun `date_certainty` bliver ny kolonne.
2. ~~**Staging-strategi (K2)**~~ **Afgjort:** separat `person.staged`, loader-flag `--staged`, central
   RLS-gate og samlet `red_publicer_udgave(source_id)`. Afventer deploy/rehearsal.
3. **Bibliografiske identiteter (A3d):** Holstein 2018-20 vs. 2024; 1893 Ludwig vs. Thiset.
   Afklar mod primærkilder før source-poster oprettes.

---

## Codex' 10 min-krav → hvor de bor i planen

| Codex min-krav | Placering |
|---|---|
| 1. Opdatér til origin/main | ✅ Allerede løst (worktree = origin/main) |
| 2. Versioneret deterministisk 1939-konverter | A3a |
| 3. Bevar narrativ/side/linje/nr/slægtled/børn/godser/begravelser/kryds | A3b |
| 4. Udled date_min/date_max deterministisk | A2 |
| 5. Luk/karantænér 18 review-poster | A3c |
| 6. Definér forventet facit + test | A4a |
| 7. Fase 4 GATE 0 mod prod-dump + rollback | B1 |
| 8. Deploy migration/RLS/backfill + verificér slots/P1 | B3–B6 |
| 9. Rehearsal-load 1939 mod prod-kopi | K1 |
| 10. Staging-strategi så dubletter ikke offentliggøres | ✅ K2 kode; deployes i B3/B4 |
