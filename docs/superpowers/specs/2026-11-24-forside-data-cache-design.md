# Færdigpakket forside-data (2026-11-24)

**Status:** design til godkendelse. Spor 4 (caching) i POC-klargøringen til Adelsforeningens bestyrelse, rykket frem
af projektejeren 2026-11-24, fordi forsiden ellers møder bestyrelsen med næsten kun datokort.

## Formål og hvorfor
Forsiden (»Fra Aarbogen«, `web/src/components/feed/FeedStreamView.tsx`) skal vise rigtige kort (portræt, citat,
arkiv, historie) fra første visning og stadig være en ny, tilfældig forside ved hvert besøg.

I dag henter hver visning sine data direkte fra Supabase som gæst:
- biografier: 100+ bid-kald til `public_person_bio_source_versions_v2`, 10-12 s i alt;
- hændelser: bladring over `public_haendelse_feed`; prod 24/11: 8 af 36 kald ramte gæsternes 3 s-loft;
- livsdatoer (`livsdato.ts`), historier (`story.ts`), nævnt-grundlag (`feedGrundlag.ts`).

Første uddeling sker efter `FEED_FOERSTE_UDDELING_FRIST_MS` = 2,5 s. Til den tid er kun livsdatoerne nået frem, så de
første seks kort er datokort, og viste kort skiftes aldrig ud. #459 gjorde hentningen robust (ét genforsøg, delvise
biografier), men ikke hurtig.

**Succes:** en gæst, der åbner forsiden, får portræt-, citat- og historiekort blandt de første seks kort, uden fejlbanner,
og forsiden er forskellig fra besøg til besøg.

## Mål
1. Forsidens langsomme data hentes som **én færdigpakket fil** fra Vercels CDN på under ét sekund.
2. **Tilfældigheden bevares uændret**: filen indeholder data, ikke en rækkefølge. Blandingen sker som i dag i
   browseren (`createFeedStream` med et tilfældigt frø pr. besøg).
3. Filen er **højst cirka en time gammel** (projektejerens valg: »inden for en time eller et døgn«).

## Ikke-mål
- Minimumskrav til forsidens personer (»(Søn) Reventlow«, én post pr. person, nylig døde). Eget spor efter dette.
- Hastighed på personsiden, søgning og stamtræ.
- Mobilappen (dev-only; kan få samme fil senere).
- En »opdatér nu«-knap. Fravalgt; en ændring slår igennem inden for en time.

## Anti-mål (ville være en fiasko, selv om det virker)
- **Filen indeholder noget, en gæst ikke må se** (levende personer, private narrativer, upublicerede tekster).
- **En redaktør retter noget og kan ikke se det**, fordi hun får den gamle fil.
- **Forsiden går i stykker, når filen mangler** (første besøg efter en deploy, Vercel nede): den skal falde tilbage
  til dagens direkte hentning.
- **En ufuldstændig fil ligner en komplet** og bruges som bevis for fravær (falske »Nævnt i Aarbogen«-kort).

## Tilgange (overvejet)
1. **Vercel-funktion bag Vercels CDN (valgt).** En serverløs funktion `web/api/forside-data` samler data som gæst og
   svarer med `Cache-Control: public, s-maxage=3600, stale-while-revalidate=86400`. Vercels CDN gemmer svaret; efter en
   time får næste besøgende stadig den gemte udgave straks, mens en ny bygges i baggrunden. Ingen tidsplan, ingen ny
   hemmelighed, bruger det, projektet allerede har.
2. **Supabase Storage + planlagt job.** Et job (pg_cron + Edge Function) bygger filen og lægger den i en offentlig
   bucket bag Supabases CDN. Fravalgt: flere dele (job, funktion, skrivenøgle til lageret), en hemmelighed med
   skriveadgang, og jobbet kan stoppe uden at nogen opdager det.
3. **Fil bygget ved deploy (statisk asset).** Fravalgt: filen opdateres kun ved ny deploy, så den kræver en planlagt
   deploy (GitHub Actions-minutter er begrænsede, jf. CI-budgettet).

## Design (beslutninger)
- **Samme pipeline, anden transport.** Funktionen henter de samme *rå* svar, som forsidens loadere henter i dag
  (biografiversioner pr. person-række, hændelses-feedet, livsdato-rækker, historie-rækker, nævnt-grundlagets
  subjekt-id'er), og leverer dem uændret. Browseren kører de samme bygge-funktioner som i dag (kanonisering via
  modellens `canonicalIdById`, valg af standardbiografi, `buildHaendelserBy` osv.). Der er altså én sandhed om
  sammenfoldning og valg, og den bor stadig i klienten.
- **Kun gæsteadgang.** Funktionen bruger den offentlige anon-nøgle (samme som hjemmesiden), aldrig service-rollen. RLS
  og de offentlige RPC'er afgør derfor, hvad der kommer med — præcis det, en gæst i dag kan hente. Forsidens
  eksisterende værn (`kunSikkertDoede`) gælder stadig i klienten.
- **Fuldstændighed følger med.** Filen bærer `komplet` pr. del (fx `bios.komplet`, `haendelser.komplet`) og
  `genereret` (tidspunkt). En ufuldstændig del bruges som i #459: vis det, der er, men aldrig som bevis for fravær.
  Et svar, hvor en hel del fejlede, caches ikke (funktionen svarer med fejl / `no-store`), så CDN'et ikke gemmer en dårlig
  fil i en time.
- **Hvem får filen:** gæster (ikke logget ind). En logget-ind bruger (redaktør) bruger dagens direkte hentning, så hun
  ser sine rettelser med det samme.
- **Tilbagefald:** henter browseren ikke filen inden for en kort frist (forslag 3 s) eller er den ugyldig, bruger
  forsiden dagens direkte hentning (inkl. #459's robusthed).
- **Første uddeling:** når filen er kommet, er alle forsidens kilder afgjort, og første uddeling sker straks med fuldt
  data. Fristen på 2,5 s bliver kun aktuel ved tilbagefald.

## Begrænsninger
- Gæsternes `statement_timeout` er 3 s pr. kald, også for funktionen; den skal hente i bidder som klienten (og må gerne
  have højere parallelitet end browserens 3, hvis loggen tåler det).
- Vercel Hobby: funktionens varighed skal sættes op (`maxDuration`, op til 60 s); biografierne tager 10-12 s.
- `web/vercel.json` omskriver alle stier til `index.html`; `/api/` skal undtages.
- Supabase-klienten i `web/src/supabase.ts` læser `import.meta.env`; funktionen kører i Node og skal have klienten
  sendt ind (eller sin egen), så loaderne kan genbruges i begge miljøer.
- Free tier pauser efter 7 dages inaktivitet; et cachet svar lever videre, men en ny generering fejler, mens basen er
  pauset (så serveres den gamle, jf. `stale-while-revalidate`).
- Filens størrelse: ca. 540 kB biografitekst + 180 kB hændelsestekst + metadata; komprimeret anslået 250-400 kB.

## Overladt til bygger
- Filens præcise form (én JSON med en sektion pr. kilde) og versionsfelt, så en gammel fil kan afvises efter en
  deploy, der ændrer formen.
- Om nævnt-grundlaget og historierne skal med i første version, eller kun biografier + hændelser + livsdatoer (de
  langsomme). Mål tiden for hver først.
- Hvordan første besøg efter en deploy undgår at vente (Vercel tømmer CDN'et pr. deploy): tilbagefaldet dækker det;
  en »opvarmning« efter deploy er valgfri.
- Om funktionen skal bruge `getAll`/bladring fra `@daa/core` direkte eller loaderne efter en lille omskrivning, så de
  tager en Supabase-klient som parameter.

## Færdigbevis
- Enhedstests: funktionen (mocket Supabase) leverer de rå svar og `komplet`; et svar med en fejlet del caches ikke;
  klienten bruger filen for gæster, dagens hentning for indloggede og ved tilbagefald; ufuldstændig fil giver intet
  nævnt-grundlag.
- Preview: forsiden indlæst 5 gange efter hinanden — portræt/citat blandt de første seks kort, forskellig rækkefølge
  hver gang; svartid for `/api/forside-data` og `x-vercel-cache: HIT` på 2. kald.
- Prod-log efter merge: antallet af `public_person_bio_source_versions_v2`-kald fra gæster falder fra hundreder pr.
  time til få (én generering pr. time).
- CI: node-jobbet.
