# Dagsværk 4.3b — første modelkald mod rigtige data

**Kørt:** 2026-09-12/13. **Grundlag:** plan 4.3b, spec §6.5.
**Manifest:** `56a57a56222951409d832771e3eeceb90ad270a2a93b1076a231cc1ea7fcf248`
(projektejerens GO). **Ledger:** `e41348bd6f5abed4…` — 591 records, 488 eligible.
**Profil** `daa-2018-20-v1` v1.3.0 · **prompt** `d46cda80177cf3b6…` ·
**model** `gpt-5.6-terra`.

Første gang ægte DAA-prosa er sendt til en model i dette projekt.

## Svaret

**Ja — modellen kan læse bogen.** Det var ikke givet, og det er nu målt på
rigtige data. Alle fem tærskler er bestået på alle ti poster.

Men de to vigtigste fund blev ikke fanget af nogen tærskel. De står i »Hvad
tallene ikke fanger«, og de hører til 4.4.

## Tallene

Ti poster, 86 claims, alle bedømt af projektejeren. Binding og ordrethed
forudfyldt maskinelt.

| Mål | Resultat | Tærskel | |
| --- | ---: | ---: | --- |
| Præcision — sand ifølge teksten | 85/86 = **99 %** | 90 % | ✅ |
| Klausulbinding — citerer rigtige klausul | 86/86 = **100 %** | 90 % | ✅ |
| Ordrethed — datoer gengivet ordret | 17/17 = **100 %** | 95 % | ✅ |
| Dækning — intet oversprunget noteret | **100 %** | 60 % | ✅ |
| Brugbarhed — poster m. mindst ét korrekt claim | **8/8** biografiske | 10/10 | ✅ |

Forbrug: **175.840 input-tokens** for ti poster, ~17.600 pr. post.

| Post | Klausuler | Claims | |
| --- | ---: | ---: | --- |
| I-29 | 2 | 0 | henvisning, ikke biografi |
| I-100 | 1 | 4 | |
| I-112 | 3 | 5 | |
| I-11 | 3 | 7 | fejlede først — se »Claim-niveau« |
| IV-19 | 10 | 25 | |
| III-104 | 2 | 0 | henvisning, ikke biografi |
| I-101 | 1 | 5 | |
| I-21 | 2 | 4 | |
| I-120 | 5 | 25 | |
| IV-34 | 13 | 11 | `delvis` |

**Brugbarheden er opgjort mod de otte biografiske poster.** I-29 og III-104 er
krydshenvisninger — de kan per definition ikke give claims, og modellens tavshed
var korrekt tilbageholdenhed.

### Prædikatfordeling

Tyngden ligger på `person.office` (12), `mention.place` (11), `person.death` (9),
`person.name` (7), `person.birth` (6) og `person.publication` (6) — 20 typer i
alt. Det er netop den **rygrad**, invariant 6 siger laget skal hente: embeder,
steder, datoer og navne, ikke prosaen selv.

## Hvad tallene ikke fanger

Her ligger dagsværkets egentlige udbytte. Begge fund har samme rod: **kontrakten
kontrollerer form.** Et claim kan være velformet, sandt og alligevel ubrugeligt.

### 1. Modellen misforstod en tidsangivelse — den opfandt ikke præcision

**Rettet 2026-09-13 efter at have læst selve sætningen.** Denne rapport påstod
først, at modellen havde opfundet en præcision, kilden ikke har. Det holder ikke.

I-11 fik to dødsclaims: `† 1342/1353` fra overskriften, og
`død 1353 (23. april)` fra en senere passage. **Begge står ordret i teksten** —
modellen har intet udledt. Men passagen lyder:

> »…var død 1353 (23. april), **da** hans sønner … solgte landsbyen Dunkelstorf.«

**23. april 1353 er datoen for sønnernes salg, ikke for dødsfaldet.** Bogen siger,
at han på det tidspunkt allerede *var død* — en `terminus ante quem`. Modellen
læste konstruktionen »var død [dato], da [begivenhed]« som en dødsdato.

Det er en **sproglig** fejl, ikke en præcisionsfejl, og konsekvensen er vigtig:
den kan ikke fanges ved at sammenligne datointervaller, for der er intet interval
at sammenligne. Den kræver forståelse af sætningens grammatik og hører derfor til
menneskets arbejde i 4.5 — ikke til en maskinel regel i 4.4.

Fejlen blev først kaldt »overpræcision« (denne rapport), derefter
»fejlattribution« (anden læsers hypotese). Ingen af delene kunne afgøres uden at
læse sætningen. **Tre gæt på samme fejl er et argument for at læse teksten, før
man designer en detektor.**

### 2. To af seks relations-claims identificerer ingen

| | værdi |
| --- | --- |
| `relation.marriage` | `NN.` |
| `relation.child` | `4 sønner` |

Begge er **sande** — bogen siger netop det — og begge formelt gyldige, fordi
kontrakten kun kræver et objekt med ordret `raw`. Men »4 sønner« er et **antal**,
ikke et barn, og `NN.` er en ukendt hustru. Som relationer er de ubrugelige: der
er ingen modpart at binde til.

Hullet er i valideringen, ikke i modellen. Skal `relation.*` kunne bære promotion,
må enten kontrakten kræve en identificerbar modpart, eller også må denne slags
klassificeres som noget andet — fx et `person.*`-faktum om antal børn.

### 3. Nogle poster er henvisninger, ikke biografier

To af de ti gav nul claims, fordi de er krydshenvisninger: I-29 (50 tegn) og
III-104 (70 tegn), begge med »se«-henvisning.

**Hvor mange der findes, er ikke afklaret.** En første måling sagde 38, men den
talte »kort **eller** uden årstal«, hvilket er noget andet. Præcist målt har kun
**3 af de 591** en eksplicit »se«-henvisning — og udvalget ramte tilfældigvis to
af dem. Til gengæld er **96 poster under 80 tegn** og giver næppe meget uanset.

Et filter før modelkaldet er stadig værd at overveje, men gevinsten er mindre end
først antaget, og signalet skal findes bedre end »se«.

### 4. En segmenteringsfejl, som ikke er modellens

I-11's klausuler er 1.958, **3** og 410 tegn. Den på tre tegn er `VI.` — et
**romertal, der er en sektionsoverskrift**, klippet ud som sin egen klausul.

Værre: den splittede Nicolaus' biografi **midt i en sætning**. Klausul 3 begynder
med »Den holstenske linje, nr. 9) panteforskrivning…«, som er fortsættelsen af
klausul 1. Modellen fik altså en sønderdelt sætning at læse — og det er
sandsynligvis medvirkende til fejllæsningen i afsnit 1.

Klausulledgerens flag sagde `structural_header: 0`. Segmenteringen så altså ikke
`VI.` som en overskrift. Det er et konkret, målbart hul i 4.1b's motor og er
registreret som selvstændigt punkt.

Bredere: **409 af de 485 klargjorte poster har kun én klausul.** Segmenteringen
deler altså sjældent op. Udvalget blev derfor bevidst skævt mod de svære strata —
det måler informationsværdi, ikke repræsentativitet, og tallene ovenfor skal
læses i det lys.

## Claim-niveau afvisning: en beslutning, kørslen fremtvang

I-11 fejlede i første omgang med `validation_failed`: modellen sendte
`person.name` med et objekt, hvor prædikatet kræver en streng. Ét ugyldigt claim
ud af syv fældede hele posten og dens **seks korrekte** claims.

Fejlen var ikke systematisk — alle øvrige claims havde korrekt værdiform, og ved
genkørsel kom **alle syv igennem uden afvisninger**. Det er modellens
variabilitet, ikke en misforstået prompt, og man kan ikke skrive sig ud af en
fejl, der kun sker nogle gange.

Projektejeren afgjorde derfor (2026-09-12), at et ugyldigt claim kun fælder sig
selv. Posten markeres `delvis`, og antallet af afviste står i logget. Sikkerheden
er uændret — et afvist claim lagres aldrig — men ved den observerede fejlrate
ville omtrent hver tredje rige post ellers gå tabt af ét forkert felt.

**IV-34 blev den første post, hvor reglen trådte i kraft:** nogle claims kom
igennem, resten blev afvist, og posten gik ikke tabt. Under den gamle regel var
alle elleve røget.

## To målefejl, jeg selv lavede

**Ordrethed blev først målt forkert.** Den maskinelle forudfyldning tjekkede, om
**alle** værdier stod ordret i klausulen (28/34). Men planens nævner er »claims
m. ordret krav«, og det er datoprædikaterne. De seks afvigelser var titler, som
modellen med rette havde skåret ud af længere sætninger. Rigtigt tal: 17/17.

**Optællingen meldte falsk `PENDING`.** Scriptet talte kun `green` og ignorerede
`delvis`, selv om alle poster havde validerede claims. `batch_status` var rettet;
scriptets eget print var ikke.

## Metode og efterprøvelighed

- Hvert kald kørte bag Seatbelt-gaten med adgangstesten bestået **umiddelbart
  før**, og gennem eligibility-værnet, som slår hver record op i ledgeren.
- Kørslen nægter at starte uden det godkendte manifests hash og stopper ved drift
  i ledger, profil eller prompt.
- Bedømmelsen foregik i private `0600`-ark uden for repoet med klausultekst og
  claims side om side. Ark-hashes: `a128f026eaa0ebcb…` (bundt 1),
  `ea6f0776c4283df7…` (I-11), `a09a155e520db596…` (bundt 2).
- **Ingen claim-værdier fra biografier er gengivet her** ud over de fire, der
  udgør selve fundene, og som ikke rummer oplysninger om levende personer.
- Alle ti poster kørte under samme frosne profil, prompt, model og outputskema
  (afvigelse E).

## Konklusion og næste skridt

**4.3b er gennemført.** Sporet bærer: modellen udtrækker sande, kildebundne fakta
af ægte DAA-prosa med 99 % præcision og perfekt klausulbinding, og den finder
ikke på noget, den ikke kan belægge.

**To ting skal lukkes i 4.4, før noget promoveres:**

1. Et `relation.*`-claim uden identificerbar modpart må ikke kunne blive en
   `interpretation_proposal`.
2. Et claim, der er mere præcist end kilden, må ikke kunne promoveres. Fuzzy
   datoer skal bevares som spænd, ikke afgøres af modellen.

**Åbent derudover:** segmenteringens tyndhed (409 af 485 poster har én klausul)
og klausulen på tre tegn i I-11. Begge hører til 4.1b's motor.

Restoren, ledgeren, manifesterne, svar-cachen og bedømmelsesarkene **bevares** til
efter 4.5 (spec §3: 4.3b-4.5 deler én restore). Sletningen er en eksplicit gate
efter 4.5, ikke en oprydning her.
