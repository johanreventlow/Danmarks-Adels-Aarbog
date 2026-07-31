# Helhedsreview: redaktør-delen, data-import og missed opportunities

**Dato:** 2026-07-30
**Metode:** Multi-agent fan-out (3 parallelle Fable-reviewagents, én pr. vinkel) → syntese → adversarial krydstjek af de 6 skarpeste fund med Codex (gpt-5.6-sol) → empirisk prod-verifikation af det ene omstridte fund. Read-only; `work/`-mapperne (PII) er ikke læst af nogen agent og ikke sendt til Codex.
**Status-markering:** `verificeret` = læst i kode/fil (evt. + prod-opslag); `antaget` = indirekte evidens. Codex-verdict angivet hvor krydstjek er kørt.

---

## Executive summary

1. **Begge tilgange er "gode nok" — og bedre end som så.** Import-pipelinens deterministisk/LLM-snit er rigtigt og konsekvent skærpet efter målte fejl; redaktørens skrivemodel-kerne (rollegate → change_set → registry-drevet log → invers fortryd) er gennemarbejdet og konsekvent anvendt i ~60 RPC'er.
2. **Den ene strukturelle fejl er fælles for begge vinkler:** import-laget og redaktør-laget er to adskilte skriveverdener. Kun `red_ret_ocr_felt` har reload-invariante ankre; alt andet redaktionelt arbejde (samme_som, sletninger, narrativ-patches) er nøglet til person-id'er som en reload regenererer. Upsert/replay-blockeren er **tredje genopdagelse** af samme strukturfejl — designsessionen bør behandle den som arkitektur, ikke endnu et fixup. *(Codex: DELVIST — arkitekturlæsningen holder for al generel redaktion.)*
3. **Nyt bekræftet hul i fortryd-garantien:** `story_kilde` mangler i `version_pk_registry` → fortryd af `red_set_story_kilder` er en tavs no-op. *(Codex: BEKRÆFTET.)*
4. **Nyt Codex-fund:** `--force-reset`-listen rummer hverken `change_set` eller `change_event` — gammel id-baseret historik overlever reset og kan efter id-genbrug fremstå knyttet til forkerte rækker.
5. **Suggestion-flowet er kun en halv skrivemodel:** INSERT-vej findes, men ingen læse-/godkend-flade i nogen klient — UI'et lover "afventer redaktionel godkendelse" som ikke findes. *(Codex: BEKRÆFTET.)*
6. **Importens valideringstyngde sidder på det forkerte trin:** R1-R10 tjekker LLM-udtrækket mod segmenterens eget output, men segmenteringen — den empirisk dominerende fejlkilde (54 % materielle fejl i 1939-audit) — har ingen blokerende gate mod bogen.
7. **Spøgelses-union-guarden (navn≠ref) besluttet 2026-07-03 er stadig ikke i loaderen.** *(Codex: BEKRÆFTET.)* Latent under append; aktiv ved næste fulde load.
8. **Tre færdigbyggede forbrugslag står med slukket motor:** hændelseslaget (alle lag bygget, LLM-pas aldrig kørt), geo-berigelse (komplet pipeline + 6.788 TNG-koordinater, aldrig kørt), fuldtekstsøgning (GIN-indeks live i prod — empirisk verificeret — nul forbrugere).
9. **Forretningsmodellen har ingen teknisk bærebjælke:** rolle-universet er {redaktion, alt-andet=anon}; "medlem" og "forsker" findes kun som prosa; præsenslisten er reelt redaktions-eksklusiv.
10. **Kernen "er vi i familie?" ER bygget** på begge platforme med konfidens-visning — driften er ikke retning men allokering: fundamentsarbejde (1939-kvalitet/identitet) har fortrængt høst af det allerede byggede.

---

## Tema A — Replay-gabet (tvær-vinkel, kritisk)

*Sammenfletning af RED-1, IMP-3, IMP-5 + Codex-fund C1. Alle: verificeret.*

**Kernen:** `log_change()` (`schema.sql:3056`) logger intet uden åbent change_set — bulk-load-stien er per design usynlig for versioneringslaget. `load_daa.R` har kun to modes: append (dubletter ved gen-load) eller `--reset` (TRUNCATE CASCADE). Reset-guarden (`load_helpers.R:39-43`) blokerer på enhver `red_*`-operation undtagen `red_ret_ocr_felt` — og prod har redaktionelt arbejde i stort omfang (samme_som-links, dubletsletninger, narrativ-patches). Konsekvens: **re-ekstraktion kan i praksis ikke loades uden at ofre redaktionsarbejdet.** Artefakt og prod er allerede drevet fra hinanden (artefakt 539 poster, prod 515; genindlæsning ville genskabe 23 slettede dubletter — `docs/decisions.md` 2026-07-29).

**Codex-verdict (DELVIST):** én begrænset replay-mekanisme findes — `import_korrektion`-journalen holdes uden for reset, preloades via `(import_key, record_key)` og overlayes under load (`load_helpers.R:74`, `load_daa.R:284`); `post_load_fixup.R` genopretter desuden to hardkodede grundlægger-links. Men: OCR-rettelser og hardkodede fixups overlever; **al generel redaktion gør ikke.** Arkitekturlæsningen står.

**Codex-fund C1 (nyt, høj):** loader-hjælpeteksten hævder at `--force-reset` sletter change-set-arbejdet (`load_daa.R:42`), men reset-listen (`load_helpers.R:74`) indeholder hverken `change_set` eller `change_event` — og `backfill_slaegtled.R:69` bekræfter eksplicit at historikken overlever. Efter reset + id-genbrug kan gammel id-baseret historik fremstå knyttet til nye, forkerte rækker. Farligere end tabt historik.

**Systemisk mønster (IMP-5, medium):** prod-data rettes uden at producerende kode/artefakt rettes (spøgelses-unioner: kode urørt; apparatus-bleed: segmentering urørt; dubletsletninger: kun i basen) — og én gang omvendt (rettet kode, stale artefakt). Ingen kanonisk afstemt tilstand findes. Replay-laget løser det strukturelt.

**Anbefaling:** Designsessionen bør vælge mellem (a) journal-mønstret generaliseret — alle `red_*`-operationer logger et reload-invariant anker (`import_key`/`record_key`-stil), eller (b) source-scoped replace hvor person-id'er bevares. `red_ret_ocr_felt` er den fungerende skabelon. K4-kravet (record_key ved udtræk) løser kun fremtiden, ikke de eksisterende samme_som-change_sets. Tag C1 (reset-listen), IMP-4 (loader-guard) og IDENTITY-migrationen (RED-8) med i samme pakke — alle er "før næste load/flere skrivere"-gates.

---

## Vinkel 1: Redaktør-delen

**Samlet dom:** Kernen knækker ikke — den knækker i randene. Godt nok til PoC med én redaktør: ja. Holdbar ud over PoC uden (1) replay + IDENTITY, (2) suggestion-apply, (3) bounded læse-slices: nej. Mønstret bag UI-hullerne er ét og samme: alt der ikke fik en dedikeret RPC ender som SQL-ved-hånden eller i den ulæste forslagskø.

| ID | Fund | Prio | Status |
|---|---|---|---|
| RED-1 | Import/redaktion to skriveveje → se Tema A | kritisk | verificeret · Codex DELVIST |
| RED-2 | Suggestion-flow skriv-kun | høj | verificeret · Codex BEKRÆFTET |
| RED-3 | `story_kilde` mangler i versionsregistret → fortryd tavs no-op | høj | verificeret · Codex BEKRÆFTET |
| RED-6 | Ægteskab: redigér/slet findes ikke | høj | verificeret |
| RED-13 | Flerslægts-blokkere B1-B3/K4 (referat af eksisterende analyse) | høj (før slægt 2) | verificeret |
| RED-12 | Fuld graf-materialisering + ubounded grid | høj post-PoC | verificeret (kendt, udskudt) |
| RED-4 | Dry-run er ren klient-forhåndsvisning | medium | verificeret |
| RED-5 | `redaktionWrite` duplikeret web/mobil, divergerer begge veje | medium | verificeret (review 24 fund 8, består) |
| RED-7 | `presens_kode` + hele lineage-entiteten uden skrivevej | medium | verificeret |
| RED-8 | `max(id)+1` overalt + TOCTOU; kun OCR-laget har fingerprint-tjek | medium (kritisk før flerbruger) | verificeret (kendt) |
| RED-9 | `red_upsert_fakta` nondeterministisk find-or-create, stadig i brug | medium | verificeret · Codex DELVIST |
| RED-11 | Mobil-crash i redaktør: ikke reproducerbar statisk, muligvis død efter omskrivninger | medium | antaget/uafklaret |
| RED-10 | Konventions-divergenser i RPC-fladen (2 relations-RPC'er, fritekst-fejlkontrakt, blandet grant-stil) | lav | verificeret |

**RED-2 (høj, Codex BEKRÆFTET):** `suggestion`-tabellen har INSERT-vej (`red_suggest`, `schema.sql:2347`; routet fra `planCall`, `web/src/data/redaktionWrite.ts:537-541`) men ingen klient læser den, og ingen godkend/afvis/apply-RPC findes. `web/src/Redaktion.tsx:2178` lover brugeren "afventer redaktionel godkendelse". Alle ikke-redaktør-bidrag og alle family-redigeringer lander i en kø kun psql kan se. Payload er fri jsonb af klientens `Change`-form uden formatversionering — og `Change`-unionen er allerede divergeret mellem web og mobil (RED-5). For forenings-modellen ("medlem foreslår, redaktør godkender") er dette den manglende halvdel af skrivemodellen.

**RED-3 (høj, Codex BEKRÆFTET):** `red_set_story_kilder` (`schema.sql:1519-1543`) kører DELETE+INSERT på `story_kilde`, men registryet (`schema.sql:2945`) har `story` og `feed_pin` — ikke `story_kilde`; `db-migrations.sql:3215` gentager udeladelsen. Trigger-loopet (`schema.sql:3080`) hænger kun logning på registry-tabeller → intet logges, og fortryd opretter et tomt reversal-change-set uden events. **Fix:** registrér tabellen + tilføj en `db-verify`-assert: enhver tabel en `red_*`-funktion DML'er mod skal stå i registry eller være eksplicit undtaget (samme maskinelle vagt som review 24 fund 12 efterlyste for grants). Bifund: `media_variant` er uversioneret og `red_registrer_media_variant` åbner intet change_set — formentlig bevidst, men udokumenteret.

**RED-6 (høj):** `red_opret_union` findes; `red_slet_union`/`red_rediger_union` findes ikke (fuld RPC-flade tjekket). Plan 2C-2b lovede en separat RPC til tom-family-sletning — den kom aldrig. Vielse-fakta kan kun redigeres via den generiske flade → RED-2's sorte hul. Basens hyppigste datafejl-klasse (spøgelses-unioner, forkerte partnere — change_sets 1-7, 30) kan ikke rettes i produktet; change_set 30 krævede direkte SQL (`docs/changelog.md:1195-1197`).

**RED-4 (medium):** `dryRun` returnerer før databasen rammes (`redaktionWrite.ts:549-565`) — ingen server-validering (eksistens, cyklus-guards, rolle). Korrekthed hviler på prop-threading af boolean'en; den fejlklasse er allerede indtruffet én gang (SammenlignUdgaver, 8 dage usynlig, PR #72). Billig hærdning: én delt `useDryRun()`-kilde.

**RED-7 (medium):** Ingen `red_*`-RPC rører `lineage`. Linjenavne, slægtsnavn, `parent_lineage_id` (slægtsrods-migrationen) og `presens_kode` er alle SQL-only — linje VI-arbejdet 2026-07-29 blev udført som håndskrevet change_set 788. Det kendte hul ("UI-felt til presens_kode") er reelt større: der mangler en lineage-skrive-RPC.

**RED-9 (medium, Codex DELVIST):** `LIMIT 1` uden `ORDER BY` i find-or-create står i både schema og seneste migration (`db-migrations.sql:2306`), og `fact` har ingen uniqueness på (subjekt, faktatype). Codex' præcisering: normal redigering af eksisterende oplysning går via `red_edit_oplysning` med assertion-id; `red_upsert_fakta` bruges til "første fact" + `forældre_ukendt`-remarkering. Vilkårlig slot-selection er reel men rammer ikke enhver redigering. decisions-påstanden "UI bruger den ikke mere" (2026-06-28) er drevet — `Redaktion.tsx:1693` bruger den.

**RED-11 (uafklaret):** Rapporteret mobil-crash ved person-åbning i redaktør fandt ingen statisk root cause; skærmen er væsentligt omskrevet siden (alle mount-fetches `.catch`-guardede). Kandidat: fuld `redaktionModel` (1.758 personer) i device-hukommelse. **Re-test på device før der bruges jagt-tid.**

---

## Vinkel 2: Data-import

**Samlet dom:** God nok — på flere punkter forbilledlig for materiale af denne art. Fejlprofilen er den designede: udeladelser og fejlklip, næsten aldrig forkerte påstande (0 forkerte navne/år/ægtefæller i auditen). To strukturelle svagheder: valideringstyngden sidder på LLM-trinnet mens segmenteringen er dominerende fejlkilde, og replay-gabet (Tema A) gør re-ekstraktion til et åbent kredsløb.

| ID | Fund | Prio | Status |
|---|---|---|---|
| IMP-3 | Replay-gab → se Tema A | kritisk | verificeret |
| IMP-1 | Validering tjekker mod segmenterens output, ikke bogen | høj | verificeret |
| IMP-2 | Kvalitetsgate kun proces-håndhævet (1939 loadet med rød gate) | høj | verificeret |
| IMP-4 | Spøgelses-union-guard (navn≠ref) fraværende i loader | høj | verificeret · Codex BEKRÆFTET |
| C1 | Reset-listen mangler change_set/change_event | høj | verificeret (Codex-fund) |
| IMP-5 | Prod rettes, kode/artefakt rettes ikke (mønster, 4 instanser) | medium | verificeret |
| IMP-7 | Recall-kontrol tynd: korpus-udeladelser usynlige for per-post-validering | medium | verificeret |
| IMP-8 | Marginalomkostning pr. ny bog = en mini-pipeline | medium | verificeret |
| IMP-11 | Identitetsarbejdet beskytter fremtiden, ikke de 835 staged rækker | medium | verificeret |
| IMP-6 | Deterministisk/LLM-snit rigtigt og konsekvent skærpet (positivt) | lav | verificeret |
| IMP-9 | LLM-kørselsharness (`work/extract_all.py`) eneste ikke-versionerede led | lav | verificeret |
| IMP-10 | Presens-validering svagere uden kvalitetsmarkering i data | lav | verificeret |

**IMP-1 (høj):** Samtlige R-regler (`validate.py:716-820`) tjekker udtræk mod `src['raw_text']` — segmenterens eget output. Er posts.json klippet forkert, består R1/R6/R7 alligevel. Præcis dét er de dokumenterede materielle fejl (54 % poster med ≥1 materiel fejl i 1939-baseline-audit, alle udeladelser/fejlklip; post 13 fik en anden persons narrativ — den ene fejltype der "ser autoritativ ud og er forkert"). R1-R10 er ikke teater — de tjekker faktisk observerede fejlklasser — men kædens tætteste kontrol sidder på det trin der fejler mindst. **Anbefaling:** formalisér segment-mod-bog-tjek (dobbeltbogføring/pegepind, nr-kontinuitet, sidste-post-hale) som blokerende gate på trin ②, parallel til trin ④.

**IMP-2 (høj):** Changelog 2026-07-26: artefaktet i prod var accepteret med fejlende gate (88,8 % → senere 91,2 %). `load_daa.R` accepterer enhver clean.json; intet manifest binder gateresultat til den loadede fil. **Anbefaling:** validate/segment skriver manifest (input-hash + gateresultat) som `load_daa.R` kræver og verificerer.

**IMP-4 (høj, Codex BEKRÆFTET):** `load_daa.R:379-386` linker partner via `parse_intern_ref` uden navn-krydstjek; `partner_navn` bruges kun i fallback-grenen når ref ikke kan linkes; `parse_intern_ref` modtager slet ikke navnet (`load_helpers.R:246`). Diskriminatoren blev besluttet 2026-07-03, prod oprydt (change_sets 3-7), koden urørt. Lille, veldefineret rettelse (uenighed → parkér + log, samme mønster som `match_barn_union`) — skal med før replay-laget tages i brug.

**IMP-7 (medium):** `expected_signals` (`validate.py:676-696`) tjekker kun ægteskab + død. 1939's største mangel — otte faktatyper med 0 forekomster (dåb 0 vs. 237, dekoration 0 vs. 131), 0 af 506 embede-relationer — var maskinelt synlig men blev først fundet ved manuel prod-måling måneder senere. Én korpus-plausibilitetsgate (faktatype-fordeling mod referenceudgave) havde fanget K1-K3 på dag ét.

**IMP-8 (medium):** 1939 krævede egen segmenter (791 linjer), egen konverter (779 linjer) + identitetsregister-værktøjer; "Reventlow" hardkodet tre steder (`post_load_fixup.R:53`, `convert_1939_stamtavle.py:67`, `segment_1939.py:43`); B1-nøglerumskollisionen (`lineage UNIQUE(source_id,kode)`) er uafklaret. Delvist iboende (hver udgave HAR eget layout), men "edition-profil som konfiguration" + K4 er ikke bygget. Datamodellen selv er slægtsneutral — spærringerne er pipeline + én constraint.

**IMP-6 (positivt):** narrativ-klip, `boern`, dato-bounds, lokator, `record_key` — alle flyttet fra LLM til deterministisk kode efter *målt* LLM-svigt, ikke af princip. Ét forbehold: R9-historien (`tjek_lokator` eksisterede men blev aldrig kaldt — fundet af Codex-review, havde ellers mintet 515 nye identiteter) viser at reglers *tilslutning* ikke selv er testet. En "alle regel-funktioner er koblet ind"-test lukker klassen.

---

## Vinkel 3: Missed opportunities

**Sigter projektet mod kernen?** Ja — "er vi i familie?" er fuldt bygget på begge platforme (`web/src/components/RelateView.tsx`, `mobile/.../relate.tsx`) med konfidens-korroboration af svage led (invariant 7 respekteret). Driften er allokering, ikke retning: tre færdigbyggede forbrugslag står med motoren slukket, og "på tværs af slægter"-løftet (mobilens `SlaegtPicker` er mockup med hardcodede slægter) forbliver uindfriet til slægt nr. 2 loades. Største strukturelle gab: der findes reelt kun to brugertyper.

### Rangeret efter gevinst/indsats

| # | Fund | Indsats | Gevinst | Status |
|---|---|---|---|---|
| 1 | **OPP-2: Kør hændelses-LLM-passet.** `haendelse`-tabel live i prod, feed-kort (`arkiv`/`paadennedag`/`citat`) bygget i `@daa/feed` + begge klienter, `/daa-haendelser`-skill klar, `web/src/data/haendelser.ts` fetcher tolerant mod tom tabel. Hele forbrugsapparatet venter på én batch-kørsel mod allerede-bevarede narrativer. Billigste enkeltting der gør forsiden levende. | lille | stor | verificeret (bevidst udskudt — men forbrugssiden er bygget siden) |
| 2 | **OPP-3: Kør geo-enrich-pipelinen.** `R/geo-enrich/` komplet (TNG-crosswalk ~6.788 punkter + Nominatim-fallback + review-CSV, egne tests) men aldrig kørt; kort-views er shipped på begge platforme og tegner på næsten tomt grundlag (`buildGeo` filtrerer koordinatløse fra). | lille | mellem/stor | verificeret |
| 3 | **OPP-4: Eksponér fuldtekstsøgning.** `narrative.fts` (GENERATED tsvector) + GIN-indeks **empirisk verificeret live i prod** (dette review); nul forbrugere i produktkode; al søgning er klient-side navnefilter. "Søg i biografierne" er forsker-abonnentens brugsscenarie. Ingen udskydelses-beslutning → reelt overset. **Bifund (drift):** `schema.sql` — erklæret source of truth — har kun fts som udkommenteret forslag (`schema.sql:1394`); prod-kolonnen mangler i repoets deploybare SQL. | lille/mellem | stor | verificeret (Codex REFUTERET på repo-SQL; prod-opslag afgjorde: fundet står + drift-bifund) |
| 4 | **OPP-8: Offentlig udgave-sammenligning.** Datamodellens erklærede differentiator ("vise årbogens egen udvikling") findes kun som bio-faner + redaktør-only `SammenlignUdgaver.tsx`. Med 2 udgaver i prod (og 1939 på vej) ligger dataene klar; "hvad ændrede bogen?"-fladen er følgesvend-ideens tydeligste udtryk. | mellem | stor | verificeret (delvist bevidst — "kommer"-flade i nav) |
| 5 | **OPP-7: GEDCOM 7-eksport.** Erklæret i CLAUDE.md + datamodel §8; nul kode (grep: 2 kommentarer). Import-vejen er bevidst DAA-først, men *eksport* har ingen beslutning, intet design. Standardforventning hos genealoger/forskere — abonnent-målgruppen. Lav-risiko read-side-projektion af konklusioner. | mellem | mellem/stor | verificeret (reelt overset) |

### Øvrige fund

- **OPP-5 (forretningsgab, stor/stor):** `current_rolle()='redaktion'` er eneste rolletjek; medlem/forsker-tier kun skitse i `db-rls.sql §FREMTID`; nul betalings-/abonnementskode eller -design. Konkret konsekvens ingen har skrevet ned: **præsensliste-featuren (10 tasks, begge platforme) er reelt redaktions-eksklusiv** — anon/medlem ser ikke levende personer, så fladen er tom for alle andre. Medlemsfordelen i dag er alene bogmærker. RLS-siden er bevidst udskudt; at betalings-/samtykkesiden aldrig er designet er gabet.
- **OPP-6 (lavthængende, mellem/mellem):** TNG gemte rapporter/smart-lister blev udpeget "NÆSTE FOKUS" 2026-07-03 (193 reelt brugte lister, eksplicit brugerinteresse) — ikke rørt siden, ingen beslutning omgør prioriteringen. Faldet mellem stolene.
- **OPP-9 (uudnyttet model, mellem/mellem):** Embeder/organisationer/dekorationer loades med fuldt evidenslag, vocab (153 rækker) findes netop for "samme slags"-forespørgsler — men ingen flade for "alle amtmænd"/"alle riddere af Elefanten"; Organisationer = null i nav. Vocab stadig ikke FK-håndhævet (review 24 fund 14).
- **OPP-10 (uudnyttet model, lille/lille-mellem):** Modellen bærer fuldt kvalifikatorsæt (about/before/floruit + `date_raw`), men offentlige flader viser kun rå årstal fra visning-cachen. Læseren kan ikke se forskel på "1660" og "ca. 1660" — mod ånden i invariant 7.
- **OPP-1 (kerne-drift):** "På tværs af slægter"-løftet i UI (SlaegtPicker-mockup) er uindfriet indtil slægt 2. Bevidst PoC-scope; parathed analyseret (`flerslaegt-parathed-2026-07-28.md`). DNA eksplicit afvist af brugeren — tælles ikke som missed.

**Bevidst udskudt/afvist (tælles ikke som missed):** 1939-publicering (pauset til re-ekstraktion), levende feed fase 4, mediehåndtering fase 5 + foto-rigdom, DNA (afvist), flersproget stamtræ, medlem-RLS-tier (afventer auth), samtykke-granularitet, skalering/paginering.

---

## Codex-krydstjek (gpt-5.6-sol, adversarial)

| Fund | Verdict | Afgørende evidens |
|---|---|---|
| RED-3 story_kilde-fortryd-hul | **BEKRÆFTET** | Registry uden story_kilde i både `schema.sql:2945` og `db-migrations.sql:3215`; præcisering: efterlader tomt reversal-change-set |
| RED-9 nondeterministisk upsert | **DELVIST** | SQL-fejl bekræftet (`db-migrations.sql:2306`), men normal redigering går via `red_edit_oplysning` — rammer "første fact"/`forældre_ukendt`, ikke enhver redigering |
| IMP-4 spøgelses-union-guard | **BEKRÆFTET** | `partner_navn` kun i fallback-gren; `parse_intern_ref` modtager ikke navnet (`load_helpers.R:246`) |
| OPP-4 FTS uden forbrugere | **REFUTERET på repo-SQL** → **står efter prod-opslag** | fts kun udkommenteret i `schema.sql:1394`; prod-query viste `fts` GENERATED + `narrative_fts_idx` → fund står, plus nyt drift-bifund |
| RED-2 suggestion skriv-kun | **BEKRÆFTET** | `red_suggest` = ren INSERT (`schema.sql:2347`); RLS-SELECT-policy findes men bruges aldrig; ingen kø-UI, ingen apply-RPC |
| RED-1/IMP-3 to skriveveje | **DELVIST** | `import_korrektion`-replay findes men dækker kun OCR-felter; generel redaktion overlever ikke reload — arkitekturlæsningen står |
| C1 reset-listen (Codex' eget fund) | nyt | `load_daa.R:42` lover sletning; `load_helpers.R:74` mangler change_set/change_event; `backfill_slaegtled.R:69` bekræfter |

Krydstjekket ændrede konklusionen tre steder: RED-9 nedjusteret i rækkevidde, OPP-4 fik et ekstra drift-bifund (schema.sql ≠ prod), og C1 er et nyt høj-prioritetsfund ingen af de tre reviewagents havde.

---

## Hvad blev IKKE undersøgt

- **Empirisk prod-tilstand** ud over det ene FTS-opslag — alle øvrige DB-udsagn er fra repo-filer (fx om story_kilde-registret skulle være patchet direkte i prod; rækketal for estate/organisation/place).
- `extract-prompt.md`/`extraction-schema.json` i detaljer; `segment.py`/`segment_1939.py` linje-for-linje; `omnoegl_lokator.py`/`afstem_lokator.py`; `load_presens.R`/`load_haendelser.R` i detaljer.
- Testsuiterne (~3.900 linjer R + web/mobil-tests) — kun tilstedeværelse noteret, ikke dækningskvalitet.
- `db-verify.sql`-asserternes dækning af story/feed-RPC'erne; performance af `red_fortryd_change_set` på store change_sets.
- Mobilens `sammenlign.tsx`/`SkrivePreviewSheet`; mobil/web-paritetsdetaljer; `packages/feed`-scoringens dybde.
- Fuld gennemlæsning af `docs/changelog.md` (2.000+ linjer, grep-skimmet) og review 26 (UX) — kan rumme bevidste fravalg der flytter enkelte OPP-fund fra "overset" til "udskudt".
- RED-11 (mobil-crash) kræver device-re-test — ikke muligt i dette review.

---

## Anbefalet rækkefølge (sammenfatning)

1. **Replay-designsessionen** (Tema A) — inkl. C1 (reset-listen), IMP-4 (loader-guard), IMP-2 (gate-manifest) og IDENTITY-migrationen som samlet "før næste load"-pakke.
2. **RED-3-fixet + registry-assert** — lille, lukker en hel fejlklasse maskinelt.
3. **Tænd de tre slukkede motorer** (OPP-2 hændelser, OPP-3 geo, OPP-4 FTS) — størst produktværdi pr. indsats, uafhængige af replay-arbejdet.
4. **Suggestion-apply-fladen (RED-2) + ægteskabs-redigering (RED-6)** — de to redaktør-huller der reelt blokerer forenings-skalaen.
5. **Segment-gate mod bogen (IMP-1) + korpus-plausibilitetsgate (IMP-7)** — før næste udgave udtrækkes.
