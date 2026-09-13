# Dagsværk 4.3b — første modelkald mod rigtige data, bundt 1

**Kørt:** 2026-09-12/13. **Grundlag:** plan 4.3b, spec §6.5.
**Manifest:** `56a57a56222951409d832771e3eeceb90ad270a2a93b1076a231cc1ea7fcf248`
(projektejerens GO). **Ledger:** `e41348bd6f5abed4…`, 591 records / 488 eligible.
**Profil** daa-2018-20-v1 v1.3.0, **prompt** `d46cda80177cf3b6…`, **model**
`gpt-5.6-terra`.

Første gang ægte DAA-prosa er sendt til en model i dette projekt.

## Kort svar

**Modellen kan læse bogen.** Alle fem tærskler er bestået, de fleste med god
margin. Men to fund, som ingen tærskel fanger, betyder mere for spørgsmålet om,
hvorvidt laget bærer — se »Hvad tallene ikke fanger«.

## Tallene

Fem poster, 41 claims. Bedømt af projektejeren; binding og ordrethed forudfyldt
maskinelt.

| Mål | Resultat | Tærskel | |
| --- | ---: | ---: | --- |
| Præcision — sand ifølge teksten | 40/41 = **98 %** | 90 % | ✅ |
| Klausulbinding — citerer rigtige klausul | 41/41 = **100 %** | 90 % | ✅ |
| Ordrethed — datoer gengivet ordret | 9/9 = **100 %** | 95 % | ✅ |
| Dækning — intet oversprunget noteret | **100 %** | 60 % | ✅ |
| Brugbarhed — poster m. mindst ét korrekt claim | **4/4** biografiske | 10/10 | ✅ (delvist) |

Forbrug: ~17.700 input-tokens pr. post; 88.376 for bundtet.

| Post | Klausuler | Claims | |
| --- | ---: | ---: | --- |
| I-29 | 2 | 0 | henvisning, ikke biografi — se nedenfor |
| I-100 | 1 | 4 | |
| I-112 | 3 | 5 | |
| I-11 | 3 | 7 | fejlede først; se »Claim-niveau« |
| IV-19 | 10 | 25 | |

### Ordrethedsmålet blev først målt forkert

Den maskinelle forudfyldning tjekkede, om **alle** værdier stod ordret i
klausulen, og gav 28/34. Men planens nævner er »claims m. ordret krav«, og det er
datoprædikaterne. De seks afvigelser var `person.publication`, `person.office` og
`person.education`, hvor modellen med rette har skåret en titel ud af en længere
sætning. Med den rigtige nævner: **9 af 9 datoer ordret**.

## Hvad tallene ikke fanger

Det er her, dagsværkets egentlige udbytte ligger.

### 1. Modellen opfandt en præcision, kilden ikke har

I-11 fik **to** dødsclaims: `† 1342/1353` — det tvetydige spænd, bogen faktisk
skriver — og `død 1353 (23. april)`, som **vælger** det ene år og tilføjer en
dato. Det andet er markeret usandt og er dagsværkets eneste præcisionsfejl.

Fejlen er værre, end tallet antyder. Prompten forbyder udtrykkeligt at udlede, og
invariant 5 findes netop for at bære fuzzy datoer som `(date_min, date_max)`.
Et claim, der ser **mere** præcist ud end kilden, er farligere end et, der ser
forkert ud: det ligner kvalitet og bliver ikke fanget af en redaktør, der ikke
har siden foran sig.

### 2. Halvdelen af relations-claimene identificerer ingen

Fire relations-claims, hvoraf **to** ikke peger på nogen:

| | værdi |
| --- | --- |
| `relation.marriage` | `NN.` |
| `relation.child` | `4 sønner` |

Begge er **sande** — bogen siger netop det — og begge er formelt gyldige, fordi
kontrakten kun kræver et objekt med en ordret `raw`. Men »4 sønner« er et
**antal**, ikke et barn, og `NN.` er en ukendt hustru. Som relationer er de
ubrugelige: der er ingen modpart at binde til.

Det er en hul i valideringen, ikke i modellen. Kontrakten kontrollerer **form**,
ikke om et relations-claim udpeger nogen. Skal `relation.*` kunne bære promotion,
må enten kontrakten kræve en identificerbar modpart, eller også må denne slags
klassificeres som noget andet end en relation — fx et `person.*`-faktum om antal
børn.

### 3. Nogle poster er henvisninger, ikke biografier

I-29 gav nul claims. Projektejeren vurderede, at posten er en **henvisning** til
en person, ikke en biografi, og databasen bekræfter det: 50 tegn, en
»se«-henvisning, intet årstal, intet `f.`/`d.`.

Modellens tavshed var altså **korrekt tilbageholdenhed**, ikke en udeladelse.
Bundt 2 gav en post mere af samme slags: III-104, 70 tegn med »se«-henvisning,
også nul claims.

**Hvor mange der findes, er ikke afklaret.** En første måling sagde 38, men den
talte »kort **eller** uden årstal«, hvilket er noget andet. Præcist målt har kun
**3 af de 591** en eksplicit »se«-henvisning — og to af dem er netop I-29 og
III-104, som udvalget tilfældigvis ramte. Til gengæld er **96 poster under 80
tegn**, og de giver næppe meget uanset.

Et filter før modelkaldet er derfor stadig værd at overveje, men gevinsten er
mindre end først antaget, og signalet skal findes bedre end »se«.

Brugbarhedsmålet er opgjort mod de **biografiske** poster, ikke mod henvisningerne.

### 4. En segmenteringsfejl, som ikke er modellens

I-11's klausuler er 1.958, **3** og 410 tegn. En klausul på tre tegn er ikke en
meningsbærende enhed. Det er 4.1b's motor, ikke udtrækket, og det er ikke
undersøgt her.

## Claim-niveau afvisning: en beslutning, kørslen fremtvang

I-11 fejlede i første omgang med `validation_failed`: modellen sendte
`person.name` med et objekt, hvor prædikatet kræver en streng. Ét ugyldigt claim
ud af syv fældede hele posten og dens **seks korrekte** claims.

Fejlen var ikke systematisk — alle 34 øvrige claims havde korrekt værdiform, og
ved genkørsel kom **alle syv igennem uden afvisninger**. Det er altså modellens
variabilitet, ikke en misforstået prompt, og man kan ikke skrive sig ud af en fejl,
der kun sker nogle gange.

Projektejeren afgjorde derfor, at et ugyldigt claim kun fælder sig selv. Posten
markeres `delvis`, og antallet af afviste står i logget. Sikkerheden er uændret —
et afvist claim lagres aldrig — men ved den observerede fejlrate ville omtrent
hver tredje rige post ellers gå tabt af ét forkert felt.

## Metode og efterprøvelighed

- Hvert kald kørte bag Seatbelt-gaten med adgangstesten bestået **umiddelbart
  før**, og gennem eligibility-værnet, som slår hver record op i ledgeren.
- Bedømmelsen foregik i et privat `0600`-ark uden for repoet med klausultekst og
  claims side om side; kun domme og tal er gengivet her.
  Ark-hash: `a128f026eaa0ebcb…` (bundt 1) og `ea6f0776c4283df7…` (I-11).
- **Ingen claim-værdier fra biografier er gengivet i denne rapport** ud over de
  fire, der udgør selve fundene, og som ikke rummer personoplysninger om levende.

## Status og næste skridt

Bundt 1 er **grønt på alle fem tærskler**.

**Bundt 2 er kørt** (`III-104, I-101, I-21, I-120, IV-34`): 5/5 dækket, heraf én
`delvis`, 45 claims, 87.464 input-tokens. IV-34 er den første post, hvor
claim-niveau afvisning faktisk trådte i kraft — nogle claims kom igennem, resten
blev afvist, og posten gik ikke tabt. Bedømmelsen af bundt 2 udestår, og de
samlede tal for alle ti poster skrives, når den foreligger.

Fundene i afsnit 1-3 hører under alle omstændigheder til 4.4's ingest: et
`relation.*`-claim uden modpart bør ikke kunne blive en `interpretation_proposal`,
og et claim, der er mere præcist end kilden, bør ikke kunne promoveres.
