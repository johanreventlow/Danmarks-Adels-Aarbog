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

## 27. Trin 6d-3: 1939's relationer, dobbelt ægtefælle og 1791 — LIVE i prod (2026-11-11)

**Grundlag:** decisions 2026-11-10 (6d-3's afgrænsning), spec `2026-11-10-trin6d3-relationer-design.md`, runbook
`docs/runbooks/trin6d3-prod.md`. PR #315 merget som `6d77d46d`. Privat runner `~/.private/5ab-overfoersel/36-trin6d3.sh`
(sha `608af06a…`) med bundet pakke `~/.private/6d3/prod-pakke/`; R i **replay** mod generalprøvens items. Projektejeren
kørte alle trin i sin shell (klassifikatoren afviser også læsetrin mod prod); sessionen læste kvitteringerne.

- **DDL** (GO `56074c10`): `private.relation_persona_profile` (4 seeds `4:f87b9679…`, RLS, ingen rettigheder til
  PUBLIC/anon/authenticated/service_role), tekstfoldning (`relation_fold_raw_text`, `relation_ordered_windows`,
  `relation_text_form`, `relation_name_compare_text`) og ægteskabsnummer; 9 funktioner, alle med `search_path` og
  `REVOKE`. 1939's ægteskaber uden position 59 → 10. `get_advisors` kunne ikke køres (MCP'en ser ikke DAA-projektet);
  RLS, `search_path` og grants er tjekket statisk og af runneren (`T6D3_GRANTS` alle `-`).
- **Data** (GO `b43349c9`, under meldt frys): D 42 `samme_som` (`links=42 ingen=0`, dobbelt 42 → 0, `samme_som`
  720 → 762); O `privat=2` (1791 og 1795); R: persona-batch 115 elementer, kandidater 1096, kontrol 22 kort (passed),
  korroboration 46, afgørelser 68, bindinger **69** (68 ægteskaber + 1 forælder). Forslag for kilde 3 (ægteskab/forælder/
  barn) 271/6/4 → 203/5/4 `proposed`.
- **Ubundne ægteskaber pr. årsag** (af 271): parkeret i udtrækket 161 (`navn_uklart` 89, `partner_ligner` 52,
  `navn_afkortet` 8, `intet_vindue` 6, `flere_klausuler` 6); ikke egnede efter kandidatkørslen 42 (`name_or_rank` 22,
  `count_mismatch` 20). Børn 4 (`praedikat_ikke_i_profil`, kræver `relation-child-v1`). En stikprøve på 20 af de 161
  viste 19 rigtige match (grundlag for en 1939-navneregel, backlog).
- **Uændret:** kilde 1's `K1_ORD` `1857a95c…` og `K1_BIND` `9e0db348…` i alle faser; familiekilderne
  `b217ebfd…` → `06e71a11…` (præcis som på alle stand-ins).
- **Vagten** er en kæde af fulde aftryk, hvor hvert skridt kun må ændre sine målte tabeller (9 aftryk, ingen fremmed
  skrivning). Fortrydelsens grundlag er ddl-dumpet `daa-prod-20261111213132-6d3.dump` (restore-hash `5ed3f37a…`) og
  foer-dumpet `daa-prod-20261111204138-6d3.dump` (`b23c1de6…`). Efter `VERIFY_OK` er rettelser almindelig redigering.
- **Tid i prod:** DDL 18 s, D 9 s, O 2 s, R 330 s. Tidsbudget OK; første `anon` efter DDL brød på `famsrc_364`
  (100 mod 93 ms, prod-støj), genmålt OK (77 ms).
- **Browsertjek som anon** (projektejeren): »DAA 1939« på ægteskaber hos sammenfoldede personer (81, 612); D-par 88,
  97, 99, 133 med én ægtefælle; 815/816 én ægtemand; 1791/1795 ikke synlige.
- **Fundet ved browsertjekket:** 612 viser stadig to ægtemænd, fordi 1939-hovedpersonen 955 (»Claus [Reventlow] til
  Gaarz«) ikke er koblet til 2018-20's 75 (Nicolaus), mens ægtefællen 1474 → 612 er. Det omvendte af D's tilfælde;
  før 6d-3, backlog (decisions 2026-11-11).

## 26. Trin 6d-2b: fire forkert tilskrevne 1939-tekster trukket tilbage — LIVE i prod (2026-11-10)

**Grundlag:** decisions 2026-11-10 (6d-2b indsnævret). Ingen DDL. Den eksisterende redaktørhandling
`red_tilbagetraek_legacy_narrative` blev kaldt fire gange i én transaktion af den private runner
`~/.private/5ab-overfoersel/35-trin6d2b.sh` (sha `c994eae27592f64f…`; trin `maal`, `apply --jeg-mener-det`, `verify`,
`fortryd --jeg-mener-det`). Aktøren er projektejerens redaktørkonto (`b2/aktoer.txt`, hash-verificeret). Sessionen kørte
alle trin efter projektejerens udtrykkelige ønske.

- **Fastlåst indhold:** narrativ 598 (person 929), 603 (934), 1165 (1791) og 1169 (1795), hver med tekstens sha256 og
  status `grandfathered_publication`. 1939's synlige narrativer (`person_daa_narrative_publication_allowed`) var før 569
  (id-mængde sha `298d147c…`), forventet efter 565 (`b39c08c0…`). Prod svarede præcis det ved `maal`.
- **Generalprøve** på stand-in `daa5ab_ddl_standin_20261110171715_6d2b` (kopi af `6d2afb` = prod efter 6d-2a): apply →
  verify → en anden apply afvist (`T6D2B_FOER_VIS`) → fortryd (samme 569-mængde) → apply → verify. To fejl fanget og
  rettet før prod: `SELECT SELECT` i plpgsql og `NARRATIVE_RECORD_FOREIGN_CHANGE_SET` (change_set nulstilles mellem
  kaldene).
- **Prod:** `T6D2B_MAAL_OK` → `T6D2B_APPLY_OK` → `T6D2B_VERIFY_OK`: de fire står som `withdrawn`, 4 aktuelle
  `legacy_withdrawn`-events (begrundelse `6d-2b: …`), 565 synlige med den forventede mængde. Transaktionen tjekkede også,
  at der kom præcis 4 change_sets.
- **Fortrydelse:** `35-trin6d2b.sh fortryd --jeg-mener-det` (bevist på stand-in) fortryder de fire aktuelle events med
  `red_fortryd_person_narrative_publication_event`. Teksterne er ikke slettet.
- **Ikke rettet her (6d-3):** levnspersonen 1791 er stadig offentlig og står som `partner` i familie 742 og 743.

## 25. Trin 6d-2a: oversigtsreglen og 1939's sidste identitetssager — LIVE i prod (2026-11-10)

**Procedure:** `docs/runbooks/trin6d2a-prod.md`, privat runner `~/.private/5ab-overfoersel/34-trin6d2a.sh` (sha
`0d22fd46…`, med `34-trin6d2a-vindue.sql`). Repo `ca4edb4e` (`main` med PR #312; blokkens sha `dfaaf9dacebdcac2…`,
`db-rls.sql` `16ac093b…`). To skrivende ceremonier, kørt af projektejeren; læsetrinnene kørt af sessionen.

- **Før:** `fase=foer kanter_par=0 unresolved=1 uden_identitet=2`, `KOORD_2018_20=99a5a2de04b1b9219631a1e53b53d415`,
  `KOORD_SRC=2136dfc066fd41d789ea32a7405239f9`, BIO `3177a5d1…` (= slut-generalprøven). Tidsbudgettets basis som anon
  (median af 3): `bio_alle` 12.679 ms, koordinater 1.253 ms, `public_person_facts` 134-160 ms, `public_family_sources`
  93-117 ms.
- **Dump før DDL (B1):** `daa-prod-20261110131506-6d2a.dump`, 19.449.033 bytes, sha
  `69cc587194d05f1226982d14cfa180870b376d82e2c7cc7eaf44d82f467b6305`; age
  `0bbe53a0393daea3b3a867a5ca14846e0cb41b6b412e9597442aa2eeed5319f0` (SFTP, rundtur ok).
- **DDL (GO `41981aa8`):** `T6D2A_APPLY_DDL_OK tilstand=ddl blok=dfaaf9dacebdcac2`, 24,7 s; katalogaftryk
  `8d269e5ee1150960`. Nye `private.overview_mention_narratives(bigint[])`, `private.samme_som_data_direction(bigint,bigint)`
  og `public.red_overview_mentions(bigint[])` (kun `authenticated`); ændrede `public_person_bio_source_versions(_v2)` og
  `red_samme_som`. Claude Code flyttede kommandoen i baggrunden efter 120 s; en anden kørsel imens stoppede på
  `T6D2A_FOER_DDL` (fase allerede `ddl`) uden at skrive.
- **Efter DDL:** `fase=ddl regel=10 synlige_anon=9 bio_oversigt=0`, KOORD og FAKTA uændrede, BIO `de88b746…`.
  `T6D2A_ANON_BUDGET_BRUDT` på `bio_alle` (25.123 og 24.858 ms i to kørsler; stand-in'erne viste +2-8 %). Personsidens
  kald (én persons id'er) målt efter data som anon i browseren (`/person/134`): 339, 209 og 487 ms, alle `200`; hele
  siden 5,62 s. Projektejeren valgte at fortsætte (decisions 2026-11-10).
- **Advisors** (dashboardet, projektejeren, kun *security*; *performance* ikke set): ingen før-liste at diffe mod, så
  vurderingen bygger på DDL'ens objekter. Blandt dem optræder kun `red_overview_mentions`
  (`authenticated_security_definer_function_executable`, forventet som de øvrige `red_*`); de to nye `private`-funktioner
  optræder ikke. `anon`-fundene er 11 offentlige læsere (to af dem, biografilæserne, ændret af DDL'en, var anon-kaldbare
  før); DDL'en oprettede ingen tabeller. `auth_leaked_password_protection` er en Auth-indstilling uden for 6d-2a.
- **Dump før data (B1, fortrydelsens grundlag):** `daa-prod-20261110135430-6d2a.dump`, 19.456.941 bytes, sha
  `07b86122de69102a23c77747d2c401f45d1f0200824aecb7f74147b62952e997`; age
  `f968648926ab7ee365f4cb7809ca407deb1a7dd4ea63d7e1b58eec868d45d033` (SFTP, rundtur ok; første forsøg `SFTP_FEJL`
  »Connection closed«, genkørt).
- **Data (GO `fb102458`):** `identitet_ceremoni.sql` (src=3) i én transaktion: `T6D2A_OK kanter=1 identiteter=3
  regel=11`, 14 sætninger, langsomste 37,2 s, i alt 105,3 s; `T6D2A_APPLY_DATA_OK fase=data tal=11,9,0,1,0,0
  fakta=uaendret bio_aendret=nej`; vinduesaftryk efter ceremonien `6b58ffd3d3dec892`.
- **Verify:** `T6D2A_VERIFY_OK tal=11,9,0,1,0,0`, KOORD og FAKTA som ddl-dumpet, BIO `de88b746…`. Budgettet stadig brudt
  på `bio_alle` alene (25.941 ms); de øvrige kald inden for.
- **Karantænetjek (B1, decisions 2026-11-10):** prod-dump-kopi `b5b4dd9d…` på stand-in `6d2afb` (samme `maal` som prod);
  appens `collapseSameAs` på anon-data: 715 afklarede kanter, 9 karantænegrupper (som før). De 11 oversigtspar: 9
  synlige oversigtspersoner foldes ind i detaljepersonens kort, 967 og 1014 er `staged` (intet anon-kort), 1048's kort
  er 134; ingen detaljeperson i karantæne. Alle 11 detaljepersoner leverer én kilde 3-biografi som anon.
- **Fortrydelse:** `fortryd` med data-dumpet (restore), så med DDL-dumpet; kun under meldt frys og så længe intet andet
  er skrevet (vinduesvagten stopper ellers).

## 24. Trin 6d-1: 1939's placements og medlemskaber — LIVE i prod (2026-11-09)

**Procedure:** `docs/runbooks/trin6d1-prod.md`, privat runner `~/.private/5ab-overfoersel/33-trin6d1.sh` (med
`33-trin6d1-vindue.sql`). Repo `997a033c` (`main` med PR #310; blokkens sha `217b3f44…`, `db-rls.sql` `e63c2182…`).
To skrivende ceremonier, kørt af projektejeren. Færdigbevis: `docs/evidensbaseret-genimport/placement-6d1-prod.md`.

- **Før:** `fase=foer`, ledger 576 `retained_legacy`, 563 publicerede, `KOORD_2018_20=99a5a2de04b1b9219631a1e53b53d415`,
  `KOORD_SRC=2136dfc066fd41d789ea32a7405239f9` (som prod-dumpet `1653c8f7…`, generalprøvens grundlag).
- **Dump før DDL (B1):** `daa-prod-20261109160931-6d1.dump`, 18.543.034 bytes, sha
  `9cb986029ab735cd06316b9d87d522e1fcb6e45be660fb5b47e542bdb8d17d18`; age
  `cd91ec4ed8d3696426c0715bd9ed293b0f832af4eee1e76186a54f3a168009ed` (SFTP, rundtur ok).
- **DDL 6d-1 (GO `c8f09536`):** `T6D1_APPLY_DDL_OK tilstand=ddl`, 14,0 s. Nye `private.membership_component_states()`
  og `private.placement_human_header_levels(bigint)`; ændret `record_legacy_disposition` (mapped via identitet),
  `placement_header_violations`, `red_promote_placement_memberships` (vagt mod fremmed kildes grundlag) og
  `public_person_source_coordinates` (placement kun ved entydige `(entry, printed_number)` pr. kilde). Grant-matrix
  `---------xxx`; alle fast `search_path`. `get_advisors` ikke kørt (MCP'en på en anden organisation).
- **Dump før data (B1, fortrydelsens grundlag):** `daa-prod-20261109162937-6d1.dump`, 18.549.753 bytes, sha
  `9e628a58462063856efea2eb82a47bc54003ae92d7117d9303535827d117b460`; age
  `0748e114d01ff9c7c95256191544d991564c4478b0a1d17c20b5e996de8f562c` (SFTP, rundtur ok).
- **Data (GO `79609895`):** `placement_ceremoni.sql` (src=3) i én transaktion: linjeskema 8 entries, 138 overskrifter,
  528 record- og 528 persona-placements, ledger 528 `mapped` + 48 `retained_legacy`, 528 linjemedlemskaber, 528
  revalideret. `tal=8,528,528,528,48,528,563,0,441,3`, 129 s (langsomste sætning 21,6 s). `verify` grøn.
- **Læseren:** 2018-20's og 1939's koordinatrækker byte-ens (1939 vises fra legacy indtil 6e). Koordinat-RPC'en som
  anon 526-574 ms → 1.231-1.285 ms.
- **B6:** 441 `corroborated` (to kilder, samme linje), 3 `conflict` (åben backlog).
- **Fortrydelse:** `fortryd` med data-dumpet (restore), så med DDL-dumpet; kun under meldt frys og så længe intet andet
  er skrevet (vinduesvagten stopper ellers).

## 23. Trin 6c-3: 2018-20's A6b-rest (tekstrevision og genbinding) — LIVE i prod (2026-11-08)

**Procedure:** `docs/runbooks/trin6c3-prod.md`, privat runner `~/.private/5ab-overfoersel/32-trin6c3.sh` (med
`32-trin6c3-vindue.sql`). Repo `bdcb4184` (`main` med PR #305, #307 og #308; blokkens sha `1e8d9553…`, `db-rls.sql`
`e63c2182…`). To skrivende ceremonier, kørt af projektejeren. Færdigbevis:
`docs/evidensbaseret-genimport/kildetekst-revision-6c3-prod.md`.

- **Før:** `tilstand=foer` (`andre=049163332f67…`, personas 1.395), som prod-dumpet `890d7f49…` generalprøverne er
  lavet fra.
- **Dump før DDL (B1):** `daa-prod-20261108183045-6c3.dump`, 18.400.483 bytes, sha
  `9f3d72f6afd0b649aa7ab9d15cf70c1521bfcb7a362da5e356045048b65ef415`; age
  `fb421c1f36efa5af778fa4f05ab643824e90867a01e403e9a18c76e596a157fe` (SFTP, rundtur ok).
- **DDL 6c-3a (GO `432b5680`):** `T6C3_APPLY_DDL_OK tilstand=ddl`, 11,9 s. Ny tabel `private.text_revision_reconciliation`
  (append-only, RLS, ingen grants) og writeren `private.write_text_revision_reconciliation`; ændret
  `write_relation_persona`, `relation_binding_state`, `verify_relation_persona_receipts`, `persona_family_context`,
  `spouse_principal_person` (alle DEFINER, fast `search_path`, ingen EXECUTE for API-roller). `get_advisors` ikke kørt
  (MCP'en på en anden organisation); grants kontrolleret af runneren i prod, lint på stand-in `c3h`.
- **Dump før data (B1, fortrydelsens grundlag):** `daa-prod-20261108184046-6c3.dump`, 18.430.410 bytes, sha
  `d22ffbfae5a93de727400138fb32b4b6429035ce96f0f1f8b9750f7ae1832a24`; age
  `f1ad7f6c3d91c5837530046b0d624a6f948a9bac28e960a9910b87ed63a3950e` (SFTP, rundtur ok).
- **Data (GO `1b94d057`):** revision (10 tekstversioner, 58 nøgler `superseded`) → 75 nye forslag → parter (3
  ægtefælle-personas genbrugt, 0 nye) → afstemning → kontrol (afgrænset til de 75) → 13 faktaafgørelser, 4
  forælder-, 1 barn-, 3 ægteskabsafgørelser → 16 nye promotions → kvittering 74 rækker. `tal=1,58,10,75,15,1395,13,4,1,3,16,74`,
  168 s. `verify`: `genbundet=14 genfundet=30 ikke_genfundet=28 tilbagetrukket=2`, `andre` uændret.
- **Læseren:** fakta bundet 9 → 8 (1 tilbagetrukket vises som import), familiekilder 7 → 6; narrativ- og
  publiceringshash uændrede. Anon-stikprøver via API: 8 fakta med »DAA 2018-20 · <post>«, alle 6 familier med kildelinje.
- **Fortrydelse:** `fortryd` med data-dumpet (restore), så `fortryd` med DDL-dumpet; kun så længe intet andet er skrevet
  i prod (vinduesvagten stopper ellers).

## 22. Trin 6m del 2: 1939's faktaforslag rettet efter bogen — LIVE i prod (2026-11-07)

**Procedure:** `docs/runbooks/trin6m-del2-prod.md`, privat runner `~/.private/5ab-overfoersel/31-trin6m-del2.sh`. Repo
`74bb00e7` (`main` med PR #303, merge-commit ved head `19fc05af`; blokkens sha `e191f1d4…`, `db-rls.sql` `e63c2182…`).
To skrivende ceremonier (DDL 6m-a, så data A), kørt af projektejeren. Beslutning: decisions 2026-11-07.

- **Før:** tilstand d efter del 1 (`25,0,0,0,1106,1106,83,1`, `k1` `d5bedf7d…`), `ddl_6ma=0`.
- **Mål og klasser (læse-kun):** 241 markerede faktaforslag (`maal-a` sha `427c8541…`); `klasse-a` VERSION 56, BIND 23,
  RET_OG_BIND 14, SPÆRRET 4, rapport 144 (= de foreløbige tal fra prod-kopien), manifest `2f0ce6c5…`. Projektejerens
  samlede F (79, VERSION+BIND) og F på de 14 kort; ark `189d998e…`, `apply-a.sql` byte-ens med øvelsen på stand-in `_6m3`.
- **Dump før DDL:** `daa-prod-20261107190023-6m2.dump` (sha `8b2f1231…`, age `f302b777…`, SFTP-rundtur ok).
- **DDL (GO 6m2-DDL `78b268f0`):** `T6M2_APPLY_DDL_OK ddl_6ma=1 tilstand=d`, 16,9 s; `k1` uændret. Blokken opretter
  ingen tabeller: `red_ret_forslag` (DEFINER, fast `search_path`, kun `authenticated`), `private.kontroller_forslag_binding_v1`
  (låst for alle roller), ny `red_decide_interpretation` og constraint-triggeren `interpretation_forslag_binding`.
  `get_advisors` ikke kørt (MCP'en var logget ind på en anden organisation); grant-sættet gennemgået statisk.
- **Dump mellem DDL og A:** `daa-prod-20261107194057-6m2.dump` (sha `76b5c7e9…`, age `6ce12cac…`, SFTP-rundtur ok,
  `ddl_6ma=1`) — restorepunktet for `fortryd`.
- **Ceremoni A (GO 6m2-A `9b8c7c0b`):** ark `BIND:F=23 RET_OG_BIND:F=14 VERSION:F=56`, 93 kald til `red_ret_forslag`
  og 14 til `red_ret_paastand`; `T6M2_APPLY_A_OK versioner=93 rettelser=14 afgoerelser=37 bundet=37 bindinger_k=1136`,
  `vejb=t`, `tal=25,0,0,0,1136,1136,97,1`, 35,4 s. `bindinger_k` 1.106 → 1.136 (= 1.106 − 7 genåbnede + 37), rettelser
  83 → 97, `k1` `d5bedf7d…` uændret. Uafhængig `verify-a`: `T6M_VERIFY_A_OK` med samme tal.
- **Læseren:** projektejeren så tre stikprøver blandt RET_OG_BIND (person 956 navn, 1080 fødsel, 1228 titel): den viste
  værdi er den godkendte nye værdi, bundet til bogens post med DAA 1939-side inden for kortets sider.
  Sidefund: 1080's datogrænser er hele året 1746, fordi `validate.derive_date_info` ikke afgrænser formen
  »8 Okt. 1746« (kun »8. okt. 1746«); den gamle påstand havde de samme grænser, og 7 af del 2's 9 rettede datoer har
  årsgrænser. Omfanget for 1939's datoer er ikke målt.
- **Fortrydelse:** `fortryd` (restore af dumpet mellem DDL og A), så `fortryd-ddl`; kun indtil der skrives noget nyt i
  prod (runbookens »To ceremonier«).

## 21. Trin 6m del 1: 1939's læsertekst rettet efter bogen — LIVE i prod (2026-11-07)

**Procedure:** `docs/runbooks/trin6m-del1-prod.md`, privat runner `~/.private/5ab-overfoersel/30-trin6m.sh`. Repo
`23545c6b` (`main` med PR #301; to decisions-commits fulgte i en opfølgnings-PR). Én skrivende ceremoni, kørt af
projektejeren. (6c-2's ceremonier 2026-11-05/06 mangler endnu deres afsnit her; se `docs/evidensbaseret-genimport/status.md`.)

- **Før:** tilstand d (6c-2's tal `25,0,0,0,1106,1106,83,1`, `k1` `d5bedf7d…`), 1939-narrativernes hash `659b9242…`.
- **Eksport (læse-kun, 10,9 s):** 592 poster, 2.774 forslag, 563 record-bundne narrativer (561 med `publish_revision`),
  13 ubundne; sha `707a2732…`, byte-ens med stand-in'en.
- **Modelgennemgang:** 24 Opus-underagenter à 25 poster med sidebilleder (88 sider, 150 dpi); 592/592 poster og
  2.774/2.774 forslag besvaret. 651 tekstrettelser, 595 svarbare grupper, 142 i tvivl, 6 grænserettelser, 39 på poster
  uden revisionsret; 241 markerede faktaforslag og 1.121 »manglende fakta« til del 2.
- **Projektejerens svar:** 606 L (side 1-8 klikket enkeltvis, side 9-15 ved samlet beslutning; decisions 2026-11-06),
  ark `1426cb0b…`, manifest `fc9651e2…`.
- **Dump:** `daa-prod-20261107105651-6m.dump` (sha `dfc276e3…`, age `e3e6a66c…`, SFTP-rundtur ok), restore-hash
  `2d5233f9…`, `change_set` max 2767.
- **Ceremoni B (GO 6m-B `2351fc44`):** `red_revider_publiceret_person_narrative_record` pr. post med eksportens
  `state_sha256`; `T6M_APPLY_B_OK poster=268 lig=268 alle=563 afvig=0 tal=25,0,0,0,1106,1106,83,1`, 34,9 s;
  narrativernes hash `0fc9ccb6…` = øvelsens. Uafhængig `verify`: `VERIFY_B poster=268 lig=268 alle=563 afvig=0`.
- **Læseren:** projektejeren så tre stikprøver (person 1044, 1366 og 1356) med de rettede tekster.
- **Fortrydelse:** fra dumpet med apply-kvitteringen, kun indtil der skrives noget nyt i prod (runbookens »Fortrydelse«).

## 20. 6b's ceremoni C efter retning 2: 1939's identiteter — LIVE i prod (2026-11-02)

**Procedure:** `docs/runbooks/trin6c1-prod.md` »Ceremoni C«, private scripts `~/.private/5ab-overfoersel/28-trin6c1-c.sh`,
`28-trin6c1-c.R` og `28-trin6c1-c-fortryd-ddl.sql`; kortværktøjet `28-c-kort.sh` med `c-kort/`. Repo `c8d1e2a2`
(`main` med PR #293). Tre GO'er, kørt af projektejeren. Ingen dump (C fortrydes med `reverse-c`).

- **Før:** `T6C1_MAAL tilstand=b forslag_k3=2774 poster_k3=494 identiteter_k3=8 afventer=555`, `k1` `a9e32b70…`.
  Prods faktor for C's tunge læsning målt forinden (`maal-input`: 22,8 s mod 10,0 s, samme `input_sha256`).
- **C's DDL (GO 6c1-C-ddl `9ec87157`):** blokken `-- ===== trin 6c-1 retning 2: …` til slutningen af
  `db-migrations.sql` (sha `ccdfe4ac…`) + `db-rls.sql` i én transaktion, `NOTIFY pgrst`. `T6C1_R2_APPLY_DDL_OK
  foer=enig efter=auto funktioner_foer=cf4bef04d86b774a funktioner_efter=517acdea94acad49 tilstand=b`, 21,4 s, `k1`
  uændret. Aftrykket dækker `pg_get_functiondef` **og** `proacl`; i prod ejer `postgres` funktionerne, på stand-in'en
  den lokale rolle, så tallene kan ikke sammenlignes med øvelsens (`1aaaf0d7…`/`597eab91…`). Læse-kun kontrol
  (`28-r2-aftryk.sh`): definitionerne alene `d098d380039e7895` = øvelsens, 6 funktioner, `acl=postgres=X/postgres`
  (ingen `anon`/`authenticated`). `fortryd-ddl`'s mål i prod er `cf4bef04…`. Security Advisor (projektejeren, efter DDL og C): intet fund
  nævner retning 2's seks private funktioner; fundene er de kendte fra §19 (11 `anon_security_definer_function_executable`
  på læserfunktionerne, `authenticated_…` på `public.red_*`/`current_rolle`/`hist_*`, `rls_enabled_no_policy` på
  eksisterende tabeller, `auth_leaked_password_protection`); ingen `function_search_path_mutable`.
- **Control (GO 6c1-C-control `0e4e5cc4`):** kandidatkørsel `8d2ab8a4`, `input_sha256=7f783822…` (21,7 s),
  `candidates_sha256=a2e80259…`, 2.032 kandidatrækker, `control_sha256=871b21f8…`. Udfald som øvelsen: `enig` 31,
  `svag` 273 (191/64/18), `ingen_kandidat` 153, `uenig` 8 + `egen_ikke_kandidat` 45, `navnefaelle` 51; **124 kort**
  (119 nye + 5 eksisterende, stikprøve 20).
- **Render og kortgennemgang:** 5 ark (`details_sha256=eee13550…`, 23,2 s). De renderede tekstkort kunne ikke afgøres
  af et menneske (kun fornavn, »?–?«, intern record-id). Kortværktøjet (`28-c-kort.sh kontekst`, læse-kun, 8-9 s)
  hentede for kortenes 124 bindinger og 461 personer: 1939-postens tekst, sidetal (496-598) og bogteksten omkring
  posten (sammensat af renditionens forekomster), forældre/ægtefælle/børn og tekster fra andre udgaver, og byggede en
  lokal HTML-side (ingen udfald eller stikprøve vist). `28-c-kort.sh flet` skrev svarene ind i arkenes P-linjer
  (round-trip byte-ens med øvelsesarket på stand-in'en). Svar: 123 S (ingen `S <id>`), 1 F, 0 U.
- **Manifest:** `elements=553 dispositions=8 eksisterende_ikke_S=0`, `rows_sha256` = control, svar `enig:-` 28,
  `enig:S` 3, `svag:-` 260, `svag:S` 11, `ingen_kandidat:-` 146, `ingen_kandidat:S` 6, `navnefaelle:S` 48,
  `uenig:S` 50, `uenig:F` 1; dispositioner `allerede_persona` 3 + `allerede_persona:S` 5. Stikprøven 20 af 20 S.
- **C (GO 6c1-C `df185473`):** `T6C1_C_TAL elementer=553 publication_binding=454 human_S=98 human_F=1 human_U=0
  accepteret=552 stikproeve=20 identitet_som_kvittering=553 anden_person=0`; `T6C1_C_KONTROL b_personas=555
  afventer=0 staged=2 staged_i_koe=2 koe_foer=8 koe_efter=563 eksisterende=8 eksisterende_uaendret=TRUE
  pubstate_n=563 pubstate_uaendret=TRUE`; replay `already_applied samme_batch=TRUE`; batch `2e6be372`.
  Efter: `T6C1_MAAL tilstand=c forslag_k3=2774 poster_k3=494 identiteter_k3=560 afventer=0`, `k1` uændret.
- **F'et:** én persona (en oversigtspost om linje B, hvis tolkning er stamfaderen †1690, men hvis C3-binding peger på
  barnebarnet †1773) står `unresolved` med `reason='publication_binding_disputed'`. Narrativet er stadig publiceret
  på barnebarnet. Projektejeren 2026-11-02: den bliver stående til 6c-2, hvor bindingen rettes (til stamfaderen eller
  linjen) i stedet for at trække teksten tilbage (teksten nævner barnebarnet, og en tilbagetrækning skulle publiceres
  igen bagefter).
- **Fund til efter C:** 13 af de 576 personer med 1939-id har én `navn`-påstand med `vaerdi_tekst` NULL, så
  `visning_navn` er tom (publicerede, afdøde; fx person 1785); 10 stod på kortene. Rettes med nye navnepåstande
  (invariant 1). Oversigtsposter (»A) …«, »B) …«) nævner flere generationer, men fik én person ved indlæsningen.
- **Ydelse (prod mod øvelsen r2):** `apply-c` 159,2 s (dry-run 159,1 s; i alt 326,5 s) mod 34 s i alt; writer-elementerne
  135 s i alt (maks. 2,6 s) mod ca. 5 s (ca. 27×); finalize 19,6 s mod 9,6 s (2×); det første automatiske element 2,6 s
  (skønnet 31 s). Ingen sætning nærmede sig 2 min.
- **Fortryd:** `go-reverse-c` → `reverse-c` (C's identiteter `superseded`, tilstand `b`); derefter C fra `control`.
  Retning 2's DDL fortrydes kun i tilstand `b` med `fortryd-ddl`. B kan ikke længere fortrydes ved restore.

## 19. Trin 6c-1 ceremoni A og B: forslagswriteren følger helpost-reglen og 1939's forslag — LIVE i prod (2026-11-02)

**Procedure:** `docs/runbooks/trin6c1-prod.md`, private scripts `~/.private/5ab-overfoersel/27-trin6c1.sh`,
`27-trin6c1-b.R` og `27-trin6c1-vindue.sql`. Repo `20fc2278` (`main` med PR #290 og #291). To ceremonier med hver sin
GO, kørt af projektejeren. 6b's ceremoni C (identiteterne) er ikke kørt; den venter på projektejerens retning 2
(2026-11-01: C3's binding bliver identiteten; kun konflikter og en stikprøve på kort), som endnu ikke er bygget.

- **Før:** `T6C1_MAAL tilstand=foer forslag_k3=0 poster_k3=0 identiteter_k3=8 afventer=555`, 2018-20's forslagsdigest
  (`k1`) `a9e32b70…`, 2,2 s; `T6C1_DEFACL` 0/0/0.
- **Ceremoni A (DDL, GO 6c1-A `9c69fec2`):** blokken fra `-- ===== trin 6c-1: forslagswriteren følger
  helpost-reglen =====` til slutningen af `db-migrations.sql` (sha `20615bb6…`) og `db-rls.sql` (`f517b2e5…`) i én
  transaktion, derefter PostgREST genindlæst. `private.write_interpretation_proposal` erstattet (helposten vælges med
  helpost-reglen og profilens helpost-slags); data: kun profilrækken `daa-1939-interpretation-proposal-v1` (kilde 3,
  sha `c6131dcc…`). Dump før: `daa-prod-20261101221444-6c1.dump` (sha `198712b4…`, ekstern `age`-kopi `1eff634a…`,
  rundtur ok; 103,8 s). Kvittering: `T6C1_APPLY_A_OK tilstand=a tal=0,0,8,555`, `k1` uændret, 22,5 s.
- **Rådgiver (skridt 5):** Security Advisor i dashboardet efter A (intet før-billede; fundene holdt op mod blokkens
  objekter, som ved 6a og 6b). Blokken indeholder kun `private.write_interpretation_proposal` (privat skema, REVOKE'et
  fra alle) og profilrækken; intet fund nævner dem. Fundene er de kendte: 11 `anon_security_definer_function_executable`
  på læserfunktionerne (`entitet_offentlig`, `person_offentlig`, `public_person_facts` m.fl.), de forventede
  `authenticated_security_definer_function_executable` på `public.red_*` og `current_rolle`/`hist_*`,
  `rls_enabled_no_policy` på eksisterende tabeller (ingen ny tabel) og `auth_leaked_password_protection`. Ingen
  `function_search_path_mutable`.
- **Ceremoni B (data, GO 6c1-B `2a2ba22b`):** `manifest-b` gav øvelsens tal: 494 elementer, 2.774 forslag (2.127
  `principal`, 647 `other`), 2.799 citater på 682 klausuler, ledger `cbed2e7f…`, klausulsæt `e8faa166…`, forslag
  `64c6f6a1…`, indhold `9208596e…`, runner-manifest `6dc5be16…`; alle 25 prædikattal som runbookens. Fortrydelsens
  dump i tilstand `a`: `daa-prod-20261102060018-6c1.dump` (sha `fc15557a…`, ekstern `3f871040…`, rundtur ok; 94,8 s);
  mål `vindue=186bf8c5…`, 132 linjer, `restore_hash=77b1c196…`, `katalog=fccfbd55…`, 0 forældreløse (28,3 s).
  `apply-b`: ledgeren genberegnet mod prod før dry-run og efter commit, begge byte-ens med den bundne
  (`records=592 eligible=500 excluded=92`); klausulsættet genberegnet i dry-run, apply og replay (`e8faa166…`);
  `T6C1_B_DRYRUN status=finalized`, `T6C1_B_COMMITTED`, `T6C1_B_KANONISK fact=7193->7193 assertion=9306->9306
  uaendret=TRUE`, `T6C1_B_KONTROL koersler=1 forslag=2774 principal=2127 other=647 proposed_v1=2774 citater=2799
  klausuler=682 poster=494`, dispositioner `afventer_identitet=433 fortolkning_foreslaaet=249`,
  `T6C1_B_FORVENTNING som_skrevet=TRUE`, replay `already_applied`, forslagsdigest for kilde 3 n=2.774 `8eadf701…`
  (= øvelsens); `T6C1_APPLY_B_OK tilstand=b tal=2774,494,8,555`.
  Efter: `T6C1_MAAL_OK tilstand=b forslag_k3=2774 poster_k3=494 identiteter_k3=8 afventer=555`, `k1` uændret,
  `T6C1_DEFACL` 0/0/0.
- **Læser og redaktør:** forslagene er private (`proposed`) og vises ingen steder, før de afgøres (6c-2). Kanoniske
  data er uændrede.
- **Ydelse (prod mod slutøvelsens stand-in `…_6c1r`):** mange små writer-kald ca. 25× (dry-run 257,7 s mod 10,1 s;
  apply + finalize 254,2 s mod 9,9-10,2 s; det langsomste writer-kald 1,4 s mod 0,058 s); store enkeltforespørgsler
  ca. 3× (ledgerens genberegning 8,9 og 6,6 s for hele processen mod 2,8-3,1 s; autorisationen 2,2 s mod 0,69 s;
  klausulsættet 1,6 s mod 0,69 s); `ANALYZE` af 7 tabeller i alt 3,0 s (maks. 0,87 s); digestet 1,1 s efter
  `ANALYZE`. `apply-b` i alt ca. 9 min. Ingen enkelt sætning nærmede sig `statement_timeout` på 2 min. 6b-B's
  faktorer (27× og 3×) holder.
- **Skrivepausen** sluttede, da projektejeren godkendte B.
- **Fortryd:** B kun ved `fortryd-b` (restore af dumpet i tilstand `a`), kun så længe intet andet er skrevet i
  public/private siden dumpet (`T6C1_VINDUE_BRUDT`) og 6b's ceremoni C ikke har skrevet (`T6C1_FORTRYD_C`). 6b-B's
  restore-fortrydelse er lukket nu, hvor B har skrevet. A kan efter B ikke fortrydes alene.

## 18. Trin 6b ceremoni A og B: publication-operationer og 1939's personas — LIVE i prod (2026-11-01)

**Procedure:** `docs/runbooks/trin6b-prod.md`, private scripts `~/.private/5ab-overfoersel/26-trin6b.sh`,
`26-trin6b-b.R` og `26-trin6b-vindue.sql`. Repo `dcae5b34` (`main` med PR #285-#288). To ceremonier med hver sin GO,
kørt af projektejeren. Ceremoni C (identiteterne) er ikke kørt; den venter på 6c's runner.

- **Før:** `T6B_MAAL tilstand=foer personas_k3=8 identiteter_k3=8 afventer=0`, 2018-20 (`k1`) 832/832/`906c2a4d…`
  (samme hash som slutøvelsens stand-in), 0,7 s; `T6B_DEFACL` 0/0/0.
- **Ceremoni A (DDL, GO 6b-A `3a36017a`):** blokken fra `-- ===== trin 6b: publication-operationer =====` til
  slutningen af `db-migrations.sql` (sha `4a2912ca…`, inkl. opfølgningsblokken fra #287) og `db-rls.sql` (`f517b2e5…`)
  i én transaktion, derefter PostgREST genindlæst. 19 nye funktioner (5 `public.red_*`), 8 erstattede, 4 indekser og
  constraint-triggeren `trg_reimport_event_publication_identity_finalized`. Data: kun profilrækken
  `daa-1939-publication-v1`. Dump før: `daa-prod-20261101112742-6b.dump` (sha `075213af…`, ekstern `age`-kopi
  `7bf2937d…`, rundtur ok). Kvittering: `T6B_APPLY_A_OK tilstand=a`, `k1` uændret, 16,3 s.
- **Rådgiver (skridt 5):** Security Advisor i dashboardet efter A (intet før-billede; fundene holdt op mod blokkens
  objekter, som ved 6a). Eneste fund på 6b-objekter er de 5 forventede `authenticated_security_definer_function_executable`
  på `red_apply_reimport_publication_persona`, `red_apply_reimport_publication_identity`, `red_publication_control`,
  `red_publication_control_details` og `red_reverse_reimport_publication`. Ingen `anon`-fund, ingen
  `function_search_path_mutable`, intet på de private 6b-funktioner, ingen nye `rls_enabled_no_policy`. De erstattede
  public-funktioner beholder deres grants (`CREATE OR REPLACE`).
- **Ceremoni B (data, GO 6b-B `1c8aade5`):** manifest `T6B_MANIFEST_OK elementer=555 allerede_persona=8
  binding_uegnet=0 helpost_uegnet=0 ingen_bundet_narrativ=13 ingen_helpost=8 ingen_postbinding=21
  staged_ikke_offentlig=2`, indhold `36dfa422…` = øvelsens (3,0 s). Fortrydelsens dump i tilstand `a`:
  `daa-prod-20261101122034-6b.dump` (sha `56f9a466…`, ekstern `56f905df…`, rundtur ok); mål `vindue=d1a2d48f…`,
  132 linjer (98 tabeller + 34 sekvenser), `restore_hash=268deeaf…`, `katalog=0f5f2e0d…` (= slutøvelsens),
  0 forældreløse. Første `apply-b` stoppede med `SFTP_FEJL` (timeout mod SFTP-serveren i den eksterne kontrol, før
  databasen blev rørt); anden kørsel gennemført: `T6B_B_DRYRUN status=finalized`, `T6B_B_COMMITTED`,
  `T6B_B_KONTROL personas=555 primary_i_egen_helpost=555 helposter=555 identiteter=0 afventer=555
  records_med_to_personas=0 personas_k3=563`, `T6B_B_PUBSTATE n=563 uaendret=TRUE`, `T6B_B_KOE foer=8 efter=8
  nye_i_koeen=0`, replay `already_applied samme_batch=TRUE`; `T6B_APPLY_B_OK tilstand=b`, `k1` uændret.
  Efter: `T6B_MAAL_OK tilstand=b personas_k3=563 identiteter_k3=8 afventer=555`, `k1` 832/832/`906c2a4d…`.
- **Læser og redaktør:** de 555 nye personas er skjult i webkøen, og `red_afgoer_source_persona` afviser dem, indtil C
  har kørt. Læserfladen er uændret.
- **Ydelse (prod mod slutøvelsens stand-in):** manifestet 3,0 s mod 0,9-1,0 s (ca. 3×); B's dry-run 71,5 s og
  apply + finalize 70,4 s, i alt 143,4 s mod 5,2-5,6 s (ca. 27×); dump i tilstand `a` med mål 87 s + 17,5 s. Ingen
  enkelt sætning nærmede sig `statement_timeout` på 2 min. Runbookens skøn (55×) var for højt for manifestet.
- **Skrivepausen** sluttede, da projektejeren godkendte B (skridt 11).
- **Fortryd:** B kun ved `fortryd-b` (restore af dumpet i tilstand `a`), og kun så længe intet andet er skrevet i
  public/private siden dumpet (vinduesvagten stopper ellers med `T6B_VINDUE_BRUDT`) og 6c's runner ikke har skrevet.
  A med de tidligere funktionskroppe fra A-dumpet (ikke scriptet; runbookens liste) eller restore af A-dumpet, hvis
  intet andet er skrevet.

## 17. Trin 6a: helpost-regel, kildetekst-revision og 1939's klausuler — LIVE i prod (2026-10-30)

**Procedure:** `docs/runbooks/trin6a-prod.md`, private scripts `~/.private/5ab-overfoersel/25-trin6a.sh` og
`25-trin6a-b.R`. Repo `e9a289cf` (`main` med PR #281-#283). To ceremonier med hver sin GO, kørt af projektejeren.

- **Ceremoni A (DDL, GO 6a-A `035a4bcc`):** blokken fra `-- ===== trin 6a: helpost-regel =====` til slutningen af
  `db-migrations.sql` (sha `4b284563…`) i én transaktion (3 s; `statement_timeout` 2 min), derefter PostgREST genindlæst.
  12 nye funktioner (heraf `clause_write_set` med 5 argumenter i stedet for 4, og
  `public.red_apply_reimport_source_text_revision`), nye kolonner og views; klausul-writeren bruger helpost-reglen og
  den rå tekstform. Data: kun to rækker i `private.reimport_writer_profile`. Redaktørens 5b-ægteskabsark viser kun
  ægtefælleparten ved en aktuel `proposed`/`accepted`-relation. Dump før: `daa-prod-20261030194417-6a.dump`
  (sha `8239daf1…`, ekstern `age`-kopi `92771e2b…`, rundtur ok).
  Kvittering: `T6A_APPLY_A_OK funktioner=12 profiler=2 view=t`, 2018-20 uændret (`k1` 984/591/`2c530d0a…`).
- **Ceremoni B (data, GO 6a-B `a0524bcd`):** eksport `helposter=584 uden_helpost=8`; manifest indhold `3ee3d328…`
  (fil `439c7f1d…`, byte-ens med slutøvelsens). Reimport-writerens kæde (dry-run, authorize → apply → finalize) med
  profilen `daa-1939-clause-evidence-v1`: `T6A_APPLY_B_OK k3_klausuler=912 k3_poster=584 k3_afventer=687
  k3_flagget=225 k3_batch=1 status=finalized committed=TRUE sekunder=150.6 inkl_dryrun=297.6`; kanonisk lag uændret,
  replay `already_applied`, `k1` uændret. Flag: `page_marker_in_clause` 77, `unbalanced_parentheses` 66,
  `unknown_abbreviation` 59, `short_clause` 40, `possible_layout_line` 21, `uncertain_marker` 7, `multiple_marriages` 1.
  Dump før: `daa-prod-20261030221325-6a.dump` (sha `352b54a5…`, tilstand `a`, ekstern `age`-kopi `5af5dbbf…`,
  rundtur ok). Efter: `T6A_MAAL_OK tilstand=b`.
- **Ikke anvendt:** kildetekst-revisionen (`private.write_source_text_revision`, kræver READ COMMITTED) er deployet, men
  ubrugt; første brug er A6b-resten i 6c. Læserfladen er uændret.
- **Ydelse:** B's apply tog 150,6 s i prod mod 3,9 s på stand-in (slutøvelsen), knap 40 gange langsommere; kørslen blev ikke stoppet af prods
  `statement_timeout` på 2 min.
- **Rådgiver (skridt 5):** Security Advisor i dashboardet efter B (intet før-billede taget; fundene er i stedet holdt op
  mod blokkens objekter). Eneste fund på et 6a-objekt er det forventede: `authenticated_security_definer_function_executable`
  på `public.red_apply_reimport_source_text_revision` (samme mønster som de øvrige `red_apply_reimport_*`; adgangen
  afgøres i `private.write_source_text_revision` af `require_reimport_writer_editor()` og elementets autorisation). De
  fire ændrede public-funktioner beholder deres hidtidige grants (`CREATE OR REPLACE`). Blokken opretter ingen tabeller,
  så ingen nye `rls_enabled_no_policy`; ingen `anon`-fund på 6a-objekter.
- **Fortryd:** B ved restore af B-dumpet + `db-rls.sql` (klausulerne har ingen afhængige før 6c), eller et nyt
  regelsæt via `clause_revision`. A med de tidligere funktionskroppe fra A-dumpet (ikke scriptet; runbookens liste)
  eller restore af A-dumpet, hvis intet andet er skrevet.

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
- **Rådgiver (skridt 6):** `22-trin-b.sh advisors` → `ADVISORS_TRINB_OK nye=2 forsvundne=0` (netop 5c-1's to fund). CLI-
  rådgiverens lint-sæt melder kun `rls_enabled_no_policy`, så SECURITY DEFINER-funktioner (også `public_family_sources`)
  ses ikke dér; deres grants er målt af `maal` (`definer=2 anon=true auth=true`).
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
