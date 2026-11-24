# Personside og stamtræ: fire justeringer før bestyrelses-fremvisning (2026-11-23)

**Status:** kort design (lille ændring). Spor 1 af 4 i POC-klargøringen til Adelsforeningens bestyrelse
(1 småting · 2 billeder fra 2018-20 · 3 steder fra TNG · 4 caching).

## Formål
POC'en skal kunne vises frem uden skønhedsfejl, der får en læser til at tvivle på data. Eksempel: person 392
(familieoversigten og stamtræet). Kun web og den delte kerne (`packages/core`); mobilen følger automatisk, hvor den
deler kernen.

## De fire ændringer (projektejerens valg 2026-11-23)

1. **Barn, der kun står i en anden udgave (valg A).** I familielisten under »Børn« vises et barn med »Kun i DAA 1939«
   som **grå, ikke-klikbar tekst** med mærket, når den valgte udgave på personsiden ikke er den, barnet står i.
   Vælger læseren den udgave, barnet står i (udgavevælgeren), bliver navnet et link.
   Fravalgt: B (altid link, åbner i barnets udgave) — projektejeren foretrak, at linket følger udgavevalget.
2. **\* og † i stedet for bindestreg.** Livsdatoer vises som `* 1671 † 1738`, `† ung`, `* 1688 † lille`
   (i dag `1671–1738` og den fejlagtige `1688-lille`). Kun født: `* 1640`; kun død: `† 1708`; floruit uændret
   (»Nævnes 1671«).
3. **Vielse ved ægtefællen.** Under »Gift med« efter ægtefællens livsdatoer: `⚭ 18. nov. 1670` når datoen kendes,
   ellers `⚭ 1670`, ellers intet. Datoen er vielsesfaktummets visningsdato for den familie (union), der forbinder de
   to (472 vielsesfakta i prod, alle med konklusion).
4. **Stamtræet følger bogens rækkefølge.** Børn i stamtræets kolonner (`buildBidirectionalColumns`, web
   `TreeView` og mobilens `tree.tsx`) sorteres med `sorterBoernEfterBogen` — samme regel som profilen og
   fokustræet. I dag sorteres de ikke, så børn med dårlige datoer havner efter indlæsningsrækkefølgen.

## Tilgange (overvejet)
- **\* og †: global formatering (valgt) vs. kun i familielisten.** `fmtYears` i `packages/core/src/fields.ts`
  laver strengen for hele appen (søgning, stamtræ, bogmærker, feed, mobil). Fejlen `1688-lille` opstår dér og
  findes derfor overalt. *Min beslutning:* ret den ét sted, så alle visninger er ens. Bygger tjekker, at de længere
  strenge ikke knækker stamtræets kort og søgeresultaterne (bredde), og retter tests, der låser den gamle form.
- **Udgave-afhængigt link: brug personsidens valgte udgave (valgt) vs. en ny global udgave-tilstand.** Siden har
  allerede `v.aktivChip`/`v.valgtIdx` (udgavevælgeren). Barnets udgaver kendes fra `kunIAeldreUdgave`. Ingen ny
  global tilstand.
- **Sortering i stamtræet: kald `sorterBoernEfterBogen` i kernen (valgt) vs. sortere i hver app.** Kernen deles
  af web og mobil; én rettelse dækker begge.

## Ikke-mål
- Ingen datarettelser. Person 392's »Charlotte Amalie † ung — Kun i DAA 1939« er korrekt: 1939 nævner to døtre med
  navnet, 2018-20 kun én (projektejeren 2026-11-23, afklaret tidligere). Udgavernes uenighed er netop, hvad mærket
  skal vise.
- Ingen ændring af hvilke børn der vises, kun hvordan.
- Ingen DB-ændring forventet (vielsesdatoen hentes fra eksisterende læsevej; mangler den i web-modellen, hentes den
  via eksisterende offentlige fakta-RPC/-view — ingen ny RPC uden at spørge først).

## Overladt til bygger
- Hvor vielsesdatoen hentes i web-modellen (findes den allerede ved familier, eller skal family-fakta med i
  indlæsningen) — vælg den billigste eksisterende vej; mål forsidens/personsidens indlæsningstid før og efter.
- Hvad »valgt udgave« betyder, når personen kun har én udgave (ingen vælger): så gælder personens egen udgave.
- Grå tekst skal stadig være tilgængelig: mærket forklarer (`title`/skærmlæsertekst = `forklaring` fra
  `kunIAeldreTekst`).

## Færdigbevis
- Enhedstests i `packages/core` (fmtYears-former, sortering i kolonner) og web (`PersonSide`: grå vs. link pr.
  udgave; ⚭-linje med/uden dato).
- Person 392 på Vercel-preview: \*/†-former, `⚭` ved begge hustruer, Charlotte grå i 2018-20 og link i 1939,
  stamtræets børn i bogens rækkefølge.
- CI: node-jobbet (core · web · mobil `tsc`).
