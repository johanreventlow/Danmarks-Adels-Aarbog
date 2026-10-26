# Trin 5c: slægt, linje og generation som placement og membership (#150) — design

**Status:** afgørelserne i §8 truffet af projektejeren 2026-10-26 (anbefalingerne fulgt); Fable-review 2026-10-26
(GO med rettelser, indarbejdet — §10). Næste: plan med Codex-review (Opus dømmer) før implementering.
**Gren:** `docs/150-5c-spec` fra `main` (`db67fb17`).
**Grundlag:** issue #150; `docs/decisions.md` 2026-10-05 (trin 5 aktiveret, 5a → 5b → 5c) og 2026-09-04 (149b valg A:
»begge udgaver revalideres samlet, når #150/#151 leverer placements«); planen 2026-08-02 Task 17 trin 3;
`docs/superpowers/reviews/task6-legacy-placement-consumer-inventory.md` (overgangskontrakterne);
afvigelsesvurderingen 2026-08-22 §7.4. Målt på en kopi af prod efter #248 (2026-10-26).

## 1. Roadmap-kobling

1. **Roadmapmål:** trin 5, sidste delspec (5c, #150). Efter 5c: Fable-review af trin 1-5, derefter trin 6.
2. **Værdikædeled:** observation (overskrifter som kildebundne observationer) → afgørelse (placement) →
   promotion (membership). I dag ender kæden ved source record; slægt/linje/generation bor kun i legacy.
3. **Leverancetype:** generel mekanisme (header-evidens, placement, ledger, membership-promotion) + én
   midlertidig legacy-afvikling (2018-20's `person_external_id`). Udgaveprofil kun for overskrifts-grammatikken.
4. **Værdi:** redaktionelt: hver persons placering i slægten har kilde, afgørelse og fortrydelse; multi-slægt
   bliver en tilstand, ikke en mulighed (invariant 9 i datavejen). Læserværdi kommer først med 5c-2 (§3).
5. **Færdigbevis:** se §7.
6. **Erstatter:** `backfill_slaegtled.R`/`post_load_fixup.R` som skrivevej for slægtled (fryses, Task 6
   **LegacyBackfillFreeze**); `person_external_id` som eneste bærer af placering.

## 2. Problem og målt udgangspunkt

- Placement-, membership- og lineage-tabellerne er skeletter: `source_record_placement`, `source_persona_placement`,
  `person_slaegt_membership`, `person_lineage_membership` = **0 rækker**. `red_apply_reimport_person_create`
  (1939-person-oprettelse) læser record-placement og skriver persona-placement; den afviser alle kilde-1-records,
  fordi de har `person_external_id`.
- Grundstruktur findes: 1 `slaegt` (Reventlow, status **`historical`** — #150 kræver `active`; ingen læser bruger
  feltet), 3 `lineage_scheme` (2018-20 stamtavle med I-V, 1939 med VI, præsensliste), 8 entries, 7 `lineage`.
- Legacy: 1.167 `person_external_id`-rækker. **Kilde 1 (2018-20): 591**, alle med linje, nr og
  `slaegtled_lokal`, 292 med `slaegtled_gennem`. **Kilde 3 (1939): 576**, men 542 har pladsholderen `linje='1939'`,
  8 ingen linje, 0 slægtled — 1939's placering hører til trin 6.
- **Skelettet kan ikke opfyldes af 2018-20.** `validate_source_record_placement` (`schema.sql:2310`) kræver en
  `header`-observation i postens egen ankrede forekomst, og `validate_evidence_scope` (`:862`) kræver, at en
  observation ligger inden for sin forekomsts tekstspænd. 2018-20's overskrifter (linje: romertal + »DEN … LINJE«;
  slægtled; kuld-romertal; ægteskabskontekst »med X:«) står *mellem* posterne (`segment.py`). Der er 0
  `header`-observationer, og alle 2018-20's klausuler er `record_text`. (1939 har derimod `structural_header`-
  klausuler inde i posterne.) `segment.py` rapporterer desuden *umarkerede* slægtledsfald, dvs. skift uden overskrift.
- **Placements ændrer publiceringstilstanden.** Målt: én accepteret record- + persona-placement ændrer
  `narrative_publication_state` (`authority.identity_people` og `provenance`; status og eligibility uændret).
  Den gemte tilstands-sha passer så ikke → `stale_published`. Kilde 1: **541 publicerede** og 46 drafts.
  Peger en persona-placements identitet på en anden person end bindingens, bliver bindingen i stedet *blokeret*
  (`NARRATIVE_RECORD_IDENTITY_CONFLICT`, `:12440`).
- Læsere af legacy (bl.a. `red_person_grid` med `max(slaegtled_lokal)`, `red_match_personer`,
  `regen_person_visning`'s slægtsnavn, web/mobil/core) er kortlagt i Task 6-inventaret.

## 3. Afgrænsning: 5c deles i to (§8 afgørelse 1)

- **5c-1 (denne spec):** header-evidens, placements for kilde 1, ledger for alle legacy-rækker,
  membership-promotion, `slaegt` → `active`, revalidering. **Ingen læser ændres**; paritet bevises (§6.3).
- **5c-2 (senere spec):** læserne skifter til placement/membership efter Task 6's navngivne kontrakter
  (`GridPlacementSummary`, `MatchPlacementPayload`, `PlacementCoordinates`, `PresensSchemeProjection`, …) med
  paritetstest; legacy-kolonner fjernes først, når begge udgaver er migreret (trin 6).

## 4. Design (5c-1)

### 4.1 Overskrifter som kildebundne observationer (§8 afgørelse 2)

**Valgt (A): strukturelle forekomster.** Hver overskrift i 2018-20's rendition bliver en
`source_record_occurrence` med eget `occurrence_key` og en egen header-`extraction_run` (med
`header_rule_version`), aldrig ankret til en source record, med én `source_observation` med rå tekst, side og
renditionsabsolut tegnspænd. **Niveauet er observationens kind**, med nye koder i `private.vocab`:
`header_linje`, `header_slaegtled`, `header_kuld`, `header_aegteskab` (editionsneutralt; 1939 kan tilføje koder uden
DDL). Linje-overskriften er ét spænd over begge linjer (romertal + navn). Udtrækket er deterministisk (profilens
regexer fra `segment.py`), kører lokalt på den rå tekst og sender intet til en model. Overskriftsformen måles på
teksten i planens første opgave; spec'en antager ingen bestemt ordlyd.

**Validatoren udvides, erstattes ikke.** `validate_source_record_placement` accepterer enten (i) den eksisterende
sti — en `header`-observation i postens egen ankrede forekomst (bevares til 1939/trin 6) — eller (ii) en
header-observation af kind `header_linje` på en **uankret forekomst i samme rendition og samme header-kørsel,
placeret før postens forekomst** (`(page_from, char_from)` mod den tidligste ankrede forekomsts start). Triggeren
tjekker kun disse strukturelle forhold. Selve »nærmeste foregående overskrift«-reglen står i placementens `evidence`
(regelversion + de valgte observations-id'er pr. niveau) og efterprøves af en db-verify-/helbredsassert, ikke af
triggeren.

**Reglen (i evidence):** for hvert niveau den nærmeste foregående overskrift i samme header-kørsel, hvor en
overskrift af højere niveau annullerer lavere (linje > slægtled > kuld > ægteskab). Det er strengere end
`segment.py`, der kun nulstiller kuld/ægteskab ved linjeskift; uenighed med legacy går derfor til review, ikke
»legacy vinder«.

Fravalgt (B): at udvide de 591 forekomsters spænd — 149a's forekomster er uforanderlige og hash-bundne.

Følger af A: db-verify's placement-blokke og `evidence_contract.py`/`clause_ledger.py` udvides med sti (ii);
overførselsværktøjets forekomst-digests for kilde 1 skifter (forventet, som ved 5b); validatoren kræver
opgraderingstest fra prods skema.

### 4.2 Placements for kilde 1

- **Record-placement** pr. accepteret source record i kilde 1: `scheme_entry_id` (linje-overskriftens romertal →
  entry i 2018-20-schemaet), `printed_number` (postens nr. fra dens `person_post`-observation), `generation_local`,
  `generation_label_raw` (overskriftens rå ordinaltekst), `generation_global` (kun hvor bogen trykker den),
  `kuld_label`, `section_path`, `header_observation_id` (linje-overskriften).
- **Persona-placement** kun for hovedpersonen (`principal_member`, persona via `primary`-mention,
  `basis_observation_id` = postens `person_post`-observation). Ægtefæller og børn får ingen placering i 5c-1
  (Task 6 regel 3).
- **Hvor intet observeres, opfindes intet.** Et umarkeret slægtledsfald eller en manglende overskrift giver ingen
  `generation_local` fra overskriften; posten får `unresolved` i ledgeren (§4.3), ikke legacy-værdien.
- **Afgørelse uden fuldt ark.** Legacy og header-observationerne stammer fra samme læsning af samme tekst, så
  enighed er ikke uafhængig bekræftelse. Maskinel accept (`decision_origin='migration'`) kræver derfor alt af:
  1. enighed mellem reglen og legacy for linje, nr., slægtled og kuld;
  2. **strukturinvarianter, fail-closed for hele kørslen:** 5 linje-overskrifter ↔ 5 entries; hver post har præcis
     én linje- og højst én slægtledsoverskrift; slægtled-ordinaler fortløbende pr. linje; kuld-romertal stigende
     inden for et slægtled; nr. fortløbende pr. linje;
  3. **blind, stratificeret kontrolstikprøve på K = 20 poster** mod PDF'en, som projektejeren tjekker (første post
     efter hver linje- og slægtledsoverskrift, sideskift, kuld-markører; resten tilfældigt).

  Uenigheder og huller går til en token-fil uden forudfyldte svar. Kontrolark og token-fil kan nævne levende
  ægtefæller (ægteskabsoverskrifter) og behandles som `work/`-materiale: kun under `~/.private`, aldrig til en model.
- Indholds-id'er (`private.content_uuid`) for forekomster, observationer, placements og afgørelser.
- `scheme_entry → lineage`: præcis én `canonical`-mapping pr. entry, ellers stop.

### 4.3 Ledger: én disposition pr. legacy-række

Ny privat tilføj-kun tabel med `(person_id, source_id, version)` og et current-view som husets øvrige ledgers;
hver version bærer en værdi-hash af legacy-rækken. Dispositioner: `mapped` (accepteret placement findes),
`retained_legacy` (bevares uændret, fx kilde 3 indtil trin 6), `archived_by_editor`, `unresolved` (kræver
menneske). Alle 1.167 rækker får en disposition; kilde 3's 576 får `retained_legacy`. En senere ændring af
legacy-værdien gør dispositionen forældet (værdi-hash ≠ nuværende). Ingen legacy-række ændres eller slettes.

### 4.4 Membership via promotion (§8 afgørelse 3)

Én promotions-RPC (SECURITY DEFINER, `redaktion`, åbner egen change_set) fra accepteret persona-placement
(`principal_member`) + accepteret identitet → `person_lineage_membership` (`role='member'`, lineage via entryens
canonical-mapping) og `person_slaegt_membership` (`membership_kind='agnatic'`; `adopted`/`editorial` kun ved en
menneskelig afgørelse; gifte-ind får aldrig membership). `source_basis` bærer placement-id'er, identitetsversion,
regelversion og en tilstands-sha. **En membership gælder kun, når sha'en svarer til nuværende placement og
identitet** (som relationsbindinger, jf. #248): en senere identitetsrettelse gør den uden videre ikke-gældende, og
en helbredsassert i db-verify tæller ikke-gældende memberships. 5c-2's læsere skal filtrere på gældende.
Fortrydelse: RPC'ens reversal sletter rækken under en change_set (før-billedet bevares i `change_event`).
`slaegt` Reventlow sættes til `active`.

### 4.5 Revalidering af publiceringerne (§8 afgørelse 4)

De 541 publicerede bindinger i kilde 1 revalideres i **samme transaktion** som placementerne accepteres, med
`red_revalider_person_narrative_record`, så læseren aldrig ser `stale_published`.

- **Mekanik:** RPC'en kræver `auth.uid()` (`request.jwt.claim.sub` sat i transaktionen) og afviser et allerede
  sat `app.change_set_id` (`NARRATIVE_RECORD_FOREIGN_CHANGE_SET`). Derfor ryddes GUC'en mellem kaldene
  (`set_config('app.change_set_id','',true)`, husmønstret fra reversal-koden), og kaldene er **klientdrevne
  enkeltsætninger pr. post** (ikke én plpgsql-løkke, der som én sætning ville ramme prods 2-minuttersgrænse) med
  `SET LOCAL statement_timeout='15min'` for transaktionen. Varigheden måles på stand-in med 2-minuttersgrænsen.
- **Forhåndsbetingelser:** for alle 587 er identitetens person = bindingens person; for alle 541
  `publication_allowed=true` og tekst-sha = seneste event; 0 `stale_published` før.
- **Efterbetingelser:** 541 `published`, uændret eligibility, 0 `stale_published`, 0 blokerede. De 46 drafts'
  tilstands-sha ændres (forventet, dokumenteres). 1939's 563 er uberørte.
- Under transaktionen er redaktørskrivninger til de berørte poster låst; læsning er uberørt. Kørslen lægges i et
  kort skrivepausevindue.

## 5. Følger

- Rækkediff: nye rækker i placement-, decision-, membership- og ledger-tabellerne, forekomster/observationer
  for overskrifter, én header-`extraction_run`, 541 `narrative_publication_event` og deres change_sets; én
  opdateret række i `slaegt` (status). Ingen andre kanoniske ændringer.
- En record uden binding med én accepteret placement får `record_label` = linjens label (`narrative_record_labels`,
  `:12182`): rammer de 4 `unresolved_text` og fremtidige publiceringer. Dokumenteres; justeres evt. i 5c-2.
- `red_slet_person` blokeres allerede af `PERSON_HAR_KILDEIDENTITET` for de 587; den sletter memberships uden om
  promotions-RPC'ens reversal. Ingen ny blokering i 5c-1 (kendt begrænsning).
- Kilde 1 og 3 bliver asymmetriske (placement mod `existing_exact_binding`) indtil trin 6; accepteret, fordi
  1939 mangler linjedata.

## 6. Prod

1. **DDL-ceremoni (GO 1):** validator-udvidelse, vokabularkoder, ledger-tabel, promotions-RPC og reversal.
   Måling, dump, blokken i én transaktion, fingeraftryk før/efter, `get_advisors` (forventet: +1
   `rls_enabled_no_policy` pr. ny privat tabel), `NOTIFY pgrst`. Øves på en stand-in med prods 2-minutters grænse.
2. **Dataceremoni (GO 2):** overskrifts-forekomster, placements, ledger, memberships og revalidering i én
   transaktion som et ceremoniscript over genbrugelige private funktioner (`propose_*`, afgørelse, promotion,
   revalidering), så trin 6 genbruger funktionerne. For-/efterbetingelser fra §4.5, rækkediff-forventning (§5),
   kontrolark og token-fil hash-bundne i GO'en. Øves på stand-in med 2-minuttersgrænsen; varigheden noteres.
3. **Paritet:** `red_person_grid`, `red_match_personer`, `regen_person_visning`-resultater,
   `public_family_sources` og `public_person_bio_source_versions_v2` er byte-identiske før og efter.
4. **Fortrydelse** spejler kørslen: memberships trækkes tilbage → placements `superseded` → de berørte bindinger
   revalideres → ledger-dispositioner opdateres. DDL via dumpet. Dumpet er nødudvejen.

## 7. Færdigbevis

- Lokal CI grøn + opgraderingstest fra prods skema.
- Stand-in-øvelse: alle strukturinvarianter grønne; hver hovedperson med identitet har enten accepteret placement
  og gældende membership eller `unresolved` i ledgeren; 591 + 576 ledger-dispositioner; 0 `stale_published`;
  paritet (§6.3); målt varighed under grænsen.
- Prod: begge GO'er kørt med forventede kvitteringer; status-snapshot hæver »Placement og membership« til
  `produktionsverificeret` for kilde 1.

## 8. Afgørelser (projektejeren 2026-10-26)

1. **Opdeling:** 5c-1 (evidens, placement, membership) nu; 5c-2 (læserskift) som egen spec.
2. **Overskriftsmodel:** strukturelle forekomster (A) med udvidet validator.
3. **Membership-art:** alle stamtavlens hovedpersoner som `agnatic`; gifte-ind får aldrig membership.
4. **Revalidering:** de 541 publiceringer revalideres maskinelt i samme transaktion (uændret eligibility er en
   efterbetingelse; afviger den, stopper kørslen).

Mine egne valg (kan rettes): K = 20 i en stratificeret kontrolstikprøve; kun hovedpersonens persona-placement i
5c-1; ceremoniscript frem for en ny batch-writer; `occurrence_key`-form og `header_rule_version` overlades til planen.

## 9. Uden for scope

5c-2 (læserne), 1939's placering (trin 6), fjernelse af legacy-kolonner, præsenslistens scheme-scopede opslag,
`founder`/`claimant`-roller, ægtefællers og børns placering, vagter i identitetsvejene mod ikke-gældende memberships.

## 10. Reviewlog

**Fable 2026-10-26: GO med rettelser.** Indarbejdet: revalideringens mekanik og forhåndsbetingelser (D1, F2);
niveau som vokabularkoder (D2); reglens scope og hierarki, kun strukturelle facts i triggeren (D3); validatoren
udvides i stedet for at blive erstattet (D4); strukturinvarianter og stratificeret stikprøve (D5); én canonical
pr. entry (D7); ledger-nøgle og værdi-hash (D8); fortrydelsens rækkefølge (D10); `generation_label_raw` (D11);
PII i kontrolark (D12); skrivepausevindue (D13); faktarettelser (F3, F5-F7). Forenklet: membership-forældelse
som »gældende kun ved passende sha« + helbredsassert i stedet for vagter i identitetsvejene (D6); ceremoniscript
over genbrugelige funktioner i stedet for en ny batch-writer (D9).
