# Trin 5c-1: placement og membership for 2018-20 — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 2018-20's slægt-, linje- og generationsplacering bliver kildebundet evidens (overskrifter som observationer
→ placements → ledger → membership), og de 541 publicerede biografier revalideres i samme transaktion, uden at
nogen læser ændres.

**Architecture:**
- **Profil (Python):** et deterministisk overskriftsudtræk over 2018-20's rendition giver et manifest med
  overskrifter, placeringsforslag, strukturinvarianter og afvigelser mod legacy.
- **Fælles motor (SQL):** fire vokabularkoder, en udvidet placement-validator, en ledger-tabel, private
  skrivefunktioner med indholds-id'er og en membership-promotion med preview, tilstands-sha og reversal.
- **Prod:** DDL-ceremoni (GO 1) og dataceremoni (GO 2) gennem en privat runner, øvet på en stand-in af prod.

**Tech Stack:** PostgreSQL 17 (plpgsql), Python 3 (manifest og pytest), bash/zsh (opgraderingstest, privat runner).

**Spec:** `docs/superpowers/specs/2026-10-26-trin5c-placement-membership-design.md` (Fable-reviewet 2026-10-26).
**Plan-review:** Codex r1 NO-GO (5B/6M) 2026-10-26 → Opus-dom (7 nødvendige, 4 forenklede) → indarbejdet.

## Global Constraints

- **Gren:** `feat/150-5c-placement` fra `docs/150-5c-spec`. PR'en er altid `--draft`. Intet push uden et udtrykkeligt ja.
- **Prod:** røres kun i projektejerens shell med GO (`koer.zsh`). AI'en kører kun mod lokale baser.
- **`schema.sql` er source of truth.** `db-migrations.sql` får én ny blok mellem `-- Genåbnings-blokken slutter her.`
  og `-- 5b-sektionen slutter her …`; den begynder med `-- Placement og membership (#150, trin 5c-1)` og slutter med
  `-- Placement-blokken slutter her.`; den genopbygges fra `schema.sql` (som #248's `synk.py`). Ældre blokke redigeres ikke.
- **Ingen læser ændres:** `red_person_grid`, `red_match_personer`, `regen_person_visning`, `public_family_sources`,
  `public_person_bio_source_versions_v2` og alt i `web/`, `mobile/`, `packages/` er uændret.
- **Vokabular:** `observation_kind` `header_linje`, `header_slaegtled`, `header_kuld`, `header_aegteskab`.
  Dispositioner: `mapped`, `retained_legacy`, `archived_by_editor`, `unresolved`.
- **Regelversioner:** `header_rule_version='header-2018-20-v1'`, `rule_version='placement-membership-v1'`.
- **Indholds-id'er** via `private.content_uuid(kind, key)` for alle nye rækker; `kind` pr. tabel står i Task 3.
- **ACL som #244/#248:** RPC'er `REVOKE ALL … FROM PUBLIC,anon,authenticated; GRANT EXECUTE … TO authenticated`;
  private tabeller `REVOKE ALL … FROM PUBLIC,anon,authenticated,service_role`, RLS til, `private.reject_evidence_mutation()`-
  triggere for tilføj-kun.
- **PII:** rå tekst, overskrifter (»med X:« nævner levende ægtefæller), kontrolark og token-fil kun under
  `~/.private/5c/`. Tests bruger opdigtede personer med negative id'er. Chat, commits og rapporter: kun tal og hashes.
  Scripts, der læser `work/`, skriver stdout og stderr til fil og rapporterer antal (memory: PII-probe).
- **Miljø:** `env -u PGOPTIONS` foran psql, `env -u NODE_OPTIONS` foran npm, `/usr/bin/python3 -m pytest`.
- **Commits:** atomiske, Conventional Commits på dansk, ingen Claude-attribution; trailer
  `Claude-Session: https://claude.ai/code/session_01RBJjQA6K5Q1miff9EFPGba`.

## Review Focus

1. **En post uden egen slægtledsoverskrift** (umarkeret slægtledsfald). Den skal have `unresolved`, ikke arve
   legacy-værdien eller forrige overskrifts tal. Låses af `test_umarkeret_slaegtledsfald` i Task 1.
2. **En kuld- eller ægteskabsoverskrift fra et tidligere slægtled.** Den må ikke gælde efter en ny
   slægtledsoverskrift. Låses af `test_hoejere_niveau_annullerer` i Task 1.
3. **Revalidering nr. 2 i samme transaktion.** Den må ikke fejle med `NARRATIVE_RECORD_FOREIGN_CHANGE_SET`. Låses
   af `$revalider_to_i_traek$` i Task 6.
4. **En identitetsrettelse efter promotion.** Membershippen skal blive ikke-gældende, og helbredsassert'en skal
   tælle den. Låses af `$membership_forael$` i Task 4.
5. **En persona-placement, hvis identitet peger på en anden person end bindingens.** Dataceremonien skal stoppe
   før skrivning (`FIX150_PRE_IDENTITY`), ikke efterlade en blokeret binding — også når posten selv er `unresolved`.
   Låses af negativen i Task 6, trin 1, og Task 7, trin 5.

---

### Task 0: Måling og stand-in (kun lokalt, ingen commits)

**Files:** ingen i repoet. Noter i `~/.private/5c/maaling.txt`.

- [ ] **Trin 1:** Opret stand-in `daa5ab_ddl_standin_20261027090000_5ca` med ICU-locale som prod
  (`createdb --locale-provider=icu --icu-locale=da-DK --template=template0`), og restore det seneste prod-dump
  (efter #248; tag et friskt læse-dump gennem en runner, hvis projektejeren vil, ellers
  `slet_1102__daa5ab_ddl_standin_20261026160000_248g` som skabelon). Skabelonkopi `…_5ct`.
- [ ] **Trin 2:** Mål og notér: antal `person_external_id` pr. kilde, `published`/`draft`-bindinger for kilde 1,
  antal records med accepteret hovedperson-identitet, og om identitetens person = bindingens person for alle.
- [ ] **Trin 3:** Kør `segment.py`'s regexer over 2018-20's rå tekst (profilens sti) og tæl overskrifter pr. niveau
  og antal umarkerede slægtledsfald. Kun antal i noterne.

### Task 1: Overskriftsmanifest for 2018-20 (profil)

**Files:**
- Create: `.claude/skills/daa-extract/scripts/build_header_manifest.py`
- Create: `.claude/skills/daa-extract/scripts/fix_150_eksport.sql` (read-only SELECT af kilde 1's legacy-rækker som
  JSON `{record_key, linje, nr, slaegtled_lokal, slaegtled_gennem, kuld}`; ingen navne; læsetransaktion)
- Test: `.claude/skills/daa-extract/scripts/test_build_header_manifest.py`

**Interfaces:**
- Consumes: `segment.py`'s regexer (`PAGE_RE`, `POST_RE`, `ROMAN_RE`, `LINJE_NAME`, `SLGT_RE`, `MARR_RE`) og
  `build_source_evidence_manifest.project_rendition` (offset-kort til renditionsabsolutte tegn).
- Produces: `build_manifest(rendition_bytes: bytes, profile: dict, legacy: list[dict]) -> dict` (skrivemanifestet,
  kun under `~/.private/5c/`) med nøglerne
  `headers` (pr. overskrift: `element_id`, `kind` ∈ de fire koder, `page_from`, `page_to`, `char_from`, `char_to`,
  `verbatim_text`, `verbatim_sha256`, `parsed` = {`roman`|`ordinal`|`gennem`|`kuld`}), `placements` (pr. post: `record_key`, `entry_code`,
  `printed_number`, `generation_local`, `generation_label_raw`, `generation_global`, `kuld_label`, `section_path`,
  `header_ids` = {niveau: `element_id`}, `status` ∈ `machine_ok|unresolved`, `reasons`), `invariants`
  (navn → bool), `disagreements` (record_key + felt, ingen tekst) og `header_rule_version`.
  `legacy` er rækkerne `{record_key, linje, nr, slaegtled_lokal, slaegtled_gennem, kuld}` fra basen.
  `summary(manifest: dict) -> dict`: samme struktur uden `verbatim_text` (antal, hashes, invarianter, afvigelser) —
  det eneste, der må vises i chat eller rapporter.
  CLI: `--rendition-text --profile --legacy-json --out` (alle stier under `~/.private/5c/`).

- [ ] **Trin 1: Skriv de fejlende tests** med en syntetisk rendition (opdigtede navne):
  - `test_linje_overskrift_to_linjer`: romertal + »DEN … LINJE« giver én `header_linje` over begge linjer, `roman='II'`.
  - `test_slaegtled_og_kuld`: posten efter »… slægtled« og et kuld-romertal får `generation_local` og `kuld_label`.
  - `test_hoejere_niveau_annullerer`: kuld fra slægtled 3 gælder ikke for første post efter slægtled 4-overskriften.
  - `test_umarkeret_slaegtledsfald`: et skift uden overskrift giver `status='unresolved'` med `reasons=['umarkeret_slaegtled']`.
  - `test_uenighed_med_legacy`: afviger legacy's `slaegtled_lokal`, står posten i `disagreements` og er `unresolved`.
  - `test_invarianter`: 5 linjeoverskrifter ↔ 5 entries, fortløbende slægtled og nr. pr. linje, stigende kuld;
    et brudt invariant giver `invariants[<navn>]=False`.
  - `test_offsets_renditionsabsolutte`: `rendition_bytes[char_from:char_to]` projiceret = overskriftens tekst.
  - `test_summary_uden_tekst`: `summary()` indeholder ingen overskrifts- eller posttekst (kun hashes og tal).
- [ ] **Trin 2:** Kør `/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_build_header_manifest.py -q`.
  Forventet: fejl (modulet findes ikke).
- [ ] **Trin 3: Implementér** `build_manifest` og CLI'en. Hierarki: linje > slægtled > kuld > ægteskab; en
  overskrift nulstiller alle lavere niveauer. `element_id` = `header:<char_from>`. Ingen netværk, ingen model.
- [ ] **Trin 4:** Kør pytest igen. Forventet: alle grønne.
- [ ] **Trin 5:** Eksportér legacy med `fix_150_eksport.sql` mod stand-in'en (til `~/.private/5c/legacy.json`), og kør
  manifestet på den rigtige tekst (stdout+stderr til fil under `~/.private/5c/`). Notér antal pr.
  `status`, alle `invariants` og antal `disagreements` i `maaling.txt`. Er et invariant falsk, stop og vis
  projektejeren antallet.
- [ ] **Trin 6: Commit** `feat(150): overskriftsmanifest for 2018-20`.

### Task 2: Vokabular og udvidet placement-validator

**Files:**
- Modify: `schema.sql` (vokabular ved `:606`; `private.validate_source_record_placement` `:2310`) og migrationsblokken
- Modify: `db-verify.sql` (placement-blokken `:3452-3466`, `:3595-3660`)
- Test: `tests/sql/test-placement-header.sql` (ny)

**Interfaces:**
- Produces: `validate_source_record_placement` accepterer (i) den eksisterende sti (kind `header` i postens egen
  ankrede forekomst) eller (ii) kind `header_linje` på en forekomst i samme rendition som postens tidligste ankrede
  forekomst, uden noget `source_record_anchor_event`, med `char_from` < postens forekomsts `char_from` og
  `o.extraction_run_id = forekomstens extraction_run_id` (samme header-kørsel). Ellers
  `EVIDENCE_PLACEMENT_HEADER_REQUIRED`. `EVIDENCE_PLACEMENT_SOURCE_MISMATCH` uændret.
  - `private.placement_header_violations(p_source_id bigint) RETURNS bigint`: antal accepterede placements, hvor en
    header-id i `evidence` ikke deler kørsel med `header_observation_id`, har forkert kind, ikke står før posten, eller
    hvor en overskrift af samme eller højere niveau står imellem (nærmeste-reglen). Bruges af db-verify og ceremoniens POST.

- [ ] **Trin 1: Skriv den fejlende test** `tests/sql/test-placement-header.sql` med fixtures fra
  `fixtures/relation-5b.sql` (post + rendition) og en strukturel forekomst:
  - `$sti_ii_ok$`: header-forekomst før posten → placement indsættes.
  - `$sti_ii_efter_posten$`: header efter postens start → `EVIDENCE_PLACEMENT_HEADER_REQUIRED`.
  - `$sti_ii_ankret$`: header-forekomsten er ankret til en record → afvist.
  - `$sti_ii_anden_rendition$` → afvist. `$sti_ii_forkert_kind$` (`header_kuld`) → afvist.
  - `$sti_i_uaendret$`: den gamle sti (kind `header` i postens forekomst) virker stadig.
  - `$sti_ii_anden_koersel$`: observationens kørsel ≠ forekomstens → afvist.
  - `$ikke_naermeste$`: en ældre linjeoverskrift med en nyere imellem → `placement_header_violations=1`.
- [ ] **Trin 2:** Kør testen. Forventet: `$sti_ii_ok$` fejler med `EVIDENCE_PLACEMENT_HEADER_REQUIRED`.
- [ ] **Trin 3: Implementér** vokabularkoderne og validatoren (`CREATE OR REPLACE`, samme signatur), og kopiér
  til migrationsblokken.
- [ ] **Trin 4:** Kør testen og `tests/sql/run-db-verify-disposable.sql`. Forventet: alle grønne. Tjek, at
  `evidence_contract.py:632-646` og `clause_ledger.py:89` ikke låser `observation_kind` (de kræver kun en kendt
  observation); ret kun, hvis de gør.
- [ ] **Trin 5: Commit** `feat(150): placement-header som strukturel forekomst`.

### Task 3: Ledger og private skrivefunktioner

**Files:**
- Modify: `schema.sql` (ny tabel + view + funktioner efter placement-RPC'erne, `:2600`; `slaegt` i
  `version_pk_registry` efter mønstret `:9414-9419`), migrationsblokken (registrering + eksplicit `log_change`-trigger,
  fordi triggerløkken allerede har kørt), `db-verify.sql` (ACL- og tabelblok som `private.relation_reopen`)
- Test: `tests/sql/test-placement-writer.sql` (ny)

**Interfaces:**
- Produces:
  - Tabel `private.legacy_placement_disposition(person_id bigint, source_id bigint, version integer CHECK (version>=1),
    disposition text CHECK (disposition IN ('mapped','retained_legacy','archived_by_editor','unresolved')),
    legacy_sha256 text NOT NULL CHECK (legacy_sha256 ~ '^[0-9a-f]{64}$'), placement_id uuid REFERENCES
    private.source_record_placement(id), evidence jsonb NOT NULL CHECK (jsonb_typeof(evidence)='object'),
    decided_by_name text NOT NULL, decided_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY (person_id,source_id,version), CHECK ((disposition='mapped')=(placement_id IS NOT NULL)))` + view
    `private.legacy_placement_disposition_current` med kolonnen `is_current = (legacy_sha256 IS NOT DISTINCT FROM
    private.legacy_external_id_sha256(person_id,source_id))` (slettet legacy-række → NULL → ikke gældende).
  - `private.legacy_external_id_sha256(p_person_id bigint, p_source_id bigint) RETURNS text` (sha over linje, nr,
    record_key, slaegtled_lokal, slaegtled_gennem, kuld med `private.reimport_canonical_json_sha256`).
  - `private.write_header_evidence(p_source_id bigint, p_rendition_id uuid, p_run jsonb, p_headers jsonb) RETURNS integer`:
    én `extraction_run` (`run_key` = `header_rule_version`), pr. header én forekomst og én observation; id'er
    `content_uuid('header-occurrence',{rendition_id,run_key,char_from})` og `content_uuid('header-observation',{occurrence_id})`.
    Idempotent: findes id'et med samme indhold, springes det over; afviger indholdet → `PLACEMENT_HEADER_DRIFT`.
  - `private.write_record_placement(p_record_id uuid, p_entry_id bigint, p_values jsonb, p_header_obs uuid,
    p_evidence jsonb) RETURNS uuid`: placement (`content_uuid('record-placement',{source_record_id,scheme_entry_id,header_rule_version})`)
    med `initial_status='accepted'` og én afgørelse v1 `accepted`, `decision_origin='migration'` (triggeren tillader det
    kun for v1, `schema.sql:2393-2402`); v1's evidence bærer GO-, manifest- og kontrolark-sha. En senere supersede er v2
    gennem `red_decide_*` med `p_expected_version=1`.
  - `private.write_persona_placement(p_persona_id uuid, p_record_placement_id uuid, p_basis_obs uuid,
    p_evidence jsonb) RETURNS uuid`: `principal_member`, samme mønster (`'persona-placement'`); skrives efter record-afgørelsen (`:2415-2421`).
  - `private.record_legacy_disposition(p_person_id bigint, p_source_id bigint, p_disposition text,
    p_placement_id uuid, p_evidence jsonb) RETURNS integer` (ny version; ingen ændring → ingen ny række).
  - `private.lineage_of_entry(p_entry_id bigint) RETURNS bigint`: præcis én `canonical`, ellers `PLACEMENT_ENTRY_LINEAGE_INVALID`.

- [ ] **Trin 1: Skriv de fejlende tests:** genkørsel giver samme id'er og 0 nye rækker; ændret header-tekst →
  `PLACEMENT_HEADER_DRIFT`; disposition `mapped` uden placement → CHECK-fejl; to canonicals → `PLACEMENT_ENTRY_LINEAGE_INVALID`;
  en UPDATE af `person_external_id` efter registreret disposition slår `is_current` til false; anon/authenticated har
  ingen adgang til tabellen; v1-afgørelsen er `accepted`/`migration` og en v2-supersede via `red_decide_*` virker;
  `slaegt` er registreret i `version_pk_registry`, og en UPDATE under en change_set giver én `change_event`.
- [ ] **Trin 2:** Kør. Forventet: funktionerne findes ikke.
- [ ] **Trin 3: Implementér**, kopiér til migrationsblokken, registrér tabellen i db-verify.
- [ ] **Trin 4:** Kør testen og db-verify. Forventet: grønne.
- [ ] **Trin 5: Commit** `feat(150): ledger og private skrivefunktioner for placement`.

### Task 4: Membership-promotion med tilstands-sha og reversal

**Files:**
- Modify: `schema.sql`, migrationsblokken, `db-rls.sql` (grant-listen), `db-verify.sql` (`::regprocedure`-listen +
  helbredsassert)
- Test: `tests/sql/test-placement-membership.sql` (ny)

**Interfaces:**
- Consumes: Task 3's `private.lineage_of_entry`.
- Produces:
  - `private.membership_state(p_persona_placement_id uuid) RETURNS jsonb` (NULL, hvis placement ikke er `accepted`
    eller identiteten ikke `accepted`): {person_id, lineage_id, slaegt_id, persona_placement_id, record_placement_id,
    identity_version, rule_version}.
  - `public.red_preview_placement_memberships(p_source_id bigint) RETURNS jsonb`: {items:[{persona_placement_id,
    person_id, lineage_id, slaegt_id, eligible, reason_code}], preview_sha256}.
  - `public.red_promote_placement_memberships(p_source_id bigint, p_preview_sha256 text) RETURNS integer`: egen
    change_set (`begin_change_set('placement_membership', …)`), skriver `person_lineage_membership` (`member`) og
    `person_slaegt_membership` (`agnatic`) med `source_basis` = state + `state_sha256`; rydder `app.change_set_id` før retur.
    Fejl: `PLACEMENT_MEMBERSHIP_FOREIGN_CHANGE_SET` (GUC'en er sat ved indgang, husmønstret fra `:3417`), `EVIDENCE_ROLE_FORBIDDEN`, `PLACEMENT_MEMBERSHIP_PREVIEW_DRIFT`, `PLACEMENT_MEMBERSHIP_CONFLICT` (anden kilde
    ejer rækken).
  - `public.red_reverse_placement_membership(p_person_id bigint, p_lineage_id bigint, p_note text) RETURNS void`
    (sletter begge rækker under egen change_set; samme GUC-vagt).
  - `private.membership_is_current(p_person_id bigint, p_lineage_id bigint) RETURNS boolean`.
  - db-verify-helbredsassert: `PLACEMENT_MEMBERSHIP_NOT_CURRENT n=<antal>` som NOTICE (ikke fejl).

- [ ] **Trin 1: Skriv de fejlende tests:** preview → promote → begge tabeller har rækken og `membership_is_current`;
  `$membership_forael$`: identiteten afgøres igen til en anden person → `membership_is_current=false` og assert'en
  tæller 1; reversal fjerner rækkerne og logger `change_event`; anden preview-sha → drift-fejl; rolle uden
  `redaktion` → `EVIDENCE_ROLE_FORBIDDEN`; kald med et fremmed aktivt change_set → `PLACEMENT_MEMBERSHIP_FOREIGN_CHANGE_SET`;
  ægtefælle-persona får aldrig et item.
- [ ] **Trin 2:** Kør. Forventet: funktionerne findes ikke.
- [ ] **Trin 3: Implementér**, ACL, kopiér til migrationsblokken, registrér i db-rls og db-verify.
- [ ] **Trin 4:** Kør testen, db-verify og `tests/sql/test-relation-binding.sql` (uændret grøn).
- [ ] **Trin 5: Commit** `feat(150): membership-promotion fra accepteret placement`.

### Task 5: Opgraderingstest og hele CI lokalt

**Files:** Create `tests/sql/test-150-upgrade.sh` (kopi af `tests/sql/test-248-upgrade.sh`).

- [ ] **Trin 1:** Byg fra `git merge-base origin/main HEAD`, kør nye `db-migrations.sql` + `db-rls.sql` to gange,
  assert at de nye funktioner og tabellen findes, kør de tre nye testfiler og `run-db-verify-disposable.sql`.
  Slutter med `echo UPGRADE_OK`.
- [ ] **Trin 2:** Kør den og `test-248-upgrade.sh`. Forventet: `UPGRADE_OK` fra begge.
- [ ] **Trin 3:** Kør alle PostgreSQL- og python-jobs lokalt (#248's `ci_lokal.py` med `SCRIPT_BASER`), node-jobbet
  for core/web/mobil (læsere skal være uændrede). Forventet: alle grønne.
- [ ] **Trin 4: Commit** `test(150): opgraderingstest fra prods skema`.

### Task 6: Dataceremoniens SQL

**Files:**
- Create: `.claude/skills/daa-extract/scripts/fix_150_maal.sql` (faser `foer|ddl|bundet|ukendt` + tal), `fix_150_fingeraftryk.sql` (som
  `fix_248_a_fingeraftryk.sql` over Task 2-4's funktioner og tabeller), `fix_150_placement.sql` (ceremonien)
- Test: `tests/sql/test-150-ceremoni.sql` (ny, syntetisk mini-kilde gennem hele ceremonien) +
  `tests/sql/fixtures/manifest-150.json` (syntetisk manifest) og `tests/sql/test-150-ceremoni.sh` (kalder scriptet med
  `-v manifest_path=… -v expect_*=…`, som runneren gør)

**Interfaces:**
- Consumes: Task 1's skrivemanifest, indlæst klientside med `` \set m `cat :'manifest_path'` `` og `:'m'::jsonb`
  (aldrig `\copy` i text-format: backslash-escapes ødelægger JSON; `\copy` interpolerer heller ikke variabler; ingen
  serverside filadgang; scriptets stderr går til en privat fil, da en fejl kan ekkoe manifesttekst), forventede antal som psql-variabler (`-v expect_published=541` osv. fra runneren),
  Task 3-4's funktioner, `red_revalider_person_narrative_record(p_person_id,
  p_source_id, p_record_key, p_expected_state_sha256)`.
- Produces: kvitteringen `\echo FIX150_OK headers=<n> placements=<n> ledger=<n> memberships=<n> revalideret=<n>`.

- [ ] **Trin 1: Skriv den fejlende test** `tests/sql/test-150-ceremoni.sql`: 3 poster, 2 publicerede, 1 `unresolved`.
  `$revalider_to_i_traek$`: begge publicerede er `published` bagefter, 0 `stale_published`; ledgeren har 3
  gældende (`is_current`) dispositioner; memberships for de 2 egnede; genkørsel → `FIX150_PRE_FASE`;
  identitet ≠ bindingens person på den `unresolved` post → `FIX150_PRE_IDENTITY` uden skrivning;
  `$fortryd_en_post$`: runbookens manuelle rækkefølge for én post (membership-reversal → persona- og record-placement
  `superseded` via `red_decide_*` → `red_revalider_person_narrative_record` → `record_legacy_disposition`) ender med
  `published` og 0 stale.
- [ ] **Trin 2:** Kør. Forventet: scriptet findes ikke.
- [ ] **Trin 3: Implementér** `fix_150_placement.sql` som `fix_248_genaabn.sql` (én transaktion, `SET LOCAL
  statement_timeout='15min'` med assert lige efter, aktør via `request.jwt.claim.sub`, `\g /dev/null` på alle
  `set_config`). 15 min er husvalget (som `fix_248_genaabn.sql:15`); runneren printer `SHOW statement_timeout` før
  `BEGIN` (stand-in: 2min som prod) og skriver `\timing` til en privat fil:
  - `FIX150_PRE_*`: rolle; 0 placements for kilde 1 (ellers `FIX150_PRE_FASE`); manifestets `invariants` alle sande;
    manifestets sha = den GO-bundne; for alle `:expect_bindings` (587) bindinger i kilde 1 med accepteret
    hovedperson-identitet er identitetens person = bindingens person (uafhængigt af manifeststatus); alle `:expect_published` `publication_allowed=true`, tekst-sha = seneste event, 0 `stale_published`; præcis én
    canonical pr. entry; `app.change_set_id` tom.
  - Skriv overskrifter, placements (kun `machine_ok`), ledger (alle rækker: kilde 1 `mapped`/`unresolved`, kilde 3
    `retained_legacy`), `slaegt` → `active` under én change_set, **ryd `app.change_set_id`**, preview + promote
    memberships, assert tom GUC.
  - Revalidering: én genereret sætning pr. post med `\gexec` (`set_config('app.change_set_id','',true)` + RPC'en med
    den aktuelle tilstands-sha), fordi GUC'en skal ryddes før hvert kald (`NARRATIVE_RECORD_FOREIGN_CHANGE_SET`); tom
    GUC assertes efter sidste kald.
  - `FIX150_POST_*`: `:expect_published` `published`, 0 `stale_published`, 0 blokerede, uændret eligibility; ledger = 1.167
    gældende og `is_current` dispositioner; memberships = antal `machine_ok`; `placement_header_violations(1)=0`; paritet for de fem læsere (hash før = efter, beregnet
    i transaktionen).
- [ ] **Trin 4:** Kør testen. Forventet: grøn.
- [ ] **Trin 5: Commit** `feat(150): scripts til placement-ceremonien`.

### Task 7: Kontrolstikprøve, runner, runbook og øvelse

**Files:**
- Create: `.claude/skills/daa-extract/scripts/placement_control_sheet.py` (+ test) — stratificeret K=20-ark og
  token-fil for `unresolved`/uenigheder; ingen forudfyldte svar; `sql`-kommando afviser ubesvarede linjer
- Create: `docs/runbooks/150-placement-prod.md`
- Privat: `~/.private/5ab-overfoersel/21-150-5c.sh` (handlinger `go|maal|dump|advisors|ddl|placement`, kopi af
  `20-248-a.sh`; GO binder blokken, scripts, manifest, kontrolark og token-fil)

- [ ] **Trin 1: Arket** (TDD som Task 1): strata = første post efter hver linje- og slægtledsoverskrift, sideskift,
  kuld-markører; resten tilfældigt med fast seed; arket under `~/.private/5c/`.
- [ ] **Trin 2: Projektejeren** tjekker de 20 mod PDF'en og svarer på token-filen. Arkets hash bindes i GO. Én
  afvigelse i stikprøven stopper kørslen og går tilbage til Task 1.
- [ ] **Trin 3: Runner og runbook** (form som `docs/runbooks/248-genaabning-prod.md`): `go → maal → dump → advisors →
  ddl → maal → advisors (+1 rls_enabled_no_policy) → placement → maal (fase bundet)`; dump-vagt; kendte følger fra spec §5.
  Fortrydelse: dumpet er nødudvejen (som #248); runbooken lister den manuelle rækkefølge pr. post (som
  `$fortryd_en_post$`) og at `db-rls.sql` køres igen efter en restore (DEFAULT PRIVILEGES).
- [ ] **Trin 4: Øv** på en frisk kopi af `…_5ct` med `ALTER DATABASE … SET statement_timeout='2min'`: hele runbooken,
  rækkediff (kun spec §5's tabeller), paritet; notér maks. tid pr. sætning og samlet varighed fra `\timing`-filen.
- [ ] **Trin 5: Negativer:** forkert GO, manglende flag, gentaget `placement` (fase), og en manipuleret identitet
  (persona-placementens person ≠ bindingens) → `FIX150_PRE_IDENTITY` uden skrivning.
- [ ] **Trin 6: LegacyBackfillFreeze:** ca. 6 linjer ved F6-vagten i `backfill_slaegtled.R`: tæl
  `private.legacy_placement_disposition` for kilden; count > 0 eller enhver fejl → stop. `post_load_fixup.R` arver
  vagten (kalder scriptet som underproces, `:157`). Køres ikke (læser `~/.Renviron` = prod); verificeres ved review.
- [ ] **Trin 7: Commit** hver for sig: `feat(150): kontrolark for placement`, `fix(150): backfill_slaegtled fryses efter 5c`,
  `docs(150): runbook for placement i prod`.

### Task 8: Review og PR

- [ ] **Trin 1:** Codex `gpt-5.6-sol` over hele grenen (eksport via `git archive`, `--skip-git-repo-check`), Opus
  dømmer fundene; ret kun det godkendte efter projektejerens ja.
- [ ] **Trin 2:** `docs/decisions.md`: post for 5c-1 (header-modellen, ledger, membership-gyldighed); status- og
  roadmap-noter efter prod.
- [ ] **Trin 3:** Hele CI lokalt igen; spørg om push og draft-PR.
