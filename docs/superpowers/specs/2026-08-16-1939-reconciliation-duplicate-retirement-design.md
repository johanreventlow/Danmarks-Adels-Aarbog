# 1939-afstemning: sporbar udfasning af ekstraktionsdublet

## Formål

Beslutningslaget skal kunne registrere, at to gamle `record_key`-poster er
tekniske ekstraktionsdubletter af samme trykte kildepost. Den korrekte gamle
nøgle videreføres til den nye kildepost. Dubletnøglen må ikke importeres, men
skal forblive synlig i auditoutputtet.

Den konkrete godkendte afgørelse gælder side 505:

- Bevar `f81f2fc4-1d45-45fd-be9f-4330e69196e7` (`Ditlev Reventlow`).
- Udfas `7e5431b3-5a60-46b7-8760-a87f00988e25` (`DitlevReventlow`) som
  ekstraktionsdublet.
- Begge gamle poster har samme kildespænd og peger på den samme nye
  kildepost; afgørelsen er ikke en sammenlægning af to personer.

## Valgt model

Beslutningsdokumentet får en særskilt `retire_duplicate_record`-handling med:

- den udfasede `baseline_record_key`;
- den bevarede `canonical_baseline_record_key`;
- den fælles `new_record_key`;
- årsagen `duplicate_extraction_record`.

Den udfasede baseline-post bevares i outputtet med dispositionen
`retired_duplicate`, en henvisning til den bevarede nøgle, `reviewed_by` og
`decision_batch`. Dens matchkant fjernes, så den ikke længere ejer eller kan
materialisere den nye kildepost. Den bevarede post får dispositionen
`accepted_carryover` og bliver den eneste gamle ejer af den nye post.

Alternativerne er fravalgt: fysisk sletning ville miste sporbarhed, mens to
fortsat aktive ejere ville efterlade en falsk merge-konflikt.

## Validering og fejltilstande

Handlingen må kun accepteres, når alle følgende forhold kan bevises i det
hashbundne afstemningsinput:

1. Begge gamle nøgler findes og er forskellige.
2. Begge står i en merge-konflikt om præcis den angivne nye nøgle.
3. Begge har identisk, ikke-tomt `source_span`.
4. Den nye nøgle findes, og begge matchkanter peger på den.
5. Ingen anden beslutning i samme batch vælger eller udfaser de samme nøgler
   på en modstridende måde.
6. Beslutningsdokumentets baseline-, Calamari- og reconciliation-hash matcher
   inputtet byte-for-byte.

Hvis et krav fejler, afvises hele batchen uden delvist output. Navnelighed,
rækkefølge eller sidetal er aldrig tilstrækkelig dokumentation.

## Rapportering og importgrænse

Rapporten tæller `retired_duplicates` særskilt. Både `unchanged`,
`accepted_carryover` og `retired_duplicate` er menneskeligt afgjorte
dispositioner, men kun de to første må eje en ny kildepost. En senere import
skal derfor filtrere `retired_duplicate` fra og kan samtidig bevare posten i
revisionssporet.

Dette arbejde ændrer ikke databasen, personidentiteter eller det gamle
identitetsregister. Det ændrer kun den versionsbundne kildepostafstemning.

## Testdesign

Testene skal først bevise, at den nuværende kode afviser den nye handling.
Derefter skal de dække:

- korrekt udfasning og ene-ejerskab for den bevarede post;
- synlig auditproveniens på den udfasede post;
- særskilt rapporttælling og korrekt restkø;
- afvisning ved forskellige kildespænd, forkert fælles mål, ukendte nøgler,
  hashdrift og modstridende beslutninger;
- uændret behandling af de allerede understøttede splitvalg.

Efter implementeringen køres den fokuserede testsuite, hele DAA-scriptpakken
og en artefaktkontrol af de fem godkendte afgørelser.
