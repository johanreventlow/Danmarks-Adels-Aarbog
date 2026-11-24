# Minimumskrav til personer på forsiden — kort design

Dato: 2026-11-24. Godkendt af projektejeren i samtale (udkast + to afklaringer samme dag).

## Hvorfor

Forsiden viste »(Søn) Reventlow« to gange — et barn, der døde samme dag, som det blev født. Forsiden skal vise
personer, der er værd at åbne, og ikke den samme person flere gange. POC'en skal vises for Adelsforeningens bestyrelse.

## Krav (projektejerens ja 24/11 til alle)

En person må kun optræde i et personkort på forsiden, når alle disse holder:

1. **Sikkert død** — findes allerede (`levende.ts`, `kunSikkertDoede`).
2. **Rigtigt navn** — ikke et rollenavn i parentes (»(Søn)«, »(Datter)«, »(Barn)«) og ikke »N. N.«. Målt i prod:
   3 personer (»(Søn)«, »N. N. von Lützow«, »N. N. Lunov eller Anne Juel af Aabjærg«). »(Anna?) von Ahlefeldt« er et
   rigtigt navn med usikkerhed og bliver.
3. **Blev voksen** — ikke kendt død før 15 år (fødsels- og dødsår kendt), og dødsteksten er ikke »ung«/»lille«/»spæd«
   (36 i prod). Ukendt alder udelukker ikke: mange personer fra 1500-1600-tallet mangler fødselsår.
4. **Har noget at fortælle** — mindst én af: offentlig biografi på mindst 200 tegn, titel, embede, hændelse, billede.
5. **Død for mindst 25 år siden** — dødsår (spændets øvre år, hvis bogen giver et spænd) højst i år − 25. Uden dødsår:
   født for mindst 145 år siden (levende-grænsen 120 + 25).

Og for forsiden som helhed:

6. **Højst ét kort pr. person.** Født og død i samme måned giver ét kort, ikke to; et portræt og et »I denne måned«-kort
   om samme person giver ét.
7. **»Nævnt i Aarbogen«-kortene slås fra** (projektejeren 24/11: »Slå dem fra«). Korttypen handler netop om personer
   uden indhold og strider mod krav 4. Koden bliver; typen lægges i `TEMP_DISABLED_KINDS`, så den kan tændes igen.
8. **Billeder tæller først med spor 2** (projektejeren 24/11). Motoren får krav 4's billed-gren som valgfrit input
   (`personerMedBillede`); web sender det ikke endnu. I dag har 9 personer i prod et billede.

Personsiden er uændret: alle offentlige personer kan stadig åbnes.

## Tilgange

- **A. Valgfrit flag i feed-motoren (valgt).** `FeedInputs.forsideKrav?: boolean`. Når det er sat, udtyndes den
  sikkert-døde model yderligere til forsideværdige personer (samme kontrolpunkt som `kunSikkertDoede`), og efter
  prioritetssorteringen beholdes kun første kort pr. person. Web og mobil sætter flaget. Uden flaget er motoren
  uændret, så ekvivalenstesten mod `orderReference.ts` (som aldrig må rettes) stadig beviser trækningsløkken.
- B. Filtrering i web/mobil før motoren — duplikerer reglerne i to apps og kan ikke lave »ét kort pr. person«, fordi
  kortene bygges inde i motoren. Fravalgt.
- C. Filtrering i databasen (et »forsideværdig«-felt) — kræver prod-DDL og skal holdes i takt med konklusioner. Fravalgt.

## Mine valg (kan rettes)

- Krav 6 virker på den prioritetssorterede pulje, før trækningen: hvilket af en persons kort der vises, afgøres af
  samme tilfældighed som resten (ny forside pr. besøg). Personer i fastgjorte kort (redaktørens pin) og dagens person
  er allerede brugt, så deres øvrige kort falder fra.
- Krav 4's »hændelse« = mindst én hændelse uden rygrad i `haendelserBy` (prod: 670 personer; med rygrad 764). En
  rygrad-hændelse genfortæller fødsel/vielse og bliver aldrig selv et kort.
- Navnereglen ser på navnets start: `^\(\s*(søn|datter|barn|dreng|pige)\s*\)` og `^N\.\s?N\.`, uden hensyn til
  store/små bogstaver.
- Mobilen får reglerne gratis (samme motor). Mobilens model mangler dødsteksten, så dér gælder kun alderen.
- »Registeret«-kortets tal (personer uden eget kort) tæller stadig alle personer i modellen.

## Uden for

- Billeder som indhold (spor 2). Bogplacering (§) er allerede fjernet (#458).
