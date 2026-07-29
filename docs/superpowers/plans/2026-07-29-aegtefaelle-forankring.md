# Ægtefælle-forankring — plan

**Dato:** 2026-07-29 · **Status:** plan, ikke påbegyndt
**Formål:** gøre de 627 gift-ind-ægtefæller redigerbare i OCR-kvalitetsarket.

## Problemet i én sætning

En rettelse skal kunne pege på **hvor i bogen** den hører til; indgiftede ægtefæller har ikke et
eget opslag at pege på, kun en omtale inde i deres partners.

`red_ret_ocr_felt` forankrer på `(source.import_key, person_external_id.record_key)`. Ægtefæller har
slet ingen `person_external_id`-række, så RPC'en har intet anker og afviser med `ingen_importanker`.
Det er 627 af 1733 personer — **36 % af korpus**, og hele 66 % af det arket ikke kan røre.

## Målt grundlag (2026-07-29, mod prod)

| | |
|---|---|
| Familier i alt | 664 |
| — begge parter har bogpost | 10 (slægtninge gift med hinanden) |
| — **præcis én part indgift** | **627** |
| — **begge parter uden bogpost** | **0** |
| — kun én part registreret | 27 |

**Ingen union mangler bogpost på begge sider.** Det er ikke et held: bogen er en slægtsbog, så
mindst én part er altid slægtsmedlem med eget opslag. Skulle tilfældet opstå, er det en **datafejl**
— ikke et tilfælde planen skal håndtere. Det bør derfor være en assert, ikke en gren i koden.

Alle 627 ægtefæller optræder i **præcis én** union (0 med flere). Ankerpersonen kan derimod have
flere ægteskaber:

| Ankerpersoner (med bogpost, optræder som partner) | 562 |
|---|---|
| gift én gang | 473 |
| gift to gange | 70 |
| gift 3+ gange | 19 (flest: 5) |
| **ægtefæller der derfor kræver et ægteskabs-indeks** | **164** |

## Nøglens form

```
record_key = <ankerpersonens record_key> + ':' + <ægteskabsnummer>
```

For 463 af de 627 er ægteskabsnummeret altid 1 og kunne udelades — men det gør nøglen uensartet.
Behold det altid; ensartethed er mere værd end kortere nøgler.

## Den reelle udfordring: er ægteskabsnummeret stabilt?

`family_member.ordinal` findes allerede og bærer ægteskabsnummeret:

| | |
|---|---|
| `partner`-rækker | 1301 |
| med `ordinal` | 1281 |
| **uden `ordinal`** | **20** |
| værdier | 1–4 |

Men det er **ikke entydigt pr. ankerperson**:

| Ankerpersoner med flere ægteskaber | 89 |
|---|---|
| entydige ordinaler | 79 |
| **kolliderer** (to unioner med samme eller manglende ordinal) | **10** |

**De 10 kollisioner skal løses før `ordinal` kan bruges som nøgle.** En nøgle der peger på to
rækker er værre end ingen nøgle: rettelsen ville lande vilkårligt.

Dette er planens egentlige arbejde. Resten er mekanik.

## Fælden der skal undgås

`person_external_id.linje` **SKAL være NULL** for indgiftede ægtefæller.

`regen_person_visning()` udleder `visning_efternavn` af linje-medlemskab og påhæfter slægtsnavnet.
Får en indgift hustru en linje, kommer hun til at hedde *Marie Elisabeth Reventlow* — men hun hed
Blome. Hun blev gift ind i slægten; hun tilhører den ikke.

Feltet `linje` og feltet `record_key` bor i samme tabel og udfyldes normalt sammen. Det er præcis
derfor det er let at ramme forkert.

**Verifikation:** korpus-diff på `visning_efternavn` og `visning_fuldt_navn` for alle personer før
og efter. Forventet resultat: **0 forskelle**. Samme disciplin som slægts-rod-migrationen, hvor den
fangede at cachen ikke blev rørt.

## Rækkefølge

1. **Opgør de 10 ordinal-kollisioner** og afgør hver enkelt mod bogen. Uden dette kan nøglen ikke
   sættes. Sandsynlig årsag: to unioner oprettet for samme person hvor bogen kun beskriver ét
   ægteskab — jf. de tidligere "spøgelses-union"-fund. Nogle af dem kan vise sig at være
   dataoprydning frem for nummerering.
2. **Fyld de 20 manglende `ordinal`** ud fra bogens rækkefølge.
3. **Backfill `record_key`** for de 627 — `linje` NULL, `nr` NULL.
4. **Verificér:** korpus-diff 0 forskelle · `red_person_grid` viser 627 flere redigerbare ·
   `get_advisors(security)` uændret.

**Gevinst:** 591 → 1218 redigerbare (34 % → 70 %).

## Afgrænsning

- **1939-ægtefæller (296 af de 627) bliver stadig blokerede.** Deres ankerperson er en
  1939-hovedpost, som selv mangler `record_key` — se `docs/decisions.md` → "1939-posternes
  permanente løbenummer". Denne plan gør dem **klar**; de bliver først redigerbare når 1939 får
  identitet. Reelt frigiver planen alene **331 personer** (2018-20's ægtefæller).
- De 27 unioner med kun én registreret part er ikke omfattet — de har ingen ægtefælle at forankre.
- De 10 familier hvor begge parter har bogpost har allerede hver sit anker og skal ikke røres.

## Åbne forbehold

- Om `ordinal` er stabil på tværs af en **genindlæsning** er ikke undersøgt. Tildeles den af
  loaderen ud fra rækkefølgen i artefaktet, arver nøglen samme skrøbelighed som 1939's løbenumre.
  Det skal afklares før backfill — ellers bygger vi det problem vi netop har besluttet at undgå.
- Antallet af kollisioner (10) er målt på det nuværende korpus. Det ændrer sig hvis flere
  spøgelses-unioner ryddes op undervejs.
