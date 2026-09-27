# Trin 4 · omsegmentering af en posts klausuler + S4 — design

**Status:** udkast 2026-09-27, ikke reviewet. **Beslutning:** `decisions.md` 2026-09-27
(omsegmentering før 4.4, skridt 3-4). **Review-budget:** DDL ⇒ 2 + 2 (decisions 2026-09-23).
**Afløser:** intet; supplerer trin 4-spec'en §4.1 (klausullaget) og §7 (proposed-ingest).

## 1. Kobling (roadmappens seks adgangskrav)

| | |
| --- | --- |
| Roadmapmål | Trin 4 (#147/#148): fortolkningskæden og klausulgranularitet |
| Værdikædeled | Klausullaget (evidens) → proposed-ingest |
| Leverancetype | Generel writer-operation (udgaveneutral) + rettelse af den generelle forslagswriter |
| Redaktionel værdi | 42 af 2018-20's 101 flerklausul-poster får hele sætninger i stedet for stumper; modellen og redaktøren læser meningsbærende klausuler (pilotens to kendte fejl ligger i dem) |
| Færdigbevis | Rehearsal mod et frisk prod-dump: 42 poster omsegmenteret, projektionen afstemt, 0 kanonisk delta, `anon` uændret; derefter prod-kørsel efter GO |
| Erstatter | Restore som eneste vej til at rette klausuler (beslutning 2026-09-17) |

## 2. Udgangspunkt (målt i koden)

- Klausuler er `private.source_observation`-rækker (`observation_kind='clause'`) under én
  helpost (`parent_observation_id`), med `UNIQUE(parent_observation_id, clause_ordinal)`
  (`ux_source_observation_clause_ordinal`) og append-only-trigger. De kan hverken slettes,
  ændres eller få en ny række med samme ordinal.
- `private.write_clause_evidence` afviser en post, der har klausuler
  (`REIMPORT_WRITER_CLAUSE_EVIDENCE_EXISTS`, `schema.sql:3392`).
- Hver klausul har en append-only dispositionsledger (`private.clause_disposition`,
  versioneret); maskinelle koder: `afventer_fortolkning`, `fortolkning_foreslaaet`,
  `afventer_identitet`, `maskinelt_flagget`, `strukturel`.
- **S4:** `private.write_interpretation_proposal` afviser kun en dublet i *samme* batch
  (`schema.sql:3649-3653`). Et nyt batch for samme post lægger nye `proposed` ved siden af de
  gamle. Trin 4-spec'en §7 kræver noget andet: »Genudtræk af en allerede ingestet record kræver
  en menneskelig `superseded`-beslutning og er trin 6.«
- Prod pr. 2026-09-27: 591 poster, 868 klausuler, **0 fortolkninger** (4.4 er parkeret). Ingen
  flade skriver menneskelige klausuldispositioner (hverken web, mobil eller en `red_*`-RPC); det
  efterprøves i rehearsalens dump.

## 3. Design

### 3.1 Klausulsæt som generation på rækken

Én ny nullable kolonne på `private.source_observation`: `clause_set_seq integer` (≥ 1; sat ⇔
`observation_kind='clause'`). Eksisterende 868 klausuler får `1` (ADD COLUMN med default fyrer
ingen UPDATE-trigger; default fjernes bagefter, så nye rækker skal angive den).

- Unikhed: `ux_source_observation_clause_ordinal` erstattes af
  `UNIQUE(parent_observation_id, clause_set_seq, clause_ordinal)`.
- Et nyt sæt skal være præcis `max(eksisterende)+1` (trigger), så sættene er en tæt,
  ordnet historik uden huller.
- **Aktuelt sæt** = højeste `clause_set_seq` pr. forælder. Ét view,
  `private.clause_observation_current` (`security_invoker`), er den eneste læsevej for »posts
  klausuler«.

Valgt frem for alternativerne:

| Alternativ | Hvorfor ikke |
| --- | --- |
| Slette/ændre de gamle klausuler | Bryder invariant 1 (append-only) og proveniensen for 4.1c's batch |
| Markere de gamle som afløst på rækken | Kræver UPDATE af append-only rækker |
| Separat `clause_set`-tabel | Unikhedsindekset kan ikke se en anden tabel; rækken skal alligevel bære sæt-id'et. En tabel kan tilføjes senere, hvis sæt får egne metadata |
| Ny helpost | Writerne kræver præcis én helpost pr. forekomst (`CLAUSE_EVIDENCE_PARENT_AMBIGUOUS`) |

### 3.2 Ny writer-operation `clause_revision`

`private.write_clause_revision(batch, element, payload)` + `public.red_apply_reimport_clause_revision`,
element-id `clause-revision:<record_key>`. Payload = `clause_evidence`'s lukkede nøglesæt plus
`replaces_clause_set_seq` og `replaces_ledger_sha256`.

Writeren:
1. Samme autorisation, lås, kontrakt- og anker-/rendition-/forælderkontroller som
   `write_clause_evidence` (fælles hjælpefunktion frem for kopi — P6-læren om to definitioner).
2. **Afviser fail-closed**, hvis
   - det aktuelle sæt ikke er `replaces_clause_set_seq`, eller dets ledger-hash (genberegnet af
     rækkerne, ikke aflæst af eventen) ikke er `replaces_ledger_sha256`
     (`CLAUSE_REVISION_BASE_DRIFT`);
   - en klausul i det aktuelle sæt citeres af en `interpretation_observation`
     (`CLAUSE_REVISION_HAS_INTERPRETATIONS`);
   - en klausul i det aktuelle sæt har en menneskelig disposition
     (`CLAUSE_REVISION_HAS_HUMAN_DISPOSITION`);
   - det nye sæt er identisk med det aktuelle (`CLAUSE_REVISION_NOOP`) — en uændret post hører
     ikke i manifestet.
3. Skriver det nye sæt (`clause_set_seq = gammelt+1`) med samme klausulvalidering og samme
   startdispositioner som `clause_evidence`.
4. Skriver pr. gammel klausul en maskinel disposition `erstattet` (ny kode i
   `clause_disposition_machine`) med batch- og manifestreference, så dispositionskøen ikke viser
   dem.
5. `reimport_event` med `operation='clause_revision'`, `before` = gammelt sæts ledger-hash og
   antal, `after` = nyt.

Afgrænsningen i punkt 2 er bevidst: en omsegmentering af en post med forslag eller menneskelige
afgørelser er trin 6 (»superseded«-beslutningen). Operationen dækker præcis det, beslutningen
2026-09-27 kræver: prod før 4.4, hvor intet afhænger af klausulerne.

**Fortrydelse:** en ny `clause_revision` tilbage til den gamle profils segmentering (sæt 3 = sæt
1's spans). Det er append-only symmetrisk og kræver ingen restore.

### 3.3 S4 i forslagswriteren

- Dublet-tjekket (`schema.sql:3649-3653`) udvides fra samme batch til **enhver** eksisterende
  `interpretation_proposal`-event for posten (`REIMPORT_WRITER_INTERPRETATION_PROPOSAL_EXISTS`).
  Genudtræk forbliver trin 6, som spec'en siger; indtil da er en ny kørsel for en post med
  forslag et STOP, ikke en stille dublet.
- Forslagswriteren slår citerede ordinaler op **i det aktuelle sæt**
  (`clause_observation_current`); et citat af en ordinal, der kun findes i et afløst sæt, er
  `REIMPORT_WRITER_CLAUSE_UNKNOWN`. Payloadens `verbatim_sha256` pr. citat kontrolleres som i
  dag mod den aktuelle klausul.
- Dispositionsoverskrivningen (`schema.sql:3766-3780`) kræver allerede, at den forrige er
  maskinel; med dublet-tjekket kan en anden forslags-kørsel ikke nå den. Uændret.

### 3.4 Læsere, der skal gå gennem det aktuelle sæt

Alle læsere af klausuler findes med `git grep "parent_observation_id\|clause_ordinal"`:
`write_interpretation_proposal`, `clause_evidence_projection.sql` (+ anon-projektionen),
`interpretation_proposal_projection.sql`, `interpretation_control_rows.sql`,
`export_43b_runner_input.R`, `export_clause_source_texts.R`, `export_clause_evidence_preview.R`,
`export_model_eligibility.R`, `db-verify.sql`. Hver skifter til `clause_observation_current`
eller filtrerer eksplicit på sættet.

**Værn mod en glemt læser:** en statisk CI-test afviser nye forekomster af
`observation_kind='clause'`/`parent_observation_id` uden for en navngiven tilladelsesliste (view,
writere, db-verify). Et glemt filter ville ellers vise to sæt side om side — tavst, fordi
ordinalerne 1..n findes i begge.

### 3.5 Manifest, profil og projektion

- **Profil:** `daa-2018-20-clause-revision-v1` (reimport-profil) binder regelversion
  `clause-rules-2018-20-v3` og den afledte `segmenter_version` fra ledgeren (P4).
- **Manifest-builder:** genbruger `build_clause_evidence_manifest.py` med en `revision`-tilstand,
  der kun tager poster, hvis klausulsæt ændres, og som bærer det gamle sæts ledger-hash fra prod
  (læst fra projektionen, ikke fra en fil). `expected_counts.clause_revisions = 42`.
- **Projektion:** `clause_evidence_projection.sql` projicerer det aktuelle sæt og
  `clause_set_seq`; den eksisterende komparator afstemmer mod den nye ledger.

## 4. Gate og rækkefølge

1. DDL (kolonne, indeks, trigger, view, vokabular, operation-CHECK, writer, RPC, ACL/RLS +
   `red_*`-vagtens liste) som idempotent migration; `schema.sql` opdateres i samme ændring (S3).
2. Tests: SQL-test for writeren (positiv, hver afvisning, fortrydelse via ny revision,
   append-only intakt), S4-test (andet batch for samme post ⇒ afvist), læser-test (to sæt ⇒ kun
   det aktuelle ses), den statiske CI-vagt.
3. **Rehearsal mod et frisk prod-dump** (prod har 0 fortolkninger, så alle 42 kan revideres; den
   bundne restore `daa43b_…` har 4.3b's 84 forslag og ville — korrekt — afvise dem):
   dry-run → apply → projektion `match` → 0 kanonisk delta → `anon` uændret → fortrydelses-
   revision → frem igen.
4. Prod: gate for privat lag uden kanonisk delta (runbook, backup, rehearsal, GO). DDL'en er
   `anon`-neutral, men RLS/ACL-ændringer ⇒ uafhængigt review efter budgettet.
5. Derefter piloten om for de 32 poster mod en ny restore (alle sendes igen; pilotens cache er
   kontrakt 1.0) og kontrolmodellen på de nye forslag; så 4.4+4.5 i prod.

## 5. Åbne punkter (afgøres i review eller af projektejeren)

1. **`clause_set_seq` på rækken vs. en `clause_set`-tabel.** Udkastet vælger kolonnen (mindst
   DDL). En tabel giver et sted til sættets proveniens (regelversion, segmenter, batch), som i
   dag kun står i `reimport_event`.
2. **Skal 1939 kunne bruge operationen?** Den er udgaveneutral, men 1939's klausuler findes
   ikke endnu (trin 6); ingen 1939-specifik kode.
3. **Den statiske læser-vagt** kan give falske alarmer i dokumentation/tests; tilladelseslisten
   skal holdes smal.
