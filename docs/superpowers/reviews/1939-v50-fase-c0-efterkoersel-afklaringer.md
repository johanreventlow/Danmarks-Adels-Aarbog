# C0's efterkørsel — de to blokerende spørgsmål afgjort

**Dato:** 2026-08-20 · **Karakter:** read-only måling mod prod · **Intet skrevet.**

Genmålingen efterlod to spørgsmål, som begge blokerede for at planlægge
efterkørslen. Begge er nu afgjort empirisk frem for ved ræsonnement.

---

## Spørgsmål 1: mister 1017 og 1297 tekst, der findes andre steder?

Det afgørende er ikke *at* tekst forsvinder, men **hvor den bliver af**.
Findes den i et andet narrativ, deduplikerer koblingen. Findes den ingen
steder, sletter den. Testet mod alle 576 1939-narrativer.

### Person 1017 — ægte tab. **Anbefaling: tag den ud af batchen.**

Det, koblingen fjerner (149 tegn):

> B) Ditlev til Wittenberg og Lammershagen († 1690), Fader til Overhofmester
> Frederik Revent- low († 1752), hvis Søn Friederich Adolph døde ugift 1773.

Fragmentet findes **ikke ordret** i noget andet narrativ. Længste delvise
match er 57 af 149 tegn — og det match er person **1021's samlede narrativ**:

> low († 1752), hvis Søn Friederich Adolph døde ugift 1773.

**1021 begynder midt i det orddelte »Revent- low«.** Den er ikke en post; den
er halen af 1017's afsnit B), skåret over ved en orddeling. Det er
grænsefejl-mønsteret i renkultur.

Konsekvensen af at køre koblingen som den står: afsnit B) fjernes fra 1017,
og de første ~92 tegn — »B) Ditlev til Wittenberg og Lammershagen († 1690),
Fader til Overhofmester Frederik Revent-« — findes derefter **ingen steder**.

C0's note antog, at B)-delen »hører til person 1021 og følger med i C3«. Det
er kun halvt rigtigt: 1021 bærer de sidste 57 tegn, ikke de første 92.

Den rigtige rettelse er derfor ikke at afkorte 1017, men at **slå 1021 sammen
med 1017's afsnit B)** — altså en C3-sammenlægning, ikke en C0-kobling.

### Person 1297 — tabet er struktur, ikke indhold. **Anbefaling: behold i batchen.**

Det, koblingen fjerner (27 tegn):

> Børn: Ottende Slægtled IIl.

En krydshenvisning til hvor børnene står i den trykte bog (»IIl« er OCR for
»III«), ikke biografisk indhold. Findes ikke andetsteds, men behøver det
heller ikke: relationerne bærer oplysningen i modellen, og fase B fjernede
allerede samme klasse af strukturmarkører (73 sidemarkører, 499
søskende-ordenstal).

**Til brugerens afgørelse:** hvis strukturlinjer skal bevares som kilde-tro
evidens, skal 1297 også ud. Fase B's præcedens siger nej.

---

## Spørgsmål 2: må en record bindes til en *staged* persons narrativ?

C0 flagede dette som et uafklaret »synligheds-/RLS-spørgsmål« og udskød det.
Målt mod prod er svaret **ja — der er ingen lækage at frygte**:

| Måling | Resultat |
|---|---|
| Er `private` eksponeret gennem API'et? | **Nej** — `pgrst.db_schemas` er tom for skemaet |
| Grants til `anon`/`authenticated`/`PUBLIC` på `narrative_record_publication` | **0 rækker** |
| `anon` forsøger at læse `private`-skemaet | `ERROR: permission denied for schema private` |
| `anon` ser narrativer for de 7 staged | **0** |
| `anon` ser de 7 staged personer | **0** |

Bindingsrækken lever i `private`, som anonyme brugere slet ikke kan røre, og
både personen og narrativet er usynlige, så længe `staged` er sat.

**Konsekvens:** rækkefølgen mellem »bind record« og »gør synlig« er
ligegyldig for synligheden. 963 og 967 kan bindes uden at afvente D3, og
spørgsmålet blokerer ikke længere efterkørslen.

---

## Hvad det betyder for efterkørslens design

Af de 10 koblinger er **9 klar** (de otte uproblematiske plus 1297), og **1017
hører til C3** frem for C0.

Men efterkørslen kan ikke arve D2's form, og det er en beslutning der kræver
sin egen spec:

**D2 var fuldt fortrydbar.** `change_set 960` dækker alle 21 ændringer, og
`person` står i `version_pk_registry`.

**Efterkørslen er det ikke.** `private.narrative_record_publication` står
ikke i `version_pk_registry`, så en forkert kobling kan **ikke rulles tilbage
ad normal vej** — dumpen er eneste udvej. Gate-kæden skal derfor være
*stærkere* end D2's, ikke den samme. Desuden erstatter efterkørslen
narrativtekst, hvor D2 kun rørte et boolsk flag.

Det er grunden til at værktøjet ikke er skrevet her: det er en ny fase med
egen spec og egen plan, ikke det sidste trin i en eksisterende.

**Praktisk note:** den lokale `daa1939_d2_rehearsal1` har nu D2 anvendt (7
staged). Skal den genbruges til at øve efterkørslen, skal den re-restores fra
dumpen først.
