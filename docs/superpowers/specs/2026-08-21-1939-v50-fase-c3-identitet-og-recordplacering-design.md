# 1939 v50 fase C3 — identitet og placering af sammenlægningssager: design

**Status:** godkendt i brainstorm 2026-08-21. Stopper før databaseændringer;
implementeringsplan følger først efter særskilt godkendelse af denne spec.

**Godkendt tillæg 2026-08-21:** Den særlige identitetslinje har
fail-closed standarden `UAFKLARET`, fordi en eksisterende `samme_som`-kant
fra alias 1021 ellers kan gøre den genererede baseline ugyldig ved G3-gaten.
Recordstandarderne for R40 og R15 er fortsat henholdsvis `TIL 1017` og
`TIL 1021`. En redaktør kan stadig vælge `SAMME 1021 1017`, men det må være
en eksplicit afgørelse, som den friske grafvalidering accepterer.

## Problemet

C0 afgjorde 41 records, men routede syv af dem til `[C3]`, fordi én record
pegede på mere end én eksisterende person. Den klasse kan ikke løses ved en
almindelig C0-kobling: der er mindst to uafhængige spørgsmål.

1. Repræsenterer personrækkerne samme fysiske menneske?
2. Hvilken person eller hvilken record-revision tilhører den enkelte
   kilderecord?

At svare ja på det første spørgsmål bestemmer ikke automatisk det andet.
Projektets identitetsmodel er **LINK, ikke merge**: `samme_som` bevarer begge
personrækker og deres proveniens, mens læsefladerne kan kollapse dem. En
kilderecord kan samtidig placeres på én bestemt person uden at personerne
linkes. Omvendt kan to personer være `samme_som`, mens to forskellige
kilderecords fortsat hører til hver sin rå personrække.

C0's efterkørsel viste desuden en konkret grænsefejl. R40 består af afsnit A),
mens R15 består af afsnit B). Begge afsnit lå i person 1017's gamle narrativ,
og person 1021 havde kun de sidste 57 tegn af B), begyndende midt i det
orddelte »Revent- low«. R40 blev derfor taget ud af C0-apply og skal behandles
sammen med R15 i C3. Den korrekte datamodel kan ikke udledes af mærket `[C3]`
alene; den kræver en eksplicit menneskeafgørelse på begge akser.

## Scope

Denne første C3-fase omfatter præcis:

- de **syv** records, som den godkendte C0-beslutningsfil mærker `[C3]`; og
- **R40** som låst ledsager til C3-recorden **R15** i sagen 1017/1021.

Det giver otte records i reviewet. R15/R40 er én særlig, sammenhængende sag;
de øvrige seks `[C3]`-records er seks selvstændige sager.

De øvrige 11 af de 12 kendte narrativer, der begynder med lille bogstav,
indgår **ikke**. De er et separat undersøgelses- og beslutningsspor. Et
lowercase-start-signal er ikke i sig selv evidens for identitet, recorddeling
eller en skrivehandling.

Fasen slutter ved et valideret, hashbundet beslutnings-JSON. Den indeholder
ingen databasewriter, intet apply-manifest, ingen RPC-kald og ingen
produktionsautorisation. En senere apply-fase skal have sin egen spec,
rehearsal, backup, manifest og eksplicitte GO.

## Datagrundlag

C3 udledes deterministisk af de allerede godkendte C0-artefakter; den åbner
ikke en ny, fri kandidatjagt.

### Frosne input

Selektionsbyggeren modtager de eksakte bytes af:

1. C0's kandidat-JSON; og
2. C0's beslutnings-JSON.

C0-beslutnings-JSON'et binder ikke selv kandidatfilens hash. C3 må derfor ikke
antage, at et filnavn eller en versionsbetegnelse beviser sammenhængen. C3's
eget selektionsartefakt beregner og bærer SHA-256 for **begge** filer og
verificerer dem igen i alle efterfølgende trin.

Selektionsbyggeren skal afvise hele kørslen, medmindre:

- beslutningsfilen indeholder præcis syv `[C3]`-beslutninger;
- hver beslutningsnøgle findes præcis én gang i kandidatfilen;
- hver valgt kandidat har C0-klassen `sammenlaegning`;
- der ikke findes manglende, ekstra eller duplikerede sagsnøgler; og
- C0's deterministiske RID-tildeling fortsat udleder R15 og R40 som de
  forventede records.

R15 skal være blandt de syv `[C3]`-records. R40 tilføjes som ledsager, ikke som
en ottende fri C3-kandidat. Person 1017, person 1021 og R15/R40-forholdet er en
låst kontrakt; afvigelse er terminal drift, ikke en anledning til at springe
sagen over.

### Frisk, read-only tilstand

Drift-prone databaseforhold genmåles gennem en ny read-only R-eksportør. Den
eksporterer kun strukturelle oplysninger, der er nødvendige for at validere
en senere beslutning, eksempelvis:

- person-id og staged-status;
- narrative-id, SHA-256, `private`, side og bindingstilstand;
- eksisterende `samme_som`-komponent og relevante konfliktmarkører; og
- databaseidentitet, så et udtræk fra en forkert database afvises.

Eksportøren medtager ingen narrativ prosa. Den må ikke genbruge eller ændre
C0F-eksportøren, hvis det udvider C0F's kontrakt; C3 får sin egen, lille
eksportør eller fælles read-only helper.

Alle fem `PGDATABASE`, `PGHOST`, `PGPORT`, `PGUSER` og `PGPASSWORD` sættes
samlet eller slet ikke. `--expect-database-name` er obligatorisk ved den
dokumenterede kørsel. Eksporten er input til reviewet og hashbindes som eksakte
bytes.

## To uafhængige beslutningsakser

Hver almindelig C3-sag kræver én identitetsbeslutning og én beslutning om
kilderecorden. En beslutning på den ene akse må aldrig udfylde eller
autorisere den anden implicit.

### Identitet

Lovlige semantiske udfald:

| Token | Betydning |
|---|---|
| `SAMME <alias> <canonical>` | Personerne er samme menneske; senere apply kan foreslå en reversibel `samme_som`-relation. |
| `FORSKELLIGE` | Kandidaterne skal forblive separate personer. |
| `UAFKLARET` | Evidensen er utilstrækkelig; ingen identitetsmutation autoriseres. |

Aliasretningen er en del af beslutningen og valideres mod den låste sag.
`SAMME` må ikke være et selv-link, pege på ukendte personer eller skabe en
konflikt med den frisk målte `samme_som`-graf.

### Kilderecord

Lovlige semantiske udfald:

| Token | Betydning |
|---|---|
| `TIL <person-id>` | Den eksisterende record tilhører én eksisterende person; dette kræver ikke personlink. |
| `REVISION <split_into\|merged_from\|replaced_by>` | Forholdet kræver en ny logisk record og et append-only `source_record_revision_event`; det er ikke en simpel placering. |
| `INGEN_PUBLIKATION` | Recorden må ikke publiceres som personrecord på det foreliggende grundlag. |
| `UAFKLARET` | Evidensen er utilstrækkelig; ingen recordmutation autoriseres. |

`REVISION` er alene en menneskelig klassifikation i denne fase. En senere fase
skal specificere retning, involverede record-id'er, minting og proposal/
acceptance-forløb i overensstemmelse med source-anchor-kontrakten.

### Den låste 1017/1021-sag

Reviewet viser tre adskilte beslutningslinjer, som redaktøren skal tage
stilling til:

1. identitet: `UAFKLARET` som fail-closed standard;
2. R40/A: `TIL 1017`; og
3. R15/B: `TIL 1021`.

Den autoritative beslutningssekvens bærer samtidig den foretrukne
`SAMME`-retning som strukturel metadata: alias 1021 → canonical 1017. Den
metadata ændrer ikke baseline-tokenet. Den bruges kun til at bevare den
godkendte retning, hvis redaktøren eksplicit skifter identitetsvalget fra
`UAFKLARET` til `SAMME`.

R40 og R15 er allerede to forskellige kilderecords. Derfor foreslås ingen
source-record revision alene for at holde A) og B) adskilt. Reviewet må ikke
omskrive denne tredeling til én samlet »merge«-handling.

## Lokalt menneskereview

Reviewgeneratoren bygger ét deterministisk token-pr-linje-ark i `work/`.
Arket indeholder de otte records og den lokale prosa, der er nødvendig for en
menneskelig afgørelse. `work/` er model-blind og gitignoreret: filen må aldrig
committes, og dens prosa må ikke kopieres til terminaloutput, tests,
beslutnings-JSON eller dokumentation.

De seks almindelige C3-sager har hver to beslutningslinjer: identitet og
kilderecord. 1017/1021-sagen har de tre låste linjer ovenfor. Det giver
**15 beslutningslinjer** i en fuld reviewfil.

Renderer og parser bruger én fælles autoritativ sags- og linjerækkefølge.
Rækkefølgen må ikke implementeres parallelt to steder. Redaktøren må kun ændre
beslutningstokens; overskrifter, ID'er, rækkefølge og kontekst er låst.

Generatorens CLI udskriver kun sikre metadata som antal og SHA-256, aldrig
narrativ tekst.

## Fail-closed konvertering

Konverteren læser reviewarket positionsstrengt og producerer struktureret JSON.
Den afviser hele filen ved:

- ændret, manglende eller ekstra overskrift eller kontekst;
- ændrede, manglende, ekstra, duplikerede eller omordnede sager;
- ukendte tokens, relationstyper eller person-id'er;
- selv-links, ulovlig aliasretning eller konflikt med aktuel
  `samme_som`-komponent;
- modstridende beslutninger inden for samme sag;
- privat record eller en bindingstilstand, som kontrakten ikke tillader;
- mismatch i C0-kandidathash, C0-beslutningshash, tilstandseksporthash eller
  reviewarkets eksakte hash; eller
- enhver afvigelse fra `7 + 1`-scope eller 1017/1021-kontrakten.

Der findes ingen stille filtrering, best effort eller delvis outputfil.
Fejlteksten identificerer sagsnøglen og forventet/faktisk værdi uden at lække
prosa fra `work/`.

`UAFKLARET` er derimod et gyldigt, eksplicit fail-closed resultat. Det bevarer
sagen i beslutningsartefaktet uden at autorisere nogen senere mutation.

## Beslutningsartefakt

Det validerede JSON indeholder kun:

- et versionsmærket skema;
- den deterministiske sagsrækkefølge og strukturerede beslutninger;
- kontroltal for syv C3-records, én ledsager og 15 beslutningslinjer; og
- eksakte SHA-256-hashes for C0-kandidat-JSON, C0-beslutnings-JSON,
  read-only-tilstandseksporten og det udfyldte reviewark.

Ingen narrativ tekst kopieres ud af `work/`. Beslutningsartefaktet er ikke et
apply-manifest og må ikke fortolkes som GO. Kun fuldt afklarede handlinger kan
senere føres videre som kandidater til en særskilt apply-fase.

## Komponenter

Implementeringen opdeles i fire små trin med snævre kontrakter:

1. **C3-selektionsbygger** — hashbinder C0-inputtene, udleder de syv `[C3]`
   og tilføjer den låste R40-ledsager.
2. **Read-only R-eksportør** — måler kun aktuel strukturel DB-tilstand og
   databaseidentitet.
3. **Reviewgenerator** — kombinerer de lokale input i processen og renderer
   gennem én fælles autoritativ sekvens.
4. **Beslutningskonverter** — validerer hele arket og skriver det hashbundne,
   tekstfri JSON.

Ingen af komponenterne må skrive til databasen.

## Verifikation

Implementeringen skal udvikles og verificeres med `/usr/bin/python3` 3.9.6.
Produktionskode og tests skal være Python 3.9-kompatible.

Testpakken skal mindst bevise:

- golden review-bytes og én fælles renderer/parser-rækkefølge;
- præcis syv routede records plus R40 og den særlige 1017/1021-kontrakt;
- afvisning af manglende, ekstra, duplikerede og omordnede sager;
- afvisning når et C0-input eller DB-eksporten ændres efter reviewgenerering;
- alle lovlige tokens samt ulovlige kombinationer;
- afvisning af ukendte person-id'er, selv-links og forkert aliasretning;
- afvisning af private eller allerede aktivt bundne records, hvor dette
  strider mod den låste sag;
- afvisning af konflikt med eksisterende `samme_som`-komponenter;
- at `UAFKLARET` accepteres uden at autorisere mutation;
- at fejl ikke efterlader en delvis beslutningsfil; og
- at fasen ikke indeholder apply-, RPC- eller anden skrivevej.

Fokuserede tests køres først; derefter den fulde relevante Python-suite og de
relevante read-only R-tests. Resultaterne rapporteres hver for sig.

## Afgrænsning og næste gate

Denne spec beslutter reviewkontrakten, ikke udfaldet af de otte records. Den
beslutter heller ikke:

- hvordan en `samme_som`-relation eller recordplacering skrives;
- hvordan nye logiske records mintes ved `REVISION`;
- backup, rehearsal, rollback eller produktions-GO;
- de øvrige 11 lowercase-start-sager;
- de 16 `[NY]`-records; eller
- publicering af staged personer.

Efter denne spec er særskilt godkendt, kan der skrives en implementeringsplan
for read-only reviewfasen. Først når reviewet senere er gennemført og
beslutnings-JSON'et er valideret, kan en ny brainstorm afgøre en eventuel
apply-fase.
