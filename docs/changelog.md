# Changelog

## 1939: Den fyenske Linje fik egen linje og omstridt slægtskab (2026-07-29)

De 26 personer i DAA 1939s linje VI kan aldrig matches mod DAA 2018-20, fordi
2018-20-forfatteren bevidst udelod dem. Bogen selv er dog mere forbeholden end
"de hører ikke til": 1939 skriver at de førte Reventlowernes murtinde men et
**helt andet hjelmtegn**, at efterkommerne *"lejlighedsvis har ført
Reventlow-Navnet"* og regnede sig til slægten, *"men om den fyenske Linjes
Samhørighed med de holstenske og meklenborgske Reventlower kan intet oplyses."*
Begge udgaver er altså enige om at slægtskabet er udokumenteret; de er uenige om
hvad man så gør.

Modelleret som to adskilte påstande frem for én:

- **Navnet hævdes.** Linjen får `parent_lineage_id=6` (slægtsroden) og arver
  dermed slægtsnavnet — "Henrik Jensen" vises nu som *Henrik Jensen Reventlow*,
  som bogen ville skrive ham. `slaegtsnavn=NULL` blev forkastet: det ville
  benægte et dokumenteret faktum for at udtrykke tvivl om et andet.
- **Slægtskabet hævdes ikke.** En `gren_af`-relation (lineage 7 → 6) med
  `konfidens='omstridt'` bærer selve afstamningspåstanden, med assertions og
  citationer fra **begge** udgaver og en `conclusion` med status `omstridt`.
  Skemaet foreskriver netop dette: *"parent_lineage_id er den hurtige FK;
  'gren_af'-relationen bærer evidens/konfidens."*

Udført i `change_set` 788: ny `lineage` 7 (source 3, kode VI), `linje='VI'` på de
26 (person 1437–1462), rolle `gren_af` tilføjet vokabularet. Verificeret positivt
før kørsel: artefaktets 26 `Lfyn`-poster står i nøjagtig samme navnerækkefølge som
DB'ens nr 514–539. Rehearset i rullet-tilbage transaktion. Ingen sideeffekt: de
øvrige 489 1939-personer og alle 2018-20-personer er urørte, slægtsnavns-
karantænen er fortsat tom.

**Faldgruber fundet undervejs (vigtige for det videre arbejde):**

1. **IV og V er byttet om mellem udgaverne.** 1939 IV = "Den danske grevelige
   Linje af 1673" = 2018-20 **V**; 1939 V = "grevelige Linje af 1767" = 2018-20
   **IV**. Enhver logik der bærer et romertal på tværs af udgaver matcher stille
   to forkerte linjer. `matchUdgaver` slår heldigvis op på `${source_id}:${kode}`.
2. **1939 er uenig med sig selv:** indledningen nummererer den fyenske som IV,
   brødteksten som VI.
3. **"A. Den holstenske Linje"** i den rensede OCR er en fejllæsning; `raw.txt`
   har "I".

**Matcher-filteret er med.** `MatchLineageRow` har fået `udenforMatchning`, og
`buildMatchPersoner` sætter et tilsvarende flag pr. person. `SammenlignUdgaver`
springer dem over **før** frames bygges, så de hverken bliver arbejdsemne eller
kandidat — 2018-20 er nyeste udgave, så uden filteret lå de 26 i *kandidat*-puljen
og kunne foreslås som match for 2018-20-personer. Flaget udledes i `fetchLineages`
fra `gren_af`-relationen, så reglen står ét sted og `lineage.status` (fri tekst)
aldrig parses. Fejler relations-opslaget, undtages ingen: at vise for mange
kandidater er en irritation, at skjule en ægte kandidat er et datatab. Testet på
begge sider — også at flaget ikke smitter mellem udgaver med samme linjekode
(opslag på `(source_id, kode)`, ikke kode alene; jf. IV/V-ombytningen).

**Udestår også:** de øvrige 489 1939-personer har fortsat den syntetiske
`linje='1939'`. Strukturen findes allerede i loaderens input (`_ctx.linje`,
`lokal_id`-præfikser som `Lfyn`/`LGallentin`/`HL`), men `_ctx.linje` er
LLM-udledt og hullet (222 poster uden værdi, mange "udledt"/"ukendt"), så en fuld
omlægning er sit eget stykke arbejde — og konverteren skal med, ellers ruller en
genindlæsning ændringen tilbage.

## 2018-20: bogens apparat bløt ind i sidste posts narrativ (2026-07-29)

Brugeren bemærkede at person 391 — en nulevende, født 2001 — havde et narrativ
med indhold fra 1700-tallet. Det var ikke en anden persons biografi, men bogens
**portrætfortegnelse**: én korrekt sætning efterfulgt af billedtekster med 21
krydsreferencer.

**Rodårsag:** IV-94 er den sidste post i linje IV. Segmenteringen skar "fra
overskrift til sektionens slut" og slugte alt efterstillet apparat. Systematisk,
ikke tilfældigt: fire af fem linjers sidste post var ramt — I-133 (person 39),
II-35 (165) og III-129 (205) havde slugt linjetillægget *"Til denne linje hørte
formentlig…"*, III-129 og IV-94 (391) desuden portrætfortegnelsen. V-200 var ren.
Ingen andre af de 591 narrativer havde mønstret, målt på tre uafhængige signaler
(tillægsmarkør, billedtekst-ord, krydsreference-tæthed).

**Kontrolleret at intet manglede den modsatte vej:** alle 591 personer har et
narrativ, og de 71 helt korte er ægte ("Barn.", "Cord – † ung.", "Gottschalk von
Reventlow, se II. Linjen Gallentin."), også de 7 hvor en kort post følger en meget
lang forgænger. Indblødningen er ensidig — sidste post sluger efterstillet stof,
men stjæler ikke fra naboen.

**Ingen persondatalækage:** anon får 0 rækker for den nulevendes narrativ; RLS-
gaten holdt hele tiden. Verificeret.

Trimmet i `change_set` 787 inde i et `begin_change_set`, så `log_change`-triggeren
fangede før-billedet: **12.469 tegn bevaret i `change_event.foer`**, 1.014 tegn
tilbage. Fuldt fortrydbart — teksten er ikke destrueret. Rehearset mod prod i en
rullet-tilbage transaktion først; alle fire trimninger ender på en afsluttet
sætning. Efter: 0 tillæg, 0 billedord, max krydsreferencer i hele korpus = 0.

**Udestår:** selve segmenteringen er ikke rettet, så en genekstraktion af 2018-20
ville genindføre fejlen. Det slugte linjetillæg er reelt genealogisk indhold
(uplacerede personer, fx *"Hinrich von Reventlow – † før 1390"*) og hører hjemme
på linjeniveau — `narrative.subjekt_type='slaegt'` findes allerede og bruges. Begge
dele er separate opgaver.

## 1939-dubletter: 23 af 35 kandidater slettet (2026-07-28)

Oprydning efter dubletdiagnosen. Brugeren gennemgik kandidatlisten mod bogens sider og slettede
23 poster via redaktørfladens `red_slet_person` — 6 først, derefter 17.

**Resultat:** 1756 → 1733 personer, 1939-hovedposter 538 → 515, 2018-20 urørt på 591. Læser-lagets
huller i forældrelink faldt fra 62 til 44 (11,5 % → 8,5 % af 1939-posterne). Integritet efter
sletningerne: **0 forældreløse rækker** i `person_external_id`, `family_member`, `relation` (begge
retninger), `narrative` og `fact` — den FK-ordnede kaskade i RPC'en holdt.

**Korrektion til diagnosen.** Rapporten konkluderede at dubletterne *producerede* de konflikter der
satte `samme_som`-grupper i karantæne, og at sletningen ville frigøre dem. Det holdt ikke: antallet
af karantænerede grupper står uændret på **238**. De 12 blokerede poster forsvandt fordi de selv
blev slettet, ikke fordi blokeringen blev ophævet. Sammenfaldet (12 af 12 stod på slettelisten) var
ægte; årsagsretningen var en tilføjelse. Karantænerne skyldes uenighed om forældre mellem *rigtige*
personer og kræver fortsat manuelt matcharbejde.

**Sidetal tilføjet til kandidatlisten undervejs** — alle 538 1939-hovedposter har et sidetal i
citationen, så hvert par kan slås op uden at lede. De 35 par fordeler sig på 32 sider (s. 504-581).

**10 par udestår bevidst:** `nr` 68 (eneste bro til 2018-20 — matchet skal flyttes først), `nr` 54
og `nr` 102 (familiekanter skal flyttes; 102 er desuden matchet til en anden 2018-20-person end sin
makker og er ikke en bekræftet dublet), `nr` 44/94 (begge er prosaomtaler, klasse AA) og fem par med
kun én detektor.

**Sidebemærkning:** sletningerne kunne ikke udføres fra en service-forbindelse — `current_rolle()`
giver `medlem` uden en indlogget bruger, og både `red_slet_person` og dens preview kræver
`redaktion`. Rå `DELETE` blev fravalgt: den ville omgå `change_set` (ingen fortrydelse) og den
FK-ordnede kaskade. RLS-hærdningen virkede efter hensigten.

## Slægts-rod i lineage — LIVE i prod, begge trin (2026-07-28)

Forberedelse til at andre slægter end Reventlow kan bo i samme base. Alle fem linjer havde
`parent_lineage_id = NULL`, så intet knudepunkt repræsenterede selve slægten: slægtsnavnet stod
gentaget på fem rækker, og en ny slægts linjer ville lægge sig sideordnet uden noget der bandt dem
sammen. Nu findes én rod pr. slægt (`source_id`/`kode` = NULL, så den aldrig får medlemmer og er
usynlig i app'ens linje-liste), og linjerne hænger under den.

**Delt i to trin efter deploy-rækkefølge — begge nu kørt.** Trin 1 (rod + repegning + dublet-guard)
er forward-kompatibel med *begge* web-versioner, fordi grenene beholdt deres eget `slaegtsnavn`;
den kunne derfor køres uden at vente på app-deployet. Trin 2 (rydning af grenenes `slaegtsnavn`)
blev kørt efter at PR #109 var merget og deployet, fordi den daværende web læste feltet råt og
ellers ville have vist præsenslistens overskrift tom. Opdelingen var ikke formalitet: den fjernede
tidsvinduet helt frem for at gøre det kort.

Slægtsnavnet bor herefter kun på roden (id 6); alle fem grene har `slaegtsnavn = NULL` og udleder
`Reventlow` via `lineage_effective_slaegtsnavn()`.

**Verificeret mod prod efter hvert trin:** korpus-diff på `visning_efternavn`/`visning_fuldt_navn`
for alle 1756 personer viser 0 forskelle mod før-tilstanden, `slaegtsnavn_karantaene` står på 0, alle 5
grene udleder fortsat `Reventlow`, roden har 0 medlemmer, og `get_advisors(security)` er uændret på
133 lints uden nye lineage-relaterede. Frisk backup taget før kørslen
(`daa-prod-pre-slaegtsrod-20260728-141840.dump`, uden for git).

**Fejlrettet antagelse undervejs.** `narrative.subjekt_type='slaegt'` med `subjekt_id=1` ligner en
fremmednøgle til `lineage` 1 og blev i første omgang beskrevet som "slægtsteksten parkeret på linje
I". Det er forkert: id'et er en *sentinel* for hele slægten, båret som konstant i begge apper
(`SLAEGT_SUBJEKT_ID`), og `fetchAbout` filtrerer slet ikke på det. En planlagt flytning til roden
ville have koblet redaktørfladens skrivesti fra læsestien. Flytningen er ude af migrationen, og en
`db-verify`-assert fastholder det. `docs/reviews/flerslaegt-parathed-2026-07-28.md` er rettet.

**Ikke løst her:** to slægter i samme årbog har begge en "Linje I", og `lineage UNIQUE
(source_id, kode)` afviser den anden — bekræftet empirisk. Det er B1 i flerslægts-vurderingen og
kræver en beslutning om nøglerummet før næste slægt loades.

## Kilde vist for de 627 personer uden bog-nummer (2026-07-28)

Brugerfund: mange personer stod uden kildeangivelse i følgesvenden (`Ada Jessie Howard Grøn`).
Årsagen var visning, ikke data. `sourcesBy` bygges alene af `person_external_id`, som kun findes
for personer bogen gav et eget opslag; de 627 ægtefæller har intet bog-nummer, så opslaget var tomt
og `DetailPanel` skjulte hele "Kilde i Aarbogen"-blokken. 335 af dem er offentligt synlige.

Proveniensen fandtes hele tiden — invariant 1 kræver at hvert faktum er kildebundet, så alle 1756
personer har `fact → assertion → citation → source`. Målt mod prod har alle 627 **præcis én** kilde
(0 flertydige) og 296 endda sidetal. Rollefordelingen blev derfor: bog-nummeret (`Linje II, nr. 4`)
er den mest præcise reference og vinder hvor den findes, mens citationen er reglen der dækker alle.
Ada konkret: id 841 → `DAA 2018-20`, id 1690 → `DAA 1939, s. 578` — matchet til hinanden, men da
ingen af siderne har bog-nummer kunne `collapseSameAs` heller ikke redde det.

Reglen ligger i `@daa/core` (`kildeProveniens.ts`), så web og mobil deler formatering. Wiringen er
bevidst forskellig: web henter først når personen mangler bog-nummer (de ~1129 hovedposter betaler
ikke for opslag de ikke bruger), mobil bulk-henter kun `navn`-faktaet — det ene faktum hver person
beviseligt har. `citationRowsTilProveniens` findes fordi PostgREST returnerer et *objekt* for en
til-én-relation mens de genererede typer siger *array*; web slap afsted med en cast, mobil gjorde
ikke. Anon-adgang til `citation`/`assertion`/`fact` + det nestede source-join blev verificeret
empirisk mod REST-API'et, ikke udledt af at en service-key-forespørgsel lykkedes.

Ingen DB-ændringer. Merget som PR #105, CI grøn på alle 6 jobs (mobil-jobbet kørte de 2 suiter der
fejler lokalt pga. manglende `@testing-library/react-native` i `node_modules` — install-drift, ikke
kode). **Udestår:** visuel verifikation af blokken i den deployede web.

**Målt undervejs, ikke rettet:**

- **Køn mangler på 625 personer** — samme population (329 + 296 ægtefæller; hovedposter mangler 0).
  Testet kontrafaktisk om det bremser tværudgave-matchningen: 625 af 629 kan udledes af partnerens
  køn, men effekten er negativ (`auto` 267 → 258, `review` 3639 → 4003). `evidensNormaliseret`
  normaliserer allerede over de signaler der kan vurderes, så et manglende køn koster intet dér.
  Det er en visnings-/korrekthedssag, ikke en matchning-blokering, og kræver skrivning via
  `red_set_koen`.
- **Ægtefælle-dubletter behøver ikke egen liste.** `udledKilderForAegtefaeller` (#90) virker 100 %
  (627/627 får udgave), og med fladens egen config (`evidensNormaliseret: true`) har 394 af de 431
  umatchede ægtefæller mindst én kandidat. Arbejdet kan gøres i `SammenlignUdgaver` som det er.

## Kvalitetsark: navn_mangler-flaget var falsk på 1169 af 1757 rækker (2026-07-28)

Brugeren spurgte hvorfor `navn_mangler` stod ved alle. Måling: **1169 flag, nul
ægte** — hver eneste flaget række viste et navn korrekt. QA-koden målte på
`candidate_count`/`felt_vaerdi`, som begge er anker-gatede, mens selve
navnevisningen (siden `4d041bf`) falder tilbage til den afklarede evidens
uafhængigt af anker. Koden flagede altså reelt "kan ikke rettes", ikke "har intet
navn" — samme sammenblanding som den tomme navnekolonne, bare flyttet fra
visningen til QA-laget. Redigerbarhed udtrykkes allerede af
`kan_rettes`/`blokarsager`. Rettet til at måle præcis den værdi griddet viser.

Fundet undervejs: griddet returnerede **to rækker for samme fysiske person** når
personen står midt i en `samme_som`-kæde (både alias og kanonisk) — rækkerne
adskiller sig på `samme_som_status` og overlevede derfor `GROUP BY`'et. Præcis én
person i prod (826) stod sådan. Nu `DISTINCT ON` med alias-forrang. Kæden kan
opstå fordi `enforce_samme_som_invariants()` kun er `BEFORE INSERT` og G4 kun
tjekker `NEW.subjekt`: indsættes den inderste kant først, slipper den ydre
igennem. **Trigger-hullet er ikke lukket** — griddet er gjort robust over for
tilstanden, men invarianten kan stadig omgås via indsættelsesrækkefølge.

Verificeret mod en lokal kopi af prods rigtige data før udrulning (1169 → 0,
navn vises på alle, `kan_rettes` uændret på 588), derefter anvendt mod prod som
ren `CREATE OR REPLACE FUNCTION` — ingen data rørt, ingen DDL, `get_advisors`
uændret på 133 lints. Prod efter: 1756 rækker for 1756 personer (dubletten væk),
0 `navn_mangler`. Rollback-artefakt med den forrige definition gemt før
udrulning.

Ikke løst her: de **627 gift-ind-ægtefæller** uden egen bogpost er fortsat
ikke-redigerbare (`ingen_importanker`). Planen behandlede dem som et sjældent
legacy-hjørne; de er 36% af korpus. Kræver egen plan — nøglen ville være
forælderens `record_key` + indeks i `aegteskaber`, og `linje` SKAL være NULL,
da `regen_person_visning()` ellers ville påhæfte slægtsnavnet til indgifte
ægtefæller.

## Personers OCR-kvalitetsark — record_key-backfill for DAA 2018-20 + web-status rettet (2026-07-28)

Genindlæsning med `--reset --import-key=` blev overvejet for at gøre eksisterende
personer redigerbare, men forkastet: loaderens `has_reset_blocking_editorial_
changes()`-spærre blokerer på enhver `red_%`-operation undtagen `red_ret_ocr_felt`,
og prods `change_set` har 482 `red_samme_som`-links plus dusinvis andre
redaktørrettelser den ville have ramt. I stedet blev en smal, kun-tilføjende
`UPDATE`-backfill kørt: 591 eksisterende DAA 2018-20-personer fik
`source.import_key='daa:2018-20'` og `person_external_id.record_key` stemplet,
udledt af at filnavnene i `data/extracted-2026-06-18/*.json` selv ER `record_key`.
To `(linje,nr)`-kollisioner (basenr 15 og 41) løst entydigt ved navnematch. Rehearsed
mod en lokal kopi af prods rigtige data før kørsel; frisk krypteret backup taget
(`daa-prod-pre-record-key-backfill-20260728-074303.dump.gpg`). Resultat mod ægte
prod: 588/591 personer nu redigerbare, 0 `record_key_mangler` tilbage,
`get_advisors(security)` uændret på 133 lints. 1939-udgaven har stadig ingen stabil
identitet.

Samtidig rettet: forrige changelog-entry og runbook sagde web-laget ikke var
deployet — brugeren havde i mellemtiden selv merget PR #103 til `main` via GitHub,
og Vercel havde allerede auto-deployet featuren til prod. `web_deployed` er derfor
opnået siden 2026-07-27; kun den manuelle redaktør-røgtest udestår.

## Personers OCR-kvalitetsark — DB LIVE i prod, web IKKE deployet (2026-07-27)

Databasen er migreret mod prod (`xjnvdhajfyrcytatnzos`): `import_korrektion`-journal,
stabile importnøgler og RPC'erne `red_person_grid`/`red_ret_ocr_felt`/`red_ocr_historik`
er live. Krypteret backup taget og gendannelses-verificeret først. Verificeret mod
rigtig prod efter migration: `anon` afvist (ægte REST-kald, 401), `get_advisors`-delta
+3 (kun de kendte SECURITY DEFINER-mønstre), data uændret (1756 personer). Brugeren
valgte at migrere databasen nu og genindlæse en udgave med `--import-key=` separat
senere — eksisterende personer er derfor synlige i griddet men endnu ikke redigerbare.

Web-laget er **ikke** deployet endnu. Se `docs/runbooks/person-ocr-kvalitetsark.md` §5.1
for detaljer, inklusive en hændelse under første migrationsforsøg (en manuel
gentastning af SQL introducerede en kolonnenavne-fejl; transaktionen rullede atomisk
tilbage uden nogen skade, og genforsøget med filens eksakte indhold lykkedes).

## Personers OCR-kvalitetsark — kodeklar, IKKE deployet (2026-07-26)

Redaktør-værktøj der viser hver importeret person som én række i et regneark-lignende
grid, med et sidepanel hvor navn, fødsel, død og køn kan rettes. En OCR-rettelse er en
rettelse af *samme* importerede kildeudsagn: `fact.id`, `assertion.id`, citation og
konklusion bevares, så oprydning aldrig bliver til en ny historisk påstand. Rettelser
lever i en holdbar journal uden for loaderens reset-liste og genafspilles efter en
genindlæsning via stabile `(import_key, record_key)`-nøgler; en ændret OCR-kontekst
markerer rettelsen `stale`, så den ikke genafspilles blindt.

Fail-closed hele vejen: RPC'en afviser med mindre personen har præcis ét stabilt
importanker og feltet peger på præcis én valgt, citeret påstand. Personer uden anker
forbliver **læsbare, men låste**. Anonyme og medlemmer afvises server-side.

**Status: kodeklar og lokalt DB-verificeret — produktionsdatabasen er ikke rørt, intet
er deployet, intet pushet.** Drift, gates og udestående manuel røgtest:
`docs/runbooks/person-ocr-kvalitetsark.md`.

Verificeret: R 475, core 358, feed 120, web 613, mobil 399, validate.py 130, loader-
DB-smoke 124 — alle grønne. Frisk base + opgraderingssti på PostgreSQL 17.10 med
idempotente migrationer (kørt to gange); rolleadgang efterprøvet med efterlignede
JWT-claims. Skala-måling ved 2001 personer: `red_person_grid()` 285–301 ms, 3.470 kB.

Undervejs fandt og lukkede arbejdet fire fejl, som testene ikke selv fangede: loaderen
korrumperede stille en buffer-kolonne, fordi `jsonlite` læser JSON-null som `NULL` men
skriver det tilbage som `{}`; `red_person_grid()` manglede `ORDER BY`, så pagineret
læsning var uden ordensgaranti; en bar ISO-dato blev tolket som helår i *begge*
parsere — uskadeligt i udtrækket, men tavst tab af præcision når en redaktør selv
taster datoen (0 af 1322 `date_raw` i korpus var berørt, så rettelsen var inert); og en
rehearsal mod prods **rigtige** data (ikke syntetisk fixture) afslørede at griddets
navn/fødsel/død-visning delte anker-gate med redigerbarheden, så alle 1757 eksisterende
personer viste tomme felter. Rettet ved at falde tilbage til den allerede afklarede
evidens, uafhængigt af redigerbarhed — 0/1757 personer har nu tomt navn (var 1757 før).

## 2018-20: 18 narrativer med slaegtled-/kuld-bleed rettet — LIVE i prod (2026-07-27)

2018-20-auditen fandt 14 poster med en trailing sektionsoverskrift
(`Sjette (nittende) slægtled`) hængende på halen af forrige posts narrativ. Videre
undersøgelse fandt 4 mere alvorlige tilfælde hvor både overskriften OG den
efterfølgende kuld-markør (`Overkammerherre Detlef lensgreve de Reventlous børn`)
bløder ind — 18 poster i alt.

**Rodårsagen var allerede rettet i koden — bare ikke genindlæst.** Sporet til
`work/raw_full.txt`: `segment.py`'s `SLGT_RE` matcher en bar slaegtled-header
korrekt, når den (som her) står alene på sin egen linje. Kørt frisk mod
`raw_full.txt` gav det nuværende `segment.py` alle 18 poster ren tekst, byte-
identisk med de øvrige 573 upåvirkede poster. Bug'en sad kun i det allerede
indlæste artefakt (`work/clean_full.json`, stale ift. dagens segmenterer) —
`segment.py` er ikke ændret. To regressionstests låser adfærden fast.

`R/update-2018-narratives.R` — målrettet patch af 18 navngivne poster, nøglet på
`(linje, nr)` fordi det ikke er globalt unikt i denne udgave (I-15a/b/c deler
basenr). Bruger `jsonb_to_recordset()` af ét JSON-parameter, da hverken
`CREATE TEMP TABLE` (DDL, fejler i dry-runs READ ONLY-transaktion) eller et
array-parameter blandet med et skalar-parameter (RPostgres fortolker det som
batch-udførsel) virkede.

**Anvendt mod prod:** `change_set=532`, 18 rækker, 18 audit-events. Verificeret
efter apply — ingen bar `slægtled`-hale tilbage, legitime krydshenvisninger
(`Andet (femtende) slægtled, nr. 2‑9.`) intakte. (#98)

## Tværudgave-matchning gjort mulig for ægtefæller (2026-07-26)

Fulgte af 1939-auditen nedenfor: auditen fandt ~51 % mangelfulde forældrelink og pegede
på re-ekstraktion (trin 2). Analysen viste at det var forkert diagnose — og hver rettelse
afdækkede den næste.

**1. Hullet var allerede halvt lukket.** `collapseSameAs` omskriver `parentChild`-kanter til
kanoniske id'er, så en matchet 1939-person arver sin 2018-20-modparts forældre i visningen.
Data-lag 253/539 mangelfulde, læser-lag 86/539. Matcharbejdet lukkede ~68 % gratis.
(`docs/reviews/kryds-udgave-udfyldning-scoping-2026-07-26.md`)

**2. 287 grupper var i karantæne — ikke af uenighed.** Målt ved at køre den rigtige
`collapseSameAs` mod et prod-dump; to SQL-genimplementeringer gav upålidelige tal. Bøgerne
er enige: 1939 skriver `Bertram + Christine Rantzau` hvor 2018-20 skriver
`Bartram + Christina von Rantzau`. Forældrene var bare ikke matchet til hinanden.

**3. De kunne ikke matches.** Ægtefæller har sjældent eget bog-nummer, og `sourceIds` blev
udledt alene af `person_external_id` — uden nummer hørte de til ingen udgave og indgik aldrig
i kandidatparrene. 0 af 73 forældrepar kunne gennemføres. `udledKilderForAegtefaeller` lader
dem arve udgaven fra deres partner, entydigt eller slet ikke: 627 ægtefæller (296+331),
0 flertydige, forældrepar 0 → 77. Lukkede samtidig at 1939-ægtefæller lå i B-siden og kunne
foreslås som match for deres egen udgave. (#90)

**4. Brugerfund: "formodet nye" var en blindgyde.** 393 poster, hvoraf 392 havde en kandidat
der var fundet og smidt væk (`tier === 'none'`), og 125 havde eksakt samme navn i 2018-20.
Årsagen strukturel: overlap tæller kun når begge sider har en dato, så en person uden årstal
har loft = `wName + wSex` = præcis review-tærsklen. `svageKandidater` bevarer dem nu med
Sammenlign/Bekræft — uden for status og fremdrift, så tællerne er uændrede. (#93)

**5. Modellen rettet.** `scorePairEvidens` normaliserer over de signaler der faktisk kunne
vurderes; ukendt årstal ryger ud af nævneren, kendt-men-uenigt bliver stående. Personer med
mindst ét forslag: **442 → 815 af 835**. Første måling uden spærre viste faren konkret —
152 par uden ét eneste årstal blev markeret "stærke" (`Otto ↔ Otto`) — så `assignTiers`
kapper navn-alene til "gennemsyn": 152 → 0. (#95 opt-in, #96 slået til)

**Værktøj:** `tools/foraeldrematch/` — `status.ts` (karantænetal), `byg-liste.ts`
(arbejdsliste, 73 forældrepar sorteret efter hvor mange børn de frigiver), `effekt.ts`,
`normaliseret.ts`. Alle read-only, og de kører den rigtige kode frem for at gengive reglerne.

**Udestår:** matcharbejdet selv (73 forældrepar → 287 karantænerede par frigives).
Arbejdslisten ligger gitignoreret i `work/`.

**CI:** R-jobbet tog 42 minutter fordi `duckdb` blev kompileret fra kilde ved hver kørsel.
Cache på `R_LIBS_USER` + idempotent install: **42m10s → 45s**, hele CI under 2 minutter. (#92)

## 1939-kvalitetsvurdering + re-segmentering — LIVE i prod (2026-07-26)

Brugerspørgsmål: er 1939-indlæsningen for dårlig, og kan matcharbejdet reddes?
Svaret er kvantificeret i to rapporter under `docs/reviews/`.

**Måling.** Strukturelt: 1939 har 355/539 hovedposter med forældrelink mod 2018-20's 566/591,
og 3,76 fakta pr. person mod 5,33. Datoparsingen er derimod *bedre* (7,8 % uparsede mod 16,4 %),
og tegn-niveau-OCR var allerede rettet af Calamari-patchen. Restdefekten var **segmentering**:
280 af 539 narrativer (51,9 %) havde mindst én snitfejl.

**Stikprøve-audit (N=25, bedømt mod renderede PDF-sider, ikke mod OCR-teksten).**
~54 % af posterne har ≥1 materiel fejl — men **0 forkerte navne, 0 forkerte fødsels-/dødsår,
0 forkerte ægtefæller**. Fejlene er udeladelser og fejlklip, ikke forkerte påstande. Fund der
ikke kan ses i SQL: mor mangler bag et gyldigt far-link i ~12 % (den strukturelle måling
undervurderer altså problemet), inkonsistent linking inden for samme kuld, og en OCR-fejl i en
kildehenvisning (`Aarb. LVIII` for `XLVIII`).

**Re-segmentering (trin 1) anvendt mod prod.** Fem rettelser i `segment_1939.py`:
kuld-overskrifter som snitgrænse, bar romertalslinje, bindestreg-normalisering (orddelte navne
ved linjeskift), `_orig_nr`-præference (`nr` er en global tæller i 1939-artefaktet, så
nummer-ankeret var reelt dødt) og snap-back til postens egen nummerlinje. Defekt-union
**280 → 159**; pipelinens kvalitetsgate gik fra rød til grøn (R1/R6-proxy 88,8 % → 91,2 %) —
artefaktet der lå i prod var accepteret med fejlende gate. I stikprøven: 16 defekte narrativer
→ 5, heraf 11 nu ordret identiske med bogen.

**Anvendt:** `R/update-1939-narratives.R` mod `xjnvdhajfyrcytatnzos`, 216 rækker,
`change_set=493`, 216 audit-events. Kun `narrative.tekst` — 0 sideændringer, ingen personer,
ingen `nr`, ingen links. De 429 samme_som-matchpar er urørte og desuden sikkerhedskopieret med
navn + rå datoer i `work_1939_stamtavle/match_backup_2026-07-26.json`. Prod-fingeraftryk
verificeret identisk med artefaktet efter apply.

**Trukket tilbage undervejs:** en sjette rettelse (indsnævring af fallback-blokke) målte som en
forbedring, men stikprøven viste at den bandt post 276/277 til en anden families børn med samme
fornavne. `_orig_nr` er ikke pålideligt scopet til postens egen blok. Reverteret før apply.

**Udestår:** 12 af de 216 ændrede rækker er allerede publiceret (`staged=false`) og slog derfor
igennem i den offentlige visning med det samme. Trin 2 (re-ekstraktion af fakta mod de ~51 %
mangelfulde forældrelinks) kræver ny loader-kode og er ikke startet. 2018-20 er ikke auditeret
med samme harness.

## Mediehåndtering fase 4 — LIVE i prod (2026-07-22)

Fase 4 er deployet til produktion samme dag som lokal verifikation (PR #75 merget):
krypteret backup taget først; migrationsblokken `mediehaandtering_fase4_identitet`
anvendt; alle fire fase-4-verify-blokke kørt og bestået direkte mod prod (impersoneret
den reelle redaktion-profil, ingen testdata-rester bagefter); `get_advisors(security)`
viste kun de allerede kendte SECURITY DEFINER-mønstre (samme som alle øvrige `red_*`-
funktioner) — ingen nye fund. Web app-deployet via Vercel. Redaktøren gennemførte en
fuld røgtest af alle tre flows (erstat fil, slet permanent, sæt/fjern portræt) med
succes. Første `R/media-janitor.R`-kørsel (rapport-only) efter et reelt erstat-forløb
bekræftede at de tre gamle byte-objekter (large/medium/thumb) korrekt identificeres som
forældreløse (kategori b) med anbefalingen "afvent frist" — ingen `--slet` kørt.

## Præsensliste: patrilineær efterkommer-tilhør rettet mod rigtig prod-data (2026-07-23)

Brugerfund ved faktisk brug af den nye præsensliste: et barn af to blod-Reventlow-forældre
(to grene der giftede sig sammen) blev vist under BEGGE forældres efterkommer-liste — men DAA
er patrilineær, så barnet hører kun til under faderen. Rettet i to omgange (task-reviewer fangede
en reel regression i første forsøg — se `docs/decisions.md` for det fulde forløb): ny
`patrilinealForaelder`-hjælper i `packages/core/src/presensListe.ts`, og `blodOgGiftInd`
(klatrings-heuristikken) gjort konsekvent med den samme regel i stedet for sin egen separate
rigdoms-heuristik. Superseder `krydsReference`-mekanismen for "barn af to kendte forældre" —
ambiguiteten løses nu før krydshenvisning bliver relevant. Core-suite: 301/301. Ingen
prod-datarettelse nødvendig (kun algoritmen var forkert).

## Præsensliste-visning v1 — implementeret på feature-branch (2026-07-22)

Beregnet, anker-baseret præsensliste-læsevisning (web + mobil), designet og planlagt
samme dag (`docs/superpowers/specs/2026-07-22-praesensliste-visning-design.md` +
`docs/superpowers/plans/2026-07-22-praesensliste-visning.md`), derefter eksekveret via
subagent-driven-development: Codex (`gpt-5.6-sol`) som implementer pr. task, uafhængige
Claude-subagenter som task-reviewere. Alle 10 tasks grønne og godkendt:

- **Core (`packages/core`):** ny `presensLabels.ts` (anker-parse + dansk
  overskrift-generator: FARBROR/FARS SØSTER/SØSTRE, genitivkæder, kønssymmetri) og
  `presensListe.ts` (bottom-up-beskæring af afdøde uden levende efterkommere,
  anker-klatring, relationsgrupper, gren-partitionering via ankersæt, redaktionelle
  advarsler). Facitliste-test reproducerer DAA 2012-14 II linje 1. grens gruppestruktur.
  Suite: 297/297 (efter krydshenvisnings-tilføjelsen, se nedenfor).
- **Vokabular:** ny faktatype `overhoved` (schema.sql + db-migrations.sql + db-verify.sql)
  — udpeger linje-/gren-overhoveder som redaktionelt fakta, ingen skemaændring. Genbruger
  eksisterende `red_upsert_fakta`/`red_opret_fakta`-flow i person-editoren (web + mobil).
  **Prod-apply udført 2026-07-22** (bruger-godkendt) — se `docs/decisions.md` for verifikation.
- **Web:** ny "Præsensliste"-fane i Følgesvend-navigationen (`/praesens`), redaktion-gated,
  "Vis i præsensliste"-genvej fra person-detaljepanelet. Suite: 427/427.
- **Mobil:** ny `/praesens`-skærm + drawer-punkt 09, spejler webbens gating/tomtilstande/
  partner-visning. Suite: 348/348.
- **Fund undervejs (rettet, se `docs/decisions.md` for detaljer):** en Vitest-dobbelt-
  test-registrering pga. sibling-test-import (rettet: udtrukket delte fixtures til egen
  fil); mobil-skærmens manglende partner-visning + indlejrede komponenter (rettet); mobil
  manglede `canonicalIdById` på modellen (gjorde samme_som-kanonisering til en no-op på
  mobil — rettet, fanget af slut-reviewet).
- **Struktur-begrænsning RETTET 2026-07-22 (bruger-beslutning "vis én gang +
  krydshenvisning"):** en levende person nået ad to veje inden for SAMME ankers
  undertræ/gren (fx et dobbelt-fætterskab) blev tidligere enten stille droppet eller vist
  dobbelt. `pruneUndertrae` deler nu ét `alleredeVist`-sæt på tværs af hele grenens
  opbygning; første forekomst vises fuldt, senere forekomster bliver en
  `krydsReference`-stub med en synlig note i UI'et. Krydsning MELLEM grene
  (`dobbelt_naaet`-advarslen) er uændret. Se `docs/decisions.md`.
- **Trust-note:** Codex' selv-rapportering viste sig ved ét task at være opdigtet (beskrev
  ikke-eksisterende kode); den faktiske kode var korrekt i alle 10 tasks, fanget fordi hver
  task blev uafhængigt genverificeret (kontrollør kørte selv test-suiter, reviewer læste
  kun diffen).
- **Branch:** `feat/praesensliste` — [PR #76](https://github.com/johanreventlow/Danmarks-Adels-Aarbog/pull/76)
  (draft), afventer brugergodkendelse af merge.

## Mediehåndtering fase 4 — implementeret og verificeret lokalt (2026-07-22)

Fase 4 ("identitet & endeligt farvel") er implementeret lokalt via subagent-drevet
udvikling (Claude på DB-tasks, Codex gpt-5.6-sol på TS/React-tasks, dobbelt-review pr.
task): `red_erstat_media_fil` (M4, erstat bytes men behold identitet — id/relationer/
mentions/rettigheder uændret, filhistorik er fortryd-historikken), `red_udrens_media`
+ preview (M11, den rigtige permanente sletning — kun fra `'fjernet'`, blokeret af ALLE
polymorfe ankre: relation, text_mention, fakta m. evidenskæde, story, narrativ, note,
og — fundet under implementering, ikke i den oprindelige spec — `suggestion`; guard+slet
er ét atomisk statement), og `red_saet_portraet` + `relation.kvalifikator` (M10,
portræt-valg som redaktionelt fravalg af heuristikken, ikke dens erstatning).

Dual-reviewet design (`docs/reviews/34-mediehaandtering-fase4-plan-dual-review.md`) fandt
og rettede tre fund FØR implementering (manglende fakta-/story-/narrativ-anker, en
check-then-delete-race, NULL-blinde test-assertions) samt ét under implementeringen
(den manglende `suggestion`-anker). Per-task-review fandt yderligere fem reelle fund,
alle rettet: en check-then-act-race i erstat-filens statustjek, manglende oversættelse af
domænefejl, en foldet-samme_som-dedup der kunne tabe portræt-flaget til rækkefølge
(fundet og rettet på BÅDE web og mobile), en fejlagtig "mislykkedes"-besked efter en
allerede gennemført permanent sletning, og manglende dobbeltklik-beskyttelse på de nye
handlinger. To fund blev bevidst accepteret som restrisiko frem for at udvide scope:
en resterende (indsnævret, ikke elimineret) race på tværs af eksisterende, urørte
skrive-RPC'er (§10.2-afvejningen), og en tilsvarende resterende race i mobilens delte,
allerede-eksisterende `SkrivePreviewSheet`-komponent (prod-dato fra før fase 4, bruges
af fire andre skærme — uden for denne fases filscope).

Verificeret: frisk `schema.sql`-install og migrationssti (`mediehaandtering_fase4_identitet`)
konvergerer til identisk flade (tomt `diff`); alle fire fase-4-verify-blokke grønne ad
begge veje; web (tsc + 460 tests + build) og mobile (tsc + 375 tests) grønne; empirisk
ende-til-ende bekræftet mod lokal Postgres (erstat bevarer identitet, udrens
blokeres/lykkes korrekt, portræt sættes/ryddes korrekt). Ingen janitor-kodeændring
(kategori b dækker allerede erstat-/udrens-efterladenskaber); ingen RLS-fil ændret.
**Prod-deploy udestår som separat, gated trin** (egen runbook, fase 3-præcedensen);
mobile er dev-only i dette projekt, så app-deploy dækker kun web.

## Mediehåndtering fase 3 — LIVE i prod (2026-07-21)

Fase 3-koden er implementeret lokalt: nye uploads hashes over de genkodede large-bytes,
bruger deterministiske sha-stier og kan genoptages idempotent; web og mobil tilbyder
tilknytning til et allerede eksisterende medie. Biblioteket viser alder på strandede
uploads og en heuristisk dubletkø med blødt flet-flow. `R/media-janitor.R` er
rapport-first; destruktiv DB/Storage-oprydning kræver `--slet`, og sha-backfill kræver
sit separate `--backfill-sha`-flag.

Slutreviewet lukkede tre dataintegritetskanter: blød flet bruger nu en atomisk RPC, der
afviser evidensbærende relationer; janitoren bærer PostgreSQL `BIGINT`-id'er tabsfrit som
tekst; og normal web-/mobilupload bekræfter først `klar`, når alle varianter er uploadet
og registreret. Lokal slutverifikation efter merge af `origin/main`: web TypeScript +
422 tests + build, mobil TypeScript + 345 tests, core TypeScript + 267 tests og
R/testthat 420 tests var grønne. DAA-loaderens COPY-rækkefølge er samtidig låst af en
import-smoke, så relationer skrives før deres assertion/citation/conclusion-evidens.
Isoleret PostgreSQL 17 bekræftede både frisk skema og
den præcist scoped migrationssti fra præ-fase-3-basen; migrationen var idempotent ved to
gennemløb, bevarede ukendt historisk `created_at` som `NULL`, ryddede kun evidensfri
relationsdubletter og fejlede højlydt på en evidensbærende dublet. En reel to-session-test
bekræftede begge rækkefølger: writer-før-unlink afviser sletningen med relation og
evidens bevaret; unlink-før-writer afviser writeren uden orphan-data. Fresh og migration
gav samme fase 3-flade (`media.created_at`, `relation_afbildet_uidx`, `ix_note_target`,
relationsevidens-triggerne, `red_relation` og `red_slet_medierelation_uden_evidens`).
Ingen RLS-fil eller gamle storage-stier er ændret.

Tre implementeringsskøn er nu fastholdt: janitorens standardfrist er 7 dage og UI's
"muligvis i gang"-grænse er 1 time; dubletkøens nøgle er præcis
`(byte_size, bredde, hoejde)` uden `mime_type`; mobil bruger `expo-crypto` frem for
`@noble/hashes`. Tilføjelsen af det native Expo-modul kræver genbygning af dev- og
release-builds — en JavaScript-only opdatering er ikke tilstrækkelig.

**Prod-cutover afsluttet:** Den scoped blok blev anvendt mod
`xjnvdhajfyrcytatnzos` fra `caeb6a3`; web-produktionen og en ny native iOS Release blev
verificeret, og redaktør-røgtesten er udført. Første janitor-kørsel var rapport-only og
fandt 0 strandede uploads, 0 forældreløse objekter, 2 variant-huller og 6
SHA-backfill-kandidater. Der blev ikke kørt `--slet` eller `--backfill-sha`; begge er
fortsat særskilte, eksplicitte opt-ins. Se den lukkede
`docs/db-backups/2026-07-20-mediehaandtering-fase3-runbook.md` for deployloggen.

## Mediehåndtering fase 3 — implementeringsplan skrevet + dual-reviewet (2026-07-20)

Implementeringsplan (10 TDD-tasks, skrevet af Fable): `docs/superpowers/plans/2026-07-20-mediehaandtering-fase3-hygiejne.md`,
mod den mergede fase 3-spec. Dual-reviewet (`docs/reviews/33-mediehaandtering-fase3-plan-dual-review.md`)
— to uafhængige gennemgange (Codex var ikke tilgængeligt som værktøj i denne sessions miljø,
så anden-reviewer-rollen blev udfyldt af en fuldt uafhængig subagent i stedet, dokumenteret
eksplicit i reviewet). Fund: en fjerde, udokumenteret FK (`haendelse.relation_id → relation`)
i den evidens-sikre oprydnings-DELETE — verificeret strukturelt uskadelig i dag (kun skrives
for conclusion-bærende relationer, som DELETE'en allerede udelukker), men nu dokumenteret +
en defensiv `foreign_key_violation`-fangst tilføjet til janitorens sletning som fremtidssikring;
en accepteret race-vindue-restrisiko i dedup-guardens fejltekst (ingen kodeændring); og en
rækkefølge-fix i "Flet ind i…"-flowet (parkér kopien i papirkurven FØR relationerne flyttes,
så et afbrudt flet altid lander i en allerede håndteret tilstand). Klar til PR — implementering
ikke påbegyndt.

## Mediehåndtering fase 1+2 + levende feed fase 2-3 + K2 selektiv publicering — LIVE i prod (2026-07-20)

Deployet direkte til produktionsdatabasen via Supabase MCP (bruger-godkendt, kørt fra
sessionen — ikke den forberedte manuelle `psql`/dashboard-runbook). Et live objektinventar
(tabeller + `pg_proc`-funktionsnavne sammenlignet mod `db-migrations.sql`) afslørede at
`docs/database-current-state.md`s "sidst afstemt 2026-07-01" var stærkt forældet: alt
arbejde dateret 2026-07-02–2026-07-17 (samme_som, udledt slægtsnavn, dato-hærdning,
Problem 2 fase 1, K2 staging-gate) var reelt allerede live, blot udokumenteret. Kun tre
ting manglede: `haendelse` (levende feed fase 2), `story`/`story_kilde`/`feed_pin`
(levende feed fase 3) og `red_publicer_personer` (K2 selektiv publicering, samme dags dato)
— alle tre nu deployet, samt mediehåndtering fase 1+2 (se tidligere entries) og hele
`db-rls.sql` (retter `text_mention`s manglende `GRANT SELECT` + `tm_read`s fail-open
media-gren). `get_advisors(security)` efter apply: 117 fund, alle kendte mønstre
(SECURITY DEFINER-eksponering af `red_*`, bevidst deny-all på historiktabeller) — ingen nye.
Se `docs/database-current-state.md` for den fulde, ajourførte status.

**Ikke-oplagt:** de to store `apply_migration`-kald (2.9k-linjers `db-migrations.sql` og
723-linjers `db-rls.sql`) blev IKKE sendt i fuld længde — at læse begge filer ind i sin
helhed ville have brugt langt mere kontekst end rådighed. I stedet blev et præcist
objekt-diff (forventet vs. faktisk) brugt til at finde de tre manglende regioner, som
derefter blev udtrukket med `sed`/`grep` og verificeret linje-for-linje før anvendelse;
`db-rls.sql` blev læst i sin helhed (mindre fil, sikkerhedskritisk indhold) og kørt uændret.
Undervejs droppede Supabase-MCP-forbindelsen midt i et `apply_migration`-kald (brugerens
togforbindelse) — ingen skade, da alle statements er idempotente og hele kaldet var én
transaktion, der rullede atomisk tilbage; blev opdaget og genkørt efter reconnect.

## Operatørguide afstemt mod read-only prod-facit (2026-07-20)

**Denne audit var read-only og forud for deploy-entryen ovenfor** — dens "ikke live"-
konklusion for levende feed fase 2/3 og mediefase 1–2 er indhentet af samme dags deploy;
bevaret som historik for selve audit-fundet (dokumentationsdrift), ikke som aktuel status.

`docs/database-current-state.md` blev omskrevet fra det forældede 1. juli-snapshot til
en aktuel skelnen mellem repo, app og prod. Read-only katalog-/aggregatqueries mod
prod `xjnvdhajfyrcytatnzos` bekræftede: 1.758 personer, 835 staged, 77 levende;
`anon` og almindelig `authenticated` ser begge 853 personer og 0 levende/staged;
921 forældrefamilie-facts; 22 versionerede tabeller; 6 media-rækker (2 klare, 4
fjernede); samt at `_delete_relation_evidence` ikke er API-eksekverbar for anon/auth.

Problem 2/A1/K2 og media Slice 0 var live. 1939-source 3 forbliver staged og usynlig.
Gældende beslutning er **ingen publicering** før nyt OCR-udtræk og gentaget
artefakt-/komplethedsgate. Den ældre 1939-plan er bevaret som fasehistorik, ikke som
aktuel publiceringsordre. Ingen prod-skrivning eller schemaændring blev udført i denne
dokumentationsrunde.

## Mediehåndtering fase 3 — hygiejne-spec skrevet (2026-07-20)

Design-spec skrevet (ingen kode): `docs/superpowers/specs/2026-07-20-mediehaandtering-fase3-hygiejne-design.md`
— aktiverer den hidtil døde dedup-mekanisme (klienten beregner sha256 af large-bytes:
Web Crypto på web, expo-crypto på mobile), skifter til deterministiske sha-stier
(`redaktor/<xx>/<sha>-{tier}.jpg`, idempotent genupload) og oversætter DB-guardens fejl
til et "Billedet findes allerede → tilknyt i stedet"-flow oven på fase 2's tilknyt-mekanisme,
inkl. selvhelende genoptagelse af strandede kladder. Additiv `media.created_at` (to-trins
ALTER — ét-trins DEFAULT now() ville stemple alle gamle rækker med migrations-tidspunktet)
giver strandede-køen alder, og et partielt unikt index (`WHERE rolle='afbildet'`) lukker
fase 2's kendte relations-dublet-gap uden at røre periode-bårne roller som `ejer`.

Ikke-oplagte valg: sha tages af de GENKODEDE bytes, så dedup fanger samme pipeline-upload
men ikke web-vs-mobile-dubletter; da `media_sha256_uidx` gør sha-dubletter strukturelt
umulige, kører bibliotekets nye "Mulige dubletter"-kø på en (byte_size,bredde,hoejde)-
heuristik, mens janitorens sha-backfill leverer den ægte dublet-liste. "Flet ind i…" er
klient-orkestreret af eksisterende RPC'er og stopper ved blødt fjern — udrensning er
fortsat fase 4. Janitoren (`R/media-janitor.R`) er rapport-first: `--slet`/`--backfill-sha`
er eksplicitte flag, frist-gated, og rækker med ukendt alder røres aldrig.

## Mediehåndtering fase 2 — biblioteket implementeret lokalt (2026-07-19)

Web og mobil har nu et samlet mediebibliotek med søgning, køerne Rettigheder/Løse/
Strandede/Papirkurv, format-defensive thumbnails og en filside med “bruges på”.
Eksisterende medier kan tilknyttes personer, godser, våben og linjer gennem den
eksisterende GDPR-gatede `red_relation`; sletning er fail-closed, indtil anvendelser
er hentet, og relationer kan fjernes enkeltvis. Indsættelsespickere og Lightbox viser
fortsat kun klare billedmedier.

Databasekoden udvider `red_doede_links` med media-mål, mens RLS skelner mellem
redaktionens fulde mention-overblik og anon/medlems synlighed. Implementeringen og
dens migration er verificeret lokalt; intet er deployet til prod. Prod-trinnet er
fortsat gated og skal samle fase 1 + fase 2, `db-rls.sql`, verify-filer og app-deploy
efter read-only backup og eksplicit brugeraccept.

Kendt follow-up: pickerene skjuler allerede tilknyttede mål, og bibliotekstællinger
deduplikerer mål, men `relation` har endnu ingen databaseunikhed for identiske
`afbildet`-relationer. Direkte eller samtidige RPC-kald kan derfor stadig skabe en
dublet, som skal afkobles række for række.

## Mediehåndtering fase 2 — implementeringsplan (2026-07-19)

Plan skrevet (ingen kode): `docs/superpowers/plans/2026-07-19-mediehaandtering-fase2-bibliotek.md`
— 7 tasks med TDD-tjekbokse oven på fase 2-spec'en, forankret i kortlægningens
fil:linje-referencer. Ikke-oplagte punkter: NY Global Constraint "CI-hygiejne" (læring
fra fase 1-kørslen: ingen workflow-ændringer, aldrig `contents: write`, aldrig
selv-committende jobs — normal CI skal køre på den endelige HEAD, hvilket også står i
Definition of Done); biblioteks-query'en må IKKE filtrere `upload_status` (køerne er
pointen) mens pickers/Lightbox fortsat filtrerer `'klar'`; `klassificerMedie` holdes
tegn-for-tegn i sync web/mobile; prod-runbook'en samler fase 1-migrationen (endnu ikke
deployet) med fase 2's view-ændring i ét gated deploy.

## Mediehåndtering — dokumenter/transskription besluttet som fase 5 (2026-07-19)

Bruger-rejst behov (PDF/indscannede kilder + rå tekst-version af fx artikler; teoretisk
lyd/video) er designafklaret og skrevet ind: koncept-§4.8 + fasetabel-fase 5,
beslutningsnotat i `docs/decisions.md`. Kerne: samme media-system (tabellen er allerede
format-agnostisk; kun klient-laget er billede-specifikt), transskription som
narrativ-på-media (polymorf `narrative`, fts-søgbar — kræver egen GDPR-designrunde),
lyd/video kun som åben dør. Eneste fase 2-konsekvens indskrevet i spec-§6.1: defensiv
thumb-rendering (ikke-billede-mime → dokument-ikon, udeladt af Lightbox) — additiv
regel, ingen scope-udvidelse.

## Mediehåndtering fase 2 — design-spec for biblioteket (2026-07-19)

Spec skrevet (ingen kode), efter fase 1 er merget til main (PR #59):
`docs/superpowers/specs/2026-07-19-mediehaandtering-fase2-bibliotek-design.md` omsætter
konceptets fase 2 (M5–M7 + M9's synlighed) til 6 skiver. Empirisk forankret i den
mergede fase 1-kode: web's "Medier"-fane FINDES allerede men er tom
(`fetchEntityRecords('media')` → `[]` — fanen skal fyldes, ikke opfindes);
`red_relation(...,'afbildet')` findes server-side med GDPR-guard men er ueksponeret i
UI (ny Change-art `tilknytMedia` med klient-sidet retningsforgrening, server-guard som
bagstopper); `text_mention`+`ix_text_mention_maal` dækker allerede media ("bruges på"
er tre små queries, on-demand pr. filside). Kun ÉN DB-ændring: `red_doede_links` får
media-gren (kun ikke-eksisterende media = dødt link; fjernet medie er IKKE dødt — det
kan genoprettes og synliggøres via papirkurven). Kø-klassifikation som ren, testbar
funktion; strandede-køen UDEN aldersfilter (media har ingen `created_at` — kolonnen
udskudt til fase 3's janitor, åbent punkt §9.1). Lukker koncept-§10.5: mobile får
kø-tællere + tappbare rækker + fuld filside, web er primærflade for kø-arbejde.

## Mediehåndtering fase 1 — implementeringsplan (2026-07-19)

Plan skrevet (ingen kode): `docs/superpowers/plans/2026-07-19-mediehaandtering-fase1-filside.md`
— 9 tasks med TDD-tjekbokse oven på fase 1-spec'en. Ikke-oplagte valg: RPC-asserts
lægges i `db-verify.sql` efter det ETABLEREDE impersonerings-mønster (Task 5/5b:
`request.jwt.claim.sub` + profiles-seed + ROLLBACK_TEST_OK) — ikke i
`db-verify-media.sql`, hvis kontrakt er RLS-only uden redaktør-kontekst (den får kun
en anon-gating-assert for fjern→genopret-cyklussen via direkte UPDATE). Migrationens
DROP af gamle `red_upload_media` skal afskrives eksplicit fra git-historikken
(14-parameter-signaturen). Task 5/6 (læse-lag viser `'fjernet'`) og Task 7/8 (UI-
filtrene) er markeret som sammenhørende — mellemtilstanden kan vise fjernede thumbs.
Prod-deploy er eksplicit UDEN FOR planen (controller-gated runbook-trin i Task 9).

## Mediehåndtering fase 1 — design-spec for filsiden (2026-07-19)

Spec skrevet (ingen kode): `docs/superpowers/specs/2026-07-19-mediehaandtering-fase1-filside-design.md`
omsætter konceptets fase 1 (M1–M3) til 6 skiver: `red_opdater_media` (NULL=uændret/''=ryd),
`red_genopret_media` (kun fra `'fjernet'`, RAISE ved 0 rækker), `red_upload_media`-
signatur-udvidelse med kunstner/datering (⚠ kræver DROP+CREATE — `CREATE OR REPLACE`
ville skabe en PostgREST-tvetydig overload OG knække det navnebaserede grant-loop),
tre nye Change-arter (`opdaterMedia`/`genopretMedia`/`mediaRettigheder` — alle uden
fil-bytes, kan degradere til red_suggest), udvidet redaktions-read hvor `'fjernet'`
nu VISES for redaktionen (med to udpegede fail-open-fælder: narrativ-billedvælgeren
og Lightbox skal eksplicit filtrere `'klar'` — redaktionens storage-politik signerer
også fjernede stier), filside-overlay (web) / `MediaDetaljeSheet` (mobile) og udvidet
upload-ark. Kendt accepteret hul: fjernet medie uden relation kan først genoprettes
når fase 2-biblioteket lander.

## Mediehåndtering — koncept for robust medieforvaltning (2026-07-19)

Nyt konceptdokument `docs/design/2026-07-19-mediehaandtering-robust-koncept.md`
(ingen kode): analyse af redaktørens nuværende medie-muligheder (empirisk kortlægning
af web+mobile+DB) og et Wikimedia-inspireret målbillede — filside pr. medie,
mediebibliotek med arbejdskøer, komplet livscyklus (genopret/udrens), rettigheds-
workflow-UI oven på det eksisterende `red_set_media_rettigheder`, erstat-fil med
stabil identitet, samt aktivering af den i praksis inaktive sha256-dedup (klienten
hasher aldrig — DB-guarden fødes ikke). 11 konkrete mangler (M1–M11) prioriteret,
4 faser, ingen nye tabeller — kun 4–5 nye `red_*`-RPC'er efter etableret konvention.
Lukker de kendte udeståender "løse billeder"-oversigt + rettigheds-UI (Slice 0h-
changelog) som del af én sammenhængende plan i stedet for spredte features.

## 1939-narrativer — deterministisk kvalitetsrettelse (2026-07-19)

1939-segmenteringen er hærdet efter empirisk fund af gruppe-/vinduesduplikering,
grænse-bleed, kørende sidehoveder og bogstavspredning. `segment_1939.py` bruger nu
flere kildefaste ankre og bogens egne post-/sektionsmarkører, lokale og eksplicit
navngivne fallback-metoder samt 1939-specifik tekstrensning; `extract_text.sh`
filtrerer også 1939-sidehovedet ved fremtidige udtræk. QA-loggen måler nu bl.a.
duplikatklynger, flerpost-narrativer, sidehoveder, bogstavspredning, fremmede unikke
datoer og længdehale.

Lokalt facit for 539 poster: vinduesstore narrativer 42→0, maks-længde
80.192→4.377, eksakt duplikerede poster 98→25, flerpost-narrativer 208→13,
sidehovedforekomster 625→0 og narrativer med bogstavspredning 486→0. Ingen
prod-opdatering er udført; rettet staged data kræver separat backup, rehearsal og
eksplicit godkendt 1939-only opdatering. Se
`docs/reviews/2026-07-19-1939-narrativ-kvalitet.md`.

## Levende feed fase 3 — implementeret og lokalt verificeret (2026-07-19)

Fase 3 er gennemført efter
`docs/superpowers/plans/2026-07-19-levende-feed-fase3.md`: additivt
`story`/`story_kilde`/`feed_pin`-skema med RLS, syv kontrollerede redaktions-RPC'er og
versionering; delt story-/pin-logik i `@daa/feed`; tolerant load og `historie`-kort i begge
klienter; inline story-editorer; web-feedstyring; samt portræt-pins som startpersoner med den
hidtidige kuraterede liste som fallback.

**Ekstra review og rettelser:** Medlemsflowets `red_suggest`-payload mistede tidligere
`storyId` ved redigering og medtog ikke storyens kilder. Forslaget indeholder nu både
routing-id, tekstfelter og hele kildelisten. Den direkte web-editor gemmer fortsat story og
kilder via de to eksisterende RPC'er, men udsætter person-reload til begge er lykkedes. Hvis
kildekaldet fejler efter en oprettelse, forbliver editoren åben med det persistente story-id,
så næste forsøg redigerer samme story i stedet for at oprette en dublet. Begge forløb er låst
af nye regressionstests. Slutreviewet fangede desuden et muligt overlap mellem to samtidige
gemninger: editoren har nu en single-flight/generations-guard, relevante handlinger er låst
mens begge RPC'er kører, og sene resultater ignoreres efter navigation/editor-skift. Et
vellykket medlemsforslag lukker editoren, så samme forslag ikke indsendes igen ved et ekstra
klik. Publicerings-RPC'en er samtidig gjort fail-closed: kladder må fortsat stå uden kilder,
men status kan ikke skiftes til `publiceret`, før mindst én `story_kilde` findes. Den nye
databaseassert blev først kørt rød mod den uhærdede funktion og derefter grøn mod både
clean-slate- og migrationsstien. Web-feedstyringen genbruger nu de eksisterende theme tokens
i stedet for at indføre lokale farve- og fontkopier.

**Verificeret automatisk/lokalt og i CI:** `@daa/feed` 107/107 tests + typecheck,
`@daa/core` 264/264 tests, mobil 224/224 tests + typecheck og web 235/235 tests +
produktions-build. Alle nye tests ligger i de eksisterende `feed`, `web` og `mobile`-jobs i
`.github/workflows/ci.yml`; der er ikke tilføjet fase 3-jobs, og R-jobbet er urørt. CI-kørsel
`29705889967` på commit `4b9a1d2` er grøn for feed, core, mobil, web, R og pipeline.

**Verificeret i lokal PostgreSQL:** både frisk `schema.sql` og migrationsstien fra fase 2
(`db-migrations.sql` kørt to gange, derefter `db-rls.sql`) er kørt. Den afgrænsede fase
3-blok i `db-verify.sql` er grøn for CHECK/UNIQUE/RPC-gates, anon/authenticated-RLS,
`story_kilde`-cascade og fortryd af både statusskift og hel story. En afsluttende read-only
kontrol af migrationsdatabasen bekræftede de tre tabeller, RLS/policies, story-RPC'erne og
`trg_log_story`/`trg_log_feed_pin`. Det komplette historiske `db-verify.sql` stopper fortsat
tidligere på en ældre fixture-afhængig cache-test i den tomme lokale base; fase 3-blokken er
kørt selvstændigt. Task 13-gaten blev gentaget 2026-07-20 mod den verificerede prod-backup:
3 tabeller, 7 RPC'er, 8 policies, 2 versioneringstriggers, RLS på alle tre og 0 ugyldige
constraints; anon kunne kalde 0/7 RPC'er, mens authenticated kunne kalde 7/7.

**Rollback-beredskab:** Den separate `db-rollback-fase3.sql` er lokalt rehearsed. Den kører i
én transaktion og afbryder ved fase 3-data eller -historik, så den kun kan fjerne det tomme
additive lag efter en fuld backup. Task 13-gaten kørte rollbacken to gange og bekræftede
idempotens, 0 resterende fase 3-objekter og bevaret fase 2-`haendelse`; det er ikke en
prod-migrering eller et prod-bevis.

**Manuel UI-status og resterende deploy-gates:** Et lokalt browser-smoke dækkede kort-views,
editor-/feedstyringsflader og staging-preview, men Task 8/10/11's komplette LIVE-forløb
(opret/publicér/arkivér/fortryd story, pin/skjul/fjern og authenticated medlemsstaging) er
ikke kørt mod en Supabase-kopi, fordi en sådan kopi ikke er tilgængelig. Derfor er rigtig
PostgREST-nesting, JWT-rolleoverførsel, schema-cache og Supabase security advisors heller ikke
end-to-end-verificeret. De punkter er deploy-gates, ikke skjult som lokale testresultater.

**Prod-status:** Ingen prod-migration eller prod-skrivning er udført.
`docs/database-current-state.md` er bevidst uændret og må først opdateres efter en eksplicit
gated prod-migrering.

## Levende feed fase 2 — implementeret i kode (2026-07-18)

Fase 2 er gennemført efter `docs/superpowers/plans/2026-07-18-levende-feed-fase2.md`:
additiv `haendelse`-projektion med RLS, kontrolleret status-RPC og versionering; hændelses-load
i begge klienter; hændelsesdrevne `arkiv`-, `citat`- og `paadennedag`-kort; den nye
`.claude/skills/daa-haendelser`-pipeline; samt redaktionens kronologiske hændelsestidslinje
og statusmarkering på web og mobil. Fase 1-reviewfund er samtidig indarbejdet.

**Verificeret automatisk/lokalt:** frisk schema-installation og migrationsstien (migrationen
kørt to gange) mod lokale PostgreSQL-databaser; fase 2's målrettede CHECK/RLS/RPC/versionerings-
asserts; GDPR-eksportens optælling mod den samme lokale kopi (544 eksporterede, 47 ikke-
offentlige kandidater udeladt); H1–H8-validatorens og den fail-closed Opus-promotions
Python-tests; R-loaderens merge-tests;
loader-`--dry-run` med rollback; samt genkørsel oven på en markeret hændelse, hvor både id og
`feed_status='interessant'` blev bevaret. Klient-, core-, feed-, R- og pipeline-suiterne samt
web-build er kørt lokalt; CI har fået et særskilt `pipeline · unittest`-job.

**Ikke manuelt verificeret:** den samlede redaktør-UI mod en autentificeret PostgREST-session
i browser/simulator. UI'ens data-, status-, staging- og tidslinjelogik er dækket af tests og
typecheck/build. Det komplette historiske `db-verify.sql` når fase 2-blokken, men stopper senere
i en allerede eksisterende rolle-gating-test for `red_slet_oplysning`; fase 2's målrettede
DB-verifikation er grøn.

**Prod-status:** Ingen prod-migration og intet prod-pipeline-load er udført. Det er fortsat
separate, eksplicit godkendte deploytrin; `docs/database-current-state.md` er derfor uændret.

## Levende feed fase 2 — implementeringsplan skrevet (2026-07-18)

`docs/superpowers/plans/2026-07-18-levende-feed-fase2.md` (13 tasks, TDD task-for-task efter
fase 1-planens skabelon) omsætter design-specen til konkrete skridt: skive 1 (DB) → task 1,
skive 3 (klient-load) → task 2-4, skive 4 (motor: arkiv/paadennedag/citat/kort-views) → task
5-7, skive 2 (offline pipeline `daa-haendelser`) → task 8-10, skive 5 (redaktions-tidslinje)
→ task 11-12, skive 6 (CI+afstemning) → task 13. Skrevet af en Fable-subagent, der undersøgte
den faktiske kodebase (ikke kun specen) for præcise filstier/linjenumre/funktionssignaturer —
egen efterfølgende verifikation fandt og rettede én reel fejl: agentens påstand om at
versionerings-infrastrukturen (`version_pk_registry` + trigger-loop) kun findes i
`db-migrations.sql` var forkert (den findes i BÅDE `schema.sql` og `db-migrations.sql`, med
forskellig håndtering nødvendig i hver — se planens Self-review-noter); uden rettelsen ville
en frisk clean-slate-deploy mangle `trg_log_haendelse`. Øvrige åbne verifikationspunkter
(fx om PostgREST tillader dobbelt-nestede selects) er ærligt flagget i planen som
implementer-verifikation, ikke påstået som fakta. Ingen kode er ændret; implementeringen
starter ikke før eksplicit anmodning.

## Levende feed fase 2 — design-spec skrevet (2026-07-18)

`docs/superpowers/specs/2026-07-18-levende-feed-fase2-design.md` (6 skiver) beskriver
hændelses-skelettet: ny tabel `haendelse` (regenerérbar projektion oven på fact/
assertion/conclusion — aldrig ny evidens), offline LLM-ekstraktionspipeline
(`.claude/skills/daa-haendelser/`, samme eksport→LLM→valider (H1–H8)→load-mønster
som daa-extract) med bevarelses-mergende genkørsel via en stabil nøgle (normaliseret
klausul + #N-suffiks ved dubletter), RLS via `entitet_offentlig`-kaskade, ny RPC
`red_set_haendelse_status`, `arkiv`-korttype + udvidet `paadennedag` + klausul-baseret
`citat` i `@daa/feed`, og redaktionens hændelses-tidslinje (begge apps). Skrevet af en
Fable-subagent efter eksplicit anmodning; ni DB-mekanismer verificeret uafhængigt mod
`schema.sql`/`db-migrations.sql`/`db-rls.sql` (funktion-signaturer, `vocab`-PK-form,
`staged`-kolonnen, `entitet_offentlig`-brug) — alle stemmer. Endnu ikke implementeret;
ingen plan skrevet.

## Levende feed fase 1 — implementeret (2026-07-18)

Fase 1 (dynamik & uendelig scroll) af `docs/design/2026-07-18-levende-feed-koncept.md` er
gennemført task-for-task efter `docs/superpowers/plans/2026-07-18-levende-feed-fase1.md`.
12 tasks, alle grønne (`@daa/core` 254 tests · `@daa/feed` 59 tests · mobil tsc+jest 196
tests · web tsc+vitest 188 tests + build + 3× stabil Playwright-e2e).

**Ny pakke `@daa/feed`** (`packages/feed/`, eget CI-job): kandidat-pool (builders porteret
fra mobilens v3-`buildFeed`, caps fjernet) → forklarlig scoring (BASE-vægte pr. kind,
timeliness/personal/seen-faktorer) → seedet vægtet trækning uden tilbagelægning
(mulberry32) med rytme-regler (R1 ikke-samme-kind, R2 person-afstand, R3 mindst ét
portræt pr. 6) og eskalerende relaksering når kind-diversitet løber tør → positionslåse
(dagensperson, slaegt) via byt (ikke fjern+genindsæt — undgår at sammenføje naboer) →
strøm-API (`createFeedStream`/`resumeStream`) med bevist `next(a)+next(b) ≡ next(a+b)`.
To nye korttyper: `paadennedag` (dag-præcis, med måneds-fallback) og `dagensperson`
(dagligt roterende, disjunkt fra portræt/citat). Livsdato-join (fact→conclusion→assertion)
er delt logik; hver app henter selv (mobil: parallelt med hoved-batchen i `load.ts`; web:
ved feed-mount i `feedAux.ts`/`livsdato.ts`) — `visning_foedt/doed` er rå datotekst og kan
ikke bære dag-præcision.

**Mobil:** forsiden doserer nu via `createFeedStream` (seed = dagsdato + tilfældig nonce,
det eneste sted `Math.random` optræder), ægte `onEndReached`-append, pull-to-refresh =
nyt seed, footer med tre reelle tilstande. Set-hukommelse i AsyncStorage (LRU 300,
decay-vægte 0.25/0.5/0.75). Gamle `buildFeed.ts`/`feedHash.ts` + deres testsuite slettet
(ingen forbrugere tilbage — alle imports peger nu på `@daa/feed`).

**Web:** ny `FeedStreamView` monteret under forsidens hero/kuraterede sektion (samme motor
og kort-katalog som mobil, egne kort-views i webbens idiom). Bio hentes og stemples ind i
en model-kopi ved feed-mount (`fetchFeedBios`/`withFeedBios`); ved ankomst genopbygges
strømmen med samme seed og genoptages via `resumeStream`, uden at nulstille allerede viste
kort. **Reel bug fanget af den nybyggede e2e-test (Playwright, bootstrappet fra bunden —
ingen opsætning fandtes forud):** uendelig-scroll-sentinellen brugte en
`IntersectionObserver` med standard-root (viewporten), men Følgesvendens rodlayout scroller
i en indre `[data-scroll]`-container (`height:100vh; overflow:hidden` på roden) — observeren
så derfor aldrig sentinellen krydse ind/ud og fejlede helt stille. Erstattet med en
`scroll`-lytter direkte på `[data-scroll]` + en synkron "fyld skærmen"-efterkontrol (dækker
både ægte scroll og "indhold ankommer uden at brugeren scroller", fx bios der forlænger en
kort forside). 18/18 e2e-kørsler grønne efter fixet.

**Oprydning:** `interleave` (ubrugt — rytmen er vægtet trækning, ikke round-robin) fjernet
fra `@daa/feed`s offentlige API. v3-spec'en (2026-07-05) har fået en status-note: §3
(feed-datamodellen) er afløst; §4-6 (UI/drawer/bogmærker) er fortsat gældende. Ingen
backend-/skemaændringer i hele fasen.

## Plan: levende feed fase 1 — klar til implementering (2026-07-18)

Implementeringsplan for fase 1-spec'en: **`docs/superpowers/plans/2026-07-18-levende-feed-fase1.md`**
— 12 tasks i TDD-stil (fejlende test → implementér → grøn → commit) i eksekverbar rækkefølge:
pakke-skelet+prng → typer+pool → tidslige kort → scoring+ordning → strøm → mobil livsdato/seen/dosering
→ web datalag/views/e2e → oprydning. Pakke-invariant fastlagt: `@daa/feed` er netværksfri (rene
join-/decay-helpers i pakken, fetch i app-lagene); `resumeStream` definerer den append-sikre
genoptagelse ved webs bio-ankomst. Punkter implementer skal slå efter frem for at gætte er markeret
eksplicit (core-exportmekanisme, Aux-feltformer, pickPreferredBio-signatur, web-nav-handlers,
Playwright-placering). Dokumentationssporet (koncept → spec → plan) er hermed komplet — implementering
kan køres af en eksekverende session/model uden yderligere designbeslutninger.

## Spec: levende feed fase 1 — dynamik & uendelig scroll (2026-07-18)

Design-spec for feed-konceptets fase 1: **`docs/superpowers/specs/2026-07-18-levende-feed-fase1-design.md`**.
6 skiver: (1) ny delt pakke `@daa/feed` (lukker konceptets ○a) med motor-kernen pool → score → seeded
sampling (mulberry32) → rytme-regler, caps/interleave udgår; (2) strøm-API `createFeedStream` med
`next(n)`-stabilitet og ærligt terminalkort; (3) mobil: ægte dosering via `onEndReached`, pull-to-refresh
= nyt seed, set-hukommelse i AsyncStorage (LRU 300, decay-vægte); (4) tidslige kort — `paadennedag` +
`dagensperson` + dag-præcise jubilæer via tolerant klient-load af konklusionsdatoer (fact→conclusion→
assertion.date_min; `visning_foedt/doed` er rå datotekst og kan ikke bære dag-præcision); (5) web-feed-MVP
under forsidens hero (aux-adapter, embede-kort bevidst udeladt, bio-strategi med målt payload + chunket
fallback); (6) oprydning + afløsnings-note i v3-spec'en. Ingen backend-ændringer — kun nye læsninger af
eksisterende tabeller under eksisterende RLS.

## Idékatalog: formidling oven på kildematerialet (2026-07-18)

Brainstorm-runde i forlængelse af feed-konceptet, dokumenteret til senere bearbejdning:
**`docs/design/2026-07-18-formidlingskatalog.md`** — 19 idéer i 7 klynger (evidens-formidling som
attraktion, serier/udstillinger, kort & sted, personalisering, objekter, distribution ud af appen, leg),
hver med databasegrundlag, afhængigheder og indsats, plus et vejledende prioriteringsbillede (mest
særegne: kildeuenigheds-serien, årbogens egen udvikling, efterlysninger; billigst: føljetoner,
våben-forklaringer, delekort). Intet besluttet — hver idé løftes til eget koncept når den vælges.
Krydsrefereret fra feed-konceptet og indekseret i `docs/README.md`.

## Koncept: Det levende feed (2026-07-18)

Idéudviklings-runde (ingen kode) der samler feed-videreudviklingen i ét styringsdokument:
**`docs/design/2026-07-18-levende-feed-koncept.md`**. Baseret på kodebase-analyse af mobil-feed'en
(`buildFeed` — deterministisk, ingen paginering, `FeedOverride` no-op), web-forsiden (statisk PoC uden
highlights-tabel) og narrativ/fakta-laget (intet beskrivelsesfelt på `fact`; daterede gerninger bevidst
kun i prosaen). Hovedgreb: (1) feed-motor 2.0 — kandidat-pool + scoring + seeded sampling + rytme-regler
+ lazy strøm-API (ægte uendelig scroll), delt web↔mobil-pakke; (2) nyt **formidlingslag** oven på uændret
evidensmodel: `haendelse` (narrativ-afledt dateret hændelses-skelet, offline LLM-pass) + `story`
(redaktionelle minihistorier m. kildefod) + `feed_pin`; (3) redaktionelt historieværksted
(hændelses-tidslinje, markér interessant, skriv/godkend) med "Foreslå historie"-knap via auth-gated Edge
Function — LLM-kladder publiceres aldrig uden redaktørgodkendelse, kun afdøde. 4 faser; lukker samtidig
web-konceptets åbne §9.f (forside = faste indgange + feed). Indekseret i `docs/README.md` (ny sektion
"Design & koncepter").

## Sikkerhedshærdning fra Codex-fundament-review (2026-07-17)

Et helrepo-"fundament-review" (Codex, 21 fund F-01..F-21) blev triageret ind i waves med fokus på: dels at
få 1939-stamtavlen indlæst til prod, dels at lukke de fund der bør løses. **1939-loadet er nedstrøms Fase
4-cutoveren**, så alt der skal på prod-skemaet samles i én gated deploy; resten er app/loader/CI uden prod.

**Wave 0 (pre-cutover, ingen prod-berøring) — merged til main:**
- **F-01 (#42):** `_delete_relation_evidence` (SECURITY DEFINER, muterende) var anon-kaldbar via PostgREST →
  anon kunne slette relations-evidens som ejer (omgår RLS). REVOKE + `current_rolle()`-guard. Præcis analyse:
  kun denne var et reelt hul; version-helperne (SECURITY INVOKER) fik REVOKE som defense; `_regen_mentions_for`
  bevidst urørt (trigger kalder den som skriveren → REVOKE ville bryde narrative/note-writes).
- **F-02 (#43 person + #45 media):** authenticated-tier (enhver logget-ind bruger) kunne læse alle ikke-private
  LEVENDE personer + deres fakta/relationer/narrativer/evidens **og fotos** uden samtykke (brød invariant #8).
  `auth_read` filtrerede kun `privat`, ikke `levende`. Fail-close: spejler nu anon via `person_offentlig`;
  media/media_variant/storage via `media_synlig_anon`. Redaktion beholder fuld adgang (additivt `redaktion_read`).
- **F-02c (PR #46, draft):** Codex-genkørsel (med reel fil-adgang) fandt at `<> 'person'`-mønstret er en HEL
  KLASSE af fail-open — media var #1, `family`/ukendt-type #2: en levende families vielse-/skilsmisse-fakta +
  noter var synlige for anon OG authenticated (family_member skjult, men family-fact ikke). Nye SECURITY
  DEFINER-helpers `entitet_offentlig(type,id)` + `family_offentlig(fid)` erstatter alle 8+ `<> 'person'`-
  klausuler i fact/relation/narrative/note/text_mention; fact/relation-mål cascader gennem targetets RLS;
  fail-closed på ukendt type. db-verify Task 8b+8c tester begge retninger (læk skjult + ingen over-hiding).
- **F-16 (#44):** CI gatede ikke `@daa/core`-typecheck eller R-testene → en tsc-fejl (`Koen`-type i
  tree.test.ts) akkumulerede ufanget. Fix + eksplicit vitest-import i buildGeo.test.ts + nye CI-jobs
  (core-typecheck + R/testthat via duckdb, DB-service-frit). Alle 4 CI-jobs grønne.

**Fase 4 cutover forberedt (ikke udført — gated på prod-godkendelse):** `docs/fase4-runbook.md` fik **Trin 1b**
(gen-anvend `db-rls.sql`) — kritisk fordi `db-migrations.sql` ikke gen-anvender RLS-laget, så F-01/F-02/F-02c
ellers aldrig ville nå prod. Plus GATE-0 blast-radius-query (f) for F-02c's over-hiding af død-familie-fakta.

**Metode:** TDD mod lokal `daa_test2` (RED→GREEN + regression begge retninger); dual-review (Codex adversarial
+ selv-audit); advisor-konsultation før den polymorfe RLS-omskrivning. Prod aldrig rørt — klassifikatoren
kræver at brugeren eksplicit navngiver prod-målet.

## `packages/core` — delt web↔mobil-logik (review 27 Bølge 3 #13, 2026-07-14)

**Den rene, DOM/RN/netværks-frie domænekerne er samlet i ÉN npm-workspace-pakke `@daa/core`**, som
både web (Vite) og mobil (Metro/Expo SDK 56) importerer source-only (rå `.ts`, ingen build). Lukker
rodårsag #2 fra review 27: ~15 spejlede moduler uden delingsmekanisme, hvor drift allerede var begyndt.
Repoet er nu et npm-workspace (root `package.json`, konsolideret lockfile).

Flyttet til core (kanonisk én kopi): `collapseSameAs`, `relationship`, `generations`, `buildModel`,
`sammeSomPreflight`, `buildGeo`, `geoSelectors`, `fields`, `pickPreferredBio`, `collation`, `mentions`,
`getAll` (paginering — fik sin første test), samt tree-kernen (`columnLabel`, `columnGen`, `buildDirection`,
`unknownParentRing`, `unknownChildSection`, `buildBidirectionalColumns`). Den snævre delte type-grænse
(`Model`-superset m.m.) bor i `packages/core/src/types.ts`; begge apps re-eksporterer den + beholder app-
specifikke typer lokalt. **Bliver bevidst i apps** (ægte platform-forskelle): fetch-orkestrering
(`model.ts`/`load.ts`), redaktør-skrivelaget, bogmærker, og graf-traverseringerne `childrenOf`/`parentsOf`
(web `childIdx` vs mobil `childrenByUnion`). `buildBidirectionalColumns` parameteriseret over de to
traverseringer, så den kunne deles trods app-specifik graf-adgang.

Alle `parity.test.ts`-vagter pensioneret (funktionerne er nu single-source). Tests dedupликeret: ~669 →
538 (211 core + 146 web + 181 mobil), ingen dækning tabt — de delte tests kører nu én gang. Begge apps
`tsc` rene; Vercel-deploy verificeret (installCommand kører fra repo-rod så workspace-symlinket resolves).

Eksekveret spike-first (ét modul + 5 tooling-checkpoints før fuld flytning), dual-reviewet spec (Codex:
5 fund indarbejdet — bl.a. at `linjeByPerson`-konflikten sidesteppes ved at holde `Aux` app-specifik frem
for at forsone den), og subagent-drevet per-task-review. Spec: `docs/superpowers/specs/2026-07-13-*`,
plan: `docs/superpowers/plans/2026-07-13-*`.

## Slankning af `claude.md` (2026-07-12)

CLAUDE.md-audit (`/claude-md-improver`): filen gik fra ~382 til ~53 linjer. Fjernet historisk
handoff-framing, forældet onboarding (§6/§8), og en artefakt-tabel der pegede på 4 filer der ikke
findes (`diagram-1/2-*.mermaid`, `supabase_load.py`, `import_test.py`). Tilføjet en `## Kommandoer`-tabel
(web/mobile/R/DB — det største hul). De 9 invarianter bevaret ordret i substans (kondenseret til én linje
hver), §7-dubletter foldet ind i dem. Ny struktur: kun stabilt/ufravigeligt bor resident; status, historik
og backlog peger ud i `docs/`. Tidligere kontekst arkiveret ordret i `docs/claude-md-context-archive.md`
(commit `dc9908f`). Pushet til `origin/main` (`dc9908f` + `bfc7f6c` review-docs 24-27).

## Review 27 — dual-review af review-26-rettelserne (web+mobil, branch `feat/generations-browser-v2`, 2026-07-11)

Claude+Codex dual-review af selve review-26-rettelserne (`docs/reviews/27-review26-fixes-dual-review.md`).
Code-analyzer: 0 bugs. **Codex hævede den rigtige robustheds-/scoping-flanke** (alle claims verificeret
empirisk — ingen laundering):

- **MEDIUM (rettet):** `red_tilbagetraek_fakta` åbnede et change_set FØR den tjekkede om noget blev ramt →
  forkert/dobbelt-klik gav tomt change_set + falsk succes. Nu fail-closed `IF NOT EXISTS(... afklaret) THEN
  RAISE` før `begin_change_set` (schema.sql + db-migrations.sql). Rollback-test udvidet: dobbelt-retract
  rejser nu ærlig fejl. **Kræver prod-re-apply** (idempotent CREATE OR REPLACE).
- **Determinisme (rettet):** `fetchForaeldreUkendtMarkering` manglede `order` (PU-loaderen har `.order('id')`)
  → `.order('target_id')` tilføjet (begge platforme).
- **NaN-guard (rettet):** `buildRpcCall`-guarden afviste kun `null`; `Number('')===0` slap igennem. Nu
  afvises tom/blank + ikke-endelige eksplicit (begge platforme; tests +2).
- **Stale kommentar (rettet):** `Redaktion.tsx` sagde stadig `red_slet_oplysning (fjern)`.
- **HIGH surfacet (pre-eksisterende, IKKE regression):** samme_som-collapse gør Fjern ufuldstændig —
  editoren opererer på rå `personId`, projektionen er kanonisk; to foldede medlemmer begge markeret →
  Fjern rammer kun én. Eskalering af review-26 MEDIUM 3. Afventer bruger-beslutning (kaskadér / vis konflikt
  / PoC-grænse). Sjældent (kræver to samme_som-linkede personer begge hånd-markeret).
- **Kvalitet:** web 243/243 + mobil 332/332 + tsc rent + lokal rollback-test grøn (inkl. guard-assertion).

## Review 26 (Codex) — rettelser af generationsbrowseren (web+mobil, branch `feat/generations-browser-v2`, 2026-07-11)

Codex-review af `feat/generations-browser-v2` (brief: `docs/reviews/26-foraeldre-ukendt-generationsbrowser-review-brief.md`).
Fund verificeret mod koden (advisor-gate + `superpowers:receiving-code-review`): HIGH 2 = ægte bug,
HIGH 1 = reel over-implikation (delvist), MEDIUM 2 = dokumenteret PoC-grænse, MEDIUM 1 + 3 = backlog.

- **HIGH 2 (bug — rettet):** "Fjern markering" kaldte `red_slet_oplysning`, som re-peger konklusionen
  til den ÆLDSTE tilbageværende påstand. Efter Markér → Opdatér (to påstande) → Fjern genoplivede den
  derfor den oprindelige markering i stedet for at fjerne den. **Fix:** ny generisk RPC
  `red_tilbagetraek_fakta(p_fact_id)` sætter fakta-slottets konklusion `'afklaret' → 'tilbagetrukket'`
  (læse-gates kræver `afklaret`, så markeringen holder op med at projicere; re-Markér reaktiverer via
  `red_upsert_fakta`s `ON CONFLICT`). Append-sikkert (påstande uforanderlige, invariant 1), fortrydbart
  (`conclusion` er `version_pk_registry`-sporet). App: ny `tilbagetraekFakta`-art (web+mobil buildRpcCall),
  `fetchForaeldreUkendtMarkering` returnerer nu `factId`, Fjern-knappen ruter om. Per-oplysnings-🗑
  uændret (`sletOplysning` er korrekt der). **Verificeret:** lokal rollback-test mod prod-kopien
  (`daa_test2`) beviste både bug-reproduktion OG fix i én rullet-tilbage transaktion (retract → 0
  afklarede + 2 bevarede påstande + virkende re-Markér). `schema.sql` + idempotent `db-migrations.sql`.
- **HIGH 1 (over-implikation — ordlyd skærpet):** nedad-projektionen ligger inde i en mands børne-kolonne
  og kunne læses som "hans mulige børn". Kandidat-visningen beholdt (bruger-ønske om inline-bladring),
  men ordlyden skærpet: header "Uforbundne i dette slægtled" → "Uforbundne — placeret efter slægtled,
  ikke forældreskab"; grad-1-note "Muligt barn — …" → "Muligt barn **i linjen** — forælderen er ikke
  navngivet". Rene string-ændringer, delt kerne holdt byte-identisk.
- **Bevidst udskudt:** MEDIUM 2 (kilde gemt som fritekst i `citat_tekst` frem for struktureret
  `source_id`/side + ordret formulering) — dokumenteret PoC-grænse (`schema.sql` linje 536); det rigtige
  fix er skema+UI-arbejde, holdt ude af dette changeset for at bevare stramhed. MEDIUM 1 (`usikker` tabes
  i `backfill_slaegtled.R` — anden akse: usikkert *medlemskab* vs. ingen *forbindelse*, ingen forbruger
  endnu, YAGNI) + MEDIUM 3 (flere markeringer efter samme_som-collapse: "første vinder", deterministisk,
  sjælden) = backlog.
- **Kvalitet:** web 242/242 + mobil 331/331 + tsc rent begge steder. `red_tilbagetraek_fakta`
  **anvendt mod prod 2026-07-11** (ren additiv `CREATE OR REPLACE`, bekræftet FALSE→TRUE, signatur
  `p_fact_id bigint`) — Fjern-knappen virker nu i live-appen. **UDESTÅR:** empirisk E2E på device
  (markér→opdatér→fjern via redaktør-login) + dual-review + merge.

## "Forældre ukendt"-markering + inline marker-gatet kandidat-kolonne (web+mobil, branch `feat/generations-browser-v2`, IKKE merget, 2026-07-09)

Løser problemet fra `docs/reviews/25-generationer-ukendt-forbindelse-analyse.md`: stamtræets ene
signal "ingen `family_member`-kant" dækkede over FIRE virkeligheder (bevist / formodet / kilden
angiver ingen forbindelse / kant ikke udtrukket endnu). v1/v2's fallback tolkede ALT fravær som
"ukendt" → forkerte kandidater (person 210 under 208). Den manglende epistemiske primitiv: at KILDEN
ikke angiver en forbindelse opad er selv en kildepåstand.

**Beslutninger (bruger-interview 2026-07-09):** (a) skeln TO grader ('forælder ukendt' vs 'ingen
forbindelse angivet'); (b) INLINE distinkt kolonne i træet — IKKE et separat side-panel-register
(det var netop det spor der gled væk fra ønsket om inline-bladring); (c) markér én reel klynge til
verifikation.

- **Phase A:** fjernet den ugatede fallback + activeCoord-maskineriet (T6-review-effekten). Kun
  beviste kanter + slægtled-labels læst fra faktisk koordinat (`columnGen`, løser review 20 H1
  "-7. slægtled"). Slettet `fallbackRing`/`buildAnchorPeers`/`adjacentGen` founder-hop (inert i prod).
  **Rydder også v1's aner-fallback der stadig er live på main/prod** ved merge.
- **Phase B:** INGEN skema-ændring (invariant 2). Markeringen = `fact(faktatype='forældre_ukendt')`
  + assertion (grad) + citation (proveniens) + afklaret konklusion, skrevet via `red_upsert_fakta`.
  Ren `buildParentsUnknown`-resolver (byte-identisk web↔mobil) + `fetchParentsUnknownRows`
  (overlapper hoved-batchen) → `parentsUnknownByPerson` på model/store. Vokabular seedet i
  `db-migrations.sql`.
- **Phase C:** `unknownParentRing` — inline marker-gatet kandidat-kolonne (forrige slægtled,
  kuld-grupperet). Fyrer KUN på en tilstedeværende afklaret markering, aldrig på fravær af en kant.
  Cross-linje-bladring (founder → moderlinjen) emergerer af samme_som-collapse uden founder-hop.
  Grad afgør ordlyden. Distinkt render (stiplet/amber, "muligt slægtled"-tag, Kilde-footer); klik
  re-ankrer (ren navigation). Web `Folgesvend` + mobil `tree.tsx`.
- **Nedad-projektion (efterkommer-retning):** `unknownChildSection` — samme markeringer vist NEDAD:
  når man bladrer fra en (mandlig) stamfader, augmenteres børne-kolonnen med en "Uforbundne i dette
  slægtled"-sektion (markerede-uforbundne i næste slægtled, samme linje). Ren projektion af de
  eksisterende markeringer (ingen ny authoring — evidens-hygiejne: kun projektionen har altid et ægte
  kilde-citat). Marker-gate + bevist-forælder-eksklusion + patrilineær køns-gate (bruger-beslutning).
  Proveniens pr. person; grad-splittet ordlyd ('ingen forbindelse angivet' aldrig som barn-claim).
  Fable-agent-eksploreret (4 optioner) → Option 1. Data-fit bekræftet mod prod.
- **Authoring (redaktion):** markér/opdatér/fjern med grad + kilde via `submitChange`/`setPending`
  (dry-run/LIVE, fortrydbar change_set). `markerForaeldreUkendt`-art + `sletOplysning` til fjern.
  Web `ForaeldreUkendtControl` + mobil person-editor-kontrol. `fetchForaeldreUkendtMarkering`-læser.
- **Kvalitet:** TDD, byte-identisk delt kerne (paritets-test på `buildGenCoords`/`buildParentsUnknown`/
  `columnLabel`/`columnGen`/`buildDirection`/`buildBidirectionalColumns`/`unknownParentRing`),
  4-agent `/simplify`-pass (5 fund anvendt). **web 231/231 + mobil 328/328 + tsc + build grønne.**
- **UDESTÅR:** empirisk verifikation mod prod (markér én reel klynge via §6-query + redaktør-UI, se
  ringen rendere) — kræver prod-adgang/redaktør-login. Dual-review + merge.

## Datafix: person 1 fejlagtigt "gift med" eget barnebarn person 104 (2026-07-06)

Bruger opdagede at person 1 (Gottschalk von Reventlow, 1. slægtled, linje I) stod registreret som
"gift med" person 104 (Hartwich, 3. slægtled — Gottschalks barnebarn via person 82) i familie 74.
Undersøgt og bekræftet: en loader-fejl fra den oprindelige DAA-indlæsning (familie 74 havde ingen
`change_event`-historik, dvs. aldrig rørt af redaktør siden) — samme fejlklasse som de tidligere
"spøgelses-union"-fund, men IKKE en af de allerede oprydede (change_sets 3-7). Bogteksten for
Hartwich siger "Gift med NN" (ukendt hustru); intet sted nævnes Gottschalk. Iwan (person 44,
familie 74's barn) kaldes gentagne gange "søn af ridderen Hartwich von Reventlow" — aldrig
Gottschalk.

**Rettet mod prod** via en manuelt forfattet, fortrydbar `change_set` (id 30): fjernede person 1
som partner i familie 74 (`DELETE family_member WHERE family_id=74 AND person_id=1 AND
rolle='partner'`), efterlader Hartwich (104) som eneste partner + Iwan (44) som barn — matcher
det etablerede enkelt-partner-mønster for ukendt ægtefælle (7 lignende tilfælde findes allerede
i basen, inkl. Hartwichs egen union med sin far). Verificeret: ingen flere spøgelse-par tilbage
(bred søgning på partner-par ≥2 slægtled fra hinanden i samme linje — ikke udtømmende, fanger
ikke tværlinje-tilfælde).

**Opfølgning noteret i `claude.md` §9:** redaktøren har stadig ingen flade til at rette den slags
fejl selv — denne rettelse krævede direkte SQL. Se også separat bug-rapport: mobilapp crasher ved
åbning af person i redaktør-delen (urapporteret root cause).

## Konto-bogmærker: dual-review 22 af IMPLEMENTERINGEN + 4 fund rettet (2026-07-06)

Efter skive 1-6 (nedenfor) kørt en ANDEN dual-review-cyklus (Claude+Codex) — denne gang af den
faktiske KODE, ikke spec'en (spec allerede dual-reviewet, review 21). Fandt og rettede:

- **H1:** mobil `count` var `idsList.length` (ikke session-gated) → viste stale badge-tal efter
  log-ud selvom `ids`/`has()` korrekt gik tomme. Fix: `count: ids.size`.
- **N1 (HIGH):** web's `useBookmarks(session ? {userId} : null, ...)` byggede et NYT objekt-
  literal hver render → ustabil effekt-dependency → gentaget refetch på HVER render. Fix: begge
  hooks (web+mobil) tager nu `userId: string | null` (primitiv, stabil) i stedet for et
  session-objekt.
- **M1:** hurtig dobbelt-toggle af samme id kunne race'e (add+remove krydsende, out-of-order
  netværkssvar). Fix: `toggle` ignorerer gentaget tryk mens id'et allerede er in-flight.
- **N3:** web-login manglede busy-guard (dobbelt-klik → overlappende `signIn`-kald) + rejection-
  handler på `currentSession()`. Begge rettet.
- **N2 (recalibreret MEDIUM):** ingen bruger-nøglet rydning af bogmærke-listen ved brugerskift.
  Reconcile-verifikation bekræftede RLS forhindrer reel cross-account data-korruption (skrivninger
  scopes altid til `auth.uid()` server-side — kun en misvisende UI-glimt, og scenariet er slet
  ikke nået via appens faktiske UI-flow, som ikke understøtter konto-skift uden log-ud). Mitigeret
  med ryd-ved-reelt-brugerskift.
- **Selv-fanget regression under fixet:** den FØRSTE N2-mitigering (ubetinget `setIdsList([])` i
  effekt-kroppen) genintroducerede en uendelig render-loop identisk med den allerede-hærdede
  udlogget-gren (fanget af `vitest` der hang/OOM'ede) — rettet med en ref-sporet "kun ved reelt
  brugerskift"-betingelse.
- **Bevidst udskudt (H2):** mobil har to uafhængige `useBookmarks`-instanser (Home-skærm +
  Bogmærker-skærm) uden delt state — fjern et bogmærke på Bogmærker-skærmen opdaterer ikke Home's
  badge/ikoner før genmontering. Codex' reconcile bekræftede et ægte fix kræver en ny Zustand-
  bogmærke-slice, ikke en hurtig patch — udskudt til separat brainstorm/plan (jf. projektets
  konvention for ikke-trivielle arkitektur-ændringer). Se `docs/reviews/22-*.md`.
- **Verificeret:** web 23/23 filer, 208/208 tests (2 nye); mobil 23/23 filer, 337/337 tests,
  tsc+eslint rene.

## Konto-bogmærker — login-eksklusive, cross-device-synkroniserede bogmærker (web+mobile, branch feat/bogmaerker-konto, 2026-07-06)

Bogmærker opgraderet fra lokal PoC (AsyncStorage/localStorage) til et **login-eksklusivt gode**
lagret i Supabase — følger brugeren på tværs af web og mobil. Ingen hybrid/merge-logik, ingen
offline-cache (bevidst PoC-afgrænsning, jf. spec 2026-07-06).

- **DB-lag:** ny `bookmark`-tabel (`user_id=auth.uid()` default, `person_id` FK ON DELETE CASCADE,
  unik `(user_id,person_id)`) + RLS (own-row select/insert/delete) + **eksplicit** `GRANT/REVOKE`
  (dual-review 21 N1 — Supabase auto-grant'er default-privilegier til anon/authenticated, RLS alene
  er ikke nok). Idempotent DDL (`schema.sql`+`db-migrations.sql`+`db-rls.sql`). Ny `db-verify.sql`
  Task 14: RLS-isolation, dublet-sikring, cascade, anon-blokering.
- **Empirisk fund under lokal test (ikke antaget):** anon har INGEN grant overhovedet på
  `bookmark` — et bart `SELECT` som anon rejser `permission denied`, ikke et tomt resultat (stærkere
  end RLS-alene-filtrering). Testens assertion rettet til at forvente `insufficient_privilege`.
- **Repository-lag (web+mobil):** `RemoteRepository` (Supabase-backet, erstatter lokal lagring) +
  auth-gated `useBookmarks(session, canon)`: udlogget → tom, `canSave:false`, `toggle` no-op;
  logget-ind → hent-ved-mount, optimistisk toggle m. **race-guard** (dual-review H2: en fokus-
  refetch klobrer ikke en igangværende skrivning). `person_id` sendes altid som **streng** til
  PostgREST (N2 — bigint > 2^53 korrumperes af `Number()`).
- **Web:** minimal login-session + modal tilføjet i den offentlige Folgesvend-læser (genbruger
  eksisterende `data/auth.ts`); alle bogmærke-gem-steder gates via `saveOrPrompt` (udlogget tap →
  login-modal, ikke stille no-op). Mobil havde allerede login (Konto-fanen) — kun wiring nødvendig.
- **Empirisk fund under web-test-kørsel (fanget FØR mobil-porten, undgået der fra start):** den
  udloggede gren kaldte `setIdsList([])` med en FRISK array-reference hver effekt-kørsel →
  kombineret med en ustabil `canon`-reference gav det en uendelig render-loop (OOM i test-
  runneren). Rettet med bail-safe funktionel updater; samme fix indbygget i mobil-porten fra start.
- **Mobil eslint-fund (React Compiler-lint, kun mobil har denne strenge config):** `pendingRef`
  skiftet fra `useMemo` til `useRef` (mutation af en useMemo-værdi er ikke tilladt); fjernede
  synkron `setState` i effekt-krop for udlogget-grenen (afledt i stedet for lagret+ryddet).
- **Test-scope-justering (empirisk afprøvet, ikke antaget):** `@testing-library/react-native@14`
  (react-native 0.85/react 19) virker ikke i dette repos jest-opsætning — selv en triviel
  `useState`-hook giver `renderHook() → { result: undefined }`. Afhængigheden droppet igen;
  mobil-testen dækker det renderer-uafhængige repository-lag (5 tests); hook-adfærd verificeret
  empirisk i iOS-simulatoren i stedet (web derimod har fuld `renderHook`-dækning, 10 tests).
- **Verificeret:** web tsc+vitest (23/23 filer, 206/206 tests) grøn; mobil tsc+eslint+jest (23/23
  filer, 337/337 tests) grøn; DB Task 14 grøn lokalt (frisk `daa_test`-genopbygning fra
  `schema.sql`+`db-migrations.sql`+`db-rls.sql`, ingen prod-berøring). iOS-simulator (idb): app
  booter uden crash, ingen badge udlogget, gem-ikon-tap→`/konto` (login-gate bekræftet), Bogmærker-
  skærm viser korrekt login-CTA.
- **Udestår:** DB-migrationen er **ikke anvendt mod prod** (kræver eksplicit bruger-godkendelse,
  git-gate). Fuld login+cross-device-persistens-verifikation kræver netværk (sim-fetch fejler,
  kendt begrænsning) — næste skridt er fysisk enhed (mobil) + browser (web) mod rigtig prod-konto.
  Se `docs/superpowers/{specs,plans}/2026-07-06-konto-bogmaerker*` + `docs/reviews/21-*`.

## Følgesvend v3 — forsidefeed, menu-drawer & bogmærker (mobile, branch feat/folgesvend-v3, 2026-07-05)

Mobil-appen bragt op til v3-designet (`Reventlow-folgesvend-v3.dc.html`). Tre nye elementer +
afgrænset visuel afstemning (sidstnævnte udestår). **Ingen backend-/model-ændringer** — feedet er
ren læsning ovenpå den eksisterende `Model`/`Aux`.

- **Forsidefeed (`data/buildFeed.ts`):** ren, deterministisk selector der udleder et redaktionelt
  `FeedCard[]` (9 korttyper: portrait/citat/gods/forbundet/slaegt/embede/jubilaeum/vaaben/samle).
  Portrait+citat i **disjunkt** hash-partition (ingen dobbelt-optræden); `today` injiceres
  (jubilæum = runde ≥100 år); per-kind `FEED_CAPS` før round-robin-`interleave`; `overrides`-krog
  til senere redaktionel kilde (hybrid-beslutning). 17 unit-tests.
- **Forside (`app/(tabs)/index.tsx`):** omskrevet til `FlatList`-feed + kollapsende hero +
  `HomeTopBar` (hamburger, brand-på-scroll, bogmærke-badge). `slaegt`-kort sætter `relA/relB` før
  `push('/relate')`. Den gamle nummererede 01–08-liste **flyttet ud** af forsiden.
- **Menu-drawer (`components/MenuDrawer.tsx`):** venstre slide-in (reanimated) m. slægt-header,
  nav-liste 01–08 (+ Bogmærker) og konto-footer.
- **Bogmærker (`lib/bookmarks.ts` + `app/bogmaerker.tsx`):** async AsyncStorage-lager + synkron
  render-state-hook (spejler web's person-kun kontrakt). Gem-ikon iff kort har `personId`.
- **Dual-review (Claude+Codex, `docs/reviews/20`):** 11 fund, alle empirisk verificeret mod koden
  og rettet i spec FØR implementering (bl.a. BM1 async-race, BM2 recollapse-miss, NEW1 forbundet-
  data findes ikke, NEW2 relate-slots). advisor-gate fangede `samle`-dødkode (nu wiret).
- **Verificeret:** tsc + eslint rene, **327 jest grønne** (305 eksisterende + 22 nye). **iOS-
  simulator mod SEED-data (idb):** feed renderer, hamburger→drawer, bogmærke-toggle→badge "1",
  **persistens over app-genstart**, Bogmærker-skærm — alle bekræftet empirisk. Krævede frisk
  native dev-client-build (`expo run:ios`) da den installerede binary var stale (manglede
  `react-native-webview` → `RNCWebViewModule`-crash ved boot; pre-eksisterende, ej vores kode).
- **Skive 5 (visuel afstemning):** iOS-sim-audit af eksisterende sub-skærme (Om slægten, Stamtræ,
  Slægtens våben, Persondetalje) mod v3-designet fandt dem **allerede pixel-tæt konforme** — de blev
  bygget til v3 i tidligere sessioner (delt `TopBar` + tokens). **Ingen substantielle ændringer nødvendige.**
  Godser/søg/slægtskab deler samme komponenter+afstamning (forventet konforme; endelig visuel pass
  bør ske på fysisk enhed mod live-data).
- **Udestår:** verifikation mod live-Supabase-data (sim-fetch fejler → SEED-fallback; kræver fysisk
  enhed, jf. memory `mobil-sim-rn-fetch-1005`) + merge/push. Se `docs/superpowers/{specs,plans}/2026-07-05-folgesvend-v3-*`.

## Generations-reparation af stamtræet — hul-reparation via slægtled (web+mobile, PROD-LIVE + merget, 2026-07-05)

Ny navigations-vej for de tidligste, ubeviste generationer: når aner-ringen i Kolonner-
stamtræet er tom (ingen bevist forælder), vises nu generations-naboerne fra samme linjes
forrige slægtled som **ubeviste kandidater** (stiplet/amber, "muligt slægtled"-tag,
slægtled-header, kuld-gruppering). Klik re-ankrer — skriver **aldrig** en kant.

- **Datalag (PROD-LIVE):** `segment.py` fanger nu bogens dobbelt-nummererede slægtled
  ("Første (tolvte)") → `slaegtled_lokal`/`slaegtled_gennem` + `kuld` på `person_external_id`
  (3 additive kolonner + trigger-hærdning så generation/kuld-UPDATE ikke regenererer
  `visning_*`). Deterministisk backfill (ingen LLM): `change_set 20` (fortrydbar),
  **591/591 lokal-dækning**, join på `(source_id, linje, nr)`, fail-closed source-valg,
  suffix-variant-assert, data-aware idempotens (overlever `--force-reset`), wiret reload-
  durabelt i `post_load_fixup.R` (subproces-isoleret). Conrad V-1=(1,12)/III-58=(12) valideret
  som founder-bro. Migration advisor-ren.
- **App-lag:** ren `buildGenCoords`/`previousAncestorGen` (founder-krydshop via `parent_lineage_id`,
  fail-closed) → parametriseret `genCoords` i den delte `buildDirection`-bygger (web `tree.ts` +
  mobil `selectors.ts`, byte-identisk). Source/lineage-scoped kandidat-match.
- **Proces:** 11 TDD-tasks m. per-task-review, 5× `/simplify`, samlet dual-review (Claude opus +
  Codex) → ingen Critical, write-invariant bekræftet af begge, 7 fund rettet (F1-F7) + re-review.
  web 189/189, mobil 304/304. Merget til main efter ren integration med geo-kort-UI-featuren.
- **v2 (dok. spec §12b):** founder-hop over flere linje-niveauer + active-line-kontekst for ring-valg
  (begge ureachable i nuværende single-source-data). **Udestår:** empirisk UI-verifikation
  (web-browser + mobil-enhed) mod live-data. Se `docs/superpowers/{specs,plans}/2026-07-05-generations-reparation*`.


## Mediehåndtering — Slice 0h: runtime-fix + slet/afkobl + objekt-foto (2026-07-05)

Tre ting i forlængelse af Slice 0g, udløst af brugerens egen prod-test af upload-featuren:

- **Reel bug fanget ved runtime-verifikation (rettet på begge platforme):** `submitChange`
  kaldte aldrig `red_bekraeft_media_upload` efter `red_upload_media` — uploads sad derfor
  fast som `upload_status='kladde'` for evigt (aldrig synlige efter gating). Brugeren
  uploadede 3 rigtige testbilleder (Conrad/Anna Sophie Reventlow-portrætter) mod prod, som
  afslørede fejlen; rettet, og de tre rækker flyttet til `'klar'` via det nu-virkende RPC-kald
  (ikke en rå UPDATE — change-log intakt). Præcis den slags fejl unit-tests ikke fanger, fordi
  `buildRpcCall` testes rent/netværksfrit og selve netværkskæden aldrig eksekveres af nogen test.
- **Slet/afkobl billede (bruger-anmodet):** to distinkte, bevidst forskellige handlinger.
  *Afkobl* ("Fjern") genbruger det eksisterende generiske `red_slet_relation`-RPC uændret —
  den sletter kun selve `afbildet`-relationen (+ evidens), rører hverken `media`-rækken eller
  Storage-bytes, så mediet kan stadig være tilknyttet andre. *Slet billede* er et nyt, lille
  RPC (`red_fjern_media`) der sætter `upload_status='fjernet'` — elegant fordi
  `media_rettigheder_ok` allerede kræver `upload_status='klar'`, så et fjernet billede
  automatisk forsvinder fra al anon/auth-synlighed uden ny RLS-politik, og `media` har
  allerede versionerings-triggeren (`trg_log_media`), så handlingen er gratis fortrydbar via
  den eksisterende redaktionelle historik. Storage-bytes røres aldrig → Supabases
  `storage.protect_delete()`-beskyttelse kommer aldrig i spil. En ægte hård sletning
  (fjerne bytes fra Storage) er bevidst IKKE eksponeret i redaktør-UI'et — forbliver en
  sjælden, manuel admin-handling.
- **Objekt-foto-upload (gods/våben):** samme upload/galleri-mønster som person-portrætter,
  nu også for `estate`/`coat_of_arms` via `red_upload_media`s eksisterende `p_objekt_type`-gren
  (fandtes allerede server-side, kun UI manglede). Web: ny delt `renderMateriale()` i
  `Redaktion.tsx` bruges af både person-editoren og `renderGenericEditor()` (estate/arms).
  Mobile: ingen generisk entitets-detail-editor findes endnu, så en bevidst minimal,
  selv-mærket "ikke en fuld editor"-skærm (`entitet/materiale.tsx`) blev tilføjet, nået via
  tappbare gods/våben-rækker i `entitet/[type].tsx`; galleri + upload-sheet delt med
  person-editoren via nye `MediaGallery`/`MediaUploadSheet`-komponenter.
- **Arbejde udført i separat worktree** (`.claude/worktrees/media-slet-objektfoto`,
  branch `feat/media-slet-objektfoto`) efter brugerens ønske.
- **`/simplify` (4 agenter parallelt) anvendt — 4 reelle fund, alle rettet:**
  (1) *simplification* — web's `run()` opdaterede kun objekt-editorens medie-refetch-
  betingelse til at inkludere de nye `fjernMedia`/`sletRelation`-arter, men glemte
  person-editorens parallelle `skipMedia`-betingelse (stadig kun `!== 'uploadMedia'`) — reelt
  fund, ikke bare stil: ville have efterladt et lige-fjernet billede synligt i galleriet.
  Rettet ved at udlede begge fra samme `mediaChanged`-boolean.
  (2) *reuse* — mobile duplikerede hele galleri-markup'en (thumb + status + Fjern/Slet-knapper)
  og tre style-objekter mellem person-editoren og den nye objekt-skærm, i stedet for at dele
  den som web gjorde via `renderMateriale`; udtrukket til en ny delt `MediaGallery`-komponent
  (og en `CenterMsg`-komponent, der samtidig lukkede en allerede-eksisterende 3-vejs
  duplikering af "Henter…/fejl"-beskeden på tværs af person-editor og entitetsliste).
  (3) *efficiency* — ingen fund (agenten bekræftede den nye `mediaFromRelPairs`-hale er en
  reel dedup, ikke ekstra I/O; de to nye `useEffect`'er er korrekt gensidigt udelukkende).
  (4) *altitude* — reelt datahazard: `red_bekraeft_media_upload`s ubetingede
  `UPDATE ... WHERE id=p_media_id` kunne i teorien genoplive en blødt-slettet
  (`'fjernet'`) række til `'klar'` igen ved et forsinket/gentaget bekræft-kald (ikke nået via
  nuværende app-flow, men RPC'et bør ikke være afhængigt af det). Hærdet med
  `AND upload_status <> 'fjernet'` i WHERE-klausulen, anvendt til prod via MCP samme dag.
  Mindre fund også rettet: hoistede en pr.-række-genberegnet konstant i mobile, og udtrak
  web's 3× gentagne `entity==='estate'||'arms'`-tjek til en delt `HAR_OBJEKT_MATERIALE`-Set
  (spejler mobiles `HAR_MATERIALE`). **Bevidst sprunget over:** en SQL-verify-test for
  `red_fjern_media`/guarden i `db-verify-media.sql` — filens etablerede mønster er specifikt
  scopet til RLS-tests uden redaktør-kontekst (`SET LOCAL ROLE anon/authenticated`); en
  RPC-kaldende test kræver JWT-claim-impersonering, som ikke passer den etablerede fil-kontrakt.
  tsc + 272/272 jest (mobile) + tsc + 155/155 vitest + build (web) alle grønne efter fixene.
- **Udestår:** samme kendte gap som Slice 0g — ingen automatiseret runtime-verifikation af
  selve slet/afkobl/objekt-foto-UI'en (ingen browser-driver/iOS-simulator-tap-værktøj i
  repo'et); "løse billeder"-admin-oversigt og rettigheds-workflow-UI (`red_set_media_rettigheder`)
  forbliver separate, ikke-startede opgaver.

## Mediehåndtering — Slice 0g: redaktør-upload porteret til web (2026-07-05)

Samme redaktør-portræt-upload som mobile (se ovenfor), nu også i web-arbejdsbordet
(`web/src/Redaktion.tsx`) — bruger-anmodet efter at have opdaget web kun havde en generisk
læse/forslag-"Medier"-fane, intet reelt upload. Browser-nativt: et `<input type="file">`s
`File`-objekt uploades direkte til `supabase.storage` (intet `expo-file-system`-ækvivalent
nødvendigt). Ny "Materiale"-sektion i person-editoren, ny `web/src/data/mediaUpload.ts`
(`buildStoragePath`/`performUpload`), ny `Change`-art `uploadMedia` i `redaktionWrite.ts`,
ny `fetchRedPersonMedia` i `redaktionRead.ts` (adskilt fra `data/media.ts`s offentlige,
RLS-begrænsede `fetchPersonMedia` — redaktøren skal se `kladde`/spærrede egne uploads).
- **Rolle-gating, web-specifikt:** web's skrive-lag har (modsat mobile) en rolle-baseret
  fallback til `red_suggest` for ikke-redaktion. Upload kan IKKE degradere til et forslag
  (intet ejerskab af fil-bytes) — gated to steder: UI'en skjuler knappen for ikke-redaktion,
  OG `submitChange` afviser eksplicit hvis kaldet alligevel ville route til `red_suggest`.
- **`/simplify` (4 vinkler) anvendt:** (1) reuse — mindre, accepteret duplikering af en
  5-linjers relations-query-form ift. `data/media.ts`s `fetchMediaByRelation` (sprunget over:
  ægte genbrug kræver at omstrukturere en delt, allerede-testet offentlig modul for
  marginal gevinst — samme afvejning som mobile allerede har); (2) simplification — foldede
  signering ind i `fetchRedPersonMedia` selv (som `media.ts`s eget `loadMediaItems`-mønster)
  i stedet for en separat `mediaUris`-state + `useEffect` med kun ét kaldested (mobile beholdt
  sin tilsvarende to-trins-opdeling, fordi `useMediaUris` der er en reelt genbrugt hook på
  tværs af flere skærme — web havde ingen sådan begrundelse); (3) efficiency — medie-refetch
  var føjet ind i den allerede eksisterende "genindlæs ALT efter enhver gemt ændring"-liste;
  nu kun ved en faktisk `uploadMedia`-ændring (ny `loadPerson(id, {skipMedia})`-parameter);
  (4) altitude — en `uploadMedia`-ændring der (fejlagtigt eller pga. rolle-skift) falder
  igennem til `red_suggest` ville serialisere et rå `File`-objekt til `'{}'` og rapportere
  falsk succes; `submitChange` afviser nu eksplicit før det kan ske (bekræftet: DB/RLS er
  den reelle autoritetsgrænse, UI-gaten er kun UX — statisk-import-valget for
  `mediaUpload.ts` blev også bekræftet korrekt, ingen native afhængigheder på web modsat mobile).
  tsc + 152/152 vitest + build alle grønne efter fixene.
- **Udestår:** samme som mobile — objekt-foto-upload-UI (estate/våben), og reel browser-
  runtime-verifikation (ingen browser-driver i repo'et, kun tsc/test/build).

## Mediehåndtering — Slice 0g: redaktør-upload (mobile, 2026-07-05)

Sidste stykke af Slice 0's "0f"-punkt: portræt-upload fra redaktør-person-editoren
(`mobile/src/app/redaktion/person/[id].tsx`). Nye dependencies `expo-image-picker`
(`~56.0.19`) + `expo-file-system` (`~56.0.8`), installeret via `npx expo install` —
begge SDK-56-versionerede docs læst FØR kode (mobile/AGENTS.md-mandat); brugte SDK 56's
nye `File`-klasse (`.bytes()`) i stedet for den deprecated `readAsStringAsync`.
- **Ny `mobile/src/lib/mediaUpload.ts`:** `pickImage` (biblioteksvælger m. tilladelses-
  request), `readFileBytes`, `buildStoragePath`, `performUpload` (læs+upload som én enhed).
- **`redaktionWrite.ts`:** ny `Change`-art `uploadMedia` → `red_upload_media`. To-fase-upload
  (bytes til Storage FØR RPC'en) sker KUN i LIVE, aldrig dry-run — ellers ville "Forhåndsvis"
  efterlade en rigtig fil i den private bucket. Dynamisk `import('../lib/mediaUpload')` i
  `submitChange` holder `buildRpcCall` netværks-/native-fri til test.
- **`redaktionRead.ts`:** ny `fetchPersonMedia` (relation→media-join, samme mønster som
  `fetchPersonFamilie`).
- **UI:** ny "Materiale"-sektion + `MediaUploadSheet` i person-editoren (vælg billede →
  slags/titel/må-publiceres → delt dry-run/LIVE-flow via `SkrivePreviewSheet`).
- **`/simplify` (4 vinkler) anvendt:** (1) `fetchPersonMedia`s media-query manglede
  `getAll`-wrapping ift. filens etablerede mønster — rettet; (2) `PersonMedia.relationId`
  blev beregnet men aldrig brugt af UI'en — fjernet (YAGNI, tilføjes når en slet/erstat-
  handling faktisk får brug for den); (3) `refreshMedia()` kørte ubetinget efter ENHVER
  gemt ændring i editoren, ikke kun upload — nu gated på `pending?.art === 'uploadMedia'`;
  (4) selve Storage-uploadet sad i `redaktionWrite.ts` og læste stien tilbage fra det
  allerede-byggede (utypede) RPC-args-objekt — flyttet til `mediaUpload.ts`s nye
  `performUpload`, kaldt direkte med payload-værdierne. Sprunget over: en 3. kopi af
  pille-vælger-mønstret (ville kræve refaktorering af BarnSheet/UnionTypeSheet uden for
  diffen); objekt-foto-grenen i `buildRpcCall` (ingen UI-kalder endnu, men RPC'en
  understøtter det og der er en unit-test — bevidst dækning, ikke spekulativ kode).
  tsc + 269/269 jest + lint alle grønne efter fixene.
- **Udestår:** objekt-foto-upload-UI (estate/coat_of_arms, samme RPC-gren findes allerede);
  runtime-verifikation på device/simulator (ingen fysisk enhed tilgængelig i denne session).

## Mediehåndtering — DB/RLS-lag LIVE i prod (Slice 0, 2026-07-05)

Kørt direkte mod prod (`xjnvdhajfyrcytatnzos`) via Supabase MCP fra en maskine med adgang —
runbook-Trin 1+2 anvendt som to navngivne, sporede migrationer (`mediehaandtering_slice0_schema`,
`mediehaandtering_slice0_rls`), verbatim delta fra `db-migrations.sql`/`db-rls.sql`. `media`-bucket
(privat) var allerede oprettet af brugeren (Trin 3).
- **Verificeret:** Task 8 (afbildet-gating) + Task 12 (rettigheds-gating + storage-mapping) kørt
  direkte mod prod med negative test-ID'er, selv-oprydende — begge OK.
- **Task 12b (storage.objects-politikker) IKKE funktionelt afprøvet mod prod:** kræver
  `SET LOCAL storage.allow_delete_query='true'` for at omgå Supabases `protect_delete`-trigger
  til testens egen oprydning — auto-mode-klassifikatoren blokerede dette korrekt som en
  sikkerheds-bypass på en produktions-tabel, i tråd med brugerens eksplicitte forsigtigheds-krav.
  Verificeret i stedet **read-only** via `pg_policies`: alle 5 forventede politikker
  (`media_obj_anon/auth/redaktion/write/update/delete`) findes med nøjagtig de `qual`/`with_check`-
  udtryk koden tilsigter. Reel end-to-end-funktionstest af disse politikker udestår (kræver enten
  brugerens eget samtykke til delete-bypasset, eller en rigtig fil uploadet via Storage API/UI).
- **`get_advisors(security)` efter DDL:** 8 nye medie-funktioner udløser samme
  "SECURITY DEFINER public-exec"-advarsel som 32 allerede eksisterende `red_*`-RPC'er (etableret
  mønster — adgang håndhæves internt via `current_rolle()`, ikke via GRANT). Ingen nye huller.
- **Ny divergens fundet lokal-stub vs. rigtig Supabase:** vores lokale Postgres-testklynge
  (bootstrap.sql) har ingen `storage.protect_delete()`-trigger, så `db-verify-media.sql`s Task 12b
  passerede lokalt men ville fejle uændret mod rigtig Supabase. Filen er endnu ikke opdateret til
  at håndtere dette (kræver en bevidst bruger-beslutning om delete-bypasset, ikke en stille fix).

## Mediehåndtering — code-review-fixes (Slice 0, 2026-07-04)

High-effort `/code-review` (5 finder-vinkler) på Slice 0-diff'en fandt 10 fund; alle rettet:
- **#1 (sikkerhed) `red_upload_media`:** afviser nu `p_objekt_type='person'` i objekt-grenen —
  ellers kunne en omvendt `media→person afbildet`-relation omgå GDPR-gatingen (schema.sql + db-migrations.sql).
- **#2 (web fejl-isolation):** `fetchPersonMedia`/`fetchObjectMedia` er nu selv-tolerante (try/catch → []),
  så en medie-/storage-fejl ikke længere blanker hele personpanelet/våben-listen.
- **#3 (portræt):** `pickPortrait` normaliserer `slags` (case/trim) i web+mobile; mobile vælger portræt
  blandt *signerbare* medier (ingen permanent placeholder når første medie fejler signering).
- **#4 (test):** ny `db-verify.sql` Task 12b udøver de faktiske `storage.objects`-politikker under
  `SET LOCAL ROLE anon`/`authenticated` (ikke kun helper-kald) — springes over uden `media`-bucket.
- **#5 (efficiency):** `fetchObjectMedia` batchet til array-signatur (`Map<objektId, MediaItem[]>`);
  `fetchArms` gik fra N×3 til én relation+media+sign-triade.
- **#6 (session-læk):** mobile signed-URL-cache ryddes ved `onAuthStateChange`.
- **#7:** `red_opret_media` giver domæne-fejl ved sha256-dublet (ikke rå 23505).
- **#8:** `ArmsView` vælger første *signerbare* billede (ikke blindt `media[0]`) + fast .82-aspekt.
- **#9:** `media_obj_update`-storage-politik fik `WITH CHECK`.
- **#10 (vocab):** `licens`/`kildehenvisning`/`gengivelsestilladelse` (faktatype), `rettighedshaver` (rolle),
  nyt `media_rettigheder_status`-scheme tilføjet `vocab.json`.
- **Ryddet/afvist:** id-alloc-race (accepteret husstil), RPC schema↔migrations-mirror (konvention),
  transient-placeholder (selv-heler), "eksisterende billeder forsvinder" (media-tabel tom i prod + fail-closed tilsigtet).
- **Re-verificeret:** hele SQL-kæden lokalt (Task 8/12/12b grønne, #1+#7-guards rejser); web tsc+147+build;
  mobile tsc+264 (4 nye pickPortrait-tests).

**`/simplify` (4 vinkler) oven på fixes:**
- **Altitude (sikkerhed):** GDPR-retnings-guarden løftet ind i `red_relation`-primitiven (afvis
  `afbildet` med person på objekt-siden) — lukker fail-open for ALLE kaldere, ikke kun `red_upload_media`.
  De to gating-dimensioner komponeret i `media_synlig_anon`/`media_synlig_auth`, delt af media-tabel-
  OG storage.objects-politikkerne (ingen split-brain-drift, ét objekt→media-opslag pr. række).
- **Reuse/efficiency:** web `signPaths` fik mobile's TTL-cache + `onAuthStateChange`-clear (ingen
  re-signering/billed-re-download pr. visning); `MediaThumb` flyttet til `components/primitives.tsx`.
- **Altitude/simplification:** web `fetchPersonMedia`/`fetchObjectMedia` samlet i én retnings-parametriseret
  `fetchMediaByRelation`; mobile signable/portræt/galleri konsolideret i en `usePersonMedia`-model-hook;
  `firstSignable`-helper delt i ArmsView; `red_set_media_rettigheder` 3 IF-blokke → én VALUES-løkke;
  `fetchEstateInfo` kører nu medie-fetchen samtidig med narrativ/sted-kæden.
- **Skippet (bevidst):** stribet-placeholder-ekstraktion (præeksisterende), `red_upload_media`-dobbelt-gate
  (tilsigtet fail-fast + change-set-label), render-memoization (negligibel ved nuv. datastørrelser).

## Mediehåndtering — DB/Storage/RLS-fundament (Slice 0, 2026-07-04)

Første skive af den samlede medie-design-session (`CLAUDE.md` §6.6/§9, udskudt "samlet,
ikke stykvis"). **Kun DB-laget** i denne omgang; frontend (portræt/objekt-visning,
redaktør-upload) og bulk-import følger som senere slices. Fuld plan i
`docs/superpowers/plans/2026-07-04-mediehaandtering.md`.

**Designprincip:** fysisk byte-metadata → kolonner på `media` (eneste legitime "fedning"
af den tynde tabel); semantiske links → `relation` (`afbildet` findes allerede);
rettigheds-*dokumentation* → `fact` på `subjekt_type='media'`; publikations-*gating* →
kontrol-kolonne (som `person.levende`/`privat`).

- **`media`-skema udvidet** (`schema.sql` + idempotente ALTER'er i `db-migrations.sql`):
  storage-metadata (`bucket`, `storage_path`, `mime_type`, `byte_size`, `bredde`, `hoejde`,
  `sha256`, `original_filnavn`, `upload_status`) + unikke indekser på `(bucket,storage_path)`
  og `sha256`. To-fase upload: række (`'kladde'`) → bytes → `'klar'`.
- **Rettigheder fra dag 1:** `maa_publiceres BOOLEAN DEFAULT false` (fail-closed) +
  `rettigheder_status`. To **ortogonale** gating-dimensioner: GDPR-person-gating (fandtes)
  + ny copyright/publikations-gating. Begge skal opfyldes for offentlig visning.
- **RLS** (`db-rls.sql`): nye SECURITY DEFINER-helpers `media_rettigheder_ok` (kun
  `maa_publiceres AND upload_status='klar'`) + `media_id_for_object` (objekt→media-mapping).
  De tre `media`-tabel-politikker udvidet med rettigheds-gating. **Én privat bucket `media`**
  + `storage.objects`-politikker der spejler media-stakken (signed URLs, ikke offentlige URLs
  — begge dimensioner er tilbagekaldelige). Forældreløst objekt → fail-closed.
- **RPC'er** (`schema.sql` + `db-migrations.sql`, husstil: SECURITY DEFINER, `current_rolle`-
  gate, `begin_change_set`, `max(id)+1`): `red_opret_media`, `red_bekraeft_media_upload`,
  `red_upload_media` (media + `afbildet`-relation i ét change_set via re-entrant B7),
  `red_set_media_rettigheder`. Tilknytning af eksisterende media = eksisterende `red_relation`.
- **Verify:** `db-verify.sql` Task 8 opdateret (fixturer sætter rettigheds-felter så afbildet-
  testen isoleres) + ny **Task 12** (rettigheds-gating + storage-mapping). **Empirisk verificeret
  LOKALT:** hele kæden `schema → db-migrations → db-rls → db-verify` kørt mod en frisk Postgres 16
  med Supabase-stub (roller/auth/storage); begge medie-tasks grønne under faktisk RLS (rolle `anon`).
- **Udestår (bruger-gatet):** anvendelse til prod (migration + `db-rls.sql` + bucket-oprettelse);
  vocab-seed for rig rettigheds-dokumentation (Slice 1); redaktør-upload (Slice 0g).

**Frontend read-path (web + mobile, samme session):**
- **Web** (`web/src/data/media.ts` nyt): signed-URL-helper (`createSignedUrls`, batch, 600s) +
  `fetchPersonMedia` (person→media afbildet) + `fetchObjectMedia` (media→objekt). `fetchPersonDetail`
  udvidet med `media`; portræt i `DetailPanel` (fald tilbage til placeholder) + "Materiale"-galleri;
  objekt-billeder i `ArmsView` (hovedvåben + varianter) og `EstatesView`. Delt `MediaThumb`
  (klik → fuld signed URL i ny fane). tsc + 147 web-tests + build grønne.
- **Mobile** (`mobile/src/lib/media.ts` nyt): `signPaths` (TTL-cache) + `useMediaUris`-hook +
  `pickPortrait`. **Rettet latent bug:** `buildAux.mediaBy` nøglede på `m.person_id` (kolonne findes
  ikke → altid tom); nu koblet via relation person→media `afbildet` (2 nye enheds-tests).
  Header-portræt + Materiale-galleri (`expo-image`, allerede installeret) i `person/[id].tsx`.
  tsc + 260 mobile-tests grønne. **Empirisk device-verifikation udskudt** (RN-sim-fetch-bug,
  se memory `mobil-sim-rn-fetch-1005`) — kræver prod-migreret base + fysisk enhed.

## TNG-analyse opfølgning + backlog-prioritering (2026-07-03)

Fuld gennemgang af `jr_tng_reventlow.sql` (alle 37 `CREATE TABLE`-blokke + reelle
rækketal via quote-aware parsing, ikke kun stikprøver som juni-analysen). Nye fund
tilføjet som §7 i `docs/tng-reventlow-analyse.md` (git-ignoreret, levende-data):
foto-regionmarkering/albums/event-scoped medielink (46/5/119 reelt brugte rækker),
`frel`/`mrel` er per-forælder ikke pr. familie (44 reelle adopted/foster-rækker),
gemte rapporter reelt brugt 193 gange, finkornet TNG-rettighedsmodel som RLS-
reference. Status opdateret: barn-rolle-vokabular, `person.privat` og
`citation.citat_tekst/citat_dato` (alle fra juni-analysen) er allerede rettet i
schema.sql.

**Bruger-prioritering (§8):** DNA **afvist** (ikke udskudt). Foto/medie-rigdom
**udskudt samlet** til én fælles design-session (ikke stykvis). Gemte rapporter/
smart-lister = **næste fokus**. Navnepartikel ("von"/"af") udskudt. **Nyt,
ikke-designet krav rejst i samme samtale:** flersproget stamtræ (tysk/svensk/norsk/
engelsk) — kræver egen brainstorm om UI-i18n vs. indholds-i18n og hvor oversættelse
lander i evidenslaget/`narrative`. Se `docs/decisions.md` + `CLAUDE.md` §9.

Ingen kodeændringer denne session — kun dokumentation/prioritering.

## Flere narrativer pr. person — udgave-nøglede narrativer (DB + web + mobile, 2026-07-03)

En person kan nu bære **én biografi pr. DAA-udgave** (`source`) i stedet for præcis én. Spec +
dual-review + plan i `docs/superpowers/{specs,plans}/2026-07-03-*` og `docs/reviews/18-*`.
Implementeret på feature-branch `feat/flere-narrativer-per-person`; **prod-cutover udskudt** til
koordineret merge + web-deploy (RPC-DROP er en cross-client breaking change — se decisions).

**DB.** `red_upsert_narrativ` nøgles nu på `(subjekt_type, subjekt_id, source_id)` (var: første
række by id). Ny additiv `source.aar SMALLINT` bærer udgave-kronologi (source-id ≠ kronologi, og
`source.udgave` er upålidelig fritekst). `red_opret_kilde` udvidet med `p_aar`. Gamle 4-arg-
signaturer droppes eksplicit (undgår PostgREST-overload-tvetydighed). `side = COALESCE(p_side, side)`
så en udeladt side ikke slettes. Tabellen selv var uændret (flere rækker pr. person var altid lovligt).
Verificeret lokalt mod `daa_test`-prod-kopi: to udgaver = to rækker, re-upsert bevarer side,
**fortryd er per narrativ-id** (fortryd af udgave B lader udgave A urørt), 4-arg back-compat.

**Delt selector.** `pickPreferredBio` (ren, spejlet identisk i web+mobile) vælger den foretrukne
offentlige biografi pr. subjekt: `aar DESC NULLS LAST, source_id DESC, narrative_id DESC`, filtreret
til `slags='DAA-udgave'` (ingen vilkårlig TNG-stub-fallback). Bruges af begge læsere.

**Web-redaktør.** Udgave-faner under "Narrativ · biografi" + "+ Ny udgave" (vælg eksisterende kilde
eller opret DAA-udgave). textarea/privat/side binder til aktiv udgave; Gem sender `p_source_id`.

**Mobil-redaktør (minimal, obligatorisk).** Read henter `source_id`, Gem sender `p_source_id`
(default 1) → knækker ikke af RPC-DROP. Single-narrativ-UI bevaret; faner er follow-up.

**Læsere.** Web `public.ts` + mobil `load.ts` vælger foretrukne DAA-udgave pr. medlem/person via
`pickPreferredBio` (deterministisk, i stedet for "første by id"/"første mødte"). Adfærd uændret i
dag (alle 591 narrativer = DAA source 1). Cross-medlem-concat (web founder-først) urørt.

**Tests:** web 124/124 (+`pickPreferredBio`, `mapNarrativer`, arg-buildere inkl. `opretKilde`),
mobil 257/257, tsc + build grønne. DB verificeret mod lokal prod-kopi + skema-shape-asserts i
`db-verify.sql`. FK-embed-formen (objekt, ikke array) bekræftet mod eksisterende prod-kode
(`joinEvidence`'s `citation→source(titel)`).

**Udestår (bevidst):** (1) **Prod-cutover** — migrationerne er kun kørt mod lokal `daa_test`; den
rigtige `DROP`-transition (gammel 4-arg → 6-arg) fyrer først ved koordineret merge + web-deploy.
(2) **Udgave-byline i læseren** er udskudt (source-metadata dropfiltreres i `public.ts`/`load.ts`;
kun værdi ved >1 udgave). Se spec §6.

## Redaktør: klikbar familie-navigation + fødsels/dødsår (web+mobile, 2026-07-03)

Redaktør-familieoversigten kan nu **navigeres** og viser mere kontekst. Merget til `main`
(`bffdfc2`) + pushet.

**Navigation.** Partnere, børn og forældre i familie-sektionen er nu klikbare og åbner den
pågældende persons redaktør-flade. Web: `setRecordId` (samme flade); mobile: `router.push`
(ny editor-skærm) — sidstnævnte genbruger nøjagtig `PersonRad`-primitiven der allerede drev
forældre-navigation. Ugemte narrativ-edits kasseres stille ved navigation, bevidst identisk med
person-listens eksisterende adfærd.

**Fødsels/dødsår.** Børn (og partnere) viser nu årstal i oversigten. Kilden er den allerede
loadede `model.byId[pid].years` (samme cache som navne-opslaget) — **ingen ekstra DB-query**.
Nyt `aar`-felt tilføjet `FamilieBarn`/`FamiliePartner` i read-laget (`mapFamilieRows`), spejlet
web+mobile for at holde "hold i sync"-kontrakten.

**Modellen urørt:** navigation er ren læsning; edit/slet gik i forvejen gennem de append-baserede /
fortrydbare `red_*`-RPC'er. Ingen invariant-brud.

**Verifikation:** web 112/112 + mobile 249/249 tests + tsc grønne; web build ok; ny
`redaktionRead.test.ts` (web) + opdateret mobil-test dækker år-propagering. iOS-simulator-
runtime-verifikation **udskudt til fysisk enhed** pga. et RN-fetch-miljøbug på simulatoren
(-1005 "network connection was lost" mens host-curl + sim-Safari når Supabase fint) — ikke en
fejl i ændringen. Se memory `mobil-sim-rn-fetch-1005`.

## TNG-QA Etape 3+4 + spøgelses-union-oprydning (2026-07-03)

Adresserede TNG-QA-rapportens 5 dato-uenigheder (Etape 3) + 10 manglende links (Etape 4).
Undervejs afdækkedes en **systematisk spøgelses-union-fejl** i data.

**Etape 3 — vores datoer stod fast (change_set 3):** alle 5 dato-uenigheder blev adjudikeret mod
DAA-kilden (narrativen) — vores `date_raw` matcher bogen i alle 5; TNG havde fejlene (1-10 år). I
stedet for korrektion blev TNG oprettet som `source` (id 2) + TNG's 5 datoer loadet som
**konkurrerende assertions** på død-fakta, med vores konklusion uændret blåstemplet (evidenslag §1).

**Etape 4 — 8/10 falske positiver:** V-1/IV-1's "manglende far" fandtes allerede via samme_som;
V-56/V-95 var allerede ægtefæller; QA-pipelinen traverserer bare ikke samme_som/stub-dubletter.
Reelt: **V-121-dedup** (change_set 4 — ægtefælle-stub 826 = samme som V-114/409, intra-slægt-ægteskab)
+ **I-103-grenen** var strukturelt ødelagt.

**I-103-gren-reparation (change_set 5):** loaderen havde skabt spøgelses-unioner mellem I-103 og hans
far (I-97) + 3 sønner, efterladt 10 børn (I-109-118) forældreløse, og moderen uoprettet. Bogen: "Gift
1673 med Maria Elisabeth von Buchwaldt til Tresdorf ... 10 børn". Genopbyggede fam 4 (bar det ægte
vielse-1673-fakta): oprettede Maria Elisabeth, tilknyttede de 10 børn, slettede 3 spøgelses-unioner.

**Spøgelses-union-oprydning (change_sets 6+7):** systematisk scan fandt **26 barnløse unioner** hvor et
barn var fejl-"gift" med sin egen far/ane (fx I-19 Johann m. far I-11; I-12/13/15 m. progenitoren I-1).
11 direkte-forælder + 15 ane-spøgelser slettet. Diskriminator: barnløs + begge interne + **navn≠ref**
(se nedenfor). Én kryds-linje-union (fam 11, I-112 m. III-79 Hinrich) bekræftet ÆGTE af bruger, bevaret.

**Rodårsag (dokumenteret, endnu ikke rettet i loader):** spøgelserne opstår når et barns mor-grupperings-
heading ("med X (se nr. Y)") bliver til en fake-`aegteskab` hvor `partner_navn` (moderen) og
`partner_ekstern_ref` ("se nr. Y" → en ane) er UENIGE; `load_daa.R` (~l.280) linker ref'en og ignorerer
navnet → barn "gift" med ane. **Guard (næste skridt):** afvis intern-ref-link når navnet ikke matcher
`partner_navn`. Et reload gen-skaber ellers alle 26 spøgelser. Alle 7 change_sets er fortrydbare.

## Børn af flergifte forældre knyttet til korrekt union (2026-07-03)

Loaderen hang tidligere ALLE børn af en flergift forælder på forælderens FØRSTE union
(`load_daa.R`, `fam <- fams[[1]]`), så børn af 2./3./4. ægteskab blev fejl-tilknyttet 1.
ægteskab. Generelt problem: 20 flergifte forældre, 65 børn berørt — fx alle Conrad de
Reventlows 10 andet-ægteskabs-børn (inkl. dronning Anna Sophie) lå på Anna Margaretha Gabel
i stedet for Sophia Amalia Hahn. Dataene til at rette det lå der hele tiden i hvert barns
`aegteskab_kontekst`.

**Loader (`load_helpers.R` + `load_daa.R`):** delt DB-fri matcher `match_barn_union()` — barnets
`aegteskab_kontekst` → rette union; partnernavn primær anker, ordenstal kryds-tjek, NA ved
uenighed/ukendt partner (gætter aldrig). Wired i child-loop via `recmap` (nøgle→rec); kun ved
2+ ægteskaber; uafklarede parkeres på partnerløs union frem for fejl-link. 34 testthat-tests.
Eksekveret write-frit mod alle 591 records via `--dry-run` (parkerede præcis 1: III-85).

**Prod-data (`fix_boern_multi_union.R`, samme matcher):** 64 børn flyttet, 1 parkeret, i ét
`change_set` (id 1, fortrydbart via `red_fortryd_change_set(1)`); idempotens-guard. Verificeret:
Conrad Gabel 6 / Hahn 10; 132 change-events (64×2+2+2 → intet barn tabt); kun family/family_member
berørt; acceptance-gate grøn (Anna Sophie nu på Hahn).

**III-85 (Detlef) — efterfølgende løst (`change_set 2`):** den automatiske parkering var her
et falsk-negativt. `aegteskab_kontekst` var en ekstraktionsfejl (indeholdt en fremmed persons
ægteskab "Margaretha von Rumohr"; Detlef døde som spæd og var aldrig gift). Bogens tekst: "af
første ægteskab med Catharina von Brockdorff" — moderen ER Brockdorff (Friedrichs 1. ægteskab).
Flyttet tilbage til fam 175 + park-union 380 slettet (`red_fortryd_change_set(2)`); kildefeltet i
`clean-v2.json` rettet så reload rammer rigtigt (matcher: idx 1 via begge). Læring: parkering
beskytter mod falske påstande, men et menneske med kilden er facittet.

## Redaktør-web-cohesion: v2-header + person-browse (2026-07-03)

Bragte redaktør-fladen (`web/`) i tråd med publikums-web-v2 (Følgesvend). Committet `91b7797` på
`feat/samme-som-collapse`; header-ændringerne ført både i design-mockuppen og den kørende app.

**Header (`design/project/Reventlow-redaktion.dc.html` + `web/src/Redaktion.tsx`):** DAF-logo-lockup +
"Danmarks Adels Aarbog" + mono "Redaktion · Dansk Adels Forening" (erstatter R-firkant + "Redaktion ·
Reventlow"); slægt-chip m. crest-ring + "Reventlow ▾" (verbatim fra web-v2); header-mål 66px/gap 22/
padding 0 26px; mockup-link "Åbn publikumsvisning" → web-v2 (v1→v2).

**Person-liste (spejler Følgesvend §9.1/§9.2):** A–Å grupperet liste + alfabet-hop, sortér navn/fødeår
(`RedPerson.born`, aldrig dødsår), linje-filter som chips fra `model.lineage` (filtrerer KUN listen —
redaktør har intet stamtræ at hoppe fokus i). `buildBrowse` generaliseret strukturelt (`BrowsePerson`)
så samme testede motor driver både `ModelPerson` og `RedPerson` via et `name`-alias; id-rummene flugter
fordi redaktør-modellen loades `collapse:false`. Ikke-person-entiteter beholder den flade søgeliste.

**/simplify (4 parallelle agenter):** `personBrowse` gated til person-entiteten (ellers null — sparer en
900+-personers browse ved hvert tastetryk under andre entiteter); to næsten-ens række-renderere gen-forenet
til én `listRow`-helper; `browseInput`-memo inlinet; memo-dep smalnet til `lineage.byPerson`. Udskudt (uden
for diff): udtræk delt `LinjeChip`/`<BrowseControls>` på tværs af Følgesvend+Redaktion.

**Verifikation:** `tsc` rent · 94/94 web-tests (18 browse) · prod-build OK. **Ikke** visuelt/runtime-verificeret
i browser (ingen browser-driver i repo'et).

## Redaktionel samme_som-linking implementeret + DB live i prod (2026-07-02)

Redaktør-funktion til at markere to `person`-poster som samme fysiske person (producenten til det
allerede-live collapse). Fuld cyklus: brainstorm → 3× Codex-review (design+spec) → 7-task TDD-impl → /simplify.

**DB (LIVE i prod, ende-til-ende-verificeret):** `enforce_samme_som_invariants`-**trigger** (BEFORE INSERT
på `relation`) håndhæver graf-invarianterne (self-link, unik sink/ingen multi-sink, ingen re-root) for ALLE
insert-veje — ikke kun RPC'en (Codex-3-fund: en RPC-lokal check kan omgås af `red_relation`/undo/load/manuel).
`red_samme_som` (evidens-komplet wrapper: relation+assertion+afklaret-conclusion, advisory-lås, idempotent) +
`red_fjern_samme_som` (komplet evidens-slet via delt `_delete_relation_evidence`-helper) + `red_relation`
afviser `rolle='samme_som'`. Anvendt via MCP `apply_migration`; verificeret mod prod med rollback-DO-blok
(opret/idempotens/G3-multi-sink/self-link/fjern) — 0 muterede rækker, 2 rigtige links intakte.

**App (web+mobile spejlet, testet):** `sammeSom`/`fjernSammeSom` Change-arter, `fetchSammeSomLinks` +
retnings-mapping, rådgivende `previewSammeSom` (kører collapse med hypotetisk kant), og UI i person-editorens
relations-sektion ("Samme person"-liste + fjern + "Marker som samme person" → PersonPicker → retningsvælger +
pre-flight-hint → dry-run/LIVE). Mobile 247, web 94, tsc rent.

**Codex-fund (3 runder, alle løst):** invariant → trigger (H1); enten-retning skjuler re-root → modsat-retning
afvist, re-root=fjern+opret (H2); slette-orden fejler på citations → genbrug komplet sekvens (H3); pre-flight
ikke-autoritativt (RLS-datasæt-afvigelse); evidens-kontrakt (valgt_assertion_id/blaastemplet_af); concurrency
→ advisory-lås; `max(id)+1`-race = arvet codebase-begrænsning (bruger-accepteret v1). /simplify: delt
delete-helper + fjernet død G5-trigger-walk. Spec: `docs/superpowers/specs/2026-07-02-redaktionel-samme-som-linking-design.md`.

**Udestår:** manuel live-verifikation af UI'et (web-browser + Expo).

## Stamtræ: Kolonner-visning + bidirektionel aner/efterkommere (web + mobile) (2026-07-03)

Stamtræets **Kolonner-visning (variant B)** færdiggjort og udvidet til begge retninger, i
**både web og mobile**.

**Trin 1 — Kolonner på web (lukker item 8 fra web-v2-porten):** segmenteret kontrol
Fokus/Kolonner + vandret-scrollende drill-down-kolonner (matcher mobilens eksisterende variant B).
Ren `buildTreeColumns` i `web/src/data/tree.ts`; drill-valg gennem historik-fri `onFocus` (adskilt
fra `onPick` så dyb drill ikke fylder tilbage-stakken). `/simplify` (4 fund anvendt) + advisor.

**Trin 2 — bidirektionelle kolonner (aner + efterkommere):** fokus er nu et fast **anker** i
midten; aner folder ud til venstre (Forældre → Bedsteforældre → Oldeforældre → Tipoldeforældre →
**N× Tipoldeforældre**), efterkommere til højre (Børn → Børnebørn → …). Bilineal ane-drill via
`parentsByChild` (vælg forælder → dens to forældre). Delt retnings-parametriseret bygger
(`buildBidirectionalColumns` med visited-`Set`-cyklusguard + stabile `kind:depth`-keys), spejlet
web (`data/tree.ts`) + mobile (`data/selectors.ts`). Web parentsOf tilføjet; mobile genbruger sin.

**Tilstands-arkitektur:** web = lokal `useState` (`anchorId`/`up`/`down`) med **frontier-reset**
(kun yderste ane/efterkommer bevares ved fokus-skift — ellers ekstern nav → nulstil); mobile =
zustand-slice (`path` → `anchorId`/`up`/`down`), navigations-mutatorer nulstiller eksplicit, drill-
mutatorer bevarer ankeret. Auto-scroll: centrér anker + kompensér prepend (web `useLayoutEffect`;
mobile scroll-events). Variant A/C urørt.

**Codex-review af design-spec (1 BLOCKER + 5 SHOULD-FIX indarbejdet):** BLOCKER = reset måtte være
frontier-baseret, ikke fuldt medlemskab (ekstern nav til en mid-strip-node skal folde drillen);
plus rigtig cyklus-guard, kollisionsfri kolonne-keys, platform-specifik scroll, forældre-antal ej
antaget=2, dansk genealogisk label-kortform. Se `docs/superpowers/specs/2026-07-03-kolonner-aner-
efterkommere-design.md`.

**Verificeret:** web tsc + 109 tests + build; mobile tsc + 249 tests. **Web visuelt bekræftet af
bruger.** **Mobile empirisk verificeret i iOS-simulator mod prod-Supabase** (idb-drevet): bidirektionel
default (begge forældre), 3 niveauer ane-drill m. korrekte labels/chevrons, glidende up-scroll, og
samme_som-collapse gennem traverseringen (Conrad → Detlef). Descendant-drill på mobile ikke separat
gentestet denne session (barnløs fokus-linje), men samme mekanisme + web-verificeret.

## samme_som-collapse implementeret (web + mobile) (2026-07-02)

Frontend identitets-projektion: en person der optræder som flere DB-poster (linket via
afklarede `samme_som`-relationer) vises nu som ÉN person i søgning, person-visning og
slægtskabsfinder — i **både web og mobile**. 9-task plan (`docs/superpowers/plans/`)
implementeret TDD, dual-reviewet efter hvert logisk trin.

**Kerne (`collapseSameAs.ts`, spejlet web+mobile):** ren funktion der grupperer `samme_som`-
linkede id'er (union-find), vælger kanonisk = unik sink, **validerer og karantænerer** konflikter
(self-forælder/-ægtefælle, global cyklus, konkurrerende forældre, hard vital/køn-konflikt) på den
kombinerede projicerede graf via en **fixed-point-løkke**, fletter person-posterne (coalesce,
`years`-regen, `privat=OR`, konfidens-stærkeste kant-dedup) og omskriver alle graf-kanter til
kanoniske id'er FØR `buildModel`. Motoren (`buildModel`/`relationship`) er URØRT. Reversibel:
returnerer `canonicalIdById` + `mergedFrom` + `quarantined`.

**Integration:** `load.ts`/`model.ts` henter godkendte `samme_som` (relation + afklaret conclusion,
polymorf → to fetches + JS-match) og folder før `buildModel`. Alle person-id-bærende Aux-strukturer
kanoniseres; `linjeByPerson` er nu multi-linje. Rute/fokus/rel/mig-id'er resolves gennem alias-map
(inkl. `meId` ved read-site). Person-visningen viser multi-linje badge + proveniens-note
("Optræder i Aarbogen som …"). Redaktion collapser IKKE (ser separate DB-poster).

**Dual-review (7 kerne-fund + 3 integrations-fund, alle rettet):** Codex opgraderede to "defer"
til reelle silent-corruption-bugs (konkurrerende forældre maskeret af rejekteret gruppe →
fixed-point; konfidens-nedgradering ved dedup). code-analyzer fangede et meId-read-site-bug
(★ Dig-badge brød for foldede personer). Se `docs/reviews/16-samme-som-collapse-kerne.md`.

**Empirisk valideret mod prod:** de 2 eksisterende `samme_som` (Conrad III-58→V-1, Detlef
III-104→IV-1) er begge `afklaret`, cross-linje, konflikt-fri → folder rent; founder'en arver
sit forælder-link (der før manglede på founder-posten). Suiter: mobile 236, web 84.

**Udestår (manuel):** Expo-simulator + web-browser-verifikation af selve skærmene (navigation
via begge alias-ruter → samme samlede person + badge).

## DAA-reimport Etape 1+2, data-tab-genopretning, grundlægger-links, samme_som-design (2026-07-02)

**Etape 1 — loader/validate-hærdning (merget til main, pushet):** 9-task subagent-drevet
forløb (final-reviewet af Opus). Partner-dedup via `partner_ekstern_ref` (dry-run: 41 færre
dubletter); børne-løkke rewrite (15a/15b-opslag + observerbar logging af uopløste — kun 3
uopløste i hele stamtavlen); deterministisk `date_min/max` fra `date_raw` (+ floruit-spans);
`--dry-run` + RESET-guard (fail-closed) + `--force-reset`; frossen trin ③-prompt
(`references/extract-prompt.md`). Union-heuristik reverteret efter Opus-review (brugte
forkert kontekst-entitet, 0-impact). Suiter: R 181, validate 38, escalate 16.

**Data-tab-hændelse + Etape 2-reload:** Live-basen (`xjnvdhajfyrcytatnzos` — appen, R og MCP
peger alle her) var i en TIDLIGERE session overskrevet til 3 test-personer. Bruger godkendte
reset-reload af fuldt datasæt: `load_daa.R clean-v2.json --reset --force-reset` → **922
personer** (41 færre dubletter), cache regenereret, 70 levende. TRUNCATE CASCADE ramte også
`profiles`/`lineage`/`suggestion` → genoprettet (redaktør-profil for johan@reventlow.dk;
5 lineage-navne) i et durabelt, idempotent `post_load_fixup.R` (par-opslag på linje/nr =
reload-sikkert). Ryddet 32 orphaned `change_set` + 191 `change_event`.

**TNG-QA-måling (docs/reviews/tng-qa-rapport-2026-07-02.md):** manglende relations-links
**125 → 10** (Etape 1 genindvandt 92%), enig 177 → 288, 0 falske links. Bekræfter empirisk
at de manglende links var et linking-problem (bucket c=0), ikke et udtræks-problem — re-udtræk
var ikke nødvendigt. Rest: 10 kryds-linje-links (Etape 4) + 5 dato-uenigheder (fejl-attribueret
`date_raw`).

**Grundlægger-identitets-links:** Conrad de Reventlow (III-58↔V-1) + Detlef de Reventlou
(III-104↔IV-1) — samme person i to linjer — linket via `samme_som`-relation (evidenslag),
bekræftet via TNG-crosswalk. Løser samtidig 2 af de 10 manglende links.

**samme_som-collapse — design + plan (dual-reviewet, ikke implementeret):** frontend
identitets-projektion så en person med flere DB-poster vises som ÉN (søgning/person-visning/
slægtskabsfinder). Spec `docs/superpowers/specs/2026-07-02-samme-som-collapse-design.md`
(Codex-reviewet: valideret reversibel projektion, completeness-baseret GDPR, konflikt-karantæne).
Plan `docs/superpowers/plans/2026-07-02-samme-som-collapse.md` (9 tasks, web+mobile). **Klar til
implementering næste session.**

## Flere-forældrepar datafix (2026-07-01)
* **Bruger observerede** at personer så ud til at have flere forældrepar. Undersøgt:
  90 personer med beviseligt modstridende forældrepar, 163 fejlagtige `barn`-links i alt
  (af 559). Rodårsag: `load_daa.R`'s child-linje-fallback prøvede et upålideligt LLM-udtrukket
  `boern.linje`-felt FØR forælderens egen linje — når feltet var forurenet, matchede et
  genbrugt løbenummer nogle gange en helt anden gren/generation.
* **Rettet:** `load_daa.R:246-260` dropper nu `stated`-fallback helt, matcher
  udelukkende egen linje (så en gen-indlæsning ikke kan genskabe fejlen). Prod-data
  korrigeret ved SQL-sletning af de 163 spuriøse rækker (kørt som versioneret `change_set`
  #3, fuldt fortrydbart), lokal backup af `family_member` gemt i `work/`. 4 personer uden
  linje-match + 46 nu-forældreløse personer er sandsynligvis rescuable via en målrettet
  gen-kørsel af den fixede loader (ikke gjort her — kræver egen plan). Sideeffekt: løste
  også den tidligere kendte era-tie-break-fejl (børn født før forældre) fuldt ud.
  Se `docs/reviews/11-flere-foraeldre-datafix.md`.

## Versionering + hyperlinks — real-device Expo-verifikation + DB-bugfix (2026-07-01)
* **App-lag afprøvet på ægte iPhone-simulator mod rigtig prod-Supabase** (`idb`-baserede taps,
  ikke kun statisk `tsc`/jest). Konfirmeret empirisk: hyperlink-rendering/navigation,
  bio-klamp, MentionPicker insert-at-cursor, fortryd-flow, redo-knap på reversal-post.
  Konflikt-retry (B9-divergens) forbliver utestet.
* **DB-bug fundet + rettet:** `_version_upsert_row` (fortryd-restore-helper) manglede eksklusion
  af `GENERATED ALWAYS`-kolonner fra sin dynamiske `INSERT`/`ON CONFLICT`-kolonneliste —
  Postgres tillader slet ikke en eksplicit værdi for disse. Ramte `narrative.fts` (aktiv
  fuldtekstsøgning i prod, selvom CLAUDE.md §9 hævdede den var kommenteret ud — schema-drift).
  Konsekvens: fortryd fejlede hårdt for ENHVER tabel med en generated-kolonne. Transaktionen
  rullede korrekt atomisk tilbage (ingen delvis korruption), fundet + rettet + genverificeret
  ved en ægte LIVE-testskrivning + fortryd på en obskur testperson (godkendt af bruger).
  Migration anvendt til prod; `schema.sql`/`db-migrations.sql` opdateret.
* **UI-bug fundet + rettet (brugerfund):** dry-run-toggle-switchen i `redaktion/person/[id].tsx`
  havde omvendt polaritet ift. den identiske switch på Konto-/dashboard-skærmen — samme felt,
  modsat "til højre = sikker"-betydning afhængig af skærm.
* Se `docs/reviews/10-app-lag-hyperlinks.md` for fuld verifikations-log.

## Versionering + hyperlinks (App-lag, RN/Expo) — kode-komplet, dual-reviewet, IKKE Expo-kørt (2026-06-30)
* **Hyperlink-tokens i narrativ:** `mentions.ts` (parser/encoder, ren funktion, 17 jest-tests)
  + `NarrativRenderer` (klikbar visning, wrapper `Typography.Body` 1:1) + `MentionPicker`
  (@-mention-søgning, indsæt-ved-cursor i redaktør-editoren).
  Token-grammatik (spec §5.1): `[[type:id|tekst]]`, 10 fast entity-typer, `\|[]`-escape.
* **Redaktionel historik-skærm** (`redaktion/historik/[id].tsx`): change_set-liste m. "Fortryd"
  + en samlet døde-links-rapport (D1/D3). Fortryd ruter gennem den eksisterende
  `pending`+`SkrivePreviewSheet`-modal (dry-run/LIVE-bekræftelse) — IKKE et direkte
  `submitChange`-kald, som var en tavs no-op i dry-run (fanget proaktivt før review).
* **Dual-review (cycle 10, Claude+Codex):** H1 [HIGH] escape-asymmetri — `makeToken` eskaperede
  ikke `\` selv, så et label der ender på backslash fik scanneren til at sluge afgrænserens `]`
  og hele tokenet lækkede som synlig tekst. Min første fix-recipe (narrow scanner-regex) var
  selv FORKERT — Codex korrigerede til encode-siden (escape `\` i `makeToken`); empirisk
  verificeret med 7 round-trip-cases. H2 [MEDIUM] `reverteret`-feltet havde omvendt semantik
  (`reverterer_id` peger FRA den nye fortrydelse TIL den originale, ikke omvendt) — Fortryd-
  knappen forblev aktiv på allerede-fortrudte poster. M3 [MEDIUM, Codex-only fund] stille
  fejl-svælgning i `MentionPicker` umuliggjorde at skelne netværksfejl fra reelt nul personer.
  Se `docs/reviews/10-app-lag-hyperlinks.md`.
* **`/simplify`:** 6 behavior-preserving cleanups (NarrativRenderer→Body-wrapper, dødt
  TYPES-sæt + dead defensiveness i mentions.ts, `erFortrydKonflikt`-ekstraktion + regressionstest,
  unødig Number/String-tur-retur fjernet, `useRef` i stedet for `useState` til cursor-position).
* **Verifikation: `tsc --noEmit` 0 fejl, jest 197/197 grøn.** Det er taget for hvad det er — det
  dækker rene funktioner og mappere, IKKE render/interaktion (cursor-indsætning i `TextInput`,
  nested-`Text`-clamp, `Alert`-flow). **Ikke Expo-kørt i denne session** (intet device/simulator
  tilgængeligt) — se manuel punch-list i review-dokumentet, §"Manuel Expo-verifikation".
  Vigtigst deri: eksisterende narrativer i basen har INGEN `[[...]]`-tokens endnu (funktionen
  er ny), så `NarrativRenderer` over LIVE-data i dag tester reelt kun plain-text-fallbacken.
* **Branch `feat/versionering-hyperlinks-app-lag` ikke merget/pushet** — afventer brugerens
  beslutning (git-gate).

## Versionering + hyperlinks (DB-lag) — implementeret, dual-reviewet, applied til prod (2026-06-30)
* **Fortryd-bar redaktionel ændringshistorik:** hybrid change-set-log (`change_set`/
  `change_event`) — hver `red_*`-skrive-RPC åbner et re-entrant `change_set`, og en generisk
  `log_change`-trigger på alle 22 versionerede tabeller snapshotter før/efter-tilstand
  (kolonne-projektion: `visning_*`/`email`/`rolle` ekskluderet). `red_fortryd_change_set`
  inverse-applier ét sæt i én transaktion med optimistisk divergens-tjek.
* **Append-baseret `red_edit_oplysning`:** ny påstand + re-peg konklusion (ærer invariant #1);
  returtype `void→jsonb` (`ny_assertion_id`). App-laget upåvirket (consumer læser ikke retur).
* **Hyperlinks i fri-tekst:** `[[type:id|tekst]]`-tokens → `parse_mentions` + afledt
  `text_mention`-indeks (regen-trigger på narrative/note) + døde-links-view. RLS dobbelt-gating.
* **Historik-API:** `hist_for_subjekt`/`hist_events` (redaktion-only, SECURITY DEFINER);
  deny-all RLS på historik-tabeller.
* **TDD mod lokal prod-kopi** (free tier → ingen branch; postgresql@17 + auth-shim + read-only
  pg_dump). **5 bugs fanget før prod:** 3 under impl (begin_change_set-placering ved flerlinjet
  rolle-tjek, assert-filter-fejlklassificering, `FOREACH IN ARRAY NULL`-crash) + 2 HIGH i
  dual-review (Claude+Codex+code-analyzer, konvergent): DELETE-inverse manglede divergens-tjek
  (blind PK-overskrivning) og `_version_upsert_row` nulstillede NOT NULL skip_cols
  (`profiles.rolle`-crash). Begge empirisk reproduceret + regressions-testet. Se
  `docs/reviews/09-versionering-hyperlinks-db.md`.
* **Applied til prod Supabase (atomisk, --single-transaction):** verificeret — 4 tabeller,
  22 log-triggere, RLS aktiv, `red_edit_oplysning`→jsonb, 963 personer uændret. Pre-apply
  schema+data-backup taget lokalt. 24 verify-asserts grønne + clean-slate-konsistent.
* **Bevidst deferret:** TOCTOU (single-writer PoC), parse_mentions open-token (delt-parser/app-lag),
  `red_doede_links` dækker 3/10 mention-typer (completeness).

## TNG-QA: pipeline komplet ende-til-ende (Trin 1-6) + kalibrering (2026-06-30)
* **Forbindelses-bug fixet:** top-level `on.exit()` under `source()` fyrede
  `dbDisconnect(shutdown=TRUE)` FØR næste query → "Invalid connection". Lukker nu
  forbindelser efter sidste brug.
* **Trin 3-4-glue (`scored` → `crosswalk`):** `our_match_frame`/`tng_match_frame`/
  `build_scored` — blokering på fornavns-initial + fødselsår-vindue, vektoriseret
  overlap, top-K pr. person rangeret på score. Fix: `person.id` bigint→integer
  (data.frame recycler ikke integer64); DATE→år-konvertering.
* **Auto-tier bootstrap-kalibreret:** den uniforme "Reventlow" gjorde `unique_block`
  ubrugelig (auto=0). Erstattet med ambiguitets-margin (`ambiguity_margin=0.05`):
  auto kræver score≥0.90 OG bedste kandidat klart foran nr. 2 OG top-kandidat.
  Kalibreret mod bootstrap-ankre (entydige eksakte matches). `calibrate.R` ny.
* **Dato-overlap som scoring-evidens:** `birth/death_overlap` er nu kun TRUE ved
  reel dato på begge sider (`.overlap_evidence`) — fjerner 0.3 "gratis" vægt på
  dato-løse par. Auto kræver nu reel fødselsårs-korroboration. auto≈347, review≈658.
* **Trin 5 gen-kørsels-crash fixet:** review-køen skrives nu med udfyldelig
  `afgoerelse`-kolonne; `merge_review_decisions` tåler tom/manglende afgørelse.
* **Trin 6 aktiveret — relations-QA mod TNG:** sammenligner ægteskaber/forælder-barn/
  datoer/køn; producerer `docs/reviews/tng-qa-rapport-<dato>.md`. **GDPR PII-gate =
  input-gating** (filtrér begge sider til afdøde-ikke-private FØR sammenligning,
  fail-closed) — verificeret 0/70 levende-id i rapporten. Første kørsel: 183
  handlingsorienterede uenigheder.
* **Tests:** 35 (match/report/review/extract/pull), alle grønne.

## Slægtskabsfinder: bilineal multi-linje + konfidens på stien (2026-06-30)
* **Bilineal:** "Er vi i familie?" (`mobile/src/data/relationship.ts`) traverserer nu BEGGE
  forældre-linjer (BFS over `parentsByChild`) i stedet for kun den primære forælder-kæde.
  Slægtskab via mor-linjen blev før tavst overset — en reel korrekthedsfejl i en sammengift slægt.
* **Multi-linje:** returnerer alle distinkte forbindelses-linjer (`lines[]`), nærmeste først.
  Anepar grupperes til ÉN linje (helsøskende vises ikke som to). Klassisk dobbelt-fætterskab
  giver to anepar-linjer. "Halv" markeres kun når den anden forælder faktisk er kendt og
  forskellig (ingen falske halvsøskende fra datahuller).
* **Køn:** kønsbestemte moderne etiketter (Fætter/Kusine, Onkel & niece, Mor & søn) via
  `person.koen`, med kønsneutral fallback der matcher de oprindelige strenge.
* **Konfidens på stien (invariant #7):** `family_member.konfidens` trækkes nu ind i modellen
  (loader + kant-indeks `konfByEdge`). Hver linje beregner sit SVAGESTE staterede led; en sti
  gennem et formodet/omstridt led flages (`usikker`) — på resultat-kortet, pr. trin på
  tidslinjen, og på øvrige linjer. Uangivne led larmer ikke. Samme kant med flere påstande
  beholder den stærkeste konfidens. *Hage:* de fleste eksisterende links er `NULL` (bulk-load),
  så visningen viser usikkerhed i takt med at konfidens-data berigt (fx de 97 kendte fejl-links).
* **Datalag:** `koen` + `konfidens` tilføjet til visningsmodellen (types + loader), bagudkompatibelt.
* **Tests:** relationship-suiten udvidet 6 → 27 (bilineal, anepar-collapse, halv, dobbelt
  fætterskab, kønsetiketter, konfidens-svageste-led). Hele suiten 141/141 grøn, tsc + eslint rene.
* **Roadmap:** `docs/moed-en-slaegtning-roadmap.md` — telefon-til-telefon slægtskab ved fysisk
  møde (NameDrop-stil dobbelt-aktiv-handling, QR-MVP → BLE → UWB, GDPR-samtykke-design).

## Opret-ny-entitet — Tilføj-fanen (2026-06-29)
* **Hvad:** Redaktøren kan oprette ny person/gods/kilde/organisation fra "Tilføj"-fanen gennem
  dry-run→live-gate; person → lander i editoren, øvrige → vises i listen.
* **4 nye SECURITY DEFINER RPC'er (deployet prod):** `red_opret_person` (INSERT + navn/født/død/titel
  som facts via `red_upsert_fakta`, privat=true default), `red_opret_estate`, `red_opret_kilde`,
  `red_opret_organisation`. id=max+1, NULL/whitespace-navn afvist. Grants tilføjet i
  `db-migrations.sql` (schema.sql bærer ingen grants by design; db-rls.sql grant-loop dækker red_*).
* **B1/B2 (Codex-review):** `loadRedaktionModel(force)` tvinger reload (var no-op på 'ready');
  `SkrivePreviewSheet.onApplied(result)` bærer ny id til navigation.
* **`OpretSheet`:** grid + per-type formularer; `buildRpcCall`-cases for 4 opret-arter; enkelt-Modal
  (kun én Modal synlig ad gangen via `visible={visible && !pending}`); wire til Tilføj-fanen.
* **Privatliv:** ny person privat=true (levende=false=anon-læsbar → glemt toggle ville publicere).
* **Udskudt:** sted-picker til gods (ingen place-picker/placeListe); inline-opret fra PersonPicker;
  medie/våben/majorat; dedup-UNIQUE; id-sequence (post-PoC).
* **Test:** jest (`buildRpcCall` opret-arter) + DB rollback-test + manuel web-e2e.
* **Codex-review-fix (2026-06-30):** nestet native Modal fjernet — OpretSheet rendrer nu én Modal
  ad gangen + SkrivePreviewSheet som søskende; Task 1 happy-path-test omskrevet fra psql-`\gset`
  til `DO`-blok med `RAISE EXCEPTION`-asserts (eksekverbar via `execute_sql`).
* **GDPR-hærdning cycle-08 (2026-06-30):** `p_privat`-param fjernet fra `red_opret_person` — privat
  er nu FORCERET `true` i INSERT-kroppen; gammel 7-arg-signatur DROPpet på PROD (ny 6-arg erstatter).
  Synlighed skiftes herefter udelukkende via `red_set_privat`. `OpretSheet` og `buildRpcCall`
  fjerner `privat`-feltet fra payload; jest-test opdateret (30/30). Lukker anon-eksponerings-footgun:
  en crafted RPC-kald med `p_privat=false` kunne gøre en afdød person anon-læsbar ved opret.

## Plan 2C-2b — redigerbar familie-sektion (partner + barn + konfidens) i redaktør-person-editoren (2026-06-29)
* **Hvad:** Redaktøren kan nu tilføje og afkoble ægtefælle/partner, tilføje og afkoble børn
  samt justere konfidens på familie-links direkte i person-editoren — alt via det eksisterende
  SkrivePreviewSheet-gate (dry-run → live). HVERV/GODSER/KILDER er uændrede fra 2C-2a.
* **4 nye SECURITY DEFINER RPC'er (deployet mod prod 2026-06-29):**
  - `red_opret_union(p_partner_a, p_partner_b, p_type, p_ordinal)` — opretter ny family-entitet
    + 2 partner-links. INGEN auto-dedup: samme par kan gifte sig igen — par-dedup ville flette
    børn og event-tidslinjer fra to selvstændige ægteskaber (Codex H2). partner_a==b og ugyldig
    type afvises med RAISE.
  - `red_tilfoej_barn(p_family_id, p_barn_id, p_rolle, p_konfidens)` — tilføjer barn-link til
    eksisterende family. Cyklus-guard via recursiv CTE: tilføjer en ane som barn → RAISE (Codex H3).
    Selv-forælder (barn==en af familiens partnere) afvises. PK-dublet = no-op. Ugyldig
    rolle/konfidens afvises.
  - `red_set_familie_konfidens(p_family_id, p_person_id, p_rolle, p_konfidens)` — UPDATE
    `family_member.konfidens` for præcist ét link; ukendt link → RAISE; ugyldig konfidens → RAISE.
  - `red_slet_familie_link(p_family_id, p_person_id, p_rolle)` — sletter KUN `family_member`-rækken.
    Sletter ALDRIG `family`-entiteten (heller ikke når det er det sidste link), da family bærer
    276+ facts og 700+ notes uden FK — en family-sletning ville efterlade al evidens forældreløs
    (Codex H1).
* **`fetchPersonFamilie`** — per-person familie-fetch (unioner + barn-af-links), separat fra
  `redaktionAux` der ikke eksponerer `family_member.konfidens` eller de primærnøgler
  (`family_id`/`person_id`) som slet- og konfidens-kaldene kræver.
* **`eraAdvarsel`** — klient-side blød dato-advarsel (barn født udenfor forældrenes plausible
  livsrum). Advarer og tillader — afviser ikke. 27 verificerede historisk-inkonsistente tilfælde
  i eksisterende data ville trigger en hard-reject uberettiget.
* **`PersonPicker`** — sheet-komponent til valg af person (søg + tryk), brugt ved
  "+ Tilføj partner" og "+ Tilføj barn" i editoren.
* **`buildRpcCall`-cases** for `opretUnion` / `tilfoejBarn` / `setFamilieKonfidens` /
  `sletFamilieLink`; type `Change` udvidet med `familyId`, `personId` (familie-kontekst)
  og de 4 nye Change-arter.
* **Redigerbar ÆGTEFÆLLE/BØRN/FORÆLDRE-sektion** i person-editoren: tilføj partner
  (PersonPicker → opretUnion), tilføj barn (PersonPicker → tilfoejBarn, m. era-advarsel),
  juster konfidens (KonfidensVaelger → setFamilieKonfidens), afkobl
  (sletFamilieLink). FORÆLDRE-sektionen (personen som barn): forældre-NAVNE er read-only, men
  konfidens kan justeres og forkert forælder kan afkobles ("🗑 afkobl forælder" → sletFamilieLink).
* **Test:** 121/121 jest, tsc rent.
* **Controller-gate kørt (2026-06-29):** schema-backup (15 funktioner →
  `docs/db-backups/2026-06-29-prod-red-functions-2c2b-pre.sql`), 4 RPC'er deployet + grant-loop re-kørt,
  rollback-tests bestået (nul mutation): H2 samme par → 2 selvstændige unioner (ingen kollaps); H3
  cyklus-guard + selv-forælder afvist + PK-dublet no-op; konfidens-UPDATE + valideringer; H1 slet alle
  family-links → family-entitet + 276+ facts + 700+ notes INTAKT.
* **Final-review-fix:** era-advarsel medtager nu fokus-forælderens egne datoer (manglede → eget barn-tilføj
  ikke era-tjekket, dødt for én-forælder-unioner).
* **Udestår:** kun manuel web-e2e. Bredere redaktionModel-invalidering efter familie-write = §9-follow-up.


## Plan 2C-2a — redigerbar sektion-relationer (hverv/godser) i redaktør-person-editoren (2026-06-29)
* **Hvad:** Redaktøren kan nu tilføje og slette hverv- og godser-relationer direkte i person-editoren.
  Familie (family_member) og kilder (external_id) forbliver read-only i denne plan; familie-redigering
  er udskudt til 2C-2b. Alle ændringer passerer igennem det eksisterende SkrivePreviewSheet-gate
  (dry-run → live).
* **To nye SECURITY DEFINER RPC'er (deployet mod prod 2026-06-29):**
  - `red_slet_relation(p_relation_id)` — FK-ordnet evidens-cascade:
    citation → conclusion → assertion → note → relation. Nødvendigt fordi relations bærer ~955
    evidens-rækker uden FK (target_type/target_id er polymorft, ingen cascade-constraint).
  - `red_tilfoej_relation(p_subjekt_id, p_objekt_type, p_objekt_id, p_rolle, p_periode_raw)` —
    validerer objekt_type + eksistens, dup-guard (returnerer eksisterende id ved gentagelse,
    ingen dublet), indsætter relation.
* **`fetchPersonRelationer`** — ny pagineret per-person relations-fetch (ikke via `redaktionAux`,
  som dropper relation-id'er og ikke kan bruges til slet-kald).
* **`EntitetPicker`** — sheet-komponent til valg af entitet (gods, organisation m.fl.) med
  type-menu + navne-liste, brugt ved "+ Tilføj hverv/gods" i editoren.
* **`buildRpcCall`-cases** for `sletRelation` + `tilfoejRelation` (relations-kald vha. eksisterende
  write-gate); type `Change` udvidet med `relationId`, `sletRelation`, `tilfoejRelation`.
* **Test:** 109/109 jest, tsc rent.
* **Controller-gate kørt (2026-06-29):** schema-backup (13 funktioner + 43 policies →
  `docs/db-backups/2026-06-29-prod-red-functions-policies.sql`), begge RPC'er deployet mod prod +
  grant-loop re-kørt (kaldbare af `authenticated`), rollback-test bestået (FK-ordnet slet rydder
  al evidens uden orphans; dup-guard returnerer samme id; 4 valideringer afviser ugyldig
  objekt_type/ikke-eksisterende objekt) — alt i rollback-txn, nul mutation mod prod data.
* **Udestår:** kun manuel web-e2e (klik gennem editor). Bredere cache-invalidering efter relation-write
  (public person / gods-ejer-tidslinje / 2C-1 ownerCount stale til model-reload) er spec §9-follow-up.


## Plan 2C-1 — entitetslister (read-only) i redaktions-appen (2026-06-28)
* **Hvad:** Entiteter-tab er nu en type-menu med 6 typer (Personer · Godser · Kilder ·
  Organisationer · Medier · Våben), hver med tæller → read-only liste. Personer åbner 2A-listen →
  editor; de øvrige er read-only browse (ingen entitets-write-RPC'er endnu = 2C-2/2C-3).
* **Data:** `buildAux` udvidet med fem flade lister (`kilde/org/medie/gods/vaabenListe`) fra de rå
  arrays den allerede modtager + ét nyt `coat_of_arms`-fetch (våben). Læses fra redaktion-modellens
  aux (2B) — ingen ekstra fetch for de fire. `godsListe` er komplet (inkl. ejerløse godser, modsat
  `estateList`); ejer-tæller bevaret.
* **Auth-state:** lister/menu viser "Kræver redaktør-rolle" for ikke-redaktører (Codex fangede at de
  ellers ville sidde fast på "Henter…" permanent). "Henter…" kun under redaktør-load.
* **Korrektion (Codex):** `coat_of_arms` (våben) FINDES — tidligere fejlpåstand om manglende tabel
  rettet; våben inkluderet. `majorat` korrekt udeladt (en `slags` af estate, ingen egen tabel).
* **Review:** Codex-spec-review (auth-state + våben) + per-task spec+quality. 104/104 jest, tsc rent.
  Relations-redigering = 2C-2; entitets-write + detail-editor = 2C-3.


## Plan 2B — editor-dybde: selv-forsynende editor + køn + familie/sektion (2026-06-28)
* **Hvad:** Person-editoren åbner nu for ALLE personer inkl. de 70 levende (før: "Personen blev
  ikke fundet" fordi den lænede sig på den delte anon-model på 893). Tilføjet: køn-editor
  (redigerbar: mand/kvinde/ukendt → `red_set_koen`), familie (forældre/ægtefæller/børn) +
  sektioner (hverv/godser/kilder) **read-only**.
* **Separat redaktion-model:** ny store-slice (`redaktionModel`/`redaktionAux`) loades via
  redaktion-sessionen (`loadFromSupabase({includePrivat:true})` → 963 inkl. levende, getAll-
  pagineret), adskilt fra publikums-modellen → ingen GDPR-læk i publikums-faner. Editoren bruger
  de EKSISTERENDE selektorer (`parentsOf`/`childrenByMarriage`) + aux uændret → ingen divergens
  fra publikums-visningen (Codex-aligned, se decisions).
* **Narrativ-privat-fix:** `fetchPersonNarrativ` henter første narrativ by id (= præcis skrive-
  målet for `red_upsert_narrativ`) og editoren bevarer privat-flaget på Gem — før kunne en privat
  bio overskrives + gøres offentlig (Codex 2B #1).
* **Privat-toggle** initialiseres nu fra `person.privat` (før hardkodet false). `AppPerson.privat`
  tilføjet; publikums-load uændret default.
* **Review:** Codex-spec-review (skiftede arkitektur fra per-person re-derivation → separat model,
  fangede pagination + familie/hverv-divergens + narrativ-tab) + per-task spec+quality + idle-race-
  fix. 100/100 jest, tsc rent. Relations-redigering + medier + generisk editor = 2C.


## Plan 2A — person-liste & navigation i redaktions-appen (2026-06-28)
* **Hvad:** Entiteter-tab'en har nu en rigtig person-liste (søg + alfabet-hop + alfabetisk/fødeår-sort)
  → tap → person-editor. Dashboardets "Personer"-celle navigerer dertil. Løser URL-tastnings-smerten
  (ingen in-app-vej til en person → web-reload → skrivemode nulstillet).
* **Separat redaktion-fetch:** ny `fetchRedaktionPersoner` (mobile/src/data/redaktionRead.ts) henter ALLE
  personer inkl. levende/privat via redaktion-sessionen — **pagineret** (genbrug `getAll`/`.range`,
  PostgREST capper ved 1000 lydløst). Den delte publikums-model (`load.ts`) røres ikke → ingen GDPR-læk
  i publikums-faner. Verificeret live: redaktion ser 963, anon 893 (70 levende skjult fra publikum).
* **DRY:** `buildSearch` refaktoreret til pool-baseret `searchPool` (genbrugt af publikum + redaktion);
  publikums-`search.tsx` uændret.
* **Tags:** levende/privat-personer markeres i listen ("levende"/"privat"). `born` udledes direkte af
  visning_foedt (ikke dødsår — Codex 2A M1). Fejl-tilstand i listen (ikke tom-som-clean — cycle 03 NEW1).
* **Review:** Codex-review af spec (pagination + born-sort indarbejdet før impl); per-task spec+quality.
  94/94 jest, tsc rent. Andre entiteter + generisk editor = 2C; køn/familie-visning = 2B.


## Redaktions-UI kerne-skive — implementeret + DB-deploy (2026-06-27)
* **Hvad:** Vertikal kerne-skive af redaktør-appen (mobil editor): `redaktion/`-route-segment
  med native `(red-tabs)`-navigation, dashboard (rolle-kort + dry-run + konflikt-kø +
  entitets-grid), person-editor (evidens-lag: kerne-fakta navn/foedt/doed/titel med
  konklusion←oplysninger, redigér/slet/gør-til-konklusion/tilføj via inline-editor + narrativ),
  konto + login-sheet, skrive-preview-sheet (dry-run/live) og slet-bekræft m. cascade-advarsel.
* **Nyt evidens-read-lag** (`mobile/src/data/redaktionRead.ts`): `fetchPersonEvidence` henter
  den polymorfe model (fact/assertion/conclusion/citation) som N flade queries + klient-join
  (target_type/target_id har ingen FK → nested-select 400'er; citation→source nestes via FK).
  `fetchKonflikter` (konflikt-kø) + `fetchSletPreview` (cascade).
* **Write-lag udvidet** (`redaktionWrite.ts`): `buildRpcCall`-cases for redigerOplysning/
  sletOplysning/setKonklusion/setPrivat/sletPerson + `oversaetFejl` (dansk). Alle writes via
  én path (dry-run preview ELLER live RPC); cache regenereres af DB-trigger.
* **DB additivt (deployet live 2026-06-27):** `red_konflikt`-view (`security_invoker=true` —
  KRITISK, ellers omgår viewet RLS og lækker private personers konflikter); redaktion-read-RLS
  (rolle=redaktion ser private rækker, så privat-toggle ikke låser redaktøren ude);
  `red_slet_person_preview`-RPC (cascade-advarsel der spejler red_slet_person's indgående+udgående
  relations-slet). Backup taget før deploy (`~/daa-backup-20260627-redaktion-ui.sql`).
  Live-verificeret: view returnerer konflikt-rækker, RPC rolle-gated (P0001), privat-læk lukket (anon ser 0 private).
* **Review:** Codex-review af spec (8 fund indarbejdet før impl); per-task spec+quality-review;
  final whole-branch review (opus) READY — RPC-kontrakt app↔DB, evidens-join, GDPR/RLS,
  write-data-flow alle verificeret rene. 81/81 jest grøn, tsc rent.
* **Udestår (plan 2, bevidst):** køn-editor i UI (red_set_koen-path findes+testet, intet kort);
  familie/sektioner read-only-visning; entitetslister; generisk record-editor; opret-flow;
  relations/sektion-redigering. Operationelt: seed en `redaktion`-profil (auth.users +
  profiles.rolle='redaktion') for at teste happy-path-writes mod live; manuel e2e på device.

## `levende`-GDPR-cache udledt + RLS-deploy-bug rettet (2026-06-25)
* **Root cause:** `load_daa.R:64` hardkodede `levende=FALSE` på hver person — flaget
  blev aldrig udledt. Alle 963 stod FALSE, inkl. nulevende (fx Johan Martin, id 488,
  f. 1977). Med RLS aktiv ville selv korrekt filter eksponere dem.
* **Regel (bruger):** levende = født inden for seneste 100 år (ift. load-dato) UDEN
  død/begravelse/dødsårsag-fakta og uden `visning_doed`. Fail-closed: ukendt fødselsår
  → FALSE (de udaterede er tidlige aner). Udledt fra **struktureret** fødedato
  (`assertion.date_min/max` via blåstemplet `conclusion`), ikke display-cachen.
* **Backfill (live, committet):** 70 personer → `levende=TRUE`. To uafhængige metoder
  (display-regex + struktureret fakta) konvergerede på præcis 70; risiko-bucket (166 uden
  fødsels/død-fakta) verificeret til 0 levende (alle tidlige aner; edge-case id 940 =
  1785-ægtefælle). `load_daa.R` fået derivations-pass så næste load ikke nulstiller.
* **`db-rls.sql`-bug:** oprettede `anon_read` men droppede ALDRIG den midlertidige
  `dev_anon_read` (USING true). Postgres OR'er permissive politikker → deploy as-is =
  fuld læk (anon ser alle 70 levende). Verificeret via transaktionel sim mod live
  (apply → SET ROLE anon → tæl → ROLLBACK): A=70 lækket, B (dev droppet)=0. Rettet:
  `db-rls.sql` dropper nu `dev_anon_read` på alle tabeller først. Re-sim: 0 lækket,
  893 afdøde + data loader stadig (narrative 550, relation 961, family_member 1205).
* **Deployet mod live (2026-06-25):** `db-rls.sql` kørt via `work/rls_deploy.R`
  (verificer-og-commit). Verificeret som anon: 893 afdøde synlige, 0 levende lækket,
  helper-fn på plads, `dev_anon_read` væk. anon-tier GDPR-lag er nu aktivt i prod.
* **Udestår:** `authenticated`-tier (medlem/forsker ser levende slægtninge m. samtykke)
  — skitse nederst i `db-rls.sql`, bygges når login/profiles er på plads. `media`-tabel
  er deny-all indtil afbildet-gating skrives (tom nu).

## Slægtslinjer navngives — `lineage`-entitet, trin (a) (2026-06-23)
* Linjer levede kun som bart `'I'..'V'`-token på `person_external_id.linje`. Ny entitet
  `lineage(id, source_id, kode, navn, UNIQUE(source_id,kode))` giver dem navne:
  I=Den holstenske linje, II=Linjen Gallentin, III=Den mecklenburgske linje,
  IV=Den lensgrevelige linje af 1767, V=Den grevelige linje af 1673.
* `schema.sql` (source of truth) + idempotent migration i `db-migrations.sql`. Backfill
  er **data-drevet**: `source_id` + `kode` udledes via `SELECT DISTINCT` fra
  `person_external_id` (ingen hardcodet source-id); `ON CONFLICT DO NOTHING` → re-kørbar.
* App (`mobile/`): `load.ts` henter `lineage` (tolerant `.catch(()=>[])` indtil migration
  kørt), `buildAux.ts` bygger `linjeNavn`-map + `navn` på `linjeList`. UI viser navn med
  fallback til `Linje {kode}`: linje-chips (tree), gen-header (VariantC), persondetalje-badge.
* **Trin (b) bevidst udskudt:** adling→ny slægt, forgrening (`gren_af`), eget våben,
  person↔linje m. konfidens. Tabellen er forward-kompatibel — (b) er ren `ALTER ADD` +
  relationer senere. Se `docs/decisions.md` + datamodel-oversigt §5/§9.
* Tests: `buildAux.test.ts` udvidet (navn-map, fallback til null, bagudkompatibilitet);
  8/8 grøn, `tsc --noEmit` ren.
* **Udestår:** migrationen er IKKE kørt mod live-basen endnu (auto-mode blokerede
  produktions-skrivning); runner klar i `/tmp/run_lineage.R`.

## Ægtefælle-rygrad for hele slægten + deterministisk boern (2026-06-17)
* Re-load af hele stamtavlen med ægtefælle-rygrad for HELE slægten (ikke kun nær
  familie): 591 poster → 925 personer (591 hoved + 334 ægtefæller). Backup-dump af
  forrige base gemt (`work/dump_before_reload_*.rds`, 22.702 rækker).
* Loader-fixes: `sp_date()` tåler nu både struktureret (object) og rå string
  partner-datoer (udtræk var inkonsistent: 198 string vs 29 object for fødsel);
  ægtefælle-bio-note flyttet fra person til `family` (så appen viser den);
  begivenheder uden navn skippes + fallback-rolle "deltager".
* **`boern` udledes nu DETERMINISTISK** i `validate.py` (`derive_boern`) — LLM-trinnet
  missede børne-referencer systematisk (Codex fangede 38/123). Regex hærdet mod alle
  fraseringer (plural sønner/døtre, "?"-markør, "5 (7?) børn", bar "børn:", linjebrudt
  range). Fanger 123 ægte, afviser hallucinerede uden tekst-belæg.
* Bugs fundet+fixet: forkerte forældre (dato-linje læst som post-header i ad-hoc patch);
  manglende ægtefælle-info (string-datoer ej parset).
* Undersøgt: 145 kryds-gren-tvetydige boern-links (`boern.linje` = bogens interne
  gren-tæller, IKKE JSON-linje). 97 verificerede fejl, 38 ægte kryds-gren. Era-tie-break
  anbefalet (next-step). Rammer også linje V (fx V-73→V-106).

## App-skive + slægtskabs-UI (2026-06-15/16)
* Minimal Vite/React/Supabase-app der renderer lagdelte evidens-data.
* Relations-visning centreret på en fokus-person (forældre/søskende/ægtefælle/børn),
  klikbar graf-navigation; start på Johan Martin (V-186).
* Viser: lagdelte fakta (vaerdi + dato), dekoration (hvilken · hvornår), fuld narrativ,
  vielsesdato(er) + skilsmisse på ægtefælle-kort, ægtefælle-bio-noter + person-fakta.
* s.å./s.m. ekspanderes i visning via opløst ISO-dato (rå tekst bevaret i basen).
* Midlertidig dev-RLS udvidet til alle læse-tabeller (erstattes af rigtigt RLS-lag).

## DAA-parsere som skills (2026-06-15)
* `/daa-extract` — stamtavle-PDF → evidensmodel. Pipeline: pdftotext → segment.py
  (deterministisk) → LLM-udtræk → blokerende validering → R bulk-load.
* `/daa-presens` — præsensliste (nulevende medlemmer, OCR-tolerant, relations-træ).
* Segmentering håndterer: gren-headere (DEN…LINJE + LINJEN GALLENTIN), per-linje
  løbenr, under-numre (15a/b/c), ?-præfiks (usikkert medlemskab → konfidens).

## Datamodel + load (2026-06-15/16)
* Fuld Reventlow-stamtavle loadet: 591 poster → 934 personer (Sonnet-udtræk).
* Evidenslag på relationer (ikke kun fakta); steder normaliseret til `place`;
  ejendom/org/begivenhed dedupes (get-or-create); ægteskab → familie-fakta.
* Bulk-insert loader (dbAppendTable/COPY): 30+ min, skrøbelig → ~14 sek, pålidelig.
* Indekser på relations-/evidens-opslag. Kontrolleret vokabular (vocab) + V9-validering.
* Forkortelsesnøgle (bogens bagstof) seedet i vocab(scheme='forkortelse').
* Nær families ægtefæller (V-175/186/187/188/199) beriget: fødsel/dåb/død + bio-note.
* erhverv/uddannelse holdt UDE af rygrad (ligger i narrativ/bio-note).

## TNG-analyse (2026-06-15)
* `jr_tng_reventlow.sql` (25k personer) analyseret som senere enrichment-kilde;
  gaps dokumenteret i docs/tng-reventlow-analyse.md (git-ignoreret, levende-data).

## Kendte issues / næste
* Haiku-fuld-broaden af ægtefælle-rygrad FEJLEDE (parallelle agenter clobberede delt
  output-mappe) — ingen data tabt, men ~10% kvote spildt. Genoptag KUN med isolerede
  output-mapper/worktrees + terse agent-output. Se memory parallel-agenter-isoleret-output.
* RLS-lag (rigtigt) mangler — kritisk før multi-bruger pga. nulevende-data.
* Dekorations-nøgle hentes fra anden DAA-udgave (koder bevaret rå).
* ~16% relative datoer uopløst ved udtræk (rå tekst bevaret).

## 2026-07-19 — Mediehåndtering fase 1: filside og fuld CRUD

- Tilføjer redigerbar filside på web og mobile med metadata, rettigheder, publiceringsgate og filstatus.
- Tilføjer `red_opdater_media` og `red_genopret_media`; upload gemmer nu også kunstner og datering.
- Fjernede medier bevares i redaktionens læselag og kan genoprettes, men filtreres fortsat fra lightbox og narrativ-mention-pickere.
- Ingen produktionsmigration er kørt fra dette ændringssæt. Kør `db-migrations.sql`, derefter `db-verify.sql`, `db-verify-media.sql` og til sidst `db-rls.sql` efter runbooken.
