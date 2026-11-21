# »Kun i DAA 1939« — mærke for personer, en nyere stamtavle ikke har med

Dato: 2026-11-21 · Størrelse: lille ændring (core + web-visning, ingen DB) · Opfølgning på PR #414

## Hvorfor

Conrad Reventlows datter Charlotte Amalie (1939 nr. 2, person 1793) står kun i DAA 1939. DAA 2018-20's forfatter har
gennemgået kilderne kritisk og ikke medtaget hende. Siden viser hende i dag som et almindeligt barn. Læseren skal
straks kunne se, at hun kun bygger på den ældre udgave — loyalt over for begge: 1939's oplysning skjules ikke, men
får heller ikke samme vægt som det, begge bøger er enige om.

## Ordvalg (projektejeren)

»Kun i DAA 1939« — neutralt: et udsagn om kilderne, ikke en dom. »Afvist« kræver en påstand fra 2018-20 (invariant 1:
påstand = én kildes udsagn; tavshed er ikke et udsagn). Ingen parenteser om navnet: data bruger parenteser til
kaldenavne (»Anna (Anny) Frederikke …«).

## Regel (tilgang B, valgt)

Én ren funktion i `@daa/core` pr. person:

- Personen har stamtavlenumre i en eller flere udgaver (`bogNrBy`, kanonisk).
- Forældrene (kanonisk) står i en nyere udgave N, som er en **stamtavle** for slægten (ikke præsensliste: den rummer
  kun nulevende og ville give falske mærker).
- Personen står ikke i N og i ingen udgave, der er lige så ny eller nyere.
- Så: »kun i <personens udgaver>, ikke i N«. N = forældrenes nyeste stamtavle-udgave med kendt år.
- Ellers intet mærke: ingen forældre, forældre uden nyere udgave, ukendt år, eller personen kun i nyere udgaver
  (typisk født efter den ældre udgave — forventeligt, ikke en udeladelse).

Fravalgt: A (afledt af sorteringen — to regler, der kan glide fra hinanden), C (relationens citater pr. udgave —
ekstra hentning pr. side, virker ikke i stamtræet).

## Visning

- Personsidens børneliste og stamtræets barnekort: mærket »Kun i DAA 1939« efter navnet, i samme stil som
  konfidensordet (»FORMODET«), men en anden farve end `T.danger` (konfidens er redaktionens vurdering; dette er en
  kendsgerning om bøgerne). Mus-over / `title`: »Står i DAA 1939, men ikke i DAA 2018-20.«
- Personens egen side: linje under navnet (som »Optræder i Aarbogen som …«): »Nævnes kun i DAA 1939 og er ikke med i
  DAA 2018-20.«
- Rækkefølgen er uændret (barnet står på sin plads fra den ældre udgave, jf. #414).
- Udgavenavne fra `model.udgaver[].label`; flere ældre udgaver forbindes med » og «.

## Ikke-mål

Mobil, feed, søgning, redaktionens konfidens-felt, DB/skema/loader.

## Skalering

Reglen sammenligner med forældrenes nyeste stamtavle, ikke bogens nyeste udgave: hver slægt har sin stamtavle i sit
eget bind, så andre slægter får automatisk den rigtige sammenligningsudgave. Opslag O(1) pr. person over et indeks,
der allerede bygges én gang.
