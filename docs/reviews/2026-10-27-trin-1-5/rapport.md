# Helhedsreview af dataarbejdet, trin 1-5 — samlet dom

> Fase 3, skrevet af hovedsessionen (Opus) 2026-10-27 på grundlag af fase 0-2 i denne mappe. Kun til projektejeren.
> Grundlag: `docs/superpowers/specs/2026-10-27-review-trin-1-5-design.md`. Trin 6 startes ikke, før du har gennemgået
> rapporten.

## 1. Kort svar

**Er kvaliteten høj?** Ja, i kernen. Evidenslaget (source records, personas, klausuler, én generel writer) er
gennemtænkt, append-only og bevist på den rigtige bog uden at ændre kanoniske data. RLS for anonyme læsere er solid.
Testene er ægte adfærdstests. Svaghederne ligger rundt om kernen: `schema.sql` er ikke længere det, prod kører; CI
dækker ikke importens kerne; gamle skriveveje er aldrig lukket; og styringsdokumenterne siger imod sig selv.

**Dækker metoden behovet?** Halvt. Den kan *spore og binde* det, der allerede står i databasen, til kilden. Den kan
endnu ikke *oprette* noget nyt fra en kilde: alt i trin 4-5 bandt til personer og fakta, som den gamle loader skrev
(2-01). Og læseren kan ikke se resultatet: trin 4's 622 bindinger er usynlige i appen efter ti uger (1a-03). For
trin 6 (1939 gennem samme kæde) holder grundlaget med en kort liste af rettelser og beslutninger. For trin 7 (en ny
årbog eller en ny slægt) holder det ikke, før opret-benet er designet og bevist.

**Hvad har det kostet?** Mest overførslen til prod. Fortrydelse kun ved restore og »byg i restore, overfør
samlet« har kostet omtrent en uge pr. trin i overførselsmaskineri (U43: 10 af 15 PR'er), og garantien hviler i
sidste ende på ét dump (1a-04, 2-06). Processen er generelt ude af proportion med en PoC for én familie og én
redaktør (1a-12). Ingen enkelt beslutning var forkert; ingen besluttede proportionen.

**Er der noget, der skader prod-data lige nu?** Nej. Den eneste farlige skrivevej, der er åben, er
`load_presens.R --reset` (1c-01), og den kræver, at nogen kører den.

## 2. Afgørelser truffet undervejs i reviewet

- Kontrolpunkt 1 og 2 holdt; fase 1 fik flere Codex-runder efter dit ja (fem i alt).
- **1b-01 er P1** (din afgørelse ved kontrolpunkt 2, begrundet på bevis-aksen; `afvejning-codex.md`, øverst).
- **1c-01 rettes sammen med resten efter rapporten**, ikke som hurtigfix (dit valg).
- Fable kørt én gang i fase 2 efter dit ja, med Codex' rå fund som input, så Opus' nedjusteringer kunne efterprøves.
- Fase 0's tal »110 tests uden for CI« var forkert (ca. 92); rettet med note i `maalinger.md` og `systemkort.md`.

## 3. Dom pr. område

Skala: solidt / solidt men overbygget / hul / bør laves om (skalaen er mit valg; du har ikke bekræftet den).
Hvor reviewerne var uenige, står min dom og hvorfor.

| Område | Dom | Begrundelse |
|---|---|---|
| Datamodellen (konceptet) | **solidt** | Påstand/konklusion, generisk relation og source record ≠ person holder mod bogen. Projektets bedste aktiv. |
| Invarianternes håndhævelse | **hul** | Invariant 1 er kun konvention for `assertion`, og live-RPC'er overskriver og sletter (1b-06, 1d.1-02, 1d.1-03). Invariant 7 fodres ikke af kæden (2-05). CLAUDE.md tager fejl om `koen` (1b-12). |
| Ekstraktion og segmentering | **hul** | Virker for begge udgaver, men CI kalder 0/30 funktioner i `validate.py` og 1/25 i `segment.py` (1c-02), 13 mulige prosalinjer kan mangle (1d.3a-03), og parentesfletningen er død (1d.2-02). Udgavelogikken ligger i fælles kode (2-02): det skal laves om før trin 7, ikke før trin 6. |
| Source records og personas (trin 1-3) | **solidt** | 149a/149b beviste proveniensen på den rigtige bog med nul kanonisk delta. Rester: `verbatim_text` betyder to ting (1d.3a-01). |
| Fortolkning (trin 4) | **solidt men overbygget** | Runner og klausullag er en reel kontrakt (99 % præcision). Men 83 % af forslagene ligger uden kø (2-03), og 4.4-pakken blev bygget og aldrig brugt (1a-06). |
| Identitet (trin 5a) | **hul** | Kernen (afgørelse, låsning, versioner) er solid. Men facit er cirkulært, 1939-kandidater har næsten kun navn, og første binding efter familieskift er uvagtet (1d.3b-01). Det er præcis dér, trin 6 rammer. |
| Relationer og placement (trin 5b-5c) | **solidt men overbygget** | 5c-1 er læsbar, tilføj-kun og godt vagtet. 5b's tests er stærke. Men relation-opret er kun bevist syntetisk, og et medlemskab tåler kun én kilde (1d.1-07). |
| Promotion som helhed | **hul** | Kun binding, intet opret-ben (2-01); promotion-kontrakten fra 08-03 modsiges (1a-07); modstridende udgaver er aldrig udøvet (2-09). |
| Publicering og prod-overførsel | **bør laves om** | Restore-only plus genspilspakke kostede ca. en uge pr. trin og hviler på ét dump (1a-04, 2-06). 5c-1 gik direkte mod frisk dump på to dage. Den form bør være standard. |
| `schema.sql` og migrationer | **bør laves om** | `schema.sql` er bagud for prod siden RED-8 (17 kroppe, 16 tabeller; 1b-01); 16 funktioner er skrevet to gange (1b-03); paritetsvagten dækker 13 af 349 (1b-02); en forældet C3-fil ville rulle prod tilbage (1b-04). |
| RPC'er (`red_*`) | **solidt men overbygget** | Rollegate, versionsvagter og change_set-sporing overalt. Men to stilarter og låse til en verden, prod ikke har (1b-03, 1b-07). |
| RLS og GDPR for anon | **solidt** | Fail-closed, alle definer-funktioner har `search_path`, offentliggørelse kræver dødsevidens. Den juridiske afgrænsning ved skalering er uafklaret (2-04). |
| Beviser og `db-verify` | **solidt men overbygget** | Beviserne er ærlige om deres grænser, og katalogtjekkene er stærke. Men en del af `db-verify` tjekker ord, ikke adfærd (1b-14), og `SKIP` tæller som grønt (1e-03). |
| Test og CI | **hul** | Testene er gode (1c: trin 2-5 solidt). Hullet er, hvad der kører: CI bygger nogle job fra et skema, prod ikke har (1b-01), kernen er ikke i CI (1c-02), og tallene var målt forkert (1c-06). |
| Python/R-organisering | **solidt men overbygget** | 64 % af `daa-extract/scripts` er 1939/C3-engangskode blandet med den levende pipeline (1c-07). v1/v2/v3-filerne er derimod levende profiler; behold dem (1c-10). |
| Præsensloaderen | **bør laves om** | Ingen tests og en uvagtet `--reset` (`TRUNCATE … CASCADE`) mod prod (1c-01). |
| Styring og beslutninger | **hul** | Visionen og ét-aktivt-mål er gode, og disciplinen holdt i oktober. Men `status.md` og roadmappet modsiger sig selv (1a-01), den gamle loader har tre statusser (1a-02), og budget og afbrydelser håndhæves ikke (1a-05, 1a-09). |
| Læserværdi | **hul** | Trin 4's værdi er usynlig, og roadmappet har intet trin, der leverer den (1a-03). |

## 4. Alvor — to akser, holdt adskilt

Fase 1's P1-definition er: forkert adfærd, risiko for data eller prod, eller et bevis der ikke beviser. Fable vurderede
også metoden og produktet. Det er to forskellige spørgsmål, så de står i to lister. Der er altså ikke syv P1 for prod.

**P1 — data, prod eller bevis (4):**

| id | Hvad | Status |
|---|---|---|
| 1c-01 | `load_presens.R --reset` er en uvagtet `TRUNCATE … CASCADE` mod prod og står i SKILL.md | Ret først |
| 1b-01 | `schema.sql` er ikke det, prod kører; schema-only-CI tester 5b-writers på id-kroppe, prod ikke har | Din afgørelse: P1 |
| 1a-02 | `load_daa.R` er stadig den dokumenterede indgang, selv om den skaber dobbeltfamilier; »lukket« hviler på en kontraktversion | Kræver én beslutning (B5) |
| 1a-01 | `status.md` og roadmappet modsiger sig selv om mål, prod-tilstand og næste skridt; direkte årsag til orienteringstabet | Ren dokumentation |

**P1 — metode og produkt (3):**

| id | Hvad | Min vurdering |
|---|---|---|
| 2-01 | Kæden har intet bevist opret-ben; trin 7 kan ikke køres for en ny slægt | Enig. Tallene er efterprøvet (622 bindinger, 0 nye fakta). |
| 1d.3b-01 | Første binding efter familieskift sammenlignes ikke med den afgjorte familie for ægteskab og forælder | Enig. Selv efterprøvet i fase 1 (`schema.sql:17475/17482` mod `:17053-17054`). Samme fejlklasse som #248; rettelsen er én linje. Opus' P2 holder kun for prod i dag. |
| 1a-03 | Læseren ser intet af trin 4-5 | Enig. Projektets største risiko er værdi, ikke data. |

**Fables øvrige opjusteringer**, som jeg tilslutter mig: 1d.3a-01 bliver en beslutning i trin 6-spec'en (P2).
1d.3c-04 indgår i beslutningen om de gamle loadere (B5). 1d.1-07 er en gate før trin 6-spec'en, ikke en forenkling.
1d.1-02 bliver P2. Den sidste er sandsynlig, men ikke efterprøvet af mig: den hviler på, at UI'et tilbyder sletning af
importerede påstande.

**Hvor Opus' nedjusteringer holder:** de fleste. Codex læste koden rigtigt i næsten alle fund. Uenigheden handlede om
alvor, ikke om fakta. Tre argumenter holder kun for nuværende skala: »latent«, »ingen kendt forekomst« og
»procedurekontrolleret«. De holder ikke for trin 6, hvor 1939 bringer langt flere navnefæller (`fable-koncept.md` §2.6).

## 5. Beslutninger, du skal træffe

Flere af dem omgør eller formaliserer dine egne tidligere beslutninger. Min anbefaling står efter hver, markeret.

| # | Beslutning | Omgør eller formaliserer | Koster at gøre | Koster at lade være | Min anbefaling |
|---|---|---|---|---|---|
| B1 | Gate 8 skrives om: fortrydelse = særskilt handling *eller* restore af dateret dump inden for et deklareret vindue (`fable-koncept.md` §2.4 forslag 3) | Formaliserer restore-only (valgt 9 gange) | Papirgarantien svækkes, men den er allerede brudt i praksis | Arkitekturen lover noget, ingen bygger | **Ja**, med 2-06's dump-disciplin som betingelse: to kopier, hash noteret, tjek som første skridt |
| B2 | Genspilspakken droppes; 5c-1's form (dump → kør mod prod med flag → mål før/efter) bliver standard. Indholds-id'er beholdes | Omgør »byg i restore, overfør samlet« (10-01) | Ingen genspilsprøve før prod | Ca. en uge overførsel pr. trin | **Ja** |
| B3 | Trin 7 deles i 7a (ny udgave af samme slægt) og 7b (ny slægt fra ingenting); vælg kandidat-årbog | Roadmappet | Trin 7 bliver ærligt større | »Tredje årbog« bliver endnu en Reventlow-udgave og beviser ikke skalering | **Ja** |
| B4 | Spec for opret-benet før 7b; første rigtige prøve på 1939's 16 `[NY]`-records | Ophæver »binding, ikke oprettelse« (trin 4 pkt 6) som *princip* for 7b. Gælder fortsat for trin 4 | En spec og et bevis | Trin 7 må bruge `load_daa.R` | **Ja**, men efter trin 6 |
| B5 | `load_daa.R`, `post_load_fixup.R`, `backfill_slaegtled.R`: frys med `--jeg-mener-det` og kontraktport; ret CLAUDE.md:23 og SKILL.md samme dag | Lukker kursskiftet væk fra loaderen (1a-02) | Lille | Næste agent følger CLAUDE.md ind i den gamle vej | **Ja, nu** |
| B6 | Medlemskab fra en anden kilde bliver `corroborated`, ikke `conflict` (1d.1-07) | Ny regel | En spec-linje + kode i trin 6 | Trin 6's promotion stopper på første 1939-placement | **Ja**, i trin 6-spec |
| B7 | `verbatim_text`: én betydning på tværs af udgaver, eller betydningen deklareres pr. udgave (1d.3a-01) | Ny regel | Lille | Trin 6 læser to betydninger som én | Beslut i trin 6-spec |
| B8 | Kontrolmodellens stikprøve: røgtest (drop segl og hash-ceremoni) *eller* strengt blind (1a-10) | Justerer 09-27 | — | Ceremoni uden den bevisværdi, den koster | **Røgtest**. »Ingen flere fulde ark« beholdes |
| B9 | `schema.sql`: portér RED-8 i hånden nu, eller generér skemaet fra en migreret base (1b-05) | CLAUDE.md's source-of-truth-regel | Portering: lille. Generering: stor diff, statiske tests der læser skemaets tekst kan knække | Begge lukker 1b-01 | **Portér nu** (gate). Generering som særskilt beslutning efter trin 6 |
| B10 | GDPR ved skalering: udelukkelse = »død før (år − 10)«, og behandlingsgrundlag på foreningsniveau (2-04) | Regel 1-4 og pkt 5 (09-06) | 10-års-reglen er billig. Grundlaget kræver jurist | Stopper trin 7, ikke trin 6 | 10-års-reglen **ja**. Juristen før foreningens data |
| B11 | Læserværdi bliver en del af trin 6's færdigbevis: fakta med kildehenvisning i persondetaljen (1a-03) | Roadmappet | Ca. en dags skive | Ti uger mere uden synlig værdi | **Ja** |
| B12 | OCR-rettelse er ikke en ny påstand (07-26), genbekræftet mod visionens »originalen er uforanderlig« (08-25) | Genbekræfter | Én linje i decisions | Uafklaret forhold mellem to beslutninger | Genbekræft |
| B13 | Review-budget og kontrollerede afbrydelser håndhæves: én linje i spec-hovedet, overskridelse kræver en linje i decisions (1a-05, 1a-09) | Håndhæver 09-03 og 09-23 | Lidt disciplin | Specs vokser af reviews | **Ja** |

## 6. Prioriteret handlingsliste

Kolonnen »Vej til prod« angiver, hvad hver rettelse kræver. Det afgør rækkefølgen, og hvad der kan samles i én ceremoni.

**Trin A — uden prod-berøring (kan laves straks, små):**

| # | Handling | Fund | Vej til prod |
|---|---|---|---|
| A1 | Vagt eller fjern `--reset` i `load_presens.R`; ret SKILL.md | 1c-01 | Intet. R-script |
| A2 | Frys de gamle loadere + ret CLAUDE.md:23 og SKILL.md | 1a-02, 1d.3c-01/04/05 (B5) | Intet. R-scripts + docs |
| A3 | Portér RED-8 til `schema.sql`, udvid paritetsvagten, sekvens-verify for de 25 tabeller | 1b-01, 1d.1-05, 1b-02 | Intet. Prod har allerede migrationskroppene. Verify-blokken kan køres læse-kun mod prod |
| A4 | Skriv `status.md` om til ét snapshot, ret `roadmap.md`, markér døde planer historiske | 1a-01, 1a-14, 2-07 | Intet. Docs |
| A5 | Arkivér den forældede C3-deployfil og de røde R-tests | 1b-04, 1c-05, 1c-04 | Intet. Fjerner en fil, der ville rulle prod tilbage |
| A6 | Du læser de 13 `NOISE_RE`-linjer mod kilden (ikke en model: persondata); én disposition pr. linje | 1d.3a-03 | Afhænger af udfaldet: tekstrettelse kan kræve narrativskrivning |

**Trin B — én DDL-ceremoni (samlet, med `get_advisors` bagefter):**

| # | Handling | Fund | Vej til prod |
|---|---|---|---|
| B-1 | `judged` sammenligner med `decision_evidence.family_id` for ægteskab og forælder, som børnegrenen gør + test | 1d.3b-01 | Funktionskrop: migration + prod-DDL |
| B-2 | `red_edit_oplysning`: `ON CONFLICT DO NOTHING`, kopiér `date_certainty` | 1d.1-03 | Funktionskrop: samme ceremoni |
| B-3 | Vagt mod sletning af `uforanderlig` påstande i `red_slet_oplysning` | 1d.1-02 | Funktionskrop: samme ceremoni |
| B-4 | Statusfilter i cachen | 1d.1-04 | Funktionskrop + **mål først**, om en cachet faktatype har anden status i prod. Hvis ja, ændrer regenereringen prod-data |

**Trin C — før trin 6-spec'en:** beslutningerne B1-B3 og B6-B8 og B11 fra afsnit 5. Desuden 1d.2-02 (ny
klausulregelversion med parentesfletning; ingen prod-berøring før en genkørsel) og CI-dækning af `validate.py` og
`segment.py` (1c-02).

**5c-2 (læserskift)**, som var planlagt som næste skridt før reviewet, kan gå efter trin A og B. Den er ikke
afhængig af beslutningerne i trin C. Den bør laves sammen med B11 (fakta synlige for læseren), fordi begge er
læserflade og kan verificeres i samme browsertest.

**Trin D — senere:** opret-benet (B4) før 7b; redaktionel rettelsesvej for familiefejl (2-08) før trin 6 begynder
at finde 1939-fejl; konfidens fra bindingens oprindelse (2-05); én kø for uafgjorte forslag (2-03); modstridende
udgaver som konkurrerende påstand (2-09).

## 7. Udestående (spørgsmål 7)

Den fulde, deduplikerede liste står i `fable-koncept.md` §2.5 (34 punkter i fem grupper). Tallene:

| Gruppe | Antal | Indhold |
|---|---|---|
| A. Gates før trin 6 | 14 | Afsnit 6 trin A-C ovenfor, plus de fire `unresolved_text` (I-133, II-35, III-129, IV-94) |
| B. Trin 6's indhold | 8 | 1939-klausulregler, årstal til kandidater, `samme_som` i generatoren, 1939-placement, #158-#163 |
| C. Læser- og redaktørværdi | 8 | Fakta i persondetaljen, binding synlig, kø, rettelsesflade, konfidens, `authenticated`-tier og samtykke |
| D. Hygiejne og arkiv | 4 | 1939-engangskode, dubletdefinitioner, CI-discover, upushede docs-grene, lokale baser (måles før sletning) |
| E. Lovligt parkeret | — | Spor H/M, C1/C2, DNA, mediefase 5, flersproget |

Nyt i forhold til 0d's 126 rå punkter: 2-01 til 2-09. Ingen af dem stod på nogen liste før.

## 8. Reviewets egne grænser

- **Intet er kørt mod en database.** Alle fund er læst i kode og dokumenter, ikke reproduceret. Undtagelse: én
  syntetisk kørsel af segmenteren (1d.2-02).
- **Codex' dækning er tynd for trin 1, 2, 5a, overførsel B1/B2 og indholds-id.** Kun Opus har set dem.
- **Web, mobil og `packages/` er ikke vurderet** (egen senere runde). Slægtskabsfinderens visning af konfidens er
  derfor ikke set (2-05's konsekvens er sandsynlig).
- **2-04's juridiske præmis** (10-års-reglen, abonnement ≠ databehandleraftale) er ikke efterprøvet af en jurist.
- **Læselofter:** 1b 30, 1c 21 og afvejning A 21 filer eller sektioner læst fuldt (loft 40); Fable 21 af 25 opslag. Resten via grep og målinger.
- **Fase 0 var mekanisk.** Ét tal var forkert (110 → ca. 92 tests uden for CI) og er rettet.

## 9. Forbrug

| Fase | Model | Forbrug |
|---|---|---|
| 0 | Sonnet (3 agenter) + hovedsessionens scripts | ikke målt |
| 1a-1c + 2 afvejninger | Opus (5 agenter) | ca. 1,39M tokens |
| 1d + 1e | Codex `gpt-6.1-terra` (7 kald) | ca. 10,2M input (ca. 92 % cache), ca. 45k output |
| 2 | Fable (1 kald) | ca. 467k tokens |
| 3 | hovedsessionen (Opus) | ikke målt |

## 10. Hvad sker nu

1. Du gennemgår rapporten og tager stilling til B1-B13. Skriv gerne bare numre og ja/nej.
2. Trin A (uden prod-berøring) kan begynde straks efter dit ja, i en egen gren, ét commit pr. handling.
3. Trin B samles i én DDL-ceremoni med GO fra dig.
4. 5c-2 og læserværdien (B11).
5. Trin 6-spec'en skrives med beslutningerne fra trin C som indgang.

Kildefiler i denne mappe: `maalinger.md`, `beslutningskronologi.md`, `systemkort.md`, `udestaaende-raa.md`,
`leverancetidslinje.md` (fase 0); `fund-1a.md` … `fund-1e.md`, `afvejning-codex.md` (fase 1); `fable-koncept.md` (fase 2).
