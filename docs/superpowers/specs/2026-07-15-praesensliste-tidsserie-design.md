# Præsensliste som tidsserie ("som-af"-semantik + snapshot-diff) — Design

**Dato:** 2026-07-15
**Status:** Udkast — afventer PDF af anden DAA-udgave + brugergodkendelse før implementering
**Relateret:** `docs/flere-daa-udgaver-roadmap.md` (Problem 1 — dette spec; Problem 3 er forudsætningen),
`docs/superpowers/specs/2026-07-15-tvaers-udgave-identifikation-design.md` (søsterspec: matchings-kernen
`matchUdgaver` + "Sammenlign udgaver"-flowet + `red_ikke_samme_som` — genbruges her uændret som
identitets-leverandør),
`docs/superpowers/specs/2026-07-02-redaktionel-samme-som-linking-design.md` (producenten `red_samme_som`, implementeret),
`docs/superpowers/specs/2026-07-02-samme-som-collapse-design.md` (forbruger-kontrakten — brydes ikke),
`.claude/skills/daa-presens/SKILL.md` + `docs/daa-presens-archetype.md` (loader + ekstraktions-kontrakt).

## 1. Formål

Præsenslisten udkommer med års mellemrum (DAA 2012-14, 2015-17, …) og beskriver de **samme nulevende
personer** igen og igen — den er en **tidsserie af snapshots**, ikke en samling isolerede kilder. I dag
loader `/daa-presens` hver liste append-only som en ny `source` (`.claude/skills/daa-presens/SKILL.md:88-91`)
uden nogen "som-af"-mekanisme: `person.levende` (schema.sql:124) er et rent GDPR-flag, ikke en udgave-scopet
tilstand, og identitetssammenkædning er "pragmatisk holdt" i PoC (SKILL.md:96-97). Ingen præsensliste er
endnu i prod (`docs/database-current-state.md:38-39`) — dette er design af uafprøvet territorium, ikke en
bugrettelse.

Featuren leverer tre ting, når udgave nr. 2 foreligger:

- **(a) Som-af-semantik:** en veldefineret, effektiv forespørgsel "vis personens status som den var i
  udgave X" (§3) — uden nye kernetabeller.
- **(b) Tidsserie-identitet:** en fastlagt integration mellem `daa-presens`-loaderen og søsterspec'ets
  matchings-flow — **load-then-link** (§4) — så DAA 2012-14-Christian, DAA 2015-17-Christian og
  stamtavlens Christian bliver ét identitets-komponent via `samme_som`.
- **(c) Diff-visning:** en **beregnet** (ikke gemt) diff mellem to udgavers snapshots af samme person —
  ny partner, nyt barn, dødsfald, bopæls-/erhvervsskift (§5) — plus liste-niveauet "ny på listen /
  ikke genfundet".

Hovedbeslutningen, argumenteret i §3.4: **evidenslaget ER allerede snapshot-lageret.** Hver påstand er
kildebundet via `citation.source_id` (schema.sql:384-392), og `source.aar` (schema.sql:37) er
tidsserie-aksen. Det der mangler er ikke et nyt snapshot-lag, men (1) tre små loader-huller lukket,
(2) identitets-links (søsterspec'et), og (3) rene læse-projektioner i app-laget.

## 2. Arkitektur: ren ansvarsfordeling

Samme doktrin som samme_som-spec'et §2 og søsterspec'et §2: **DB er eneste sikkerhedsgrænse for delte
invarianter; klient-beregninger er rådgivende projektioner.** Et som-af-snapshot og en diff er pr.
definition projektioner — de beskytter ingen delte data og hører derfor IKKE i DB-laget.

| Lag | Ansvar | Håndhævelse |
|---|---|---|
| **Loader** (`load_presens.R`, revideret) | Append-only load af udgave-N som ny `source` med komplet proveniens: `source.aar` sat, `person_external_id` på ALLE oprettede personer (også partner-stubs), evidens-rækker på alle relationer | Deterministisk script; fail-closed ved uparsebar udgave-streng |
| **DB** (uændret kerne; én lille RPC: `red_set_levende`) | Evidens-invarianter (uforanderlige påstande), `samme_som`-graf-invarianter (trigger, schema.sql:944-973), RLS/GDPR-gating | **Autoritativ** |
| **Identitets-flow** (søsterspec'et, genbrugt uændret) | Kandidat-scoring + redaktør-bekræftelse → `red_samme_som`/`red_ikke_samme_som` | Rådgivende scoring; beslutning via DB-RPC |
| **Som-af-/diff-kerne** (`packages/core/src/presensSnapshot.ts` + `presensDiff.ts`, nye) | Rene funktioner: source-scopet snapshot-projektion + felt-diff mellem to snapshots af samme komponent | Ren funktion, klient-side, rådgivende |
| **UI** (web `Redaktion.tsx` + mobile `redaktion/`) | "Ændringer siden sidste udgave"-visning + handlinger (dødsfald → `red_set_levende`) gennem eksisterende dry-run/LIVE-flow | Rådgivende |

**Nøglebeslutning — intet persisteret snapshot/diff:** snapshots og diffs er rene funktioner af data der
allerede er i redaktions-datasættet, og de **afhænger af identitets-links der kan ændres** (et nyt
`samme_som`-link eller en fjernelse ændrer hvilke rækker der hører til komponenten). En gemt diff ville
drifte ved hver identitets-beslutning — præcis samme ræsonnement som søsterspec'ets fravalg af
kandidat-staging (§2 dér) og `person.visning_*` som envejs-cache (schema.sql:128-134). Se §5.1.

## 3. Som-af-semantik (a)

### 3.1 Hvad `citation.source_id` allerede giver

For **fakta** er som-af-semantikken allerede til stede i skemaet: `load_presens.R`'s `fact_value`
(`.claude/skills/daa-presens/scripts/load_presens.R:80-82`) skriver fact → assertion → citation med
`source_id` = udgavens source for hvert navn/fødsel/død/erhverv/bopæl/titel. "Person P's fakta som af
udgave U" er derfor:

```
assertions A hvor A.target_type='fact' og EXISTS citation(C.assertion_id=A.id AND C.source_id=U)
og fact(A.target_id).subjekt = et medlem af P's identitets-komponent
```

Det er en ren filtrering — ingen skemaændring. Semantisk er det også det *rigtige*: som-af-visningen skal
vise **hvad den trykte udgave påstod** (assertion-laget, invariant 1), ikke den aktuelle konklusion.
Konklusionslaget forbliver "nuværende bedste viden"; som-af er en kilde-projektion ved siden af.

### 3.2 De tre huller der SKAL lukkes (loader-leverancer)

1. **`source.aar` sættes aldrig.** `load_presens.R:106-107` (og `load_daa.R:236-237`) indsætter source
   UDEN `aar` — men `aar` er pr. skemaets egen kommentar tidsserie-aksen ("udgave-fritekst er upålidelig
   til sortering", schema.sql:37). Uden den kan "forrige udgave" ikke afledes deterministisk. **Leverance:**
   loaderen parser udgave-strengen (`DAA 2012-2014` → `aar=2014`; konvention: **sidste dækkede år**,
   dokumenteret i `docs/decisions.md`) og **stopper fail-closed** hvis intet årstal kan parses. En lille
   backfill i `db-migrations.sql` sætter `aar` på de eksisterende source-rækker (DAA 2018-20 → 2020).
2. **Partner-stubs får ingen `person_external_id`.** Pass B (`load_presens.R:136-137`) opretter
   ægtefælle-personer uden `add_extid` — de mangler dermed det kilde-medlemskabs-spor søsterspec'et
   kræver (§3.1 dér: "mindst ét af de to spor pr. person"; citation-fallbacken dækker dem i praksis via
   navne-factet, men external-id-sporet er det billige og eksplicitte). **Leverance:** `add_extid` også
   for partner-stubs.
3. **Pass C-familier (forælder-barn) har nul evidens.** `load_presens.R:147-158` skriver `family` +
   `family_member` uden nogen assertion/citation — relationen kan derfor ikke kilde-scopes via
   evidenslaget. Fuld evidens på `family_member` er Problem 2's søsterspec (roadmap linje 78-83) og
   designes IKKE her. **Men det blokerer ikke som-af for præsens-serien**, fordi load-then-link (§4)
   bevarer én person-række pr. udgave: en præsens-persons familier består pr. konstruktion KUN af
   medlemmer fra samme load, så **kilde-scoping af `family_member` afledes af medlemmernes
   `person_external_id.source_id`** (schema.sql:137-146). Det er en **konvention, ikke en invariant**
   (en redaktør kan manuelt koble på tværs) — accepteret og dokumenteret; Problem 2-spec'et løfter den
   til rigtig evidens senere. **Leverance her (minimal):** loaderen skriver ét `fact('registreret', subjekt=family)`
   med citation? **Nej — fravalgt** (§10): afledningen via medlemmer dækker behovet uden ny mekanik.

Dertil én afgrænsning uden fix: **manuelle redaktionelle rettelser er udgaveløse** —
`red_upsert_fakta`/`red_tilfoej_oplysning` skriver citation med `source_id NULL` (schema.sql:596-598).
De optræder derfor ikke i nogen som-af-projektion, kun i konklusions-/nu-visningen. Det er korrekt
adfærd (som-af = hvad kilden skrev), ikke et hul.

### 3.3 Datakontrakt: `PresensSnapshot` (packages/core, ren funktion)

`presensSnapshot(evidens: RedaktionsData, komponentMedlemmer: PersonId[], sourceId: SourceId): PresensSnapshot`

```ts
type PresensSnapshot = {
  sourceId: SourceId; aar: number;
  personId: PersonId | null;          // komponentens medlem i DENNE udgave (via person_external_id) — null = ikke i udgaven
  fakta: SnapFakta[];                 // {faktatype, vaerdi, dateMin/Max, dateRaw, sted} — fra assertions citeret af sourceId
  partnere: SnapPartner[];            // fra family_member(rolle='partner') på udgave-medlemmets familier: {partnerPersonId, ordinal, vielseRaw, skilt}
  boern: SnapBarn[];                  // fra family_member(rolle='barn') i familier hvor udgave-medlemmet er partner
};
```

Bygges udelukkende af det redaktions-datasæt klienten allerede henter komplet (`fetchRedaktionPersoner`
+ udvidelserne søsterspec'et §11 alligevel kræver af `redaktionRead`: kilde-medlemskab, år-intervaller).
`redaktionRead` udvides yderligere med assertion→citation→source_id-koblingen for komponentens medlemmer
(bounded: én komponents facts, ikke hele basen).

### 3.4 Ærlig vurdering: rækker den lette tilgang? Ja — derfor ingen nye kernetabeller

Overvejet og fravalgt: et eksplicit snapshot-lag (fx `person_udgave_status(person_id, source_id, …)` eller
temporale/bitemporale tabeller). Begrundelse for fravalg:

- **Kadence og kardinalitet:** udgaver er diskrete og sjældne (hvert ~3. år, håndfulde i alt; hundreder af
  personer pr. liste). Der er intet kontinuerligt "gyldig fra/til"-behov — kun "hvad sagde udgave U".
  Citation-sporet besvarer præcis det.
- **Én kilde til sandhed:** et snapshot-lag ville duplikere hvad evidenslaget allerede bærer, med alle
  cache-drift-problemerne (invariant 4) og endnu en `max(id)+1`-allokeringsflade (jf. samme_som-spec §3).
- **Den eneste reelle strukturelle mangel** er `family_member`-evidens — og den er (i) allerede scopet som
  Problem 2's eget spec, og (ii) ikke blokerende for præsens-tidsserien pga. medlems-afledningen (§3.2.3).
  Hvis Problem 2-spec'et lander, bliver som-af for relationer *stærkere* (ægte evidens frem for
  konvention) uden at denne features kontrakt ændres — `presensSnapshot` skifter blot afledningskilde.

Konklusion: **kun query-/visningsopgave i app-laget + loader-hygiejne.** Ingen skemaændring ud over
`red_set_levende` (§7) og `source.aar`-backfill.

## 4. Tværudgave-identitet for levende personer: load-then-link (b)

### 4.1 De to kandidat-flows

**Flow A — match FØR load (pre-link):** kør matching på det udtrukne JSON mod basen; redaktøren bekræfter;
loaderen skriver derefter fakta ind under de bekræftede eksisterende person-ID'er (nye assertions på samme
person).

**Flow B — match EFTER load (load-then-link, dagens append-flow + søsterspec'et):** load udgaven som nye
personer under ny source (uændret `load_presens.R`); kør derefter "Sammenlign udgaver"; bekræftede matches
bliver `samme_som`-links; app-collapse folder.

| Hensyn | A: pre-link | B: load-then-link |
|---|---|---|
| Loader-kompleksitet | Høj: merge-semantik (hvilket fact-slot? upsert vs. nyt fact), delvist loadede tilstande | Uændret: dum, deterministisk, transaktionel (`load_presens.R:99-172`) |
| Matchingens datagrundlag | Rå JSON — uden for DB, uden for søsterspec'ets populations-model (§3.1 dér afgrænser via `person_external_id.source_id`, som forudsætter at udgaven ER loadet) | Rigtige DB-rækker med fuld evidens — præcis hvad `matchUdgaver` er designet til |
| Reversibilitet | Dårlig: et forkert pre-match har blandet to personers fakta på ét person-id; adskillelse = manuel kirurgi i evidenslaget | God: `red_fjern_samme_som` (schema.sql:1006-1017) skiller komponenten igen; ingen datarækker rørt |
| Som-af/proveniens | Svagere: person-rækken repræsenterer flere udgaver; udgave-medlemskab kun via citations | Stærkere: én person-række pr. udgave = gratis snapshot-scoping (bærer §3.2.3) |
| Blokering | Load venter på redaktørens gennemgang af hele arbejdslisten | Load straks; identitetsarbejde asynkront, i redaktørens tempo |
| Person-inflation | Ingen | Ja: +100-600 rækker pr. udgave, foldet i UI af collapse |
| Genbrug | Kræver nyt matching-flow mod JSON + ny skrive-vej | Genbruger søsterspec'et + `red_samme_som` + collapse 1:1 — nul ny identitetsmekanik |

### 4.2 Valg: **B — load-then-link**

Person-inflationen er den eneste reelle omkostning, og den er allerede betalt: collapse-projektionen
(collapse-spec §2-§8) eksisterer netop for at folde flere person-rækker til én identitet, og
grundlægger-dubletterne bruger den i prod i dag. Alt andet taler for B — især reversibiliteten (en
identitets-fejl må aldrig kræve evidens-kirurgi) og at søsterspec'ets hele populations- og UI-model
forudsætter at den nye udgave er i basen. **A fravælges også principielt:** pre-link gør loadets
korrekthed afhængig af redaktionelle skøn; append-only-loadet skal forblive et rent kilde-aftryk
(invariant 1 — kildens påstande står alene).

Konsekvens-konventioner:

- **Retning:** som søsterspec'et §5.4 — eksisterende post = kanonisk sink, ny udgaves person = alias.
  Ved tredje udgave (2015-17) linkes dens person **direkte til samme kanoniske sink** (stjerne-topologi,
  ikke kæde alias→alias): G3/G4-triggeren (schema.sql:954-963) tillader flere aliaser pr. sink, og
  UI'ets injektivitets-advisory (søsterspec §5.5) gælder kun *inden for* samme kilde.
- **Snapshot-tilhør (invariant for denne feature):** en person-række tilhører præcis én udgave
  (`person_external_id.source_id`); redaktionelt oprettede personer er udgaveløse og deltager ikke i
  som-af-projektioner. `presensSnapshot` afleder `personId` pr. udgave af komponentens medlemsliste.
- **Rækkefølge ved genoptagelse** (roadmap linje 149-159, bekræftet): leverance 0 = fixup-source-bug
  (søsterspec §7), så loader-hygiejnen (§3.2), så load, så "Sammenlign udgaver", så diff.

### 4.3 Match-prioritering for præsens-personer

En præsens-person kan matche (i) stamtavlens person eller (ii) en tidligere præsenslistes person — begge
tilfælde er for `matchUdgaver` bare "personer uden for min kilde" og håndteres af samme arbejdsliste.
Er BEGGE til stede (stamtavle-Christian har allerede et 2012-14-alias, og 2015-17-Christian matcher begge),
demoterer den injektive rangering ikke — begge er legitime; redaktøren linker til **den kanoniske sink**
(default-retningen §4.2 sørger for det). Præsenslisters datakvalitet hjælper: eksakte fødselsdatoer giver
skarpe års-overlap-signaler (søsterspec §3.5 forbehold 2 gælder omvendt positivt her).

## 5. Diff/ændrings-visning (c)

### 5.1 Beregnet, ikke gemt — anbefaling

**Anbefaling: en ren, ikke-persisteret felt-diff i `packages/core/src/presensDiff.ts`** mellem to
`PresensSnapshot`s af samme identitets-komponent. Ingen "ændringslog"-tabel. Begrundelse:

- Diffens input (identitets-komponenten) er **redaktionelt flydende** — hvert bekræftet/fjernet
  `samme_som`-link ændrer den. En gemt diff drifter øjeblikkeligt og kræver invalidering/GC (samme
  argument som søsterspec §2 mod kandidat-staging).
- Skalaen er triviel: én komponents to snapshots er < 100 rækker; hele listens diff (600 komponenter)
  er millisekunder i JS over det allerede-hentede redaktions-datasæt.
- En ændringslog ville desuden være en **andenhånds-afledning** af evidens der allerede er fuldt
  bevaret — den tilføjer intet nyt fakta, kun cache (invariant 4-lugt).

Genovervejes kun hvis diffen skal (a) vises offentligt i skala uden at hente evidenslaget, eller
(b) annoteres redaktionelt ("denne ændring er verificeret") — begge er fremtidige behov (§10).

### 5.2 Datakontrakt

`presensDiff(fra: PresensSnapshot, til: PresensSnapshot, identitet: IdentitetsIndeks): PresensDiff`

```ts
type PresensDiff = {
  status: 'sammenlignet' | 'ny_paa_listen' | 'ikke_genfundet' | 'afventer_identitet';
  aendringer: DiffEntry[];
};
type DiffEntry =
  | { art: 'fakta';   faktatype: string; kategori: 'ny'|'aendret'|'ophoert'; fra?: string; til?: string }
  | { art: 'partner'; kategori: 'ny'|'skilt'|'ophoert'; partnerVisning: string; ordinal?: number }
  | { art: 'barn';    kategori: 'ny'; barnVisning: string }
  | { art: 'doedsfald'; til: string }                            // død-fact i `til`, ikke i `fra`
  | { art: 'uoverensstemmelse'; faktatype: string; fra: string; til: string };  // fx fødsel ≠ fødsel
```

`IdentitetsIndeks` = `canonicalIdById` fra collapse-kernen (redaktions-projektionen) — bruges til at
afgøre om `til`-snapshottets partner/barn "er samme" som `fra`-snapshottets.

### 5.3 Felt-semantik

| Domæne | Nøgle | Regel |
|---|---|---|
| navn, titel, bopæl | faktatype (singleton) | strengsammenligning på normaliseret værdi → `aendret` ("flyttet" for bopæl) |
| erhverv | faktatype (multi) | mængde-diff på normaliseret tekst → `ny`/`ophoert` pr. værdi |
| fødsel | faktatype | **sanity, ikke diff:** afvigelse ud over OCR-tolerance → `uoverensstemmelse` (signal om fejlmatch/OCR — vises rødt, foreslår gennemsyn af samme_som-linket) |
| død | faktatype | i `til` men ikke `fra` → `doedsfald` + handlings-knap (§7) |
| partnere | partner-identitet: `canonicalIdById` hvis begge partner-rækker er linket; ellers **navnefoldnings-nøglen fra `matchUdgaver`** (søsterspec §3.2 — genbrugt, én normaliserings-sandhed) | ny ordinal/nyt foldet navn → `ny`; `skilt`-fact i `til` → `skilt`; partner i `fra` uden modpart → `ophoert` (vises neutralt — kan være skilsmisse ELLER udeladelse) |
| børn | som partnere | barn i `til` uden modpart i `fra` → `ny` |
| person-niveau | komponentens medlemskab af de to kilder | medlem i `til` men intet i `fra` → `ny_paa_listen`; omvendt → `ikke_genfundet`; komponent uafklaret (kandidater ≥ review-cutoff hverken linket eller afvist, søsterspec §2) → `afventer_identitet` — diff undertrykkes |

**Epistemisk invariant (I-fravær): fravær i en præsensliste er svag evidens.** En person kan være udeladt,
flyttet, udmeldt eller overset af redaktionen. `ikke_genfundet` og `ophoert` er derfor ALTID neutrale
observationer i UI'et — **aldrig** automatiske skrivninger (ingen auto-død, ingen auto-sletning af
partner). Kun positiv evidens (et død-fact) udløser en foreslået handling.

## 6. Redaktør-UI

Ingen ny top-level-flade: diffen bor som **fane "Ændringer" i søsterspec'ets "Sammenlign udgaver"**
(samme kildepar-vælger, web `Redaktion.tsx`-sektion + mobile `redaktion/sammenlign`), plus et
per-person-panel:

- **Liste-niveau:** "DAA 2015-17 mod DAA 2012-14: X gengangere · Y nye på listen · Z ikke genfundet ·
  W dødsfald · V afventer identitet". Dødsfald og uoverensstemmelser øverst (handlingskrævende).
- **Person-niveau:** på redaktions-person-siden (`mobile/src/app/redaktion/person/[id].tsx` + web) en
  "Som af"-vælger over komponentens udgaver (drevet af `presensSnapshot`) og en "siden sidste udgave"-boks
  (drevet af `presensDiff`). Kilde-badge pr. udgave (proveniens som collapse-spec §8's mergedFrom-badge).
- **Handlinger** (alle gennem eksisterende dry-run/LIVE-flow i `redaktionWrite`):
  - `doedsfald` → knap "Markér som afdød": kalder ny `red_set_levende(p_person_id, false)` (§7) på ALLE
    komponentens medlemmer (bounded loop, samme mønster som "Markér som ny person" i søsterspec §5.3).
    Selve død-factet er allerede loadet med kilde — flaget er den eneste manglende skrivning.
  - `uoverensstemmelse` → link til samme_som-linket ("gennemse match") + til fact-kortene.
  - Øvrige kategorier er ren visning — kildens påstande står allerede i evidenslaget; en redaktør der vil
    ændre konklusionen bruger de eksisterende fact-flows (`red_set_konklusion` m.fl.).

## 7. RLS / GDPR (d)

Præsenslister vender GDPR-profilen om: hvor stamtavlen er ~100 % afdøde, er præsenslisten ~100 %
`levende=TRUE` (`load_presens.R:64-65`) — inklusive **adresser (bopæl), erhverv og mindreårige børn med
fødselsdatoer** (`docs/daa-presens-archetype.md` §2). Vurdering mod eksisterende infrastruktur:

- **Anon-tier dækker, fail-closed.** `person_offentlig` kræver `levende=false AND coalesce(privat,false)=false`
  (`db-rls.sql:39-43`), og person-politikken (`db-rls.sql:265`) skjuler dermed alle præsens-personer og alle
  deres personbundne rækker for anon — verificeret adfærd i prod (0 levende lækket,
  `docs/database-current-state.md` §2). At loade en præsensliste eksponerer altså **intet** offentligt.
  Partner-stubs oprettes også `levende=TRUE` (fail-closed korrekt, selv når kun navnet kendes).
- **`place`-rækker fra bopæl er ikke person-gatede** — men de er rene stednavne ("Stenstrup, Svendborg")
  uden person-kobling; koblingen (bopæl-factet) er gated. Arketypen udtrækker bevidst kun by-niveau, ikke
  gadeadresser — **dataminimerings-grænsen fastholdes som kontrakt** (archetype §2 er autoritativ; udtræk
  aldrig mere end listen trykker, og aldrig ned på gadeniveau selv hvis en fremtidig liste trykker det
  uden redaktionel beslutning).
- **Identitets-links til/mellem levende:** oprettes frit på evidenslaget men **foldes ikke offentligt** —
  collapse'ns completeness-gate + RLS (collapse-spec §5, søsterspec §8). Uændret. Hele som-af-/diff-fladen
  er **redaktion-only** i v1 og kører på redaktions-datasættet redaktøren allerede ser i fuldt omfang —
  ingen ny dataeksponering.
- **Én ny mekanisme kræves: `red_set_levende(p_person_id bigint, p_levende boolean)`.** Der findes i dag
  ingen redaktionel vej til at flippe flaget (kun `red_set_privat`, schema.sql:817-823; `red_opret_person`
  sætter det kun ved fødslen). Et dødsfald i en ny udgave er den kanoniske udløser, og flippet er en
  **synligheds-eksplosion** (personen + alle fakta bliver offentlige for anon) — det SKAL derfor være en
  eksplicit, versioneret redaktionel handling (change_set, fortrydbar), aldrig en diff-sideeffekt
  (invariant I-fravær, §5.3). Tynd RPC efter `red_set_privat`-skabelonen; `p_levende=false` er
  hovedbrugen, `true` dækker fortryd/fejl.
- **Ændrer volumen noget principielt?** Nej teknisk — gaten er den samme uanset 10 eller 600 levende. Men
  den gør to kendte udeståender mere presserende (uændret ejerskab, blot re-flaget):
  `authenticated`-tieren + samtykke-granularitet (`db-rls.sql` §FREMTID, `database-current-state.md` §3)
  skal designes FØR levende præsens-data vises for medlemmer; og EU-region/behandlingsgrundlag
  (berettiget interesse/foreningsformål for medlemslister) bør noteres i `docs/decisions.md` ved første
  prod-load. Ingen af delene blokerer dette spec — data forbliver redaktion-only indtil da.

## 8. Test

**Core (`packages/core/src/__tests__/`):**
- `presensSnapshot`: source-scoping (kun assertions citeret af U; manuel NULL-source-rettelse udelades);
  komponent med medlem i U → `personId` sat; uden → `null`; familie-afledning via medlemmers
  `person_external_id.source_id` (to-kilde-fixture: stamtavle-familie blandes IKKE ind i præsens-snapshot).
- `presensDiff`: fixtures for hver DiffEntry-art — nyt barn, ny partner, skilt, dødsfald, bopælsskift,
  erhvervs-mængde-diff, fødsels-`uoverensstemmelse`; `ny_paa_listen`/`ikke_genfundet`/`afventer_identitet`;
  partner-nøgle falder tilbage til navnefoldning når partner-stub er ulinket; determinisme (samme input →
  samme diff, stabil sortering).
- Konvergens med identitets-flowet: nyt `samme_som`-link ændrer diff-status fra `ny_paa_listen` til
  `sammenlignet` ved genberegning (ingen stale tilstand — intet er gemt).

**Loader (`load_presens.R`, mod lokal prod-kopi):**
- `source.aar` sat korrekt fra udgave-streng; uparsebar streng → abort med rollback (fail-closed).
- Partner-stubs har `person_external_id`-række med source_id.
- To sekventielle loads (2012-14 + 2015-17-fixture): disjunkte id-rum, ingen kryds-kontaminering af
  familier, `MAX(id)`-append intakt.

**DB (`db-verify.sql`):**
- `red_set_levende`: rolle-gate, change_set + fortryd (flag tilbage), person findes-guard; RLS-effekt:
  efter flip til false bliver personen anon-synlig, efter fortryd usynlig igen (fail-closed begge veje).
- `source.aar`-backfill idempotent.

**App (web + mobile spejlet):**
- "Ændringer"-fanen: kildepar → diff-liste, handlingsknap kalder `red_set_levende` for alle
  komponent-medlemmer via dry-run/LIVE; `afventer_identitet` undertrykker diff og linker til arbejdslisten.
- Som-af-vælgeren på person-siden viser kilde-badges og skifter projektion uden re-fetch.
- Anon-regression: ingen præsens-person, -fakta eller -relation synlig (eksisterende RLS-asserts udvidet
  med præsens-fixture).

## 9. YAGNI / bevidste fravalg

- **Ingen nye kernetabeller / intet snapshot-lag** — evidenslaget + `source.aar` + `person_external_id`
  bærer som-af fuldt ud (§3.4); genovervej kun hvis udgave-kadencen bliver kontinuerlig frem for diskret.
- **Ingen ændringslog-/diff-tabel** — beregnet projektion (§5.1); genovervej ved offentlig diff-visning i
  skala eller redaktionel annotering af enkelt-ændringer.
- **Ingen pre-link-load (flow A)** — append-only-loadet forbliver et rent kilde-aftryk; identitet er
  altid en efterfølgende, reversibel redaktionel beslutning (§4.2).
- **Ingen `family_member`-evidens her** — Problem 2's søsterspec; præsens-serien klarer sig med
  medlems-afledningen (§3.2.3), og kontrakten er forberedt på opgraderingen.
- **Ingen auto-skrivning fra diff** — heller ikke dødsfald: `red_set_levende` er altid et redaktør-klik
  (invariant I-fravær; spejler søsterspec'ets "intet tier udløser en skrivning", §3.4 dér).
- **Ingen offentlig som-af-/diff-visning (v1)** — redaktion-only; offentlig tidsserie venter på
  authenticated-tier + samtykke (og ville kræve server-side projektion, ikke klient-diff).
- **Ingen kæde-topologi alias→alias mellem udgaver** — alle udgave-aliaser peger på samme kanoniske sink
  (§4.2); simplere komponenter, og collapse-kontrakten er upåvirket.
- **Ingen SQL-view for som-af** — projektionen bor i core (redaktions-datasættet er alligevel
  klient-side); et view tilføjes først når en offentlig/serverside-forbruger findes.
- **Ingen håndtering af udgaveløse redaktionelle assertions i som-af** — bevidst udeladt af
  projektionen (§3.2); "nu-visningen" (konklusioner) dækker dem.
- **Ingen gade-/finkornet adresse-udtræk** — dataminimeringsgrænsen fra arketypen fastholdes (§7).

## 10. Berørte filer (forventet)

- `.claude/skills/daa-presens/scripts/load_presens.R` — `source.aar`-parse (fail-closed), `add_extid` på
  partner-stubs (§3.2).
- `.claude/skills/daa-presens/SKILL.md` + `docs/daa-presens-archetype.md` — dokumentér aar-konvention,
  load-then-link-rækkefølgen og at identitets-arbejdslisten er et obligatorisk efter-trin (erstatter
  "pragmatisk i PoC"-forbeholdet, SKILL.md:96-97).
- `schema.sql` + `db-migrations.sql` — `red_set_levende` (ny, efter `red_set_privat`-skabelon,
  schema.sql:817-823) + `source.aar`-backfill for eksisterende rækker. Alt idempotent.
- `db-verify.sql` — asserts (§8): `red_set_levende` inkl. RLS-effekt begge veje; aar-backfill.
- `packages/core/src/presensSnapshot.ts` (ny) + `packages/core/src/presensDiff.ts` (ny) +
  `index.ts`-eksport; genbruger navnefoldningen fra `matchUdgaver.ts` (søsterspec §11).
- `packages/core/src/__tests__/` — snapshot-/diff-/konvergens-tests (§8).
- `web/src/data/redaktionRead.ts` + `mobile/src/data/redaktionRead.ts` — assertion→citation→source-kobling
  for komponent-medlemmer; source-liste m. `aar` (delvist leveret af søsterspec §11).
- `web/src/data/redaktionWrite.ts` + `mobile/src/data/redaktionWrite.ts` — Change-art `setLevende`.
- `web/src/Redaktion.tsx` + `mobile/src/app/redaktion/sammenlign.tsx` — "Ændringer"-fane i
  "Sammenlign udgaver"; `mobile/src/app/redaktion/person/[id].tsx` (+ web) — som-af-vælger + diff-boks.
- Tests: `web/src/data/__tests__/`, `mobile/src/data/__tests__/`.
- Efter godkendelse: notat i `docs/decisions.md` (aar-konvention, load-then-link-beslutning,
  behandlingsgrundlag-note) + status-opdatering i `docs/flere-daa-udgaver-roadmap.md`.
