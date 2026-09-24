# Trin 5a — én identitetsvej med kandidater og spor i databasen (#151)

**Status:** designudkast, godkendt sektion for sektion i brainstorm 2026-09-24. Implementering
kræver, at projektejeren aktiverer trin 5 som programmål i `docs/decisions.md`; trin 4 (#147/#148)
er det aktive mål, indtil 4.5's pilotrapport og prod-beslutning foreligger.

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
- **Gældende kørsel** pr. kilde er den seneste; ældre kørsler bevares og kan refereres af gamle
  afgørelser.
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
- Angives `candidate_id`, skal kandidaten tilhøre personaen og `run_id`, og ved `same` skal person-id
  være kandidatens; ellers `EVIDENCE_IDENTITY_CANDIDATE_MISMATCH`.
- Noten er fortsat obligatorisk (RPC'ens eksisterende krav); arket genererer en automatisk note
  (`ark <sheet_sha256 kort> linje N`), som redaktørens egen note lægges til.
- `new_person_needed` kan filtreres via `evidence->>'reason'` i kø-RPC'en.

### 4.2 Guard mod de gamle veje

`red_decide_source_persona_identity` afviser nye afgørelser, hvis `evidence->>'basis'` ikke er
`web_detail` eller `human_sheet` (`EVIDENCE_IDENTITY_BASIS_REQUIRED`). De historiske autoriteter
(`person_external_id`, batch-hash) kan ikke længere skrives. Eksisterende rækker og hændelser røres ikke.

Før guarden aktiveres, kortlægges alle kaldere målt, ikke antaget: 1939's
`materialize_source_personas_1939_v50.py` og `materialize_remaining_source_personas_1939_v50.py`,
149b's legacy-writer og især **om en 149b-fortrydelse skriver identitetshændelser**. Hver kalder får
enten den nye basis, eller markeres historisk og slås fra med en guard som den gamle 1939-writer. En
kalder, der skal bestå, men ikke passer i de to basis-værdier, er et STOP og en beslutning, ikke en
tredje basis indført i stilhed. `source_persona.py` (0 konsumenter) slettes eller tages i brug; planen
afgør det efter læsning.

## 5. Generatoren

- **Placering:** Node-CLI i monorepoet, der importerer `matchUdgaver` fra `@daa/core`. Én matcher i
  systemet; webkøen viser kun gemte kandidater.
- **Input:** personas uden gældende afgørelse (eller en eksplicit liste i genbekræftelsestilstand,
  §8.2) fra én kilde. Persona-siden: navn fra personaens mention (`nameKey` via `matchKey`), fødsels-
  og dødsår fra personaens fortolkninger (`accepted` foran `proposed`), køn hvor kendt. Person-siden:
  `person` med visningsnavn, køn og fødsels-/dødsfakta.
- **Output:** top-K (standard 3) pr. persona med score, tier og signaler. **Ingen automatisk accept** —
  heller ikke ved tier `auto`; tier bruges kun til sortering.
- **Skrivning:** ny writer-RPC `red_record_identity_candidates(run jsonb, candidates jsonb)` i én
  transaktion, med rollegate, forventet antal og `input_sha256`/`config_sha256`, der genberegnes eller
  valideres ved skrivning. Idempotent på `(source_id, input_sha256, config_sha256)`: samme input giver
  samme kørsel, ikke en ny.
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
  signaler) og en kollisionsliste: kandidatpersoner, der allerede er `accepted` for en anden persona i
  samme post eller kilde.
- `KildepersonaKo`:
  1. kandidatkort med knappen »Samme som denne« (sender `candidate_id` + `run_id`);
  2. personsøgning (den eksisterende i redaktionen) i stedet for id-feltet;
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

Generatoren køres på de 587 personas fra 2018-20 i en kopi af restoren, uden at se deres afgørelser.
Måles mod de accepterede identiteter:

- andel med rigtig person som kandidat 1 (top-1) og blandt top-3;
- andel uden kandidater;
- præcision pr. tier (hvor ofte kandidat 1 er rigtig, når tier er `auto` hhv. `review`);
- det samme med `evidensNormaliseret`, og separat for personas uden årstal.

Tallene rapporteres uden navne. Der sættes ingen tærskel på forhånd, som gør matcheren »godkendt« —
tallene afgør, hvordan tier må præsenteres (fx om `auto` må stå først i arket), og indgår i 5b's
design.

### 8.2 Blind ende-til-ende-genbekræftelse

Ca. 30 af de 587, stratificeret på tier, sendes gennem hele kæden i genbekræftelsestilstand:
generator → rækkefil → ark (uden det gamle svar) → projektejerens afgørelse og hash → SQL med
negativtest → `red_afgoer_source_persona` → historik. Bagefter sammenlignes med det gamle svar. Det
beviser kæden og giver en menneskeligt målt præcision for kandidaterne. Mindst én sag afgøres også i
webkøen, og de to spor sammenlignes felt for felt (samme struktur, forskellig `basis`).

Genbekræftelsen skriver nye versioner i arbejdsbasen (en kopi), aldrig i restoren og aldrig i prod.

## 9. Test

- **SQL** (CI's friske schema-sti): tabeller og constraints; writer-RPC (rollegate, antal, idempotens,
  hash-validering); de fire udgange; `candidate_id` der ikke hører til personaen; guarden afviser
  historiske autoriteter og manglende basis; eksisterende rækker uændrede; anon/authenticated uden
  adgang til de nye tabeller.
- **Pytest** for arket: alle tokens, `_` stopper, byttede og slettede linjer, ændret rækkefil, forældet
  kørsel, forkert version, note-escaping; delt modul testet én gang og brugt af begge ark.
- **Node/vitest** for generatoren (deterministisk output og hash for fast input, top-K, ingen
  auto-accept) og for webkøens datalag og komponent (kandidatklik, søgning, ny person, kollision,
  historik); Playwright mod lokal base.
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
   Uden navn: ingen kandidater, talt for sig. Kalibreringen (§8.1) køres på de personas, der har
   navn nu (ca. 27), og gentages efter en fuld 2018-20-kørsel og i 5b.
2. **Guard-regel (§4.2).** Kortlægningen viste tre slags ikke-menneskelige skrivninger:
   fortrydelser (`superseded` + `reversed_batch_id`), oprettelse (`red_apply_reimport_person_create`
   binder en persona til den person, den lige har oprettet) og batch-match til eksisterende
   personer (149b-mønstret). Projektejeren valgte: menneskelig basis og fortrydelse tilladt;
   batch-evidens kun når personen er oprettet i samme transaktion; batch-match til eksisterende
   personer lukket.
3. **Rangering (§5).** `matchUdgaver`'s `assignTiers` er injektiv; flere personas kan være samme
   person, så generatoren rangerer selv pr. persona oven på `buildScored`/`scorePair` med samme
   tier-tærskler.
4. **Generatorens form (§5).** Der findes ingen Node-DB-klient i repoet; CLI'en er en ren funktion
   (psql eksporterer JSON, CLI'en rangerer, psql skriver via writer-RPC'en) og kører gennem `tsx`.
5. **Webtest (§9).** Der findes ingen Playwright-fixture for redaktionslogin; webkøen dækkes af
   vitest-komponenttests, og én afgørelse i webkøen mod den lokale base indgår i beviset (§8.2).
