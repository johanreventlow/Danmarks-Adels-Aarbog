# Levende feed — sociale personposter med billeder (design-spec)

**Dato:** 2026-07-26
**Gren/worktree:** `feat/feed-social-posts` i `.claude/worktrees/feed-social-posts`
**Bygger på:** levende feed fase 1–3 og det eksisterende offentlige medielag
**Implementeringsmodel:** `gpt-5.6-terra`
**Implementeringsplan:** følger separat efter brugerens review af denne spec

## 1. Mål

Web- og mobilfeedet skal føles mere som Threads/Twitter/Instagram uden at foregive at
være et socialt netværk. Personrelaterede feedkort samles i en ensartet poststruktur,
personens offentlige billeder vises i en swipebar billedstribe, og hele den store
postflade åbner personprofilen. Den lille mobile handling `Læs mere` er ikke længere den
nødvendige indgang til profilen.

Feedets genealogiske og redaktionelle karakter bevares. Der tilføjes ikke likes,
kommentarer, reposts, følgere eller andre sociale funktioner.

## 2. Afgrænsning

### I scope

- Fælles visuel postskal for alle `FeedCard`-typer med `personId`.
- Initialemærke, navn, leveår, posttype/dato, bogmærke, typespecifikt indhold og
  valgfri billedstribe.
- Op til fire offentlige billeder pr. personpost.
- Threads-lignende vandret stribe, hvor næste billede titter frem.
- Varieret, men deterministisk billedudvalg mellem forskellige poster om samme person.
- Stor profiltrykflade, selvstændigt billedtryk og eksisterende bogmærkehandling.
- Fuldskærmsvisning med eksisterende titel, kunstner og datering.
- Batchet og tolerant medielæsning uden at omordne feedet.
- Samme funktionelle kontrakt på web og mobil.

### Ikke i scope

- Ny postdetaljeside: en post åbner personprofilen.
- Databaseændringer, migrationer eller nye medie-/story-relationer.
- Redaktionel kurering af præcis hvilke billeder der tilhører den enkelte story.
- Sociale reaktioner eller aktivitetsmålinger.
- Automatisk carousel, video eller lyd.
- Ny publicerings- eller uploadworkflow.
- Slægts-/linjevåben i postheaderen. Headerens identitetsmærke får en udskiftelig grænse,
  men første version bruger initialer.
- En endelig regel mod gentagelser i lange feeds. Første version varierer billederne;
  yderligere dæmpning kan besluttes på baggrund af faktisk brug.

Ikke-personkort som gods, våben, slægt, forbindelser og terminalkort beholder deres
eksisterende særpræg. De presses ikke ind i personpostskallen.

## 3. Godkendte produktbeslutninger

1. Alle personrelaterede kort kan vise personens billeder.
2. Billedstriben viser højst fire billeder pr. post.
3. Flere billeder vises som en vandret Threads-stribe, ikke som mosaik eller
   ét-billede-ad-gangen-pager.
4. Portræt- og `dagensperson`-poster starter altid med det valgte primærportræt.
5. Andre personposter må variere forsidebilledet deterministisk.
6. Headeren bruger initialer. Primærportrættet gentages derfor ikke som en lille avatar.
7. Tryk på header, tekst eller tom postflade åbner personprofilen.
8. Vandret swipe bladrer i billedstriben.
9. Tryk direkte på et billede åbner fuldskærmsvisningen.
10. Bogmærkeknappen er en selvstændig handling.
11. Hvis ingen brugbare billeder kan læses eller signeres, vises tekstposten uændret
    uden tom billedramme.

## 4. Personpostens visuelle struktur

Personposten består i rækkefølge af:

1. **Header**
   - udskifteligt identitetsmærke, i første version personens initialer;
   - personens fulde visningsnavn;
   - leveår, når de findes;
   - posttype og relevant dato/år;
   - eksisterende bogmærkekontrol.
2. **Indhold**
   - korttypens eksisterende faglige indhold: biografi, citat, historie, embede,
     jubilæum eller hændelse;
   - eksisterende kildeangivelse bevares;
   - korttypernes indholdsregler ændres ikke skjult af den fælles skal.
3. **Medier**
   - intet medieområde ved nul brugbare billeder;
   - ét billede fylder medieområdets bredde;
   - to til fire billeder vises vandret, hvert cirka 75–80 % af postbredden, så næste
     billede er synligt i kanten;
   - billedernes proportioner bevares inden for en begrænset højde. Historiske
     dokumenter og portrætter må ikke beskæres aggressivt;
   - titel, kunstner og datering bruges i den eksisterende fuldskærmsvisning og som
     tilgængelig beskrivelse.

Den fælles skal genbruger projektets papir-, typografi- og farvetokens. “Social” betyder
her struktur, rytme, swipe og store trykflader — ikke et fremmed visuelt brand.

## 5. Navigation og gestures

### Web

- Postens ikke-interaktive flade opfører sig som navigation til personprofilen og kan
  nås med tastaturet.
- Enter eller mellemrum på den fokuserede post åbner profilen.
- Billeder og bogmærke er rigtige selvstændige kontroller og stopper propagation.
- Billedstriben bruger vandret overflow og scroll-snap.
- Et vandret scrollforsøg må ikke udløse profilnavigation.

Posten må ikke implementeres som en stor `<button>` med indlejrede knapper. Det ville
give ugyldig interaktiv HTML og dårlig tastaturnavigation. Komponenten skal i stedet
have en semantisk navigationskontrakt omkring en ikke-interaktiv container og eksplicitte
børnekontroller.

### Mobil

- Header, tekst og fri postflade er en stor `Pressable` profilindgang.
- Billedstriben er en vandret swipekomponent med selvstændige billedtryk.
- Swipegestussen vinder over det omgivende profiltryk.
- Bogmærkets eksisterende hit-area og handling bevares.
- Der kører ingen automatisk bevægelse, og reduced-motion respekteres.

## 6. Mediemodel og deterministisk udvælgelse

Der indføres en lille fælles kandidatmedieform med mindst:

- `id`
- primærmarkering
- `slags`
- titel, kunstner og datering
- stabile referencer til platformens medium- og originalressource

En ren fælles udvælgelsesfunktion modtager:

- stabilt `card.id`;
- kanonisk `personId`;
- kortets `kind`;
- personens deduplikerede offentlige medier;
- loftet `4`.

Funktionen:

1. deduplikerer på medie-id og lader `primaer=true` vinde;
2. sorterer input stabilt, så PostgREST-rækkefølge ikke påvirker resultatet;
3. vælger primærportræt med den eksisterende regel
   `primaer → portræt-egnet slags → første brugbare`;
4. låser dette billede først for `portrait` og `dagensperson`;
5. afleder en stabil rotation fra `card.id` og `personId` for øvrige personkort;
6. returnerer højst fire unikke billeder.

Samme post viser dermed samme billeder efter rerender og genstart med samme kort-id.
Forskellige kort om samme person kan begynde forskellige steder i galleriet. Der bruges
ikke `Math.random()` eller UI-tid.

Udvælgelsen ændrer ikke `FeedCard`, score, pins, seen-weights, rytmeregler eller
feedrækkefølge. Den sker efter kortet er valgt og er ren præsentationsberigelse.

## 7. Dataflow

### Fælles grænse

`@daa/feed` forbliver netværks- og app-frit. Pakken kan eje den rene kandidatmedietype,
deduplikering og udvælgelsesfunktion, men ikke Supabase-klienten, signed URLs eller
React-komponenter. Udvælgelsen sker på metadata og stabile ressourcereferencer; først
derefter oversætter platformadapteren de valgte kandidater til `mediumUrl`/`largeUrl`.

Medier er ikke input til `buildFeedOrder`. Sen medieankomst må derfor aldrig genstarte
strømmen eller flytte allerede viste kort.

### Web

Web får en feed-specifik batchlæser:

1. saml de kanoniske person-id'er for den viste side;
2. udvid til kendte `same_som`-medlemmer via modellens eksisterende mapping;
3. hent `afbildet`-relationer i batch;
4. hent de berørte `media`-rækker og `medium`-varianter i batch;
5. deduplikér og udvælg metadata før signering;
6. signér kun valgte `medium`- og `large`-stier i batch;
7. cache resultatet pr. kanonisk person for feedvisningens levetid.

Når næste side appendes, hentes kun manglende personer. Der må ikke opstå ét sæt
Supabase-rundture pr. kort.

### Mobil

Mobilens `Aux.mediaBy` indeholder allerede foldede personmedier, og `RawMedia` er allerede
beriget med `thumb_storage_path` og `medium_storage_path`. Feedet genbruger denne model,
udvælger højst fire medier pr. synlig post og signerer de valgte medium/original-stier
gennem den eksisterende URL-cache.

Offline-seed eller tom `mediaBy` giver almindelige tekstposter.

## 8. Privatliv og fejl

- Det eksisterende feed-GDPR-filter (`kunSikkertDoede`) forbliver eneste indgang til
  personidentificerende kort.
- Medier læses gennem eksisterende RLS på `media`, `relation`, `media_variant` og
  Storage. Klienten må ikke omgå politikker eller anvende privilegerede nøgler.
- Kun rækker, som den aktuelle rolle kan læse, må sendes til URL-signering.
- Signed URL-cache ryddes fortsat ved auth-skift.
- Manglende relationer, varianter, Storage-objekter eller signeringsfejl logges og
  reducerer kun det berørte mediesæt.
- Et enkelt defekt billede filtreres fra; de øvrige billeder må stadig vises.
- En samlet mediefejl giver en tekstpost, ikke en fejlet feedside.
- Ingen ny SQL eller prod-skrivning er nødvendig for denne feature.

Supabase-changelog, aktuelle dokumenter og security advisors skal kontrolleres før en
eventuel afvigelse fra dette design eller en senere schema-/RLS-ændring.

## 9. Komponentgrænser

Den konkrete plan skal holde ansvar adskilt:

- **Ren medieudvælgelse:** typer, stabil rotation, deduplikering og primærregel.
- **Platformenes medieadaptere:** batchlæsning, variantslag og signering.
- **Personpost-identitet:** afleder navn og leveår fra den allerede indlæste model via
  `personId`, så alle personkort får samme header uden at kopiere felterne ind i hver
  `FeedCard`-variant.
- **Personpostskal:** header, typespecifikt body-slot, profilnavigation og bogmærke.
- **Mediestribe:** layout, swipe/scroll, billedtryk og tilgængelighed.
- **Eksisterende lightbox:** genbruges med feedets udvalgte fuldskærmsmedier.
- **Ikke-personkort:** fortsætter gennem deres eksisterende renderere.

Identitetsmærket i headeren modtager en lille præsentationsmodel frem for at kende til
initialberegning. Første adapter leverer initialer. Det gør en senere adapter for
konkret slægts-/linjevåben mulig uden at omskrive personposten.

## 10. Test- og acceptkriterier

### Rene tests

- stabilt resultat for samme kort og mediesæt;
- variation mellem forskellige kort-id'er for samme person;
- højst fire unikke medier;
- `primaer` vinder deduplikering;
- portræt-/dagensperson starter med primærportræt;
- andre personkort kan rotere første billede;
- nul, ét, to, fire og flere end fire medier;
- stabilitet ved forskellig inputrækkefølge.

### Dataadaptere

- folded `same_som`-medier samles på den kanoniske person;
- relationer, medier og varianter læses batchvis;
- kun udvalgte stier signeres;
- medium falder tilbage til original;
- delvise og samlede fejl degraderer til færre eller ingen billeder;
- auth-skift genbruger ikke tidligere signed URLs.

### Web

- personheader/-tekst/-baggrund åbner profilen;
- Enter/mellemrum åbner profilen;
- billedtryk åbner lightbox og ikke profilen;
- bogmærke gemmer og åbner ikke profilen;
- vandret scroll åbner ikke profilen;
- nul billeder giver ingen tom mediebeholder;
- én og flere billeder har korrekt layout og scroll-snap.

### Mobil

- stor postflade åbner profilen;
- `Læs mere` er ikke den nødvendige trykflade;
- billedtryk åbner lightbox;
- swipe åbner ikke profilen;
- bogmærke åbner ikke profilen;
- billeder hentes fra `Aux.mediaBy`, og offline-seed fungerer uden medier.

### Afsluttende porte

- `npm test --workspace packages/feed`
- `npm test --workspace packages/core`
- `npm test --workspace web`
- `npm test --workspace mobile -- --runInBand`
- relevante TypeScript-/lint-porte for ændrede workspaces
- `npm run build` i `web/`
- visuel smoke-test på web og mobil for nul/ét/flere billeder, blandede proportioner,
  horisontal swipe, lightbox og profilnavigation
- `git diff --check`
- scopekontrol: ingen SQL-, migrations- eller redaktionsændringer

## 11. Udgangsbaseline

Det isolerede worktree blev oprettet fra `origin/main` ved `4679953`.

- feed: 120/120 tests grønne
- core: 304/304 tests grønne
- web: 528/528 tests grønne med ikke-hemmelige Supabase-testværdier
- mobil: 399/399 tests grønne; forventede offline-seed-advarsler

Dette er baseline før enhver produktionskode. Implementeringen må først begynde efter
brugerens review af denne spec og en separat, godkendt TDD-plan.
