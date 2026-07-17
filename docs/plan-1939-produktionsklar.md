# Plan: 1939-stamtavlen produktionsklar + dato-hærdning + cutover

**Status:** Aktiv styringsplan. **Oprettet:** 2026-07-17.
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

**A2 RUNDE 2 (udestår — noteret som TODO i `derive_date_info`):** kirkelige mærkedage → dato via computus
(bevægelige helligdage: Paaske, Michaelis) + `calendar`-sætning ved konvertering; `s.å./s.m./s.d./s.st.`-
ankeropløsning (kræver kontekst-arkitektur — parseren modtager i dag kun isoleret `date_raw`; LLM opløser dog
de fleste allerede, 183/186 i eksisterende korpus). Falder indtil da tilbage til hele-år/None uden at forringe.

### A3. Versioneret 1939-konverter + re-ekstraktion
- [ ] **A3a — Byg en versioneret, deterministisk 1939→`load_daa.R`-konverter.** Erstatter den ad-hoc
      vinduesproces uden checked-in generator. Kør den kanoniske pipeline
      (`segment.py → posts.json → validate.py → clean.json → load_daa.R`), IKKE præsens-loaderen.
      *Hvorfor ikke presens-loaderen:* den sætter source=`'præsensliste'`, hardcoder `levende=TRUE` for alle,
      og dropper narrativer/begravelser/godser (`load_presens.R:82,132`).
- [ ] **A3b — Bevar ordret:** narrativ (prosa), side, linje, nummer, slægtled, børnehenvisninger, godser,
      begravelser, krydsreferencer. (`linked_clean.json` HAR disse — de tabes kun i den forkerte slutfil.)
- [ ] **A3c — Luk/karantænér de 18 `review.json`-poster** eksplicit med dokumenteret resolution.
- [ ] **A3d — Bibliografisk source-oprydning (før import).** Afklar identiteterne + opret separate `source`-poster:
      Holstein (repo kalder den "DAA 2018-20"; dato-analysen siger 2024 — afklar) · 1893 (Ludwig zu Reventlow
      vs. Anders Thiset, jf. `docs/reviews/2026-07-15-...divergens-rapport.md`) · 1939 (Bobé).
      Holstein må **ikke** automatisk "vinde" — rettelser går begge veje.

### A4. Facit-validering (acceptance-test for re-ekstraktionen)
- [ ] **A4a — Definér forventet facit** (Codex min-krav #6): antal poster, familier, barn-links, roots,
      uopløste referencer. Uden facit ved vi ikke hvornår artefaktet er godt nok.
- [ ] **A4b — Bekræft levende-tærskel.** `load_daa.R:435-445` HAR allerede GDPR-sikker alders-sweep
      (født <100 år siden uden død/begravelse/dødsårsag → `levende=TRUE`; fail-closed for ukendt fødselsår).
      Re-ekstraktion til `load_daa.R`-format aktiverer den automatisk. **Ingen ny heuristik nødvendig** —
      bekræft blot at 100-års-tærsklen fanger de ~7 personer født 1926-1936 uden registreret død.

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
- [ ] **K2 — Beslut staging-/publiceringsstrategi** så umatchede 1939-dubletter IKKE offentliggøres ved commit.
      `source` har intet kladde/publiceret-felt (`schema.sql:32`); `person.privat` default FALSE (`schema.sql:122`).
      **Åben beslutning** (se nederst). Relevant *før medlemmer inviteres*, ikke akut nu (pre-launch).
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
2. **Staging-strategi (K2):** source-niveau `draft/published`-felt vs. midlertidig `privat=TRUE` på nye
   1939-poster indtil matchet/gennemgået vs. andet. Afgør før rigtig load.
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
| 10. Staging-strategi så dubletter ikke offentliggøres | K2 |
