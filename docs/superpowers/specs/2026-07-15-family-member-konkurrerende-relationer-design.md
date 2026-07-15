# Konkurrerende slægtskabspåstande på `family_member` — Design

**Dato:** 2026-07-15
**Status:** Udkast — afventer PDF af anden DAA-udgave + brugergodkendelse før implementering
**Relateret:** `docs/flere-daa-udgaver-roadmap.md` (Problem 2 — dette spec; Problem 3 er forudsætningen),
`docs/superpowers/specs/2026-07-15-tvaers-udgave-identifikation-design.md` (søsterspec: tværudgave-identifikation —
leverer `samme_som`-linket der gør to udgavers `family_member`-rækker sammenlignelige som påstande om samme person),
`docs/superpowers/specs/2026-07-02-redaktionel-samme-som-linking-design.md` (stil-/mønster-skabelon; RPC+trigger-doktrinen),
`docs/superpowers/specs/2026-07-02-samme-som-collapse-design.md` (forbrugeren hvis karantæne-regel dette design gør *løsbar*),
`docs/decisions.md` § "TNG er sammenlignings-reference, ikke facit" (præcedensen der generaliseres).

## 1. Formål

`fact` og generisk `relation` har fuldt evidenslag: rivaliserende kilders udsagn bevares som `assertion`-rækker
(schema.sql:361-371), kildebundet via `citation` (schema.sql:384-392), med præcis ét kanonisk valg pr. slot
håndhævet af `conclusion`s `UNIQUE (target_type, target_id)` (schema.sql:373-382). Mønsteret er bevist i
produktion: TNG-datokonflikterne blev loadet som **konkurrerende assertions på samme fakta med vores konklusion
uændret** (`docs/decisions.md:158-166`).

Selve slægtskabet — forældre/ægtefælle/børn — bor derimod i `family`/`family_member` (schema.sql:315-328), som
**ikke** er koblet til evidenslaget: eneste usikkerhedsbærer er `konfidens`-kolonnen (schema.sql:326), der siger
*hvor sikker* redaktionen er, men ikke *hvem der påstår hvad*. Der er heller intet der forhindrer to modstridende
fædre for samme barn (PK er kun `(family_id, person_id, rolle)`, schema.sql:327). `claude.md`s løfte "Hver trykt
DAA-udgave er en selvstændig `source` — så modstridende udgaver håndteres indfødt" (claude.md:41) er dermed kun
indfriet for `fact`/`relation`, ikke dér hvor forældreskabet faktisk ligger.

Featuren leverer, når udgave 2 påstår en anden far for person X end udgave 1:

- **(a)** et evidens-slot pr. barns fødselsfamilie ("hvem er X's forældrefamilie?") hvor begge udgavers påstande
  ligger side om side, kildebundet — uden at nogen overskrives (invariant 1, claude.md:28);
- **(b)** ét bevidst redaktionelt valg af den kanoniske familie (conclusion-semantik — aldrig "nyeste udgave
  vinder"-automatik);
- **(c)** en projektion hvor `family_member` forbliver den kanoniske graf som al eksisterende collapse-/
  finder-/stamtræskode læser i dag — **nul ændringer i `packages/core`, `web/src/data/model.ts`,
  `mobile/src/data/load.ts`**;
- **(d)** `konfidens` bevaret som redaktionelt overlay ovenpå det valgte — med `omstridt` nu operationaliseret
  (sættes når en rival-påstand foreligger, vises af finderen jf. invariant 7, claude.md:34).

Afhængighed af søsterspec'et: konflikten OPSTÅR først når `red_samme_som` (schema.sql:977-1002) har bekræftet at
udgave 2's person-række og udgave 1's er samme fysiske person — det er dét der gør deres to forældre-familier til
*konkurrerende påstande om samme barn* i stedet for to urelaterede træer. Flowet i §6 starter derfor dér hvor
"Sammenlign udgaver"-flowet slutter.

## 2. Arkitektur: ren ansvarsfordeling

Samme doktrin som samme_som-spec'et §2/Læring 3: DB håndhæver invarianter der beskytter delte data;
klient-lag er rådgivende projektioner.

| Lag | Ansvar | Håndhævelse |
|---|---|---|
| **DB-constraint** (ny: deferrable EXCLUDE på `family_member`, §4.4) | Grafinvariant: højst ÉN fødselsfamilie ('barn'-række) pr. person i den kanoniske graf — lukker roadmap-hullet "to modstridende fædre" for ALLE skrive-veje (RPC/loader/undo/manuel) | **Autoritativ** |
| **DB-RPC** (nye: `red_tilfoej_foraeldre_paastand`, `red_vaelg_foraeldre`; udvidede: `red_tilfoej_barn`, `red_flyt_barn`, guard i `red_upsert_fakta`/`red_opret_fakta`) | Evidens-komplet skrivning af påstande + adjudikation; synkron projektion konklusion→`family_member`; forældre_ukendt-kontradiktions-guard | Autoritativ (transaktionel) |
| **db-verify.sql** | Drift-fangere: slot↔række-konsistens, backfill-komplethed | Maskinel efterkontrol |
| **UI** (web `Redaktion.tsx` + mobile `redaktion/person/[id].tsx`) | Påstands-liste pr. barn, konflikt-arbejdsliste, vælg/afvis gennem eksisterende dry-run/LIVE-flow | Rådgivende |
| **Offentlig visning** | UÆNDRET: læser `family_member` + `konfidens` som i dag; `omstridt` vises via eksisterende konfidens-rendering | Ingen ny kode |

**Nøglebeslutning — `family_member` er den kanoniske projektion, ikke påstands-lageret.** Rivaliserende påstande
lever KUN i evidenslaget (assertions på et slot-fact); `family_member` indeholder til enhver tid præcis den
konkluderede graf. Det er nøjagtig samme arbejdsdeling som `fact`→`person.visning_*` (schema.sql:128-134, invariant
4): påstandene er mange, projektionen er én. Alternativet — at lade udgave 2's alternative far ligge som en ekstra
rå `family_member`-række — ville give barnet dobbelte forældre i stamtræet/finderen og permanent karantænere
collapse-komponenten (`packages/core/src/collapseSameAs.ts:164-171` afviser "konkurrerende forældre (forskellige
ikke-tomme sæt)"), dvs. kræve omskrivning af præcis den collapse-/projektions-kode vi har forpligtet os til ikke
at røre. Én afvigelse fra visning_*-mønsteret: `family_member` er versioneret og redaktionelt skrivbar
(version_pk_registry, schema.sql:1452), så synkroniseringen sker i **RPC-laget** (samme change_set, fortrydbart
samlet), ikke i en cache-trigger — med en db-verify-assert som drift-fanger (ærlig grænse, §10).

## 3. Slot-modellen: fact-slot pr. barn — og hvorfor ikke de to oplagte alternativer

Kernespørgsmålet i (a): hvad er *slottet* konklusionen vælger på? For `fact` er slottet spørgsmålet ("hvornår blev
X født?"), ikke svaret. For forældreskab er spørgsmålet **"hvilken familie er person X barn af?"** — og det
spænder pr. definition over FLERE `family`-rækker. Deraf valget:

**Valgt: ét `fact`-slot pr. barn, `faktatype='forældrefamilie'`, med entitets-værdi-bærende assertions.**
`fact(subjekt_type='person', subjekt_id=<barn>, faktatype='forældrefamilie')` er spørgsmålet; hver udgaves svar er
en `assertion` der peger på den påståede familie via to nye, nullable kolonner `assertion.objekt_type/objekt_id`
(§4.1); `conclusion`s eksisterende `UNIQUE (target_type, target_id)` (schema.sql:381) giver **gratis** præcis den
"ét bevidst valg"-semantik opgaven kræver. `red_set_konklusion`-familien (schema.sql:672-688), `red_tilfoej_oplysning`-
mønsteret (schema.sql:616-639), versionering, RLS-kæden og konflikt-view-mønsteret (`red_konflikt`,
schema.sql:1191-1204) genbruges alle uændret. Præcedens for at et forældre-spørgsmål er et fact: faktatypen
`forældre_ukendt` findes allerede med fuld evidens-kæde og hentes offentligt (web/src/data/model.ts:192-216).

**Fravalgt A — `target_type='family_member'` (roadmap'ens umiddelbare skitse).** Tre strukturelle problemer:
1. `family_member` har ingen surrogat-PK (komposit `(family_id, person_id, rolle)`), og `assertion.target_id` er
   `BIGINT NOT NULL` — det ville kræve en ny id-kolonne, og vigtigere: rækkerne er IKKE stabile identiteter.
   Husets eget korrektions-mønster er DELETE+INSERT (decisions.md:195-198, kirurgisk change_set;
   `red_flyt_barn`, schema.sql:1149-1161) — evidens hæftet på rækken ville forældreløses ved hver flytning.
2. Konflikten spænder over TO rækker i TO familier. Med conclusion pr. række får hver udgaves påstand sit EGET
   conclusion-slot — begge kan stå 'afklaret' samtidig, og intet tvinger det ene bevidste valg. Slottet skal sidde
   på *spørgsmålet* (barnet), ikke på *svarene* (rækkerne).
3. To 'barn'-rækker skal så alligevel sameksistere råt i tabellen indtil afgørelse → collapse-karantæne +
   dobbelt-forældre offentligt (§2) → læser-omskrivning. Netop det vi skal undgå.

**Fravalgt B — atomisér `family` til dyadiske relationer** (`relation` person→person, rolle 'far'/'mor', som ville
passe naturligt i `rel_value`-mønsteret, load_daa.R:159-162). Fravalgt fordi `family` bærer union-semantik der
ikke er dyadisk: `family.type` (vielse/partnerskab), vielses-fakta på familien (`fact.subjekt_type='family'`),
partner-`ordinal` (ægteskabs-sekvens, schema.sql:1044), søskende-`ordinal`, GEDCOM FAM-interop (claude.md:13) —
og HELE læse-siden (buildModel/relationship/collapse, model.ts:106-126, load.ts:131ff, TNG-QA
`derive_our_pc`, R/tng-qa/06-compare.R:8) er bygget over family-unionen. En migrering til dyader er en
totalomskrivning med negativ værdi: unionen er den rigtige model; det er kun *evidensen* der mangler.

**Scope-afgrænsning: kun 'barn'-slottet i v1.** "Forskellige forældre" er et eksklusivt valg (én fødselsfamilie)
og er dét roadmap Problem 2 handler om. Ægtefælle-medlemskab er IKKE eksklusivt (flergifte er legitime — flere
partner-rækker er normaltilstand, ikke konflikt), så et vælg-én-slot er forkert semantik dér; en udgave-uenighed
om en vielse udtrykkes allerede i dag som konkurrerende assertions på familiens vielses-fact plus
`konfidens='omstridt'` på partner-rækken. Adoptions-/sted-/plejebarn-rækker (rolle-subtyper, schema.sql:323-324)
er heller ikke fødselsfamilie-påstande og holdes udenfor slottet. Se §11.

## 4. Datakontrakt (skemaudvidelse — hver kolonne, idempotent migrations-stil)

### 4.1 `assertion.objekt_type` / `assertion.objekt_id` — entitets-værdi på en påstand

```sql
-- Konkurrerende slægtskabspåstande (2026-07-15): en påstands VÆRDI kan være en entitet
-- (her: den påståede forældrefamilie). Polymorf (type,id)-par uden hård FK — husets
-- konvention (schema.sql:13-14). NULL for alle eksisterende, rent tekst-/dato-bårne påstande.
ALTER TABLE assertion ADD COLUMN IF NOT EXISTS objekt_type TEXT;
ALTER TABLE assertion ADD COLUMN IF NOT EXISTS objekt_id   BIGINT;
CREATE INDEX IF NOT EXISTS ix_assertion_objekt ON assertion(objekt_type, objekt_id)
  WHERE objekt_id IS NOT NULL;
```

- **objekt_type** `TEXT` — i v1 altid `'family'` når sat; polymorf så fremtidige entitets-værdi-påstande (fx to
  udgaver uenige om et grennavn — det åbne punkt i lineage-kommentaren, schema.sql:156-162) kan genbruge kolonnen.
- **objekt_id** `BIGINT` — den påståede families id. Bevidst ingen hård FK (polymorf-konventionen); eksistens
  valideres i RPC'en, og `family` kan i praksis ikke slettes (ingen slette-RPC; Codex H1-noten ved
  `red_slet_familie_link`, schema.sql:1076).
- Fravalgt: at kode family-id i `vaerdi_tekst` ('familie 123') — uforespørgselbart, join-fjendtligt, og
  `red_konflikt`-mønsteret (DISTINCT-tælling) ville hvile på strengformatering. Fravalgt: ny tabel
  `family_member_assertion` — invariant 2 (claude.md:29) siger genbrug mekanismer/nye *typer*, ikke nye tabeller;
  en paralleltabel ville duplikere citation/conclusion/RLS/versionering.
- Versionering: `assertion` er allerede i `version_pk_registry` (schema.sql:1455) med `to_jsonb`-snapshots —
  nye kolonner følger automatisk med. RLS: uændret (politikkerne er række-, ikke kolonne-baserede, db-rls.sql:325-333).

### 4.2 Vokabular + slot-fakta

```sql
INSERT INTO vocab (scheme, code, label) VALUES ('faktatype','forældrefamilie','Forældrefamilie (fødselsfamilie)')
  ON CONFLICT (scheme, code) DO NOTHING;
```

Slottet: `fact(subjekt_type='person', subjekt_id=<barn>, faktatype='forældrefamilie')`, **højst ét pr. person**
(find-or-create i RPC'en, som `red_upsert_fakta`, schema.sql:581-588; entydigheden bevogtes desuden af en
db-verify-assert — `red_upsert_fakta`s kendte `LIMIT 1`-nondeterminisme, review-fund 13b, undgås ved at de nye
RPC'er er eneste skrive-vej, §4.5).

Én udgaves påstand = tripel efter husets standardmønster (`fact_value`, load_daa.R:141-144; `red_samme_som`,
schema.sql:992-1000):

1. `assertion(id, target_type='fact', target_id=<slot>, vaerdi_tekst='barn', objekt_type='family', objekt_id=<familie>)`
   — `vaerdi_tekst='barn'` spejler rolle-som-værdi-konventionen fra `rel_value`/`red_samme_som`.
2. `citation(id, assertion_id, source_id=<udgavens source>, side, citat_tekst, kvalitet='primær')` — udgaven ER
   kilden (claude.md:41). Redaktionelle påstande uden trykt kilde: `source_id NULL` + fritekst i `citat_tekst`
   ('(kilde mangler)'-mønsteret, schema.sql:596-599).
3. `conclusion(target_type='fact', target_id=<slot>, valgt_assertion_id, status, blaastemplet_af, blaastemplet_naar)`
   — én pr. slot (UNIQUE, schema.sql:381). `status='afklaret'` når valget er entydigt/truffet; `'omstridt'` når en
   rival-påstand foreligger og valget ikke er genbesøgt (§6).

### 4.3 Konsistens-invariant (slottet ↔ projektionen)

**Invariant P1:** har person X et 'forældrefamilie'-slot med `conclusion.status='afklaret'`, så findes præcis én
`family_member(family_id=<valgt assertions objekt_id>, person_id=X, rolle='barn')`-række, og ingen 'barn'-række i
nogen anden familie. Håndhæves af RPC-laget (§4.5) + EXCLUDE-constrainten (§4.4); efterprøves maskinelt i
db-verify.sql (§10). Bevidst IKKE en trigger: `family_member` er versioneret + har legitime ikke-evidens-skrive-veje
(loadere, `red_slet_person` schema.sql:861, undo-restore), og en konklusions-trigger der muterer en versioneret
tabel ville dobbelt-skrive under `red_fortryd_change_set`-restore (begge tabellers events restaureres allerede
konsistent, fordi RPC'en skrev dem i samme change_set). Samme ærlige enforcement-grænse-argumentation som
ikke_samme_som-kontradiktions-guarden (søsterspec §4).

### 4.4 Grafinvariant: højst én fødselsfamilie pr. person

```sql
-- Fail-closed prætjek: constrainten må ikke kunne tilføjes ovenpå eksisterende dubletter.
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM family_member WHERE rolle='barn'
             GROUP BY person_id HAVING count(*) > 1) THEN
    RAISE EXCEPTION 'family_member: person(er) med >1 fødselsfamilie — afklar manuelt før constraint';
  END IF;
END $$;
ALTER TABLE family_member DROP CONSTRAINT IF EXISTS family_member_en_foedselsfamilie;
ALTER TABLE family_member ADD CONSTRAINT family_member_en_foedselsfamilie
  EXCLUDE USING btree (person_id WITH =) WHERE (rolle = 'barn')
  DEFERRABLE INITIALLY DEFERRED;
```

- **EXCLUDE frem for partielt UNIQUE-indeks** af én præcis grund: `red_flyt_barn` (schema.sql:1149-1161)
  indsætter den nye række FØR den gamle slettes (for at genbruge `red_tilfoej_barn`s cyklus-/partner-guards) —
  et ikke-deferrable unikheds-indeks ville fejle den transaktionelt korrekte flytning midtvejs. `DEFERRABLE
  INITIALLY DEFERRED` tjekker ved commit: flytningen består, to modstridende fædre committes aldrig.
- Rammer kun `rolle='barn'` — adoptions-/sted-/pleje-rækker og partner-rækker er uberørte.
- Dækker ALLE skrive-veje (Læring 3, samme_som-spec §12): loader-append, undo-restore, manuel SQL.
- Prod-forventning: 0 dubletter (spøgelses-union- og multi-union-oprydningerne, decisions.md:168-198, efterlod
  én union pr. barn) — men prætjekket er fail-closed, ikke en antagelse.

### 4.5 RPC'er

**`red_tilfoej_foraeldre_paastand(p_barn_id bigint, p_family_id bigint, p_source_id bigint DEFAULT NULL, p_side text DEFAULT NULL, p_citat text DEFAULT NULL, p_kilde_fritekst text DEFAULT NULL) RETURNS jsonb`**
— "Operation A"-analogen (jf. `red_tilfoej_oplysning`): registrér en kildes påstand UDEN at ændre det kanoniske valg.

1. `current_rolle()='redaktion'`-gate; barn + familie findes; familien har mindst ét medlem med `rolle='partner'`.
2. Idempotens FØR change_set (Codex-2 M1-mønsteret, samme_som-spec §4): findes allerede en assertion på slottet
   med samme `objekt_id` og samme citation-`source_id` → returnér eksisterende id'er, intet change_set.
3. `begin_change_set(...)`; find-or-create slottet; indsæt assertion (m. objekt-kolonner) + citation (§4.2).
4. **Konflikt-detektion:** har slottet en conclusion hvis valgte assertion peger på en ANDEN familie →
   `UPDATE conclusion SET status='omstridt'` (valgt_assertion_id **urørt** — TNG-præcedensens "vores konklusion
   uændret", decisions.md:161-163) + eskalér den eksisterende 'barn'-rækkes `konfidens` til `'omstridt'` (§7).
   Ingen conclusion endnu og påstanden matcher personens eksisterende 'barn'-række → opret conclusion
   `status='afklaret'` (selv-helende korroboration, ingen konflikt).
5. Returnér `{fact_id, assertion_id, citation_id, konflikt boolean}`.

**`red_vaelg_foraeldre(p_assertion_id bigint, p_konfidens text DEFAULT NULL) RETURNS void`** — adjudikationen:
ét bevidst valg + synkron projektion, i ÉT change_set (B7-re-entrans, schema.sql:1145-1147).

1. Gate; assertionen findes, targeter et 'forældrefamilie'-fact og har `objekt_type='family'` (ellers `RAISE`).
2. **Kontradiktions-guard:** har barnet et aktivt `forældre_ukendt`-fact (afklaret conclusion) → `RAISE`
   ("tilbagetræk forældre_ukendt-markeringen først" via `red_tilbagetraek_fakta`, schema.sql:769-783) — at skifte
   mening er to versionerede trin, samme mønster som samme_som-re-root (samme_som-spec §4).
3. `begin_change_set`; upsert conclusion → `valgt_assertion_id=p_assertion_id, status='afklaret'`
   (ON CONFLICT-mønsteret fra `red_set_konklusion`, schema.sql:683-687).
4. **Projektion:** har barnet en 'barn'-række i en anden familie → `PERFORM red_flyt_barn(<gammel>, <valgt>,
   p_barn)` (genbruger cyklus-/partner-guards uændret, schema.sql:1092-1123); ingen 'barn'-række →
   `PERFORM red_tilfoej_barn(<valgt>, p_barn)`. EXCLUDE-constrainten (§4.4) er sidste værn ved commit.
5. `p_konfidens` sat → `PERFORM red_set_familie_konfidens(...)` (schema.sql:1062-1074); ellers: konfidens der
   stod `'omstridt'` pga. konflikten nulstilles IKKE automatisk — redaktøren udtrykker sin tillid eksplicit (§7).

**Guards i eksisterende RPC'er** (tving den evidens-komplette vej — mønsteret fra `red_relation`s
samme_som-afvisning, schema.sql:901):
- `red_upsert_fakta` + `red_opret_fakta` + `red_tilfoej_oplysning` afviser `faktatype='forældrefamilie'` /
  assertions der forsøger at sætte objekt-kolonner ("brug red_tilfoej_foraeldre_paastand / red_vaelg_foraeldre").
- `red_tilfoej_barn` (schema.sql:1092): nyt venligt prætjek "person % har allerede en fødselsfamilie — brug
  red_flyt_barn eller forældre-påstands-flowet" (i stedet for en rå exclusion_violation ved commit).
- `red_flyt_barn` (schema.sql:1149): udvides med intern slot-vedligehold — har barnet et slot med afklaret
  conclusion der peger på fra-familien, tilføjes en redaktionel assertion (objekt=til-familien, citation
  '(kilde mangler)'/fritekst) og conclusion re-pegges — så en direkte strukturel flytning ikke driver slottet
  (invariant P1). Barn uden slot: uændret adfærd (grandfather-reglen, §5).

**ID-allokering:** arvet `max(id)+1`-konvention med de kendte codebase-brede race-forbehold — accepteret som i
samme_som-spec §3 (single-writer-PoC); ingen ny race-frihed påstås.

### 4.6 Konflikt-view til dashboardet

`red_konflikt` (schema.sql:1191-1204) tæller DISTINCT `vaerdi_tekst` og kan ikke genbruges direkte (slot-assertions
bærer værdien i `objekt_id`). Nyt søster-view, samme `security_invoker`-disciplin:

```sql
CREATE OR REPLACE VIEW red_foraeldre_konflikt WITH (security_invoker = true) AS
SELECT f.subjekt_id AS person_id, f.id AS fact_id,
       count(DISTINCT a.objekt_id) AS antal_familier,
       count(*)                    AS antal_paastande,
       max(c.status)               AS status
FROM fact f
JOIN assertion a ON a.target_type='fact' AND a.target_id=f.id AND a.objekt_type='family'
LEFT JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id
WHERE f.subjekt_type='person' AND f.faktatype='forældrefamilie'
GROUP BY f.subjekt_id, f.id
HAVING count(DISTINCT a.objekt_id) > 1;
```

## 5. Migrationsvej for eksisterende data (b): backfill — udgave 1's påstande gøres eksplicitte

**Valgt: fuld bagudkonvertering** af de eksisterende 'barn'-rækker (~850-900 rækker for de ~922-960 personer;
tælles ved kørsel) til slot+assertion+citation+conclusion — frem for sameksistens af "gamle rækker uden evidens,
nye med".

Begrundelse:
- Rækkerne HAR en kendt, entydig kilde: DAA 2018-20-loadet (`load_daa.R:155-157` skrev dem; udgaven er allerede
  `source`-rækken alle personens øvrige facts citerer). Backfillen opfinder ingen viden — den nedskriver
  eksplicit hvad der i dag er implicit. Det er præcis claude.md:41-løftet, indfriet med tilbagevirkende kraft.
- Sameksistens ville kræve en permanent to-regime-regel i alle forbrugere ("har slot" vs. "har ikke"), og
  konflikt-flowet (§6) forudsætter at udgave 1's påstand FINDES som assertion at konkurrere imod — ellers skulle
  den alligevel oprettes lazily midt i konflikten, med samme indhold som backfillen, bare senere og pr. håndkraft.
- Going-forward-invarianten bliver dermed ren: **enhver 'barn'-række har et evidens-spor** (db-verify-assert).

Idempotent, set-baseret migration (db-migrations.sql-stil), fail-closed kilde-opslag — IKKE hårdkodet `id=1`
(læringen fra `(linje,nr)`-kollisionsbuggen, søsterspec §7 / docs/reviews/24-datamodel-helhedsreview.md:145):

```sql
DO $$
DECLARE v_src bigint;
BEGIN
  SELECT id INTO STRICT v_src FROM source WHERE udgave = 'DAA 2018-20';  -- STRICT: 0 el. 2+ → abort
  -- 1) slots for barn-rækker uden slot (WHERE NOT EXISTS → idempotent)
  -- 2) én assertion pr. slot: vaerdi_tekst='barn', objekt_type='family', objekt_id=rækkens family_id
  -- 3) citation: source_id=v_src, kvalitet='primær',
  --    citat_tekst='(bagudkonverteret: slægtskab loadet fra DAA 2018-20 uden per-række-citat)'
  -- 4) conclusion: valgt=assertionen, status='afklaret',
  --    blaastemplet_af='DAA 2018-20 (backfill af forældre-evidens)', blaastemplet_naar=current_date
  -- id'er: (SELECT coalesce(max(id),0) FROM <tabel>) + row_number() OVER (ORDER BY person_id)
END $$;
```

- **Ærlighed i citatet:** `citat_tekst` siger eksplicit at rækken er bagudkonverteret — den foregiver ikke et
  ordret kildeuddrag (citation.citat_tekst-semantikken, schema.sql:389). `side` sættes NULL (per-række-sidetal
  blev ikke bevaret ved load; narrativen bærer siderne).
- **Uden change_set** (som andre load-/backfill-scripts — fx slaegtled-backfill): dette er data-komplettering af
  et load, ikke en redaktionel handling; migrationen er idempotent og dokumenteret i changelog i stedet.
- Partner-rækker backfylles IKKE (uden for slot-scope, §3). Konfidens-kolonnen røres ikke.
- Loader-krav fremadrettet: `load_daa.R`s `add_member` (linje 155-157) og `load_presens.R:85` ledsager hver
  'barn'-række med slot-triplen (ny `member_evidence()`-helper ved siden af `fact_value`) — så udgave 2 lander
  born-evidens-komplet og aldrig genintroducerer to-regime-tilstanden.

## 6. Konklusions-logik ved konflikt (c): redaktionelt valg, aldrig automatik

**Automatisk "nyeste udgave vinder" er fravalgt.** Begrundelsen er empirisk, ikke æstetisk: i det eneste
produktions-afprøvede konflikt-tilfælde (TNG vs. DAA) var den *eksisterende* konklusion korrekt i 5 af 5
(decisions.md:160-166) — og DAA-redaktioner retter både frem OG tilbage (en ældre udgave kan have ret).
`conclusion` er pr. design "den blåstemplede vurdering" (schema.sql:373) — et bevidst valg med proveniens
(`blaastemplet_af`), ikke en sorteringsregel. Automatik ville også gøre load-rækkefølgen semantikbærende.

**Flowet når udgave 2 er loadet og matchet** (fortsætter søsterspec'ets §5-flow):

1. Udgave 2 loades selvstændigt: egne person-/family-/family_member-rækker + (pr. §5-loader-kravet) egne slots.
   Ingen konflikt endnu — to disjunkte træer. EXCLUDE-constrainten rammes ikke (forskellige person_id'er).
2. Redaktøren bekræfter identitet via "Sammenlign udgaver" → `red_samme_som`. Collapse opdager nu evt.
   "konkurrerende forældre" og **karantænerer** komponenten (collapseSameAs.ts:164-171) — korrekt fail-safe:
   offentligheden ser to ufoldede personer, aldrig et gæt.
3. Karantænen er arbejdslisten: redaktions-UI'et viser komponenten under "Forældre-konflikter" (collapse-outputtets
   `quarantined` + `red_foraeldre_konflikt`-viewet). For hver konflikt:
   a. `red_tilfoej_foraeldre_paastand(kanonisk_barn, udgave2_familie, source=udgave2, side, citat)` — udgave 2's
      påstand registreres på det KANONISKE barns slot (append-only; udgave 2-personens eget slot står urørt —
      invariant 1, ingen re-targeting af uforanderlige assertions). Konklusionen bliver `status='omstridt'`,
      rækkens konfidens `'omstridt'` — offentligheden ser nu ærlig usikkerhed, ingen strukturel ændring.
   b. Redaktøren adjudikerer mod kilderne: `red_vaelg_foraeldre(<vindende assertion>, p_konfidens)`. Vinder
      udgave 2, flytter projektionen barnet (`red_flyt_barn`-genbrug); vinder udgave 1, står grafen som før —
      i begge tilfælde er BEGGE påstande bevaret, kildebundet, og `blaastemplet_af` bærer proveniensen.
   c. Udgave 2-personens overflødige rå 'barn'-række fjernes med eksisterende `red_slet_familie_link`
      (schema.sql:1079-1085) — *påstanden* er nu bevaret som assertion, rækken var kun dens rå skygge; sletningen
      er versioneret (change_set) og genopretbar. Derefter ser collapse ikke længere konkurrerende forældre →
      komponenten folder. UI'et fører redaktøren gennem a-c som ét dry-run/preview-flow.
4. Er udgaverne ENIGE (langt de fleste), er der ingen karantæne; en korroborations-påstand (trin a uden konflikt,
   selv-helende afklaret-gren i §4.5 pkt. 4) kan tilføjes fra samme UI, men kræves ikke.

**Visning af "der findes en konkurrerende påstand":**
- **Redaktør:** person-editorens familie-sektion (web `Redaktion.tsx`, mobile `redaktion/person/[id].tsx:325ff`)
  viser pr. barn slottets påstands-liste som fakta-kortenes oplysnings-liste: kilde-badge (udgave), side/citat,
  valgt-markering, "vælg denne"-knap; plus dashboard-listen fra `red_foraeldre_konflikt`.
- **Offentligt:** INGEN ny UI i v1. `konfidens='omstridt'` flyder allerede gennem `parentChild.konfidens`
  (model.ts:122-125 / types.ts:58-66) til stamtræ og slægtskabsfinder (svageste-led-flagning,
  relationship.ts:200-240) — invariant 7's "vis usikkerhed" er dækket af eksisterende rendering, uden at en
  ikke-redaktør druknes i evidens-detaljer. Kilde-detaljevisning offentligt er en bevidst udskydelse (§11).

## 7. Forholdet til `konfidens` (d): bevaret, som redaktionelt overlay — nu med skarp semantik

**`konfidens` udgår IKKE og erstattes IKKE.** De to lag svarer på forskellige spørgsmål og er komplementære:

| | Spørgsmål | Bæres af | Ejer |
|---|---|---|---|
| Evidenslaget | *Hvem påstår hvad, med hvilken kilde?* | assertion+citation på slottet | Kilderne (append-only) |
| `conclusion` | *Hvilken påstand gælder kanonisk?* | conclusion (én pr. slot) | Redaktionen (ét valg) |
| `konfidens` | *Hvor meget stoler redaktionen på det valgte?* | family_member-rækken | Redaktionen (overlay) |

`konfidens` er altså redaktørens tillid til den VALGTE konklusion — ikke et substitut for kildesporing (det var
den utilsigtede dobbeltrolle den har båret indtil nu, jf. kolonne-kommentaren schema.sql:326 der lovede et
evidenslag som aldrig blev koblet på). En 'formodet' med én kilde og en 'sikker' med tre kilder er begge
udtrykkelige nu. Konkret kobling, minimal og énvejs:

- **Auto-eskalering, aldrig auto-beroligelse:** `red_tilfoej_foraeldre_paastand` sætter konfidens →
  `'omstridt'` når en rival registreres (at skjule en kendt konflikt ville bryde invariant 7). Den modsatte vej
  er ALTID manuel: `red_vaelg_foraeldre` nulstiller ikke konfidens medmindre `p_konfidens` gives — redaktøren
  skal aktivt erklære sin tillid efter en adjudikation. Versioneret (change_set) i begge retninger.
- `red_set_familie_konfidens` (schema.sql:1062-1074) består uændret som direkte overlay-sætter.
- `packages/core`-typen `Konfidens`/`KONFIDENS_RANK` (types.ts:64-73), collapse-dedup'ens stærkeste-vinder
  (collapseSameAs.ts:307-316) og finderens svageste-led (relationship.ts:240) er alle uberørte.

## 8. App-lag (web + mobile spejlet)

- **`redaktionWrite.ts`** (begge): tre nye Change-arter gennem eksisterende `planCall`/`submitChange`
  dry-run/LIVE-flow:
  - `foraeldrePaastand {barnId, familyId, sourceId?, side?, citat?, kildeFritekst?}` → `red_tilfoej_foraeldre_paastand`
  - `vaelgForaeldre {assertionId, konfidens?}` → `red_vaelg_foraeldre`
  - (genbrug) `sletFamilieLink` findes allerede → trin 3c.
- **`redaktionRead.ts`** (begge, i dag family_member-fetch på web/src/data/redaktionRead.ts:362-368 /
  mobile/src/data/redaktionRead.ts:353-359): udvid person-familie-hentningen med slottet — fact('forældrefamilie')
  + assertions (inkl. objekt_id + familie-label) + citations (source→udgave-badge) + conclusion; plus
  `red_foraeldre_konflikt`-listen til dashboardet.
- **UI:** familie-sektionen i person-editoren får et "Forældre-påstande"-panel pr. barn-relation (påstands-liste,
  vælg-knap, konflikt-banner når status='omstridt'); redaktions-dashboardet får "Forældre-konflikter"-kort
  (view + karantæne-komponenter). Konflikt-flowet (§6 trin a-c) præsenteres som guidet preview-ark.
- **Offentlig web/mobile: nul ændringer** (model.ts/load.ts/selectors læser samme kolonner som i dag).
- **Loadere:** `member_evidence()`-helper i load_daa.R/load_presens.R (§5); `daa-extract`/`daa-presens`-SKILL.md
  opdateres med kravet.

## 9. RLS / GDPR

- **Ingen nye tabeller → ingen nye politikker.** Slottet er et `fact` på en person og arver den eksisterende
  target-gatede evidens-kæde (db-rls.sql:320-347: assertion/conclusion gates på deres fact→person, citation på
  sin assertion). Præcedens for at netop denne kæde allerede læses offentligt: `forældre_ukendt`-fetchen
  (model.ts:192-216). En rival-påstand om en OFFENTLIG (afdød, ikke-privat) person er offentligt læsbar evidens —
  det er tilsigtet (åben kildesporing for afdøde, claude.md:35).
- **Levende personer:** slots for præsensliste-børn (levende=TRUE) skjules af de eksisterende person-gates i
  samme politikker — ingen ny eksponeringsklasse. `assertion.objekt_id` peger på en `family`, hvis medlemmer
  allerede RLS-gates individuelt (family_member-politikken, db-rls.sql:276-279); at en skjult persons *familie-id*
  kan optræde i en offentlig assertion lækker intet personhenførbart (family-rækken bærer kun `type`) —
  verificeres eksplicit i §10.
- Nye RPC'er: `SECURITY DEFINER` + `current_rolle()='redaktion'`-gated som alle `red_*`. `red_suggest`-vejen for
  medlemmer er uændret (forslag, ikke direkte skrivning).

## 10. Test

**DB (`db-verify.sql`-asserts mod lokal prod-kopi):**
- Backfill-komplethed: ingen `family_member`-række med `rolle='barn'` uden 'forældrefamilie'-slot med afklaret/
  omstridt conclusion; præcis ét slot pr. person; hver slot-assertion har `objekt_type='family'` + eksisterende familie.
- **Invariant P1-driftfanger:** for hvert afklaret slot matcher valgt assertions `objekt_id` personens faktiske
  'barn'-rækkes `family_id` (og omstridt slot ⇒ rækkens konfidens='omstridt').
- EXCLUDE-constraint: to 'barn'-rækker for samme person afvises (også via rå INSERT); `red_flyt_barn`s
  insert-før-delete består (deferred); undo-restore af en flytning består.
- `red_tilfoej_foraeldre_paastand`: evidens-tripel komplet; idempotens (samme familie+kilde → samme id'er, intet
  nyt change_set); konflikt-gren sætter status='omstridt' + konfidens-eskalering, valgt_assertion_id urørt;
  korroborations-gren opretter afklaret conclusion; ikke-redaktion afvist.
- `red_vaelg_foraeldre`: re-peg + flyt i ÉT change_set (fortryd genopretter BÅDE conclusion og række);
  forældre_ukendt-kontradiktion RAISEr; vælg-eksisterende (udgave 1 vinder) flytter intet; cyklus-guard nedarves
  (vælg en familie hvor barnet er ane til en partner → RAISE fra red_tilfoej_barn).
- Guards: `red_upsert_fakta`/`red_opret_fakta`/`red_tilfoej_oplysning` afviser 'forældrefamilie';
  `red_tilfoej_barn` giver venlig fejl ved eksisterende fødselsfamilie.
- Migration: STRICT-kildeopslag aborterer ved 0/2+ 'DAA 2018-20'-kandidater; gen-kørsel er no-op (idempotens).
- RLS: anon ser slot-kæden for offentlig person; anon ser INTET af kæden for levende/privat person (subjekt-gaten).

**Core (`packages/core/src/__tests__/`) — regressioner, ingen nye features:**
- collapse-fixture: komponent med konkurrerende forældre karantæneres (eksisterende adfærd); efter §6-oprydning
  (rival-række fjernet) folder samme fixture — dokumenterer at flowet er collapse-kompatibelt uden core-ændringer.
- Konfidens-flow uændret: parentChild med 'omstridt' flager stien (relationship-testene består urørt).

**App (web + mobile spejlet):**
- Change-arter → korrekt fn+args, dry-run vs LIVE; påstands-panelet viser kilde-badges/valgt-markering;
  konflikt-flowets tre trin producerer de forventede RPC-kald i rækkefølge; dashboard-listen mapper viewet.
- Offentlige read-sites: snapshot-test at model.ts/load.ts-queries er uændrede (blast-radius-vagt).

## 11. YAGNI / bevidste fravalg

- **Ingen automatisk konfliktafgørelse** ("nyeste udgave vinder" / højeste kildeantal) — conclusion er et bevidst
  valg; TNG-præcedensen viste automatik-antagelsen forkert i 5/5 (§6).
- **Intet partner-/vielses-slot** — ægtefælle-medlemskab er ikke eksklusivt; udgave-uenighed om en vielse dækkes
  af eksisterende vielses-fact-assertions + konfidens (§3). Genovervej hvis en konkret udgave-konflikt om *samme*
  ægteskabs identitet opstår.
- **Ingen atomisering af `family`** til dyadiske far/mor-relationer — unionen er den rigtige model; kun evidensen
  manglede (§3, fravalg B).
- **Ingen `family`-level samme_som/dedup** — udgave 2's duplikat-familier for ENIGE forældrepar konsolideres
  redaktionelt via barn-flyt + `red_slet_familie_link`; en identitetsmekanisme for familier venter på empirisk behov.
- **Ingen trigger-vedligeholdt family_member-projektion** — RPC-synk + db-verify-driftfanger; trigger ville
  kollidere med at tabellen selv er versioneret og loader-skrevet (§4.3, ærlig grænse).
- **Ingen hård FK på `assertion.objekt_id`** — polymorf-konventionen (schema.sql:13-14); eksistens tjekkes i RPC.
- **Ingen offentlig evidens-/kilde-UI for forældre-links i v1** — 'omstridt'-konfidens vises allerede; kildekort
  offentligt er et separat visnings-projekt (§6).
- **Ingen backfill af partner-rækker** — uden slot-semantik ville det være evidens-teater (§5).
- **Ingen as-of/udgave-snapshot-forespørgsler** (roadmap Problem 1) — dette design EFTERLADER dataene
  snapshot-bare (hver påstand er source-bundet via citation), men diffing/visning specificeres separat.
- **Ingen sequence-migration af `max(id)+1`** — arvet, accepteret begrænsning (samme_som-spec §3); backfillen
  kører set-baseret i én transaktion.

## 12. Berørte filer (forventet)

- `schema.sql` + `db-migrations.sql` — `assertion.objekt_type/objekt_id` + indeks; vocab-række; EXCLUDE-constraint
  m. fail-closed prætjek; backfill-blok (STRICT-kildeopslag); `red_tilfoej_foraeldre_paastand` +
  `red_vaelg_foraeldre`; guards i `red_upsert_fakta`/`red_opret_fakta`/`red_tilfoej_oplysning`/`red_tilfoej_barn`;
  slot-vedligehold i `red_flyt_barn`; view `red_foraeldre_konflikt`. Alt idempotent.
- `db-verify.sql` — asserts (§10), især P1-driftfangeren og backfill-kompletheden.
- `db-rls.sql` — ingen ændringer forventet (verificeres; §9).
- `.claude/skills/daa-extract/scripts/load_daa.R` + `.claude/skills/daa-presens/scripts/load_presens.R` —
  `member_evidence()`-helper: slot-tripel pr. 'barn'-række; SKILL.md-krav opdateret.
- `web/src/data/redaktionWrite.ts` + `mobile/src/data/redaktionWrite.ts` — Change-arter `foraeldrePaastand`/`vaelgForaeldre`.
- `web/src/data/redaktionRead.ts` + `mobile/src/data/redaktionRead.ts` — slot+påstands-fetch, konflikt-liste.
- `web/src/Redaktion.tsx` + `mobile/src/app/redaktion/person/[id].tsx` — påstands-panel + konflikt-flow;
  dashboard-kort.
- `packages/core/` — **ingen kildeændringer**; kun regressions-fixtures i `__tests__/` (§10).
- `web/src/data/model.ts`, `mobile/src/data/load.ts`, `mobile/src/data/selectors.ts` — **uændrede** (blast-radius-vagt-test).
- Tests: `web/src/data/__tests__/`, `mobile/src/data/__tests__/`.
- Efter godkendelse: notat i `docs/decisions.md` + status-opdatering i `docs/flere-daa-udgaver-roadmap.md`
  (Problem 2 → specificeret).
