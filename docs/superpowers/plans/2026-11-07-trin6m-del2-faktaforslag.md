# Trin 6m del 2: faktaforslag rettet efter bogen — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** De faktaforslag, modellen i del 1 fandt forkert udtrukne (spor A), får en ny version med bogens læsning,
og hvor databasens påstand også er forkert, rettes den og bindes til 1939, alt efter projektejerens klik på A-kortene.

**Architecture:** Én ny RPC `red_ret_forslag` (blok 6m-a) laver en `proposed`-version med en menneskeligt godkendt
værdi og proveniens. Et læse-kun mål-SQL henter de berørte forslag og deres påstande frisk. `faktaforslag_rettelse.py`
klassificerer, viser kort, fletter svar og skriver én ceremoni-transaktion: ny version → (påstandsrettelse) →
afgørelse → binding, med 6c-2's skriveveje (`red_ret_paastand`, `red_decide_interpretation`, scoped binding). Runneren
`30-trin6m.sh` i `~/.private` udvides med del 2's handlinger.

**Tech Stack:** PostgreSQL 17 (plpgsql, psql), Python 3.11 (pytest), HTML-kort som i del 1.

**Spec:** `docs/superpowers/specs/2026-11-05-trin6m-modelgennemgang-1939-design.md` (#299) med ændringer i
`docs/decisions.md` 2026-11-06; del 1-planen `docs/superpowers/plans/2026-11-06-trin6m-del1-modelgennemgang-og-laesertekst.md`.

## Roadmap-kobling

1. **Roadmapmål:** trin 6, færdigbevis (a): 1939's fakta, som læseren ser med kildehenvisning, er bogens.
2. **Værdikædeled:** forslag → afgørelse → rettelse → binding (1939).
3. **Leverancetype:** én generel RPC (kilde-uafhængig, ingen editionsnavn) + kort/ceremoni-værktøj med kilde-id som
   parameter.
4. **Værdi:** forkerte forslag (embeder, godser, uddannelse m.fl.) bæres ikke videre til 6c-3/6d; forkerte påstande
   om navn, fødsel og død rettes i læserfladen, og rettede forslag bindes, så faktaet viser 1939 som kilde.
5. **Færdigbevis:** Task 8 Step 5 (spec §7 pkt. 2-3 for spor A).
6. **Erstatter:** at projektejeren skal finde og rette forkerte forslag i hånden, og at spec §4.4's
   `FORSLAG_FEJL`-rækker ikke har en skrivevej.

## Målt udgangspunkt (del 1's model-svar, `samlet.json` manifest `fc9651e2…`; stand-in `_6m` læse-kun 2026-11-07, kun antal)

241 markerede A-svar: 155 `FORSLAG_FEJL`, 62 `BEGGE`, 19 `TVIVL`, 5 `DB_FEJL`; billedet bekræfter 229, modsiger 12;
239 grupper (2 med to elementer). Fordelt efter forslagets status og art:

| Del | Antal | Hvad del 2 gør |
|---|---|---|
| `FORSLAG_FEJL`, `proposed`, `property` (embede 16, gods 13, militær 5, uddannelse 5, dekoration 5, dåb 5, begravelse 3, rang 2, erhverv 2) | 56 | kort: ny version, forbliver `proposed` (klasse `VERSION`) |
| `FORSLAG_FEJL`/`DB_FEJL`, afgjort (`accepted` 7, `rejected` 28, `unresolved` 6), alle `person.name/birth/death/title` | 41 | kort: genåbn, ret, acceptér og bind (`BIND` eller `RET_OG_BIND`) |
| `FORSLAG_FEJL`/`TVIVL` på `relation` (50), `mention` (11), `event` (5) | 66 | kun rapport til 6c-3/6d (spec §4.1) |
| `BEGGE` | 62 (41 titler) | kun rapport; tallet er input til 6c-3's spørgsmål om et svar »begge rigtige« (spec §5) |
| `TVIVL` på `property` | 16 | kun rapport |

Alle 97 kortforslag er `property` med strengværdi og gældende version. De 7 `accepted` har hver én gyldig binding. Alle
41 afgjorte har præcis én påstand af regelens faktatype for personen, citeret af præcis kilde 1939 (ingen
`PAASTAND_KILDE_DELT`). Ved naiv sammenligning har ca. 22 af de 41 (målt 7/11 på en prod-kopi fra 6/11, før del 1's B-ceremoni, forslag uændret af den: BIND 23) allerede databaseværdi = bogens læsning.

Uden for kortene (kun rapport): 38 tekstrettelser på 14 poster uden narrativ og 1 på et narrativ, der kun må trækkes
tilbage (`legacy-sager.json` `kun_rapport`); 6 grænsefejl (`graensefejl.txt`, til 6d); `k-sager.json` er tom (ingen
kildetekstsager); 1.121 manglende fakta (antal). **De 13 narrativer uden record-binding** har ingen skrivevej:
`red_upsert_narrativ` afviser DAA-kilder under kontrakt v2 (`NARRATIVE_RECORD_REQUIRED`, `schema.sql:6919`), og en
record-binding kræver en post, som 1939 først får med 6d's placements (eksportens `ubundne_paa_en_post=0`). De
flyttes til 6d sammen med de 39 tekstrettelser uden læsertekst: **projektejerens beslutning 2026-11-07** (ændrer
decisions 2026-11-06, der lagde dem i del 2); 6d ejer dem, færdigbevis »de 13 har record-binding og er læst efter
spor B«.

## Global Constraints

- Modellen kører ikke i del 2; kortene viser del 1's svar. Modellens forslag vises, men er ikke forudfyldt; et
  ubesvaret felt betyder ingen handling (spec §4.3.2).
- En værdi er aldrig fri i ceremonien: `FORSLAG_FEJL` skriver `bogens_laesning` fra `samlet.json`, `DB_FEJL` skriver
  forslagets gældende værdi; begge bundet af `manifest_a` og arkets hash.
- Genåbning af et afgjort forslag sker kun ved projektejerens udtrykkelige `F` på netop det kort, og kortet viser den
  tidligere afgørelse (status og grund). Uden `F` står 6c-2's afgørelse (spec §3 pkt. 6). Godkendt af projektejeren
  2026-11-07.
- Ét skriveværdi-begreb: `ny_vaerdi` = `saml_blanktegn_v1` af kildeværdien, beregnet i Python før klassifikation,
  manifest og kort, og identisk med det, RPC'en skriver.
- Relationer, omtaler og hændelser skrives ikke (spec §4.1); `interpretation_party` røres ikke.
- En binding fra 6c-2 må ikke forsvinde stille: en genåbnet `accepted` genbindes i samme transaktion, eller intet
  skrives.
- Ingen prod-skrivning uden GO i projektejerens shell; `--jeg-mener-det`; dump før hver skrivende ceremoni; fryse fra
  dump til godkendelse; fortrydelse fra dumpet.
- `~/.private` og arbejdsmapper committes aldrig; scripts printer kun antal, nøgler og hashes; kort og SQL-filer med
  bogtekst/værdier er 0600 i `~/.private`.
- Prods `statement_timeout` er 2 min; stand-in-tid er ikke prod-tid.
- Push/PR kun efter projektejerens ja pr. gang; PR'er som kladde.
- Implementer-briefs: ingen kommando på `~/.private`, heller ikke `ls`; drop ikke DB'er, list dem.

## Review Focus

1. **Forslaget eller påstanden har ændret sig mellem kort og ceremoni** (ny version, ny afgørelse, rettet påstand),
   eller klassifikationen er kørt om efter kortene. Forventet: `FORSLAG_VERSION_KONFLIKT`, `PAASTAND_DRIFT` (både
   `BIND` og `RET_OG_BIND`) eller `MANIFEST_MISMATCH`; intet skrives. Test i Task 1, Task 3 og øvelse i Task 7 Step 4.
2. **Bogens læsning kan ikke skrives som påstand** (navnet forkortes, dato kan ikke tolkes, målet er bundet af en
   anden fortolkning). Forventet: klassen `SPAERRET` med grund; kortet har ingen svarknap; intet SQL. Test i Task 3.
3. **En genåbnet `accepted` mister sin binding** (den gamle binding er ugyldig, så snart den nye version er
   gældende), også ved et enkeltstående RPC-kald uden for ceremonien. Forventet: genbundet i samme transaktion, ellers
   afviser den udskudte kontrol ved COMMIT (`FORSLAG_BINDING_TABT`). Test i Task 1 (negativ, med rigtig commit) og
   Task 7 Step 3 (positiv).
4. **En `proposed`-række med ikke-tom `decision_evidence` læses som afgjort** af en eksisterende læser. Forventet:
   ingen læser antager det. Tjek i Task 1 Step 1 (grep-liste i ledgeren) og test i `test-forslag-laesning.sql`.
5. **Forbudte svar i arket** (`F` på en rapport- eller `SPAERRET`-række, ukendt ref, andet manifest, samme ref med to
   svar). Forventet: `flet_a` og `anvend_a` afviser. Test i Task 4 og Task 5.

---

### Task 0: Frisk stand-in og målinger (hovedsessionen)

`_6m` er fra før del 1's B-ceremoni og må ikke bruges til tørkørsel.

**Files:** ledger `.superpowers/sdd/2026-11-07-trin6m-del2/progress.md` (gitignoreret).

- [ ] **Step 1:** Projektejeren kører `koer.zsh 29-trin6c2.sh dump-kopi` og `standin <kvittering> 6m2`. Forventet:
  `daa5ab_ddl_standin_<14 cifre>_6m2` (ICU, ANALYZE, `statement_timeout '2min'`).
- [ ] **Step 2:** Mål (læse-kun, kun antal) og skriv i ledgeren: de 97 kortforslag har stadig del 1's version og
  status; antal af de 41 afgjorte, hvor `binding_value_matches(regelens value_kind, bogens læsning, påstand)` er sand;
  antal 1939-bindinger gyldige (`maal_trin6c2.sql`) og `k1_bindinger_hash`; for hver af de 41 målpåstande, om den har en
  gyldig binding fra en anden fortolkningsnøgle (`ALREADY_BOUND_OTHER`-risiko); for hver gyldig egen binding: target =
  `rettelse_maal` (ellers `SPAERRET` `binding_paa_andet_maal`).
- [ ] **Step 3:** Afviger tallene fra tabellen ovenfor, rettes tabellen i samme gren som Task 6.

### Task 1: RPC `red_ret_forslag` (blok 6m-a)

**Files:**
- Modify: `schema.sql` (efter `red_normaliser_forslag`, ca. linje 9518; og `red_decide_interpretation` 9368)
- Modify: `db-migrations.sql` (ny blok `-- ===== trin 6m-a: forslagsversion med menneskelig læsning =====` sidst)
- Modify: `db-verify.sql` (assert-blok 6m-a efter 6c-2b's, ca. 10589)
- Modify: `tests/sql/inspect-5ab-function-parity.sql:40` (tilføj `('public','red_ret_forslag')`,
  `('public','red_decide_interpretation')` og `('private','kontroller_forslag_binding_v1')`; ret sumkommentaren øverst)
- Modify: `.github/workflows/ci.yml:407-408` (forventet antal paritetslinjer 44 → 47, også i fejlteksten)
- Create: `tests/sql/test-forslag-laesning.sql` (skabelon: `tests/sql/test-interpretation-normalisering.sql`)
- Modify: `tests/ci/interpretation-proposal-db.sh:71` (kør den nye test efter normaliseringstesten)

**Interfaces:**
- Produces: `public.red_ret_forslag(p_interpretation_id uuid, p_expected_version integer, p_vaerdi text,
  p_evidence jsonb) RETURNS jsonb` → `{"interpretation_id", "version", "foer_status", "genaabnet": bool}` (ingen
  værdier i kvitteringen). SECURITY DEFINER, `search_path=pg_catalog,public,private`; REVOKE fra
  PUBLIC/anon/authenticated, GRANT EXECUTE til authenticated.
- Regler, i rækkefølge (fejlkoder er kontrakten):
  1. `auth.uid()` og `current_rolle()='redaktion'`, ellers `EVIDENCE_ROLE_FORBIDDEN`.
  2. `p_expected_version ≥ 1`, ellers `EVIDENCE_EXPECTED_VERSION_REQUIRED`; rækken `FOR UPDATE`; findes ikke →
     `EVIDENCE_INTERPRETATION_NOT_FOUND`; version ≠ forventet eller en nyere version findes → `FORSLAG_VERSION_KONFLIKT`.
  3. Status i (`proposed`,`accepted`,`rejected`,`unresolved`), ellers `FORSLAG_STATUS_UGYLDIG`.
  4. `interpretation_kind='property'` og `jsonb_typeof(value)='string'`, ellers `FORSLAG_ART_UGYLDIG`.
  5. `v_ny := private.saml_blanktegn_v1(p_vaerdi)`; tom/NULL → `FORSLAG_VAERDI_TOM`; status `proposed` og
     `v_ny` = gammel værdi → `FORSLAG_UAENDRET` (uændret værdi er kun tilladt som genåbning af et afgjort forslag).
  6. `p_evidence` er et objekt med `basis='menneske-laesning-v1'`, `manifest_a_sha256` og `ark_sha256` (64 hex),
     `ref` (ikke-tom), `svar` i (`FORSLAG_FEJL`,`DB_FEJL`), `billede` i (`bekraefter`,`modsiger`,`ikke_fundet`), ellers
     `FORSLAG_EVIDENS_UGYLDIG`.
  7. `daa.extraction_run_id` peger på en `private.extraction_run` med forslagets `source_id`, ellers
     `FORSLAG_KOERSEL_MANGLER` (samme mønster som `red_normaliser_forslag`).
  8. Ny række: version+1, `status='proposed'`, `derivation_kind='human_judgement'`, `method='menneske-laesning-v1'`,
     `value=to_jsonb(v_ny)`, `supersedes_id`=gammel, **`extraction_run_id = v_run`** (ceremoniens kørsel, ikke den
     gamles), øvrige kolonner kopieret, `decided_*` NULL (påkrævet af `interpretation_proposal_actor_check`),
     `decision_evidence = p_evidence || {laest_af, laest_af_navn, laest_at, foer_status, foer_version, foer_bundet}`
     (aktøren bor i evidensen, fordi en `proposed`-række ikke må bære `decided_*`; `foer_bundet` = den gamle version
     havde en gyldig assertion-binding). Observationerne kopieres som i `red_normaliser_forslag`.
- Udskudt kontrol: `CREATE CONSTRAINT TRIGGER … AFTER INSERT ON private.interpretation DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW` på rækker med `method='menneske-laesning-v1'` og `decision_evidence->>'foer_bundet'='true'`: ved COMMIT
  skal nøglens gældende række være `accepted` med en gyldig assertion-binding (`assertion_binding_current`), ellers
  `FORSLAG_BINDING_TABT`. Et enkeltstående kald kan dermed ikke efterlade et fakta uden sin 1939-binding.
  Triggerfunktionen `private.kontroller_forslag_binding_v1()` er `SECURITY DEFINER` med
  `search_path=pg_catalog,public,private` (triggeren fyrer ved COMMIT som `authenticated`, der ikke kan læse
  `private.*`), REVOKE fra PUBLIC/anon/authenticated/service_role; migrationen bruger `DROP TRIGGER IF EXISTS` +
  `CREATE CONSTRAINT TRIGGER` (en constraint-trigger har ingen `OR REPLACE`).
- `red_decide_interpretation`: `p_evidence->>'basis'='menneske-laesning-v1'` → `EVIDENCE_BASIS_RESERVED:
  menneske-laesning-v1` (som `source_text_revision`, linje 9368), så en afgørelse ikke kan efterligne læsningen.

- [ ] **Step 1:** Grep efter læsere af `decision_evidence` (`schema.sql`, `db-verify.sql`, `tests/`,
  `.claude/skills/daa-extract/scripts/`) og skriv listen i ledgeren med én linje pr. læser: antager den, at `proposed`
  har tom evidens? Gør en det, rettes den i denne task, eller planen stoppes.
- [ ] **Step 2: Skriv testen** `tests/sql/test-forslag-laesning.sql` (fixture som normaliseringstestens): én blok pr.
  fejlkode i reglerne 1-7; en vellykket `proposed` (ny version, `method`, `derivation_kind`, `decided_by IS NULL`,
  evidensens nøgler, observationer kopieret, `extraction_run_id` = GUC'ens kørsel); en genåbning af `rejected` med
  uændret værdi (`genaabnet=true`); en genåbning af en bundet `accepted` alene, kaldt som `authenticated`
  med redaktør-claim → `FORSLAG_BINDING_TABT` (ikke `permission denied`) ved `SET CONSTRAINTS ALL IMMEDIATE` (en BEGIN/ROLLBACK-fixture fyrer aldrig en udskudt trigger); samme genåbning efterfulgt
  af afgørelse og genbinding → ingen fejl; anden kørsel
  med samme forventede version → `FORSLAG_VERSION_KONFLIKT`; `red_decide_interpretation` med reserveret basis afvist;
  en `relation`-fortolkning → `FORSLAG_ART_UGYLDIG`.
- [ ] **Step 3:** Kør mod en frisk skema-base (`tests/ci/interpretation-proposal-db.sh`) → FAIL.
- [ ] **Step 4:** Implementér i `schema.sql` og som idempotent blok i `db-migrations.sql` (hele
  `red_decide_interpretation` gentages i blokken); `db-verify.sql`: funktionen findes, ACL som `red_normaliser_forslag`
  (linje 3019), den reserverede basis afvises, triggeren findes og er `DEFERRABLE INITIALLY DEFERRED`, og
  triggerfunktionen har ingen EXECUTE for anon/authenticated.
- [ ] **Step 5:** Kør testen, `db-verify.sql` og paritets-inspektionen på frisk skema og på en opgraderet base (CI's
  `reimport_legacy_empty_153`-mønster, som allerede migrerer to gange) → PASS, paritet ens, 47 linjer.
- [ ] **Step 6:** Commit: `feat(db): red_ret_forslag — forslagsversion med menneskelig læsning (blok 6m-a)`

### Task 2: Læse-kun mål-SQL

**Files:**
- Create: `.claude/skills/daa-extract/scripts/faktaforslag_maal.sql`
- Test: `.claude/skills/daa-extract/scripts/test_faktaforslag_rettelse.py`

**Interfaces:**
- Input: GUC `daa.faktaforslag_ids` = JSON-array af interpretation-id'er; `-v src`.
- Produces (stdout, ét JSON-dokument): `{"source_id", "forslag": [{"interpretation_id", "interpretation_key",
  "version", "status", "gaeldende_id", "gaeldende_version", "kind", "predicate", "value_text", "value_type", "source_id", "person_id"|null,
  "tidligere": {"status", "grund"|null, "decided_at"|null} (`grund` = `decision_evidence`'s `grund` eller `basis`,
  hvis den findes), "egen_binding": {"promotion_id", "gyldig"}|null,
  "rettelse_maal": {"assertion_id", "forventet", "graenser", "value_kind"}|null, "maal_bundet_af_anden": bool}]}`.
  `rettelse_maal` beregnes som `interpretation_control_rows.sql`'s (`:16-21`), men uanset forslagets status.

- [ ] **Step 1: Skriv testen** `test_maal_sql_er_laese_kun` (mønster som del 1's eksporttest: `BEGIN; SET TRANSACTION
  READ ONLY; … ROLLBACK;`, ingen skrivende nøgleord) og `test_rettelse_maal_som_control_rows(db)` (DB-fixture som
  `test_maal_trin6c2.py`: for et `proposed` forslag giver begge filer samme `rettelse_maal`; for det samme forslag
  afgjort `rejected` giver mål-SQL'en stadig målet).
- [ ] **Step 2:** Kør → FAIL. **Step 3:** Skriv SQL'en. **Step 4:** Kør → PASS; hovedsessionen kører den på Task 0's
  stand-in (output 0600, tæl kun): 97 rækker, 41 med `rettelse_maal`, 7 med gyldig `egen_binding`.
- [ ] **Step 5:** Commit: `feat(6m): læse-kun mål for faktaforslag, der rettes efter bogen`

### Task 3: Klassifikation og manifest

**Files:**
- Create: `.claude/skills/daa-extract/scripts/faktaforslag_rettelse.py`
- Test: `.claude/skills/daa-extract/scripts/test_faktaforslag_rettelse.py`
- Modify: `.github/workflows/ci.yml:156` (tilføj testfilen til pytest-listen)

**Interfaces:**
- Consumes: `samlet.json` (`A`), `noegle.json` (ref → `interpretation_id`, `version`), mål-JSON (Task 2);
  `control_model_v2._p_dato(value_text) -> dict` og navnereglen fra `control_model_v2.b_afvisning`.
- Produces:
  - `class FaktaError(Exception)` med kode som streng.
  - `saml_blanktegn(s: str) -> str` — Python-port af `private.saml_blanktegn_v1` (samme tegnklasse, `schema.sql:9415`);
    `navn_forkortes(gammel: str, ny: str) -> bool` — port af `private.navn_forkortes` (`schema.sql:9423`).
    ICU-`lower()` for ÆØÅ er en kendt begrænsning (som i SQL-kommentaren).
  - `klassificer(a: list[dict], noegle: dict, maal: dict) -> list[dict]` → én række pr. markeret ref:
    `{"ref", "klasse", "grund"|null, "interpretation_id", "version", "status", "ny_vaerdi"|null, "assertion_id"|null,
    "forventet"|null, "p_dato"|null, "ret_paastand": bool}`. `ny_vaerdi` = `saml_blanktegn(kildeværdi)` (FORSLAG_FEJL:
    `bogens_laesning`; DB_FEJL: gældende værdi) beregnes **før** klassen. Klasser:
    - `RAPPORT` — `BEGGE`, `TVIVL`, art ≠ `property`; `UAENDRET` (`proposed` og `ny_vaerdi` = gældende værdi);
      `ALLEREDE_BUNDET` (gyldig `egen_binding` og `ny_vaerdi` matcher målet).
    - `DRIFT` — nøglens `interpretation_id` ≠ målets `gaeldende_id` (kun rapport; »ændret siden gennemgangen«).
    - `VERSION` — `FORSLAG_FEJL` på `proposed`.
    - `BIND` — afgjort; `ny_vaerdi` matcher målpåstanden efter `binding_value_matches`' regel (lower, btrim, NFC);
      `ret_paastand=false`; `forventet` fra målet (til drift-kontrollen).
    - `RET_OG_BIND` — afgjort, matcher ikke; `ret_paastand=true`, `forventet` og (dato) `p_dato` fra målet.
    - `SPAERRET` — afgjort uden `rettelse_maal`, `maal_bundet_af_anden`, `navn_forkortes(målets værdi, ny_vaerdi)`,
      eller datoen giver ingen grænser (`control_model_v2.dato_uden_graenser`); `grund` = koden.
  - `manifest_a(klasser: list[dict], a: list[dict]) -> str` — sha256 af kanonisk JSON over hver klasserække (alle
    felter ovenfor) forenet med A-rækkens `(svar, felt, vaerdi, bogens_laesning, billede)`, sorteret på ref. Køres
    `klasse-a` om efter kortene, ændres hashen, og ceremonien afviser (`MANIFEST_MISMATCH`).
  - CLI: `faktaforslag_rettelse.py klassificer --ud D` (mål kun fra `D/maal.json`; et `--maal` skal være netop den fil,
    ellers `MAAL_STI`) → `D/a-klasser.json` (0600); printer
    `FF_KLASSE_OK version= bind= ret_og_bind= spaerret= drift= rapport= manifest_a=<sha8>`. Hver klasse-række bærer
    kortets kontekst: `post`, `record_key`, `tekst_sha256` (noeglen), `sider` (bidden) og `tidligere` (status, grund,
    decided_at); `kort` tager den tidligere afgørelse derfra og afviser en post, hvis tekst, navn eller sider afviger
    (`KONTEKST_AFVIGER`). Sidebilledernes PNG-indhold er ikke hash-bundet (afledt deterministisk af PDF'en).

- [ ] **Step 1: Skriv de fejlende tests** (syntetisk fixture, ingen rigtige navne):
  - `test_manifest_a_stabil_og_foelsom` — samme input → samme sha; ændret `bogens_laesning`, `version`, klasse eller
    `forventet` → anden.
  - `test_saml_blanktegn_som_sql` — dobbelt mellemrum, linjeskift, NBSP (U+00A0), U+202F → ét mellemrum, trimmet.
  - `test_uaendret_og_allerede_bundet_er_rapport` — `proposed` med `bogens_laesning` »Carl  Hansen« og værdi »Carl
    Hansen« → `RAPPORT`/`UAENDRET`; bundet `accepted`, der allerede matcher → `RAPPORT`/`ALLEREDE_BUNDET`.
  - `test_relation_og_begge_er_rapport` — `relation.marriage` med `FORSLAG_FEJL` og `BEGGE` på `person.title` → `RAPPORT`.
  - `test_proposed_bliver_version` / `test_afgjort_lig_bliver_bind` (»Hansen « mod »hansen«) /
    `test_afgjort_ulig_bliver_ret_og_bind` (med `forventet` og `p_dato` for `person.death`).
  - `test_db_fejl_bruger_gaeldende_vaerdi` — `ny_vaerdi` = forslagets værdi, ikke `bogens_laesning`.
  - `test_spaerret_grunde` — uden mål, mål bundet af anden, navn forkortes, dato uden grænser → `SPAERRET` med fire
    forskellige grunde.
  - `test_drift_naar_gaeldende_id_aendret`.
  - `test_cli_printer_kun_tal` — stdout matcher `^FF_KLASSE_OK( [a-z_]+=[0-9a-f]+)+$`.
- [ ] **Step 2:** Kør → FAIL. **Step 3:** Implementér. **Step 4:** Kør → PASS.
- [ ] **Step 5:** Commit: `feat(6m): klassifikation af faktaforslag mod bogen og databasen`

### Task 4: A-kort og flet

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/faktaforslag_rettelse.py`
- Create: `.claude/skills/daa-extract/scripts/faktaforslag_kort.html` (mønster: `laesertekst_kort.html`)
- Test: `.claude/skills/daa-extract/scripts/test_faktaforslag_rettelse.py`

**Interfaces:**
- Produces:
  - `byg_kort(klasser: list, samlet: dict, bidder: list, maal: dict) -> list[dict]` — kort med svarknapper kun for
    `RET_OG_BIND` (ca. 15-19 rækker; målt 7/11 på en prod-kopi fra 6/11, før del 1's B-ceremoni, forslag uændret af den: 14, SPÆRRET 4; ingen gruppesvar). Rækken viser postens tekstuddrag, sidebilledets sti, feltet,
    forslagets værdi, bogens læsning, databasens værdi, tidligere afgørelse (status + grund), modellens grund og
    billedstøtte, og at `F` retter databasens værdi. `VERSION` og `BIND` står i en oversigt uden knapper (antal pr.
    felt) med teksten »omfattet af det samlede F (projektejeren 2026-11-07)«.
  - `samlet_f(klasser: list[dict], manifest_a: str) -> dict` — projektejerens samlede beslutning som svarfil (som
    del 1's side 1001): `{"manifest_a", "side": 1001, "kilde": "projektejeren 2026-11-07: samlet F på VERSION og BIND",
    "svar": {ref: "F"}}` for præcis rækkerne i `VERSION ∪ BIND`. Runneren skriver den først, når projektejeren har set
    `FF_KLASSE_OK`-tallene og sagt ja.
  - `render(kort, manifest_a: str, pr_side: int = 40) -> list[str]`.
  - `flet_a(klasser: list[dict], manifest_a: str, svarfiler: list[dict]) -> str` — kræver `manifest_a(klasser, …)` =
    svarfilernes manifest; tilladte refs og klasser læses af `klasser`; ark: `# manifest_a <sha256>` og én linje pr. ref
    `A <ref> : F|N|_` (F = gør det, kortet beskriver; N = modellen tager fejl, intet skrives; _ = ubesvaret, intet
    skrives). Svarbare klasser: `VERSION`, `BIND` (kun via den samlede svarfil) og `RET_OG_BIND` (kun via kortene).
  - CLI: `kort --ud D` → `D/kort-a/kort-<n>.html`; `samlet-f --ud D` → `D/svar-a-1001.json` (0600); `flet --ud D SVAR...` → `D/ark-a.txt` (afviser eksisterende ark:
    `ARK_FINDES`) og en uændret kopi af hver svarfil i `D/svar-a-<side>.json` (0600; en anden fil for samme side:
    `SVAR_SIDE_DUBLET`; et navn, der kun afviger i versaler, fx del 1's `svar-A-<k>.json`: `SVAR_NAVN_KOLLISION`); kun
    antal og hashes.
- Kortvejledning (fast tekst øverst): hvad F, N og tomt betyder; at F på et afgjort forslag genåbner 6c-2's afgørelse;
  »er du i tvivl, så lad den stå tom«; `RAPPORT`/`SPAERRET`/`DRIFT` står i en sektion uden knapper med forklaringen
  »gives videre til 6c-3/6d«.

- [ ] **Step 1: Skriv de fejlende tests:**
  - `test_kort_er_ikke_forudfyldt` — ingen `checked`/`selected`.
  - `test_kort_viser_tidligere_afgoerelse` — en `RET_OG_BIND` fra `rejected` viser »afvist« og grunden.
  - `test_rapport_og_spaerret_har_ingen_knapper`.
  - `test_vejledning_definerer_hvert_svar`.
  - `test_flet_afviser` — andet manifest → `MANIFEST_MISMATCH`; ukendt ref → `SVAR_UKENDT_REF`; F på `RAPPORT`,
    `SPAERRET` eller `DRIFT` → `SVAR_IKKE_TILLADT`; ugyldigt token → `SVAR_UGYLDIGT`; samme ref med to svar →
    `SVAR_KONFLIKT`.
  - `test_flet_ark_findes`.
  - `test_kun_ret_og_bind_har_knapper` — `VERSION`- og `BIND`-rækker har ingen knapper og står i oversigten.
  - `test_samlet_f_daekker_praecis_version_og_bind` — svarfilen har F for hver `VERSION`/`BIND`-ref og ingen andre;
    flettet med kortsvar giver arket F for dem, kortets svar for `RET_OG_BIND`, `_` for ubesvarede `RET_OG_BIND`.
  - `test_flet_afviser_samlet_svar_paa_ret_og_bind` — en side-1001-fil med en `RET_OG_BIND`-ref → `SVAR_IKKE_TILLADT`;
    et kortsvar på en `VERSION`/`BIND`-ref → `SVAR_IKKE_TILLADT`.
- [ ] **Step 2:** Kør → FAIL. **Step 3:** Implementér (render/flet-mønster fra `laesertekst_rettelse.py`). **Step 4:**
  Kør → PASS.
- [ ] **Step 5:** Commit: `feat(6m): A-kort og flet til projektejerens svar på faktaforslag`

### Task 5: Ceremoniens SQL og verifikation

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/faktaforslag_rettelse.py`
- Test: `.claude/skills/daa-extract/scripts/test_faktaforslag_rettelse.py`

**Interfaces:**
- Produces:
  - `anvend_a(klasser: list, samlet: dict, noegle: dict, ark_tekst: str) -> dict` — genberegner `manifest_a` og kræver
    arkets; samme afvisninger som `flet_a`. → `{"version": [...], "bind": [...], "ret_og_bind": [...]}` med kun F-rækker.
  - `sql_a(anvendt: dict, *, source_id: int, manifest_a: str, ark_sha256: str) -> str` — én transaktion:
    1. `\set ON_ERROR_STOP on`, `BEGIN`, `standard_conforming_strings=on`, aktør via `request.jwt.claim.sub` (`:'actor'`).
    2. Kildeværn: hvert forslag har `source_id=src`, er gældende og har arkets version, ellers `FORSLAG_DRIFT`; og én
       DO-blok for alle `BIND ∪ RET_OG_BIND`: målpåstandens `vaerdi_tekst`, `date_raw`, valgte påstand og
       `citation_sources` = `forventet`, ellers `PAASTAND_DRIFT`.
    3. Én `private.extraction_run` (ejerrollen): `run_key='menneske-laesning-v1:'||<ark_sha256>`,
       `input_sha256=<manifest_a>`, `manifest={antal, manifest_a, ark}`; `daa.extraction_run_id` sat.
    4. `SET LOCAL ROLE authenticated`; pr. F-række én DO-blok med `set_config('app.change_set_id','',true)` før hvert
       RPC-kald: `red_ret_forslag` → (kun `ret_og_bind`) `red_ret_paastand(assertion, forventet, 'bogen_har_ret',
       ny_id, p_dato)` → (kun `bind`/`ret_og_bind`) `red_decide_interpretation(ny_id, version+1, 'accepted',
       {basis:'kort-6m-a', ref, ark_sha256})`.
    5. Binding af `bind ∪ ret_og_bind` med 6c-2's scoped-mønster (`daa.transfer_scope`, `TARGETS_SCOPED_SQL`,
       preview eligible, `red_promote_interpretations_batch`), men beviset og målkoblingen nøgles på
       `interpretation_key`, **ikke** `supersedes_id`: den accepterede række ligger to versioner efter kortets, og
       mellemversionens id skabes først i transaktionen. Hver nøgles mål = rækkens `assertion_id`; tælling med
       `assertion_binding_current` = antal.
    6. Verifikation før `COMMIT`: nye versioner = antal F; påstandsværdier = `ny_vaerdi` for `ret_og_bind`; 1939's
       gyldige bindinger = før − |accepted blandt F| + |bind ∪ ret_og_bind|; `k1_bindinger_hash` = Task 0's.
    7. `COMMIT`; `\echo 'T6M_APPLY_A_OK versioner= rettelser= afgoerelser= bundet= sha256='`.
  - `verify_a_sql(anvendt) -> str` — læse-kun efterkontrol af samme tal og `vejb` som 6c-2.
  - CLI: `sql --ud D` → `D/apply-a.sql`, `D/verify-a.sql`, `D/rapport-a.json` (alle ikke-svarbare og N-rækker:
    ref, klasse, grund, felt; ingen værdier); fletter først alle `D/svar-a-*.json` igen og kræver arket byte for byte
    (`ARK_AFVIGER`, intet skrevet); printer `FF_SQL_OK version= bind= ret_og_bind= svar_sha256= sha256=`
    (`svar_sha256` = sha256 over `shasum -a 256`-linjerne for svarfilerne sorteret på navn; til GO-koden).

- [ ] **Step 1: Skriv de fejlende tests:**
  - `test_sql_a_raekkefoelge` — for en `ret_og_bind`: `red_ret_forslag` før `red_ret_paastand` før
    `red_decide_interpretation`; for `version` kun `red_ret_forslag`.
  - `test_sql_a_nulstiller_change_set_foer_hvert_kald` — antal nulstillinger = antal RPC-kald.
  - `test_sql_a_citerer_apostrof` — `O'Neill` → `'O''Neill'`.
  - `test_sql_a_binder_genaabnet_accepted` — en `accepted` i `bind` står i bindingsscope, og binding-tællingen
    forventer den.
  - `test_sql_a_bruger_ikke_supersedes_id` — den genererede SQL indeholder ikke `supersedes_id`.
  - `test_sql_a_drift_tjekker_bind_og_ret_og_bind` — drift-blokken nævner hver `BIND`- og `RET_OG_BIND`-påstand.
  - `test_anvend_afviser_aendret_samlet` — `bogens_laesning` ændret efter flet → `MANIFEST_MISMATCH`.
  - `test_n_og_tomt_skrives_ikke`.
  - `test_rapport_indeholder_ingen_vaerdier` — `rapport-a.json` har ingen `vaerdi`/`bogens_laesning`-nøgler.
- [ ] **Step 2:** Kør → FAIL. **Step 3:** Implementér (genbrug kun `control_model_v2._jlit`, `_uuid`, `RESET`,
  `ANALYZE_SQL`, `TARGETS_SCOPED_SQL`; ikke `sql_v2`'s bindingsbevis). **Step 4:** Kør → PASS.
- [ ] **Step 5:** Commit: `feat(6m): ceremoni-SQL for faktaforslag — version, rettelse, afgørelse, binding`

### Task 6: Rapport og beslutninger

**Files:**
- Modify: `docs/decisions.md` (BESLUTTET 2026-11-07: del 2's skriveveje)
- Modify: `docs/evidensbaseret-genimport/status.md`

- [ ] **Step 1:** Indførslen: `red_ret_forslag` som generel skrivevej for en menneskeligt godkendt forslagsværdi
  (med udskudt bindingskontrol); genåbning af afgjorte kun ved udtrykkeligt F (projektejeren 2026-11-07),
  som et samlet F for `VERSION`/`BIND` (svarfil side 1001) og kort for `RET_OG_BIND`;
  relationer/omtaler/hændelser, `BEGGE` (62, heraf 41 titler) og `TVIVL` registreres til 6c-3/6d; de 13 ubundne
  narrativer og de 39 tekstrettelser uden læsertekst flyttes til 6d efter projektejerens beslutning 2026-11-07 (målt:
  ingen skrivevej uden placements); 6d ejer dem, færdigbevis »de 13 har record-binding og er læst efter spor B«;
  kun antal.
- [ ] **Step 2:** status.md: 6m del 2 i gang.
- [ ] **Step 3:** Commit: `docs(decisions): trin 6m del 2 — skriveveje for faktaforslag`

### Task 7: Runner og øvelse på stand-in (hovedsessionen)

**Files:** `~/.private/5ab-overfoersel/30-trin6m.sh` (0600; backup `.foer-del2`); runbook `docs/runbooks/trin6m-del2-prod.md`.

- [ ] **Step 1:** Nye handlinger: `maal-a` (læse-kun), `klasse-a`, `kort-a`, `flet-a`, `sql-a`, `dump`, `go-ddl`,
  `apply-ddl` (blok 6m-a + `db-verify.sql`), `go-a`, `apply-a` (`--jeg-mener-det --go`), `verify-a`, `fortryd`. GO-koden
  binder commit, blok-sha (DDL) eller mål-, klasse-, ark- og SQL-sha (A). Kun antal og hashes ud.
- [ ] **Step 2:** Øvelse fra `~/.private` (operatørens cwd) på Task 0's stand-in: `apply-ddl` → verify grøn →
  `get_advisors`-ækvivalent (lint-forespørgslen fra memory `koer-get-advisors-efter-ddl`) uden nye fund.
- [ ] **Step 3:** Syntetisk ark med F på alle svarbare (inkl. alle 7 `accepted`): `apply-a` → `verify-a` grøn, tal som
  Task 5 Step 6; `public_person_facts` for de berørte personer viser 1939 som kilde på de bundne fakta; `fortryd` →
  forslag, påstande og bindinger som før (mængde-sammenligning af id'er, ikke kun antal).
- [ ] **Step 4:** Drift-øvelse: ret én `RET_OG_BIND`- og én `BIND`-målpåstand på stand-in'en efter `sql-a` → `apply-a`
  fejler med `PAASTAND_DRIFT`, og intet er skrevet (rollback); afgør ét forslag efter `sql-a` → `FORSLAG_DRIFT`;
  kør `klasse-a` om efter `flet-a` → `MANIFEST_MISMATCH`.
- [ ] **Step 5:** Timeout-gate: længste kald og hele transaktionen × 6c-2's prod/stand-in-forhold < 60 s.
- [ ] **Step 6:** Runbook (rækkefølge, forventede linjer, fortrydelse, fryse) og commit:
  `docs(runbook): trin 6m del 2 i prod`

### Task 8: Prod — DDL, kort, ceremoni og færdigbevis

- [ ] **Step 1:** Codex-runde på diffen før prod (B13: `gpt-6.1-sol`, Opus dømmer hvert fund). PR som kladde efter
  projektejerens ja; projektejeren merger; tjek `git merge-base --is-ancestor <head> main` efter merge.
- [ ] **Step 2:** `dump` → `go-ddl` → projektejeren kører `apply-ddl` → verify grøn → advisors.
- [ ] **Step 3:** `maal-a` (prod, læse-kun) → `klasse-a`; projektejeren ser tallene (`version=`, `bind=`,
  `ret_og_bind=`) og bekræfter det samlede F → `samlet-f` → `kort-a`; projektejeren svarer på `RET_OG_BIND`-kortene →
  `flet-a` → `sql-a` → øvelse på en frisk stand-in med det rigtige ark (Task 7 Step 3).
- [ ] **Step 4:** `dump` → `go-a` → projektejeren kører `apply-a` → `verify-a` grøn → ledger; frysning ophæves.
- [ ] **Step 5 (færdigbevis, spec §7 for spor A):** prod-antal nye forslagsversioner = arkets F; påstandsrettelser =
  F i `RET_OG_BIND`; afgørelser og nye gyldige bindinger = F i `BIND ∪ RET_OG_BIND`; 0 tabte bindinger
  (bindingstallet som Task 5 Step 6); `k1_bindinger_hash` uændret; `vejb` grøn; projektejeren vælger tre rettede fakta
  og ser dem med 1939-kildehenvisning i læserfladen.

---

## Efter planen

B13's plan-runde er kørt (nedenfor). Udførelse kræver projektejerens godkendelse af planen og valg af
udførelsesform.

**Review-runde 1 (2026-11-07):** Codex `gpt-6.1-sol` gav NO-GO med 8 fund + 2 noter; Opus dømte 5 nødvendige
(bindingstab ved enkeltkald, CI-paritet 44→47 inkl. triggerfunktionen, `extraction_run_id`, bindingsbevis over to versioner, 13 narrativer som
projektejerens beslutning) og 5 forenklede (manifest binder klasse og mål, drift-tjek for `BIND`, ét
skriveværdi-begreb, `flet_a`'s input, `ALLEREDE_BUNDET`); alle indarbejdet efter projektejerens ja. Næste Codex-runde
er på diffen før prod (Task 8 Step 1).

## Projektejerens svar (2026-11-07)

1. Et `F` må genåbne en afgørelse fra 6c-2 (41 forslag: 7 accepterede, 28 afviste, 6 `unresolved`); kortet viser
   den tidligere afgørelse, og uden F står den.
2. De 13 ubundne narrativer og de 39 tekstrettelser uden læsertekst flyttes til 6d.
3. Fuld del 2 (ny RPC), ikke en minimal del 2 uden DDL. Samlet F på `VERSION` (56) og `BIND` (ca. 22; målt 7/11: 23): ingen af dem
   ændrer en værdi, læseren ser (kun forslaget eller kildehenvisningen), og alle 97 er billedbekræftede. Projektejeren
   ser kun kortene for `RET_OG_BIND` (ca. 15-19; målt 7/11: 14), hvor databasens værdi ændres. Bekræftes mod de faktiske tal i
   Task 8 Step 3, før svarfilen skrives.
