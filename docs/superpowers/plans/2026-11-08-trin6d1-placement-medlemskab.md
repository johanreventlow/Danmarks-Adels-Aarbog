# Trin 6d-1: overskrifter, placement og medlemskab for 1939 — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 1939's poster får bogens egne koordinater (gren, slægtled, gruppe, løbenummer) som kildebundet evidens —
overskrifter → record- og persona-placement → ledger → medlemskab på kilde 3-rækkerne — og en `samme_som`-komponent,
som begge udgaver placerer i samme linje, kan læses som `corroborated`; alt i én data-ceremoni uden et eneste
`stale_published` bagefter.

**Architecture:**
- **Profil (Python):** `build_header_manifest.py` bliver profilstyret. 2018-20's grammatik flyttes uændret ind bag
  profilen `header-2018-20-v1` (byte-ens manifest); 1939 får `header-1939-v1`, der genbruger `segment.py`'s
  `UDGAVE_PROFILER['1939']` og kobler records til overskrifter **efter tegnposition** (1939's record-nøgler er præfiks +
  uuid, så 2018-20's nøgleafledning kan ikke bruges).
- **Generel DDL (lille):** ledgeren kan give `mapped` via identitet; promotionen afviser et medlemskab fra en anden kilde;
  ny læse-kun `private.membership_component_states()`; evt. en kildeentydigheds-gate i læserens koordinat-RPC
  (afgørelse 4).
- **Prod:** én DDL-ceremoni og én data-ceremoni (linjeskema, overskrifter, placements, ledger, medlemskab,
  revalidering) gennem en privat runner, øvet på en stand-in fra et frisk prod-dump.

**Tech Stack:** PostgreSQL 17 (plpgsql, psql), Python 3.11 (pytest), bash/zsh (opgraderingstest, privat runner).

**Spec:** `docs/superpowers/specs/2026-11-08-trin6d-placement-relationer-medlemskab-design.md` (godkendt 2026-11-08;
Fable-review §11). Mekanismen: 5c-1 (`docs/superpowers/plans/2026-10-26-trin5c-placement-membership.md`).

## Roadmap-kobling

Spec §1: trin 6, færdigbevis (a) for placement og (c) B6 i afledt form; værdikædeled source record → overskrift →
placement → medlemskab. Erstatter 1939's syntetiske `linje='1939'`/globale nr. som eneste placering. Færdigbevis:
Task 10 trin 4 (spec §8). Review-budget (B13): én Codex-runde (`gpt-6.1-sol`) på spec+plan (Task 0 trin 5), én på
diffen (Task 10 trin 1); Opus afvejer hvert fund (memory `opus-afvejer-codex-fund`).

## Global Constraints

- **Gren:** `feat/trin6d1-placement` fra `docs/trin6d-spec`. PR'er altid `--draft`. Intet push uden projektejerens ja.
- **Prod** røres kun i projektejerens shell med GO (`--jeg-mener-det --go <kode>`); AI'en kører kun mod lokale baser.
  Dump med ekstern kopi før hver skrivende ceremoni; vinduesvagten fra starten (memory `vindues-vagt-ikke-kun-change-set`);
  fortrydelse = restore + `db-rls.sql` igen.
- **Ingen nye overskriftstyper** (spec §5.1): 1939's niveauer mappes til `header_linje`, `header_slaegtled`,
  `header_kuld`; `header_aegteskab` kun hvis bogen har dem. Regelversioner: `header_rule_version='header-1939-v1'`,
  `rule_version='placement-membership-v1'` (uændret).
- **Ingen editionsnavngiven permanent overflade:** ingen ny 1939-writer, -tabel eller -RPC. Nye scripts er
  kildeparametriserede (`-v src=3`); profiler og målescripts må bære udgave-/trinnavn (præcedens: `maal_trin6c1.sql`).
- **`schema.sql` er source of truth.** `db-migrations.sql` får én ny blok sidst i filen, der begynder med
  `-- ===== trin 6d-1: placement og medlemskab for flere kilder =====`; nye/ændrede funktioner har byte-ens krop i
  begge filer; migrationen er idempotent (to kørsler). Ældre blokke redigeres ikke. `fix_150_*.sql` fryses (læses, ændres ikke).
- **2018-20 uændret** (spec §4 anti-mål): 2018-20's placements, medlemskaber, publiceringer og
  `public_person_source_coordinates`-rækker byte-ens (hash) før og efter.
- **Indholds-id'er:** nye rækker via `private.content_uuid`; ark og manifester refererer record_key, entry-kode og
  linjens `(source_id, kode)`, aldrig tilfældige id'er fra en tidligere kørsel (memory `pin-indhold-ikke-ceremoniens-id`).
- **PII (invariant 8):** renditionen `work_1939_stamtavle/full_ocr_calamari_r6_clean.txt` (sha `020123a3…`) læses kun
  deterministisk og lokalt, aldrig af en model. Manifest, ark og token-filer kun under `~/.private/6d1/` (0600). Scripts,
  der læser `work*/`, skriver stdout+stderr til fil og rapporterer antal (memory `pii-probe-omdiriger-begge-streams`).
  Tests bruger opdigtede personer med negative id'er. Chat, commits, rapporter: kun tal, nøgler og hashes.
- **Miljø:** `env -u PGOPTIONS` foran psql, `env -u NODE_OPTIONS` foran npm, `/usr/bin/python3 -m pytest`.
  Prods `statement_timeout` er 2 min pr. sætning; stand-in-tid er ikke prod-tid (mål forholdet).
- **Implementer-briefs:** ingen kommando på `~/.private`, heller ikke `ls`; drop ikke databaser, list dem.
- **Commits:** atomiske, Conventional Commits på dansk, ingen Claude-attribution; trailer
  `Claude-Session: https://claude.ai/code/session_01VptDwxfa7QuCnVDfrmTTVN`.

## Review Focus

1. **En guide-overskrift, der ikke genfindes i Calamari.** Posterne under den må ikke arve forrige overskrift af samme
   niveau eller guidens værdi uden evidens: `unresolved` med `overskrift_ikke_fundet:<niveau>`. Låses af
   `test_overskrift_ikke_fundet_er_unresolved` i Task 1.
2. **Records uden nummereret post** (stamfædre, »Personer af Navnet Reventlow, der ikke kan anvises Plads«). De får
   aldrig placement: `unresolved` med `uden_post`. Låses af `test_uden_post` i Task 1.
3. **En `samme_som` uden `afklaret` konklusion** må ikke forbinde to komponenter. Låses af `$ikke_afklaret$` i Task 4.
4. **En komponent med medlemskaber i to linjer** (2 findes i dag) er `conflict`, og intet skrives eller slettes.
   Låses af `$konflikt_uroert$` i Task 4 og ceremoniens POST (Task 7).
5. **1939-læserrækkerne skifter koordinater ved promotion** (`public_person_source_coordinates` bruger placement ved
   gældende medlemskab). Ceremonien hasher 1939-rækkerne før/efter og sammenligner med afgørelse 4's forventning.
   Låses af `$laeser_1939$` i Task 5 og ceremoniens `PLC_POST_LAESER`.

## Afgørelser (Gate A, 2026-11-08 — projektejeren: ja til alle anbefalinger)

Målt i Task 0 (stand-in c3h; tal i `~/.private/6d1/maaling.txt`); beslutningen står i `docs/decisions.md` 2026-11-08.

6. **Overskrifternes kilde:** raw.txt (`work_1939_stamtavle/raw.txt`, sha `efab316b528eafc60074c21c877590b31ab8e960cd1adc14f5c79bf01f12dab7`)
   er guide og kontrol; overskrifterne skrives på Calamari-renditionen (sha `020123a3…`), hvor de genfindes mellem
   samme naboposter (målt: linje 6/6, stamme 2/2, slægtled 44/48, beskrivelser 68/77, romertal 29/75). Ikke genfundne →
   kort. Calamari alene giver 5 linjer, 5 slægtled, 0 romertal og bruges ikke.
1. **Fællesstammen:** de 2 stammesektioner (43 poster i raw) bliver entries; linjearket (Task 2) afgør deres linje.
2. **Validatoren** ændres ikke (alle poster har en linje- eller stammeoverskrift foran ved 6).
3. **Records uden nummereret post (revideret 2026-11-08, `docs/decisions.md`):** de unummererede Calamari-records
   parres med raw.txt's `_segment_1939_v2`-poster (Task 1b): stamfædre (18) placeres uden nummer; nummer ødelagt i
   Calamari (4) og uparrede med persona (17) → kort med guidens forslag; oversigtsposter (18) og uparrede uden persona
   (26) ingen placement, `retained_legacy`, grund `ingen_nummereret_post`. Oprindeligt: ingen placement. Gate A sagde 37
   (29 med persona), målt via Calamari-segmenteringen; Task 1's rigtige kørsel giver **83 (57 med persona)**, i tråd med
   raw-v2's ~89 unummererede poster (stamfædre, oversigter). Beslutningen gælder uændret; tallet meldes i færdigbeviset.
4. **Læseren:** variant (b) — kildeentydigheds-gaten i `public_person_source_coordinates` (Task 5). 1939: 53 numre deles
   af 389 poster, så 1939-rækkerne forbliver `legacy_external_id` indtil 6e; `expect_laeser_1939=uaendret`.
5. **3 personas uden accepteret identitet:** record-placement, ingen persona-placement, intet medlemskab. Antallet af
   persona-placements er **ikke** 560 (Codex r1 #1): 29 personas sidder på de 37 records uden nummereret post, så højst
   534; det forventede tal = |nummereret post ∩ ikke parkeret gren ∩ accepteret placement ∩ accepteret identitet|,
   beregnet af Task 1's manifest og fastlåst i runneren. Alle 563 bindinger er `published` og opslag via recordens nøgle virker; 0 kanoniske dubletter.

---

### Task 0: Måling, stand-in og Gate A (kun lokalt; ingen kode-commits)

**Files:** noter i `~/.private/6d1/maaling.txt`; probe-scripts i `$CLAUDE_JOB_DIR/tmp`. Målt på c3h (Gate A pkt. 6 i
`docs/decisions.md`); frisk stand-in fra prod først i Task 9.

- [x] **Trin 2 (DB, kun antal):** genmål spec §2's tal; personas pr. `record_kind`/`mention_role` (forventet: alle 563
  `primary` på helposten); `count(distinct canonical_person_id)` over de 560 accepterede identiteter (to personas med
  samme person giver `conflict` i `placement_membership_set`, og promotionen stopper på enhver konflikt); bindinger pr.
  record (via `narrative_record_publication` → `source_record`) og dermed antal publiceringer, placementerne gør
  `stale_published`; om kort 122's binding blokeres af en persona-placement (afgørelse 5). Revalideringens *tid* måles
  i Task 9's generalprøve. `(gren, nr)`-kollisioner kan først tælles efter trin 3.
- [x] **Trin 3 (tekst):** kør en engangsprobe, der kalder `segment._segment_1939` på renditionen og tæller overskrifter
  pr. niveau, distinkte gren-/slægtled-/gruppelabels (labels er bogens strukturord, ingen navne — vis kun romertal og
  ordinaler), records pr. fase (stamme/gren), records uden `header_linje` foran tidligste forekomst, records uden
  nummereret post, `(gren, nr)`- og `(section_path, nr)`-kollisioner. stdout+stderr til fil.
- [x] **Trin 4: Gate A.** Vis projektejeren tallene og afgørelse 1-5 som ét samlet valg; skriv svarene ind i planen og
  `docs/decisions.md`; commit `docs(6d): plan-afgørelser efter måling`.
- [x] **Trin 5: Codex-runde** (`gpt-6.1-sol`) på spec+plan fra en eksport uden `work*/` (`git archive`,
  `--skip-git-repo-check`; udeluk `work*/` i selve søgekommandoen, memory `codex-soegning-pii-filnavne`). Opus dømmer
  hvert fund (nødvendig / forenkl / kendt begrænsning / afvis); indarbejd efter projektejerens ja; log i spec §11;
  commit `docs(6d): plan efter Codex-runde`.

### Task 1: Profilstyret overskriftsscanner og 1939-profilen

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/build_header_manifest.py`
- Create: `.claude/skills/daa-extract/references/header-profiles/header-2018-20-v1.json`,
  `header-1939-v1.json`
- Create: `.claude/skills/daa-extract/scripts/placement_eksport.sql` (kildeparametriseret, læsetransaktion)
- Test: `.claude/skills/daa-extract/scripts/test_build_header_manifest.py` (udvid)

**Interfaces:**
- Header-profil (JSON): `{header_rule_version, raw_text_sha256, grammar: "2018-20"|"1939", record_matching:
  "key_from_text"|"earliest_occurrence", levels: {<bogniveau>: <header-kind>}, stamme_afsnit_level: "slaegtled"|null,
  guide_text_sha256: <sha>|null}`. `grammar` peger på `segment.UDGAVE_PROFILER[...]`; regexerne flyttes ikke ud af
  `segment.py`. 1939-profilen: `raw_text_sha256` = Calamari-renditionen (`020123a3588dacf80705a22fb021ab4f5da97b8de202e8664304ca01f9a6da37`),
  `guide_text_sha256` = raw.txt (`efab316b528eafc60074c21c877590b31ab8e960cd1adc14f5c79bf01f12dab7`); begge tjekkes
  (`HEADER_RENDITION_SHA_MISMATCH` / `HEADER_GUIDE_SHA_MISMATCH`).
- `placement_eksport.sql` (`-v src=N`) → JSON `{entries:[code…], records:[{record_key, record_kind, page_from,
  char_from, legacy:{linje,nr}|null}], parents:[{child, parent}], counterparts:[{record_key, lineage_kode, source_id}]}`.
  `char_from` = tidligste accepterede forekomst med validatorens orden (`ORDER BY page_from, char_from, id LIMIT 1`,
  `schema.sql:2404`). `parents` og `legacy` går via identitet (persona → accepteret `canonical_person_id` →
  `family_member` / `person_external_id`), ikke via `record_key`. `counterparts` = 2018-20-linjen for hver afklaret
  `samme_som`-modpart til recordens kanoniske person. Ingen navne eller tekst.
- `build_manifest(rendition_bytes, profile, legacy, parents=None)` — **uændret** for `grammar="2018-20"`.
- `build_manifest_by_offset(rendition_bytes: bytes, guide_bytes: bytes, profile: dict, records: list[dict],
  parents: list[dict]) -> dict` med samme nøgler som 2018-20-manifestet (`headers`, `placements`, `invariants`,
  `disagreements`, `header_rule_version`) plus `transfer` (pr. niveau: guide-antal, genfundet, ikke genfundet). Pr.
  placement desuden `record_kind`, `post_char_from`, `guide_lokal_id`; `generation_global=None`; `kuld_label` = guidens
  romertal eller beskrivelses-slug; `section_path` = header-id'er gren → slægtled → gruppe.
- **Guide-scanning (raw.txt):** samme tilstandsovergange som `segment._segment_1939` (linje-blok → niveau `linje` med
  `roman`; stammesektion → `linje` med `stamme_slug`, entry-kode `Stamme-<slug>`; slægtled → `slaegtled` med `ordinal`,
  `label_raw`; afsnit-romertal → `kuld`, i stammefasen → `slaegtled` når `stamme_afsnit_level="slaegtled"`;
  gruppebeskrivelse → `kuld` kun når intet frisk romertal står foran, ellers del af romertallets gruppe).
- **Overførsel til Calamari:** begge tekster scannes for poster; postsekvenserne alignes på `nr_label` med
  `difflib.SequenceMatcher(autojunk=False)` (deterministisk; målt 476/505). Hver guide-overskrift søges i Calamari-
  linjerne mellem de alignede naboposter med niveauets matcher: linje = romertallet alene på linjen eller kort linje med
  »Linje«; stamme = sluggens ord + »Linje«; slægtled = normaliseret linje (kun bogstaver, små) begynder med ordinalen og
  indeholder `slægtled`, < 30 tegn; romertal = linjen er romertallet (± `.,`); beskrivelse = normaliseret
  beskrivelse genfundet som delstreng af vinduet (længste fælles stykke ≥ max(15, 60 % af de første 60 tegn)). En
  gruppe er genfundet, når romertallet **eller** beskrivelsen er. Genfundet → header med Calamari-linjens tegnspænd og
  `verbatim_text` fra Calamari. Flere kandidater i vinduet → ikke genfundet (aldrig gæt).
- **Værdier kun fra det, Calamari viser** (beviset skal kunne efterprøves i basens rendition): `parsed` udledes af
  Calamari-linjen, ikke af guiden. Er gruppen kun genfundet via beskrivelsen, er `kuld_label` beskrivelses-sluggen (som
  `segment._segment_1939` gør, når romertallet mangler), aldrig guidens romertal. En linjeoverskrift genfundet uden
  romertal kræver, at linjenavnet (normaliseret) er det samme som guidens; entry-koden er da guidens romertal, bundet
  til navnet. Guiden står kun som sporbarhed i `parsed.guide = {value, char_from, line_sha256}` (raw.txt's linje,
  ingen tekst) og i kørslens `guide_text_sha256`.
- **Records er posterne** (fix-runde 1, målt: 509 records begynder med et postnummer, 213 midt i en linje, fordi
  Calamari ofte løber posterne sammen; 0 deler `char_from`): renditionens post = recorden selv, sorteret på `char_from`;
  nummeret parses ved `char_from` med `^\s{0,6}\??\s{0,2}(\d{1,3})\s*([a-z]?)\s*[.,]\s`; intet nummer → `uden_post`.
  Alignmentet er guide-poster mod nummererede records; header-vinduerne er renditionslinjerne mellem de alignede
  naboers `char_from`. Calamari-postsegmenteringen bruges ikke i 1939-stien.
- **Persona-vagt:** mere end én record med persona i samme fysiske post → alle `unresolved` (`flere_personas_i_post`);
  records uden persona må dele postens koordinater.
- Pr.-post-årsager (→ `unresolved`): `overskrift_ikke_fundet:<niveau>`, `ikke_alignet`, `uden_post`, `flere_personas_i_post`,
  `nr_ikke_fortloebende`, `slaegtled_ikke_monoton`, `gruppe_flere_familier`, `uenig:foraelder_generation`,
  `uenig:legacy_linje`, `uenig:legacy_nr` (kun hvor legacy-linjen ikke er `1939`). Kørselsinvarianter (alle skal være
  sande): `record_keys_unikke`, `section_path_nr_unik` (blandt `machine_ok`, pr. **fysisk post** = `post_char_from`: flere
  records i samme post deler lovligt koordinater; to forskellige poster med samme `(section_path, nr)` bryder),
  `en_overskrift_pr_gruppe`,
  `segmenter_paritet` (guide-scannerens lokal_id'er = `_segment_1939(raw)`'s).
- CLI: `--header-profile` (default 2018-20-profilen), `--guide-text` (kræves ved `guide_text_sha256`), `--legacy-json`
  eller `--records-json` (gensidigt udelukkende); `summary()` uændret plus `transfer`.

- [x] **Trin 1: Skriv de fejlende tests** (syntetisk 1939-tekst, opdigtede navne):
  - `test_2018_20_byte_ens`: manifestet for den eksisterende 2018-20-fixture har samme `canonical_sha256` som før
    refaktoreringen (sha'en hardkodes i testen, målt før ændringen).
  - `test_1939_niveauer`: centreret guide + ucentreret rendition (samme opdigtede poster): linje-blok, slægtled,
    afsnit-romertal giver tre header-kinds med renditionens offsets; posten får `section_path` med tre id'er,
    `generation_local`, `kuld_label`.
  - `test_record_efter_offset`: to records i samme post (person + fact) får samme `printed_number`/`section_path`.
  - `test_overskrift_ikke_fundet_er_unresolved` (slægtledslinjen fjernet fra renditionen), `test_uden_post`,
    `test_ikke_alignet` (en post kun i guiden), `test_to_kandidater_er_ikke_fundet`.
  - `test_gruppe_via_beskrivelse` (romertallet mangler i renditionen, beskrivelsen findes → gruppen genfundet,
    `kuld_label` = beskrivelses-slug, guidens romertal kun i `parsed.guide`).
  - `test_linje_uden_romertal_kraever_samme_navn` (navn afviger → ikke genfundet).
  - `test_stammesektion_er_entry` (stammesektion → `header_linje`, entry-kode `Stamme-<slug>`).
  - `test_gruppebeskrivelse_efter_romertal_er_ikke_ny_overskrift` og `test_gruppebeskrivelse_alene_er_kuld`.
  - `test_nr_brud_og_slaegtled_fald`: brud giver årsagen på posten, ikke en falsk kørselsinvariant.
  - `test_gruppe_flere_familier` (parents-par fra to forældrefamilier i én gruppe).
  - `test_segmenter_paritet`: scannerens lokal_id'er (`linje.slaegtled.afsnit.nr`) = `_segment_1939`'s i samme orden;
    en bevidst afvigelse giver `segmenter_paritet=False`.
  - `test_offsets_renditionsabsolutte` (1939) og `test_summary_uden_tekst` (1939).
- [x] **Trin 2:** `/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_build_header_manifest.py -q` →
  de nye fejler, de gamle er grønne.
- [x] **Trin 3: Implementér** profilerne, dispatch og `build_manifest_by_offset`; eksport-SQL'en. Ingen netværk, ingen model.
- [x] **Trin 4:** pytest igen → alle grønne. **Prods 2018-20-manifest:** kør den refaktorerede scanner med
  2018-20-profilen på `work/raw_full.txt` + en frisk `fix_150_eksport.sql`-eksport (`-v src=1`) fra stand-in'en, og
  assert at `summary()['manifest_sha256']` = værdien i stand-in'ens `header-2018-20-v1`-`extraction_run` (fix_150
  bandt den). Kør derefter 1939-eksporten mod stand-in'en og manifestet på den rigtige tekst (`--guide-text
  work_1939_stamtavle/raw.txt`; output under `~/.private/6d1/`, stdout+stderr til fil); notér `summary()`'s tal i
  `maaling.txt`. Forventet omtrent Task 0's overførselstal; er en kørselsinvariant falsk: stop og vis antallet.
- [x] **Trin 5: Commit** `feat(6d): profilstyret overskriftsscanner med 1939-profil`.

### Task 2: Linjeskema-ark (grene → slægtslinjer)

**Files:**
- Create: `.claude/skills/daa-extract/scripts/lineage_mapping_sheet.py` + `test_lineage_mapping_sheet.py`

**Interfaces:**
- Consumes: Task 1's manifest (grenlabels) og eksportens `counterparts`.
- `render(manifest, export) -> (ark_tekst, token_tekst)`: én linje pr. gren med fordelingen af modparternes
  2018-20-linjer (antal pr. `lineage_kode`) og forudfyldt forslag = flertalslinjen, når den har ≥ 80 % og ingen anden
  linje > 2; ellers intet forslag (memory `forudfyldt-ark-skjuler-konflikt`). Den eksisterende entry `VI` står med sin
  nuværende `canonical` (lineage `(3,'VI')`). Stammesektionerne (`Stamme-<slug>`, Gate A pkt. 1) er linjer på arket.
- Token-svar pr. gren: `C <lineage_kode>` (canonical), `A <kode>` (tilføj `historical_alias`), `P` (parkér), `S <kode>`
  (kilde 3-linje). `approvals(...) -> dict {sheet_sha256, entries:[{code, label_sha256, sort_order,
  canonical:{source_id,kode}|null, aliases:[…], parkeret:bool}]}`; ubesvarede linjer afvises.

- [x] **Trin 1: Fejlende tests:** forslag ved klart flertal; intet forslag ved 70/30; `VI` bevares; ubesvaret linje →
  fejl; `P` giver `parkeret=true` og `canonical=null`; output indeholder ingen navne (kun koder og antal).
- [x] **Trin 2-4:** kør (fejl) → implementér → kør (grøn). Render arket for stand-in'en til `~/.private/6d1/`.
- [x] **Trin 5: Projektejeren** svarer på token-filen (spec §6 pkt. 1). Arkets sha bindes i GO.
- [x] **Trin 6: Commit** `feat(6d): ark for 1939's grene til slægtslinjer`.

### Task 3: Ledger via identitet og vagt mod fremmed kilde i promotionen

**Files:**
- Modify: `schema.sql` (`private.record_legacy_disposition` `:2958`; `public.red_promote_placement_memberships`
  `:3102`), ny migrationsblok
- Test: `tests/sql/test-placement-writer.sql`, `tests/sql/test-placement-membership.sql` (udvid)

**Interfaces:**
- `record_legacy_disposition` (samme signatur): `mapped` er også gyldig, når der findes en gældende accepteret
  `principal_member`-persona-placement på `p_placement_id`, hvis personas accepterede identitet har
  `canonical_person_id = p_person_id`. Den gamle `record_key`-vej er uændret. Ellers `PLACEMENT_LEGACY_MAPPING_INVALID`.
- `red_promote_placement_memberships` (samme signatur), to ændringer (Codex r1 #4, #6):
  1. **Før** det generelle konfliktstop (`PLACEMENT_MEMBERSHIP_CONFLICT`): findes for et item en række på
     `(person_id, lineage_id)` eller `(person_id, slaegt_id)`, hvis `source_basis->>'source_id'` ikke er
     `p_source_id::text` (også NULL) → `PLACEMENT_MEMBERSHIP_FOREIGN_SOURCE`; intet skrives.
  2. **Atomisk i skrivningen:** begge upserts får `ON CONFLICT … DO UPDATE … WHERE <tabel>.source_basis->>'source_id'
     = excluded.source_basis->>'source_id'`; `GET DIAGNOSTICS` 0 rækker → `PLACEMENT_MEMBERSHIP_FOREIGN_SOURCE`
     (dækker en anden kildes række indsat mellem forhåndstjek og skrivning). Ingen tosessionstest (ceremonien kører i
     én session; Opus-dom »forenklet«).

- [x] **Trin 1: Fejlende tests:** `$ledger_via_identitet$` (record_key ≠ legacy-nøgle, identitet = personen → mapped);
  `$ledger_anden_person$` og `$ledger_identitet_ikke_accepteret$` → `PLACEMENT_LEGACY_MAPPING_INVALID`;
  `$ledger_noegle_uaendret$` (den gamle vej virker); `$fremmed_kilde$` (eksisterende medlemskab med kilde 1 på samme
  `(person, linje)` → `PLACEMENT_MEMBERSHIP_FOREIGN_SOURCE`, ikke `…_CONFLICT`, 0 rækker ændret); `$fremmed_kilde_null$`;
  `$fremmed_kilde_i_skrivning$` (testens midlertidige AFTER INSERT-trigger på `person_lineage_membership` indsætter en
  kilde 1-række i `person_slaegt_membership` for samme person; slægts-upserten rammer den → 0 rækker →
  `PLACEMENT_MEMBERSHIP_FOREIGN_SOURCE`, transaktionen rulles tilbage; triggeren droppes i testen).
- [x] **Trin 2:** `env -u PGOPTIONS psql -v ON_ERROR_STOP=1 -f tests/sql/test-placement-writer.sql` (og membership)
  → de nye fejler.
- [x] **Trin 3:** Implementér, kopiér byte-ens til migrationsblokken.
- [x] **Trin 4:** Begge testfiler + `tests/sql/run-db-verify-disposable.sql` → grønne.
- [x] **Trin 5: Commit** `feat(6d): ledger mapped via identitet og vagt mod fremmed kilde`.

### Task 4: Afledt B6 — komponenttilstand for medlemskab

**Files:**
- Modify: `schema.sql` (efter `placement_membership_set`), migrationsblokken, `db-verify.sql` (`::regprocedure`-listen
  + ACL-assert)
- Create: `tests/sql/test-membership-component.sql`; tilføj den til `.github/workflows/ci.yml` efter
  `test-placement-membership.sql` (`:241`)

**Interfaces:**
- `private.membership_component_states() RETURNS TABLE(component_root bigint, members bigint[], state text,
  lineage_ids bigint[], source_ids bigint[], same_source_duplicate boolean)`. STABLE, INVOKER, `REVOKE ALL … FROM
  PUBLIC,anon,authenticated,service_role`. Komponent = lukningen over `relation` med `rolle='samme_som'`
  (person↔person) **og** en `conclusion` (`target_type='relation'`, `status='afklaret'`); egen rekursiv CTE —
  `_samme_som_gruppe` (`:7718`) bruges ikke (intet statusfilter). `component_root` = mindste person-id. Kun gældende
  medlemskaber (`membership_is_current`) tæller; kilde = `source_basis->>'source_id'`.
  `state`: `corroborated` (≥ 2 kilder, præcis 1 linje), `conflict` (≥ 2 linjer), `single` (1 kilde, 1 linje),
  `none`. `same_source_duplicate` = to medlemskaber fra samme kilde i komponenten (vises som fund, ikke bekræftelse).
  Kun komponenter med mindst ét medlemskab eller mindst to personer returneres.

- [x] **Trin 1: Fejlende test** (opdigtede personer, negative id'er): `$bekraeftet$` (kilde 1 og 3, samme linje);
  `$konflikt_uroert$` (to linjer → `conflict`, tabellerne uændret); `$enkelt$`; `$ikke_afklaret$` (`samme_som` med
  `omstridt` konklusion splitter komponenten); `$samme_kilde_dublet$` (to kilde 3-personer → `single`,
  `same_source_duplicate=true`); `$ikke_gaeldende$` (identitet omafgjort → medlemskabet tæller ikke); `$acl$` (anon og
  authenticated kan ikke kalde den).
- [x] **Trin 2-4:** kør (fejl) → implementér + migrationsblok + db-verify → testen og db-verify grønne. Mål kørselstiden
  på stand-in'en (forventet < 1 s; 719 relationer).
- [x] **Trin 5: Commit** `feat(6d): afledt komponenttilstand for medlemskab (B6)`.

### Task 5: Læserens koordinater kræver entydige placements pr. kilde (afgørelse 4b)

**Files:** Modify `schema.sql` (`public_person_source_coordinates` `:3164`), migrationsblokken;
Test: `tests/sql/test-person-source-coordinates.sql` (udvid).

**Interfaces:** samme signatur og kolonner. `m1` udvides med kildegaten: en kilde bruger placement-koordinater kun,
når ingen to af dens gældende membership-placements deler `(scheme_entry_id, printed_number)`; ellers falder alle
kildens rækker til legacy. Ingen udgavenavne.

- [x] **Trin 1: Fejlende tests:** `$laeser_1939$` (to placements i samme entry med samme nummer → begge kildens rækker
  `legacy_external_id`); `$laeser_entydig$` (entydig kilde → `placement`, som i dag); eksisterende tests uændrede.
- [x] **Trin 2-4:** kør → implementér → grøn; desuden 5c-2's paritetstest for 2018-20-rækkerne.
- [x] **Trin 5: Commit** `feat(6d): læserens koordinater kræver entydige placements pr. kilde`.

### Task 6: Opgraderingstest og hele CI lokalt

**Files:** Create `tests/sql/test-6d1-upgrade.sh` (kopi af `tests/sql/test-150-upgrade.sh`).

- [x] **Trin 1:** Byg fra `git merge-base origin/main HEAD`, kør nye `db-migrations.sql` + `db-rls.sql` to gange, assert
  at Task 3-5's funktioner har de nye kroppe (`pg_get_functiondef`-sha = `schema.sql`'s), kør Task 3-5's testfiler og
  `run-db-verify-disposable.sql`; slut med `echo UPGRADE_OK` (memory `signaturaendring-kraever-opgraderingstest`).
- [x] **Trin 2:** Kør den og `test-150-upgrade.sh` → `UPGRADE_OK` fra begge.
- [x] **Trin 3:** Hele CI-jobbet lokalt: alle PostgreSQL-jobs, python-jobbet, R-suiten, node (core/feed/web/mobil m.
  `tsc --noEmit`) (memory `koer-hele-ci-jobbet-lokalt`). Forventet: alt grønt.
- [x] **Trin 4: Commit** `test(6d): opgraderingstest fra prods skema`.

### Task 7: Data-ceremoniens SQL og målescript

**Files:**
- Create: `.claude/skills/daa-extract/scripts/placement_ceremoni.sql` (kildeparametriseret; model:
  `fix_150_placement.sql`, som fryses), `maal_trin6d1.sql` (faser `foer|ddl|data` + tal; printer i hver fase `KOORD_2018_20=<md5>` over
  `public_person_source_coordinates()`-rækkerne med `source_id<>3` i fast orden; runneren stopper, hvis `ddl` eller
  `data` afviger fra `foer`), `test_maal_trin6d1.py`
  (som `test_maal_trin6c1.py`)
- Test: `tests/sql/test-placement-ceremoni.sh` + `tests/sql/fixtures/manifest-6d1.json`, `mapping-6d1.json`
  (syntetisk mini-kilde gennem hele ceremonien); tilføj til `ci.yml` efter `test-150-ceremoni.sh`

**Interfaces:**
- Consumes: Task 1's manifest, Task 2's mapping-afgørelser, kortsvar fra Task 8 (`approvals`), Task 3-5's DDL,
  `red_revalider_person_narrative_record(p_person_id, p_source_id, p_record_key, p_expected_state_sha256)`.
  Filerne indlæses klientside med `` \set m `cat :'manifest_path'` `` (aldrig `\copy`); stderr til privat fil.
- psql-variabler: `actor src go manifest_path manifest_sha mapping_path mapping_sha approvals_path approvals_sha
  rendition_sha header_rule_version expect_headers expect_entries expect_placements expect_persona_placements
  expect_bindings expect_published expect_revalidated expect_ledger_mapped expect_ledger_retained expect_memberships
  expect_corroborated expect_conflict expect_laeser_1939 expect_koord_2018_20` (`expect_laeser_1939` ∈
  `uaendret|placement`; `expect_koord_2018_20` = baseline-hashen fra `maal foer`).
- **Bindinger og tilstande slås op via recorden, aldrig via legacy-rækken:** `private.narrative_record_publication b
  JOIN private.source_record sr ON sr.id=b.source_record_id` (kilde `src`), og `narrative_record_state(n.subjekt_id,
  sr.source_id, sr.record_key)` / `red_revalider_person_narrative_record(n.subjekt_id, sr.source_id, sr.record_key, …)`
  med recordens nøgle. fix_150's `person_external_id.record_key`-opslag rammer kun 8/576 kilde 3-rækker.
  Personen pr. record kommer fra den accepterede identitet.
- Kvittering: `\echo PLC_OK entries=… headers=… placements=… persona=… ledger_mapped=… memberships=… revalideret=…
  corroborated=… conflict=…`.
- Rækkefølge (én transaktion, `SET LOCAL statement_timeout='15min'` + assert; aktør via `request.jwt.claim.sub`;
  `\g /dev/null` på alle `set_config`):
  1. `PLC_PRE_*`: rolle; DDL til stede (Task 3-5's kroppe); tom `app.change_set_id`; fase = 0 placements for `src`;
     manifestets `header_rule_version` = `:header_rule_version` og alle kørselsinvarianter sande; manifest-, mapping- og
     approvals-sha = de GO-bundne; præcis én rendition med `rendition_sha`; identitet = binding for alle `:expect_bindings`
     bindinger på records, der får persona-placement (afgørelse 5; fix_150's materialiserede form, `fix150_pi`-mønstret
     med `ANALYZE`); ingen to personas, der får placement, har samme `canonical_person_id` (`PLC_PRE_SAME_PERSON`);
     `:expect_published` publiceret,
     0 `stale_published`; mappingen dækker hver `entry_code` i de poster, der skrives.
  2. Linjeskema under change_set `placement_lineage_scheme`: nye `lineage_scheme_entry` (kode, label, sort_order) og
     `lineage_scheme_entry_lineage` (`canonical` + `historical_alias`) **kun for ikke-parkerede grene**; linjen slås op
     på `(source_id, kode)`; `lineage_of_entry` lykkes for alle kildens entries; ryd GUC. En parkeret gren får ingen
     entry, og dens records udelukkes fra placement-, persona- og medlemskabssættet (Codex r1 #2).
  3. `write_header_evidence` (run_key = `:header_rule_version`), `write_record_placement` for `machine_ok` + godkendte,
     `write_persona_placement` for records med præcis én `primary`-persona på helposten og accepteret identitet.
  4. Ledger for kildens 576 rækker: `mapped` hvor Task 3's identitetsvej holder, ellers `retained_legacy` med
     `evidence.grund` ∈ {`ingen_placement`, `ingen_nummereret_post`, `parkeret_gren`, `ingen_identitet`}. Andre kilders
     rækker røres ikke.
  5. `ANALYZE` (memory `restore-uden-planner-statistik`); preview + promote memberships som redaktør; assert tom GUC.
  6. Revalidering: én `\gexec`-sætning pr. `stale_published` med `set_config('app.change_set_id','',true)` foran.
  Timeout (Codex r1 #5): ceremonien kører under sin egen `SET LOCAL statement_timeout='15min'` (som 5c-1 i prod);
  prods 2-minuttersgrænse gælder ikke ceremoniens sætninger, kun læserne (Task 9 trin 3).
  7. `PLC_POST_*`: 0 `stale_published` og samme publicerede; uændret eligibility pr. post; ledger-antal = forventede og
     `is_current`; `placement_header_violations(src)=0`; `placement_membership_not_current()=0`; komponenttal =
     `expect_corroborated`/`expect_conflict`; **2018-20-paritet** (hash før = efter over kilde 1's placements,
     medlemskaber, publiceringstilstand og `public_person_source_coordinates`-rækker med `source_id<>src`, plus
     fix_150's fem læsere) **og** koordinat-hashen = `:expect_koord_2018_20` (baseline taget af `maal_trin6d1.sql` i
     fasen `foer`, dvs. før DDL; Codex r1 #7); `PLC_POST_LAESER` (1939-rækkernes hash uændret ved `uaendret`, ellers alle `placement`).

- [x] **Trin 1: Fejlende test** (mini-kilde: to grene, 4 records, 3 publicerede, 1 `unresolved`, 1 parkeret gren, en
  modpart i kilde 1): `$fuld_koersel$` (PLC_OK, 0 stale, ledger 3 mapped + 1 retained, 1 `corroborated`); genkørsel →
  `PLC_PRE_FASE`; identitet ≠ binding → `PLC_PRE_IDENTITY` uden skrivning; mapping mangler en gren → `PLC_PRE_MAPPING`;
  persona med `unresolved` identitet → record-placement, ingen persona-placement, binding stadig `published`;
  bindingens record_key ≠ legacy-rækkens → revalideres alligevel (`$binding_via_record$`);
  `$fortryd_en_post$` (membership-reversal → placements `superseded` via `red_decide_*` → revalidering → ledger) ender
  `published` og 0 stale; `$paritet_2018_20$` (en bevidst ændring af en kilde 1-række får POST til at fejle);
  `$parkeret_gren$` (en parkeret gren med ellers `machine_ok`-records: ingen entry, ingen placement, ledger
  `retained_legacy`/`parkeret_gren`, PLC_OK).
- [x] **Trin 2-4:** kør (fejl) → implementér ceremoni + `maal_trin6d1.sql` + pytest → grønne.
- [x] **Trin 5: Commit** `feat(6d): data-ceremoni for placement og medlemskab pr. kilde`.

### Task 8: Kontrolark for 1939's placements

> **Ændret 2026-11-09 (decisions samme dag):** kortene besvares af Opus mod PDF-sidebilleder i stedet for af
> projektejeren. Implementeret i `placement_kort_1939.py` (job → model → undtagelser → approvals, kontrakt v3 med
> `reviewer`), ikke i `placement_control_sheet.py` (2018-20 uændret). 81 kort: K 20, GK 18, SK 32, SG 6, NK 5.
> Projektejeren får undtagelser + 5 V-kontroller. Status: modul + ceremoni-kontrakt committet; pilot kører.

**Files:** Modify `.claude/skills/daa-extract/scripts/placement_control_sheet.py` + `test_placement_control_sheet.py`.

**Interfaces:**
- `--strata-profil 1939`: strata = første post efter hver gren-, slægtled- og gruppeoverskrift; mindst én af hver
  `record_kind` ≠ person; poster med `usikker`; resten tilfældigt med fast seed; K=20 blinde, ingen forudfyldte svar.
- Kort for `unresolved` (alle årsager fra Task 1) og forudsete `conflict`-komponenter (fra en generalprøve på
  stand-in'en): højst ~30 pr. ark; flere → flere ark. Konfliktkort viser begge udgavers gren/linje og nummer, intet navn
  ud over det, bogen trykker på kortet (memory `kortark-kraever-kontekst-html`: lokal HTML under `~/.private/6d1/`).
- Godkendelige årsager (som fix_150's `uenig:kuld`-liste): `nr_ikke_fortloebende`, `slaegtled_ikke_monoton`,
  `gruppe_flere_familier`. `overskrift_ikke_fundet:*`, `ikke_alignet`, `uden_post` kan ikke godkendes.
- **Svarformat 1939** (Codex r1 #8): stikprøvesvar `<slægtled> <romertal|->` fra PDF'en som i dag. Sammenligningen
  bruger `kuld_label`, når det er et romertal, og ellers guidens romertal (`parsed.guide.value`, kun kontrol, aldrig
  evidens); ingen forudfyldning.
  Konfliktkort registreres (svar → `docs/decisions.md`-backlog), skriver intet i 6d-1 (spec §5.4).
- 2018-20-tilstanden (default) er uændret.

- [ ] **Trin 1-4:** fejlende tests (strata dækker alle `record_kind`; ikke-godkendelig årsag i svarene → afvist; 2018-20
  default byte-ens; render → svar → approvals for en romertalsgruppe og en beskrivelsesgruppe) → implementér → grønne.
- [ ] **Trin 5: Projektejeren** tjekker de 20 mod PDF'en og svarer på kortene (spec §6 pkt. 2-3). Én afvigelse i
  stikprøven stopper og går tilbage til Task 1. Arkenes og token-filernes sha bindes i GO.
- [ ] **Trin 6: Commit** `feat(6d): kontrolark med 1939-strata og konfliktkort`.

### Task 9: Runner, runbook og generalprøve

**Files:**
- Create: `docs/runbooks/trin6d1-prod.md` (form som `docs/runbooks/trin6c3-prod.md`)
- Privat: `~/.private/5ab-overfoersel/33-trin6d1.sh` (kopi af `32-trin6c3.sh` med vinduesvagt; handlinger
  `go|standin|maal|dump|advisors|ddl|data|vindue`), `33-trin6d1-vindue.sql`

- [ ] **Trin 1: Runner:** fastlåste indholdsafledte forventninger (Task 0-8's tal), GO binder DDL-blokkens sha,
  scripts, manifest, mapping-ark, kontrolark og token-filer; afviser ukendte argumenter og kræver `--jeg-mener-det`
  (memory `prod-wrapper-skal-kraeve-flag`); dump-vagt; rækkeaftryk pr. tabel før og efter (vinduesvagt med negativtest).
- [ ] **Trin 2: Runbook:** `go → maal(foer) → dump → advisors → ddl → maal(ddl) → advisors → dump → data → maal(data) →
  vindue`; kendte følger (læserens 1939-rækker efter afgørelse 4); fortrydelse = restore + `db-rls.sql`; manuel
  fortrydelse pr. post som `$fortryd_en_post$`.
- [ ] **Trin 3: Generalprøve** fra operatørens cwd (memory `oev-fra-operatoerens-cwd`) på en frisk kopi af `…_6d1t`
  med `statement_timeout='2min'` (læserne; ceremonien sætter selv 15 min): hele runbooken; rækkediff (kun spec §5's
  tabeller + `change_set`/`change_event`); 2018-20-paritet; maks. tid pr. sætning og samlet varighed fra
  `\timing`-filen — stop, hvis den langsomste sætning × prod/stand-in-forholdet (fra `maal`) > 15 min; `public_person_source_coordinates`
  og personsiden som anon for de tungeste personer (< 3 s med margen, memory `anon-timeout-3s-public-facts`).
- [ ] **Trin 4: Negativer:** forkert GO, manglende flag, gentaget `data` (fase), manipuleret identitet →
  `PLC_PRE_IDENTITY` uden skrivning; ændret mapping-ark efter GO → sha-fejl.
- [ ] **Trin 5: Commit** `docs(6d): runbook for 6d-1 i prod` (runneren committes ikke).

### Task 10: Review, prod og færdigbevis

- [ ] **Trin 1:** Codex `gpt-6.1-sol` over hele grenens diff (eksport uden `work*/`); Opus dømmer; ret kun det godkendte
  efter projektejerens ja; hele CI lokalt igen.
- [ ] **Trin 2:** Spørg om push og draft-PR; CI på PR'en grøn.
- [ ] **Trin 3: Prod** i projektejerens shell efter runbooken (DDL-GO, data-GO); AI'en læser kvitteringer og mål.
- [ ] **Trin 4: Færdigbevis** (spec §8) i `docs/evidensbaseret-genimport/status.md` og changelog: placements (record,
  persona) og de 21 persona-løse med disposition; 0 placements uden overskrift; kort og invariantbrud talt; 0
  `stale_published` før/efter og antal revalideret; ledger `mapped`/`retained_legacy` (576 i alt); komponenter
  `corroborated`/`conflict`/`single` og én `corroborated` vist med begge kilders medlemskab (SQL); 2018-20-hashes
  byte-ens; anon-tider; status-rækken »Placement og membership (5c-1)« for 1939 → `produktionsverificeret`.
- [ ] **Trin 5:** `docs/decisions.md`: ledger via identitet, afledt B6-funktion, afgørelse 4; commit
  `docs(6d): færdigbevis for 6d-1 i prod`.
