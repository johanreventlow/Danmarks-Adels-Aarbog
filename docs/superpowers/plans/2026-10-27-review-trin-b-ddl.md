# Plan: review-handling trin B — fire funktionsrettelser i én DDL-ceremoni

> Grundlag: `docs/reviews/2026-10-27-trin-1-5/rapport.md` §6 trin B; `docs/decisions.md` 2026-10-27 (B1, B2, B9).
> Gren: ny gren fra `fix/review-trin-a` (`fix/review-trin-b`). **Review-budget (B13):** én uafhængig review-runde af
> diffen (Opus eller Codex) før GO; overskridelse kræver én linje i decisions.

## Adgangskrav (roadmap)

1. **Roadmapmål:** trin 5's afslutning — gates før trin 6 (rapport §6).
2. **Værdikædeled:** identitet/promotion (1d.3b-01) og redaktørens skrivevej + læsecache (1d.1-02/03/04).
3. **Leverancetype:** generel rettelse af eksisterende funktioner; ingen nye tabeller, ingen signaturændring.
4. **Værdi:** en relation kan ikke længere førstebindes til en anden familie end den afgjorte (samme fejlklasse som
   #248, der blev offentlig); redaktøren kan ikke stille ompege en konklusion eller slette importerede kildepåstande.
5. **Færdigbevis:** nye SQL-tests røde mod gammel kode og grønne mod ny; alle berørte CI-job grønne lokalt;
   ceremonien `DDL_OK` + før/efter-måling + `db-verify` grøn i prod; ingen ændring i prod-data, medmindre T0 viser
   noget (se T4).
6. **Erstatter:** intet workflow; lukker fund 1d.3b-01, 1d.1-03, 1d.1-02, 1d.1-04.

## Fortrydelse og dump (B1, første brug)

Fortrydelse = restore af dumpet taget lige før skrivningen, inden for et vindue, der lukkes udtrykkeligt efter
efterkontrollen. Før ceremonien: dump → sha256 → `age`-kryptering → upload til projektejerens SFTP-server → tjek af
den eksterne fils størrelse og sha. Én prøvegendannelse (hent, dekryptér, `pg_restore --list`) før første brug.
Engangsforberedelse hos projektejeren: `brew install age`, `age-keygen` (hemmelig nøgle i adgangskodemanager og
`~/.private/`), SFTP-adresse og login i `~/.private/`.

## Tasks

**T0 — læse-kun måling i prod (projektejeren kører scriptet med `!`).** Kun tal, ingen tekst:
- (a) antal konklusioner med `status <> 'afklaret'` på faktatyperne `navn`, `fødsel`, `død`, `titel` (styrer T4);
- (b) antal påstande pr. `uforanderlig` (sand/falsk/NULL) og pr. oprindelse (med/uden kilde i `citation.source_id`),
  så T3's vagt ikke rammer redaktørens egne påstande;
- (c) antal accepterede, ubundne ægteskabs- og forælderfortolkninger (1d.3b-01's udsatte mængde).
Målingen af id-sekvenserne er gjort 2026-10-27: alle 25 står på max(id).

**T1 — 1d.3b-01 (relationsbinding efter familieskift).** I `judged` i `preview_relation_promotions` for
`relation.marriage` og `relation.parent`: `(c.st#>>'{family,family_id}')::bigint IS DISTINCT FROM
(q.decision_evidence->>'family_id')::bigint` → `RELATION_PROMOTION_DECISION_FAMILY_CHANGED` (børnegrenen har vagten,
`schema.sql:17053`). Test: afgørelse → familieskift → førstebinding afvises for både ægteskab og forælder;
uændret familie binder fortsat. Afvejningen: `docs/reviews/2026-10-27-trin-1-5/afvejning-codex.md` §1d.3b-01.

**T2 — 1d.1-03 (`red_edit_oplysning`).** `ON CONFLICT (target_type,target_id) DO NOTHING` i stedet for `DO UPDATE`
(en ikke-valgt oplysning ompeger ikke længere konklusionen); kopiér `date_certainty`. Test for valgt og ikke-valgt.
*Uden for scope (kendt begrænsning, noteres):* datogrænserne `date_min/max` kopieres fortsat fra den gamle påstand,
når `p_date_raw` ændres. NULL betyder »åben« i datamodellen og må ikke bruges som nulstilling; en rigtig rettelse
kræver at web sender parsede grænser (signaturændring) og hører til en senere skive.

**T3 — 1d.1-02 (`red_slet_oplysning`).** Afvis sletning, når `uforanderlig` er sand (importerede kildepåstande);
redaktørens egne (`uforanderlig=false`) kan fortsat slettes. Afhænger af T0 (b). Test begge veje. Web viser i dag
slet-knappen på alle oplysninger (`web/src/Redaktion.tsx:1849`); skjul den for uforanderlige rækker, hvis feltet er
i datamodellen, ellers vises RPC'ens fejl.

**T4 — 1d.1-04 (cachen).** `AND c.status='afklaret'` i `navn_agg` i `regen_person_visning` + test (tilbagetrukket
navn → cachen ændres). Viser T0 (a) 0, ændrer regenereringen intet i prod. Viser den > 0: antallet af berørte
personer måles før, og regenereringen er en synlig dataændring under samme GO.

**T5 — SQL-filer.** Ændringerne skrives i `schema.sql` (sidste definition) og som én ny, idempotent, sha-bundet blok
sidst i `db-migrations.sql`. Paritetsvagten (`inspect-5ab-function-parity.sql`) udvides med de fire funktioner
(antallet i `ci.yml` rettes). Lokalt: alle schema-only og migrerede job, der berører filerne, plus
`run-db-verify-disposable` på begge baser.

**T6 — ceremoni (privat script i `~/.private/`, projektejeren kører det).** `--jeg-mener-det`, afviser ukendte flag.
Rækkefølge: GO-fil hash-tjek → dump + `age` + SFTP + tjek → `BEGIN; SET LOCAL lock_timeout='5s'`; kun den sha-bundne
blok → før/efter-fingeraftryk af de fire funktioner → `COMMIT` → `db-verify` (læse-kun) → måling. Projektejeren
tjekker rådgiveren (`get_advisors`) i dashboardet.

**T7 — dokumentation.** `database-current-state.md` ny sektion, `status.md` (trin B gjort), `changelog.md`.

## Rækkefølge og ansvar

T0 → (T1-T5 lokalt, ét commit pr. task) → review-runde → GO-fil → T6 → T7. Prod berøres kun i T0 (læse-kun) og T6
(efter GO). Ingen push uden projektejerens ord; PR som draft.

## Udført lokalt og reviewet (2026-10-27)

T1-T5 committet (`8aa51edc`..`1333e6e8`) og efter ét uafhængigt Opus-review (ingen P1, 8 × P3) rettet i
`dc9c0d16`..`61641756`: `date_certainty` arves kun ved uændret datotekst; web viser slet-knappen kun ved
`uforanderlig === false`; tests for manglende `family_id`, NULL-status og en NOTICE-tælling i `db-verify`
(`TRIN_B_DECISION_FAMILY_CHANGED_UNBOUND`). Prod T0 (læse-kun): 0 ikke-afklarede cachede konklusioner (NULL talt med),
0 `uforanderlig` NULL, 248/248 accepterede relationer med `family_id`, bundet og uden afvigelse — ceremonien ændrer
kun funktioner, ingen data.

**Kendte begrænsninger (bevidst ikke rettet her):**
- Mobil viser stadig slet-knappen på alle oplysninger (`mobile/src/app/redaktion/person/[id].tsx:229`); RPC'en afviser.
  Mobil er kun til udvikling.
- `red_source_persona_detail` (`schema.sql:9074`) joiner `conclusion` uden statusfilter; samme fejlklasse som T4.
- `RELATION_PROMOTION_REBIND_FAMILY_CHANGED` skygges af den nye vagt og har ingen direkte test; den værner kun mod
  gamle fejldata.
- `red_set_konklusion` nulstiller ikke status; »gør til konklusion« på et tilbagetrukket navn giver en tom cache
  (latent: `tilbagetrukket` bruges i dag ikke på cachede faktatyper).
- Genspil af en 5ab-pakke optaget før ceremonien kan give `STEP_ITEMS_MISMATCH`, hvis en afvisningsgrund er skiftet
  (fail-closed; ingen kendte tilfælde).
- Datogrænserne `date_min/max` følger fortsat den gamle påstand ved rettelse (se T2).
