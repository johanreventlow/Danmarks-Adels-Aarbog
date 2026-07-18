# Koncept — Det levende feed: dynamik, uendelig scroll & hændelseshistorier

**Status:** koncept / idéudvikling (2026-07-18). Ingen kode endnu — dokumentet skal
styre den kommende udvikling (specs + planer pr. fase, jf. §11).
**Gælder:** `mobile/` (eksisterende forsidefeed) **og** `web/` (forsiden, hvis form
stod åben i web-konceptets §9.f — dette dokument lukker den beslutning).
**Bygger på:** feed v3-spec (`docs/superpowers/specs/2026-07-05-folgesvend-v3-feed-drawer-bogmaerker-design.md`),
web-nav-konceptet (`docs/design/2026-07-08-web-navigation-soegning-stamtrae-koncept.md`),
datamodellens invarianter (`claude.md` §invarianter, `datamodel-oversigt.md` §4 + §6).
**Se også:** [`2026-07-18-formidlingskatalog.md`](2026-07-18-formidlingskatalog.md) —
idékatalog over yderligere formidlingsformater der genbruger formidlingslaget herfra.

---

## 1. Problemet i dag (empirisk, ikke antaget)

Feed'en findes og virker — men den er bygget til at være *stillestående*:

1. **Ingen dynamik.** `buildFeed` (`mobile/src/data/buildFeed.ts`) er bevidst 100 %
   deterministisk: ingen `Math.random`, ingen `Date.now`, stabil id-sortering, fast
   interleave-rytme. Samme data → nøjagtig samme feed, besøg efter besøg. Det eneste
   tidslige element er jubilæumskortet (runde 50-år mod `today`-årstallet), som højst
   ændrer sig én gang om året.
2. **Ingen reel "uendelighed".** Hele listen genereres på én gang, trunkeret af
   `FEED_CAPS` (12 portrætter, 4 citater …). Footeren "Henter flere blade fra slægten"
   er dekorativ — der hentes aldrig mere.
3. **Indholdet er genbrug af rå prosa.** Portræt- og citatkort klipper direkte i
   `narrative`-biografierne — tætte opremsninger af datoer og hændelser, skrevet som
   opslagsværk, ikke som minihistorier. Citat-heuristikken (`firstQuotableSentence`,
   første sætning på 40–180 tegn) rammer ofte kluntet — en kendt risiko fra spec'en.
4. **Ingen redaktionel styring.** `FeedOverride`-kroget (pin/hide) er en no-op;
   web-forsiden har ingen highlights-tabel (`web/src/data/home.ts:8` siger det selv).
   Redaktionen kan redigere alle entiteter, men ikke røre feed'en.
5. **Web og mobil deler ikke feed-kode.** Mobil har 9 korttyper; web har en statisk
   forside med 4 kuraterede stamfædre + "månedens gods". To implementeringer, én idé.
6. **Det bedste historiemateriale er ikke struktureret.** Evidenslaget udtrækker
   bevidst kun *rygraden* (fødsel/død/titler/adling …). De daterede gerninger —
   "vidne 1247", "lenshyldning 1580", "immatr. i Rostock" — der ville være de bedste
   minihistorier, ligger kun i den monolitiske prosa. Og `fact`/`historical_event`
   har **intet beskrivelsesfelt**: en hændelse er type + værdi + dato, aldrig en
   fortælling.

Kort sagt: feed'en har en færdig *scene* (korttyper, UI, bogmærker) men mangler
*forestillingen* — levende, skiftende, fortællende indhold.

---

## 2. Målbillede — tre løfter til brugeren

1. **"Feed'en er ny hver gang."** Hver åbning møder brugeren med en frisk
   sammensætning: andre personer, andre vinkler, dagsaktuelle kort ("på denne dag",
   jubilæer). Ikke kaos — en ny *udgave* af det samme redaktionelle blad.
2. **"Jeg kan blive ved med at scrolle."** Feed'en leverer indhold i bidder, så længe
   der er mere at vise. Med ~920 personer × flere kortformer pr. person + hændelser
   er kandidatrummet tusindvis af kort — i praksis uudtømmeligt for en session. Når
   en session faktisk har set alt, siger feed'en det ærligt (arkiv-tonen: aldrig
   foregive mere end der er).
3. **"Kortene fortæller historier."** Oven på de auto-genererede kort kommer et
   voksende lag af **minihistorier**: korte, velskrevne hændelsesfortællinger —
   redaktørskrevne, evt. LLM-assisterede, altid kildeforankrede. Feed'en bliver
   bedre måned for måned i takt med redaktionens arbejde, uden nogensinde at være tom.

**Bærende princip:** feed'en er et **formidlingslag** — et tredje lag oven på de to
eksisterende (substrat = `narrative`-prosa, rygrad = `fact`/`assertion`/`conclusion`).
Det ændrer *intet* i evidensmodellen. Formidlingslaget må gerne være genererbart,
kasserbart og redaktionelt — det er præcis dét, der adskiller det fra evidens.

---

## 3. Indholdsarkitekturen: hændelses-skelet + minihistorier

### 3.1 Svaret på "er fakta udtrukket godt nok?" — nej, og det skal de ikke være

Fristelsen er at udtrække *flere* facts, så feed'en får mere struktur at trække på.
**Det er den forkerte vej.** Evidenslagets selektivitet er en invariant (claude.md
§6: strukturér kun rygrad, forbindelse eller funktion) og en styrke: det holder
påstand/konklusion-apparatet fokuseret på det, der skal kunne modsiges og blåstemples.
Rutine-gerninger fortjener ikke det tunge apparat.

I stedet indføres et **hændelses-skelet** som *letvægts-projektion af prosaen* —
i formidlingslaget, ikke i evidenslaget:

- **`haendelse`** — én dateret hændelse *fundet i* et narrativ. Bærer:
  - subjekt (polymorf: person, family, estate …) + `narrative_id` + tekst-span
    (start/længde i prosaen — så hændelsen altid kan vises i sin kontekst)
  - **fuld fuzzy-dato** (genbruger præcis assertion-mønsteret: `date_min/max`,
    `date_qualifier`, `date_raw` — modellen findes allerede og er stærk)
  - **`klausul`** — det ordrette prosa-uddrag ("1580 deltog han i lenshyldningen …")
  - `kategori` (let vokabular: embede, rejse, uddannelse, krig, ejendom, kirke,
    personligt, …) — til rytme/filtrering, ikke til evidens
  - `feed_status`: `ingen` · `kandidat` · `interessant` · `skjult` (redaktørens dom)
  - evt. `fact_id`/`relation_id` hvis hændelsen falder sammen med et allerede
    struktureret faktum (dedup: rygrads-hændelser peger på deres fact i stedet for
    at duplikere dato-data)
- **Produceres af et offline LLM-pass** over de bevarede narrativer (samme mønster
  som extraction-pipelinen: deterministisk segmentering + LLM pr. post + validering
  + R-load). Fordi tabellen er en projektion, kan passet **gen-køres og forbedres**
  uden datatab — redaktørens `feed_status` og tilknyttede historier overlever via
  stabil nøgle (narrativ + span/dato).
- **Ikke evidens.** Ingen assertion/conclusion oven på en `haendelse`. Vil nogen
  bestride den, retter man prosaen/faktaene — hændelsen følger med ved regenerering.

Dermed: *evidens-udtrækket er godt nok som det er.* Det, der manglede, var et
**fuldt** dateret hændelseskatalog — og det hører hjemme som projektion, ikke rygrad.

### 3.2 Minihistorien — feed'ens flagskibs-indhold

**`story`** — en kort, redaktionelt formidlet hændelsesfortælling:

- subjekt (polymorf) + valgfrit anker: `haendelse_id` (typisk) eller `fact_id` /
  `relation_id` / `historical_event_id` (rygrads-hændelser) — eller intet anker
  (fri historie om personen/godset)
- `titel` (valgfri, kort) + `tekst` (~40–90 ord; ét kort, én pointe)
- dato-felter (kopieret fra ankeret eller sat manuelt, samme fuzzy-mønster)
- `status`: `kladde` → `klar` → `publiceret` (kun `publiceret` når i feed) → `arkiveret`
- `oprindelse`: `redaktoer` | `llm_assisteret` (+ ved LLM: model, promptversion,
  genereringstidspunkt — proveniens ligesom konklusioner har det)
- `skabt_af`, `godkendt_af/naar`, `privat`
- **`story_kilde`** (story → source + side, 1..n): historien viser altid sine kilder
  — kortet kan bære en diskret "efter DAA 1939, s. 112"-fod. Transparens er tonen.

Kun *interessante* hændelser får historier — redaktøren vælger. Alt andet kan stadig
optræde i feed'en som rå **arkivkort** (§5), så feed'en aldrig afhænger af
redaktionel kapacitet.

**Afgrænsning mod eksisterende entiteter:** `story` er *ikke* et `narrative`
(narrativ = ordret kildeprosa fra en source; story = original redaktionel tekst uden
kilde-ophav) og *ikke* en `note` (note = internt arbejdsredskab). Egen tabel er
ærligst. Den er heller ikke en `suggestion` — men LLM-kladder genbruger
suggestion-*mønsteret*: aldrig direkte til publikum, altid gennem godkendelse.

### 3.3 LLM-knappen — "Foreslå historie"

I redaktionsfladen, ud for en hændelse (eller en gruppe af samhørende hændelser):

1. **Kontekst samles server-side:** personens rygrad (visning-cache), hændelsens
   klausul(er) fra *alle* kilder der omtaler den (på tværs af DAA-udgaver — matchet
   pragmatisk på subjekt + kategori + dato-overlap), tilknyttede assertions med
   `citation.citat_tekst`, og det omgivende prosa-afsnit.
2. **Claude kaldes** (Supabase Edge Function, se §8) med stramme instruktioner:
   *kun* oplysninger fra den leverede kontekst, 40–90 ord, dansk, arkivtone (rolig,
   redaktionel — matcher §8.5 i web-konceptet), datousikkerhed bevares sprogligt
   ("formentlig", "omkring"), modstrid mellem kilder nævnes eller undgås — aldrig
   glattes ud. Output: forslag til `titel` + `tekst` + hvilke kilder der er brugt.
3. **Resultatet lander som `story`-kladde** (`oprindelse='llm_assisteret'`).
   Redaktøren redigerer, forkaster eller godkender. **Intet LLM-output når publikum
   uden menneskelig godkendelse** — samme princip som evidensmodellens blåstempling.

Knappen findes også i batch-form (senere): "generér kladder til alle hændelser
markeret *interessant*" — så redaktionen kan arbejde som redigerende, ikke skrivende.

### 3.4 Skitse: nye tabeller (additive — ingen ændring af eksisterende)

```
haendelse    id, subjekt_type, subjekt_id, narrative_id→narrative, span_start, span_laengde,
             date_min, date_max, date_qualifier, date_raw, kategori, klausul,
             feed_status, fact_id?→fact, relation_id?→relation, gruppe_id?
story        id, subjekt_type, subjekt_id, haendelse_id?→haendelse, fact_id?, relation_id?,
             historical_event_id?, titel?, tekst, date_min?, date_max?, date_qualifier?,
             date_raw?, status, oprindelse, llm_model?, llm_promptversion?, llm_naar?,
             skabt_af, godkendt_af?, godkendt_naar?, privat
story_kilde  story_id→story, source_id→source, side?
feed_pin     id, kort_noegle (stabil kort-id, fx 'story:<id>' / 'portrait:<personId>'),
             handling ('pin'|'skjul'), gaelder_fra?, gaelder_til?, oprettet_af, oprettet_naar
```

Forhold til invarianterne: alle fire er **formidlingslag** (som `person.visning_*`-
cachen): projektioner/redaktionelt indhold der aldrig konkurrerer med påstand/
konklusion. `haendelse` er regenererbar; `story` er redaktionel og versioneres som
øvrige redaktions-writes. RLS: publikum ser kun `story.status='publiceret'` og
`privat=false` — og **kun om afdøde** (§9). Vokabular for `kategori`/`status`/
`oprindelse` går i `vocab` (invariant #9).

---

## 4. Feed-motoren 2.0 — fra deterministisk liste til levende strøm

Kernen forbliver en **ren funktion** — dynamikken kommer fra ét injiceret seed, ikke
fra spredt tilfældighed. Determinisme bevares dermed *for test* (samme seed → samme
feed) samtidig med at brugeren møder variation (nyt seed pr. besøg).

### 4.1 Pipeline: pool → score → sampling → rytme

1. **Kandidat-pool.** Alle mulige kort genereres som *kandidater* (uden caps):
   hver person med bio er en portræt-kandidat, hver publiceret story et
   historie-kandidatkort, hvert gods, våben, embede, ægtepar, hændelse-med-dato-
   match … Poolen er tusindvis af kort.
2. **Scoring.** Hver kandidat får en prioritet af rene, forklarlige signaler:
   - **Redaktionelt:** `feed_pin` (pin = top, skjul = ude); `story`-kort over
     auto-kort; nyligt publicerede stories boostes ("nyt i arkivet" — ægte denne gang).
   - **Tidsligt:** "på denne dag/måned"-match (§4.4) og jubilæer boostes kraftigt
     den relevante dag.
   - **Personligt (let):** `meId` sat → slægtskabskort + kort om nære aner boostes;
     bogmærkede personers hændelser boostes. Alt klientside — ingen server-profil.
   - **Friskhed:** set-hukommelse (§4.5) trækker nyligt viste kort ned.
   - **Kvalitet:** kort med billede/medie over kort uden; citatkort kun når
     klausulen består heuristikken.
3. **Seeded sampling.** En seedet PRNG (fx mulberry32 over FNV-1a — `stableHash`
   findes allerede i `feedHash.ts`) trækker vægtet *uden tilbagelægning* fra poolen.
   Seed = `hash(dagsdato + sessionsnonce)` injiceret via `FeedOptions` (aldrig
   `Math.random` inde i motoren).
4. **Rytme-regler** (erstatter det faste interleave med *begrænsninger* frem for
   fast rækkefølge): aldrig to kort af samme type i træk; samme person højst én gang
   pr. ~15 kort; mindst ét "tungt" kort (story/portræt) pr. skærmfuld; citat/våben/
   samle som krydderi, ikke hovedret. Reglerne håndhæves i samplingen (afvis træk,
   træk igen) — deterministisk givet seedet.

### 4.2 Strøm-API: rigtig uendelig scroll

`buildFeed` afløses af en **lazy generator** i den delte pakke:

```ts
const stream = createFeedStream(model, aux, {
  seed, today, meId, focusId, pins, seenWeights,
});
stream.next(12) // → FeedCard[] — næste side, deterministisk givet seed+historik
```

- Mobil: `FlatList.onEndReached` → `stream.next(n)`. Footeren "Henter flere blade"
  bliver **ægte** (spinner mens næste bid beregnes/appendes).
- Web: `IntersectionObserver`-sentinel nederst → samme kald.
- Poolen er endelig; når den er tom for en session, leverer strømmen et ærligt
  **slutkort** ("Du har mødt hele slægten i dag — udforsk registeret / kom igen i
  morgen"). Med pool-størrelsen sker det reelt aldrig i en normal session — men
  ærligheden er en designværdi (web-koncept §8.4).
- Alt kører stadig på den allerede indlæste model i hukommelsen — ingen nye
  netværkskald pr. side. "Paginering" er beregnings-dosering + render-dosering,
  hvilket er præcis hvad UI'et behøver.

### 4.3 Seed-politik: ny sammensætning pr. besøg, forankret i dagen

- **Sessions-seed** (ny ved hver app-åbning/side-load) styrer sammensætning og
  rækkefølge → "feed'en er ny hver gang".
- **Dagsdatoen** (ikke seedet) styrer de tidslige kort → alle brugere ser samme
  "på denne dag"- og jubilæumsindhold samme dag (delt samtaleemne, à la en avis).
- Pull-to-refresh (mobil) / opdatér (web) giver nyt seed → ny blanding med det samme.

### 4.4 Tidslige kort — dynamik næsten gratis

Datomodellen er allerede rig nok (`date_min/max` på assertions; samme mønster på
`haendelse`) til dagsaktuelle kort:

- **"På denne dag"** — hændelser/rygradsfakta hvis dato matcher dagens dag+måned,
  på tværs af århundreder: *"18. juli 1691 — Conrad Reventlow udnævnes til
  storkansler."* Skifter hver dag af sig selv; det stærkeste enkelte dynamik-greb.
- **"I denne måned"** — blødere fallback når dagen er tynd (fuzzy datoer med kendt
  måned).
- **Jubilæer** — beholdes, men udvides fra kun-årstal til dag-præcise mærkedage
  (300-året for et bryllup, på dagen).
- **"Dagens person"** — dagligt roterende fremhævning: `hash(dagsdato) % kandidater`
  blandt personer med bio/portræt. Én pr. dag, øverst-ish, delt af alle.

Kræver at publikums-load henter konklusionsdatoer (i dag hentes facts kun til geo)
— en lille load-udvidelse, ingen skemaændring.

### 4.5 Set-hukommelse (friskhed uden server)

Klienten husker lokalt (AsyncStorage/localStorage) de seneste ~300 viste kort-nøgler
med tidsstempel. Scoringen straffer gensyn med aftagende vægt (fx halvering pr. 3
dage). Effekt: i morgen ser man overvejende *andet* indhold; om to uger må en god
historie gerne komme igen. Ingen serverside-tracking, intet GDPR-aftryk.

### 4.6 Determinisme & test

- Motoren forbliver ren: seed, dato, pins, seen-vægte injiceres. Samme input →
  samme strøm. Unit-tests arver v3-spec'ens tilgang (fixtures + dyb lighed).
- Nye test-akser: rytme-invarianter (aldrig to ens naboer, person-afstand),
  vægtnings-effekt (pin → først; skjul → aldrig; set → senere), strøm-stabilitet
  (next(5)+next(5) ≡ next(10)), tidslige kort mod injiceret dato.

---

## 5. Kort-kataloget (eksisterende 9 + nye)

| Kort | Status | Kilde | Bemærkning |
|---|---|---|---|
| `portrait` | beholdes | narrative-bio | uændret rolle; bedre spacing via rytme-regler |
| `citat` | **erstattes gradvist** | bio-heuristik → `haendelse.klausul` | klausuler er reelle citerbare enheder; heuristikken beholdes kun som fallback |
| `gods`, `vaaben`, `forbundet`, `embede`, `slaegt`, `samle` | beholdes | uændret | `samle` bliver også slutkort (§4.2) |
| `jubilaeum` | udvides | rygradsdatoer | dag-præcise mærkedage (§4.4) |
| **`historie`** | **ny — flagskib** | `story` (publiceret) | titel + tekst + dato + kildefod + person-link; gembar |
| **`paadenne dag`** | ny | haendelse/fact-datoer | dagligt skiftende (§4.4) |
| **`dagensperson`** | ny | dagsdato-hash | én pr. dag, delt af alle |
| **`arkiv`** | ny | `haendelse` (kandidat/interessant, uden story) | ærligt råt: *"Årbogen skriver: '…'"* — verbatim klausul + dato + kilde. Arkiv-æstetik gør råheden til en styrke |
| **`medie`** | ny (når data findes) | `media`/`media_variant` | portræt/maleri med billedtekst — thumbnails indlæses allerede |

Alle nye kort med `personId` er bogmærkbare (eksisterende kontrakt genbruges).
`arkiv`-kortet er broen mellem "intet redaktionelt indhold endnu" og "fuldt
kurateret": feed'en er hændelses-drevet fra dag ét, og stories opgraderer gradvist
de bedste hændelser fra `arkiv`-kort til `historie`-kort.

---

## 6. Web-forsiden — beslutningen i web-konceptets §9.f lukkes

**Forsiden bliver en kombination (A + B): faste indgange øverst, feed nedenunder.**

1. **Øverst (bevares fra i dag):** søge-hero ("Find din vej ind i slægten") +
   "Redaktionen foreslår · begynd her". Startpersonerne skifter fra
   `curatedFounders`-heuristikken til `feed_pin`-styrede valg, når tabellen findes
   (heuristikken forbliver fallback).
2. **Derunder: feed-strømmen** — samme motor, samme kort-katalog som mobil, fra den
   delte pakke. Én kolonne, maks-bredde ~680 px, centreret: redaktionel ro, ikke
   masonry-dashboard. Uendelig scroll via sentinel.
3. **Delt kode:** feed-motoren + korttyper flyttes til `packages/` (naturlig
   fortsættelse af `@daa/core`-mønstret fra review 27 — enten ind i core eller som
   `@daa/feed` med core som afhængighed; kortenes *views* forbliver platformspecifikke).
   Web-kort-views bygges i webbens eksisterende idiom (tokens fra `theme.ts`).

Dermed forsvinder web/mobil-splittelsen: én motor, én indholdsmodel, to skind.

---

## 7. Redaktionsflowet — fra fakta-kort til historieværksted

Ny flade i redaktionen (web + mobil, genbruger eksisterende editor-mønstre):

1. **Hændelses-tidslinjen** på personens redaktionsside: alle `haendelse`-rækker
   kronologisk, hver med dato + klausul + kategori + link til prosa-konteksten
   (span-highlight i narrativet). Rygradsfakta flettes ind (via `fact_id`-koblingen)
   så tidslinjen er komplet.
2. **Markér:** ét tryk sætter `feed_status` — `interessant` (godt feed-stof),
   `skjult` (aldrig i feed). Umarkerede er `kandidat` (må vises som `arkiv`-kort).
3. **Skriv:** "Ny historie" ud for en hændelse åbner story-editoren (titel, tekst,
   dato forudfyldt fra ankeret, kilder forudfyldt fra hændelsens narrativ-source).
4. **Foreslå (LLM):** knappen fra §3.3 — kladde ind i samme editor, redaktøren
   redigerer og publicerer. Dry-run/LIVE-toggle og versionshistorik gælder som for
   alle andre redaktions-writes.
5. **Feed-styring:** en enkel "Feed"-side i redaktionen: pin/skjul kort
   (`feed_pin`), se publicerede stories, se hvad der er pinnet netop nu. Ikke et
   CMS — tre handlinger: pin, skjul, afpublicér.

Redaktørens arbejde er dermed **kuraterende** (markér + redigér), ikke afskrivende.

---

## 8. LLM-integrationen — teknisk ramme

- **Placering:** Supabase **Edge Function** (`foreslaa-historie`) — projektets
  første. Auth-gated til redaktørrollen (JWT + rolle-tjek som `red_*`-RPC'erne);
  API-nøglen bor i funktionens secrets, aldrig i klienten. Publikums-appen kan
  **ikke** kalde den — der genereres aldrig live i feed'en (omkostning, kvalitet,
  kontrol).
- **Model:** Claude Sonnet som default, Opus til svære poster — samme valg og
  fallback-mønster som extraction-pipelinen, så projektet har én LLM-konvention.
- **Kontrakt:** input = hændelses-id (eller gruppe-id); funktionen samler kontekst
  server-side (§3.3) — klienten sender aldrig selv tekst ind (ingen prompt-
  injektion fra klientdata, konsistent kontekst). Output = struktureret JSON
  (titel, tekst, brugte kilder, usikkerhedsmarkeringer) valideret før den gemmes
  som kladde.
- **Proveniens:** model-id, promptversion og tidspunkt gemmes på storyen. Prompten
  versioneres i repoet (som `references/extract-prompt.md`-mønstret).
- **GDPR:** funktionen afviser subjekter med `levende=true`. Kun afdødes data
  sendes til LLM'en.

---

## 9. Privatliv & ærlighed (feed-invarianter)

1. **Feed'en viser kun afdøde.** `person.levende=false` er adgangsbillet til alle
   personbårne kort. (Levende med samtykke er en *senere* beslutning — ikke nu.)
2. **`privat`-flag respekteres** hele vejen (narrative → haendelse → story arver
   skjulthed; RLS håndhæver, klienten filtrerer som defense-in-depth).
3. **Intet LLM-indhold uden menneskelig godkendelse.** `status='publiceret'` kan
   kun sættes af en redaktør; `oprindelse` er synlig i redaktionen (og kan, hvis
   foreningen ønsker det, vises diskret på kortet — åben beslutning §11.○d).
4. **Citater er citater.** `arkiv`-kort viser verbatim tekst *som* citat med kilde.
   Stories omskriver — men aldrig ud over kildernes indhold, og altid med kildefod.
5. **Ingen fabrikerede tidsstempler** ("nyt!" kun når noget faktisk er nyt —
   stories har ægte publiceringsdatoer, så "Nyt i arkivet" bliver ærligt).
6. **Slutkortet er ærligt** — feed'en foregiver aldrig uendelighed den ikke har.

---

## 10. Faser (styrer implementeringen — én spec + plan pr. fase)

### Fase 1 — Dynamik & uendelig scroll (ren klient, ingen backend-ændringer)
*Spec: [`../superpowers/specs/2026-07-18-levende-feed-fase1-design.md`](../superpowers/specs/2026-07-18-levende-feed-fase1-design.md)
(lukker samtidig ○a: ny pakke `@daa/feed`).*
Feed-motoren omskrives til pool → score → seeded sampling → rytme + strøm-API
(§4.1–4.3, 4.5–4.6) i en delt pakke; mobil-UI kobles på ægte paginering; web får
feed-MVP under den eksisterende hero (§6); set-hukommelse; "på denne dag"/udvidede
jubilæer i det omfang datoer allerede er i klienten (dagens person + rygradsdatoer;
load-udvidelse med konklusionsdatoer hører også her).
*Leverer løfte 1 + 2 straks, med eksisterende indhold.*

**Status 2026-07-18:** Implementeret og regressionsdækket; efterfølgende fase 1-reviewfund
er rettet på fase 2-grenen.

### Fase 2 — Hændelses-skelettet & arkivkort (backend additivt + offline pass)
*Spec: [`../superpowers/specs/2026-07-18-levende-feed-fase2-design.md`](../superpowers/specs/2026-07-18-levende-feed-fase2-design.md).*
`haendelse`-tabellen + offline LLM-pass over narrativerne (pipeline-mønster
genbruges) + RLS + load ind i klienten; `arkiv`- og forbedrede `paadenne dag`-kort;
citat-kortet skifter kilde til klausuler. Redaktionens hændelses-tidslinje (læse +
markér `feed_status`).
*Feed'en bliver hændelses-drevet og langt rigere — stadig uden krav om redaktionel skrivning.*

**Status 2026-07-18:** Implementeret i kode og valideret mod lokale kopi-databaser.
Prod-migrationen og den første prod-pipelinekørsel er ikke udført og kræver fortsat den
gatede deployprocedure.

### Fase 3 — Minihistorier & redaktionel styring
`story`/`story_kilde`/`feed_pin`-tabellerne + story-editor + pin/skjul-UI +
`historie`-kortet + web-startpersoner fra pins. `FeedOverride`-kroget fra v3-spec'en
realiseres endelig (pins/hides føder motoren).
*Leverer løfte 3 — det kuraterede lag.*

### Fase 4 — LLM-assist
Edge Function + "Foreslå historie"-knap + proveniens + evt. batch-kladder +
hændelsesgruppering på tværs af udgaver.
*Skalerer redaktionens kapacitet.*

Rækkefølgen er bevidst: hver fase leverer selvstændig brugerværdi, og ingen fase
blokerer på redaktionelt indhold for at virke.

---

## 11. Beslutninger — foreslået ✓ / åbent ○

- **✓a. Formidlingslag, ikke mere evidens.** Hændelser og stories er projektioner/
  redaktionelt indhold oven på uændret evidensmodel (§3.1). Fakta-udtrækket
  udvides *ikke*.
- **✓b. Ét seed, ren motor.** Al variation kommer fra injiceret seed + dagsdato;
  motoren forbliver deterministisk og testbar (§4.6).
- **✓c. Sessions-seed + dags-forankrede tidskort** (§4.3). Ny blanding pr. besøg;
  fælles dagsindhold for alle.
- **✓d. Arkivkort må vises uden redaktionel godkendelse** (verbatim citat m. kilde;
  `feed_status='skjult'` er opt-out). Alternativet (kun godkendt indhold) ville gøre
  feed'en afhængig af redaktionel kapacitet fra dag ét. *(Kan strammes hvis
  kvaliteten skuffer — beslutningen er reversibel.)*
- **✓e. Web-forsiden = faste indgange + feed** (§6); delt motor i `packages/`.
- **✓f. LLM kun redaktionelt, kun afdøde, aldrig live** (§8).
- **○a. `@daa/core` vs. ny `@daa/feed`-pakke** — afgøres ved fase 1-spec (afhænger
  af hvor meget aux-logik der skal med).
- **○b. Hændelses-gruppering på tværs af udgaver** — pragmatisk dato+kategori-match
  eller genbrug af `samme_som`-mønstret? Afgøres ved fase 4.
- **○c. Skal `historie`-kort vise oprindelse** ("skrevet med AI-assistance")?
  Foreningens politik-beslutning — teknisk understøttet uanset.
- **○d. Levende personer med samtykke i feed'en** — udskudt; kræver
  samtykke-granularitet fra datamodellens §7 først.
- **○e. Push/notifikation** ("på denne dag i din slægt") — naturlig forlængelse af
  §4.4, men eget spor (permissions, kadence).

---

## 12. Ikke-mål

- **Ingen ændringer i evidensmodellen** (fact/assertion/conclusion/citation urørt).
- **Ingen server-side personalisering/profiler** — al personalisering er klientside
  og let (meId, bogmærker, set-hukommelse).
- **Ingen live LLM-generering i publikums-appen** — nogensinde, i dette koncept.
- **Ingen social mekanik** (likes, kommentarer, deling-tracking) — feed'en er et
  redaktionelt blad, ikke et socialt netværk.
- **Ikke multi-slægt endnu** — motoren parametriseres naturligt af model/aux, men
  slægts-skift er sit eget spor (hardkodet Reventlow accepteres fortsat i PoC).
- **Video/lyd-kort, kort-/geo-kort i feed** — mulige senere korttyper; ikke i
  faserne her.
