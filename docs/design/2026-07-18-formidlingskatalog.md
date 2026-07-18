# Formidlingskatalog — idéer oven på kildematerialet

**Status:** idékatalog til senere bearbejdning (2026-07-18). Ingen af idéerne er
besluttet eller planlagt — de er råstof: hver idé kan modnes til eget koncept/spec
når den prioriteres.
**Forhold til feed-konceptet:** [`2026-07-18-levende-feed-koncept.md`](2026-07-18-levende-feed-koncept.md)
er det *besluttede* styringsdokument for feed'en og etablerer formidlingslaget
(`haendelse`, `story`, `feed_pin`). Dette katalog er horisonten *rundt om* det:
flere formater der genbruger samme lag og samme kildemateriale. Flere idéer herfra
er bevidst små overbygninger på story-tabellen og feed-motoren.

**Læsevejledning pr. idé:** *Grundlag* = hvilke data i modellen der bærer idéen
(findes de allerede?). *Afhænger af* = hvad der skal stå først. *Indsats* =
lav/mellem/høj (groft, relativt).

---

## A · Evidensmodellen som attraktion

Det mest særegne ved databasen er påstand/konklusion-laget — variation mellem
kilder er *indhold*, ikke støj. Ingen almindelig slægtsdatabase kan lave disse.

### A1 · "Kilderne er uenige"-serien
Kort-/artikelformat der fremlægger en kildeuenighed som lille detektivhistorie:
hvad siger DAA 1884, hvad siger kirkebogen, hvad konkluderede redaktionen — og
hvorfor. Formidler samtidig historisk metode.
- **Grundlag:** findes — `assertion`-rækker med `conclusion.status='omstridt'`/
  `'forældet'`, `citation.citat_tekst`, hver udgave som selvstændig `source`.
  Modstrid er dokumenteret helt ned i det trykte forlæg ("† 18. jan. 1821
  (1. jan. 1820?)").
- **Afhænger af:** intet nyt skema; evt. `story`-tabellen som bærer af den
  redigerede fremstilling (`kategori`/korttype "uenighed").
- **Indsats:** lav (visning + redaktionelt udvalg).

### A2 · "Årbogens egen udvikling"
Følg én person på tværs af udgaverne (1884 → 1939 → 2012…): hvordan voksede,
skrumpede eller ændrede omtalen sig? Fortæller *værkets* historie —
følgesvend-DNA'et. `SammenlignUdgaver`-komponenten i redaktionen er en teknisk
forløber; dette er publikumsudgaven.
- **Grundlag:** findes — `narrative` pr. (person, udgave), `person_external_id`
  pr. udgave, tværudgave-identifikation (jf. `flere-daa-udgaver-roadmap.md`).
- **Afhænger af:** mindst to udgaver loadet for samme personer (1939-loadet).
- **Indsats:** mellem.

### A3 · "Bag om et faktum" (evidens-transparens for publikum)
Tryk på en dato/et faktum i personrapporten → se påstandene, citaterne og
konklusionen bag. Gør den videnskabelige rygrad synlig som feature.
- **Grundlag:** findes — hele evidenslaget; vises i dag kun i redaktionen
  (`fetchPersonEvidence`).
- **Afhænger af:** RLS-gennemgang (publikum læser assertions/citations for
  afdøde) + publikums-UI.
- **Indsats:** mellem.

### A4 · Efterlysninger ("Kan du hjælpe?")
Bogen dokumenterer selv sine huller. Et kort-format: *"Vi kender ikke Sophies
dødsår — ved familien noget?"* Svar går ind ad den eksisterende
`suggestion`-staging. Gør medlemmer til medforskere og skaffer data tilbage.
- **Grundlag:** delvist — `suggestion`-tabellen findes; "kendt hul"-markering pr.
  person/linje er nævnt i datamodel-oversigten §9 men ikke implementeret.
- **Afhænger af:** hul-markering (lille additiv tilføjelse) + moderationsflow i
  redaktionen (konflikt-køen findes).
- **Indsats:** mellem.

---

## B · Serielle og kuraterede formater (overbygning på `story`)

### B1 · Føljetoner
Minihistorier kædet i serier: "C.D.F. Reventlow i fem afsnit", ét kort pr.
dag/uge, "næste afsnit"-mekanik i feed'en (serien fortsætter hvor brugeren slap).
- **Grundlag:** `story`-tabellen (feed-koncept fase 3).
- **Afhænger af:** lille udvidelse: `serie_id` + `raekkefoelge` på `story` (eller
  en `serie`-tabel med titel/ramme).
- **Indsats:** lav (oven på fase 3).

### B2 · Digitale udstillinger
Kuraterede temasamlinger som et museum: "Kvinderne i slægten", "Søofficererne",
"De der udvandrede", "Slægten og enevælden". En udstilling = redaktørvalgt
sekvens af personer/hændelser/medier med en indledende ramme-tekst. Giver
"Historie"-temaets Artikler-punkt (web-nav, i dag "kommer") reelt indhold.
- **Grundlag:** `story` + relationer + media; kuratering er redaktionel.
- **Afhænger af:** fase 3 + en `udstilling`-entitet (titel, ramme, ordnet liste af
  indslag) + visnings-side. Kan genbruge føljeton-mekanikken (B1) — overvej fælles
  "samling"-begreb for B1+B2.
- **Indsats:** mellem.

### B3 · Tidslinjen over Danmarkshistorien
Slægtens daterede hændelser lagt oven på et kurateret kontekstlag af rigshistorie
(svenskekrigene, enevælden, 1848…). "Tidslinje" står allerede som kommer-punkt i
web-nav'en.
- **Grundlag:** `haendelse`-skelettet (fase 2) + rygradsdatoer + `historical_event`;
  kontekstlaget er en lille kurateret liste (kan bo i `historical_event` med kilde).
- **Afhænger af:** fase 2.
- **Indsats:** mellem–høj (tidslinje-UI er sit eget håndværk).

---

## C · Sted og geografi

### C1 · Kortfortællinger (story maps)
Fortalte ruter oven på det eksisterende geo-lag: en udvandringsrejse, et
godsimperiums vækst og opløsning (Bukkehave → Christianssæde), animeret
ejerskifte over tid. Scrolly-telling: teksten driver kortet.
- **Grundlag:** findes delvist — geo-punkter (`fact.sted_id` + `place`), livsrejse-
  kortet, `relation` med perioder for ejerskab.
- **Afhænger af:** `story`-lag for teksterne; et scrolly-telling-view.
- **Indsats:** høj (men genbruger GeoMap-fundamentet).

### C2 · Stedet som indgang (QR + audioguide)
QR-kode på godset/kirkegården → stedets side med tilknyttede personer og
hændelser. Udvidelse: audioguide — "gå-turen på kirkegården" med oplæste
minihistorier ved hvert gravsted (gravsted-som-sted med koordinater er allerede
i modellen).
- **Grundlag:** `place`-hierarkiet inkl. gravsteder, relationer sted↔person,
  deep-links (`/estate/:id` findes; sted-sider "kommer").
- **Afhænger af:** steder-registeret (web-nav "kommer"); audio kræver E1-sporet
  (oplæsning). QR er trivielt når sederne findes.
- **Indsats:** lav (QR→side) / høj (audioguide).

---

## D · Relationer og personalisering

### D1 · "Din vej til…" (personlig vinkling)
Med `meId` sat vinkles ethvert indhold personligt: *"Conrad Reventlow — din
8×tipoldefar"*. Slægtskabsfinderen findes; dette er ren præsentation oven på den.
Plus **personlige anejubilæer**: "i dag for 250 år siden blev din direkte ane
gift" — den stærkeste daglige tilbagevendings-grund, og et oplagt senere
push-format (jf. feed-koncept ○e).
- **Grundlag:** findes — `computeRelationship`, rygradsdatoer; alt klientside
  (ingen server-profil, GDPR-let).
- **Afhænger af:** `daa_me_id`-selv-udpegning færdig (issue #4).
- **Indsats:** lav–mellem.

### D2 · Slægternes netværk
Grafvisning af hvilke slægter man giftede sig ind i, hvornår — magthistorie som
netværk. Bliver for alvor interessant når flere slægter er i basen; god
skalerings-fortælling for foreningen.
- **Grundlag:** `family`/`family_member` + gift-ind-ægtefællers slægtsnavne
  (findes); rigere når flere slægter loades.
- **Afhænger af:** reelt: flere slægter. PoC-udgave mulig nu (Reventlow ↔
  ægtefælleslægter).
- **Indsats:** mellem (grafvisualisering).

### D3 · Anetavle-passet
Genereret, smukt opsat PDF/side med brugerens direkte linje bagud, krydret med
minihistorier undervejs. Print-venligt; oplagt medlemshvervnings-artefakt.
- **Grundlag:** stamtræ + `story` (fase 3).
- **Afhænger af:** `daa_me_id` + fase 3; PDF-/print-rendering.
- **Indsats:** mellem.

---

## E · Objekterne

### E1 · Våbnet forklaret
Blasoneringer oversat til lægmandssprog, felt for felt, og briseringen mellem
linjerne som fortælling ("hvorfor har den grevelige linje af 1673 en anden
hjelm?"). LLM-assisteret førsteudkast + heraldik-kyndig redaktørgodkendelse —
præcis samme flow som "Foreslå historie" (feed-koncept §3.3/§8), blot med
`coat_of_arms` som subjekt.
- **Grundlag:** findes — `coat_of_arms` med blasonering, delte våben, varianter;
  `story` er allerede polymorf på subjekt.
- **Afhænger af:** fase 3 (+ fase 4 for LLM-assist).
- **Indsats:** lav (oven på faserne).

### E2 · Ugens portræt
Maleri-/portrætgalleriet som roterende fremhævning med kunsthistorisk billedtekst
(kunstner, medium, datering, nuværende placering — metadata-felterne er tiltænkt
i modellen). Feed-kortet `medie` er første skridt; dette er den kuraterede
overbygning + evt. egen galleri-side ("Billeder" står som kommer-punkt i nav'en).
- **Grundlag:** `media`/`media_variant` (thumbnails indlæses allerede); rig
  metadata for "tunge" medier er et besluttet princip men tyndt befolket endnu.
- **Afhænger af:** billedmateriale loadet (portræt-/galleridelen af 1939-særudgaven
  m.fl.); rettigheds-afklaring pr. værk.
- **Indsats:** lav–mellem.

### E3 · Artefakt-kort
Segl, dokumenter og breve som "genstands-fortællinger" — museumsformatet én
genstand, én historie. Seglet er allerede tænkt ind i modellen som dokumenterende
artefakt (afbilder våbnet, knyttet til person + dateret dokument).
- **Grundlag:** media/kilde + afbilder-/brugt-af-relationer (modelleret, tyndt
  befolket).
- **Afhænger af:** digitalisering af artefakter; `story` til teksterne.
- **Indsats:** mellem (mest indholdsarbejde).

---

## F · Rytme og distribution (ud af appen)

### F1 · "Ugens brev"
Automatisk komponeret nyhedsbrev: ugens dagens-personer, nye stories, en
uenighed (A1), et portræt (E2). Feed-motoren genbruges 1:1 som kilde — e-mailen
er endnu et "skind" oven på strømmen, ligesom web og mobil.
- **Grundlag:** feed-motoren (fase 1) + story-laget (fase 3).
- **Afhænger af:** udsendelses-infrastruktur (mail-tjeneste, tilmelding/samtykke,
  afmelding) — foreningens medlemskartotek er uden for appens datamodel i dag.
- **Indsats:** mellem.

### F2 · Delekort
Ethvert person- eller historiekort renderet som smukt billede (OG-image) til
deling i familiens gruppechats og ved deep-links. Lav friktion, stor rækkevidde
i målgruppen.
- **Grundlag:** kort-designet + deep-links (`/person/:id` findes).
- **Afhænger af:** server-side/build-time billedrendering (fx edge-funktion eller
  prerender); GDPR-tjek: kun afdøde på delekort.
- **Indsats:** lav–mellem.

### F3 · Årshæftet (print-on-demand)
Årets bedste minihistorier sat op som lille tryksag. Den perfekte cirkelslutning
for en *følgesvend til et trykt værk*: digitalt indhold der vender tilbage til
papiret. Kan også være foreningens årsgave/medlemsfordel.
- **Grundlag:** `story` med publiceringsdatoer (fase 3) + kildefødder.
- **Afhænger af:** fase 3 + sats/print-pipeline (kan starte som genereret PDF).
- **Indsats:** mellem (mest redaktionelt udvalg + opsætning).

---

## G · Leg (med omtanke)

### G1 · Gæt-og-lær
Små quizformater: "Hvilket gods hørte til hvilken linje?", "Ældst eller yngst?",
"Match våbnet til linjen". Genereres deterministisk fra modellen (samme
seed-mønster som feed-motoren). **Doseres varsomt** så arkiv-tonen ikke skrider —
lejlighedsformat frem for fast indslag (julekalender i december er den oplagte
ramme, og kobler til "på denne dag"-mekanikken).
- **Grundlag:** findes — modellen + seeded generering.
- **Afhænger af:** feed-motor fase 1 (kort-infrastruktur); redaktionel smags-dom.
- **Indsats:** lav–mellem.

---

## Prioriteringsbillede (vejledende, ikke besluttet)

| Akse | Idéer | Hvorfor |
|---|---|---|
| **Mest særegne** (kun muligt med denne datamodel) | A1, A2, A4 | Evidenslaget som indhold — differentiator ingen andre slægtsdatabaser har. Dataene findes allerede. |
| **Billigst** (rene overbygninger på feed-koncept fase 1–3) | B1, E1, F2, G1, A1 | Genbruger story-tabel, feed-motor og kort-infrastruktur næsten uden nyt fundament. |
| **Stærkeste tilbagevendings-driver** | D1 | Personlig vinkling + anejubilæer; gated af `daa_me_id` (issue #4). |
| **Størst indholdsafhængighed** (godt, men kræver materiale/flere udgaver) | A2, E2, E3, D2 | Venter naturligt på 1939-loadet, billedmateriale og flere slægter. |
| **Eget infrastruktur-spor** | F1, F3, C1, C2-audio, B3 | Mail, print, scrolly-telling, audio, tidslinje-UI — selvstændige beslutninger. |

**Naturlig bearbejdningsrækkefølge:** når feed-konceptets fase 2–3 står, modnes
først A1 + B1 (næsten gratis), dernæst A4 + D1 (medforsker- og
personaliserings-sporene), og A2 når 1939-loadet giver tvær-udgave-data. Resten
prioriteres derefter — hver idé løftes til eget koncept-/spec-dokument når den
vælges (samme proces som feed-konceptet).
