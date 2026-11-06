# Trin 6m del 1: modelgennemgang af 1939 og rettelse af læserteksten — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** En model gennemgår alle 592 af 1939's poster (spor B: tekst mod sidebillede; spor A: forslag mod bog) i én
kørsel, og projektejerens godkendte rettelser af *læserteksten* (narrativet) kommer i prod gennem én ceremoni.

**Architecture:** Et læse-kun eksport-SQL giver ét JSON-dokument pr. udgave. `model_gennemgang.py` bygger filtrerede
modelbidder med sidebilleder, briefs og en fail-closed sammenlægning af modellens svar (spor A og B gemmes begge).
`laesertekst_rettelse.py` viser spor B's rettelser grupperet på kort, fletter projektejerens svar til et hash-bundet
ark og skriver ceremoniens SQL: `red_revider_publiceret_person_narrative_record` pr. post med `expected_state_sha256`
fra eksporten. Runneren `30-trin6m.sh` i `~/.private` kører det hele som 6c-2.

**Tech Stack:** Python 3.11 (pytest), PostgreSQL 17 (psql, læse-kun eksport), poppler (`pdftoppm`/`pdftotext`),
Opus-underagenter i Claude Code.

**Spec:** `docs/superpowers/specs/2026-11-05-trin6m-modelgennemgang-1939-design.md` (merget #299, main `15933347`).

**Opdeling (*mit valg*, rådgiverens forslag):** specen er delt i to planer. **Del 1 (denne):** værktøjet, hele
modelkørslen (A og B), projektejerens B-kort og ceremonien for læsertekst. **Del 2 (senere plan):** A-kortene, ny DDL
for en forslagsversion med menneskelig læsning (specens §4.4-hul), flytning af afgørelse og binding, og de
kildetekstrevisioner, projektejeren vælger sag for sag (svaret `K` i del 1). Del 2 planlægges ud fra del 1's tal.

## Global Constraints

- Model-input kun efter filteret: en person med databaseværdier medtages kun, hvis databasen har en død for personen
  eller et fødselsår til og med 1939; ellers udelades personen, og et forslag om netop den person går til
  projektejeren uden modelforslag (spec §4.2.1).
- Modellen får ingen interne id'er, kun ref'er; nøglen bliver i `~/.private` (§4.2.2).
- Modellen læser kun inputfilerne og skriver kun svarfilerne (0600 i `~/.private`); dens svar til sessionen er kun
  antal. Modellen skriver aldrig i et ark eller i databasen (§4.2.3).
- Opus til begge spor; Fable aldrig i en workflow (§4.2.4). Mekanisme: underagenter i Claude Code (§8.7).
- Sidebilledet er facit; en rettelse uden billedstøtte meldes som `TVIVL` (§4.1).
- Modellens forslag vises, men er ikke forudfyldt; et ubesvaret felt betyder ingen handling (§4.3.2).
- Over 300 markerede elementer efter gruppering: stop og vend tilbage til projektejeren med tallene (§4.3.3).
- Grænse til nabopost rettes ikke; parkeres med forstavelsen `GRÆNSEFEJL: ` til 6d (§4.1 B pkt. 3).
- Ingen prod-skrivning uden GO i projektejerens shell; ingen push/merge uden godkendelse; PR'er som kladde (§6).
- Arbejdsmapper og `~/.private` committes aldrig; scripts printer kun antal, nøgler og hashes (§6).
- Prods `statement_timeout` er 2 min; stand-in-tid er ikke prod-tid (§6).
- Fryse: ingen redigering af 1939-narrativer i prod fra eksporten, til ceremonien er godkendt (§6).
- Implementer-briefs: ingen kommando på `~/.private`, heller ikke `ls`; drop ikke DB'er, list dem.

## Review Focus

1. **Narrativet er ændret i prod efter eksporten.** Forventet: ceremonien skriver intet (RPC'en kaster
   `NARRATIVE_RECORD_STATE_STALE`, transaktionen ruller tilbage). Test i Task 6 (`test_sql_b_bruger_eksportens_state_sha`).
2. **En rettelses `fra`-tekst findes 0 eller flere gange i narrativet, eller to godkendte rettelser overlapper.**
   Forventet: afvist både ved sammenlægning af modelsvar og ved anvendelse af arket. Test i Task 4 og Task 6.
3. **Postens tekst står ikke på sidebillederne** (kort post, side Calamari mangler). Forventet: modellen svarer
   `TVIVL`, kortet viser det, intet anvendes uden projektejerens klik. Test i Task 4 (`test_saml_ikke_fundet_kraever_tvivl`).
4. **Narrativ uden record-binding eller med blokeret publiceringspolitik** (13 uden binding målt på `_slut2`). Forventet:
   posten går til modellen, men kortet viser »kun rapport« uden svarknapper, og SQL'en rører den ikke. Test i Task 5 og 6.
5. **Gruppesvar med undtagelse.** Forventet: gruppens svar gælder alle elementer undtagen dem, projektejeren har sat
   anderledes; `K` registreres, men skrives ikke i del 1. Test i Task 5 (`test_flet_gruppesvar_med_undtagelse`).

---

### Task 0: Frisk stand-in af prod i tilstand d og målinger (hovedsessionen)

`_slut2` er fra før den rigtige ceremoni 4 og må ikke bruges til tal eller tørkørsel.

**Files:** ingen i repoet; ledger `.superpowers/sdd/2026-11-06-trin6m-del1/progress.md` (gitignoreret).

- [ ] **Step 1:** Projektejeren kører (eller tillader) `koer.zsh 29-trin6c2.sh dump-kopi`; derefter
  `koer.zsh 29-trin6c2.sh standin <kvittering> 6m`. Forventet: `daa5ab_ddl_standin_<14 cifre>_6m`, `maal` = tilstand d.
- [ ] **Step 2:** Mål på stand-in'en (kun antal) og skriv i ledgeren: source records (1939), narrativer pr.
  `narrative_record_publication.status`, narrativer uden binding, `eligibility_status`/`blocking_reason` fra
  `public.red_person_narrative_records` pr. 1939-person (antal pr. værdi), forslag pr. status, poster uden narrativ, og
  hvor mange narrativer er tegn-identiske med postens OCR-vindue (`persona_kort.vindue(...)["post"]`).
- [ ] **Step 3:** Ret spec §2's tabel, hvis tallene afviger, i samme gren som Task 1.

### Task 1: Roadmap-linje og status

**Files:**
- Modify: `docs/decisions.md` (ny BESLUTTET-indførsel 2026-11-06)
- Modify: `docs/evidensbaseret-genimport/status.md` (6c-2 i prod afsluttet; 6m del 1 i gang)

- [ ] **Step 1:** Skriv indførslen: »Trin 6m (modelgennemgang af 1939) indsættes mellem 6c-2 og 6c-3; spec #299;
  vej (a): læsertekst rettes, kildetekst kun sag for sag; del 1/del 2 som i planen.«
- [ ] **Step 2:** Opdatér status.md: 6c-2 i prod 2026-11-06 (tilstand d, 1106 bundne, 83 rettelser, kort 122
  `unresolved`); næste 6m del 1.
- [ ] **Step 3:** Commit: `docs(decisions): trin 6m mellem 6c-2 og 6c-3; status efter 6c-2`

### Task 2: Læse-kun eksport

**Files:**
- Create: `.claude/skills/daa-extract/scripts/model_gennemgang_eksport.sql`
- Test: `.claude/skills/daa-extract/scripts/test_model_gennemgang.py`

**Interfaces:**
- Produces: ét JSON-dokument på stdout:
  `{"udgave": str, "source_id": int, "poster": [{"record_key": str, "narrativ": {"person_id": int, "narrative_id": int,
  "tekst": str, "status": str, "blokeret": str|null, "state_sha256": str} | null, "placering": [samme form som
  persona_kort_kontekst.sql's plac], "forslag": [{"interpretation_id": str, "version": int, "predicate": str,
  "value_text": str, "status": str, "persona_id": str, "person_id": int|null}]}], "personer": {"<person_id>":
  {"navn","fuldt_navn","foedt","doed","titel"}}}`. Variabel `:src` (kilde-id).
- `state_sha256` og `blokeret` kommer fra `private.narrative_record_state(person_id, :src, record_key, true)` og
  `public.red_person_narrative_records`' `blocking_reason`; `person_id` på forslaget er personaens accepterede identitet.

- [ ] **Step 1: Skriv testen** `test_eksport_sql_er_laese_kun`: filen starter med `BEGIN;` + `SET TRANSACTION READ
  ONLY;`, slutter med `ROLLBACK;`, indeholder ingen af `INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|GRANT` (som
  `test_persona_kort.test_kontekst_sql_er_laese_kun`), og bruger `:'src'`/`:src`.
- [ ] **Step 2:** `python3 -m pytest .claude/skills/daa-extract/scripts/test_model_gennemgang.py -q` → FAIL (filen findes ikke).
- [ ] **Step 3:** Skriv SQL'en. Placering og stykker som i `persona_kort_kontekst.sql` (occ/plac), men pr. post (via
  `source_record_anchor_current` `accepted`) og for alle forslag i `private.interpretation_current` med `source_id=:src`
  (alle statusser).
- [ ] **Step 4:** Testen → PASS. Kør på stand-in'en fra Task 0 (hovedsessionen, output til 0600-fil i `~/.private`,
  tæl kun): `poster`=592, forslag i alt = Task 0's tal, narrativer = Task 0's tal.
- [ ] **Step 5:** Commit: `feat(6m): læse-kun eksport af 1939's poster, narrativer og forslag`

### Task 3: Modelinput med filter og sidebilleder

Generaliserer `~/.private/5ab-overfoersel/modelforslag.py` (hovedsessionen giver implementeren `sikker`- og
sidevalgslogikken i briefen; implementeren læser ikke `~/.private`).

**Files:**
- Create: `.claude/skills/daa-extract/scripts/model_gennemgang.py`
- Test: `.claude/skills/daa-extract/scripts/test_model_gennemgang.py` (syntetisk fixture, ingen rigtige navne)

**Interfaces:**
- Consumes: eksporten fra Task 2; `persona_kort.vindue(placering) -> dict|None`.
- Produces:
  - `class GennemgangError(Exception)` (koder som strenge, fx `"SVAR_DUBLET"`).
  - `sikker(person: dict) -> bool` — død ikke-tom, eller største 4-cifrede år i `foedt` ≤ 1939.
  - `vaelg_sider(occ_sider: list[int], post_ord: set[str], sideord: Callable[[int], set[str]], almindelige: set[str],
    max_sider: int = 4) -> list[int]` — altid forekomstsiderne; ±1 naboside hvis ≥15 % af postens særord står i
    sidens tekstlag; højst 4, sorteret.
  - `render_side(pdf: Path, side: int, ud: Path) -> Path` — `pdftoppm -r 150 -png -singlefile`, fil 0600; stubbes i tests.
  - `byg_input(eksport: dict, *, bid: int = 25) -> tuple[list[dict], dict]` — bidder og nøgle. Ref'er: post `p<n>`,
    forslag `p<n>-f<i>`. Bid: `{"udgave", "poster": [{"post", "tekst" (narrativets tekst, ellers OCR-vinduets post),
    "tekstkilde": "narrativ"|"ocr", "ocr_vindue", "sider", "kun_rapport": bool, "forslag": [{"ref", "felt",
    "vaerdi", "databasen" (kun navn/titel/fødsel/død, bundet og sikker), "status"}], "manuelle_forslag": int}]}`.
    Nøgle: `{ref: {"type": "post", "record_key", "narrative_id", "state_sha256"} | {"type": "forslag",
    "interpretation_id", "version"}}`.
  - CLI: `model_gennemgang.py input --eksport F --pdf P --ud D [--bid 25]` → `D/input-<k>.json`, `D/noegle.json`,
    `D/sider/s<p>.png` (alle 0600). Printer kun `MG_INPUT_OK poster= bidder= forslag= manuelle= sider= uden_billede=`.

- [ ] **Step 1: Skriv de fejlende tests:**
  - `test_sikker_doed_eller_foedt_senest_1939` — `{"doed":"x"}`→True; `{"foedt":"f. 1936"}`→True;
    `{"foedt":"1940"}`→False; `{}`→False.
  - `test_forslag_om_usikker_person_gaar_uden_modelforslag` — forslaget optræder ikke i bidden; `manuelle_forslag`=1.
  - `test_databasevaerdi_kun_for_kontrolfelter_og_bundne` — sted-forslag har ingen `databasen`; ubundet navn heller ikke.
  - `test_ingen_interne_id_i_bidder` — ingen uuid (regex fra `control_model_v2.UUID`) og intet `person_id` i bid-JSON.
  - `test_narrativ_uden_binding_er_kun_rapport` — `narrativ=None` eller `blokeret` ikke-null → `kun_rapport=True`.
  - `test_vaelg_sider_altid_forekomst_og_belagt_nabo` — stub `sideord`; nabo med 10 % udelades, med 20 % tages; max 4.
  - `test_cli_printer_kun_tal` — stdout matcher `^MG_INPUT_OK( [a-z_]+=[0-9]+)+$`, `render_side` monkeypatchet.
- [ ] **Step 2:** Kør → FAIL.
- [ ] **Step 3:** Implementér.
- [ ] **Step 4:** Kør → PASS.
- [ ] **Step 5:** Commit: `feat(6m): modelinput i bidder med filter, ref'er og sidebilleder`

### Task 4: Brief-skabelon og fail-closed sammenlægning

**Files:**
- Create: `.claude/skills/daa-extract/scripts/model_gennemgang_brief.md` (skabelon med `{INPUT}`, `{SVAR_A}`, `{SVAR_B}`)
- Modify: `.claude/skills/daa-extract/scripts/model_gennemgang.py`
- Test: `.claude/skills/daa-extract/scripts/test_model_gennemgang.py`

**Interfaces:**
- Svarformat (står i skabelonen):
  - `svar-A-<k>.json`: `[{"ref": "p3-f2", "svar": "OK"|"FORSLAG_FEJL"|"DB_FEJL"|"BEGGE"|"TVIVL", "bogens_laesning":
    str|null, "billede": "bekraefter"|"modsiger"|"ikke_fundet", "grund": str}]`. `bogens_laesning` kræves ved
    `FORSLAG_FEJL`; `DB_FEJL` kun hvor `databasen` findes; `FORSLAG_FEJL`/`DB_FEJL` på navne, tal og steder kræver
    `billede="bekraefter"`.
  - `svar-B-<k>.json`: `[{"post": "p3", "billede": ..., "rettelser": [{"fra": str, "til": str, "art":
    "ocr"|"orddeling"|"mangler"|"overskydende"|"graense", "billede": "bekraefter"|"tvivl", "rammer_forslag": [ref],
    "grund": str}]}]`; `"rettelser": []` betyder OK. `fra` skal forekomme præcis én gang i postens `tekst`.
- Produces:
  - `skriv_briefs(skabelon: str, mappe: Path, bidder: int) -> list[Path]` — `mappe/brief-<k>.md`.
  - `saml(bidder: list[dict], noegle: dict, svar_a: list[Path], svar_b: list[Path]) -> dict` →
    `{"A": [...], "B": [...], "taelling": {...}}`; kaster `GennemgangError` med `SVAR_DUBLET`, `SVAR_MANGLER`,
    `SVAR_UKENDT_REF`, `SVAR_UGYLDIGT`, `RETTELSE_IKKE_ENTYDIG`, `RETTELSE_OVERLAPPER`, `BILLEDSTOETTE_MANGLER`.
  - `grupper_b(b: list[dict]) -> list[dict]` — nøgle `(art, fra, til)` for `ocr`/`orddeling`, ellers én pr. rettelse;
    `graense` grupperes ikke og tæller ikke med i tærsklen.
  - CLI: `model_gennemgang.py saml --ud D` → `D/samlet.json` (0600); printer `MG_SAML_OK a_ok= a_markeret= b_poster_ok=
    b_rettelser= b_grupper= graense= tvivl= over_taerskel=0|1`; ved `over_taerskel=1` exit 3 (stop, §4.3.3).

- [ ] **Step 1: Skriv de fejlende tests** (én pr. fejlkode) plus:
  - `test_saml_ikke_fundet_kraever_tvivl` — `billede="ikke_fundet"` med `FORSLAG_FEJL` → `BILLEDSTOETTE_MANGLER`.
  - `test_grupper_b_samler_samme_ocr_par` — tre `ocr` `"rn"→"m"` på tre poster → én gruppe med 3 elementer.
  - `test_taerskel_300_efter_gruppering` — 301 grupper → `over_taerskel=1`, exit 3; 300 → 0.
  - `test_skabelon_naevner_alle_svarvaerdier` — skabelonen indeholder hver svarværdi, ordet »sidebillede« og
    sætningen om, at svaret til sessionen kun er antal.
- [ ] **Step 2:** Kør → FAIL. **Step 3:** Implementér. **Step 4:** Kør → PASS.
- [ ] **Step 5:** Commit: `feat(6m): brief-skabelon og fail-closed sammenlægning af modelsvar`

### Task 5: B-kort og flet

**Files:**
- Create: `.claude/skills/daa-extract/scripts/laesertekst_rettelse.py`
- Create: `.claude/skills/daa-extract/scripts/laesertekst_kort.html`
- Test: `.claude/skills/daa-extract/scripts/test_laesertekst_rettelse.py`

**Interfaces:**
- Consumes: `samlet.json`, `noegle.json`, bidderne (Task 3-4).
- Produces:
  - `byg_kort(samlet: dict, bidder: list[dict]) -> list[dict]` — én side pr. gruppe/post; hver række viser
    nuværende tekst med kontekst, rettelsen, art, billedstøtte, modellens grund og sidebilledets sti.
  - `render(kort: list[dict], input_sha256: str, pr_side: int = 40) -> list[str]` — HTML-sider.
  - `flet_b(input_sha256: str, svarfiler: list[dict]) -> str` — ark: `# input <sha256>` og én linje pr. rettelse
    `R <ref> : L|K|N|_` (L = ret læsertekst, K = ret læsertekst og meld kildetekst-sag til del 2, N = afvis, _ =
    ubesvaret = ingen handling).
  - CLI: `laesertekst_rettelse.py kort --ud D` → `D/kort-b/kort-<n>.html`; `flet --ud D SVAR...` → `D/ark-b.txt`
    (afviser et eksisterende ark: `ARK_FINDES`); printer kun antal og hashes.
- Kortvejledning (fast tekst, øverst på hver side): hvad L, K, N og tomt betyder; »er du i tvivl, så lad den stå tom«;
  `graense`-rækker og `kun_rapport`-poster har ingen knapper og forklaringen »parkeres til 6d / rettes ikke her«.

- [ ] **Step 1: Skriv de fejlende tests:**
  - `test_kort_er_ikke_forudfyldt` — ingen `checked`/`selected` i HTML; modellens forslag står som tekst.
  - `test_graense_og_kun_rapport_har_ingen_knapper`.
  - `test_vejledning_definerer_hvert_svar` — HTML indeholder forklaring af L, K, N og tomt.
  - `test_flet_gruppesvar_med_undtagelse` — gruppe-svar L, ét element N → arket har L for de andre, N for det ene.
  - `test_flet_afviser_andet_input` — svarfil med andet `input_sha256` → `INPUT_MISMATCH`.
  - `test_flet_ark_findes` — anden flet i samme mappe → `ARK_FINDES`.
- [ ] **Step 2:** Kør → FAIL. **Step 3:** Implementér (mønster: `persona_kort.html`/`persona_kort.py`'s render og
  `flet_sheet`, svar gemt lokalt i browseren og hentet som JSON). **Step 4:** Kør → PASS.
- [ ] **Step 5:** Commit: `feat(6m): kort og flet til projektejerens svar på læsertekst-rettelser`

### Task 6: Ceremoniens SQL og verifikation

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/laesertekst_rettelse.py`
- Test: `.claude/skills/daa-extract/scripts/test_laesertekst_rettelse.py`

**Interfaces:**
- Produces:
  - `anvend(bidder, noegle, samlet, ark_tekst: str) -> dict` → `{"poster": [{"record_key", "person_id",
    "state_sha256", "foer_sha256", "efter_tekst", "efter_sha256", "rettelser": int}], "k_sager": [...],
    "graense": [...]}`; kaster `RETTELSE_IKKE_ENTYDIG`/`RETTELSE_OVERLAPPER` igen mod den aktuelle tekst.
  - `sql_b(anvendt: dict, source_id: int) -> str` — én transaktion: rolle/aktør som 6c-2
    (`-v actor`, `request.jwt.claim.sub`), pr. post `SELECT set_config('app.change_set_id','',true)` og
    `public.red_revider_publiceret_person_narrative_record(person, :src, record_key, <tekst-literal>, state_sha256)`;
    tekst som sikkert SQL-literal (enkeltcitater fordoblet; ingen `E''`).
  - `verify_b_sql(anvendt: dict) -> str` — læse-kun: hver posts `narrative.tekst`-sha256 = `efter_sha256`; antal.
  - CLI: `laesertekst_rettelse.py sql --ud D` → `D/apply-b.sql`, `D/verify-b.sql`, `D/k-sager.json`,
    `D/graensefejl.txt` (linjer med `GRÆNSEFEJL: `-forstavelse, kun ref og record_key); printer
    `LT_SQL_OK poster= rettelser= k_sager= graense= sha256=`.

- [ ] **Step 1: Skriv de fejlende tests:**
  - `test_sql_b_bruger_eksportens_state_sha` — hver kaldlinje bærer postens `state_sha256` fra nøglen.
  - `test_sql_b_nulstiller_change_set_mellem_kald` — antal `set_config('app.change_set_id'` = antal kald.
  - `test_sql_b_citerer_apostrof` — tekst `O'Neill` → `'O''Neill'` i SQL'en, ingen anden forekomst af enkeltcitat.
  - `test_anvend_afviser_overlap_mod_aktuel_tekst`.
  - `test_k_skrives_ikke_i_del_1` — K-rettelser ændrer læserteksten (som L) og står i `k_sager`; ingen
    kildetekst-RPC i SQL'en.
  - `test_kun_rapport_rores_ikke`.
- [ ] **Step 2:** Kør → FAIL. **Step 3:** Implementér. **Step 4:** Kør → PASS.
- [ ] **Step 5:** Commit: `feat(6m): ceremoni-SQL for læsertekst med state-sha-værn og verifikation`

### Task 7: Runner og øvelse på stand-in (hovedsessionen)

**Files:** `~/.private/5ab-overfoersel/30-trin6m.sh` (0600, aldrig i repoet); runbook
`docs/runbooks/trin6m-del1-prod.md`.

- [ ] **Step 1:** Runner efter `29-trin6c2.sh`' mønster: handlinger `eksport` (læse-kun), `input`, `briefs`, `saml`,
  `kort`, `flet`, `sql`, `dump`, `go-b`, `apply-b` (`--jeg-mener-det --go`), `verify`, `fortryd`. GO-koden binder commit,
  eksport-, input-, samlet-, ark- og SQL-hash. Kun antal og hashes ud.
- [ ] **Step 2:** Foreslå projektejeren præcise allow-regler for de læse-/lokale handlinger (aldrig præfiksregel);
  hans valg.
- [ ] **Step 3:** Øvelse fra `~/.private` (operatørens cwd) på stand-in'en fra Task 0 med en syntetisk ark-fil (L på 3
  rettelser): `apply-b` → `verify` grøn; `fortryd` fra dumpet → narrativerne er som før (sha). Mål sekunder pr. post.
- [ ] **Step 4:** Skriv runbooken (rækkefølge, forventede linjer, fortrydelse, fryse) og commit:
  `docs(runbook): trin 6m del 1 i prod`

### Task 8: Modelkørsel, projektejerens kort og ceremoni i prod

- [ ] **Step 1:** `eksport` fra prod → `input` → `briefs`. Pilot: én bid (25 poster) med én Opus-underagent;
  `saml` på pilotbidden; projektejeren ser oversigten og siger til.
- [ ] **Step 2:** Resten af bidderne som Opus-underagenter, højst 6 ad gangen, hver med sin egen `svar-A-<k>.json` og
  `svar-B-<k>.json`. `saml` → hvis exit 3 (over 300): stop og vis projektejeren tallene.
- [ ] **Step 3:** `kort` → projektejeren svarer → `flet` → `sql` → øvelse på en frisk stand-in med det rigtige ark
  (Task 7 Step 3's forløb).
- [ ] **Step 4:** `dump` (prod) → `go-b` → projektejeren kører `apply-b` → `verify` grøn → ledger. Spor A's samlede
  svar og `k-sager.json` gemmes i kontrolmappen som input til del 2.
- [ ] **Step 5 (færdigbevis §7):** dækning 592/592 poster og alle forslag besvaret (fra `MG_SAML_OK`); prod-antal
  reviderede narrativer = arkets L+K-poster; projektejeren vælger tre poster og ser den rettede tekst i læserfladen.

---

## Efter planen

Codex-runde på spec + plan (B13, `gpt-6.1-sol`, Opus dømmer hvert fund: nødvendig / forenkl / kendt begrænsning /
afvis) før udførelse.
