# DAA 1939 v50 Death-Year Identity Review Design

**Dato:** 2026-08-17

**Status:** Godkendt design. Review-only; ingen databaseændringer.

## Formål

Efter to godkendte identitetsbatches er 30 v50 source records fortsat uden en
identitetsafgørelse. Næste reviewpakke skal finde den snævre delmængde, hvor en
resumépost entydigt kan forbindes med en allerede kortlagt 1939-person ved
hjælp af personens hovednavn og dødsår.

Resultatet er kun kandidatmateriale til menneskelig godkendelse. Det må ikke
oprette source personas, ændre kanoniske personer eller skrive til databasen.

## Valgt metode

En ny deterministisk Python-builder fremstiller en reviewpakke for alle 30
resterende source records. Et kandidatlink oprettes kun, når samtlige følgende
krav er opfyldt:

1. Kandidaten tilhører de 543 allerede kortlagte 1939-profiler.
2. Kandidatens navn findes som et ordret navnesignal i postens hovedpersondel.
3. Et firecifret år i samme hovedpersondel findes også i kandidatens
   eksisterende `død`-faktum.
4. Præcis én kortlagt profil opfylder navn-og-dødsår-kravet for posten.
5. Hver kandidat-record key og hvert kanonisk person-ID bruges højst én gang i
   pakken.

Navne- og årssignaler gemmer eksakte tegn-offsets og henviser til den konkrete
profil og det konkrete dødsfaktum. Normalisering må hjælpe med kontrol og
sortering, men må ikke stå som beslutningsbevis; den accepterede evidens er de
ordrette source-substrings.

## Hovedpersondel og hierarki

Hovedpersondelen slutter før den første eksplicitte overgang til børn eller
efterkommere, herunder `Fader til`, `hvis Søn`, `havde Søn`, `havde Sønnen`,
`havde Sønnerne` og tilsvarende datterformer. Et år, navn eller gods efter
overgangen må derfor ikke kvalificere den indledende person.

Poster, hvor den tilsigtede person først introduceres hierarkisk gennem en
forælder, indgår ikke automatisk. Det gælder konkret posten med formuleringen
`Storkansler Conrad Reventlow havde Sønnen: ... Christian Ditlev ... † 1738`.
Den bliver synligt uafklaret og forelægges særskilt.

## Autoritative input

Builderen hashbinder og validerer:

- `mapped-identity-review-v1.json`, som er udgangspunktet med 32 subjects;
- begge eksisterende identitetsbeslutningsbatches, så deres source records og
  kanoniske personer ikke kan genbruges;
- `database-preview-v1.json`, som binder baseline record keys til person-ID'er;
- `clean_1939_v3.json`, som leverer profilnavn og source-bundet dødsfaktum.

Inputdrift, ukendte schemas, ugyldige gates, dubletter, manglende profiler og
uventet subject-coverage afvises fail-closed. De to nyligt godkendte subjects
fjernes eksplicit, så output dækker præcis 30 resterende subjects.

## Forventet reviewpakke

Den godkendte regel forventes at frembringe 11 entydige kandidater:

1. Detlev til Hemmelmark, død 1701
2. Conrad Detlev, død 1750
3. Cay Friedrich, død 1762
4. Ditlev, Biskop i Lübeck, død 1536
5. Johan Ludvig, død 1801
6. Conrad Reventlow, død 1708
7. Ditlev, død 1733
8. Otto til Schöneweide m.fl., død 1618
9. Henning til Hemmelmark, død 1705
10. Ditlev til Rixdorf, død 1604
11. Otto til Wittenberg og Waterneverstorf, død 1676

De øvrige 19 subjects forbliver eksplicit listet uden kandidat. Et andet antal
end 30 subjects eller 11 kandidatlinks gør den konkrete build til `NO-GO`.

## Output og gates

Det private, ignorerede bundle under
`work/task22-1939-v50-identity-review/` indeholder:

- inputhashes og generatorversion;
- alle 30 resterende subjects i stabil source order;
- 11 review-only links med ordrette navne- og årssignaler;
- 19 subjects uden link;
- eksakte person-ID'er, record keys og source spans;
- `review_state: pending` og `canonical_mutations_authorized: false`;
- `identity_decision_gate: NO-GO`, `database_gate: NO-GO` og
  `reimport_gate: NO-GO`.

En efterfølgende brugerbekræftelse kan materialiseres som en særskilt
beslutningsbatch. Reviewbuilderen må aldrig selv ændre et link til `same`.

## Test og verifikation

Testene skal mindst bevise:

- observeret RED før implementering og GREEN efter minimal implementering;
- præcis 30/11/19-coverage og stabil sortering;
- byteidentisk rebuild fra uændrede input;
- afvisning af SHA-, schema-, gate-, count- og key/person-drift;
- afvisning af navn uden dødsår, dødsår uden navn og år efter en
  slægtskabs-overgang;
- afvisning af flere kvalificerede profiler eller genbrug af record key/person;
- eksakte literal offsets for navn og år;
- bevarelse af pending/review-only-status og alle skrive-gates på `NO-GO`;
- fuld eksisterende scriptsuite uden regressioner.

