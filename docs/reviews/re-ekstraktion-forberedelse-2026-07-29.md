# Re-ekstraktion af DAA 1939 — forberedelse

**Dato:** 2026-07-29 · **Status:** forberedelse, ikke påbegyndt
**Formål:** afgøre modelvalg og fastlægge hvad der SKAL udtrækkes, så vi undgår flere genudtræk.

## Del 1 — Modelvalg

### Hvad LLM-trinnet faktisk laver

Kun **ét** af pipelinens fem trin bruger en model (`SKILL.md` ③). Alt andet er deterministisk:

| | |
|---|---|
| Narrativen | **ikke** LLM — prosaen klippes ordret af `segment.py` |
| `boern` | **ikke** LLM — parses deterministisk; LLM missede den systematisk |
| `date_min`/`date_max` | **ikke** LLM — udledes af `date_raw` i trin ④ |
| `record_key` | **ikke** LLM — kommer nu fra identitetsregisteret |
| **Struktureret rygrad pr. post** | ← modellens eneste opgave |

Konteksten er **én post ad gangen**. Det er ikke en lang-kontekst-opgave; det er mange små,
skema-bundne opgaver med to hårde krav: `date_raw` og `kilde_span` skal stå **ordret** i prosaen
(R7 fejler ellers), og klassifikationen skal ramme rigtigt.

### Præcedens der peger direkte på svaret

`docs/decisions.md` (2026-06-16) afgjorde samme spørgsmål for Claude-tierne:

> Sonnet til stamtavle-udtræk (klarer tredjeparts-fælder, dense biografier). Haiku testet: rammer
> genealogisk rygrad tæt, men **taber på klassifikations-nuancer (karriere vs embede)** og er flakier.

Det er ikke et generelt "større er bedre". Det er en **målt** observation om præcis den dimension
denne opgave er svær på: at skelne hvad der er rygrad fra hvad der er biografisk staffage.

### Anbefaling

**`gpt-5.6-terra` på max effort.**

- Opgavens hårde del er *klassifikation*, ikke volumen eller lang kontekst — og det er netop dér den
  billige tier målt tabte sidst.
- **Frarådes: `luna`.** Ikke fordi den er svag, men fordi projektet allerede har målt at
  tilsvarende tier fejler på denne ene dimension. At gentage forsøget uden ny information ville være
  at genopdage et kendt resultat.
- **`sol` er formentlig overkill** til langt de fleste poster — men se eskalering nedenfor.

### Eskalering frem for ét valg

Pipelinen har allerede et to-tier-mønster (`escalate_merge.py`, "Opus-eskalering af flaggede").
Genbrug det:

```
terra (max effort)  →  alle poster
   ↓ flagget af valideringen (R1-R8, lav faktatæthed, tvetydig klassifikation)
sol (max effort)    →  kun de flaggede
```

Det holder omkostningen nede uden at ofre de svære poster — og "flagget" er allerede defineret af
den eksisterende validering, så der skal ikke opfindes et nyt kriterium.

### Afgør det med en kalibrering, ikke med et gæt

`facit_1939.py` findes allerede og rapporterer **kun tal** (PII-disciplin). Kør derfor:

1. Vælg ~30 poster stratificeret: 10 tætte biografier · 10 med flere ægteskaber · 10 fra
   oversigtsprosaen (hvor fejlen skete sidst).
2. Udtræk med **terra max** og **luna max** mod samme prompt.
3. Scor mod et håndlavet facit på de dimensioner der fejlede: er posten en person eller en omtale ·
   er ægtefællen dekomponeret · er `date_raw` ordret · rammer titel-vs-embede.
4. Vælg på evidens. Beslutningen skrives i `docs/decisions.md` som den forrige.

**Omkostningen ved kalibreringen er ~30 kald.** Omkostningen ved at vælge forkert er et helt
genudtræk — det er den asymmetri der afgør at kalibreringen skal køres.

---

## Del 2 — Hvad SKAL udtrækkes

> ⚠ **Rettelse (2026-07-29, efter at have læst kontrakten frem for kun databasen).**
> Første udgave af dette afsnit opstillede ti krav som om kontrakten manglede dem. Det var forkert.
>
> **DAA 1939 blev aldrig udtrukket med `extraction-schema.json`.** Artefakternes nøgler er en helt
> anden, ad hoc-form:
>
> ```
> 2018-20:  facts[] · embeder[] · begivenheder[] · tilnavn · boern    ← kontrakten
> 1939:     foedsel{} · doed{} · erhverv[] · _ctx · lokal_id · flags  ← noget andet
> ```
>
> 1939-artefaktet har **intet `facts`-array, intet `embeder`, intet `begivenheder`**. Derfor mangler
> otte faktatyper: der var ingen kasse at lægge dem i. Modellen overså dem ikke.
>
> **Konsekvens: en re-ekstraktion med den faktiske frosne kontrakt retter K1, K2 og størstedelen af
> K3 uden en eneste ny regel.** Kun tre ting manglede reelt i skemaet — de er nu tilføjet (K4b, K9,
> K10 nedenfor).
>
> Læringen er metodisk: jeg målte hvad databasen manglede og sluttede tilbage til kontrakten.
> Kontrakten skulle have været læst først.

Målt mod prod 2026-07-29. Sammenligningsgrundlaget er DAA 2018-20, som **er** udtrukket med den
frosne kontrakt og fungerer.

### K1 — Faktatyper 1939 slet ikke har *(rettes af kontrakten alene)*

| Faktatype | 2018-20 | **1939** |
|---|---|---|
| dåb | 237 | **0** |
| dekoration | 131 | **0** |
| floruit | 105 | **0** |
| dødsårsag | 21 | **0** |
| klosterindgang | 8 | **0** |
| tilnavn | 5 | **0** |
| adling | 4 | **0** |
| overhoved | 4 | **0** |

Otte typer, nul forekomster. Bogen fra 1939 *indeholder* dåbsdatoer og dekorationer — de blev bare
ikke udtrukket. **Kontrakten skal kræve dem eksplicit**, ikke bare tillade dem.

### K2 — Embeder og hverv: 1939 har ingen *(rettes af kontrakten alene)*

```
personer med embede-relation:   2018-20: 150      1939: 0
```

506 embede-relationer i alt, **ingen** fra 1939. Det er den største enkeltmangel, og den rammer
netop de personer bogen skriver mest om.

### K3 — Ægtefæller: kun et navn *(delvist i kontrakten: `partner_foedsel`/`_daab`/`_doed` fandtes, men blev brugt 0 %)*

```
snit fakta pr. ægtefælle:   2018-20: 2,62      1939: 1,00
                            (fødsel 237/331)   (fødsel 0/296)
```

1939-ægtefæller har **præcis ét faktum** — navnet. Ingen datoer, intet køn, ingen steder. 2018-20
viser at det kan lade sig gøre. Se også omtale-journal-planen: ægtefællens felter skal kunne rettes,
og det forudsætter at de findes.

### K4 — Køn *(reel mangel i skemaet — nu tilføjet)*

625 personer uden `koen`, alle ægtefæller. Årsagen er konkret: skemaet havde `koen` på posten, men
**intet `partner_koen`** på ægteskabet. Gift-ind ægtefæller har ingen egen post, så der fandtes
bogstavelig talt intet felt at skrive deres køn i.

**Tilføjet 2026-07-29:** `partner_koen` + `partner_koen_kilde`.

### K5 — Navne må ikke være sætninger

112 af 604 ægtefæller (18,5 %) har gods, titel eller parentes inde i navnefeltet:

> `General af Infanteriet, Guvernør i Kbhvn. Nicolai Maximilian Friherre Gersdorff til Baroniet Marselisborg og Gross-Nordsee`

Navn · titel · gods er **tre** felter. Målt konsekvens: et titel-præfiks sænker
navnesammenligningen fra ~0,86 til 0,54 og forhindrer tværudgave-match.

### K6 — Godser som relationer, ikke som tekst

85 ægtefæller har gods i navnet og **nul** godsrelationer. Af de godser: 25 findes allerede i
`estate`, 33 delvist, **52 kendes slet ikke**. Bogen navngiver dem; udtrækket taber dem.

### K7 — Steder

864 steder findes, men kun **3 har koordinater**. Kontrakten bør kræve stednavnet ordret som skrevet
(så det kan geokodes senere) — ikke normaliseret af modellen.

### K8 — Hændelser: laget er tomt

`haendelse`-tabellen har **0 rækker** for begge udgaver. Formidlingslaget er bygget, men aldrig
fyldt. Det er et selvstændigt LLM-pass (`/daa-haendelser`) og hører ikke nødvendigvis i denne
re-ekstraktion — men beslutningen bør tages bevidst, ikke ved forglemmelse.

### K9 — Omtaler må ikke blive personer *(reel mangel — nu tilføjet)*

Den dyreste fejl sidst: oversigtsprosa gav ~30 spøgelsesposter. Modellen *så* det selv — den
skrev `_ctx.gruppe = "narrativ-kæde (…)"`. **Kontrakten skal kræve et eksplicit felt**
(`er_omtale: true`) frem for at lade det ligge i en fritekst-etiket, så valideringen kan gate på
det i stedet for at nogen skal opdage det bagefter.

### K10 — Modellen skal deklarere sin egen usikkerhed *(reel mangel — nu tilføjet)*

Hvor et felt beror på modellens skøn frem for bogens ord, skal det fremgå:

- `ordinal_kilde: "bog" | "udledt"` — bogen skriver `1°/2°` eller vi tæller
- `koen_kilde: "bog" | "udledt"` — står der "datteren", eller gætter vi på fornavnet

Så kan fail-closed-gates bygges på det. Uden det kan vi ikke skelne et faktum fra et skøn — og det
var præcis dét der gjorde ægteskabsnummeret ubrugeligt som nøgle.

---

## Del 3 — Rækkefølge

1. ~~**Opdatér kontrakten**~~ ✅ **udført 2026-07-29.** `extraction-schema.json` fik `er_omtale`,
   `koen_kilde`, `ordinal_kilde`, `partner_koen`, `partner_koen_kilde`, `partner_titel`,
   `partner_godser` + skærpet `navn`-beskrivelse. `extract-prompt.md` fik en blokerende
   `er_omtale`-sektion, krav om ægtefælle-dekomponering og skøn-mærkning; `prompt-version` bumpet
   til `2026-07-29`. K1-K3 kræver ingen kontraktændring — kun at kontrakten faktisk bruges.
2. **Kalibrér** (Del 1) på ~30 stratificerede poster. Skriv beslutningen i `decisions.md`.
3. **Kør fuldt udtræk** med den valgte model + eskalering.
4. **Afstem mod identitetsregisteret** — `reconcile()` FORESLÅR hvilke poster der er de samme.
   Tvetydige stopper og kræver menneskelig afgørelse. Eksakte hit hvor en anden aktiv post deler
   `lokal_id` inden for driftvinduet (10 sider) demoteres OGSÅ til tvetydige — perturbationstesten
   viste at et eksakt hit under sidedrift kan være en nabos nøgle (nabo-vagten, Codex-review
   2026-07-29 fund 2). Udestående proces-trin efter reconcile: menneskelig afgørelse af tvetydige,
   writeback af id til artefaktet, håndtering af nye poster og bortfaldne.
5. **Load** — ⚠ **UAFKLARET BLOCKER (Codex-review 2026-07-29 fund 3):** loaderen kan i dag kun
   *append* (opretter ny source + NYE personer; samme import_key rammer source-unikheden) eller
   *reset* (truncater bl.a. relation, person_external_id, person, source). Ingen af delene fører
   redaktionelt arbejde over: de 613 samme_som-match hænger på person-id, og kun
   `import_korrektion` har replay. At record_key følger med i artefaktet gør en fremtidig upsert
   MULIG — men upsert-/replay-laget findes ikke og skal designes og bygges FØR load
   (jf. docs/superpowers/plans/2026-07-02-daa-reimport-fire-etaper.md om differentiel reload).

### Trin 3½ — lokal_id fra segmenteringen (status 2026-07-30)

**2018-20-sporet: løst.** `segment.py` komponerer nu `lokal_id = {linje}.{nr_label}`
(fx `I.15a`) — begge komponenter er TRYKTE (gren-label + løbenummer), bogens egen
unikke nøgle, og en overset post forskyder ingen naboers identitet. Mangler
linje-konteksten sættes `None`, og R9-gaten blokerer posten.

**1939-sporet: design udestår — og det naive skema er forkastet på måling.**
1939 har ingen trykt gren-label; kandidaten `G{gruppeindeks}.{trykt nr}` blev målt
mod artefaktet: (gruppe, orig_nr) er ganske vist unik (476/515 dækning, 0 dubletter),
men gruppeindekset er BEREGNET, og grupperne er små — **127 nabogruppe-par deler
både trykt nr og side**. Ét forskudt gruppeindeks (en overset/sammenlagt gruppe)
ville altså give tavse forkerte match i stor stil — samme fejl som positions-
lokatoren, bare på gruppeniveau. Kravet til 1939-skemaet er derfor en TRYKT
gruppe-forankring (fx normaliseret gruppeoverskrift/stamfar-linje + trykt nr), og
det designes som del af re-segmenteringen — med perturbationstesten som gate FØR
skemaet vælges. De 39 unummererede poster (stamfædre m.fl.) skal have egen løsning.
Om-nøglingen af registeret (record_key → nyt skema, afstem_lokator-mønstret
generaliseret til begge lokator-komponenter) sker først når den nye segmentering
findes og skemaet har bestået perturbationstesten.

## Åbne forbehold

- `reconcile()` er unit-testet, men **aldrig kørt mod et rigtigt nyt udtræk**. Trin 4 er det første
  virkelige møde med den funktion, og den bør køres i tørløb først.
- **Loaderen er ikke et migrationsværktøj.** Se blockeren under trin 5 — re-ekstraktionens
  resultat kan ikke loades oven i eksisterende redaktionelt arbejde uden et nyt upsert/replay-lag.
- **`afstem_lokator.py` er baseline-afstemning, ikke matcher** (Codex-review 2026-07-29 fund 4):
  den kræver at artefaktet allerede bærer record_key. For et frisk udtræk er opgaven netop at
  FINDE record_key — det gør reconcile() + menneskelig afgørelse.
- Kalibreringen forudsætter et håndlavet facit for ~30 poster. Det er manuelt arbejde mod bogen og
  bør laves af en der kan læse gotisk sats.
- K8 (hændelser) er medtaget som beslutning, ikke som krav.
