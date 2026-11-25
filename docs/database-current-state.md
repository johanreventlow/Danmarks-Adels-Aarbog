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

## 54. Review 37 ceremoni 2b: kontrollistens id-henvisninger — LIVE i prod (2026-11-25)

**Grundlag:** PR #484 (CI grøn i alle jobs på `1c0ccbd2`; merget `f6d0ba25` efter DDL). Privat runner
`~/.private/review37-c2b/prod.zsh`, fastlåst på `1c0ccbd2` (blok-sha `237af1fe…`), kørt i projektejerens shell **før** merge.
Afgørelse: `docs/decisions.md` 2026-11-25 (»Rettet samme dag«).

- **Hvorfor:** §52 foldede kontrollistens rene id-tal sammen ud fra en ukontrolleret påstand. Målt i prod-kopien stod 8
  identitetskandidater med personens id (`basis`: `"person_id": P`) i den sammenklappede gruppe; sletningen fjerner dem ikke.
- **DDL (én transaktion, 4,6 s):** blokken `-- BEGIN review37-c2b` (sidst i db-migrations.sql), én funktionskrop
  (`private.person_purge_kontrol`), samme signatur og ACL, ingen data. Ny grund `id_henvisning`: P's eget id som værdi for
  en nøgle med »person« i navnet eller i en liste under en person-/partner-nøgle (samme betydning som planens `jrx`).
  Nøgleinventaret over de scannede kildedata viser, at alle person-id-bærende nøgler har »person« i navnet.
- **I transaktionen:** katalog-delta præcis 1, ACL uændret; facit 1 linje OK; verify-enheden `c1` OK; anon 1725 personer og
  `public_person_facts`-md5 før = efter; data uændret (4 tabeller). Prøve 6,0 s, commit 4,6 s.
- **Efterkontrol (læse-kun):** kroppen har `id_henvisning`; hverken `anon` eller `authenticated` kan kalde funktionen;
  `get_advisors` (security): samme 4 lint-typer som efter §52, funktionen nævnes ikke.
- **Ydelse:** mønstret starter med det faste ord. En første form med `"[a-z_]*` forrest tog 44 s for den største profil i
  generalprøven; den endelige 4,1-4,3 s (stand-in, varmt) som før.
- **Bevis:** `tests/sql/test-review37-c2b-upgrade.sh` fra `86bc91ce` (prods SQL efter §53) og `test-person-purge.sh`
  (6 `c2b_*`-tests). Generalprøve på stand-in (uden §53's blok, som kræver dataflytningen; c2b rører ikke billedtyper):
  prøve → commit → `tal` → `tid` → fortryd-prøve → fortryd (`P_FORTRYD_TROFAST`).
- **Fortryd:** `/bin/zsh -f ~/.private/review37-c2b/prod.zsh fortryd [--jeg-mener-det]` (prods krop fra
  `fortryd-definitioner.prod.sql`).
- **Åbent:** R37C2-2 i #397 — skal sletningen selv fjerne sådanne id-henvisninger i interne kildedata?

## 53. Billedtypen er motivet og en kontrolleret ordliste — LIVE i prod (2026-11-25)
**Grundlag:** PR #481 (CI grøn; merget `cb750799` FØR DDL — klienten tåler begge tilstande). Spec
`docs/superpowers/specs/2026-11-25-media-slags-ordliste-design.md`; afgørelse `docs/decisions.md` 2026-11-25.
- **Dataflytning (projektejerens shell):** `R/media-slags-flytning.R` (`--proev-binding` OK 25006 ×2, derefter
  `--jeg-mener-det`): 56 `media` via `red_opdater_media` (45 maleri + 9 foto → `portræt`, 2 scanning (7, 8) → `våben`),
  48 `teknik`-fakta via `red_upsert_fakta` (Maleri 45, Fotografi 3; ingen på 7, 8, 10-16). 56 change_sets. Efter:
  portræt 167, våben 23, gods 11, segl 6, medalje 5; 0 uden for listen.
- **DDL (én transaktion, 1,0 s):** blokken `-- BEGIN media-slags-ordliste` fra `cb750799` (sha `5074be40…`, 66 linjer),
  kørt med en engangsrunner (`psql -1`, ON_ERROR_STOP, sha-tjek) i projektejerens shell: vagt (0 rækker uden for
  listen), 6 `vocab`-rækker (scheme `media_slags`), `private.validate_media_slags()` + `trg_media_slags` (BEFORE INSERT
  OR UPDATE OF slags ON media). Ingen data, ingen grants.
- **Efterkontrol:** vocab 6, trigger 1, 0 media uden for listen. I ROLLBACK: `slags='maleri'` → `portræt`;
  `slags='tegning'` → `23514 MEDIA_SLAGS_UKENDT`. `get_advisors` (security): samme 4 lint-typer, ingen ERROR, ingen nævner
  den nye funktion.
- **Ikke øvet på stand-in** (lille, transaktionel blok med egen vagt); opgraderingstesten
  `tests/sql/test-media-slags-ordliste-upgrade.sh` kører blokken mod en prod-formet base fra `0c1288db`, også med
  forkerte data (negativ base) og som mutationstest.
- **Oprydning:** `PORTRAIT_SLAGS`/`BILLEDER_PORTRAET_SLAGS` = kun `portræt` (gren `chore/media-slags-oprydning`).

## 52. Review 37 ceremoni 2: personsletningens kontrolliste og gruppelås — LIVE i prod (2026-11-25)

**Grundlag:** PR #482 (CI grøn i alle jobs på `acc94f21`; merget `e1692be6` efter DDL). Privat runner
`~/.private/review37-c2/prod.zsh`, fastlåst på `d3a31df4` (blok-sha `54a0ea11…`), kørt i projektejerens shell **før** merge.
Afgørelser: `docs/decisions.md` 2026-11-25.

- **DDL (én transaktion, 6,1 s):** blokken `-- BEGIN review37-c2` (sidst i db-migrations.sql), fire funktionskroppe med
  samme signaturer og ACL, ingen data:
  - P3+P10 `private.person_purge_kontrol`: også historier, beskrivelser og andres påstande/citater søges (navn og id-tal);
    ét fund pr. række med grund `fritekst` (navn) eller `kun_id` (kun et id-tal); navnet trimmes. Forhåndsvisningens
    hash ændres, så åbne forhåndsvisninger afvises med `PURGE_PREVIEW_AENDRET`.
  - P9 `red_slet_person_helt`: den virkningsløse `set_config('statement_timeout')` er væk (loftet er redaktørens 8 s).
  - R37P11-3 `red_slet_person` låser hele samme_som-gruppen; `red_set_privat` tager `samme_som_mutation` først.
- **I transaktionen:** katalog-delta præcis 4 (funktionskroppene), ACL uændret; facit (frisk base af commit'en) 4 linjer OK;
  verify-enheden `c1` OK; anon 1725 personer og `public_person_facts`-md5 før = efter; data uændret (4 tabeller).
  Prøve 6,4 s, commit 6,1 s.
- **Efterkontrol:** `get_advisors` (security): samme 4 lint-typer som efter §51; ceremoniens funktioner står kun under den
  kendte `authenticated_security_definer_function_executable` (alle `red_*`), `person_purge_kontrol` slet ikke.
- **Bevis:** `tests/sql/test-review37-c2-upgrade.sh` fra `90fa6fff` (prods SQL efter c1): katalog = frisk, funktionsretter og
  data uændrede, idempotent, hele db-rls.sql oveni uden ændring, fuld db-verify grøn. Adfærd: `test-person-purge.sh`
  (gruppe `review37_c2`) og `test-person-purge-concurrent.sh` (`r37p11_3_*`, røde uden rettelsen).
- **Øvelse:** stand-in `daa5ab_ddl_standin_20261124224412_c1`, først bragt i prods tilstand med c1 (c1's øvelse sluttede med
  fortryd): prøve → commit → `tal` → `tid` → fortryd-prøve → fortryd (`P_FORTRYD_TROFAST`). Tid (stand-in, varmt) uændret:
  største slettelige profil forhåndsvisning 2,1 s og sletning 4,9 s; største profil i alt forhåndsvisning 4,3 s.
- **Fortryd:** `/bin/zsh -f ~/.private/review37-c2/prod.zsh fortryd [--jeg-mener-det]` (prods fire kroppe fra
  `fortryd-definitioner.prod.sql`).
- **Kendt rest:** R37C2-1 i #397 (fortryd af en fortrydelse er en tavs no-op); andre skrivere af `privat`/`levende`/`staged`
  (import, promotion) tager ikke samme_som-låsen.

## 51. Review 37 ceremoni 1: indeks, forslagslofter, klientkaldbare funktioner — LIVE i prod (2026-11-24)

**Grundlag:** PR #477 (CI grøn i alle jobs på `030d6c39`; merget `90fa6fff` efter DDL). Privat runner
`~/.private/review37-c1/prod.zsh`, fastlåst på `030d6c39` (blok-sha `f19eda61…`), kørt i projektejerens shell **før** merge.

- **DDL (én transaktion, 3,9 s):** blokken `-- BEGIN review37-c1` (sidst i db-migrations.sql) + DO-blokken
  `$review37_c1_execute$` (db-rls.sql, før R37S8-2-blokken):
  - Y8 `private.ix_interpretation_promotion_target`; Y10 `ix_fact_type_subjekt` og partiel `ix_fact_sted`.
  - S6 `red_suggest`: `FORSLAG_FOR_STORT` (værdi > 40.000 bytes, kilde/note > 4.000, art/felt > 64, payload > 64 kB) og
    `FORSLAG_UKENDT_SUBJEKTTYPE` (hverken public-tabel eller klientkaldenavn); `search_path` med `pg_temp` sidst.
  - S9/R37S8-2-3: EXECUTE fjernet for PUBLIC/anon/authenticated på 9 triggere/interne skrivere (`log_change`, 5 `trg_*`,
    `regen_person_visning`, `_regen_mentions_for`, `parse_mentions`); `service_role` beholder.
  - R37S8-2-2 (funktionsdelen): `postgres`' standard-EXECUTE i public fjernet — nye funktioner er lukket for klienterne,
    til de får en eksplicit GRANT. Efter: `{postgres=X, service_role=X}`.
- **I transaktionen:** katalog-delta præcis 14 (standardrettigheden, `red_suggest`, 9 ACL, 3 indeks), intet forsvundet;
  facit (frisk base af commit'en) 48 linjer OK; verify-enhederne `c1` og `r37s8-2` OK; anon 1725 personer og
  `public_person_facts`-md5 før = efter; data uændret (4 tabeller). Prøve 5,6 s, commit 3,9 s.
- **Efterkontrol (læse-kun):** anon kan ikke kalde `regen_person_visning` (REST: `42501`), `public_person_facts` 200;
  indeksene findes; sitet 200. `get_advisors` (security): samme 4 lint-typer som efter §48, ingen nævner
  ceremoniens funktioner.
- **Bevis:** `tests/sql/test-review37-c1-upgrade.sh` fra `647b9e15` (prods SQL efter R37S8-2): enheden grøn på frisk base,
  rød på prods form (direkte EXECUTE + prods standardrettighed seedet), katalog/funktionsretter = frisk efter deploy, en ny
  funktion kaldbar for anon før og lukket efter, idempotent, hele db-rls.sql oveni uden ændring, fuld db-verify grøn.
  `tests/sql/test-review37-r37s8-2-seeded.sh` giver r37s8-2 tænder på frisk base (R37S8-2-1).
- **Øvelse:** stand-in `daa5ab_ddl_standin_20261124224412_c1` (læse-dump `daa-prod-20261124224127`, sha `67533d6c…`):
  prøve → commit → fortryd (`P_FORTRYD_TROFAST`) → prøve igen. Prod: prøve, derefter commit.
- **Fortryd:** `/bin/zsh -f ~/.private/review37-c1/prod.zsh fortryd [--jeg-mener-det]` (prods `red_suggest` fra
  `fortryd-definitioner.prod.sql`, GRANT tilbage på de 9, standardrettigheden tilbage, DROP af de 3 indeks).
- **Regel fremover** (`docs/decisions.md` 2026-11-24, CLAUDE.md »Robotter og misbrug«): en ny klientkaldbar
  public-funktion uden for `red_*` skal på listen i verify-enheden `c1`; anon kræver også en linje i decisions.
- **Pensioneret:** R37S8-2's opgraderingstest (`tests/ikke-i-ci.txt`).

## 49. Review 37 R37S8-2: klienter har kun læseret i public — LIVE i prod (2026-11-23)

**Grundlag:** PR #455 (CI grøn i alle jobs; SQL = `01d0dd95`). Privat runner `~/.private/review37-r37s8-2/prod.zsh`,
fastlåst på `01d0dd95` (blok-sha `08a196fd…`), kørt i projektejerens shell **før** merge.

- **Målt før (23/11):** Supabases standardrettigheder (`pg_default_acl` for `postgres` i public) havde givet `anon` og
  `authenticated` INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER/MAINTAIN på 29 tabeller og alle 4 views, MAINTAIN også
  på `story_kilde`, `import_korrektion` og `bookmark`, og SELECT/UPDATE/USAGE på 27 sekvenser. Ikke et åbent hul (PostgREST har
  intet TRUNCATE, ingen skrivepolitik uden for `bookmark`, views er `security_invoker`), men RLS var eneste mur.
- **DDL (én transaktion):** kun DO-blokken `$review37_r37s8_2_skriveret$` (sidst i `db-rls.sql`): ikke-SELECT-retter
  (tabel og kolonne) for PUBLIC/anon/authenticated fjernet på public-relationer med noget at fjerne, alle sekvensretter
  fjernet, `bookmark` beholder authenticated INSERT + DELETE, og `postgres`' standardrettigheder i public mister
  skrive- og sekvensretterne (standard-SELECT bevaret). Katalog-delta 63 relationer + 2 standardrækker, facit = frisk
  base, verify-enheden `r37s8-2` OK i transaktionen, rækketal uændret i 43 tabeller, læserne som anon (1725 personer)
  og authenticated uændrede; 4,3 s (prøve 5,1 s; rækketællingen dominerer). Ingen relationslåse (målt lokalt).
- **Efterkontrol:** kun `bookmark:authenticated:{INSERT,DELETE}` tilbage ud over SELECT; ingen sekvensret;
  standardrettighederne `r:{anon,authenticated}:SELECT`; alle public-tabeller med RLS; `get_advisors` uden nye
  kategorier; sitet 200.
- **Regel fremover** (`docs/decisions.md` 2026-11-23): ny klientskriveret GRANT'es inde i blokken og føjes til
  verify-enhedens tilladte mængde; en ny public-tabel arver SELECT og skal derfor have RLS — verify kræver RLS på hver
  public-tabel.
- **Bevis:** `tests/sql/test-review37-r37s8-2-upgrade.sh` fra `f806cedc` (seeder Supabase-retterne som overmål inkl.
  kolonneretter og standardrettigheder): enheden rød før/grøn efter, katalog = frisk, idempotent, db-rls oveni uden
  ændring, en ny tabel arver kun SELECT, fuld db-verify grøn; rød uden MAINTAIN i blokken. Fortryd øvet trofast på
  prod-kopi (`prod.zsh fortryd` GRANT'er præcis de målte retter tilbage).

## 48. Review 37 Y1 + D8: personkontrol-gitteret i udsnit — LIVE i prod (2026-11-23)

**Grundlag:** PR #453 (CI grøn i alle jobs; SQL = `a9eba04b`; merget `f806cedc` efter DDL). Privat runner
`~/.private/review37-y1/prod.zsh`, fastlåst på `a9eba04b` (blok-sha `1da9ba10…`), kørt i projektejerens shell **før**
merge.

- **DDL (én transaktion):** kun blokken `-- BEGIN review37-y1` (sidst i db-migrations.sql). Ny
  `red_person_grid_udsnit(p_efter, p_antal, p_person_id)`: et vindue i id-orden (1-1000 personer) eller én person,
  SECURITY DEFINER, `search_path=public, pg_temp`, `plan_cache_mode=force_custom_plan`, EXECUTE kun `authenticated`
  (eksplicit REVOKE/GRANT i blokken). `red_person_grid()` er en tynd indpakning om den (samme signatur og ACL);
  `red_ret_ocr_felt` henter kun den rettede persons række (D8). Katalog-delta præcis 3 (2 ændrede + 1 ny), md5 = facit,
  data uændret (5 tabeller); 8,5 s, fordi ceremonien beregner gitteret fire gange (prøve 8,1 s).
- **Adfærd i transaktionen (som redaktør, kun md5/ms skrevet):** `red_person_grid()` før = efter = vinduer à 500
  (1802 rækker, md5 `84d65ec3…`). Tider i prod: enkeltkald højst 13 ms (før ~350 ms via hele gitteret), vindue à 500
  455 ms / 200 ms, fuldt gitter 405 ms.
- **Planfejl fundet undervejs:** uden `force_custom_plan` skifter plpgsql efter 5 kald til en generisk plan for
  `= ANY(v_ids)`, der passer til små arrays; på en prod-kopi tog et vindue à 500 efter 20 enkeltkald 22,5 s. `db-verify.sql`
  asserter indstillingen (`VERIFY_FAILED: review 37 Y1`, set rød uden den).
- **Bevis:** `tests/sql/test-review37-y1-udsnit.sql` (syntetisk, i CI på frisk schema): vinduer = fuldt gitter,
  enkeltkald = fuld-række, grænser, ACL, ikke-redaktion afvist, D8-svaret; rød mod to vinduesafhængige fejl.
  `tests/sql/test-review37-y1-upgrade.sh` fra `8bc9acd4`: rød på basen, efter blokken kroppe/proconfig/ACL/katalog =
  frisk `schema.sql`, data uændret, idempotent, db-rls oveni uden ændring, fuld db-verify grøn. På prod-kopi: gammel fuld
  = ny fuld = udsnit = vinduer (md5 `188d3586…`), 0 afvigelser ved enkeltkald for alle 1802.
- **Web:** kvalitetsarket henter i keyset-vinduer à 500 (stop på tomt vindue; bigint som streng), »Genindlæs
  kilderække« henter én række, og rækkerne er memo-komponenter med `useDeferredValue` på søgningen (renderingsgevinst
  efter design, ikke målt). Vercel-preview som redaktør før merge: 1802 af 1802.
- **Efterkontrol (læse-kun):** `prod.zsh tal`: anvendt, alle 3 md5 = facit. `get_advisors` (security): samme 4
  lint-typer som efter §47; den nye funktion står ikke under `anon_security_definer_function_executable`, kun under
  `authenticated_security_definer_function_executable` som alle `red_*`.
- **Øvelse:** stand-in `daa5ab_ddl_standin_20261121170307_y1proeve` (kopi af `kar…h130` + D9-blokken fra `8bc9acd4`):
  prøve → commit → fortryd (`P_FORTRYD_TROFAST`, md5 tilbage, ny funktion droppet), gentaget med adfærdstjekkene.
  Prod: prøve, derefter commit.
- **Fortryd:** `/bin/zsh -f ~/.private/review37-y1/prod.zsh fortryd [--jeg-mener-det]` (gendanner prods 2 definitioner
  fra `~/.private/review37-y1/fortryd-definitioner.prod.sql` og dropper `red_person_grid_udsnit`). Fortryd kun DB'en,
  efter at web er rullet tilbage — web kalder den nye funktion.
- **Pensioneret:** D9's opgraderingstest (`tests/ikke-i-ci.txt`).

## 47. Review 37 D9 + R37B-1: fortryd og sletning låser ikke hinanden fast — LIVE i prod (2026-11-23)

**Grundlag:** PR #450 (CI grøn undtagen R-jobbet, der to gange blev stoppet af 20-minutters grænsen under duckdb-
kompileringen, før nogen test kørte; R-suiten lokalt på `8f792c33`: 6901 bestået, 0 fejl; SQL = `8f792c33`; merget
`8bc9acd4` efter DDL). Privat runner `~/.private/review37-d9/prod.zsh`, fastlåst på `8f792c33` (blok-sha `6297a49a…`),
kørt i projektejerens shell **før** merge.

- **DDL (én transaktion):** kun blokken `-- BEGIN review37-d9` (sidst i db-migrations.sql). 7 funktioner = facit
  (krop-md5 + ACL). En fælles advisory-lås `daa-fortryd-slet`: `red_fortryd_change_set` tager den eksklusivt,
  `red_slet_oplysning`, `red_slet_relation`, `red_fjern_samme_som`, `red_fjern_ikke_samme_som`, `red_slet_person` og
  `red_slet_familie_link` delt, før første rækkelås (i fortrydelsen og `red_slet_person` lige efter narrativ-
  kontraktlåsen, som forbliver den første). R37B-1: fortrydelsen låser linjemedlemskabets person før medlemskabet.
  Data uændret (6 tabeller); 2,7 s (prøve 4,3 s, stand-in 0,8 s).
- **Hvorfor én lås, ikke én rækkefølge:** fortrydelsen låste assertion → citation → conclusion → … → relation,
  slette-RPC'erne følger FK-ordenen og de almindelige writere konklusion → påstand → person; der findes ingen fælles
  orden, og at flytte fortrydelsens ville give nye baglåse mod writerne. Pris: to fortrydelser kører ikke samtidig, og en
  sletning venter på en fortrydelse og omvendt (begge typisk under et sekund); sletninger blokerer ikke hinanden.
- **Bevis:** `tests/sql/test-review37-d9-laaseorden.sql` (to-tre sessioner via dblink, i CI i `ci_k36_laase`) giver
  deadlock på prods kode i (a) fortryd × `red_slet_oplysning` og (c) fortryd × `red_reverse_placement_membership`, og
  er grøn efter. `tests/sql/test-review37-d9-upgrade.sh` fra `b18bd8a8`: rød på basen, efter blokken kroppe/ACL/katalog
  = frisk `schema.sql`, data uændret, idempotent, db-rls oveni uden ændring, fuld db-verify grøn.
- **Efterkontrol (læse-kun):** `prod.zsh tal`: anvendt, alle 7 md5 = facit. MCP: de 7 er stadig SECURITY DEFINER med
  `search_path=public`, EXECUTE for `authenticated`, ikke `anon`. `get_advisors` (security): samme 4 lint-typer som efter
  §46; de 7 står kun under `authenticated_security_definer_function_executable` som alle `red_*`.
- **Øvelse:** stand-in `daa5ab_ddl_standin_20261121170307_d9oev` (kopi af `kar…h130`): prøve → commit → fortryd
  (`P_FORTRYD_TROFAST`). Prod: prøve, derefter commit.
- **Fortryd:** `/bin/zsh -f ~/.private/review37-d9/prod.zsh fortryd [--jeg-mener-det]` (prods definitioner fra før
  apply: `~/.private/review37-d9/fortryd-definitioner.prod.sql`).
- **Kendte rester (#397):** R37B-6 (ikke målt): almindelige writere kan stadig deadlocke mod en fortrydelse, fx
  `red_set_konklusion` på den påstand, sættet oprettede (konklusion → påstand mod fortrydelsens påstand → konklusion).
  `red_slet_person_helt` er bevidst uden låsen; dens to-sessionstests mod fortrydelsen (`test-person-purge-concurrent.sh`:
  fakta-, pin- og mediesæt, begge rækkefølger) giver ingen 40P01. Blok 4's opgraderingstest er pensioneret.

## 46. Review 37 blok 4: konklusion og ændringssæt i redaktionens RPC'er (D4, D10, D11) — LIVE i prod (2026-11-22)

**Grundlag:** decisions 2026-11-22 (BESLUTTET: et redaktionelt valg af konklusion gør den gyldig; et tilbagetrukket
slot har ingen gældende konklusion), PR #447 (CI grøn på `b4ae8510`; SQL = `201c64db`; merget `b18bd8a8` efter DDL). Privat runner
`~/.private/review37-b4/prod.zsh`, fastlåst på `201c64db` (blok-sha `2365d3d4…`), kørt i projektejerens shell **før**
merge.

- **DDL (én transaktion):** kun blokken `-- BEGIN review37-b4` (sidst i db-migrations.sql). 5 funktioner = facit
  (krop-md5 + ACL): `red_set_konklusion` sætter `status='afklaret'` ved valget (D4); `red_tilfoej_foraeldre_paastand`
  regner et tilbagetrukket slot for uden gældende konklusion og genbruger rækken med upsert (D10); `red_set_koen`,
  `red_set_privat` og `red_slet_oplysning` afviser et ukendt id efter rollegaten og før ændringssættet (D11). Data
  uændret (4 tabeller); 2,1 s (prøve 3,3 s, stand-in 0,3 s).
- **Målt i transaktionen:** fakta-konklusioner 7.202 `afklaret` og 0 tilbagetrukne; relationskonklusioner 2.316
  `afklaret` og 1 `omstridt` (bliver `afklaret`, hvis en redaktør vælger en påstand på den).
- **Efterkontrol (læse-kun, MCP):** de fem har kun `postgres` og `authenticated` EXECUTE (ingen `anon`/PUBLIC);
  rettelserne står i kroppene. `get_advisors` (security): samme 4 lint-typer som efter §45; de fem står kun under
  `authenticated_security_definer_function_executable` som alle `red_*`.
- **Øvelse:** stand-in `kar20261122_…h130` (nu blok 1-4 + S3): prøve → commit → fortryd-prøve → fortryd
  (`P_FORTRYD_TROFAST`) → commit. Prod: prøve, derefter commit.
- **Fortryd:** `/bin/zsh -f ~/.private/review37-b4/prod.zsh fortryd [--jeg-mener-det]` (prods definitioner fra før
  apply: `~/.private/review37-b4/fortryd-definitioner.prod.sql`).
- **Kendte rester (#397):** web's `joinEvidence` (`web/src/data/redaktionRead.ts`) viser den valgte påstand som
  konklusion uanset status, så »Gør til konklusion« mangler på en tilbagetrukken konklusions egen påstand (latent:
  kernefelter kan ikke trækkes tilbage fra appen). D9 (låserækkefølge) er holdt ude. P11's kaldermatrix kører nu
  direkte mod frisk schema i CI, P11's opgraderingstest er pensioneret.

## 45. Review 37 S8 + S5 + P11: læserens kolonner, ingen offentlig bucket, én sletteknap — LIVE i prod (2026-11-22)

### S8 + S5 (PR #442 + #445)

**Grundlag:** PR #442 (merget `14f22a6d`) og opfølgningen #445 (projektejerens valg: medlemmer skjules også på
`story`/`feed_pin`; merget `4cce1eb5`, SQL = `86c0df81`). S8 ændrer ikke web-koden, så begge PR'er blev merget **før**
prod-kørslen, der tog den endelige blok fra main. Privat runner `~/.private/review37-s8/prod.zsh`, fastlåst på
`86c0df81` (blok-sha `85b99151…`).

- **DDL (én transaktion):** kun DO-blokken `$review37_s8_anon_kolonner$` (db-rls.sql, efter feed_pin-sektionen).
  `anon` mister tabelretten på `media`, `story`, `feed_pin` og får kolonne-SELECT på læserens kolonner; `authenticated`
  får det samme på `story` og `feed_pin`, men beholder tabel-SELECT på `media`. Begge roller har kun SELECT tilbage
  (før: ALL inkl. TRUNCATE på `media`, MAINTAIN på alle tre). Facit 56 linjer; 38 katalogposter ændret (kun de tre
  tabeller og deres kolonner); data uændret (4 tabeller); 1,7 s.
- **Skjult for gæster:** `story.skabt_af/godkendt_af/godkendt_naar/oprindelse/llm_*`, `feed_pin.oprettet_af`,
  `media.original_filnavn/sha256`. `media.storage_path` er bevidst læsbar (bucket'en er privat; storage-politikken gater
  pr. billede).
- **Målt efter (læse-kun, MCP, `set local role anon`):** `media` 13, `feed_pin` 1, `media_variant` 20 rækker læsbare;
  `original_filnavn` og `story.skabt_af` giver permission denied. `get_advisors` (security): 4 lints, ingen om de tre
  tabeller.
- **S5:** `db-verify`-enheden `r37s5` fejler, hvis en storage-bucket er offentlig (ingen DDL).
- **Øvelse:** stand-in `…_s8oev2`: prøve → commit → fortryd-prøve → fortryd → commit. Prod: prøve, derefter commit.
- **Fortryd:** `/bin/zsh -f ~/.private/review37-s8/prod.zsh fortryd [--jeg-mener-det]` (prods ACL fra før apply:
  `~/.private/review37-s8/fortryd-definitioner.prod.sql`).
- **Kendte rester (#397):** medlemmer læser stadig `media.original_filnavn/sha256` (redaktionens medieliste og dublettjek
  læser dem direkte → rolle-gated RPC, før medlemmer lukkes ind; prod har 0 medlemmer). `media_variant` har stadig
  Supabases standard-ALL for `anon`/`authenticated`, og `story_kilde` har MAINTAIN.

### P11 (PR #443)

**Grundlag:** decisions 2026-11-22 (én sletteknap, systemet vælger vejen), PR #443 (CI grøn på `e8b8023d`; merget
`526a769a` **efter** DDL — ny web på gammel database sender alle til »Slet helt«). Privat runner
`~/.private/review37-p11/prod.zsh`, fastlåst på `e8b8023d` (blok-sha `34afc4ce…`).

- **DDL (én transaktion):** kun blokken `-- BEGIN review37-p11` (sidst i db-migrations.sql). 4 funktioner = facit
  (krop-md5 + ACL): ny `private.person_slet_aarsag(bigint)` (kun ejer), `red_slet_person` afviser en ikke-offentlig
  person med `SLET_KRAEVER_SLET_HELT: <årsag>`, `red_slet_person_preview` får `kan_fortrydes` + `aarsag`, ny
  `red_slettede_personer(integer)` (rollegate redaktion; kun `authenticated` EXECUTE). Data uændret (2 tabeller); 3,4 s.
- **Målt i transaktionen:** af prods personer er 1.725 offentlige (kan slettes med fortryd), 73 levende og 4 staged
  (kun »Slet helt«); 0 private eller skjult af samme_som.
- **Efterkontrol (læse-kun, MCP):** `anon` har ingen EXECUTE på de fire; `person_slet_aarsag` lukket for alle andre end
  ejeren; de tre `red_*` kun `authenticated`.
- **Øvelse:** stand-in `…_p11oev2`: prøve → commit → fortryd-prøve → fortryd → commit. Prod: prøve, derefter commit.
- **Fortryd:** `/bin/zsh -f ~/.private/review37-p11/prod.zsh fortryd [--jeg-mener-det]` (prods definitioner fra før
  apply: `~/.private/review37-p11/fortryd-definitioner.prod.sql`).
- **Kendte rester (#397):** en fortrudt fortrydelse falder ud af listen; intet tvangsvalg ved konflikt i listen; højst
  100 rækker; ingen redaktørvej til at rette `levende`; en ikke-offentlig samme_som-knude blokeres begge veje; latent
  kapløb i en samme_som-gruppe.

## 44. Review 37 S3: en familie uden medlemmer er ikke offentlig — LIVE i prod (2026-11-22)

**Grundlag:** decisions 2026-11-22 (BESLUTTET: en familie uden medlemmer er ikke offentlig), PR #440 (CI grøn på
`99a652f0`; SQL = `d529f386`). Privat runner `~/.private/review37-s3/prod.zsh`, fastlåst på `d529f386` (blok-sha
`4733ff07…`), kørt i projektejerens shell **før** merge.

- **DDL (én transaktion):** kun DO-blokken `$review37_s3_tom_familie$` (db-rls.sql): `family_offentlig(bigint)` kræver
  mindst ét medlem. Præcis 1 katalogobjekt; krop = facit, ACL uændret, data uændret (4 tabeller), ingen tabel-låse;
  2,4 s (stand-in 0,1 s).
- **Effekt:** en familie uden medlemmer og et ikke-eksisterende familie-id er ikke offentlige, så fakta, noter, narrativer
  og billeder, der står tilbage efter fjernede partnerkoblinger, skjules for gæster (og billeder også for medlemmer).
  Medlemmer kan ikke foreslå rettelser til en tom familie (`FORSLAG_SUBJEKT_UTILGAENGELIGT`).
- **Målt:** 0 af 676 familier uden medlemmer før og efter → intet skiftede; 640 af 676 offentlige; 13 af 13 medier
  synlige for anon.
- **Øvelse:** stand-in `kar20261122_…h130` (nu blok 1-3 + S3): prøve → commit → fortryd-prøve → fortryd
  (`P_FORTRYD_TROFAST`) → commit. Prod: prøve, derefter commit.
- **Efterkontrol (læse-kun, MCP):** krop-md5 = facit; `get_advisors` (security) identisk med før.
- **Fortryd:** `/bin/zsh -f ~/.private/review37-s3/prod.zsh fortryd [--jeg-mener-det]` (prods egen definition fra før
  apply: `~/.private/review37-s3/fortryd-definitioner.prod.sql`).
- **NB:** kommentaren i `red_suggest` (»family_offentlig er true for en familie uden medlemmer«) er forældet, men
  står i funktionskroppen og er ikke rettet for ikke at ændre funktionen; eksistensvagten dér er stadig korrekt.

## 43. Review 37 blok 3: billedretning, familie-gate, dato- og liste-CHECKs — LIVE i prod (2026-11-22)

**Grundlag:** decisions 2026-11-22 (BESLUTTET: review 37's databasefund, S4 og D5) + blok 3's note, PR #438 (CI grøn på
`261a9236`). Privat runner `~/.private/review37-b3/prod.zsh`, fastlåst på `261a9236` (blok-sha `606e7da7…`), kørt i
projektejerens shell **før** merge.

- **DDL (én transaktion):** før-kontrol (`tests/sql/review37-b3-foer.sql`, 0 overtrædelser) → DO-blokken
  `$review37_b3_media_gate$` (db-rls.sql; ikke hele filen) → blokken `-- BEGIN review37-b3` … `-- END review37-b3`
  (db-migrations.sql), CHECK'erne sidst med `lock_timeout` 5 s. Præcis 25 katalogobjekter:
  - 12 validerede CHECKs: `relation_afbildet_kanonisk`, `relation_periode_orden`, `relation_konfidens_chk`,
    `assertion_/haendelse_/story_dato_orden`, `assertion_/haendelse_/story_date_qualifier_chk`,
    `family_member_rolle_chk`, `family_member_konfidens_chk`, `conclusion_status_chk`.
  - 2 nye funktioner (kun ejer-EXECUTE): `private.kraev_gyldig_datering(date,date,text)`,
    `private.person_purge_familie_skjult(bigint)`.
  - 11 ændrede kroppe (ACL uændret): `media_afbilder_skjult`, `media_afbilder_privat`,
    `private.person_purge_plan_fra_historik`, `red_opret_fakta`, `red_upsert_fakta`, `red_tilfoej_oplysning`,
    `red_opret_story`, `red_rediger_story`, `red_ret_ocr_felt`, `red_relation`, `red_tilfoej_relation`.

  Facit (frisk base af samme commit) ens; data uændret (md5 af 8 tabeller før/efter); 5,4 s (prøve 6,4 s; stand-in 0,6 s
  — forskellen er netværk pr. sætning). Seks læsertabeller er låst (ACCESS EXCLUSIVE) fra første ALTER til COMMIT.
- **Effekt:** S4 — `afbildet` kun `person→media` og `media→{estate, coat_of_arms, lineage, family, place}`; case-varianter
  afvises; `red_relation`/`red_tilfoej_relation` giver `AFBILDET_RETNING_UGYLDIG`. Billed-gaten skjuler også billeder af en
  familie, der ikke er offentlig (anon) / har et privat medlem (medlem). Personsletning låser et bevaret billede, der
  mister en slettet familie, når familien var skjult før sletningen. D5a — dato-orden på assertion/haendelse/story og
  relationens perioder (start- og slut-par i orden + `start_min ≤ end_max`); writerne giver `DATO_INTERVAL_OMVENDT`
  (nu også story og OCR). D5b — lukkede lister for `date_qualifier`, `family_member.rolle`, konfidens og
  `conclusion.status`; `DATO_KVALIFIKATOR_UGYLDIG` med dansk tekst i web og mobil.
- **Målt før (læse-kun):** `afbildet` kun `person→media` (11) og `media→coat_of_arms` (2); 0 omvendte intervaller; alle
  listeværdier inden for listerne. Efter: 13 af 13 medier synlige for anon (uændret — ingen familiebilleder).
- **Øvelse:** stand-in `kar20261122_…h130` (prod 21/11 + blok 1+2, midlertidigt omdøbt): prøve → commit → fortryd-prøve
  → fortryd (`P_FORTRYD_TROFAST`) → commit. Stand-in'en har nu blok 1-3. Prod: prøve, derefter commit.
- **Efterkontrol (læse-kun, MCP):** 12 CHECKs validerede; nye funktioner kun ejer-EXECUTE; ingen `anon`-EXECUTE på de
  berørte `red_*`. `get_advisors` (security): identisk med før blokken (samme fund og antal pr. type).
- **Fortryd:** `/bin/zsh -f ~/.private/review37-b3/prod.zsh fortryd [--jeg-mener-det]` (dropper de 12 CHECKs og 2 nye
  funktioner; prods egne 11 definitioner fra før apply: `~/.private/review37-b3/fortryd-definitioner.prod.sql`).
- **Kendte rester (#397):** simpel `red_slet_person` låser hverken person- eller familiebilleder; fortryd af et gammelt
  ændringssæt, hvis snapshot bryder en ny CHECK, fejler med rå 23514 (ikke målt); S3 — billede af en medlemsløs familie
  er synligt (`family_offentlig` sand for tom familie; afventer afgørelse); medie-fletning kender ikke familie-/
  stedbilleder; story-editorens kvalifikator er fritekst.

## 42. Review 37 blok 2: slægtsnavn fra linjemedlemskab, »Ret« rammer det viste, datotjek — LIVE i prod (2026-11-22)

**Grundlag:** decisions 2026-11-22 (BESLUTTET: review 37's databasefund, pakke B), PR #436 (CI grøn på `d6ce73f6`).
Privat runner `~/.private/review37-b2/prod.zsh`, fastlåst på `d6ce73f6` (blok-sha `9257af0c…`), kørt i projektejerens
shell. PR'en blev merget ~30 s **før** DDL'en; uden betydning her (den nye fejltekst virker i begge rækkefølger), men
rækkefølgen DDL → merge gælder fortsat for blokke med web-afhængighed.

- **DDL + data (én transaktion):** før-billede (`tests/sql/review37-b2-backfill-foer.sql`) → blokken
  `-- BEGIN review37-b2` … `-- END review37-b2` (db-migrations.sql) → backfill (`tests/sql/review37-b2-backfill.sql`).
  Præcis 11 katalogobjekter: `private.person_visnings_fakt`, `red_opret_fakta`, `red_upsert_fakta`,
  `red_tilfoej_oplysning`, `red_promote_placement_memberships`, `red_reverse_placement_membership`,
  `regen_person_visning`, `trg_regen_from_lineage`, `trg_regen_from_lineage_membership` og triggerne
  `lineage.trg_lineage_regen`, `person_lineage_membership.trg_lineage_membership_regen`. Facit (`P_FACIT_OK`) og
  invarianter ens; 7,8 s.
- **Data:** **495** personer fik `visning_efternavn`/`visning_fuldt_navn` fra deres linjemedlemskab; intet andet ændret
  (backfillens kontroller: ændrede ⊆ kandidater = uafhængig forudsigelse, karantæne og historik uændret, prøve-regen af
  alle andre personer ændrer intet). Første prøve stoppede som ventet på `forventet 504` (runnerens default); prods tal
  = stand-in'ens 495 (21/11-data) → `P_FORVENTET=495`. Efter: 1.102 af 1.802 personer har efternavn.
- **Effekt:** D1+D12 — slægtsnavnet hentes også fra linjemedlemskaber og regenereres ved ændring af medlemskab og linje
  (også DELETE og ændret `kode`/`source_id`). D1 — medlemskabs-writerne låser personen før medlemskabet (ingen 40P01
  mod personsletning). D3 — »Ret« rammer den viste oplysning; navn/fødsel/død vises i bogens orden. D5 (RPC) —
  redigerings-RPC'erne afviser omvendt datointerval (`DATO_INTERVAL_OMVENDT`, dansk tekst i web og mobil).
- **Øvelse:** prod-formet stand-in med blok 1: prøve → commit → fortryd (katalog og cache trofast) → commit →
  fortryd-prøve. Prod: prøve (stop på antal), prøve, commit.
- **Efterkontrol (læse-kun, MCP):** begge triggere findes og er aktive; ingen af de fem `red_*` (SECURITY DEFINER) kan
  køres af `anon`; hjælperen og trigger-funktionerne er INVOKER med kun ejer-EXECUTE; `regen_person_visning` har som
  før PUBLIC-EXECUTE (INVOKER, så RLS gælder).
  `get_advisors`: ingen nye fund for blokkens objekter (de fem `red_*` står som før under
  `authenticated_security_definer_function_executable`).
- **Fortryd:** `/bin/zsh -f ~/.private/review37-b2/prod.zsh fortryd [--jeg-mener-det]` (prods egne definitioner fra før
  apply: `~/.private/review37-b2/fortryd-definitioner.prod.sql`).
- **Kendt rest:** `red_fortryd_change_set` låser medlemsrækken før triggeren opdaterer personen ved fortrydelse af
  medlemskabs-events — samme mønster som for `conclusion`/`person_external_id`; åbent punkt i #397.

## 41. Review 37 blok 1: fortryd, udgavehistorik, bogmærke-orakel, FK-indeks — LIVE i prod (2026-11-22)

**Grundlag:** decisions 2026-11-22 (BESLUTTET: review 37's databasefund, pakke B), PR #434 (CI grøn på `974a6773`).
Privat runner `~/.private/review37-b1/prod.zsh`, fastlåst på `974a6773` (blok-sha `5ef7da7c…`), kørt i projektejerens
shell **efter** merge (ingen web-afhængighed; vagten tillader main = præcis blokkens SQL).

- **DDL:** blokken `-- BEGIN review37-b1` … `-- END review37-b1` (db-migrations.sql) + DO-blokken
  `$review37_b1_bookmark$` (db-rls.sql) i én transaktion — ikke hele db-rls.sql. Præcis 10 katalogobjekter:
  `_version_upsert_row`, `red_fortryd_change_set`, `red_publicer_udgave` (nye kroppe, uændret ACL), politikken
  `bookmark.bookmark_insert_own`, 6 indeks (`ix_haendelse_fact_id/_relation_id`, `ix_story_fact_id/_relation_id/
  _historical_event_id`, `ix_bookmark_person_id`). Facit (frisk base af samme commit) ens; data uændret; 3,0 s.
- **Effekt:** D2 — ældre ændringssæt kan fortrydes uden `force`, når kun nyere kolonner mangler i snapshottet (190
  relationssæt, 17 påstande, 16 medier m.fl.); sæt hvis rækker reelt er ændret/slettet afvises stadig. D7 —
  `red_publicer_udgave` står i historikken og kan fortrydes. S2 — medlemmer afvises (42501) ved bogmærke på skjulte og
  ikke-eksisterende id'er; redaktionen må. Y9 — FK-opslag i `haendelse`/`story`/`bookmark` er indekseret.
- **Øvelse:** prod-formet stand-in: prøve → commit → fortryd (katalog trofast) → commit. Prod: prøve, derefter commit.
- **Efterkontrol (læse-kun):** 6 gyldige indeks, ny politik, nye kroppe; forsiden 200. `get_advisors` via MCP gav
  adgangsfejl (ingen nye tabeller/funktioner i blokken).
- **Fortryd:** `/bin/zsh -f ~/.private/review37-b1/prod.zsh fortryd [--jeg-mener-det]` (prods egne 3 definitioner fra
  før apply + gammel politik; dropper de 6 indeks; katalog-sammenligning med før).

## 40. Første hændelses-load (#130) — LIVE i prod (2026-11-22)

**Grundlag:** decisions 2026-11-21 (BESLUTTET: hændelseslaget opløser s.å./s.m./s.d. fra konteksten; udaterede
parkeres), PR #427 (første feed-uddeling venter højst 2,5 s; merget og udrullet **før** load) og PR #428 (eksportfilter,
H9, trin ③c). Kun data: ingen DDL, ingen web-ændring ud over #427.

- **Pipeline:** 1.097 narrativer eksporteret med gæstens læserflade (læse-kun) → Sonnet pr. narrativ → H1-H9 →
  ét Opus-forsøg på 32 flaggede narrativer → H9 daterede 259 hændelser ud fra sammenhængen → ③c lagde 34 hændelser
  uden datogrænse til side (`~/.private/h130/parkeret.json`, ÅBEN i decisions).
- **Load:** `load_haendelser.R ~/.private/h130/clean.json --jeg-mener-det` (sha256 `e706fdc0…`), efter to
  dry-runs mod prod med samme tal. Resultat `updates=0, inserts=3932, deletes=0, overfoerte=0, mistede=0,
  uoploeste=0`, 16 min under `SHARE ROW EXCLUSIVE` på `haendelse` (blokerer kun skrivere).
- **Efterkontrol (læse-kun):** 3.932 hændelser fra 764 narrativer (de øvrige 333 fik ingen hændelser), alle
  `kandidat`, 0 uden datogrænse, spænd 1223-2013; ingen låse tilbage.
- **Bladring som anon gennem prods PostgREST:** 6 sider, alle `200`, 3.932 rækker. Databasetid ~0,9 s pr. side
  (`EXPLAIN ANALYZE`, varm); samlet ~7 s varm. **Kold første side 3,2 s klientside** — tæt på anon-loftet på 3 s; et
  timeout giver ingen synlig fejl, kun manglende hændelseskort. Følges i #419/#422.
- **Konsekvens (A2):** de 764 narrativer kan ikke revideres, før redaktøren har fjernet deres hændelser
  (`NARRATIVE_RECORD_DERIVED_EVENTS_PRESENT`).
- **Fortryd:** prod havde 0 hændelser før; at tømme `haendelse` genskaber tilstanden og låser teksterne op igen.
  Redaktørens senere `feed_status`-markeringer går tabt ved en fuld tømning.

## 39. Hændelser ændrer ikke en biografis synlighed + feedet i bidder (review 37 A2+Y3) — LIVE i prod (2026-11-21)

**Grundlag:** decisions 2026-11-21 (BESLUTTET: hændelser ændrer ikke en biografis synlighed; feedet henter hændelser i
bidder), spec `docs/superpowers/specs/2026-11-21-review37-a2-y3-haendelser-design.md`, PR #418 (CI grøn på `09249df1`,
merget `535536b8`). Privat runner `~/.private/review37-a2y3/prod.zsh`, fastlåst på `09249df1`; kørt i projektejerens
shell **før** merge (webklienten kalder den nye RPC).

- **DDL:** blokkene `-- BEGIN review37-a2` … `-- END review37-a2` og `-- BEGIN review37-y3` … `-- END review37-y3` fra
  `db-migrations.sql` + DO-blokken `$review37_y3_acl$` fra `db-rls.sql`, i én transaktion (sha256 `d15e8ef1…`). **Ikke
  hele `db-rls.sql`:** dens politikgenskabelse låser tabellerne for gæsternes læsninger, og `db-rls.sql:805` (REVOKE fra
  før #152-cutover) ville lukke redaktørens narrativ-writers. Nyt: `private.narrative_har_haendelse`,
  `public.public_haendelse_feed` (anon/authenticated), `private.feed_cursor_noegle` (én privat nøgle, RLS, ingen
  klientadgang), indekset `ix_haendelse_narrative_id`; ændret: 9 private/redaktionsfunktioner (publiceringstilstand,
  editor-tilstand, fortrydelse, personsletningens undtagelser). Ingen tabellås for læsere; 40 s.
- **Invarianter i transaktionen:** katalog-diff = præcis de 15 forventede objekter; facit (md5 af kroppe fra en frisk
  base af `09249df1`) 11/11; fingeraftryk af `publication_state` + editor-`state_sha256` for alle 1.151 bindinger og
  legacy-tilstand for 550 grundlinjer uændret; gæstens 1.099 narrativ-id'er uændret; data uændret;
  `OK: #415 synlighed pr. samme_som-gruppe`; røgtest som anon (1 kald, 0 rækker, 5 ms).
- **Efterkontrol (frisk forbindelse + prods PostgREST som anon):** `tal` = anvendt, `haendelse=0`; RPC'en svarer `200`
  med `rows=[]`, `naeste=null` (0,18-0,69 s); falsk bladremærke `400 FEED_CURSOR_INVALID`; nøgletabellen ikke
  eksponeret. Prods katalog før apply = frisk base af `bc3b1c46` (456/456 funktionskroppe;
  `~/.private/review37-a2y3/katalog-20261121/RESULTAT.md`).
- **Generalprøve** på stand-in fra læsedump 21/11 (efter #415): prøve, commit, fortryd prøve + commit (katalog byte-ens
  med før), apply igen; derefter færdigbevis §6 med syntetisk #130-load (5.880 hændelser): gæstens narrativ-mængde
  uændret ved (a)-(d); publiceret binding låses (`text_editable` true→false) uden at synligheden ændres, kladde uændret;
  maks 480 ms pr. kald; samlet bladring gennem lokal PostgREST 8 kald ≈ 3,0 s (gammel tabellæsning 15,9 s). Den
  samlede ventetid i prod måles efter #130 (#419). Revise-afvisning, reversal og genimport-fortrydelse er dækket af CI
  (kontrakt- og sletningstestene), ikke af stand-in'en.
- **Fortryd:** `/bin/zsh -f ~/.private/review37-a2y3/prod.zsh fortryd` (prøve) / `fortryd --jeg-mener-det`: genskaber
  prods egne 9 definitioner fra før apply og dropper feed, hjælper, nøgle og indeks; nægter, når `haendelse` > 0 (de
  gamle kroppe lader hændelser ændre en biografis synlighed). Kræver, at web samtidig rulles tilbage.
- **Vercel-røgtest som anon** (live efter merge, 21/11): forsiden kalder `public_haendelse_feed` (200). Samme
  sidevisning viste en **ældre fejl**: `public_person_bio_source_versions_v2` med alle 1.725 offentlige id'er i ét kald
  rammer anon-loftet (`57014`, 3,2 s), så »Nævnt i Aarbogen« udebliver. Ikke forårsaget af A2: stand-in-tider for samme
  kald er 3,04-3,10 s (dump 20/11, før #415), 3,14-3,17 s (21/11, før A2) og 3,13 s (med A2). Klienten sender alle id'er
  i ét kald (`web/src/data/feedAux.ts`).
- **Bio-kaldet rettet i klienten** (#420 + #421, 21/11): biografierne hentes i bidder à 50 med højst 3 samtidige
  kald (#420's 9 parallelle bidder à 200 ramte stadig loftet, 7/9 afbrudt). Målt som anon i prod: 35/35 kald `200`,
  maks 2,27 s live (1,38-1,89 s i forhåndsmålingerne), ~10-12 s samlet. **Rettet:** tallet »første kort efter 0,4-0,5 s«
  var forkert — målingen fangede noget andet på siden; `FeedStreamView` ventede på alle kilder inkl. biografierne, så gæster
  ventede ~10-12 s. Første uddeling har nu en frist på 2,5 s (`FEED_FOERSTE_UDDELING_FRIST_MS`); sene biografier og
  hændelser fylder de næste blade. **Fejl i #427, rettet 22/11 (`fix/feed-frist-tom-uddeling`):** uden biografier gav puljen ved fristen kun samlekortet; det
  blev fjernet ved genopbygningen, og forsiden stod med »Henter blade« for evigt. Nu deles der kun ud ved fristen, hvis der
  er egentlige blade; første portion fyldes op til seks, når data kommer. Målt i et produktionsbyg mod prod: 6 blade efter
  17-20 s — feedets indhold afhænger af biografierne, så hastigheden ligger i #422. RPC'en koster ~10 ms pr. id i prod (stand-in ~2,5 ms) — server-side optimering i #422.
  **Åbent:** visuel bekræftelse af »Nævnt i Aarbogen«-kort (den hovedløse røgtest viste kun ~7 kort uden ét).
- **#130** er frigivet (spec §7): A2, RPC'en og webklienten er i prod og efterkontrolleret som anon.

## 38. Synlighed pr. samme_som-gruppe (#415) — LIVE i prod (2026-11-21)

**Grundlag:** decisions 2026-11-21 (BESLUTTET: levende og privat smitter, staged gør ikke), PR #417 (CI grøn). Privat
runner `~/.private/415-synlighed/prod.zsh`, fastlåst på `8f9695e1` (kode) og `151f9f47` (main før), kørt i
projektejerens shell før merge (ingen web-ændring).

- **DDL:** kun blokken `-- ===== #415 samme_som-synlighed` … `-- END #415 samme_som-synlighed` fra `db-migrations.sql`
  + `person_offentlig` fra `db-rls.sql`, i én transaktion (SQL sha256 `6bd56263…`; prøven `26064feb…`). Nyt:
  `person_gruppe_skjult` (plpgsql, DEFINER, ingen klient-EXECUTE), `trg_regen_from_samme_som` + triggerne
  `trg_samme_som_regen_ins/_del` på `relation`, delindekserne `ix_relation_samme_som_subjekt/_objekt`; ændret:
  `person_offentlig`, `regen_person_floruit`, `trg_regen_from_person_offentlighed`. Ingen ACCESS EXCLUSIVE-lås (kontrolleret
  i transaktionen); 6 s.
- **Invarianter i transaktionen:** 0 personer, 0 familier og 0 `visning_floruit` skifter (før/efter-sammenligning pr.
  id); `change_set`/`change_event` uændrede; `OK: visning-floruit katalog` og `OK: #415 synlighed pr. samme_som-gruppe`.
- **Gæstetider i prod** (server-side `count(*)` som anon, før → efter): fakta 0,57 → 1,05 s, relationer 0,26 → 0,47 s,
  personer 18 → 76 ms, familiemedlemmer 21 → 96 ms, koordinater 0,28 → 0,31 s (anon-loft 3 s).
- **Frisk forbindelse bagefter:** `tjek` grøn; 1725 offentlige personer (uændret), 1434/1343/1344 skjult, de 7
  staged-par (13, 43, 134, 178, 298, 1048, 1354) offentlige, `person_gruppe_skjult` uden anon/authenticated-EXECUTE.
  Supabase-advisors ikke kørt (MCP'en ser ikke DAA-projektet).
- **Generalprøve** på stand-in fra læse-kun data-dump 21/11 (narrativ-kontrakt sat til prods v2): prøve, commit,
  gentaget apply afvist (`G415_ALLEREDE_ANVENDT`), fortryd prøve + commit, apply igen; alle 0/0/0. Prods definitioner af
  `person_offentlig`, `family_offentlig`, `regen_person_floruit` og person-triggerfunktionen var identiske med main@151f9f47.
- **Fortryd:** `zsh ~/.private/415-synlighed/prod.zsh fortryd` (prøve) / `fortryd --jeg-mener-det`: genskaber
  main@151f9f47's definitioner, dropper hjælper, triggere og indekser; samme invarianter.
- **Bortfaldet:** pligten til omfangsmåling efter hver sammenfoldning (db-verify-blokken måler lækagen).

## 37. Personsletning for ikke-offentlig person: familieindhold slettes, bevarede billeder låses (review 37 P1+P2) — LIVE i prod (2026-11-20)

**Grundlag:** decisions 2026-11-20 (løsning A + afgrænsning), spec `docs/superpowers/specs/2026-11-14-fuld-personsletning-design.md`,
slettegraf `docs/superpowers/plans/personsletning/slettegraf.md`, PR #410 (merget `015b10cb`). Privat runner
`~/.private/review37-p1p2/prod.zsh`, kørt i projektejerens shell efter merge (web tåler den gamle database).

- **DDL:** kun blokken `-- ===== review37-p1p2: …` … `-- END review37-p1p2` fra `db-migrations.sql` @ `015b10cb`
  (sha `9ae1da00…`): 10 funktioner (`red_slet_person_helt` og `private.person_purge_*`; nye:
  `person_purge_ikke_offentlig`, `person_purge_familieindhold`, kun ejeren kan kalde dem). Ingen data ændret.
  Invarianter i transaktionen: `md5(pg_get_functiondef)` for alle 10 = frisk base af samme SQL; ACL; tal for `person`,
  `family`, `fact`, `relation`, `media` (+ frigivne), `note`, `change_set`, `change_event` uændrede. 42 s (inkl. røgtest).
- **Røgtest i transaktionen** (historik → plan → preview → kontrol for de 3 personer med flest fakta, 1 levende og 1
  afbildet): koldt 1,6-12,6 s (306 er tungest), varmt 1,4-1,8 s. Kold første preview over 8 s var kendt med den gamle
  kode (18/11, backlog: 8 s-loft for store profiler); dialogen siger »prøv igen«.
- **Generalprøve** på stand-in fra `daa-prod-20261120202702-laes.dump` (sha `6ac3a0a9…`): prøve, commit, gentaget apply
  afvist, fortryd trofast (hashes = før), apply igen.
- **Efter (ny, læse-kun forbindelse):** alle 10 hashes = facit.
- **Web live:** Redaktion-bundtet indeholder de nye kontrolgrunde (`laast_familiefoto`).
- **Fortrydelse:** `prod.zsh fortryd --jeg-mener-det` genskaber prods egne 8 definitioner fra før
  (`~/.private/review37-p1p2/fortryd-definitioner.prod.sql`) og dropper de 2 nye.
- **Stopregel ophævet:** »Slet helt« må igen bruges på personer med billeder.

## 36. OCR-rettelse af kildepåstand uden importanker (`red_ret_ocr_paastand`) — LIVE i prod (2026-11-20)

**Grundlag:** decisions 2026-11-20, plan `docs/superpowers/plans/2026-11-20-ocr-rettelse-af-kildepaastand.md`, PR #407.
Runbook `docs/runbooks/ocr-paastand-prod.md`. Privat runner `~/.private/ocr-paastand-407/prod.zsh`, kørt i
projektejerens shell før merge.

- **DDL:** kun blokken `-- ===== ocr-rettelse af kildepåstand` … `-- END ocr-rettelse af kildepåstand` fra
  `db-migrations.sql` @ `f7dcf575` (sha `6d299c81…`): `paastand_korrektion_grund_check` tillader også `ocr`; ny
  `public.red_ret_ocr_paastand(bigint,jsonb,jsonb)` (security definer, kun `authenticated`). Invarianter i
  transaktionen: `person`, `fact`, `assertion`, `paastand_korrektion`, `change_set`, `change_event` og
  `visning_foedt/doed` uændrede. 695 ms.
- **Efter (ny forbindelse):** funktion 1, CHECK med `ocr` 1, anon 0, authenticated 1; journal `bogen_har_ret` 27,
  `linjeskift-v1` 70, ingen `ocr`.
- **Web:** »Ret læsefejl« (»Aa«) på kildepåstande i personeditoren, kun for redaktører.
- **Web live:** #407 merget (`8b2301ca`); Vercel-bundtet indeholder »Ret læsefejl« (kontrolleret efter merge).
- **1559 (færdigbevis):** projektejeren rettede fødslen i Redaktion. Assertion 13833 (fact 11315) er nu »25 Marts
  1578«, `date_min/max` 1578-01-01/1578-12-31 (parseren læser formatet uden punktum som år), stadig 1 påstand;
  `visning_foedt` = »25 Marts 1578«. Journalen: én `ocr`-række, `foer.date_raw` »25 Marts 157«, ingen fortolkning,
  change_set-operation `red_ret_ocr_paastand`, ikke fortrudt.

## 35. Faktatypen `fødenavn` og præsenslistens født-klausul (#401) — LIVE i prod (2026-11-20)

**Grundlag:** spec `docs/superpowers/specs/2026-11-20-foedenavn-design.md`, plan
`docs/superpowers/plans/2026-11-20-foedenavn.md`, PR #403 (merget `816605c3`). Privat runner
`~/.private/visning-cache-396/prod.zsh vocab`, kørt i projektejerens shell før merge.

- **DDL (data):** kun blokken `-- ===== fødenavn-faktatype` … `-- END fødenavn-faktatype` fra `db-migrations.sql` @
  `0d9cf40c` (sha `488b6dd7…`): én vocab-række `('faktatype','fødenavn')`. Invarianter: vocab +1, `fact`, `person`,
  `change_set`, `change_event` uændrede. Generalprøve på stand-in fra `daa-prod-20261120132821-laes.dump` (sha
  `71045928…`): prøve, commit, gentagelse uden ny række.
- **Web:** Vercel promoverede ikke main automatisk (slået fra siden floruit-rollbacken samme dag); projektejeren
  promoverede `816605c3` manuelt. Kontrol: Redaktion- og redaktionRead-bundtet indeholder feltet.
- **811:** projektejeren registrerede hendes fødenavn i Redaktion med kilde (fact 12203, afklaret, ét citat). Triggeren
  regenererede hendes cache med #396's regel, så det håndskrevne `visning_efternavn` fra 24/7 er væk; drift under
  reglen er 0 (`prod.zsh tal`). `prod.zsh rest` blev ikke brugt.
- **Fortrydelse:** `DELETE FROM vocab WHERE scheme='faktatype' AND code='fødenavn'` kun mens ingen fact bruger
  typen; i dag bruger 811's fact den, så fortrydelse er en redaktionel sletning først.

## 34. Visningscachens titel- og datoregel (#396) — LIVE i prod (2026-11-20)

**Grundlag:** issue #396, PR #400 (commit `5f115574`), runbook `docs/runbooks/visning-cache-regler-prod.md`. Privat
runner `~/.private/visning-cache-396/prod.zsh`, kørt i projektejerens shell.

- **DDL + backfill** (én transaktion, 1,2 s): kun blokken `-- ===== visning-cache-regler` … `-- END visning-cache-regler`
  fra `db-migrations.sql` @ `5f115574` (sha `2488a570…`) — en ny `regen_person_visning` — og regen af 392 og 1088.
  `db-rls.sql` er ikke kørt (ingen nye objekter eller rettigheder).
- **Invarianter før COMMIT:** driften under den nye regel før backfill = {392, 811, 1088}; kun `visning_titel` på 392
  og 1088 ændret; ingen drift bagefter uden for den udeladte 811; `slaegtsnavn_karantaene` og
  `change_set`/`change_event` uændrede.
- **Tal:** driften var 83 personer (titel 68, død 13, efternavn 2, fuldt navn 1). Under den nye regel er kun 392
  (storkansler → Greve), 1088 (Sekltnt. → Fændrik ved sjæll. Inf.Reg.), 852 og 811 ude af takt. 852 er rettet
  redaktionelt (change_set 4588: navn »Beke Ahlefeldt-Laurvig«, titel »Komtesse«); 811 står tilbage med vilje (#401).
  Floruit uændret: 232.
- **Generalprøve:** stand-in fra `daa-prod-20261120123209-laes.dump` (sha `4a946268…`): apply prøve/commit, fortryd
  (gendanner storkansler/Sekltnt.), apply igen; en fremmed drift stopper ceremonien. Fuld `db-verify.sql` grøn på frisk
  base, `OK: visning-cache-regler` fejler mod den gamle funktion.
- **Fortrydelse:** `prod.zsh fortryd --jeg-mener-det` genskaber prods egen definition fra før kørslen
  (`~/.private/visning-cache-396/fortryd-definition.prod.sql`) og regenererer 392 og 1088. Web er upåvirket.
  NB: floruit-fortrydelsen (§33) genindfører `max()`-reglen.

## 33. `visning_floruit`: »Nævnes …« for personer uden livsdatoer — LIVE i prod (2026-11-20)

**Grundlag:** spec `docs/superpowers/specs/2026-11-19-visning-floruit-design.md`, plan
`docs/superpowers/plans/2026-11-19-visning-floruit.md`, runbook `docs/runbooks/visning-floruit-prod.md`. PR #398 merget
som `5e274f54`. Privat runner `~/.private/visning-floruit/prod.zsh`, kørt i projektejerens shell.

- **DDL + backfill** (én transaktion, 2,5 s, låsevindue ca. 2 s): kun blokken `-- ===== visning-floruit` …
  `-- END visning-floruit` fra `db-migrations.sql` @ `5e274f54` (sha `856e1ecf…`; stopregel A1), katalogtjekket
  `OK: visning-floruit katalog` og `SELECT regen_person_floruit(id) FROM person`. `db-rls.sql` er ikke kørt (uændret
  siden §32; blokken har egen `REVOKE … FROM PUBLIC, anon, authenticated, service_role`).
  - Nyt: kolonnen `person.visning_floruit` (cache, i `version_pk_registry.skip_cols` og sletteinventarets S1),
    `regen_person_floruit(pid)` (skriver kun den kolonne; NULL ved livsdatoer), `regen_familie_partnere(family_id)`,
    triggerne `trg_family_member_regen` og `trg_person_offentlighed_regen`. `regen_person_visning` kalder
    `regen_person_floruit` sidst; konklusions-/påstandstriggerne regenererer familiens partnere ved familie-fakta.
  - Invarianter før COMMIT: personrækkerne uændrede bortset fra kolonnen, `change_set`/`change_event` uændrede,
    `(id, visning_floruit)` = uafhængigt facit, ingen person med både floruit og livsdatoer.
- **Tal:** 1802 personer; 232 med floruit, heraf 33 med spænd; 0 påstande med `date_min > date_max`.
- **Efterkontrol:** anon-REST `person?select=id,visning_floruit` 200 (44 = `1349–1391`, 594 = `1657`, 392 = null;
  232 rækker synlige). Browser som anon, desktop og mobil: 44 og 594 viser »Nævnes …«, Conrad (392) viser
  `1644–1708`, ingen »Livsdatoer ikke angivet«, ingen fejlende Supabase-kald.
- **Hændelse:** #398 blev merget før DDL'en; Vercel deployede main, og person-hentningen fejlede (`42703`), indtil
  projektejeren rullede produktion tilbage (Instant Rollback). Efter DDL'en er main promoveret igen.
- **Generalprøve:** stand-in fra `daa-prod-20261118191613-laes.dump` med prods standard-EXECUTE efterlignet:
  apply (prøve/commit), afvisning af dobbeltkørsel, fortryd (prøve/commit), apply igen; fuld `db-verify.sql` @
  `5e274f54` grøn (155 OK). Detaljer i runbooken.
- **Fortrydelse:** `prod.zsh fortryd --jeg-mener-det` genskaber prods egne definitioner fra før kørslen
  (`~/.private/visning-floruit/fortryd-definitioner.prod.sql`), dropper de nye objekter og nulstiller kolonnen.
  Kolonnen bliver. Web på main læser kolonnen, så fortryd kræver også et Vercel-bundt fra før #398.
- **Security Advisor** (projektejeren i dashboardet, 2026-11-20 efter DDL): intet fund nævner de fire nye funktioner eller
  triggerne. Fundene er de kendte: 12 `anon_security_definer_function_executable` på læserfunktionerne (11 som 12/11 plus
  `public_person_source_coordinates_samlet` fra §31), `authenticated_…` på `public.red_*`/`current_rolle`/`hist_*`,
  `rls_enabled_no_policy` (INFO) på private/interne tabeller og `auth_leaked_password_protection` (kræver Pro, parkeret).
- **Står tilbage:** issue #396 (cache-drift i 83 rækker, uændret af denne ændring); leverance 2 (biografierne).

## 32. `record_persona`: Henrik og Iven får deres egen 1939-tekst — LIVE i prod (2026-11-18)

**Grundlag:** spec `docs/superpowers/specs/2026-11-17-persona-for-post-uden-tekst-design.md`, plan
`docs/superpowers/plans/2026-11-17-persona-for-post-uden-tekst.md` og runbook `docs/runbooks/record-persona-prod.md`.
PR #382 er merget som `aca139a0`. Runneren `42-record-persona.sh` (privat) blev kørt i projektejerens shell med GO.

- **DDL** (GO `27a5a0e6`, 37,9 s): halen af `db-migrations.sql` fra blokken »Fuld personsletning (2026-11-14)« til
  filens slutning (sha `af15ee3e…`) plus `db-rls.sql` (`c0c62fb2…`), i én transaktion.
  - Nyt: operationen `record_persona` (writer `private.write_record_persona` og wrapper
    `red_apply_reimport_record_persona`).
  - Spærring: `legacy_withdrawn` kan ikke fortrydes, når personen har en record-binding i kilden
    (`NARRATIVE_LEGACY_RECORD_BINDING_EXISTS`).
  - Fortrydelse af legacy kræver `READ COMMITTED`.
  - Personsletningens kode (#369/#377/#380) er installeret, men ubrugt indtil dens egen ceremoni (Task 13).
  - Note 72 (forældreløs, family 54) er slettet i samme transaktion under db-verify's forbetingelse. Begge dele er
    projektejerens afgørelser fra 2026-11-18.
- **Data** (GO `4dee6d18`, ceremoni 113 s): `T_RP_OK personas=2 identiteter=2 placements=2 medlemskab=2 kladder=2`
  for `record-e63debca…` → 934 og `record-9db9004f…` → 929 (kortmanifest `20b4a68d…`, svar `c753aea9…`).
- **Efterkontrol:** runnerens måling efter commit hang på en død forbindelse og blev stoppet. Derefter er tre
  kontroller kørt særskilt:
  - `verify`: tal 2,2,2,2,2,0,554, FAKTA og BIO uændrede.
  - `vindue`: 4 change_sets, alle ceremoniens, og basen er lig aftrykket efter ceremonien.
  - `anon`: inden for budget.
- **Publicering:** projektejeren rettede OCR og publicerede de to kladder i Redaktion. `bevis` (anon): synlige
  1939-tekster 554 → **555**, læseren viser de nye tekster, og KOORD og FAKTA er uændrede.
- **Generalprøve:** stand-ins fra prod-kopien 2026-11-18 (fremad, simuleret publicering, fortryd-data, fortryd-DDL,
  negativer og en kørsel med fastlåst runner). Detaljer står i runbooken.
- **Fortrydelse:** lukket efter publiceringen. Rettelser i teksterne sker i Redaktion som revisioner.
- **Ikke kørt:** Security- og Performance-advisors (MCP når ikke prod; projektejeren kører dem i dashboardet).
- **Står tilbage:** backlog #381 (generel batch-fortrydelse) og personsletningens Task 13.

## 31. Review 36, bølge 2's DB-spor (#361): låse, portrætregel, indeks og ét koordinatkald — LIVE i prod (2026-11-15)

**Grundlag:** `docs/reviews/36-helhedsreview-kodebase-2026-11-12.md` (fund D1, P6, K6, K5, P2), PR #361 merget som
`7ddb76cb`. Halen fra `-- ===== kodereview-36-p6` til filens slutning i `db-migrations.sql` (sha `46c69383…`, 255
linjer), derefter `db-rls.sql`, hver i én transaktion. Projektejeren kørte `deploy-361.sh --jeg-mener-prod` i sin shell
(hash-tjek af commit og hale, forhåndstjek, hale, RLS, efterkontrol); sessionen læste kvitteringen.

- **P6:** indeks `ix_conclusion_valgt_assertion` på `conclusion.valgt_assertion_id`.
- **K6:** højst ét primært portræt pr. person: `relation_hoejst_et_primaert_portraet` (`EXCLUDE … DEFERRABLE INITIALLY
  DEFERRED`), og `red_saet_portraet` låser personen efter `begin_change_set`. Forhåndstjek: 0 personer med flere.
- **K5:** `red_fortryd_change_set` låser ændringssættet (`FOR UPDATE`), derefter de berørte personer stigende og øvrige
  rækker i fast orden via ny `_version_lock_row(text,jsonb)` (lukket for `PUBLIC`/`anon`/`authenticated`).
- **P2:** `public_person_source_coordinates_samlet()` giver koordinaterne som ét jsonb-svar (sorteret efter
  `person_id, source_id`), så PostgREST's grænse på 1.000 rækker ikke deler kaldet op. Web og mobil kalder den via
  `fetchPublicCoordinates` i `@daa/core` og falder tilbage til rækkefunktionen ved `PGRST202`/`42883`.
- **D1:** ingen prod-ændring; `schema.sql` er rettet til prods `private.narrative_record_state` (kun narrativer fra en
  `DAA-udgave`-kilde låses), og funktionen er med i paritetstjekket.
- **Efterkontrol (prod):** indeks 1; constraint udskudt; 0 dubletter; person-, sæt- og rækkelås findes; hjælperen lukket;
  samlet-funktionen kaldbar for `anon`/`authenticated`, 1.111 elementer = rækkefunktionens 1.111 og ens indhold;
  D1-filter 1. `db-rls.sql`: 150 authenticated-kaldbare `red_*`, 0 anon-kaldbare.
- **Læseren (anon):** samlet-kaldet 0,32 / 0,31 s (to kørsler, `READ ONLY`); før skulle klienten bruge mindst to kald.
- **Generalprøve:** kopi af stand-in `daa5ab_ddl_standin_20261114150000_fmd` (prod efter 6e-2): samme hale + RLS +
  efterkontrol, alt grønt, 1.111 koordinater. Kopien er slettet bagefter.
- **Fortrydelse:** intet snapshot; de tidligere definitioner står i `main` @ `f31e19dc`. Tilbagerulning er en ny migration.
- **Ikke kørt:** `db-verify.sql` mod prod og Security Advisor (MCP når ikke prod).
- **Står tilbage:** D1's generelle paritetsgate (18 funktioner skrevet forskelligt mellem frisk og migreret base,
  `private.ensure_reimport_operations` kun på migrerede); `feat/personsletning` skal rebases på #361.

## 30. Trin 6e-2: 1939's kildeetiket, trykte sider og koordinater — LIVE i prod (2026-11-14)

**Grundlag:** spec `2026-11-12-trin6e-laeserflade-design.md` (§12-tillægget), decisions 2026-11-13 (kildeetiketten,
afgørelse A), plan `2026-11-13-trin6e2-kildeetiket-koordinater.md`, runbook `docs/runbooks/trin6e2-prod.md`. Klient
#345 (deployet før DDL), tillæg #346, DB #347 merget som `8d4782af` (flettet med §29's #342). Privat runner
`~/.private/5ab-overfoersel/40-trin6e2.sh` (sha `234eb8e3…`); GO'erne bundet til `main` @ `8d4782af`. Projektejeren
kørte alle trin i sin shell; sessionen læste kvitteringerne. Færdigbevis: `evidensbaseret-genimport/laeserflade-6e2-prod.md`.

- **DDL** (GO `da5b40a6`, blok `0ad7c6c3…`, 658 linjer sidst i `db-migrations.sql`): `public.source.sidekort`
  (+ `source_sidekort_gyldigt`) og `source_trykt_side`/`side_trykt` omregner 1939's PDF-sider til særtrykkets trykte;
  læsbar postetiket for poster uden bogtrykt nøgle; `public_person_source_coordinates()` med 1939's entydige nøgle,
  `printed_page` og mængdebaseret linjemedlemskab; `public_person_facts` med trykt side. Begge RPC'er bærer §29's
  redaktør-gren (`db-verify`'s `redaktoer-ser-levende` grøn mod prod efter DDL). 12 funktioner, alle med
  `search_path`; `REVOKE ALL` før hver `GRANT`. `T6E2_APPLY_DDL_OK katalog=ok` (27,3 s); snapshot til `fortryd-ddl` i
  `prod/6e2/fortryd-ddl-20261114095036/` (4 funktioner før, 8 nye).
- **Data** (GO `0b9019de`, `etiket_ceremoni.sql` `6fb56fcf…`): én transaktion; 561 bindingers etiketter genpubliceret
  (33 uden placement), sidekortet skrevet, 5 linjenavne rettet til bogens ordlyd (III »… Ziesendorf.«, »I.«,
  »VI.« og stammeafsnittene »A.« og »B.«). 2 staged personers bindinger sprunget over (afgørelse A). `ETK_OK … stale=0`; 561 change_sets, alle
  ceremoniens; rækker afviger kun i ceremoniens 6 tabeller/sekvenser.
- **Målt (`maal`):** `BINDINGER_RECORD` 561 → 0, `UDEN_PLACEMENT` 33 → 0, `STALE` 0, offentlige biografier 1.100 og
  bundne fakta 2.264 uændrede; kilde 1's koordinater (`66e9afd9…`) og etiketter (`d97decc7…`) byte-ens;
  familiekilder `06e71a11…` → `75186593…`, skemaetiketter `83c4e28d…` → `f0cb8884…` (som alle generalprøver).
- **Læseren (anon):** koordinat-RPC'en 1.261 → 306 ms pr. kald (begge sider 2,5 → 0,6 s); Conrads biografi 120 → 157 ms.
  1.111 koordinatrækker, 0 `record-`/`legacy-source:`, 1939's højeste trykte side 92; stikprøve 5/5 mod bogen.
- **Dumps:** før `daa-prod-20261114085322-6e2.dump` (`331ac5b4…`, restore-hash `156c4073…`); ddl
  `daa-prod-20261114100655-6e2.dump` (`b47fd30d…`, restore-hash `09227d41…`); begge age-krypteret på SFTP (rundtur ok).
- **Fortrydelse:** data med ddl-dumpet (`fortryd`), DDL med snapshot-mappen (`fortryd-ddl`); begge prøvet i
  generalprøve 3. Efter færdigbeviset er rettelser almindelig redigering.
- **Tid i prod:** `maal` 35-47 s; DDL 27,3 s; ceremonien 120,1 s (604 sætninger, langsomste 19,4 s; stand-in 11,4 s);
  `apply-data` 180,6 s; `dump` 104-139 s + 83 s måling.
- **Ikke kørt:** Security Advisor i dashboardet (kun statisk); personsidens samlede indlæsning ikke tidsmålt.
- **Står tilbage:** de 2 staged 1939-poster beholder `record-` (decisions 2026-11-13); af 30 »formodet«-forældreled er
  28 rettet 2026-11-14 (change_set 4245-4272), 79/80 har »?« i 2018-20-bogen og forbliver `formodet` (decisions).

## 29. Redaktionen ser levende i personsidens fakta, familiekilder og koordinater — LIVE i prod (2026-11-13)

**Grundlag:** decisions 2026-11-13 (POC'ets regel for levende), PR #342 (draft ved deploy). Blokken
`redaktoer-ser-levende` sidst i `db-migrations.sql` (sha `c598f2a0…`) kørt af projektejeren med den private pakke
`~/.private/redaktoer-ser-levende/prod.zsh apply` (hash-låst; før-hashes = main's definitioner, målt identiske i
stand-in og 6e-2-generalprøven).

- **Ændring:** `public_person_facts`, `public_family_sources`, `public_person_source_coordinates` får
  `v_red:=current_rolle()='redaktion'` og `(v_red OR <gæste-gate>)`. Ingen RLS-ændring; `haendelse.redaktion_read`
  fandtes (målt 1). `person_offentlig`/`entitet_offentlig`/`family_offentlig`/narrativets udgivelsesregel uændrede.
- **Én transaktion:** hash-tjek → blok → db-verify-blokken (`OK: redaktoer-ser-levende`) → gæste-invarians før COMMIT.
- **Tal (prod):** gæst 1111 koordinater / 6469 fakta / 328 familiekilder før og efter; redaktion før 1111 / 6469 / 328,
  efter 1167 / 6768 / 328 (som generalprøven). Familiekilder +0: ingen bundne familier er ikke-offentlige i dag.
- **Fortrydelse:** `prod.zsh fortryd --jeg-mener-det` (kun fra anvendt tilstand → main's definitioner, én
  transaktion); prøvet apply → fortryd → apply på stand-in-kopi.
- **Ikke kørt:** Security Advisor (MCP når ikke prod). Ingen nye funktioner eller grants — kun nye kroppe.
- **Står tilbage (trin 2):** kildehenvisninger og biografi for levende følger narrativets udgivelsesregel.

## 28. 2018-20's fødsler og dødsfald bundet til bogens post — LIVE i prod (2026-11-12)

**Grundlag:** spec `2026-11-12-2018-20-dato-bindinger-design.md`, plan samme dato, runbook
`docs/runbooks/2018-20-dato-bindinger-prod.md`. Kode i PR #322 (merget `743787f3`), runbook #324 + #326; GO'erne bundet
til `main` @ `2ac193a9`. Privat runner `~/.private/5ab-overfoersel/38-dato-bindinger.sh` (sha `8d923049…`, med
`38-dato-vindue.sql`). Projektejeren kørte dumps og alle skrivende trin; sessionen kørte `maal`, `vejb`, `forbered-n`,
`kort`, `flet`, `go-*` og `verify`. Færdigbevis: `evidensbaseret-genimport/dato-bindinger-2018-20-prod.md`.

- **DDL** (GO `7f9e6656`): regel `dato-markoer-v2` (markøren afhænger af prædikatet: `*`/`f.` på fødsel, `†` på død)
  i `red_normaliser_forslag`; v1 er uændret. `tilstand=ddl verify=ok` (16,8 s; kvitteringen læst i ceremoniens session, loggen viser målingen foer → ddl med uændrede tal); writerens forrige definition og ACL står i
  `prod/dato/fortryd-ddl-20261112211215/`. Security Advisor kørt af projektejeren i dashboardet 2026-11-12 (efter `k`):
  intet nyt fra DDL'en — 11 anon-kaldbare `SECURITY DEFINER` er læser-RPC'erne, `red_normaliser_forslag` var
  authenticated-kaldbar før; ACL-hashen `9b59bcd7…` er ens i foer-, ddl- og n-dumpet. Leaked password protection kræver Pro
  (parkeret).
- **Normalisering `n`** (GO `50178e6e`): af kilde 1's 583 datoforslag (568 med skrivemåde-forskel, 15 uden fakta)
  fik 565 en ny version (`dato-markoer-v2`) i én `extraction_run`; derefter er 509 lig en påstand (`MATCH`), 59 stadig
  `SKRIVEMAADE` og 15 `NO_FACT`.
- **Kontrol og binding `k`** (GO `75ef1336`): stikprøven på 20 kort (alle `B`), 489 maskinelt accepteret, 509
  afgørelser og 509 bindinger (`machine-corroboration-v2`). Alle bindinger fra før findes stadig (nøglet sammenligning
  mod n-dumpet: `tabt:0,nye:509`). Bindinger i alt 1.759 → 2.268, hash `fa08bb8a…` → `c4ef58de…`.
- **Læseren:** kilde 1's fødsler med postens koordinat 67 → 334, dødsfald 88 → 330. Browsertjek som anon: Conrad (392)
  viser »DAA 2018-20, s. 201-202 · V-1« ved født og død; rest-personerne 10 og 20 viser uændret »DAA 2018-20«;
  0 `record-`/`legacy-source:`.
- **Vagten:** fulde aftryk før og efter hvert skridt. `n` må kun ændre `extraction_run`, `interpretation` og
  `interpretation_observation`; `k` kun `interpretation`, `interpretation_observation`, `interpretation_promotion` og
  `interpretation_promotion_batch`. Begge holdt.
- **Fortrydelse:** `k` med n-dumpet `daa-prod-20261112220624-dato.dump` (restore-hash `9ca72cd5…`), `n` med ddl-dumpet
  `daa-prod-20261112212606-dato.dump`, DDL med snapshot-mappen. Foer-dumpet er `daa-prod-20261112193719-dato.dump`
  (`a7add600…`). Efter `DATO_VERIFY_OK` er rettelser almindelig redigering.
- **Tid i prod:** `maal` 16-17,6 s; DDL 16,8 s (begge foer/DDL-tal fra ceremoniens session); `apply-n` 57,1 s; `kort` 44,9 s eksport; `dump` 162 s + 43 s
  måling; `apply-k` 95,4 s (verify 24,6 s); `verify` 42,2 s. `vejb`: største median 132 ms før og 137 ms efter
  (grænse 1.000 ms), kolde kald 0,6-0,7 s (anons grænse 3 s).
- **Står tilbage:** 59 `SKRIVEMAADE` (13 fødsler, 46 dødsfald) som `proposed`; del 2 (kort over dem) er ikke besluttet.

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

## 50. Portrætter fra DAA 2018-20 — data i prod (2026-11-24)

**Grundlag:** PR #466 (CI grøn i alle jobs), `R/billeder-2018-20-load.R --jeg-mener-det` kørt 24/11 fra grenen efter
projektejerens godkendelse af alle 24 usikre koblinger (svarfil sha256 `3c3beb4a…8040`). Ingen DDL; skrevet via
`red_upload_media`, `red_relation`, `red_registrer_media_variant`, `red_bekraeft_media_upload`, `red_upsert_fakta` og
`red_saet_portraet` (redaktør-uuid `ba4ce28d…`), én transaktion pr. billede. `--proev-binding` (READ ONLY) før kørslen.

- **Skrevet:** 156 `media` (id 18-173, `original_filnavn LIKE 'daa-2018-20-s%'`, `klar`, `maa_publiceres = true`,
  `rettigheder_status = 'ukendt'`), 312 varianter (thumb/medium), 201 `afbildet`-relationer til 179 personer, 156
  kreditlinjer (»Gengivet fra Danmarks Adels Aarbog 2018-20, s. N«), 4 portrætlåse (419→10, 515→16, 777→12, alias
  1275→13) så de viste portrætter er uændrede. 468 objekter i Storage-bucketen `media` (`redaktor/<sha>-<tier>.jpg`).
- **Verificeret som anon:** 0 af de 27 billeder, der afbilder en ikke-offentlig person, er synlige (heller ikke deres
  varianter eller 81 filer); de 129 øvrige er synlige med 258 varianter. Personside 534 i prod viser portræt,
  billedtekst og kreditlinje.
- **Advisors (security, MCP):** ingen ERROR; kun de kendte WARN/INFO.
- **Rettigheder:** uafklarede — se `docs/decisions.md` 2026-11-24. Forsidens billed-regel aktiveres, når web-delen af
  PR #466 er merget (Edge-filen hæves til format v2).

**Runde 2 — segl og medaljer (samme dag):** `--manifest …/manifest-runde2.json`, svarfil `gennemgang-runde2.txt`
(sha256 `ac7ee86e…`, projektejeren godkendte alle 5 kort). 11 `media` (id 174-184): 6 `segl` (s. 54) og 5 `medalje`
(s. 82, 83, 379); 8 synlige for anon (174, 175, 177, 179-183, med 16 varianter), 3 skjult og ukoblet, fordi personerne
ikke findes (Johann von Walstorp VI, 4; Otto von Muggele VIII, 2; Rantzau-medaljen VI, 39). Frederik 4. (861) koblet til
begge s. 83-medaljer sammen med Anna Sophia (470). 1 portrætlås: Claus (289) beholder sit maleri (media 31). Personside
59 (Hartwich) viser seglet som hovedbillede.

**Runde 3 — våben (samme dag):** `manifest-runde3.json`, svarfil `gennemgang-runde3.txt` (sha256 `802c6d30…`; projektejeren
godkendte med to rettelser: Revenfeld s. 405 udeladt, Vallø s. 58 også til Anna Sophia). 20 `media` af slags `våben`
(id 185-204), alle synlige for anon (40 varianter): stamvåben → slægts-roden (lineage 6), lensgreve 1767 → lineage 4,
greve 1673 → lineage 5, Vallø → estate 196 + person 470, og 16 personvåben (8 elefantridder-skjolde s. 68-75, våben på
kirkeinventar s. 59-65, fyrstinde af Slesvig → 470). `coat_of_arms` 1-2 er urørte. 8 portrætlåse sikrer, at de viste
portrætter er uændrede (fx 109→19, 510→67, 526→59, 882→68). Web-galleriet på våbensiden kom med PR #469.

**Runde 4 — godser og Hennekes våben (samme dag):** `manifest-runde4.json` (sha256 `e5a1fb98…`), svarfil
`gennemgang-runde4.txt` (sha256 `ae326dc3…`, ingen usikre). Gods-rækkerne valgt af projektejeren på et forhåndsark
(`runde4-forhaand/`, standard = flest ejere). 12 `media` (id 205-216), alle synlige for anon (24 varianter): 11 af slags
`gods` → estate 5 (Wittenberg), 169 (Sandbjerg), 172 (baroniet Brahetrolleborg), 170 (grevskabet Christianssæde), 119
(Altenhof), 145 (Emkendorf), 185 (Wulfshagen), 165 (Clausholm), 196 (grevskabet Vallø), 367 (Pederstrup med Skjelstofte)
og 182 (Koppel med … Etelsen …); Hennekes våben med håndskrift 1587 (s. 3, slags `våben`) → person 221. 1 portrætlås:
221→21. Godsnavnenes dubletter er åbne i #471; en sammenlægning skal flytte disse koblinger med. Advisors: ingen ERROR.
