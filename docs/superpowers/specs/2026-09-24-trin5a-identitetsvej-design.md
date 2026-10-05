# Trin 5a — én identitetsvej med kandidater og spor i databasen (#151)

**Status:** designudkast, godkendt sektion for sektion i brainstorm 2026-09-24; revideret efter
Codex runde 1 (NO-GO: 2 BLOCKER, 3 MAJOR, 4 MINOR — alle godtaget, se §14) og runde 2 (NO-GO: 1 BLOCKER,
1 MAJOR, 5 MINOR — alle godtaget, se §15; budgettets sidste planrunde, rettelserne efterprøves i koderunden). Trin 5 er aktiveret som
programmål 2026-10-05 (`docs/decisions.md`, efter prod-overførslen af 2018-20's kæde); spec og plan er
genbekræftet mod `main` samme dag (§16).

**Roadmap:** trin 5, »Placement/membership og én identitetsvej konsolideres (#150/#151)«. Trin 5
deles i tre delspecs, i denne rækkefølge:

1. **5a — identitetsvejen (#151)** — denne spec.
2. **5b — andre personer i posten** — personas for ægtefæller, børn og øvrige nævnte, og oprettelse
   af nye kanoniske personer fra kilden (trin 4-spec §11.3 og §11.7).
3. **5c — slægt, linje og generation (#150)** — placement og membership afløser de gamle
   koordinatkolonner; kræver header-observationer og paritet for `red_person_grid`/`red_match_personer`.

5a kommer først, fordi den er mindst, fordi 5b's identitetsafgørelser skal gå samme vej, og fordi
den lukker et audit-hul: i dag findes 1939's identitetsafgørelser kun i lokale filer.

## 1. Adgangskrav (roadmap)

| Krav | Svar |
| --- | --- |
| Roadmapmål | Trin 5 (#151) |
| Værdikædeled | Source personas og identitetskandidater → menneskelig afgørelse (identity gate, målarkitekturens gate 5) |
| Leverancetype | Generel motor (kandidatlag, writer, guard, ark, webkø); ingen udgaveprofil |
| Redaktionel værdi | Redaktøren får maskinens kandidatforslag med begrundelse, afgør i ark eller web, og hver afgørelse står i databasen med aktør, tidspunkt, grundlag og om forslaget blev fulgt |
| Færdigbevis | Kalibrering mod 587 kendte svar + blind ende-til-ende-genbekræftelse af en stikprøve i restoren (§8) |
| Erstatter | Lokale token-/HTML-ark med batch-writer der skriver `accepted` direkte (1939 v50), og id-indtastning i webkøen |

## 2. Udgangspunkt (målt i restoren `daa43b_20260912192527`, 2026-09-24)

- `private.source_persona`: 595 — 587 fra 2018-20 (source 1), 8 fra 1939 (source 3). Alle har en
  `accepted` identitet med kanonisk person.
- Evidensens autoritet: `person_external_id` (587, 149b's legacy-migration) og batch-hash
  (`batch_id`, `decision_sha256`; 8, 1939's materialisering). Ingen afgørelse er truffet i webkøen.
- 1939's ca. 550 identitetsmatch findes ikke i persona-laget — kun som C3-postbindinger
  (`existing_exact_binding`) og i arkiverede lokale filer. Den gamle 1939-writer er slået fra
  (`NARRATIVE_RECORD_LEGACY_WRITER_DISABLED`).
- Alle skrivninger i `source_persona_identity` går allerede gennem
  `red_decide_source_persona_identity`; webkøens `red_afgoer_source_persona` kalder den.
- **Hul:** `proposed` kræver `canonical_person_id IS NULL` (`source_persona_identity_target_check`).
  Maskinen kan derfor ikke foreslå en kandidat, og webkøen beder redaktøren indtaste et person-id.
- `KildepersonaKo` (136 linjer) har tre knapper og et id-felt; `red_source_persona_history` kaldes
  ikke af UI.
- `@daa/core` har en deterministisk, rådgivende matcher (`matchUdgaver`: navnefoldning,
  Jaro-Winkler, fødsels-/dødsår, køn, top-K, tiers `auto`/`review`/`none`, `evalPrecisionRecall`).
  Vægtene er TNG-QA-startværdier, aldrig kalibreret mod DAA-personas.

## 3. Beslutninger fra brainstormen

1. **Kun fremadrettet.** De 595 eksisterende afgørelser bliver stående med deres oprindelse
   (»migration«). 1939's match flyttes ind i persona-laget i trin 6, når 1939 køres gennem kæden.
   Ingen massegenbekræftelse.
2. **To flader, én vej.** Token-ark til store mængder og webkøen til enkeltsager; begge skriver
   gennem `red_afgoer_source_persona` med redaktøren som aktør.
3. **Nye personer er ikke med.** En ny udgang `new_person_needed` parkerer sagen synligt; oprettelse
   er 5b.
4. **Kandidater gemmes i egen tabel (tilgang A).** Fravalgt: kandidater beregnet løbende uden lagring
   (to implementeringer, forslaget kan ikke genskabes) og at løsne `target_check` (blander forslag og
   afgørelse og svækker promotion-gatens invariant).

## 4. Datamodel

Additivt, i `private`, append-only; ingen ændring af `source_persona_identity` eller dens hændelseslog.

```sql
CREATE TABLE private.source_persona_identity_candidate_run (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_id          bigint NOT NULL REFERENCES public.source(id),
  generator_version  text NOT NULL CHECK (btrim(generator_version)<>''),
  config_sha256      text NOT NULL CHECK (config_sha256 ~ '^[0-9a-f]{64}$'),
  input_sha256       text NOT NULL CHECK (input_sha256 ~ '^[0-9a-f]{64}$'),
  persona_count      integer NOT NULL CHECK (persona_count>=0),
  candidate_count    integer NOT NULL CHECK (candidate_count>=0),
  created_by         uuid NOT NULL,
  created_by_name    text NOT NULL CHECK (btrim(created_by_name)<>''),
  created_at         timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE private.source_persona_identity_candidate (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id               uuid NOT NULL REFERENCES private.source_persona_identity_candidate_run(id),
  source_persona_id    uuid NOT NULL REFERENCES private.source_persona(id),
  candidate_person_id  bigint NOT NULL REFERENCES public.person(id),
  rank                 integer NOT NULL CHECK (rank>=1),
  score                numeric NOT NULL CHECK (score>=0 AND score<=1),
  tier                 text NOT NULL CHECK (tier IN ('auto','review','none')),
  basis                jsonb NOT NULL CHECK (jsonb_typeof(basis)='object' AND basis<>'{}'::jsonb),
  UNIQUE (run_id, source_persona_id, candidate_person_id),
  UNIQUE (run_id, source_persona_id, rank)
);
```

- En persona uden kandidater har ingen rækker i kørslen; `persona_count` tæller alle vurderede.
- **Gældende kørsel** pr. kilde er den med højeste `run_seq` (`bigint GENERATED ALWAYS AS IDENTITY`,
  tilføjet ved planlægningen; tidsstempler kan være ens); ældre kørsler bevares og kan refereres af
  gamle afgørelser. Kørslen gemmer også `config jsonb` (generatorens konfiguration) og
  `candidates_sha256`.
- Append-only gælder `UPDATE`, `DELETE` **og** `TRUNCATE` (statement-trigger som de øvrige
  evidenstabeller).
- `basis` rummer de signaler, der matchede (`name`, `birth`, `death`, `sex`), hvilke persona-felter der
  blev brugt og om de kom fra `accepted` eller `proposed` fortolkninger. Ingen kildetekst ud over det,
  der allerede står i personaens mentions.
- RLS: ingen læseret for `anon`/`authenticated`; adgang kun gennem `red_*`-RPC'er med rollegate
  `redaktion` (samme mønster som de øvrige `private`-tabeller). Revoke navngiver rollerne eksplicit.

### 4.1 Afgørelsens udgange

`red_afgoer_source_persona` får en fjerde handling; statusordforrådet er uændret.

| Handling | `decision_status` | Kræver | Evidens (ud over note) |
| --- | --- | --- | --- |
| `same` | `accepted` | person-id | `basis`; ved fulgt kandidat `candidate_id` + `run_id` |
| `different` | `rejected` | intet mål | `basis` |
| `unresolved` | `unresolved` | intet mål | `basis` |
| `new_person_needed` (ny) | `unresolved` | intet mål | `basis`, `reason: new_person_needed` |

- `basis` ∈ `web_detail`, `human_sheet`. Ved `human_sheet` også `sheet_sha256`, `rows_sha256`, `line`.
- `candidate_id` og `run_id` angives altid sammen. Kandidaten skal tilhøre personaen og `run_id`, og
  ved `same` skal person-id være kandidatens; ellers `EVIDENCE_IDENTITY_CANDIDATE_MISMATCH`.
  `run_id` skal være kildens gældende kørsel **på afgørelsestidspunktet**, ellers
  `EVIDENCE_IDENTITY_CANDIDATE_RUN_STALE`. Afgørelses-RPC'en tager en delt og kandidatwriteren en
  eksklusiv transaktionslås pr. kilde, så en ny kørsel ikke kan indsættes mellem kontrol og commit.
- Noten er fortsat obligatorisk (RPC'ens eksisterende krav); arket genererer en automatisk note
  (`ark <sheet_sha256 kort> linje N`), som redaktørens egen note lægges til.
- `new_person_needed` kan filtreres via `evidence->>'reason'` i kø-RPC'en.

### 4.2 Guard mod de gamle veje (revideret efter review runde 1)

Guarden er **strukturel**, ikke en selvangivet evidens-nøgle og ikke et `xmin`-tjek:

- **Én privat kerne:** `private.decide_source_persona_identity(persona, person, forventet version,
  status, evidens, p_origin)` med `p_origin` ∈ `human`, `person_create`, `legacy_match`, `reversal`. Ingen grants;
  kun `SECURITY DEFINER`-funktioner på serveren kalder den. Den offentlige
  `red_decide_source_persona_identity` fjernes (revoke, ud af allow-listen, droppet).
- **`human`** — kun fra `red_afgoer_source_persona` (den eneste klientindgang); `basis` ∈
  `web_detail`, `human_sheet` sættes af wrapperen efter validering af konteksten.
- **`person_create`** — kun fra writere, der selv indsætter personen i samme funktion
  (`red_apply_reimport_person_create`, `red_apply_1939_v50_person_create`); person-id'et kommer fra
  deres egen oprettelse og kan ikke leveres af klienten. Kræver `accepted`, ny persona (forventet
  version 0) og en **oprettelseskvittering**: personen skal være oprettet gennem
  `private.insert_person_with_receipt` i samme toptransaktion (`pg_current_xact_id()`, 64-bit, ens i
  subtransaktioner), og kvitteringen forbruges én gang. Et `person_create`-kald med en eksisterende
  person har ingen kvittering og afvises.
- **`reversal`** — kun fra fortrydelseswriterne; kræver `superseded` og `reversed_batch_id`.
- **`legacy_match`** — kun fra 149b's `private.migrate_legacy_narrative_record`: den faste
  1:1-kobling via `person_external_id` fra en tidligere import, ikke et lighedsmatch. Kræver
  `accepted`, forventet version 0, `authority='person_external_id'`, og kernen efterprøver selv, at
  der er præcis én `person_external_id` for (kilde, postnøgle), at den peger på personen, og at
  personen kun har den ene eksterne nøgle i kilden (projektejerens valg 2026-09-24, som præciserer
  §13.2). 149b's migration og dens fortrydelse per element virker uændret.
- **Batch-match ud fra lighed eller fri evidens er lukket** — ingen oprindelse tillader det.
- **Tillidsgrænse:** rollen `redaktion` er grænsen, som overalt i systemet. Et script, der kalder
  wrapperen med redaktørens login, er en redaktørafgørelse; `human_sheet` binder arkets og
  rækkefilens hash, så afgørelsen kan spores til det godkendte ark.
- **Ingen åben mellemtilstand under deploy:** en **cutover-blok som første sætning** i
  `db-migrations.sql` fjerner klientrollernes adgang til den allerede installerede gamle kerne og
  femarguments-wrapper, før resten af filen kører; derefter erstattes definitionerne **på deres
  eksisterende plads** (kernen, wrapperen, writernes kald), så intet uguardet objekt installeres eller
  grantes undervejs. Webkøens afgørelser fejler lukket fra cutover til den nye wrapper er oprettet;
  deployet sker under skrivepause for webkøen. En statisk test (eksakt kalder-allowlist), en
  cutover-test fra et prod-lignende katalog og en funktionsflade-test håndhæver det.

Eksisterende rækker og hændelser røres ikke. `source_persona.py` (0 konsumenter) slettes eller tages
i brug; planen afgør det efter læsning.

## 5. Generatoren

- **Placering:** Node-CLI i monorepoet, der importerer `matchUdgaver` fra `@daa/core`. Én matcher i
  systemet; webkøen viser kun gemte kandidater.
- **Input:** personas uden gældende afgørelse (eller en eksplicit liste i genbekræftelsestilstand,
  §8.2) fra én kilde. Persona-siden: navn fra personaens mention (`nameKey` via `matchKey`), fødsels-
  og dødsår fra personaens fortolkninger (`accepted` foran `proposed`), køn hvor kendt. Person-siden:
  `person` med visningsnavn, køn og fødsels-/dødsfakta.
- **Output:** top-K (standard 3) pr. persona med score, tier og signaler. **Ingen automatisk accept** —
  heller ikke ved tier `auto`; tier bruges kun til sortering.
- **Input er serverens:** `private.identity_candidate_input(source_id)` bygger generatorens input
  deterministisk (personas uden gældende afgørelse + personer, `ORDER BY … COLLATE "C"`); eksporten
  kalder den gennem en rollegatet `red_identity_candidate_input(source_id)`.
- **Skrivning:** ny writer-RPC `red_record_identity_candidates(run jsonb, candidates jsonb)` i én
  transaktion med rollegate og eksklusiv kildelås. Writeren **genberegner** inputtet og kræver
  `input_sha256` = SHA-256 af det (`IDENTITY_CANDIDATE_INPUT_DRIFT`), udleder `persona_count` selv,
  kræver at hver kandidats persona og person findes i inputtet, og beregner `config_sha256` og
  `candidates_sha256` af det modtagne. `config_sha256` nøgler idempotensen og autoriserer intet;
  rangeringen genberegnes ikke på serveren (den er Node) — kandidaterne er forslag, mennesket
  afgør. Idempotent på `(source_id, input_sha256, config_sha256)` via `INSERT … ON CONFLICT` og
  låst sammenligning af `candidates_sha256`.
- **Privatliv:** ingen modelkald; CLI'en printer kun tal og hashes. Mod prod køres den via
  projektejerens shell (klassifikator- og GO-regler som hidtil).
- **`evidensNormaliseret`** (matcherens opt-in for personer uden årstal, typisk ægtefæller) måles på
  samme facit som standardkonfigurationen; konfigurationen vælges på målte tal, ikke antagelse.

## 6. Token-arket

Nyt `identity_decision_sheet.py` ved siden af `interpretation_decision_sheet.py`. Den fælles hash-,
orden- og identitetskontrol flyttes til et delt modul (fx `decision_sheet_core.py`), så arkene ikke
divergerer. Udtrækningen sker **efter 4.5's Task 6**, så pilotens kode ikke ændres midt i kørslen.

1. **Eksport** af rækkefil (0600, uden for repoet, hash-bundet): persona-id, forventet version,
   postnøgle, mention-rolle, navn som i kilden, personaens fortolkninger og kandidaterne fra gældende
   kørsel inkl. `run_id`.
2. **Render:** én blok pr. persona, sorteret efter bedste tier og score (sikreste først).

```
# POST I-105 · persona: <navn fra kilden> · nævnt som: ægtefælle
#   fortolkninger: født 1801 (foreslået) · gift med hovedpersonen
#   1: person 1234  <navn>  1799–1860  score 0.91  auto   [navn, fødselsår]
#   2: person 2201  <navn>  1801–?     score 0.74  review [navn]
#   ingen anbefaling udfyldt — vælg selv
D 5b1c…-uuid 0 : _
```

| Token | Handling |
| --- | --- |
| `1`, `2`, `3` | `same` med kandidat nr. n (`candidate_id` + `run_id` i evidensen) |
| `P <person-id>` | `same` med en anden person |
| `X` | `different` |
| `N` | `new_person_needed` |
| `U` | `unresolved` |
| `_` | uafgjort — stopper oversættelsen |

   Efter tokenet må en note følge efter `#`.
3. **Ingen forudfyldning fra matcheren.** Kun en tidligere menneskelig dom må forudfylde (som 4.5,
   ERRATA 8.2); i 5a findes ingen sådan, så alle linjer starter som `_`.
4. **Oversættelse:** arkets hash skal matche den godkendte, rækkefilens hash den forventede,
   beslutningerne dækker præcis rækkefilens personas i arkets orden, ingen `_`, og `run_id` i rækkefilen
   skal stadig være gældende kørsel for alle kandidat-tokens (ellers `SHEET_CANDIDATE_RUN_STALE`). SQL'en
   er én transaktion med `ON_ERROR_STOP`, rolle `authenticated` og `request.jwt.claim.sub` sat til den
   udpegede redaktør, ét `red_afgoer_source_persona`-kald pr. linje og en optælling til sidst.
5. **Negativtest før apply:** ændr sidste linjes version og kør i en transaktion, der skal fejle og
   rulle alt tilbage (0 nye hændelser).

## 7. Webkøen

- `red_source_persona_detail` udvides med kandidaterne fra gældende kørsel (navn, årstal, score, tier,
  signaler, `run_id`) og en kollisionsliste: kandidatpersoner **fra samme gældende kørsel**, der
  allerede er `accepted` for en anden persona i samme post eller kilde.
- `KildepersonaKo`:
  1. kandidatkort med knappen »Samme som denne« (sender `candidate_id` + `run_id`);
  2. personsøgning: et filterfelt over den eksisterende personliste (`fetchRedaktionPersoner`) i stedet
     for at bladre i hele listen;
  3. knappen »Ny person nødvendig« (note påkrævet);
  4. kollisionsadvarsel — synlig, ikke blokerende;
  5. historik via `red_source_persona_history`, inkl. om kandidatforslaget blev fulgt;
  6. sortering efter tier og filtre for kilde, status og `new_person_needed`.
- Alle knapper kalder `red_afgoer_source_persona` med `basis: web_detail`. En rettelse er en ny
  afgørelse med forventet version; historikken bevares.
- Ikke med: klausul-spans og tværkilde-modstrid i detaljen; mobil (parkeret).

## 8. Færdigbevis (i restoren, ikke i prod)

Alle personas har allerede en afgørelse, og 5b's personas findes ikke endnu; beviset bygges derfor på
kendte svar.

### 8.1 Kalibrering

Generatoren køres på de 587 personas fra 2018-20 i en kopi af den fulde 2018-20-kørsels base
(`daa2018f_20261001133125`: alle 488 tilladte poster gennem kæden, 676 afgørelser, 622 bindinger — samme
indhold som prod efter overførslen 2026-10-05), uden at se deres afgørelser. Måles mod de
accepterede identiteter:

- andel med rigtig person som kandidat 1 (top-1) og blandt top-3;
- andel uden kandidater;
- præcision pr. tier (hvor ofte kandidat 1 er rigtig, når tier er `auto` hhv. `review`);
- det samme med `evidensNormaliseret`, og separat for personas uden årstal.

Navnene kommer fra `person.name`-fortolkninger med kendte titelfejl (decisions 2026-10-03); de
trækker navnelighed ned og nævnes i rapporten som kendt forstyrrelse.

Tallene rapporteres uden navne. Der sættes ingen tærskel på forhånd, som gør matcheren »godkendt« —
tallene afgør, hvordan tier må præsenteres (fx om `auto` må stå først i arket), og indgår i 5b's
design.

### 8.2 Blind ende-til-ende-genbekræftelse

Ca. 30 af de 587, stratificeret på tier, sendes gennem hele kæden i genbekræftelsestilstand:
generator → rækkefil → ark (uden det gamle svar) → projektejerens afgørelse og hash → SQL med
negativtest → `red_afgoer_source_persona` → historik. Bagefter sammenlignes med det gamle svar. Det
beviser kæden og giver en menneskeligt målt præcision for kandidaterne. Webkøens spor bevises uden
en levende webkø mod arbejdsbasen (der findes ingen lokal Supabase-API, og webben må aldrig pege
på en ukendt base): webkøens datalag bygger payloaden i en vitest-test, samme payload sendes til
`red_afgoer_source_persona` i arbejdsbasen via psql, og de to spor (ark og web) sammenlignes felt for
felt (samme struktur, forskellig `basis`). En levende webkø-afgørelse hører til 5b, når der findes
personas uden afgørelse.

Genbekræftelsen skriver nye versioner i arbejdsbasen (en kopi), aldrig i restoren og aldrig i prod.

## 9. Test

- **SQL** (CI's friske schema-sti): tabeller og constraints inkl. `TRUNCATE`; writer-RPC (rollegate,
  genberegnet input, falsk hash, forkert antal, udeladt persona, ændret DB-input, idempotens, samtidige
  identiske kald); de fire udgange; `candidate_id` der ikke hører til personaen; forældet `run_id`;
  kildelåsen (en anden forbindelse holder den eksklusivt ⇒ afgørelsen venter/timeout); kernen er
  ikke kaldbar for `authenticated`; hver `p_origin` med sine krav; 149b-writeren lukket;
  eksisterende rækker uændrede; funktionsfladen efter én migrationskørsel (ingen femarguments-wrapper,
  ingen offentlig kerne).
- **Pytest** for arket: alle tokens, `_` stopper, byttede og slettede linjer, ændret rækkefil, forældet
  kørsel, forkert version, note-escaping; delt modul testet én gang og brugt af begge ark.
- **Node/vitest** for generatoren (deterministisk output og hash for fast input, top-K, ingen
  auto-accept) og for webkøens datalag og komponent (kandidatklik, søgning, ny person, kollision,
  historik, `run_id` i payloaden); ingen Playwright (§13.5).
- `get_advisors` efter DDL.

## 10. Prod

Leverancen til prod er skema, RPC'er og webkøen — **ingen dataændring**. DDL via `db-migrations.sql`
med GO; `db-verify.sql` udvides med asserts for de nye tabeller og guarden. Generatoren køres i prod
først, når 5b har skabt personas uden afgørelse. Fortrydelse af DDL'en er en migration, der dropper de
tomme tabeller og gendanner RPC'erne; data i prod berøres ikke.

## 11. Rækkefølge (til planen)

1. Kortlægning af identitetskaldere (§4.2) — målt, før noget ændres.
2. Datamodel + writer-RPC + SQL-tests.
3. Generator + kalibrering (§8.1).
4. Delt arkmodul (efter 4.5's Task 6) + `identity_decision_sheet.py`.
5. Detalje-RPC + webkø.
6. Guard og lukning af de gamle veje.
7. Blind genbekræftelse (§8.2) og rapport.

## 12. Åbne punkter (registreres, løses ikke her)

1. Om `auto`-tier nogensinde må forudfylde arket — afgøres først på 8.1's og 8.2's tal.
2. 1939's ca. 550 match ind i persona-laget — trin 6.
3. Oprettelse af nye kanoniske personer og personas for andre aktører — 5b.
4. Placement-signal i matcheren (slægt/linje/generation) — når 5c leverer placements.
5. Klausul-spans og tværkilde-modstrid i persona-detaljen (#151's opfølgning).

## 13. Ændringer ved planlægningen (2026-09-24)

Målt eller besluttet af projektejeren, mens planen blev skrevet; planen
(`docs/superpowers/plans/2026-09-24-trin5a-identitetsvej.md`) følger disse punkter.

1. **Navnekilde (§5).** 2018-20's 587 personas har kun én mention af typen `person_post`, som
   dækker hele posten; den er ikke et navn, og postens indledning er uregelmæssig (kun 118 af 587
   har 2–6 ord før første komma). Personaens navn tages derfor fra `person.name`-fortolkningen
   (`accepted` foran `proposed`) eller fra en navne-mention (`mention_kind='person'`, fx 1939).
   Uden navn: ingen kandidater, talt for sig. Kalibreringen (§8.1) køres på den fulde
   2018-20-kørsels base (§16; oprindeligt »ca. 27« navngivne personas i pilotbasen) og gentages i 5b.
2. **Guard-regel (§4.2).** Kortlægningen viste tre slags ikke-menneskelige skrivninger:
   fortrydelser (`superseded` + `reversed_batch_id`), oprettelse (`red_apply_reimport_person_create`
   binder en persona til den person, den lige har oprettet) og batch-match til eksisterende
   personer (149b-mønstret). Projektejeren valgte: menneskelig basis og fortrydelse tilladt;
   batch-evidens kun når personen er oprettet i samme transaktion; batch-match til eksisterende
   personer lukket. Implementeret strukturelt med en privat kerne og `p_origin` (§4.2, revideret efter review
   runde 1; `xmin`-tjekket udgik).
3. **Rangering (§5).** `matchUdgaver`'s `assignTiers` er injektiv; flere personas kan være samme
   person, så generatoren rangerer selv pr. persona oven på `buildScored`/`scorePair` med samme
   tier-tærskler.
4. **Generatorens form (§5).** Der findes ingen Node-DB-klient i repoet; CLI'en er en ren funktion
   (psql eksporterer JSON, CLI'en rangerer, psql skriver via writer-RPC'en) og kører gennem `tsx`.
5. **Webtest (§9).** Der findes ingen Playwright-fixture for redaktionslogin; webkøen dækkes af
   vitest-komponenttests, og én afgørelse i webkøen mod den lokale base indgår i beviset (§8.2).

## 14. Revision efter Codex runde 1 (2026-09-24)

| Fund | Ændring |
| --- | --- |
| BLOCKER 1 — guarden kunne omgås og afviste legitime oprettelser (`xmin`, direkte kerne, selvangivet basis) | §4.2: privat kerne med `p_origin`, ingen grants; `person_create` kun fra writere, der selv indsætter personen; `xmin`-hjælperen udgår; tillidsgrænsen er rollen `redaktion` |
| BLOCKER 2 — migrationen genåbnede den gamle vej undervejs | §4.2: erstatning på eksisterende plads; statisk test + funktionsflade-test efter én kørsel |
| MAJOR 1 — kandidatkørslens aktualitet ikke atomisk | §4.1: `candidate_id` + `run_id` sammen; aktualitet kontrolleres i RPC'en under kildelås |
| MAJOR 2 — writeren stolede på klientens hashes og antal | §5: serverbygget input genberegnes; `persona_count` udledes; persona-/personmængde kontrolleres |
| MAJOR 3 — webbeviset var ikke bundet til arbejdsbasen | §8.2: ingen levende webkø mod arbejdsbasen; payload-paritet via vitest + psql |
| MINOR 1 — `TRUNCATE` | §4: statement-trigger |
| MINOR 2 — detaljetest kunne bestå uden nøgler | Planen: `jsonb_typeof(...)='array'` før længde |
| MINOR 3 — historiske kollisioner | §7: kollisioner fra samme gældende kørsel |
| MINOR 4 — samtidige identiske kald | §5: `ON CONFLICT` + låst sammenligning |

## 15. Revision efter Codex runde 2 (2026-09-24)

| Fund | Ændring |
| --- | --- |
| BLOCKER — gammel kerne/wrapper aktiv i migrationens præfiks | §4.2: cutover-blok som første sætning; test fra prod-lignende katalog |
| MAJOR — `person_create` bandt ikke person-id'et til oprettelsen | §4.2: oprettelseskvittering udstedt af `insert_person_with_receipt`, forbrugt af kernen |
| MINOR — parseren (falske positiver/negativer, `>= 9`) | Planen: eksakt allowlist (fil, funktion, oprindelse, antal), kommentarer fjernet, negative fixtures |
| MINOR — samtidighedstesten beviste kun låsen | Planen: to forbindelser, samme `run_id`, én run-række |
| MINOR — 149b-fortrydelsesvejen forkert beskrevet / MINOR — db-verify afviste lukket 149b | Bortfaldet: 149b lukkes ikke (projektejerens valg, `legacy_match`); testen og db-verify uændrede |
| MINOR — Task 9 kunne mangle web-persona | Planen: web-personaen reserveres før stikprøven |
| MINOR — personsøgningen blev ikke bygget | §7/planen: filterfelt over den eksisterende personliste + test |

Kaldertabellen er rettet (`db-migrations.sql:8066`, `:8246` er versioner af `red_reverse_1939_v50_reimport`).

## 16. Genbekræftelse mod `main` (2026-10-05)

Spec og plan er holdt op mod `main` 984070e, 19 commits efter planens grundlag (4.5, kontrolmodel,
omsegmentering, udvalgsbygger, prod-overførsel). Identitetsguardens funktioner er byte-identiske, og
kernens kaldere er de samme; designet står uændret. To ændringer:

| Emne | Ændring |
| --- | --- |
| Kalibreringens base (§8.1, §13 punkt 1) | Kopi af `daa2018f_20261001133125` (den fulde 2018-20-kørsel) i stedet for pilotbasen efter 4.5 — flere hundrede navngivne personas i stedet for ca. 27. Projektejerens valg 2026-10-05. |
| Erstatning på stedet (§4.2) | Gælder identitetsguardens funktioner. Detalje- og kø-RPC'en må omdefineres sidst i `db-migrations.sql` (som omsegmenteringen gør), da en mellemtilstand med den gamle version er harmløs. |
