# Delspec 6d-2 — 1939's oversigtsomtaler, ubundne narrativer, identitetsflytning og kildetekst

**Status:** udkast 2026-11-09 efter brainstorm med projektejeren. Projektejerens afgørelser står i §3; mine valg er
markeret *mit valg*.
**Overordnet spec:** `docs/superpowers/specs/2026-11-08-trin6d-placement-relationer-medlemskab-design.md` §3 og §7
(6d-2's afgrænsning), `2026-10-29-trin6-1939-gennem-kaeden-design.md` §5.
**Forudgående mekanismer:** 6d-1 (placements og medlemskab, i prod 2026-11-09), 149b (legacy-migration af
narrativer, `private.migrate_legacy_narrative_record`), 6a/6c-3 (kildetekst-revision, `private.write_source_text_revision`),
redaktionel `samme_som` (`red_samme_som`, trigger `enforce_samme_som_invariants`), 6c-2 (kort 122, `P`-svar).
**Review-budget (B13), *mit valg*:** 1 Codex-runde (`gpt-6.1-sol`) på spec+plan og 1 på diffen før prod; Opus afvejer
hvert fund.

## 1. Roadmap-kobling

1. **Roadmapmål:** trin 6, færdigbevis (a): 1939's narrativer og publicering går gennem de samme operationer som
   2018-20.
2. **Værdikædeled:** source record → kildetekst (revision) → persona og identitet → narrativbinding og publicering;
   identitet på tværs af personrækker (`samme_som`).
3. **Leverancetype:** én generel regel (oversigtsomtaler publiceres ikke, når komponenten har en detaljepost i samme
   kilde), én generel udvidelse af `samme_som`-skrivevejen (retning afgøres af data) og brug af eksisterende
   skriveveje (149b's migration, kildetekst-revisionen, legacy-tilbagetrækning, identitetsafgørelse). Ingen
   editionsnavngiven permanent overflade.
4. **Værdi:** læseren ser ikke længere bogens oversigtsstumper som ekstra biografier på en person, der har sin fulde
   post; de tekster, der er den eneste 1939-tekst om en person, bliver bundet til bogens post; 1939's kildetekst får
   6m's 38 rettelser og 6 grænserettelser; fem kendte dubletpersoner lægges sammen med deres detaljeperson.
5. **Færdigbevis:** §8.
6. **Erstatter:** grandfathered legacy-publicering af 1939-narrativer uden record-binding; den uafklarede identitet fra
   kort 122; 6m's rapportlister `legacy-sager.json` (`kun_rapport`) og `graensefejl.txt` som eneste spor af rettelserne.
7. **Ændrer en tidligere beslutning:** decisions 2026-11-07 satte 6d's færdigbevis for de 13 narrativer til »de 13 har
   record-binding og er læst efter spor B«. Med projektejerens regel (§3 pkt. 1) får de, der er oversigtsomtaler af en
   person med detaljepost, *ingen* publicering; færdigbeviset bliver §8's. Registreres i `docs/decisions.md`.

## 2. Målt udgangspunkt

Målt 2026-11-09 på stand-in `daa5ab_ddl_standin_20261109142426_6d1c` (prod-dumpet `1653c8f7…` + 6d-1; dens `maal` er
byte-ens med prods `verify` efter 6d-1). Genmåles mod en frisk prod-kopi i plan-Task 0.

- **64 uplacerede 1939-records:** 21 med personpost, men uden hovedperson-persona; 8 uden personpost (6
  `structural_context`, 2 `cross_reference`); 35 med persona (32 med accepteret identitet, 3 uden).
- **De 21 uden persona** er alle uden løbenummer: 18 i oversigtszonerne (PDF 504, 508, 509) og 3 i indledningen (PDF
  498-499). 0 af dem har en publicering.
- **13 kilde 3-narrativer uden record-binding** (personer 929, 933, 934, 935, 940, 974, 977, 1013, 1014, 1135, 1791,
  1795, 1802). Alle personer er oprettet af 1939-importen alene, ingen har 1939-identitet eller -medlemskab. 8 er
  synlige for læseren i dag gennem `narrative_legacy_publication.status='grandfathered_publication'`; 5 er ikke
  (personen er ikke offentlig).
- **Komponenterne** (`samme_som`, afklaret): 974, 977, 1013 og 1802 ligger i en komponent med en placeret
  1939-person (1239, 1258, 1040, 986) og en 2018-20-person; 929 og 934 er kun koblet til 2018-20-personerne 44 og 2;
  de øvrige 7 er ikke koblet.
- **Narrativ → record** er fundet med tekstmatch (15 tegn midt i teksten, ±2 sider), *ikke* verificeret: 5 af de 13
  matcher en af de 21 (682 og 683 deler `record-7f274857…`); 602, 603 og 604 matcher samme *placerede* record
  (`record-6a073b93…`, PDF 497) — sandsynligvis tre personer, der nævnes i en anden persons post (delt tekst); 609, 804,
  1165 og 1169 matcher hver sin record (PDF 597, 532, 541, 584), heraf to placerede.
- **Henning (person 1849):** hans eneste 1939-tekst står på PDF 508 (oversigtszonen, »angives at have levet 1456-94«);
  narrativ 1191 er bundet og publiceret (binding fra C0/149b). Ingen 1939-detaljepost for ham.
- **Præcedens i 2018-20:** 11 uplacerede records, alle med en publiceret binding fra 149b's migration; 1939 har i dag
  35 publicerede bindinger på uplacerede records. `migrate_legacy_narrative_record` accepterer en post, der kun er
  blokeret af manglende identitet (`schema.sql:4253`, »valg A«), og opretter persona, accepteret identitet og
  binding. Nye bindinger uden for den vej kræver identitet gennem placement (`narrative_publication_state`).
- **Kort 122:** én 1939-identitet `unresolved` (persona på oversigtsposten `record-5fc1a041…`) med
  `ønsket_person_id=1054` (Ditlev 1646-1690, placeret i 1939). Ingen andre `P`-svar står åbne.
- **De 39 tekstrettelser** (6m's prod-rapport `legacy-sager.json`, `kun_rapport`): 30 OCR, 4 orddeling, 4
  overskydende, 1 manglende. 38 på 14 records (11 af dem blandt de 21 med 31 rettelser; 3 andre: oversigtspost PDF
  509, `ikke_alignet` PDF 532 og PDF 539) og 1 på narrativ 632 (person 963, staged), der kun må trækkes tilbage.
- **De 6 grænsefejl** (6m's `graensefejl.txt`): 4 records er placeret og publiceret (PDF 498, 500, 511, 575), 2 er
  blandt de 21 (PDF 499, 500).
- **Dubletpar** (decisions 2026-11-09 B): 991↔995, 992↔996, 1017↔1071, 978↔1136, alle oprettet fra en
  oversigtsomtale. 1014 kommer fra samme oversigtslinje som 1013 og er ikke koblet.

## 3. Projektejerens afgørelser (brainstorm 2026-11-09)

1. **Læseren tilbydes ikke en oversigtsomtale** af en person, der har sin egen detaljepost. Grænsen trækkes
   **maskinelt** (§4.1), ikke pr. kort.
2. **Er oversigtens tekst den eneste tekst** om personen i udgaven (Henning), er den hans og vises.
3. **Skjult er ikke slettet:** teksten består som kildens udsagn og kan ses af redaktøren (invariant 1).
4. **6d-2 laver `samme_som`-koblingerne** for de 4 dubletpar og 1014.
5. **Redaktøren vælger *om*, systemet vælger *retningen*,** når data kan afgøre den (§4.4); redaktøren kan ikke
   forventes at huske rækkefølgen.
6. **Alle 38 tekstrettelser føres ind i kildeteksten,** også på tekster, læseren ikke ser; rettelsen på narrativ 632
   trækkes kun tilbage.
7. **De 6 grænsefejl rettes i 6d-2** med samme mekanisme som tekstrettelserne.

## 4. Design

### 4.1 Oversigtsreglen (generel, kildeparametriseret)

En kilde-narrativ (eller binding) for person *P* i kilde *K* er en **oversigtsomtale**, når *P*'s afklarede
`samme_som`-komponent indeholder en *anden* person *Q* med accepteret record-placement og `principal_member`
persona-placement i *K*. Reglen ser på komponenten, ikke på koblingens retning, og bruger kun `afklaret`.

- Oversigtsomtaler publiceres ikke: en grandfathered legacy-publicering trækkes tilbage, en publiceret binding trækkes
  tilbage, og ingen ny binding oprettes. Narrativet, recorden og dens observationer består.
- Alle andre af de 13 (og Henning) er personens egen tekst i udgaven og bindes (§4.3).
- Reglen evalueres efter koblingerne (§4.4) og kort 122 (§4.5), så de nye komponenter tæller med.
- *Mit valg:* reglen er en læse-kun funktion (som B6's `membership_component_states`), og ceremonien bruger den til at
  udlede mængden, der skal trækkes tilbage, som pinnes på indhold (§6). Den håndhæves ikke af en trigger; en senere
  `samme_som`-kobling i redaktionen trækker ikke automatisk en publicering tilbage (registreres som kendt begrænsning;
  redaktionel vej til det er uden for 6d-2).

Forventet udfald ved målingen i §2 (genmåles i Task 0): **skjul** 974, 977, 1013, 1802 + 1014 og dubletparrenes
oversigtssider, hvis koblingerne lægger dem i en komponent med en placeret detaljeperson; **vis** 929, 933, 934, 935,
940, 1135, 1791, 1795 og Henning.

### 4.2 Skjul

Tilbagetrækning med de eksisterende veje: `red_tilbagetraek_legacy_narrative` (grandfathered) og
publiceringsvejens tilbagetrækning for bundne. Begge bevarer narrativ og audit. *Mit valg:* ingen `privat`-flag og
ingen sletning.

### 4.3 Vis: binding gennem 149b's migration

De tekster, der skal vises, bindes til deres record med `private.migrate_legacy_narrative_record` — samme operation,
som gav 2018-20's 11 uplacerede records deres binding. Migrationen opretter persona og accepteret identitet til
narrativets person; det er her, »personas for de 21« fra 6d-spec'en §7 indfries, nu kun for de records, hvis tekst
vises. Records med tekst, der skjules, får ingen persona (ingen dubletter).

Parringen narrativ → record skal fastslås, før der skrives (§2's match er heuristisk). Særtilfælde:
- **Delt tekst** (602/603/604 → én placeret record med en anden hovedperson): en persona for en nævnt person må ikke
  blive hovedperson på en andens post. *Mit valg:* disse tre går på kort til projektejeren med teksten og postens
  hovedperson; svarene er »bind som omtale«, »skjul« eller »parkér«. Kan migrationen ikke binde en ikke-hovedperson,
  parkeres de som kendt rest.
- **Record har allerede en persona** (`LEGACY_MIGRATION_PERSONA_EXISTS`): stop for den record; kort.

### 4.4 `samme_som`: koblingerne og retningen

- **Koblingerne:** 991↔995, 992↔996, 1017↔1071, 978↔1136 og 1014↔<detaljeperson>. 1014's partner findes i Task 0
  (samme oversigtslinje som 1013); projektejeren bekræfter på kort.
- **Retningen (generel regel i skrivevejen, *mit valg* at udvide `red_samme_som`/`enforce_samme_som_invariants`
  frem for en ny vej):** har den ene person en accepteret placering i en kilde, og den anden kun en uplaceret record i
  samme kilde, bliver den uplacerede alias og den placerede kanonisk — uanset hvilken retning redaktøren angav. Kan
  data ikke afgøre det (begge placeret, ingen placeret, forskellige kilder), gælder redaktørens retning som i dag.
  Konflikt med eksisterende kanter (cyklus, to sinks) stoppes af den eksisterende trigger.
- Appens sammenlægning (`packages/core/src/collapseSameAs.ts`) er uændret: kortet bliver den kanoniske person, og
  begge personers publicerede tekster vises som versioner — derfor skal §4.1 skjule oversigtsteksten.

### 4.5 Kort 122

Identiteten flyttes til 1054 (`decide_source_persona_identity`, accepteret, med 6c-2's kortsvar som evidens).
Personaens record er en oversigtspost, så §4.1 skjuler teksten; der er intet narrativ at flytte (6c-2's antagelse om
en narrativflytning bortfalder). Om den oprindelige person bliver en tom skal, måles i Task 0; i så fald `samme_som`
efter §4.4.

### 4.6 Kildetekst: 38 rettelser og 6 grænsefejl

Med kildetekst-revisionen (`write_source_text_revision`/`red_apply_reimport_source_text_revision`), første brug på
1939. Rettelserne kommer fra 6m's prod-rapport (`legacy-sager.json`, bundet med sha) og grænsefejlene fra
`graensefejl.txt`. Afhængige fortolkninger forældes (`supersede_for_text_revision`) som i 6c-3. For de 4 placerede og
publicerede records med grænsefejl revalideres placering og publicering, så 0 er `stale` bagefter (som 6d-1's
revalidering). En grænserettelse flytter tekst mellem to records; begge får en ny version.

*Mit valg:* rækkefølgen er kildetekst → koblinger og kort 122 → binding og tilbagetrækning, så bindingerne peger på den
rettede tekst.

### 4.7 Narrativ 632

Rettelsen på narrativ 632 (person 963, staged) trækkes kun tilbage fra rapporten (ingen skrivning til narrativet).

## 5. Ikke-mål og anti-mål

- Ingen nye personer fra oversigtsomtaler; ingen sletning af narrativer, records eller observationer.
- 2018-20 uændret: placements, medlemskaber, publiceringer og koordinater byte-ens (som 6d-1's paritet).
- Ingen læserændring ud over, hvilke 1939-narrativer der er publiceret (koordinater, udgavevælger: 6e).
- Ingen jagt på flere dubletter end de fem; identitet på tværs af udgaverne (fx 1849↔210, 960↔211) er backlog.
- Relationer er 6d-3.
- **Anti-mål:** en oversigtsstump, der stadig står som biografi på en person med fuld post; en tekst, der er den eneste
  om en person, og som forsvinder; en dublet, hvis kort viser oversigtens navn i stedet for detaljepostens.

## 6. Vejen til prod

Som 6d-1: privat runner efter `33-trin6d1.sh`-mønstret, dumps før hver skrivende ceremoni (B1 + age-kopi), frys,
vinduesvagt, GO pr. ceremoni, fortryd ved restore, generalprøve fra operatørens cwd på en stand-in fra en frisk prod
`dump-kopi`. *Mit valg:* én DDL-ceremoni (reglen som funktion, retningsreglen i `samme_som`-vejen) og én
data-ceremoni i én transaktion. Alle mængder pinnes på indhold (record keys, tekst- og manifest-hashes, narrativ-id'er
fra importen og person-id'er, der eksisterer i prod før ceremonien); aldrig persona-, binding- eller change_set-id'er
oprettet af ceremonien. Kort (delt tekst, 1014, persona-konflikter) besvares før GO og bindes med hash.

## 7. Overladt til bygherren

Funktionsnavne og -signaturer; om reglen er SQL eller plpgsql; den præcise tilbagetrækningsvej for bundne
publiceringer; formen på kortene (efter memory `menneske-gennemgang-token-fil` og `kortark-kraever-kontekst-html`);
hvordan grænserettelser repræsenteres i revisionens payload; testopdelingen.

## 8. Færdigbevis

- **Regel:** antal oversigtsomtaler og egne tekster, før og efter koblingerne; liste over narrativ-id'er i hver.
- **Skjul:** de skjulte er ikke synlige som anon (`person_daa_narrative_publication_allowed=false`), narrativ og
  record findes stadig.
- **Vis:** hver vist tekst har en publiceret record-binding med kilden »DAA 1939 · <post>«; 0 `stale`; Henning uændret
  publiceret.
- **Koblinger:** de fem kanter findes med detaljepersonen som kanonisk; 0 karantæne i appens sammenlægning for dem.
- **Kort 122:** identiteten accepteret til 1054; 0 `unresolved` 1939-identiteter tilbage (ud over evt. parkerede).
- **Kildetekst:** 38 rettelser og 6 grænserettelser som tekstversioner; forældede fortolkninger talt; de 4 placerede
  records revalideret, 0 `stale`.
- **2018-20 og 6d-1:** paritetshashes som 6d-1 (andre kilders placements/medlemskaber/publiceringer/ledger, læserne,
  koordinater) uændrede; 6d-1's 528 placements og medlemskaber uændrede.
- **Tid:** anon-læserne for de berørte personer under 3 s.

## 9. Åbne punkter og risici

- Delt tekst (602/603/604): om 149b's migration kan binde en ikke-hovedperson. Afklares i Task 0; ellers kort/parkering.
- 1014's partner er ukendt; kort.
- Kort 122's oprindelige person kan blive en tom skal.
- Retningsreglen ændrer en redaktionel skrivevej, der bruges i prod; den skal testes for 2018-20-par og for par uden
  placering (uændret adfærd).
- Kildetekst-revisionen er ikke brugt på 1939 før, og om en revision gør en placering eller publicering forældet, er
  ikke målt; revalideringen skal bevises på stand-in.
