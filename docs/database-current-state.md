# Database — Current State (operatør-guide)

> **Formål:** Ét sted der siger, hvad der faktisk er i prod nu, hvilke SQL-filer der
> er autoritative, og hvordan næste deploy forberedes sikkert. Changelog fortæller
> historien; denne side fortæller tilstanden.
>
> **Sidst afstemt:** 2026-09-17 (trin 4's skema og writere deployet — se §8. Målt:
> 1811 personer, 4 kilder, 1488 observationer, 0 fortolkninger, 2083 reimport-hændelser.
> **Kun trin 4-objekterne og disse fem tal er inventeret ved denne afstemning**; §1's
> øvrige tal er ældre). Forudgående afstemning 2026-08-20 (`red_slet_person` + `_preview` deployet efter
> backup: bindinger, slægts-/linjemedlemskaber og hændelses-ankre ryddes nu, og
> medlemskabstabellerne er registreret i `version_pk_registry`. Verificeret på
> ægte data — person 924 med kildebinding kunne slettes i en rullet-tilbage
> transaktion. **Fase D2 er kørt 2026-08-20: 28 → 7 staged.** Målte tal: 1.811
> personer, 7.197 facts, 2.258 `family_member`, 592 source_records, 905
> write-events; `anon` ser 1.713. Se changelog 2026-08-20).
>
> Forudgående afstemning: 2026-08-18 (den afgrænsede v50-production-writer
> kørt i prod: 8 nye summary-personer 1846-1853 oprettet, navngivet,
> narrativ-publiceret og cutover'et til offentlig synlighed;
> `red_publicer_narrative_record` hærdet
> (draft→published m. eksakt felt-match); prod = 1.812 personer, 7.199 facts,
> 321 write-events; backups + rapporter i `work/task25-1939-v50-production-writer/`.
> Se changelog 2026-08-18). Forudgående afstemning 2026-08-06
> (medie-metadata: 12 nye `vocab`-faktatyper for medier — `kilde_url`,
> `kilde_institution`, `ekstern_objekt_id`, `hentedato`, `fotograf`,
> `rettighedshaver`, `kreditlinje`, `beskrivelse`, `alt_tekst`, `teknik`,
> `fysiske_maal`, `datering` — samt RLS-skærpelse af `entitet_offentlig`:
> media-grenen gik fra ubetinget `true` til `media_rettigheder_ok(p_id)`, så et
> upubliceret medies fakta/noter/relationer nu er mørke for publikum. Applied til
> prod via migration `medie_metadata_faktatyper_og_rls_gate`. Verificeret efter
> deploy: 12/12 seeds; publiceret medie fortsat synligt; upubliceret medie mørkt
> (rollback-DO-blok, ingen data ændret); `place` fortsat true; ukendt type
> fail-closed; grants til anon+authenticated bevaret; `get_advisors(security)` =
> 0 ERROR og ingen nye WARN. Nul eksisterende rækker mørklagt — der fandtes ingen
> upublicerede medier og ingen media-fakta ved deploy. Se changelog 2026-08-06).
> Forudgående afstemning 2026-08-01 (union-redigering: `red_tilfoej_partner`,
> `_samme_som_gruppe`, `trg_partner_loft`, opdateret `red_tilfoej_barn`,
> `enforce_samme_som_invariants` m. UPDATE-trigger og udvidet `red_doede_links`
> applied til prod; data: 65 børn flyttet + 7 forældre matchet → 0 karantænerede
> grupper. Se §7 og changelog 2026-08-01). Forudgående afstemning 2026-07-31 (replay-dagen: IDENTITY + sekvens-gulv-migrationer
> applied; to source-scoped `--replace`-kørsler af DAA 1939 — v2-strukturen med 48
> unummererede + v3-fakta-laget; prod = 1804 personer, 569 1939-poster, alle
> redaktionelle invarianter verificeret; se changelog 2026-07-31). Objektinventar
> i §-afsnittene er fra 2026-07-20/21 og fortsat retvisende for skemaet — kun data
> og sekvenser er ændret. Opdatér ved hver prod-deploy. Ved uenighed med ældre
> planer/specs gælder denne side for prod-status; ret derefter det forældede
> dokument i dets egen dokumentationsrunde.
>
> **Fund ved 2026-07-20-afstemningen:** denne sides "Sidst afstemt: 2026-07-01" havde stået
> ureflekteret i tre uger. Et direkte objektinventar (tabeller + `pg_proc`-funktionsnavne)
> viste at ALT arbejde dateret 2026-07-02 til 2026-07-17 i `db-migrations.sql`/`db-rls.sql`
> (samme_som/ikke_samme_som, udledt slægtsnavn, dato-hærdning, Problem 2 forældrefamilie-fase 1,
> K2 staging-gate m.fl.) reelt VAR live i prod — blot aldrig dokumenteret her. Kun tre
> ting manglede reelt: `haendelse`-tabellen (levende feed fase 2), `story`/`story_kilde`/
> `feed_pin` (levende feed fase 3) og `red_publicer_personer` (K2 selektiv publicering,
> selv samme dag). Alle tre er nu deployet (se §2). **Læring:** stol ikke på denne sides
> dato uden et faktisk objekt-tjek ved næste afstemning — dokumentationsdrift er reel.

---

## 1. Verificeret prod-snapshot 2026-07-20

| Område | Faktisk tilstand |
|---|---|
| Personer | **1.811** total; **7 staged**; **70 levende**; 0 `privat=TRUE` — målt 2026-08-20 efter fase D2 (975 pensioneret som oversigtslinje) |
| Offentlig/medlem | `anon` ser **1.734 personer**, **0 levende**, **0 staged** (efter fase D2, 2026-08-20). Regnestykket går op: 1811 − 70 levende − 7 staged = 1734 |
| Kildebindinger | **559** i `private.narrative_record_publication`, alle `published` (efter C0-efterkørslen 2026-08-21) |
| Kilder | 3 source-rækker. Source 1 = DAA 2018-20/2020 med 591 direkte poster; source 3 = DAA 1939/1939 med 539 direkte poster |
| Slægtskab | **2.258** `family_member`-rækker; **922** `forældrefamilie`-facts (målt 2026-08-20) |
| Medier | **6** media-rækker: 2 `klar`, 4 `fjernet`; privat `media`-bucket og `media_variant` findes |
| Bogmærker | `bookmark` er live og indeholder 1 række |
| Versionering | 22 tabeller i `version_pk_registry`; `change_set`/`change_event` og `text_mention` er live |
| API-sikkerhed | `anon` og `authenticated` har ikke EXECUTE på `_delete_relation_evidence(bigint)`; public-schemaet har 63 RLS-politikker |

Tallene er et øjebliksbillede og kan drive. Synligheds- og objekttilstedeværelses-
asserts er de vigtigste driftsinvarianter; opdatér snapshotdato og tal ved næste
prod-deploy.

---

## 2. Autoritative repo-filer

| Fil | Rolle | Prod-brug |
|---|---|---|
| `schema.sql` | Source of truth for ønsket clean-slate-skema. Indeholder også endnu ikke deployede faser. | Kun frisk base; er **ikke** bevis for prod-status |
| `db-migrations.sql` | Kumulativ additiv migrationssti mod en eksisterende base. Indeholder både live og endnu ikke deployede blokke. | Kun efter backup + rehearsal; brug den præcist godkendte sti/blok |
| `db-rls.sql` | Samlet RLS-/grant-definition. Migrationer genanvender den ikke automatisk. | Genanvend efter relevante DDL-ændringer og verificér roller |
| `db-verify.sql` | Muterende adfærdsasserts med fixtures. Flere blokke er miljø-/dataafhængige. | Kør scoped efter runbook; ikke ukritisk som én samlet prod-fil |
| `db-verify-media.sql` | Media-/Storage-RLS-asserts. Rigtig Supabase har `storage.protect_delete`, som lokal shim ikke spejler fuldt. | Brug mod kopi eller med særskilt godkendt prod-testflow |
| `db-rollback-fase3.sql` | Kirurgisk rollback af tomt fase 3-feedlag; afbryder ved fase 3-data/-historik. | Kun efter fuld backup; ikke deployet eller prod-rehearsed |

`supabase_load.R` i repo-roden er historisk. Nye DAA-loads går gennem
`.claude/skills/daa-extract/scripts/load_daa.R`, normalt append/staged og aldrig
`--reset` mod en befolket prod-base.

---

## 3. Hvad er live i prod

### Kerne, evidens og Fase 4-cutover

- Evidensmodellen `fact` → `assertion` → `citation`/`conclusion`, generiske
  relationer, lineage og personens `visning_*`-cache er live.
- Problem 2-cutoveret er live: `assertion.objekt_type/objekt_id`, fødselsfamilie-
  constraint, `forældrefamilie`-slots og redaktions-RPC'erne til konkurrerende
  forældrepåstande findes. De 921 slots svarer til de to loadede udgavers valgte
  forældrefamilier.
- A1-datohærdningen er live: bl.a. `assertion.date_certainty` og calendar-bæring.
- K2-staging er live: `person.staged`, `person_offentlig`-gaten og
  `red_publicer_udgave(bigint)` findes.
- F-01/F-02/F-02c-hærdningen er live: interne mutatorer er fjernet fra den offentlige
  API-flade, og almindelig `authenticated` er fail-closed til samme personregel som
  `anon`. Levende/staged kræver fortsat redaktionsadgang.

### 1939: publiceringen er i gang (opdateret 2026-08-20)

**Aktuelt:** **7 staged** tilbage af oprindeligt 835.

- **Fase D1** publicerede 68 personer (44 probander + 24 ægtefælle-stubs) 2026-08-19.
- **Fase D2** publicerede de 21 gift-ind-ægtefæller 2026-08-20 (`change_set 960`,
  21 `change_events`, staged 28 → 7). Person-, fact-, relation- og
  narrativtællinger uændrede — fasen rørte udelukkende `staged`. Backup før
  skrivning: `pre-d2-20260820-222135.dump`, SHA-256 `2c974998…`. Se changelog
  2026-08-20 og `docs/superpowers/reviews/1939-v50-fase-d2-go-pakke.md`.

**De 7 tilbage:** `933, 935, 940, 963, 967, 1014, 1135`. Alle har et
1939-narrativ og et `person_external_id`, men **0 published bindinger** — det
er D1's kriterium, de fejler på. De er tre forskellige sager:

| Personer | Sag |
|---|---|
| 933, 935, 940, 1135 | Blandt C0's 9 uforklarede — hører til C3's identitetsspor |
| 1014 | På C0's uafklarede-liste; afventer C0 |
| 963, 967 | **`[KOBL]`-mål der selv er staged.** Uafklaret synligheds-/RLS-spørgsmål: må en record-binding publiceres på en staged persons narrativ? Hører til C0's efterkørsel, ikke til D3. |

Se `docs/superpowers/reviews/1939-v50-fase-c0-efterkoersel-genmaaling.md`.
Afsnittet nedenfor beskriver den oprindelige situation og bevares som historik.

### 1939: loadet staged, men publicering er pauset (historisk)

- DAA 1939 er loadet som source 3 med 835 staged personer (539 direkte poster +
  partnerstubs). De er usynlige for `anon` og almindelig `authenticated`.
- **Publicér ikke source 3.** Projektbeslutningen 2026-07-20 er, at 1939-PDF'en skal
  OCR-udtrækkes igen, og at artefakt-/komplethedsgaten skal gentages før videre
  1939-arbejde. Den ældre `plan-1939-produktionsklar.md` dokumenterer det tidligere
  forløb, men er ikke længere handlingsanvisning for publicering.
- En kommende erstatning/opdatering af staged source 3 kræver en særskilt,
  source-scoped plan, backup og rehearsal. Der må hverken appendes en dubletudgave
  eller bruges `--reset`.

### RLS/GDPR

- `anon` og almindelig `authenticated` ser kun afdøde, ikke-private, ikke-staged
  personer og de personbundne rækker, som arver samme gate.
- `entitet_offentlig`/`family_offentlig` lukker polymorfe fakta, relationer,
  narrativer, noter og mentions fail-closed på levende eller ukendte targets.
- Redaktion har et additivt læse-/skrive-lag gennem rolle-gatede RPC'er.
- En fremtidig medlem/forsker-model med samtykke og slægtsscope er ikke implementeret.

### Versionering, hyperlinks og bogmærker

- `change_set`/`change_event`, `log_change`, `red_fortryd_change_set` og 22
  registry-styrede versioneringstriggere er live.
- `parse_mentions`, `text_mention` og døde-links-viewet er live. Media-grenen i
  `red_doede_links` er live som del af mediehåndtering fase 2.
- Konto-bogmærker er live med owner-bundet RLS.

### Mediehåndtering fase 0-2 (live, senest bekræftet 2026-07-20)

- **Slice 0** (bucket, gating, upload-RPC'er) live siden 2026-07-05. **Fase 1** (filside:
  `red_opdater_media`, `red_genopret_media`, kunstner/datering i `red_upload_media`) og
  **fase 2** (bibliotek: `red_doede_links` udvidet med `maal_type='media'`, `text_mention`
  `GRANT SELECT` + korrekt `media_synlig_anon`-gating i `tm_read`) deployet 2026-07-20.
- `media`-afbildet-gating er FULDT AKTIV (ikke deny-all/tom — se rettelse i §3): 6 media-
  rækker i prod (2 `klar`, 4 `fjernet`), `media_variant` populeret.

### Mediehåndtering fase 3 — hygiejne (live 2026-07-21)

- Den scoped migrationsblok `mediehaandtering_fase3_hygiejne` er live: NULL-bar
  `media.created_at DEFAULT now()`, `relation_afbildet_uidx`, constraint-specifik
  fejlhåndtering i `red_relation`, `ix_note_target`, relationsevidens-triggerne og
  `red_slet_medierelation_uden_evidens`.
- Web-produktionen og en ny native iOS Release fra `caeb6a3` er deployet; den
  autentificerede redaktør-røgtest af upload, dedup, afbrudt upload, blødt flet og
  HEIC-henvisning er gennemført.
- Første janitor-kørsel var rapport-only: 0 strandede uploads, 0 forældreløse
  Storage-objekter, 0 ægte SHA-dubletter og 0 fremmede buckets. Den fandt to
  manglende varianter på media 3 og seks historiske SHA-kandidater (media 1–6).
  Disse er opfølgning; `--slet` og `--backfill-sha` er ikke kørt.

### Personers OCR-kvalitetsark — DB + web live, røgtest udestående (2026-07-28)

- Migreret mod prod (`person_ocr_kvalitetsark` + `person_ocr_kvalitetsark_rls`,
  Supabase migrationshistorik `20260727215750`/`20260727215816`): `import_korrektion`-
  journal (uden for loaderens reset-liste, ingen FK til regenererbare id'er), stabile
  importnøgler (`source.import_key`, `person_external_id.record_key`) samt RPC'erne
  `red_person_grid`, `red_ret_ocr_felt`, `red_ocr_historik`.
- Verificeret direkte mod prod efter migration: `anon` afvist (rigtig REST-kald, 401),
  `get_advisors(security)` delta +3 (kun de kendte SECURITY DEFINER-mønstre, ingen nye
  kategorier), data uændret (1756 personer, 8716 assertions).
- Krypteret fuld backup taget og gendannelses-verificeret før migration
  (`daa-prod-pre-ocr-kvalitetsark-20260727-214752.dump.gpg`).
- **Web merget og deployet (2026-07-27).** PR #103 merget til `main` af brugeren;
  Vercel auto-deploy bekræftet mod det live JS-bundle. Manuel redaktør-røgtest i
  browser (checklisten i runbookens §4) er stadig udestående.
- **DAA 2018-20 har nu stabil `(import_key, record_key)` (2026-07-28), via en
  tilføjende backfill — IKKE en genindlæsning.** `--reset`-genindlæsning blev
  forkastet: prods `change_set` har 482 `red_samme_som` plus dusinvis andre
  redaktørrettelser, som loaderens `has_reset_blocking_editorial_changes()`-spærre
  fail-closed ville have blokeret (eller, hvis tvunget igennem, slettet). I stedet
  stemplede en ren `UPDATE`-transaktion — rehearsed mod en lokal kopi af prods
  rigtige data, verificeret 591/591 uden gæt (kilde: filnavnene i
  `data/extracted-2026-06-18/*.json` ER `record_key`) — de 591 eksisterende
  2018-20-personer med `source.import_key='daa:2018-20'` og
  `person_external_id.record_key`. Frisk backup taget før kørsel
  (`daa-prod-pre-record-key-backfill-20260728-074303.dump.gpg`). Resultat mod
  ægte prod: 588/591 personer nu `kan_rettes.navn=true`, 0 `record_key_mangler`,
  `get_advisors(security)` uændret på 133 lints (ren DML). **1939-udgaven
  (staged, `source.id=3`) har stadig ingen stabil identitet.**
- **`red_person_grid` rettet i prod 2026-07-28** (ren `CREATE OR REPLACE FUNCTION`,
  ingen data rørt, `get_advisors` uændret på 133 lints): `navn_mangler` målte på
  anker-gatede felter og flagede derfor hver ikke-redigerbar række — 1169 af 1757,
  alle med synligt navn, nul ægte. Måler nu den viste værdi. Samtidig gav
  `same_as_context` to rækker for en person midt i en `samme_som`-kæde (både alias
  og kanonisk); griddet lover én række pr. fysisk person, nu håndhævet med
  `DISTINCT ON` og alias-forrang. Prod efter: 1756 rækker / 1756 personer, 0
  `navn_mangler`.
- **Kendt, ikke lukket:** `enforce_samme_som_invariants()` er kun `BEFORE INSERT`
  og G4 tjekker kun `NEW.subjekt`. Indsættes den inderste kant i en kæde først,
  slipper den ydre igennem — sådan opstod person 826's tilstand. Griddet tåler det
  nu, men invarianten kan fortsat omgås via indsættelsesrækkefølge.
- **627 gift-ind-ægtefæller** (ægtefælle/forælder i en familie, ingen egen bogpost)
  har intet `person_external_id` og er derfor ikke-redigerbare i kvalitetsarket.
  Egen plan udestår; nøgle ville være forælderens `record_key` + indeks i
  `aegteskaber`, og `linje` SKAL være NULL — ellers joiner
  `regen_person_visning()` dem ind i slægtslinjen og påhæfter slægtsnavnet.
- Drift, gated procedure og udestående trin: `docs/runbooks/person-ocr-kvalitetsark.md`.

### Levende feed fase 2-3 + K2 selektiv publicering (deployet 2026-07-20)
- **`haendelse`** (fase 2, regenererbar hændelses-projektion af narrativer) + **`story`/
  `story_kilde`/`feed_pin`** (fase 3, kurateret formidlingslag) — additive tabeller,
  RLS aktiv (anon ser kun `publiceret`+ikke-privat+offentligt-subjekt for story;
  `feed_status<>'skjult'` for haendelse), versioneret via `log_change`.
- **`red_publicer_personer(person_ids[])`**: selektiv modstykke til `red_publicer_udgave`
  — publicerer kun udvalgte 1939-personer (+ familie-partnere) fremfor hele kilden på én gang.
- Deployet direkte via Supabase MCP (`execute_sql`/`apply_migration`), ikke `psql`-runbooken;
  objekt-eksistens + `get_advisors(security)` verificeret efter apply (117 fund, alle kendte
  mønstre — SECURITY DEFINER-eksponering + bevidst deny-all på historik-tabeller — ingen nye).
  **Udestår:** brugerens egen live-røgtest af filside/bibliotek/feed i appen.

---

### #152 fase 1, #153 og 149b — DDL LIVE i prod (2026-09-05, GO 1)

`db-migrations.sql` + `db-rls.sql` fra main `21ff44b` er kørt mod prod (hver i én
transaktion, exit 0). Kontraktversionen er fortsat **1**: #152's cutover er IKKE kørt,
og ingen data er ændret (1811/1169/563/7197/2258 uændrede). Nyt i kataloget: den
generelle reimport-writer (#153) inkl. `legacy_migration`-operation og
`red_apply_reimport_legacy_migration`, #152's kontrakt-, ledger- og eventtabeller
(tomme), reversal-gren for `legacy_migrated`, statusfiltre i læsefunktionerne og
publiceringsgaten. 1939's tre reimport-batches er migreret til `private.reimport_batch`
(1 activated, 2 finalized). Backup før apply: SHA `5d1dc497…`. Se changelog 2026-09-05.

### #152-cutover — LIVE i prod, kontraktversion 2 (2026-09-06, GO 2)

`private.apply_narrative_record_cutover` kørt via runbooken fra checkout `c8b76e9`: 563
record-baselines + 552 grandfathered legacy-rækker (544 fra 2018-20, 8 fra 1939), change set
967, receipt `512068f804cb52ce…`, postverify bestået. Gamle person/DAA-skriveveje er lukkede;
redaktørerne bruger de nye `red_*_person_narrative_record`-RPC'er. Nye bindinger er frosset
indtil 149a/149b er anvendt (GO 3-4). Se changelog 2026-09-06.

### 149a — 2018-20 kilderegnskab LIVE i prod (2026-09-06, GO 3)

Batch `30469676…` (`finalized`, 591 `source_evidence`): 1 rendition
(`daa-2018-20-pdftotext-r1`, rå tekst `2dd5cf84…`), 591 `source_record` (`person_post`),
591 forekomster og 591 accepterede ankre for source 1. Ingen ændring i `person`/`fact`/
`family_member`/`narrative`/bindinger. Bindingerne følger med 149b (GO 4).

### 149b — 2018-20 narrativ-binding LIVE i prod (2026-09-06, GO 4)

Batch `0854a091…` (`finalized`, 587 `legacy_migration`): 541 biografier kildebundne og
publicerede med »DAA 2018-20, s. N« og stabil `source_record_ref`, 46 levende som skjulte
kladder, 3 fortsat overgangsdata (`I-133`, `II-35`, `III-129`), 1 uafklaret levende
(`IV-94`) uden binding. 587 persona-identiteter (evidens `person_external_id`, valg A).
Frysningen af nye bindinger fra #152 er dermed ophævet for 2018-20 og 1939.

## 4. Hvad er ikke live / bevidst udskudt

| Emne | Status |
|---|---|
| **RLS `authenticated`-tier** (medlem/forsker ser levende slægtninge m. samtykke) | Kun skitseret i `db-rls.sql` §FREMTID. Bygges når login/profiles-auth er på plads. Indtil da er levende data usynlige for alle uden `redaktion`-rolle. |
| **`max(id)+1` → IDENTITY/sekvenser** | Udskudt post-PoC. Kritisk før flerbruger-skrivning (også multi-writer-risikoen generelt). |
| **Samtykke-granularitet pr. levende person** (`samtykke_offentlig`) | Designes med auth-laget. |
| **Vocab-håndhævelse** | `vocab`-tabel findes, men `rolle`/`faktatype`/`konfidens` m.fl. er fritekst (ingen FK til vocab). Håndhæves i dag kun konventionelt. |
| **Polymorf døde-link-integritetsrapport** | Kun `text_mention` har et døde-links-view. Bredere orphan-check (fact/relation/assertion → subjekt) findes ikke systematisk endnu. |
| Levende feed fase 4 | LLM-assist/Edge Function — bevidst udskudt 2026-07-20 (for få kilder i PoC til at retfærdiggøre kørslen endnu), ikke annulleret. Se `decisions.md`. |
| **Mediehåndtering fase 4 — identitet & endeligt farvel** | **LIVE i prod (2026-07-22).** Nye funktioner i `schema.sql`: `red_erstat_media_fil` (erstat bytes, behold identitet — atomisk `AND upload_status='klar'`-gate mod race), `red_udrens_media_preview`+`red_udrens_media` (permanent sletning, blokeret på SYV polymorfe ankre: relation, text_mention, fact, story, narrative, note, suggestion — guard+slet i ét atomisk `DELETE...NOT EXISTS`-statement), `red_saet_portraet` (portræt-valg, `relation.kvalifikator jsonb`-kolonne, additiv). Deployet via scoped blok `mediehaandtering_fase4_identitet`; fase-4-verify-blokkene kørt og bestået direkte mod prod (impersoneret redaktion-profil), `get_advisors(security)` viste kun kendte SECURITY DEFINER-mønstre. `db-rls.sql` uændret. Web app-deployet (Vercel, PR #75); redaktør-røgtestet (erstat/udrens/portræt) med succes; janitor-rapport bekræftede korrekt kategori-b-håndtering af et reelt erstat, ingen `--slet` kørt. |
| **Trin 4's dataskrivning** (klausuler via `clause_evidence`, forslag via `interpretation_proposal`) | **Klausulerne er skrevet 2026-09-18**: 591 records, 868 klausuler, 617/251 dispositioner, én `finalized` batch, afstemt med klausul-projektionen (`match`, uændrede neutrale lister). Procedure: `docs/runbooks/clause-evidence-prod-apply.md`. **Omsegmenteret 2026-09-28** (§9): 51 poster har fået et nyt klausulsæt (116 klausuler skrevet, 197 `erstattet`); 984 klausulrækker, heraf 787 aktuelle. **Fortolkningskæden overført 2026-10-05:** 3.739 forslag (`interpretation_proposal`), 676 afgørelser og 622 bindinger for 2018-20 fra den nøglede pakke, `VERIFY_OK` (digests lig pakken, `anon` uden adgang). Procedure og fortrydelse: `docs/runbooks/transfer-2018-20-prod.md`; restorepunkt er skrivepausens dump. |
| Mediehåndtering fase 5 | Dokumenttransskription er ikke designet endnu. |
| 1939-publicering | Pauset indtil nyt OCR-udtræk, nyt artefakt og fornyet komplethedsgate (uddybet i §3) |
| Import-sikkerhed | Stabil import-run/checksum/udgavenøgle og source-scoped replace mangler; `--reset` er fortsat en farlig nødvej |
| Skalering | Klienterne materialiserer hele grafen; bounded server-slices/keyset-pagination mangler |

---

## 5. Gated deployprocedure

1. **Lås scope:** navngiv prod-projekt og præcis migrationsblok/feature. Ingen bred
   "kør alt"-antagelse.
2. **Read-only preflight:** tag katalog-/tælle-snapshot og bekræft forventet baseline.
3. **Backup:** krypteret `pg_dump` af prod; opbevar PII uden for Git.
4. **Restore-rehearsal:** gendan dumpet i en lokal engangsbase, kør den identiske
   migrations-/RLS-sti, mål blast radius og øv rollback.
5. **Eksplicit godkendelse:** brugeren navngiver prod-målet og det konkrete apply.
6. **Atomisk apply:** `--single-transaction` hvor artefaktet tillader det; genanvend
   `db-rls.sql` når policies/grants påvirkes.
   For evidens-hardening (#154/#155) skal den godkendte `db-migrations.sql`-blok
   og de tilhørende `db-rls.sql`-grants køres i samme deploy-transaktion efter en
   restore-rehearsal. Kør aldrig `db-rls.sql` alene som kompensation for en
   migrationssti. Hver ny eller erstattet `public.red_*` skal i samme transaktion
   være eksplicit klassificeret som authenticated-, service-only- eller lukket RPC
   og få sit passende `GRANT EXECUTE`; `PUBLIC` er aldrig en implicit klientrolle.
   Den katalogbaserede `db-verify`-policy samt både migrations- og fresh-schema-
   vejen i CI er deploy-gaten, efterfulgt af append-only- og fortolkningskontroller
   i en isoleret database.
7. **Verificér:** scoped adfærdsasserts, read-only katalog-/RLS-smoke, Data API-grants,
   schema-cache og Supabase security advisors.
8. **Dokumentér:** opdatér changelog og denne side med faktisk resultat, tal og
   rollback-artefakt. Markér tydeligt kodeklar versus live.

Git-, app- og prod-databasestatus er tre separate dimensioner. En merge eller grøn CI
er aldrig i sig selv et prod-deploy.

---

## 6. Se også

- `docs/changelog.md` — kronologisk historik og test-/deploybeviser.
- `docs/fase4-runbook.md` — det gennemførte Problem 2/A1/K2-cutover og 1939-loadets
  tidligere runbook.
- `docs/decisions.md` — arkitekturbeslutninger.
- `datamodel-oversigt.md` — konceptuel model.
- `docs/README.md` — dokumentationsindeks.

## Mediehåndtering fase 1+2 — LIVE i prod (2026-07-20)

Redaktionslaget har nu en filside for eksisterende `media`-rækker. Kuraterbare metadata
(`titel`, `slags`, `kunstner`, `datering`) opdateres via `red_opdater_media`; blødt fjernede
rækker kan genoprettes via `red_genopret_media`. Rettighedsgaten vedligeholdes fortsat gennem
`red_set_media_rettigheder`, og `red_upload_media` accepterer nu også kunstner og datering.

`upload_status='fjernet'` er fortsat usynlig for offentligheden og for almindelige medlemmer.
Redaktionen læser derimod rækken for at kunne vise status og genoprette den. Lightbox og
narrativ-mention-pickere filtrerer eksplicit til `upload_status='klar'`.

`red_doede_links` er udvidet med `maal_type='media'`: kun et media-id uden en eksisterende
`media`-række er dødt. En række med `upload_status='fjernet'` er ikke død, fordi den stadig
findes og kan genoprettes. `security_invoker` er bevaret. Samtidig fik `text_mention` sit
hidtil manglende `GRANT SELECT` (viewet var reelt utilgængeligt for alle, inkl. redaktionen,
siden 2026-06-30) og `tm_read`-policyen bruger nu `media_synlig_anon` for `maal_type='media'`
i stedet for `entitet_offentlig`s ubetingede `true`-gren — lukker et latent fail-open-hul
(aldrig udnyttet i praksis, da manglende GRANT gjorde tabellen uforespørgelig).

Se §2 for detaljer om deploy-vejen (kørt direkte via Supabase MCP samme dag som levende
feed fase 2-3, se ovenfor).


## 7. Union-redigering + identitets-invarianter — LIVE i prod (2026-08-01)

Applied atomisk med `lock_timeout 5s`; verify-blokken derefter kørt mod prod og rullet
tilbage. `get_advisors(security)`: 139 → 135 lints (revoke på de to nye trigger-funktioner).

**Nye objekter**

| Objekt | Rolle |
|---|---|
| `_samme_som_gruppe(bigint)` | Hele den uorienterede `samme_som`-komponent for en person. `SECURITY INVOKER`, EXECUTE revoked fra `PUBLIC, anon, authenticated` (ville ellers være et oracle mod skjulte relationer). |
| `_tjek_partner_loft()` + `trg_partner_loft` | `BEFORE INSERT OR UPDATE ON family_member`. Maks to parter pr. union, og de to skal være forskellige personer også på identitet. EXECUTE revoked. |
| `red_tilfoej_partner(family, person, ordinal)` | Tilføj manglende part til en EKSISTERENDE union. Gated på `current_rolle()='redaktion'`. |
| `trg_enforce_samme_som_update` | `BEFORE UPDATE ON relation`. Rolle/endepunkter på `samme_som` er uforanderlige — slet+genopret. |

**Ændrede objekter**

- `red_tilfoej_barn` — cyklus-guarden sammenligner nu `samme_som`-komponenter, ikke rå id'er.
- `enforce_samme_som_invariants` — nu `SECURITY DEFINER`, håndterer `TG_OP='UPDATE'`, og
  afviser at to parter i samme union linkes som samme person. EXECUTE revoked.
- `red_doede_links` — udvidet fra 4 til 10 måltyper (hele `parse_mentions`-vokabularet).

**Kendt, dokumenteret restrisiko:** krydsracet mellem `trg_partner_loft` og
`enforce_samme_som_invariants` er ikke lukket — advisory-låsen der ville lukke det gav
deadlock mod `load_daa.R`. Se `docs/decisions.md` (2026-08-01).

**Efterladt i data:** 15 mor-løse 1939-familier står tilbage med én part og 0 børn.
De kan ikke slettes: bogens oprindelige forældrepåstande peger stadig på dem.

## 8. Trin 4: klausullag, prædikat-navnerum og to writere — LIVE i prod (2026-09-17)

**Skema, funktioner og kontrolleret vokabular — ingen evidensdata.** Klausullaget,
prædikat-navnerummet og writerne findes; ingen klausuler, dispositioner eller
fortolkninger er skrevet. At køre writerne mod prod er en særskilt, gated beslutning (§4).

**Deploy efter §5:** læse-kun preflight → backup → restore-rehearsal → projektejerens
GO → apply → læse-kun verifikation.

- **Backup:** `daa-prod-20260917141330.dump`, SHA-256 `ee4fd901…`, 0600, uden for Git.
  Et dump fra 2026-09-15 blev kasseret: dagens var 15 KB større **med identiske tal**, så
  det gamle var ikke længere et trofast rollback-punkt.
- **Rehearsal** mod en restore af netop det dump: `db-migrations.sql` to gange rent,
  `db-rls.sql`, `db-verify` med fire OK-blokke (#148 ×2, #147 ×2), fem kontrakttests,
  nul datadelta.
- **Apply** fra repo `140a17b`: hele `db-migrations.sql` → `db-rls.sql` med
  `--single-transaction` → `NOTIFY pgrst, 'reload schema'`.
  `db-migrations.sql` kan **ikke** køre med `--single-transaction`: filen ejer #153's egen
  `BEGIN`/`COMMIT` (linje 11251–12622), som ville committe en ydre transaktion midtvejs.
  Sikkerheden er idempotens (bevist i rehearsal) plus backuppen.
- **Stopporte før første skrivning:** backup-SHA, 0 trin 4-objekter, baseline-tal,
  0 `change_set` oprettet efter backup-start, 0 in-flight autorisationer.

**Nye objekter**

| Blok | Objekter |
|---|---|
| #148 4.1a | `private.source_observation.parent_observation_id`; `private.clause_disposition` + view `clause_disposition_current`; `validate_clause_observation`, `validate_clause_disposition` + to triggere; `observation_kind='clause'` i `private.vocab` |
| #148 4.1c | `private.write_clause_evidence`; `public.red_apply_reimport_clause_evidence` |
| #147 4.2 | `private.interpretation_predicate` + view `interpretation_predicate_promotable`; fire funktioner, fire triggere; seed-prædikater |
| #147 4.4 | `private.deterministic_uuid`; `private.write_interpretation_proposal`; `public.red_apply_reimport_interpretation_proposal` |

**Erstattede objekter:** `private.validate_reimport_authorization_payload`,
`public.red_finalize_reimport`, `public.red_reimport_batch_result`. De lukkede
operationsmængder kender nu `clause_evidence` og `interpretation_proposal`. Både 4.1c og
4.4 omdefinerer alle tre, så **rækkefølgen 4.1a → 4.1c → 4.2 → 4.4 er bindende**: 4.1c
kørt efter 4.4 ville stille fjerne `interpretation_proposal` fra vokabularet.

**Verificeret i prod (læse-kun):**

- alle otte kontrollerede objekter til stede;
- begge lukkede mængder kender begge operationer;
- `anon` og `authenticated` kan ikke læse `clause_disposition`, `interpretation_predicate`,
  `interpretation` eller `source_observation`;
- `anon` har ikke EXECUTE på de fire `red_*`-funktioner. `authenticated` har EXECUTE —
  projektets mønster for redaktør-RPC'er med rolle-gate inde i funktionen, godkendt af
  `db-verify`'s ACL-blokke i rehearsal;
- tal uændrede: 1811 / 4 / 1488 / 0 / 2083.

**Web-fladen** er efterset af projektejeren efter deployet og ser umiddelbart normal ud (relevant, fordi `db-rls.sql` genskrev politikkerne).

**Ikke kørt mod prod:** `db-verify.sql` (muterende fixtures) — kun i rehearsal.

**Advisors (security, kørt 2026-09-17 efter deploy):** 0 ERROR, 141 WARN, 48 INFO. Fire
linjer skyldes trin 4, alle kendte mønstre: WARN `authenticated_security_definer_function_executable`
på `red_apply_reimport_clause_evidence` og `red_apply_reimport_interpretation_proposal`
(rolle-gate i funktionen), og INFO `rls_enabled_no_policy` på `private.clause_disposition`
og `private.interpretation_predicate` (deny-all; adgang kun via `SECURITY DEFINER`, som de
øvrige private tabeller). Ingen `anon`-lint på nye funktioner, ingen
`function_search_path_mutable`, ingen view-lint. Uden for deployet: *Leaked Password
Protection* er slået fra i Auth, og 14 ældre funktioner kan kaldes af `anon`.

**Advisors (performance, samme dag):** 0 ERROR, 24 WARN, 68 INFO. Ét fund skyldes trin 4:
INFO `unindexed_foreign_keys` på `private.interpretation.interpretation_predicate_fk`. Uden
praktisk betydning, fordi prædikattabellen afviser UPDATE/DELETE og `interpretation` er tom —
men bør indekseres, før forslags-writeren kører på skala. Øvrige fund er ældre: 5
`auth_rls_initplan` (`profiles`, `bookmark`, `suggestion`), 18
`multiple_permissive_policies` (læser- + redaktørpolitik på samme tabel), 1 `duplicate_index`
på `private.source_persona_placement` og 10 `unused_index`, som ikke må droppes alene på det
grundlag (fx `narrative_fts_idx`). MCP-forbindelsen fra Claude-sessioner når et andet
Supabase-projekt, så advisors læses i dashboardet.

**Rollback:** ingen kirurgisk rollback-fil. Vejen tilbage er restore af backuppen ovenfor.

## 9. Omsegmentering af 2018-20's klausuler (`clause_revision`, S4) — LIVE i prod (2026-09-28)

**DDL og data.** #222's klausulsæt (`clause_set_seq`, NULL = sæt 1; unikhedsindeks pr. sæt; view
`private.clause_observation_current`; fire selvstændige triggere), writer-operationen
`clause_revision` (`private.write_clause_revision`, `public.red_apply_reimport_clause_revision`) og S4
(ét forslagsbatch pr. post, citater kun i det aktuelle sæt). DDL'en deployede også #212's
hjælpefunktioner, som #222 bygger på.

**Procedure:** `docs/runbooks/clause-revision-prod-apply.md` med de private operatørscripts
`~/.private/omseg-prod/` (00-08). Skrivepause → preflight → dump i pausen → rehearsal af netop det dump →
DDL → advisors → apply → verify → pause ophævet.

- **Repo:** `b42266e`. **Backup:** `daa-prod-20260928150228.dump`, SHA-256 `004e7a50…`, 0600, uden for Git.
- **Rehearsal** af netop det dump: restore = preflight (tilstand, kanonisk, portabel anon, skema),
  DDL to gange med samme skema-fingeraftryk, F1 → `match`, fortryd (U) → `match`, frem igen → `match`,
  fuld `db-verify`.
- **DDL:** `db-migrations.sql` → `db-rls.sql --single-transaction` → `NOTIFY pgrst`. Efter: 0 `WARNING`,
  skema-fingeraftryk = rehearsal, 868/868 klausuler i sæt 1, kanonisk og anon uændrede, levende
  verify-blok OK.
- **Apply:** manifest F1 `2f4b079b…` (51 operationer), profil `daa-2018-20-clause-revision-v1`
  (`b72ddf5f…`), én `finalized` batch, replay `already_applied`. Efter: 984 klausulrækker, 787
  aktuelle, 197 `erstattet`, 51 `clause_revision`-hændelser.
- **Verify (læse-kun):** komparatoren `match` (51 records, 116 skrevet / 197 erstattet, nye
  dispositioner 56 `afventer_fortolkning` / 60 `maskinelt_flagget`), sæt-hashes `1bad2e97…`, profil-readback,
  kanonisk og anon uændrede.
- **Advisors (security, efter DDL):** 0 ERROR. Én ny linje: WARN
  `authenticated_security_definer_function_executable` på `red_apply_reimport_clause_revision` —
  samme mønster som `red_apply_reimport_clause_evidence` (kun `authenticated`, tynd indgang til en
  privat writer med batch- og autorisationskrav; ACL tjekket af verify-blokken). Ingen nye `anon`-linjer,
  ingen nye tabeller.

**Fortrydelse** er en ny revision tilbage til 4.1b's opdeling (`07-fortryd.sh`, øvet i rehearsal og på
stand-ins), ikke restore. Vinduet er åbent, indtil projektejeren lukker det; indtil da bevares
`~/.private/omseg-prod/` (inkl. `go-env.txt`), begge ledgers og renditionen (runbook §3).

**Lært undervejs:** anon-hashen over `x::text` afhænger af serverens locale (macOS citerer værdier med
byten 0xA0, Linux gør ikke), så prod ↔ lokal restore sammenlignes med en portabel hash over
`to_jsonb(x)::text`. Målt ens i prod og restore.

## 10. 5a+5b's DDL (#151) — LIVE i prod (2026-10-22, GO 1)

**DDL, ingen kildedata.** 5a's identitetsvej (kandidater, kvittering, spor, kontrolstikprøve) og 5b's relationslag
(relationspersonas, bindinger, ægtefælle-undtagelser, ægteskabsnumre, børnehenvisninger, indholds-id'er): 12 nye
`private`-tabeller og 76 nye funktioner (bl.a. `public_family_sources(bigint[])` til læserens kildelinjer); flere eksisterende `red_*` genskabt.
DDL'en skrev kun tre promotion-regler (`interpretation_promotion_rule`, `_rule_line`, `rule_mode` og
`interpretation_promotion_batch.items_sha256`). 5a's 31 kalibreringsafgørelser er ikke overført; prod har fortsat
587 149b-koblinger.

**Procedure:** `docs/runbooks/transfer-5ab-ddl-prod.md`, private scripts `~/.private/5ab-overfoersel/`.

- **Repo:** `7c645632`. **D0:** `daa-prod-20261022162044-d0.dump` (sha `dc6dfc61…`); **D1:**
  `daa-prod-20261022180917-d1.dump` (sha `7f7304ce…`), begge 0600 uden for Git og verificeret ved fuld lokal restore.
- **Rehearsal på D0:** idempotens, fire afbrud (op til 27 åbne `red_*` i et funktionsvindue), fortrydelse
  (89 objekter, intet åbnet under restoren), `db-verify` grøn.
- **DDL:** `DDL_OK` fra `PRE`; portabelt katalog/ACL = rehearsal; lokale dele uændrede; trin 4's digests uændrede;
  `DATA_DELTA_OK changed=3 new=12`.
- **Probe:** `DDL_VERIFY_OK` (`anon` kan ikke læse `private`, RLS på alle `private`-tabeller).
- **Advisors (security, CLI):** 48 → 60; de 12 nye er `rls_enabled_no_policy` på de nye `private`-tabeller (med vilje).
  CLI'en dækker færre lint-typer end dashboardet.
- **Skrivepausen** sluttede ved data-ceremoniens `VERIFY_OK` 2026-10-25 (afsnit 11).

## 16. 5c-2 + B11: læserne på placement og fakta med kilde — LIVE i prod (2026-10-29)

**Procedure:** `docs/runbooks/5c2-b11-prod.md`, privat script `~/.private/5ab-overfoersel/24-5c2-b11.sh`.
Repo `bd86d833` (`main` med PR #275-#277), GO 5c2 `bb1678f9`; dump før skrivning `daa-prod-20261029180320-5c2.dump`
(sha `0e988082…`). Efterkontrol fra `db169779` (PR #278).

- **DDL (additiv, ingen data):** blokken `-- BEGIN/END 5c2-b11` (sha `97a69759…`) i én transaktion:
  `private.assertion_binding_current(uuid)` (ingen grants), `public.public_person_facts(bigint[])` og
  `public.public_person_source_coordinates()` (begge SECURITY DEFINER, EXECUTE til `anon` og `authenticated`).
  PostgREST genindlæst. `person_source_coordinate_legacy` og alle tabeller uændrede.
- **Ekstern kopi (B1):** `age`-krypteret (sha `eb1ec566…`) på projektejerens SFTP-server, rundtur ok.
- **Afbrudt og genoptaget (decisions 2026-10-29):** målingen efter stoppede på prods `statement_timeout` (2 min); hvert
  bindingstjek læser `private.interpretation_current` (~130 ms pr. kald i prod). Målingen hæver nu grænsen lokalt;
  ingen ny DDL.
- **Kvitteringer:** før `C2B11_MAAL funktioner=0`; efter `C2B11_MAAL_OK tilstand=efter` (linjen =
  `5c2_forventet_maal.txt`: `koord=1113 placement=530 legacy=583 fakta=6473 bundet=622 import=5765 ingen_kilde=86
  uden_narrativ=621 udfald_i_alt=0 udfald_publicering=0`) og `C2B11_DIFF n=37 noegler=ens genparitet=ok`.
  PostgREST-gaten som `anon`: `RPC_GATE … resultat=OK` (samme tal).
- **Browsertjek (anon, prod-web):** person uden prosa med fakta, bundet faktum med postreference, 15a/15b, kuld-rettet
  person, kilde 3 (sammenfoldet og ufoldet) og en ikke-offentlig person: alle som forventet.
- **Ydelse:** anon-rollens `statement_timeout` er 3 s. `public_person_facts` koster op til ~1,9 s for de tungeste
  personer (id ~380-560) og timer ud i bidder af 10; klienten kalder én person ad gangen. Et `narrative`-udtræk på 1000
  rækker som `anon` timer også ud (100 rækker: 0,5 s).
- **Bemærk:** `uden_narrativ` tæller personer uden række i `public.narrative`, ikke personer uden synlig prosa;
  2018-20's prosa vises via `public_person_bio_source_versions_v2` (stikprøve: 5 af 83 personer uden prosa).
- **Udestår:** `get_advisors` (sikkerhed) efter blokken, runbookens skridt 6.
- **Fortryd:** revert af klient-PR #277 (funktionerne bliver stående); nødudvej restore af dumpet + `db-rls.sql`.

## 15. A6b: 10 narrativrevisioner (de beskårne prosalinjer) — LIVE i prod (2026-10-28)

**Procedure:** `docs/runbooks/a6b-narrativ-revision-prod.md`, privat script `~/.private/5ab-overfoersel/23-a6b.sh`.
Repo `39a812f7` (`main`, PR #273), GO a6b `5522a891` (bundet til commit, filer og retning `frem`); dump før skrivning
`daa-prod-20261028224757-a6b.dump` (14,6 MB, sha `58351421…`).

- **Hvad:** ingen DDL. De 10 publicerede 2018-20-narrativer (I-9, I-11, I-17, I-18, I-32, I-33, I-44, I-84, I-89,
  III-37) fik de prosalinjer, v1-støjreglen fjernede (`decisions.md` 2026-10-27/-28), med
  `red_revider_publiceret_person_narrative_record` i én transaktion. Manifest `work/a6b/manifest.json` (gitignoreret,
  mode 600), `manifest_sha256` `f80e8156…`.
- **Ekstern kopi (B1):** `age`-krypteret (sha `84b9d988…`) på projektejerens SFTP-server, rundtur ok; ved `apply` blev
  dumpet og den eksterne kopi tjekket igen (`B1_A6B_OK`).
- **Kvitteringer:** før `A6B_MAAL_OK tilstand=gammel events=3314 change_sets=2069 change_events=9222`;
  `A6B_OK retning=frem revideret=10 ubundet=1 change_sets=10 go=5522a891`; efter
  `A6B_MAAL_OK tilstand=ny events=3324 change_sets=2079 change_events=9232`. Øvrige narrativer og målenes øvrige felter
  uændrede (rest-hashes = øvelsens).
- **Kendt følge:** `narrative.tekst` ≠ helpostens `verbatim_text` for de 10 poster, indtil trin 6 retter kildeteksten og
  klausulerne. III-129 (ubundet) er urørt.
- **Fortryd:** `go --tilbage` + `apply --jeg-mener-det --go <kode> --tilbage` (ny revision tilbage til den gamle tekst;
  prøvet gennem runneren); nødudvej restore af dumpet.

## 14. Review trin B: fire funktionsrettelser — LIVE i prod (2026-10-28)

**Procedure:** `docs/runbooks/review-trin-b-prod.md`, privat script `~/.private/5ab-overfoersel/22-trin-b.sh`.
Repo `f3850eec` (gren `fix/review-trin-b`, før merge), GO trinb `33f99750` (= øvelsens); dump før skrivning
`daa-prod-20261028184913-trinb.dump` (14,6 MB, sha `e253f352…`).

- **Ekstern kopi (B1, første brug):** dumpet `age`-krypteret (sha `0e5bc17f…`) på projektejerens SFTP-server, hentet
  tilbage, sammenlignet byte for byte og dekrypteret (`EKSTERN_TRINB_OK … rundtur=ok`). Prøvegendannelsen genskabte
  den hentede kopi lokalt: `PROEVE_TRINB_OK … personer=1811`, fingeraftryk som prod.
- **DDL:** blokken `-- BEGIN/END review-trin-b` i én transaktion (`lock_timeout` 5 s; prods `statement_timeout` 2 min):
  `private.preview_relation_promotions` (1d.3b-01: `RELATION_PROMOTION_DECISION_FAMILY_CHANGED` for ægteskab og forælder),
  `red_edit_oplysning` (1d.1-03: ompeger ikke en konklusion; arver `date_certainty` ved uændret datotekst),
  `red_slet_oplysning` (1d.1-02: afviser importerede, `uforanderlig`, påstande) og `regen_person_visning` (1d.1-04: kun
  `afklaret` navne i cachen). Fingeraftryk `912e25df…` → `faeef822…` (`DDL_TRINB_OK`), PostgREST genindlæst.
- **Måling før og efter:** `ikke_afklaret=0 ufor_null=0 ufor_false=44 relationer=248 uden_family_id=0 ubundne=0
  afvigere=0`. Ingen data ændret. Rådgiveren: `nye=2` før og efter (5c-1's to kendte fund), ingen nye.
- **db-verify:** seeder testrækker og køres ikke mod prod. Den fulde `db-verify.sql` er grøn på en genskabt kopi af prod
  efter blokken: `TRIN_B_DECISION_FAMILY_CHANGED_UNBOUND n=0`, og RED-8-blokken (A3) bestod på prod-data.
- **Fortryd:** de fire gamle definitioner fra dumpet (runbookens opskrift, prøvet på en kopi); nødudvej fuld restore.

## 13. Placement og membership for 2018-20 (#150, trin 5c-1) — LIVE i prod (2026-10-27)

**Procedure:** `docs/runbooks/150-placement-prod.md`, privat script `~/.private/5ab-overfoersel/21-150-5c.sh`.
Repo `8ac893c5` (PR #269), GO 150 `3e69560f`; dump før skrivning `daa-prod-20261027124656-150.dump` (sha
`df49373f…`). Afgørelsesfil: `APPROVALS_OK kontrol=20 godkendt=37`.

- **DDL (GO 1):** placement-/membership-blokken (header-observationer, `private.legacy_placement_disposition`,
  placement- og membership-RPC'er, `private.placement_header_violations`). `ddl150=foer` → `DDL150_OK` →
  `ddl150=efter fase=foer`. Rådgiveren: 1 → 2 nye (`rls_enabled_no_policy|private.legacy_placement_disposition`, med
  vilje; det første er #248's `relation_reopen`).
- **Data (GO 2, kilde 1):** `FIX150_OK headers=266 placements=580 ledger=1167 memberships=576 revalideret=530` i én
  transaktion (prods `statement_timeout` 2 min; længste sætning 39,5 s). 543 maskinelt enige + 37 godkendte i 6
  kuld-grupper; 4 poster uden hovedperson-persona har placement uden membership; V-82..V-92 står `unresolved` i
  ledgeren.
- **Efter:** `MAAL_150_OK ddl150=efter fase=bundet` (0 `stale_published`, slægten `active`, memberships = placerede
  hovedpersoner med accepteret identitet). Ingen læser er ændret (5c-2). Fortryd: kun dumpet eller én post ad gangen
  (runbookens »Fortrydelse«).

## 12. Dubletreglen (#151) og #240's dobbeltfamilier — LIVE i prod (2026-10-26)

**Procedure:** `docs/runbooks/fix-240-dobbeltfamilier-prod.md`, privat script `~/.private/5ab-overfoersel/18-fix-240.sh`.
Repo `34a016f2` (PR #261), GO 240 `9e7bfa20`; dump før skrivning `daa-prod-20261026072444-240.dump`.

- **DDL:** dubletreglens blok (4 funktioner: `red_afgoer_source_persona`, `private.control_run_status`,
  `private.relation_binding_state`, `red_source_persona_queue`). **Afvigelse fra §5:** kun den sha-bundne blok, ikke
  hele `db-migrations.sql`; fingeraftryk før/efter kontrolleret.
- **Data (kilde 1):** change_set 2142 samler de 5 par (familie 11, 256, 363, 371, 372 fjernet; noter og
  vielsespåstande flyttet til 188, 282, 354, 361, 377). 7 ægteskaber afgjort og bundet (7 nye promotioner).
  Fortryd er ikke længere muligt med change_set alene (decisions #240 punkt 5); dumpet er nødudvejen.
- **Verifikation:** `MAAL_240_OK ddl151=efter fase=bundet` (= generalprøvens sha), `ADVISORS_240_OK nye=0 forsvundne=0`.
- **Opfølgning samme dag (PR #263, GO 240 `ebffa718`):** GO 2's ene dubletægteskab rettet: ægtefællen afgjort igen
  til post 753, ægteskabet bundet til familie 202 (`DUBLET_GO2_OK identitet=753 decided=1 promoted=1`). Kun data.
  Efter: `MAAL_240_OK` med uændret sha og `DUBLET_GO2 fase=efter`.
- **#248 skridt 1 samme dag (PR #265, GO 248 `cc3d684e`; dump `daa-prod-20261026124140-248.dump`):** to
  navnefælle-ægtefæller afgjort igen (624 → 625, 744 → 745); de to forkerte bindinger på familie 64/193 gælder ikke
  længere, søskendeægteskaberne er urørte. Kun data. `FIX248 fase=foer` → `FIX248_IDENTITET_OK` → `fase=efter`.
  Ægteskaberne står `accepted` uden binding til rute A (genåbning) er i prod.
- **#248 rute A samme dag (PR #267, GO 248A `d910500c`; dump `daa-prod-20261026152510-248a.dump`):** DDL'en
  (`private.relation_reopen`, `red_genaabn_relation_interpretation`, vagten i `relation_binding_state`, `post_rivals`)
  og derefter de to ægteskaber genåbnet, afgjort og bundet til familie 65/194. `ddl248a=foer fase=efter` →
  `DDL248A_OK` → `FIX248A_GENAABN_OK genaabnet=2 afgjort=2 bundet=2` → `ddl248a=efter fase=bundet`. Rådgiveren: +1
  `rls_enabled_no_policy` (`private.relation_reopen`, med vilje). `18-fix-240.sh maal` melder nu `ddl151=ukendt`
  (DDL'en omdefinerer `relation_binding_state`); ikke drift.

## 11. 5a+5b's data for 2018-20 (#151) — LIVE i prod (2026-10-25, GO 2)

**Kilde 1's identitets- og relationslag.** Arbejdskørsel 3's pakke (`46f5d1e5…`, 25 skridt) genspillet i prod: profil og
personas, kandidater, kontrolstikprøve og -ark, korroboration, afgørelser og bindinger (2a, 2b-i, kø, 2b-ii, v3),
ægtefælle-dispositioner, P-afvisningen og børnehenvisninger (2b-iii). Ingen nye kanoniske personer.

**Procedure:** `docs/runbooks/transfer-5ab-data-prod.md`, private scripts `~/.private/5ab-overfoersel/`.

- **Repo:** `8f52969d`. **GO 2-fil:** `4bd78fa9…` (efter første forsøgs `STATEMENT_TIMEOUT` ved skridt 3; runbookens
  afsnit 9).
- **Verifikation:** `VERIFY_OK measure_sha256=92a609f5…` (alle nøglede digests = pakkens slut, kanonisk baseline =
  D1's, uberørte tabeller og andre kilder uændrede, `anon`-matrixen = D1's), `authorizations_issued=1`.
- **Advisors (security, CLI):** 60, uændret fra GO 1 (`ADVISORS_DATA_OK nye=0 forsvundne=0`).
- **Tal (kilde 1; = pakkens slut, bekræftet af `VERIFY_OK`):** bindinger 622 → 874, `public_family_sources` 0 → 252, personas og identiteter 587 → 832,
  fortolkninger 4.415 → 4.669, dispositioner 1.747 → 1.878, kandidater 2.327, kontrolstikprøve 30.
- **Kendt afvigelse:** ét ægteskab står som forslag uden binding (dubletreglen, 5b §23.4). Reglen er rettet i prod
  2026-10-26 (§12); selve ægteskabet afgøres separat.
- **Skrivepausen** er slut (`FREEZE_END_OK mode=verify`); webfladen er åben for redigering igen.
