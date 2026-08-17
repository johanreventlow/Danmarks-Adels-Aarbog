# DAA 1939 v50 Remaining Identity Review Design

**Dato:** 2026-08-17

**Status:** Godkendt af brugeren 2026-08-17.

## Formål

De 17 source records, som fortsat står som `genuinely_new_identity_pending`,
skal gennemgås mod den fulde 1939-kontekst. Målet er at skelne mellem samme
person som en eksisterende post, en reelt ny personkandidat, en strukturel
tekst/resume og et ægte uafklaret tilfælde. Gennemgangen må ikke oprette eller
ændre personer og må ikke skrive til databasen.

## Låste input

Reviewpakken bindes med SHA-256 til:

- `source-persona-materialization-v1.json`, som definerer de præcise 17 poster;
- `import-preview-v1.json` og v50-reconciliationen, som leverer record keys,
  source spans og ordret tekst;
- `database-profiles-v1.json`, som indeholder profilerne for alle 543
  eksisterende 1939-personankre;
- den rensede Calamari-tekst og den konkrete 1939-PDF/rendition;
- de allerede godkendte identity-decisions v1-v4.

Et ændret input, manglende post eller afvigende span/verbatimtekst stopper
bygning eller anvendelse. Rå OCR bevares ordret. Normaliseret tekst må kun
bruges som søgesignal og må aldrig erstatte kildeteksten.

## Reviewpakke

En deterministisk builder producerer
`remaining-identity-review-v1.json` og en læsbar Markdown-rapport. Pakken
indeholder præcis de 17 poster én gang i stigende kildeoffset og viser for hver:

- record key, source span og ordret tekst;
- komplet PDF-side samt relevante nabo-/sidebrudshenvisninger;
- foregående og efterfølgende v50-record;
- mulige senere v50-forekomster af hovedpersonen;
- konservative kandidater blandt alle 543 databaseprofiler;
- de eksakte signaler og deres kilde, ikke blot en score.

Kandidatsignaler kan være et diskriminerende navn, samtidige årstal, godsnavne,
slægtskabsudsagn og literal overlap. Et navn alene er ikke tilstrækkeligt ved
gentagne fornavne. Fuzzy/OCR-normaliseret lighed må foreslå en kandidat, men kan
aldrig autorisere en afgørelse. Konkurrerende kandidater og konkurrerende
source records opregnes eksplicit.

## Lukkede afgørelsestyper

Hver af de 17 poster får præcis én af følgende afgørelser:

1. `same_existing_person`
   Kræver én target-record-key og ét canonical person-id, som udgør et entydigt
   1939-anker. PDF/Calamari, lokal hierarkikontekst og personprofil skal samlet
   vise, at source recordet beskriver samme fysiske person.

2. `new_person_candidate`
   Bruges kun når recordet klart beskriver en selvstændig person, men ingen
   eksisterende person kan identificeres. Afgørelsen indeholder intet canonical
   person-id og giver ingen person-create-autorisation.

3. `structural_or_summary`
   Bruges til linjeintroduktion, overgangstekst, resume eller opremsning, som
   ikke selv må skabe en person. Et valgfrit `context_owner_record_key` må kun
   angives, når teksten entydigt hører til én eksisterende source record;
   ellers bevares den som ejerløs strukturel kildetekst.

4. `unresolved`
   Bruges ved utilstrækkelig eller modstridende evidens. Den må ikke have
   target, canonical person-id eller implicit disposition.

Kun `same_existing_person` kan udvide source-persona-materialiseringen. De tre
andre typer bevares i afgørelsesartefaktet og må ikke fortolkes som et match.

## Visuel og menneskelig kontrol

Codex må selv godkende et tilfælde, når komplet PDF-side, literal Calamari,
nabohierarki og målprofil er entydige og ikke har en konkurrerende forklaring.
Brugeren spørges kun ved reel identitets-, hierarki- eller personoprettelses-
tvivl. Spørgsmålet skal vise siden, record key, den relevante tekst og den
konkrete alternative fortolkning; et løst navn er ikke nok.

Alle maskinelle forslag starter `unresolved`. Afgørelser er append-only,
hashbundne og angiver reviewer, evidenshash og begrundelse. Manglende menneskelig
afgørelse forbliver synligt `unresolved`.

## Materialisering og database-preview

En ny append-only materialisering læser v1-personaerne og den komplette
17-posters beslutningsfil. Den må:

- bevare de 24 eksisterende personaer byte-/feltmæssigt uændret;
- tilføje kun godkendte `same_existing_person`-links;
- opgøre `new_person_candidate`, `structural_or_summary` og `unresolved`
  særskilt;
- bevare alle canonical create/update/delete-lister tomme og
  `authorized: false`.

En efterfølgende read-only database-preview kontrollerer nye target-record/
person-id-par mod en frisk `person_external_id`-snapshot. Den erstatter den
samlede 17-blocker med præcise blockers, eksempelvis
`genuinely_new_identity_pending:<n>` og
`genuinely_new_person_creation_pending:<n>`. Strukturelle records er en
informationskategori, ikke en personoprettelse. `reimport_gate` forbliver
`NO-GO`; denne fase implementerer ingen writer eller migration.

## Tests og audit

Implementeringen følger RED → GREEN og skal bevise:

- eksakt 17/17-dækning uden dubletter eller ekstra records;
- stabil kildeorden og identiske source spans/verbatimtekster;
- lukket schema og afvisning af ukendte felter/afgørelsestyper;
- entydige targets og afvisning af skjulte eller konkurrerende ejere;
- at kun `same_existing_person` kan skabe et persona-link;
- at `new_person_candidate`, `structural_or_summary` og `unresolved` aldrig
  autoriserer canonical writes;
- hashbinding til alle input og byteidentisk genbygning af reviewpakken;
- read-only database-session, nul target-mismatches og stabile blockers.

Realdataauditten skal for hver post dokumentere PDF-side, Calamari-offset,
klassifikation, eventuelt mål og begrundelse. Midlertidige PDF-renderinger må
ikke committes.

## Afgrænsning

Arbejdet klassificerer og forbinder kildetekst; det opretter ikke de personer,
som eventuelt ender som `new_person_candidate`. Private evidenstabeller,
provenanceprojektion, production writer, replay, rollback og faktisk reimport
kræver senere, særskilt design og udtrykkelig autorisation. Den gamle
`load_daa.R` forbliver urørt.
