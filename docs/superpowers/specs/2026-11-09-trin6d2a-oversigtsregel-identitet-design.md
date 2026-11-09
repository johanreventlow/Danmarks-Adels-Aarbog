# Delspec 6d-2a — oversigtsreglen og 1939's resterende identitetssager

**Status:** udkast 2026-11-09 (revision 2) efter brainstorm med projektejeren og et bygherre-tjek (Opus), der fandt
tre påstande i revision 1, som koden modsiger (§10). Projektejeren valgte at dele 6d-2 i **6d-2a** (denne spec) og
**6d-2b** (kildetekst og binding, §9). Projektejerens afgørelser står i §3; mine valg er markeret *mit valg*.
**Overordnet spec:** `docs/superpowers/specs/2026-11-08-trin6d-placement-relationer-medlemskab-design.md` §3 og §7,
`2026-10-29-trin6-1939-gennem-kaeden-design.md` §5.
**Forudgående mekanismer:** 6d-1 (placements og medlemskab, i prod 2026-11-09), narrativvagten
`public.person_daa_narrative_publication_allowed`, redaktionel `samme_som` (`red_samme_som`, trigger
`enforce_samme_som_invariants`), appens sammenlægning (`packages/core/src/collapseSameAs.ts`), 6c-2's kort 122.
**Review-budget (B13), *mit valg*:** 1 Codex-runde (`gpt-6.1-sol`) på spec+plan og 1 på diffen før prod; Opus afvejer
hvert fund. Bygherre-tjekket på revision 1 tæller ikke med.

## 1. Roadmap-kobling

1. **Roadmapmål:** trin 6, færdigbevis (a): 1939's narrativer og publicering går gennem de samme operationer som
   2018-20 — her den del, der afgør, *hvilke* 1939-tekster læseren tilbydes.
2. **Værdikædeled:** identitet på tværs af personrækker (`samme_som`) → publiceringsvagt → læser.
3. **Leverancetype:** én generel, afledt regel i publiceringsvagten (kildeparametriseret), én generel udvidelse af
   `samme_som`-skrivevejen (retningen afgøres af data) og to redaktionelle afgørelser med eksisterende skriveveje.
   Ingen editionsnavngiven permanent overflade.
4. **Værdi:** læseren ser ikke længere bogens oversigtsstumper som ekstra biografier på en person, der har sin fulde
   post — heller ikke efter fremtidige koblinger; den sidste uafklarede 1939-identitet afgøres.
5. **Færdigbevis:** §8.
6. **Erstatter:** grandfathered/publiceret visning af 1939's oversigtsomtaler; den uafklarede identitet fra kort 122.
7. **Ændrer en tidligere beslutning:** decisions 2026-11-07 satte 6d's færdigbevis for de 13 narrativer uden
   record-binding til »de 13 har record-binding og er læst efter spor B«. Med §3 pkt. 1 får oversigtsomtalerne blandt
   dem ingen visning, og bindingen af de øvrige flyttes til 6d-2b (§9). Registreres i `docs/decisions.md`.

## 2. Målt udgangspunkt

Målt 2026-11-09 på stand-in `daa5ab_ddl_standin_20261109142426_6d1c` (prod-dumpet `1653c8f7…` + 6d-1; dens `maal` er
byte-ens med prods `verify` efter 6d-1). Kun antal og id'er på personer/narrativer fra importen. Genmåles mod en frisk
prod-kopi i plan-Task 0.

- **1939's narrativer** (kilde 3, personer), fordelt efter om personen selv har et 1939-medlemskab (= placeret) og om
  dens afklarede `samme_som`-komponent har en *anden* placeret 1939-person:

  | Selv placeret | Anden placeret | Synlig i dag | Antal |
  |---|---|---|---|
  | nej | nej | ja / nej | 32 / 6 |
  | nej | **ja** | ja / nej | **9** / 1 |
  | ja | ja | ja | 6 |
  | ja | nej | ja | 522 |

  Rækken *nej/ja* er oversigtsreglens mængde (§4.1): 10 narrativer, heraf 9 synlige. Rækken *ja/ja* er personer, der
  selv har en detaljepost; dem rører reglen ikke.
- **De 13 narrativer uden record-binding** (personer 929, 933, 934, 935, 940, 974, 977, 1013, 1014, 1135, 1791,
  1795, 1802): 974, 977, 1013 og 1802 ligger i en komponent med en placeret 1939-person (1239, 1258, 1040, 986) og
  er dermed i reglens mængde. 8 af de 13 er synlige i dag via `narrative_legacy_publication.status =
  'grandfathered_publication'`.
- **De fire »dubletpar«** fra decisions 2026-11-09 B (991↔995, 992↔996, 1017↔1071, 978↔1136) er *allerede* i samme
  afklarede komponent: begge personer er alias for samme 2018-20-person (94, 97, 25, 259). Den placerede er
  995/996/1071/1136. Ingen ny kobling er nødvendig; reglen fanger dem.
- **1014** (»Bertram«, † 1666) står i samme oversigtslinje på PDF 504 som 1013 (»… Fader til Bertram til
  Lammershagen, Stocksee, Waterneverstorf o. s. v. († 1666) …«) og er ukoblet. Kandidat: **1048** Bertram 1611-1666,
  placeret i 1939, alias for 2018-20-person 134.
- **Henning (1849):** hans eneste 1939-tekst står på PDF 508; ingen anden 1939-person i hans komponent (han er ukoblet),
  så reglen rører ham ikke. Hans tekst er bundet og publiceret.
- **Kort 122:** én 1939-identitet `unresolved` (persona på oversigtsposten `record-5fc1a041…`) med
  `ønsket_person_id=1054` (Ditlev 1646-1690, placeret i 1939). Ingen andre `P`-svar står åbne.
- **Appens sammenlægning:** den kanoniske person er komponentens entydige sink; i komponenterne ovenfor er det
  2018-20-personen, og 1939-personerne er alias. Begge 1939-personers publicerede tekster vises som versioner på kortet.

## 3. Projektejerens afgørelser (brainstorm 2026-11-09)

1. **Læseren tilbydes ikke en oversigtsomtale** af en person, der har sin egen detaljepost. Grænsen trækkes
   **maskinelt**.
2. **Er oversigtens tekst den eneste tekst** om personen i udgaven (Henning), er den hans og vises.
3. **Skjult er ikke slettet:** teksten består som kildens udsagn og kan ses af redaktøren (invariant 1).
4. **Skjulningen skal ske automatisk** også ved fremtidige koblinger — man kan ikke regne med, at en redaktør trækker
   en tekst tilbage manuelt (projektejerens note til revision 1).
5. **Redaktøren vælger *om*, systemet vælger *retningen*,** når data kan afgøre den.
6. **Dubletterne kobles i 6d-2a** (målingen viste, at kun 1014 mangler).
7. **6d-2 deles** i 6d-2a og 6d-2b; de tekster, der skal vises, bliver stående som i dag, indtil 6d-2b kan binde dem.

## 4. Design

### 4.1 Oversigtsreglen (generel, afledt, kildeparametriseret)

En kilde-*K*-narrativ for person *P* er en **oversigtsomtale**, når
- *P* ikke selv har en accepteret record-placement med `principal_member`/`co_principal` persona-placement i *K*, og
- *P*'s komponent (kun `samme_som` med `afklaret` konklusion, uanset retning) indeholder en *anden* person *Q*, der har.

En oversigtsomtale er ikke tilladt for læseren. *Mit valg:* reglen indbygges i publiceringsvagten
(`person_daa_narrative_publication_allowed`) som en afledt betingelse — ikke som en skrivning — så den
- virker straks efter enhver ny eller fjernet kobling (§3 pkt. 4), og er reversibel, hvis koblingen fjernes;
- gælder både grandfathered og bundne publiceringer;
- ikke ændrer narrativ, binding, record eller publiceringshændelser (§3 pkt. 3).

Redaktørens visning (`redaktion_read`) er uændret; *mit valg:* redaktørens narrativvisning får en markering af, at
teksten er en oversigtsomtale og derfor skjult for læseren (formen er bygherrens).

**Krav:** vagten kører pr. række under anon-RLS (grænse 3 s). Komponentopslaget må ikke gøre læserkaldene for de
tungeste personer langsommere end anon-grænsen med margen; bygherren vælger formen (fx en materialiseret eller
indekseret komponentprojektion, eller en trigger på `samme_som`, der opdaterer en afledt markering). Ændres
vagtens form, skal den stadig være afledt og reversibel.

### 4.2 Retningen i `samme_som` (generel regel i skrivevejen)

*Mit valg* at udvide `red_samme_som`/`enforce_samme_som_invariants` frem for en ny vej: har den ene person en
accepteret placering i en kilde, og den anden ingen placering i samme kilde (men en record i den), bliver den
uplacerede alias — uanset hvilken retning redaktøren angav. Kan data ikke afgøre det (begge eller ingen placeret,
ingen fælles kilde), gælder redaktørens retning som i dag. De eksisterende vagter (G3 flere sinks, G4 alias er
allerede sink, cyklus) består og stopper en kobling, der ellers ville give en tvetydig komponent; retningsreglen må
ikke omgå dem. Tests: et 2018-20-par og et par uden placering skal opføre sig som i dag.

Hvad læseren ser, afgøres af komponentens sink (appen) og af §4.1 (vagten); retningsreglen sikrer kun, at en
oversigtsperson aldrig bliver den kobling, en detaljeperson peger på.

### 4.3 1014 (kort)

Projektejeren bekræfter på et kort med oversigtslinjen og kandidatens post, om 1014 er 1048. Ja → `samme_som`
1014 → 1048 (afklaret) gennem `red_samme_som`; 1014's tekst bliver en oversigtsomtale efter §4.1. Nej → 1014 står
som egen tekst (§3 pkt. 2). Kortformen følger memory `kortark-kraever-kontekst-html` og `menneske-gennemgang-token-fil`.

### 4.4 Kort 122

Identiteten afgøres `accepted` til 1054 med den eksisterende identitetsvej og 6c-2's kortsvar som evidens.
Personaens record er en oversigtspost uden narrativ, så der er intet at flytte (6c-2's antagelse om en
narrativflytning bortfalder). Task 0 måler, om personen, identiteten pegede på før, mister sit eneste grundlag; i så
fald registreres det som rest til 6d-2b, ikke rettet her.

## 5. Ikke-mål og anti-mål

- Ingen nye personer, personas eller bindinger; ingen sletning af narrativer, records, observationer eller hændelser.
- Ingen kildetekst-rettelser og ingen grænserettelser (6d-2b).
- 2018-20 uændret: placements, medlemskaber, publiceringer og koordinater byte-ens; reglen rammer ingen 2018-20-tekst
  i dag (målt i Task 0; ellers stop og spørg).
- Ingen læserændring ud over, hvilke narrativer vagten tillader (koordinater, udgavevælger: 6e).
- Identitet på tværs af udgaverne for personer uden 1939-detaljepost (fx 1849↔210, 960↔211) er backlog.
- **Anti-mål:** en oversigtsstump, der stadig står som biografi på en person med fuld post; en tekst, der er den eneste
  om en person, og som forsvinder; en ny kobling, der giver en karantæneret (tvetydig) komponent.

## 6. Vejen til prod

Som 6d-1 i mindre skala: privat runner, dump før hver skrivende ceremoni (B1 + age-kopi), frys, vinduesvagt, GO pr.
ceremoni, fortryd ved restore, generalprøve fra operatørens cwd på en stand-in fra en frisk prod-`dump-kopi`.
- **DDL-ceremoni:** vagten (§4.1) og retningsreglen (§4.2), i én transaktion med `db-rls.sql`.
- **Data-ceremoni:** 1014's kobling (efter kortsvaret) og kort 122's identitet; pinnes på indhold (person-id'er og
  record keys, der findes i prod før ceremonien, kortets hash); aldrig id'er oprettet af ceremonien. Er
  `begin_change_set` åben for hele transaktionen, nulstilles `app.change_set_id` mellem kaldene (kendt mønster).
- **Mål før/efter:** antal synlige 1939-narrativer som anon, reglens mængde, KOORD- og paritetshashes som 6d-1,
  anon-tid for koordinat-RPC'en og for narrativlæserne for de tungeste personer.

## 7. Overladt til bygherren

Vagtens form og præstationsteknik (inden for §4.1's krav); funktionsnavne og signaturer; redaktørmarkeringens form;
kortformen; testopdelingen.

## 8. Færdigbevis

- **Regel:** reglens mængde målt i prod før og efter (forventet 10 narrativer, 9 synlige før; 11, hvis 1014 kobles);
  0 af dem synlige som anon efter; narrativ, binding og record findes stadig for alle.
- **Reversibilitet:** på stand-in fjernes én kobling og teksten bliver synlig igen; kobles igen og skjules.
- **Uberørte:** de 6 *ja/ja* og de 522 *ja/nej* er synlige som før; Henning synlig.
- **Retning:** stand-in-tests for begge retninger på et oversigts-/detaljepar og uændret adfærd for et 2018-20-par og
  et par uden placering.
- **1014 og kort 122:** kanten findes (eller kortets nej er registreret); identiteten er `accepted` til 1054; 0
  `unresolved` 1939-identiteter.
- **2018-20 og 6d-1:** paritetshashes som 6d-1 uændrede; 528 placements og medlemskaber uændrede.
- **Tid:** anon-læserne under 3 s med margen for de tungeste personer.

## 9. 6d-2b (afgrænsning, specificeres senere)

- **Binding af de tekster, der vises** (929, 933, 934, 935, 940, 1135, 1791, 1795 og de andre egne tekster uden
  binding): 149b's `migrate_legacy_narrative_record` kræver `person_external_id.record_key` = postens nøgle, hvilket
  kun gælder 8 af 1939's 576 rækker (bevidst; decisions om 1939's record_key). Kræver en ny identitetskilde i
  skrivevejen eller en ny writer. Ikke-offentlige personer kan kun få en kladdebinding.
- **De 38 tekstrettelser** (6m's `legacy-sager.json`, `kun_rapport`): kildetekst-revisionen har kun en 2018-20-profil
  (`folded_projection@page_header`); 1939 bruger `raw` med eksakte offsets i klausulgenskæringen. Kræver en
  1939-profil og afklaring af længdeændrende rettelser; revisionen kræver også et eksisterende klausulsæt på posten.
- **De 6 grænsefejl:** revisionen låser teksten til postens eksisterende spænd (`TEXT_REVISION_SPAN_MISMATCH`); en
  grænserettelse er ny forekomst + nyt anker (6a-spec'en), ikke bygget, og gør publicerede tekster forældede.
- **Bindinger, en revision taber:** 6c-3's afstemningswriter har en kendt fejl, der skal rettes, før den får en ny
  kalder (6c-3-spec'en).
- **Rettelsen på narrativ 632** (person 963, staged) trækkes kun tilbage fra rapporten.

## 10. Bygherre-tjek af revision 1 (Opus, 2026-11-09)

Fund, efterprøvet mod koden og indarbejdet:
1. 149b's migration kan ikke binde 1939-tekster (record_key 8/576) → binding flyttet til 6d-2b.
2. Grænsefejl kan ikke rettes med kildetekst-revisionen → 6d-2b.
3. Ingen 1939-profil til kildetekst-revision → 6d-2b.
4. Tabte bindinger ved revision → 6d-2b.
5. Reglens rækkevidde var uklar → defineret og målt (§2, §4.1); skærpet til »P selv uplaceret«.
6. Narrativ→record-parringen havde huller → ikke længere nødvendig i 6d-2a (ingen binding).
7. `samme_som`-vagterne og retningen → målt: de fire par er allerede koblet; kun 1014; vagterne består (§4.2).
8. Ikke-offentlige personer kan ikke få publiceret binding → 6d-2b.
