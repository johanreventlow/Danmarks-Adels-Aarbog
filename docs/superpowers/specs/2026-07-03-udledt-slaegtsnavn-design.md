# Design: Udledt slægtsnavn på fødte medlemmer

**Dato:** 2026-07-03
**Status:** Godkendt (afventer implementeringsplan)
**Reviewet:** Advisor + Codex ×3 passes (Pass 1 prosa-design §5 · Pass 2 færdig spec §5.1 ·
Pass 3 verifikation af hærdningerne §5.2) — alle reconciles foldet ind nedenfor.

---

## 1. Problem & motivation

Næsten alle *fødte* medlemmer af Reventlow-slægten er i Dansk Adels Aarbog anført **uden
efternavn** (kun "Conrad", "Conrad Detlef", ...). Så længe basen kun rummer Reventlow er
det uproblematisk, men når andre slægter senere indlæses bliver kun-fornavne forvirrende:
man kan ikke skelne slægter, sortere/gruppere på efternavn, eller eksportere meningsfuldt
til GEDCOM.

**Ønske:** udled og vis et efternavn ("Reventlow") for fødte medlemmer der mangler det —
men **ikke** for dem der allerede har det, og **ikke** for indgiftede ægtefæller med andet
slægtsnavn. Efternavnet varierer per gren for andre slægter (Ahlefeldt →
Ahlefeldt-Laurvig → Ahlefeldt-Laurvig-Lehn).

**Kerneindsigt:** efternavnet er ikke *manglende data* — det er *en afledning der ikke er
lavet endnu*. Bogens påstand ("Conrad") er en uforanderlig, kildebunden påstand og må aldrig
overskrives (invariant 1). Efternavnet udledes af slægts-medlemskab og komponeres ind i
cache-laget (invariant 4: `visning_*` er en envejs-projektion, redigeres aldrig direkte).

---

## 2. Empirisk grundlag (verificeret mod prod-basen 2026-07-03)

| Fakta | Værdi |
|---|---|
| Personer i alt | 923 |
| Har `person_external_id` (født ind i slægten, har bog-(linje,nr)) | 591 |
| Mangler `external_id` (≈ indgiftede ægtefæller) | 332 |
| `lineage`-rækker (kode I–V) | 5, `parent_lineage_id` alle NULL (ingen forgrening endnu) |
| `lineage.navn` | **deskriptivt** ("Den holstenske linje") — IKKE et efternavn |
| Fødte medlemmer uden "Reventlow" i `visning_navn` | 580 |
| Fødte medlemmer der allerede har "Reventlow" (partikel-form "von/de Reventlow") | 11 |
| Personer med flere `external_id` / flere distinkte linjer | **0** (medlemskab entydigt) |

De 11 der allerede har "Reventlow": alle den ældre partikel-form (Gottschalk I-1/I-29/II-1,
Detlef III-1, Iwan I-16, Johann I-24, Lüder I-57, Nicolaus I-17/I-43, Conrad III-58 & V-1).
Ingen "Reventlow-Criminil". Skal blot springes over (behold "von/de Reventlow" trofast).

**KRITISK forbrugerfund:** `R/tng-qa/04-match.R:95` antager `visning_navn` er **kun fornavne**
og tilføjer selv implicit "Reventlow" via `normalize_name(p$visning_navn, last="",
married_in=FALSE)`. → Overload af `visning_navn` ville give match-nøgle "conrad reventlow
reventlow" = stille brud på TNG-QA. `visning_navn` skal derfor forblive rå.

---

## 3. Invarianter respekteret

- **1 (påstande uforanderlige):** bogens navn-`assertion` ("Conrad") urørt. Ingen syntetisk
  påstand fabrikeres.
- **4 (cache = envejs-projektion):** efternavnet skrives kun til `visning_*`-felter, regenereret
  fra konklusioner + linje-medlemskab; redigeres aldrig direkte.
- **9 (kontrolleret vokabular):** slægtsnavnet hænger på `lineage` (kontrolleret entitet), ikke
  fri tekst per person.

---

## 4. Design

### 4.1 Efternavns-kilde → `lineage.slaegtsnavn`

Ny nullable kolonne:

```sql
ALTER TABLE lineage ADD COLUMN IF NOT EXISTS slaegtsnavn TEXT;
```

- Reventlow: `slaegtsnavn = 'Reventlow'` på alle 5 linjer.
- En persons **effektive efternavn** = `slaegtsnavn` for deres mest-specifikke linje; er den
  NULL, gå op ad `parent_lineage_id` til første ikke-NULL. → Ahlefeldt-Laurvig-Lehn-grenen
  bærer sit eget; roden bærer "Ahlefeldt". Ingen ny tabel — rider på eksisterende
  `parent_lineage_id`-forgrening.

### 4.2 Medlemskabs-signal → `person_external_id`

- "Født ind i slægten" = personen har mindst én `person_external_id`-række.
- Linjen findes via `external_id.linje` → `lineage.kode` (join på `(source_id, kode)`).
- Indgiftede ægtefæller har ingen `external_id` → får **aldrig** efternavn påført (beholder
  deres eget slægtsnavn).
- Medlemskab er entydigt i nuværende data (0 personer med flere linjer). Flere-medlemskab
  (forgrening/kryds-slægt) håndteres som **fremtids-regel** — se §6.

### 4.3 Vagt-regel (hvornår påføres efternavn)

Mekanisk regel, bekræftet med bruger:

> Et født medlem får den effektive families-efternavn føjet til sidst, **medmindre navnet
> allerede indeholder families-efternavnet** (normaliseret token-match, ikke rå substring).

- "Conrad" → "Conrad Reventlow"
- "Conrad Detlef" (flere fornavne) → "Conrad Detlef Reventlow"
- "Alexander Rudolph Iuel" (Iuel = mellemnavn) → "Alexander Rudolph Iuel Reventlow"
- "Sybille Vega Raben" → "Sybille Vega Raben Reventlow"
- "Detlef von Reventlow" (indeholder allerede "Reventlow") → **uændret**, `visning_efternavn = NULL`

**Bekræftet af bruger:** der er ingen fødte Reventlow-medlemmer hvor det ville være forkert at
sætte "Reventlow" til sidst. (Reventlow-Criminil er en separat slægt/gren der kommer ved en
senere import og bliver sin egen `lineage` — ikke i scope.)

Dette opløser Codex' BLOCKER-1-fare ("Conrad Hansen" → "Conrad Hansen Reventlow"): for et
**født** medlem *er* et sådant navn korrekt (mellemnavn + families-efternavn). Faren gjaldt kun
hvis reglen ramte ikke-medlemmer — hvilket `external_id`-gaten forhindrer.

### 4.4 Kompositions-mål → 3 felter (Model B)

Ny skema (to nye kolonner; `visning_navn` uændret):

```sql
ALTER TABLE person ADD COLUMN IF NOT EXISTS visning_efternavn  TEXT;  -- afledt slægtsnavn; NULL = ikke afledt
ALTER TABLE person ADD COLUMN IF NOT EXISTS visning_fuldt_navn TEXT;  -- komposition til visning/søgning/eksport
```

**OBLIGATORISK — versioning skip-liste (Codex Pass 2, punkt 6):** begge nye kolonner er
cache/envejs-projektion og **skal** tilføjes `version_pk_registry`-skip-listen for `person`
(schema.sql:1023 + db-migrations.sql), præcis som de eksisterende `visning_*`. Ellers logger
`log_change`-triggeren backfill'en som ~580 autoritative `change_event`-rækker. `db-verify.sql`
har allerede en assert for `visning_navn`-eksklusion (linje ~314) — udvid den til de to nye.

Eksempel (Alexander Rudolph Iuel):

| Felt | Værdi | Kommentar |
|---|---|---|
| `visning_navn` | `Alexander Rudolph Iuel` | rå, uændret — **TNG-QA læser fortsat denne** |
| `visning_efternavn` | `Reventlow` | KUN det afledte efternavn; NULL for indgiftede + de 11 |
| `visning_fuldt_navn` | `Alexander Rudolph Iuel Reventlow` | `visning_navn (+ ' ' + visning_efternavn)` |

**Hvorfor 3 felter (ikke ét komponeret):**
1. **GEDCOM `SURN`:** eksport kræver efternavnet separat markeret (`1 NAME ... /Reventlow/`).
   `SURN = visning_efternavn` for de ~562 afledte. **Kendt afgrænsning (Codex Pass 2):** de 11
   bog-native "von/de Reventlow" har bevidst `visning_efternavn = NULL`, så deres `SURN` er IKKE
   dækket af feltet. GEDCOM-eksporten (fremtid, udskudt) skal for netop denne bundne mængde læse
   efternavnet fra sidste token i `visning_navn` — de bærer alligevel en partikel-form ("von/de")
   der kræver særlig GEDCOM-håndtering. Overclaim "SURN = visning_efternavn dækker alle" er
   rettet: det dækker de afledte, ikke de bog-native.
2. **Proveniens/gennemsigtighed:** `visning_efternavn` er sat præcis når efternavnet er afledt →
   redaktør-UI kan vise badge "efternavn afledt af linje". (Codex punkt 10.)
3. **Søgning/sortering på efternavn på tværs af slægter** — feature'ens motivation — kræver
   efternavnet isoleret.

### 4.5 Regenerering (udvidet `regen_person_visning`)

`regen_person_visning(pid)` udvides til også at sætte `visning_efternavn` + `visning_fuldt_navn`:

1. Beregn `visning_navn` som i dag (valgt navn-konklusion).
2. Slå personens effektive families-efternavn op (§4.1 + §4.2) via join til `lineage`.
   Efternavns-opslaget SKAL være entydigt: `SELECT DISTINCT`-efternavn over personens
   linje-medlemskaber; hvis der findes **mere end ét distinkt** effektivt efternavn
   (`COUNT(DISTINCT slaegtsnavn) > 1`) → behandl som tvetydigt (se vagt nedenfor).
3. Sæt felterne efter denne prioritet:
   - `visning_navn IS NULL` (navnløst medlem) → `visning_efternavn = NULL`,
     `visning_fuldt_navn = NULL`. (Undgår `NULL || ' ' || 'Reventlow'` = NULL-inkonsistens og
     et bart " Reventlow".)
   - **Tvetydigt** efternavn (flere distinkte, jf. trin 2) → `visning_efternavn = NULL`,
     `visning_fuldt_navn = visning_navn`, og **log** til karantæne/review. Aldrig vilkårligt valg.
   - Personen har linje-medlemskab, entydigt efternavn, og `visning_navn` indeholder **ikke**
     efternavnet (normaliseret, §4.6) → `visning_efternavn = <effektivt efternavn>`,
     `visning_fuldt_navn = visning_navn || ' ' || visning_efternavn`.
   - Ellers (indgift / allerede-har / intet medlemskab) → `visning_efternavn = NULL`,
     `visning_fuldt_navn = visning_navn`.

Joiner `lineage` ved regen-tid (ingen denormaliseret efternavns-kopi på person).

**Fan-out-vagt (Codex Pass 2, punkt 1+2 — CONFIRMED):** join'et `person → person_external_id →
lineage` kan i fremtiden fane ud (person med `external_id` fra flere sources/linjer). Den
eksisterende `max(vaerdi_tekst)`-aggregering over navn-fakta bliver da flerrækket. Derfor: hent
efternavnet i en **CTE/derived table med præcis én række per `person_id`** (Codex Pass 3 —
"separat subquery" alene garanterer ikke non-fan-out). Konkret struktur:

```sql
efternavn_cte AS (
  SELECT pei.person_id,
         count(DISTINCT l.slaegtsnavn)         AS n_distinct,
         min(l.slaegtsnavn)                     AS slaegtsnavn   -- kun meningsfuldt når n_distinct = 1
  FROM person_external_id pei
  JOIN lineage l ON l.source_id = pei.source_id AND l.kode = pei.linje
  -- (effektivt efternavn = walk op ad parent_lineage_id ved NULL, §4.2/§4.7)
  GROUP BY pei.person_id
)
```

Denne CTE joines **skalart** (én-til-én på `person_id`) EFTER navn-aggregeringen — aldrig i
samme `JOIN` som `max(vaerdi_tekst)`, så navn-aggregeringen ikke fanes ud. Påfør kun når
`n_distinct = 1`; ellers tvetydig-karantæne (trin 3). Dette er den minimale del af §6's
primær-medlemskab der SKAL med nu (0 multi-medlemskaber i dag, men regen-recepten må ikke
korrumperes stille når data vokser). Fuld primær-medlemskabs-regel forbliver §6.

### 4.6 Normalisering (til vagt-sammenligning)

Præcis algoritme (Codex Pass 2, punkt 3 — recalibreret til entydighed):

**Normalisering** af både navn og families-efternavn:
- Unicode NFC + case-fold (locale da_DK).
- Whitespace-kollaps; bindestreg-varianter (U+2010/U+2011/U+2013 → U+002D).
- **Diakritik bevares** (jf. `R/tng-qa/03-normalize.R` "Diakritik bevares ALTID").
- **Bindestreg splitter IKKE** — et efternavn er ét token med bindestreger bevaret internt
  ("ahlefeldt-laurvig-lehn" = ét token).

**Match-regel — suffiks-token-sekvens (Codex Pass 3, punkt 3 — recalibreret):** split BÅDE
navnet og families-efternavnet på **whitespace** til token-sekvenser (bindestreg bevaret internt
i hvert token). Skip påføring hvis **navnets afsluttende token-sekvens er lig efternavnets
token-sekvens**. Suffiks-sammenligning (ikke "mindst ét token") fordi:
- den håndterer **fler-ords-efternavne** ("von Brockdorff", "von der Osten" = 2–3 tokens) — som
  en enkelt-token-regel aldrig kunne matche;
- den undgår **falsk skip** når efternavnet blot optræder som et *fornavn* midt i navnet
  (kun match i slutningen tæller som "har allerede efternavnet").

Verificerede konsekvenser:
- `"Detlef von Reventlow"` mod `reventlow` → afsluttende 1-token-sekvens `[reventlow]` ==
  `[reventlow]` → **skip** (partikelen "von" kræver ingen særlig logik).
- `"X Ahlefeldt"` mod gren `ahlefeldt-laurvig-lehn` (1 token m. bindestreg) → afsluttende token
  `[ahlefeldt]` ≠ `[ahlefeldt-laurvig-lehn]` → **påfør** korrekt.
- `"X Ahlefeldt"` mod rod `ahlefeldt` → `[ahlefeldt]` == `[ahlefeldt]` → **skip**.
- `"Anna Reventlow Hansen"` mod `reventlow` → afsluttende `[hansen]` ≠ `[reventlow]` → **påfør**
  (Reventlow optræder som mellemnavn, ikke som efternavn — korrekt, ingen falsk skip).
- `"X von Brockdorff"` mod `von brockdorff` → afsluttende `[von, brockdorff]` == `[von,
  brockdorff]` → **skip** (fler-ords-efternavn nu dækket).

Den mere-specifikke gren-variant-adfærd (påfør `-Lehn` selv når rod-`ahlefeldt` står i navnet)
forbliver §6-udskudt.

### 4.7 Invalidation / triggers (IKKE udskudt — Codex BLOCKER 2)

`visning_fuldt_navn`/`visning_efternavn` afhænger af flere input end konklusioner. Alle kilder
skal regenerere cachen:

| Ændring | Handling |
|---|---|
| `conclusion` (navn) INSERT/UPDATE/DELETE | eksisterende `trg_conclusion_regen` (dækker allerede) |
| `person_external_id` INSERT/UPDATE/DELETE | ny trigger → `regen_person_visning(person_id)` |
| `lineage.slaegtsnavn` eller `parent_lineage_id` UPDATE | ny trigger → regenerér **alle** medlemmer af den berørte linje-subtræ (cyklus-vagt påkrævet, se nedenfor) |

"Selv-heling ved næste konklusions-edit" er ikke konsistens; derfor eksplicitte triggers frem
for at udskyde. Trigger-sættet er lille.

**Cyklus-vagt (Codex Pass 2, punkt 4 — CONFIRMED):** både den **nedadgående** subtræ-traversering
i lineage-triggeren OG den **opadgående** `parent_lineage_id`-vandring i efternavns-opslaget
(§4.2) skal beskyttes mod cykler. To lag:
1. **Forebyg cyklus i data:** en `BEFORE INSERT/UPDATE`-trigger (eller CHECK via rekursiv
   verifikation) på `lineage` der afviser at sætte `parent_lineage_id` så en cyklus opstår.
2. **Runtime-vagt (Codex Pass 3 — præciseret):** `UNION` + en `depth`-kolonne terminerer IKKE
   automatisk, fordi den varierende `depth`/path gør hver række unik (så `UNION` deduplikerer
   intet). Kræv derfor ét af:
   - PostgreSQL `WITH RECURSIVE ... CYCLE <col> SET is_cycle USING path` (native cyklus-stop), eller
   - eksplicit visited-path: bær et `path BIGINT[]` og tilføj `WHERE NOT l.id = ANY(path)`.
   Dybde-grænse skal **`RAISE EXCEPTION`** (fejle kontrolleret), ikke stille trunkere. **Samme
   sikre walk-funktion** bruges BÅDE i den forebyggende `BEFORE`-trigger (trin 1) og i
   opslag/subtræ-regen — ikke to divergerende implementeringer. Gælder begge retninger.

### 4.8 Backfill

**Fortrydbarheds-model (Codex Pass 3 — korrigeret selvmodsigelse):** cache-kolonnerne er på
`version_pk_registry`-skip-listen (§4.4) → de får INGEN `change_event`, så et `change_set` kan
**ikke** gendanne cache-værdier direkte. Cachen er en envejs-projektion (invariant 4) og
"fortrydes" ikke — den **regenereres**. Den *autoritative, fortrydbare* ændring er derfor
**`lineage.slaegtsnavn`-tildelingen** (input'et), som logges normalt: fortryd = ryd
`slaegtsnavn` + kør regen → alt ruller deterministisk tilbage til NULL-efternavn. Backfill'en
af de 580 er altså en **deterministisk projektions-opdatering**, ikke et data-restore-`change_set`.

- Kør backfill i **én** transaktion med isolation `REPEATABLE READ` eller `SERIALIZABLE` (Codex
  Pass 3): under default `READ COMMITTED` beskytter én transaktion IKKE 580 separate regen-kald
  mod samtidige konklusions-edits. Alternativt eksplicit lås de berørte rækker.
- **Idempotent LOGGING (Codex Pass 2, punkt 6):** `regen`'s `UPDATE` skal have
  `WHERE (visning_efternavn, visning_fuldt_navn) IS DISTINCT FROM (<ny>, <ny>)`, så en
  no-op-genkørsel hverken affyrer row-triggers eller rører rækker. (Codex Pass 3 bekræftede:
  WHERE-vagten filtrerer rækken helt væk, så `UPDATE OF`-trigger-fælden opstår ikke.)
- **Karantæne-log-idempotens (Codex Pass 3):** tvetydig-karantænen (§4.5) må have sin egen
  idempotens-nøgle/upsert — ellers gen-logger den ved HVER regen, selv når `IS DISTINCT FROM`
  forhindrer person-`UPDATE`'et. (Kun relevant når multi-medlemskab opstår; noteret nu.)

### 4.9 Frontend-adoption + reader-inventar

Læsere skifter til `visning_fuldt_navn` (fallback `visning_navn` som **midlertidig** kompat):

| Fil | Ændring |
|---|---|
| `web/src/data/model.ts` | select + map → `visning_fuldt_navn` |
| `mobile/src/data/load.ts` | select + map → `visning_fuldt_navn` |
| `web/src/data/redaktionRead.ts` | vis rå + afledt (badge når `visning_efternavn` ≠ NULL) |
| `mobile/src/data/redaktionRead.ts` | do. |
| `R/tng-qa/*` (02-pull-ours, 04-match, 05b-enrich-queue) | **bevidst uændret** — læser fortsat rå `visning_navn` |
| GEDCOM-eksport (fremtid) | afledte (~562): `SURN = visning_efternavn`. **11 bog-native:** `visning_efternavn = NULL` → egen name-parser der deler GIVN/partikel/SURN fra `visning_navn` (jf. §4.4-afgrænsning). IKKE ubetinget `SURN = visning_efternavn`. |

Fallback behandles som midlertidig kompatibilitet med målbar udfasning (Codex punkt 9).
**GEDCOM-name-parseren for bog-native (de 11) specificeres i GEDCOM-eksport-planen** (udskudt) —
reader-inventaret her afspejler undtagelsen, så §4.4 og §4.9 ikke modsiger hinanden (Codex Pass 3).

---

## 5. Codex-review — reconcile

| Codex-punkt | Alvor | Beslutning |
|---|---|---|
| 1. "Har efternavn" kan ikke udledes af fritekst | BLOCKER | **Afgrænset.** Brugerregel: født medlem ⇒ efternavn-suffiks medmindre allerede til stede. `external_id`-gate fjerner "ikke-medlem"-faren. Iuel/Raben = mellemnavne → får "Reventlow". |
| 2. Regen afhænger af flere input | BLOCKER | **Adopteret.** Eksplicitte triggers (§4.7), ikke udskudt. |
| 3. "Dybeste gren vinder" ikke deterministisk | BLOCKER | **Delvist adopteret** (Pass 2): defensiv fan-out-vagt (`COUNT(DISTINCT slaegtsnavn) ≤ 1` → ellers NULL+karantæne) i regen NU (§4.5); fuld primær-medlemskabs-regel §6. Ikke længere "kun afvist". |
| (a) søsterfelt vs overload/VIEW | — | **3-felt-split** (§4.4). Overload udelukket af TNG-QA. VIEW afviger fra stored-cache-mønster. |
| 4. `external_id` blander identitet/klassifikation | SHOULD | Empirisk stærkt (0 multi, 332≈indgift). Krydstjek i planen (§7). |
| 5. `samme_som` kan få forskellige fulde navne | SHOULD | **Blødt op (Pass 2):** feature'en er collapse-*neutral* — det afledte efternavn er konsistent på tværs af familien, men `visning_fuldt_navn` indeholder også hver rækkes eget rå `visning_navn`, som kan afvige mellem `samme_som`-rækker. Fuld-navn-valget er collapse's eksisterende ansvar (præ-eksisterende, ikke indført her). Ingen overclaim om fuld-navn-stabilitet. Note §6. |
| 6. `max(vaerdi_tekst)` vilkårlig | SHOULD | **Præ-eksisterende** regen-adfærd, uden for scope. Noteret §6. |
| 7. Backfill-atomicitet | SHOULD | Samme idempotente regen i change_set under transaktion (§4.8). |
| 8. Normalisering underspec. | SHOULD | **Adopteret** (§4.6). |
| 9. Fallback skjuler drift | SHOULD | Reader-inventar (§4.9); fallback midlertidig. |
| 10. Manglende proveniens | NICE | **Løst** af `visning_efternavn`-isolation (§4.4). |

### 5.1 Codex Pass 2 — adversarial review af den færdige spec (2026-07-03)

**Verdict:** needs-attention → alle fund foldet ind som spec-hærdning (design-formen er uændret).
Klassificeret med empirical-reproduction + impact-bucketing.

**Bekræftet (verificeret via logisk/schema-inspektion):**
- **P1/P2 — fan-out i efternavns-opslag** *(silent-corruption, fremtid)*: regen-join kan fane ud
  når en person får flere linje-medlemskaber → vilkårligt efternavn. Rettet: dedupikeret subquery
  + `COUNT(DISTINCT) ≤ 1`-vagt i regen NU (§4.5). Reproduktion: join-kardinalitet mod `max()`-agg
  er logisk flerrækket ved >1 distinkt `slaegtsnavn`.
- **P4 — trigger-cyklus** *(hard-runtime, fremtid)*: nedadgående subtræ-walk manglede cyklus-vagt.
  Rettet: data-forebyggelse + `WITH RECURSIVE`-cycle-detektion begge retninger (§4.7).
- **P6 — skip-liste + idempotent logging** *(proces/støj)*: matcher mit eget Phase-1-fund. De to
  cache-kolonner SKAL på `version_pk_registry`-skip-listen (§4.4), og `regen`'s UPDATE skal bruge
  `IS DISTINCT FROM` (§4.8) — ellers ~580 spuriøse `change_event` + no-op-genkørsler rører rækker.
- **GEDCOM-11** *(spec-nøjagtighed)*: de 11 bog-native har `visning_efternavn = NULL` → ikke
  dækket af `SURN = visning_efternavn`. Overclaim rettet (§4.4, punkt 1).

**Recalibreret:**
- **P3 — normalisering**: min §4.6 var både over- (unødig partikel-logik) og under-specificeret
  (bindestreg splitter?). Omskrevet til entydig **whole-token-lighed, bindestreg bevaret internt**
  (§4.6). Codex' forenkling ("sidste whitespace-token er Reventlow") indarbejdet.
- **P5 — samme_som**: min "efternavn stabilt"-formulering overclaimede. Blødt op til
  collapse-*neutralitet* (§5 række 5 + §6).

**Dismissed:** ingen — alle Pass-2-fund var enten korrekte hærdninger eller berettigede
recalibreringer.

**Impact-bucket-tally (Pass 2):** 2 silent-corruption (fremtid) · 1 hard-runtime (fremtid) ·
1 proces/støj · 2 spec-nøjagtighed. Ingen aktuel-data-crash (alt gælder fremtidig vækst eller
logging-hygiejne), men alle er billige at bygge ind fra start frem for at retrofitte.

**Læring:** en "afvist for nu, 0 i data"-beslutning (P3-blocker) er kun sikker hvis den *recept
der læser data* også er fan-out-sikker — ellers flytter man en verificeret nul-tilstand ind i en
fremtidig stille korruption. Defensiv vagt i selve recepten > udskyde hele reglen.

### 5.2 Codex Pass 3 — verifikation af Pass-2-hærdningerne (2026-07-03)

Fokuseret pass: verificér at Pass-2-rettelserne selv er korrekte (anti-laundering). Resultat:
2 CORRECT som de var, 4 INSUFFICIENT (præciseret), 3 nye interaktions-fund. **Ingen dismissals.**

**CORRECT uden ændring:** NULL-navn-vagt (§4.5) · `IS DISTINCT FROM`-idempotens (§4.8, Codex
bekræftede at WHERE-vagten fjerner `UPDATE OF`-trigger-fælden).

**INSUFFICIENT → yderligere præciseret:**
- **Fan-out:** "separat subquery" garanterede ikke én-række-per-person → konkret **CTE med
  `GROUP BY person_id`** + skalar join efter navn-agg (§4.5, SQL-skitse tilføjet).
- **Normalisering:** whitespace-token-match kunne aldrig matche fler-ords-efternavne ("von
  Brockdorff") og kunne falsk-skippe når efternavnet var et fornavn → **suffiks-token-sekvens-
  match** (§4.6, 2 nye verificerede eksempler).
- **Cyklus:** `UNION`+varierende depth terminerer ikke → **`CYCLE`/visited-path + `RAISE`**, samme
  walk i forebyggende trigger og opslag (§4.7).
- **GEDCOM-11:** §4.9-reader-inventaret modsagde stadig §4.4 → row opdateret m. eksplicit
  11-undtagelse + name-parser udskudt til GEDCOM-planen (§4.9).

**Nye interaktions-fund (verificeret):**
- **Skip-liste ⊥ "fortrydbart":** skip-listen ⇒ ingen cache-`change_event` ⇒ et `change_set` kan
  ikke gendanne cache. Rettet: den autoritative fortrydbare enhed er **`lineage.slaegtsnavn`-
  input'et**; cachen regenereres, restores ikke (§4.8). *Denne modsigelse var indført af min egen
  Pass-2-hærdning* — præcis derfor Pass 3 ikke var redundant.
- **Isolation:** én transaktion beskytter ikke 580 regen-kald under `READ COMMITTED` → kræv
  `REPEATABLE READ`/`SERIALIZABLE` el. rækkelås (§4.8).
- **Karantæne-log-idempotens:** kan gen-logge ved hver regen trods `IS DISTINCT FROM` → egen
  idempotens-nøgle (§4.8).

**Impact-bucket-tally (Pass 3):** 1 silent-corruption-præcisering (fan-out CTE) · 1
hard-runtime-præcisering (cyklus) · 1 korrekthed (normalisering) · 3 proces/konsistens
(fortrydbarhed, isolation, karantæne-log) · 1 spec-nøjagtighed (GEDCOM). Stadig ingen aktuel-data-
crash; alt gælder fremtidig vækst eller backfill-hygiejne.

**Læring:** en hærdning kan *selv* indføre en modsigelse (skip-liste vs. fortrydbart) — et
verifikations-pass på ens egne rettelser fanger det, en selv-review sjældnere. Værd at køre når
hærdningen tilføjede nye kontrakt-claims (her: SQL-recepter).

---

## 6. Bevidst udskudt / fremtids-regler

- **Flere-medlemskab (forgrening/kryds-slægt):** når `parent_lineage_id`-forgrening eller
  kryds-slægt-medlemskab opstår, kræves et eksplicit **primært** medlemskab + cyklus-vagt på
  `parent_lineage_id`-vandringen. Afvis/karantæne tvetydighed frem for vilkårlig SQL-række.
- **Gren-variant-vagt:** når en gren har et *mere specifikt* efternavn end roden
  (Ahlefeldt-Laurvig-Lehn vs Ahlefeldt), skal vagten kunne påføre den mere specifikke variant
  selv når rod-token allerede står i navnet. For nuværende Reventlow-data er dette moot.
- **`samme_som`-stabilitet:** dokumentér at komposition sker per-DB-række før collapse; verificér
  at collapse foretrækker kanonisk rækkes fulde navn (alle `samme_som` deler slægt i dag).
- **Konkurrerende navne-konklusioner (`max`):** præ-eksisterende; adresseres separat hvis flere
  aktive navne-konklusioner opstår.
- **Reventlow-Criminil:** separat slægt/gren ved senere import → egen `lineage` m. eget
  `slaegtsnavn`.

---

## 7. Verifikation (i implementeringsplanen)

- **Medlemskabs-signal:** bekræft at ingen `external_id`-person kun optræder som ægtefælle
  (falsk positiv), og at intet født medlem mangler `external_id` (falsk negativ). Fætter/kusine-
  ægteskaber (født **og** gift) beholder korrekt `external_id` → får efternavn (ønsket).
- **Vagt:** de 11 "von/de Reventlow" får `visning_efternavn = NULL` (springes over).
- **Iuel/Raben:** de 7 bliver "… Iuel Reventlow" / "… Raben Reventlow".
- **Backfill:** 580 rækker; `change_set` fortrydbart; genkørsel idempotent.
- **TNG-QA:** kør pipelinen efter backfill; match-nøgler uændrede (læser rå `visning_navn`).

## 8. Test-plan

- **DB:** `db-verify.sql`-assert: regen sætter `visning_efternavn`/`visning_fuldt_navn` korrekt
  for (a) enkelt-fornavn, (b) flere-fornavne, (c) mellemnavn (Iuel), (d) allerede-Reventlow
  (NULL), (e) indgift-ægtefælle (NULL). Trigger-assert: `external_id`- og `lineage`-ændring
  regenererer.
- **Frontend:** web+mobile enhedstest på map-funktion (fallback-adfærd); redaktør-badge når
  `visning_efternavn` ≠ NULL.
- **Regression:** TNG-QA match-suite grøn efter backfill.
