# Delspec 6d — placement, relationer og medlemskab for 1939 (UDKAST)

**Status:** udkast 2026-11-08, ikke godkendt. Projektejeren bad om udkastet uden forudgående spørgsmål; mine valg er
markeret *mit valg*, og de åbne spørgsmål står i §9.
**Overordnet spec:** `docs/superpowers/specs/2026-10-29-trin6-1939-gennem-kaeden-design.md` §5 (6d), §6 pkt. 3 (B6)
og pkt. 8 (hvor 1939 hører hjemme), §8 (færdigbevis b og c).
**Forudgående mekanisme:** 5c-1 (`docs/superpowers/specs/2026-10-26-trin5c-placement-membership-design.md`), 5b
(`2026-10-06-trin5b-relationspersonas-design.md` og 2a/2b-i/2b-ii/2b-iii), 5c-2 (læserne).
**Review-budget (B13):** 1 Codex-runde (`gpt-6.1-sol`) på spec+plan for 6d-1 og 1 på diffen før prod; Opus afvejer
hvert fund. 6d-2 og 6d-3 får hver deres eget budget i deres spec.

## 1. Roadmap-kobling

1. **Roadmapmål:** trin 6, færdigbevis (a) for placement og (c): »et medlemskab kan bæres af to kilder — en anden
   kildes placement bekræfter (`corroborated`) i stedet for at give konflikt« (B6). Desuden (b)'s punkt »en
   1939-person har linje og nr. fra placement, ikke `linje='1939'`«.
2. **Værdikædeled:** source record → (overskrift som observation) → placement (record og persona) → medlemskab;
   derefter relationer (5b-vejen) og narrativbinding for de records, der i dag er blokeret af manglende placement.
3. **Leverancetype:** generelle mekanismer (overskrifter som evidens, placement, medlemskab med flere grundlag,
   børneflok-reglen på placementkoordinater) plus en lille 1939-profil (overskriftsmønstre og linjeskema). Ingen
   editionsnavngiven permanent overflade.
4. **Værdi:** læseren ser 1939-personens plads i bogen (gren, slægtled, nr.) i stedet for det syntetiske
   `1939`/løbenummer; en person, begge udgaver placerer i samme linje, står som bekræftet af to kilder; 1939's
   ægteskaber og børneflokke kan bindes til bogen; de 13 1939-narrativer uden record-binding og de udskudte
   identitetsflytninger kan gennemføres.
5. **Færdigbevis:** §8.
6. **Erstatter:** 1939's legacy-koordinater (`person_external_id.linje='1939'`, globale nr. 1-539 fra
   `convert_1939_stamtavle.py`), `source_basis` som eneste grundlag pr. medlemskab, og børneflok-reglens læsning af
   legacy-koordinater.
7. **Review-budget:** som i hovedet.

## 2. Målt udgangspunkt

Målt på stand-in `daa5ab_ddl_standin_20261108164526_c3h` (prods indhold fra før 6c-3's data; 6c-3 rørte kun
2018-20's private tabeller, så 1939-tallene gælder for prod), kun antal. Skal genmåles i plan-Task 0.

- **Records (kilde 3):** 592 source records: 349 `person`, 72 `marriage`, 101 `fact`, 62 `relationship`, 6
  `structural_context`, 2 `cross_reference`. Postnøglerne er uuid'er (2018-20: `I-131` osv.).
- **Personas og identitet:** 563 source personas (555 fra 6b + 8 fra C3), 560 med accepteret identitet, 1
  `unresolved` (kort 122).
- **Overskrifter:** **0** `header_*`-observationer for kilde 3 (2018-20: 5 `header_linje`, 61 `header_slaegtled`,
  99 `header_kuld`, 101 `header_aegteskab`). Placement-writeren kræver en overskrift
  (`EVIDENCE_PLACEMENT_HEADER_REQUIRED`, `schema.sql:2413`). Renditionens tekst ligger ikke i basen (kun
  `content_sha256`); overskrifterne mellem posterne findes kun i arbejdsmappen. De 6 `structural_context`-records
  er overskriftslignende (»Børn: Tredje Slægtled I.«, »Sønner: V«, en indledning til en gren). I posternes egen tekst
  optræder »Slægtled« med ordtal 4 gange, »Gren« 2 gange. **1939 er bygget op om grene og slægtled, ikke om linjer
  I-V** (plan-1939 A3c: gruppe-for-gruppe nummerering; løbenumrene er gruppe-lokale, 22 distinkte).
- **Linjeskema:** kilde 3 har ét `lineage_scheme` (stamtavle) med én entry, `VI` »Den fyenske Linje«, mappet til
  lineage 7 (kilde 3's egen). 2018-20's skema har 5 entries (I-V).
- **Legacy-koordinater (kilde 3):** 576 `person_external_id`: 542 `linje='1939'` (globale nr.), 26 `VI`, 8 uden
  linje; ingen `kuld`/`slaegtled_lokal`. Alle `retained_legacy` i ledgeren.
- **Placements:** 0 for kilde 3 (2018-20: 580 placements, 576 memberships efter 5c-1).
- **Medlemskab og B6-potentiale:** 576 `person_lineage_membership` og 576 `person_slaegt_membership`, alle med
  2018-20 som grundlag. Af de 560 kanoniske mål for 1939's identiteter har **0** selv et medlemskab, men **458** har
  et gennem deres `samme_som`-komponent (`public._samme_som_gruppe`). Ca. 102 1939-personer står alene.
- **Relationsforslag (kilde 3, fra 6c-1):** 271 `relation.marriage`, 6 `relation.parent`, 4 `relation.child`, alle
  `proposed`. 2018-20's relationsvej (5b) er ikke kørt på 1939.
- **Narrativvejen:** decisions 2026-11-02 og 2026-11-07 (målt i prod) siger, at narrativflytninger og de 13
  1939-narrativer uden record-binding kræver accepterede placements; cutover-inventaret tæller en record uden præcis
  én accepteret identitet via accepteret record- og persona-placement som blokeret
  (`private.apply_narrative_record_cutover`, `schema.sql:13973`). Præcis hvilken writer der afviser, kortlægges i
  6d-2's spec.
- **Medlemskabets form i dag:** PK `(person_id, lineage_id)`, ét `source_basis jsonb`; `red_promote_placement_memberships`
  (`schema.sql:3102`) overskriver grundlaget ved konflikt (`ON CONFLICT`), og `placement_membership_set` giver
  `conflict`, hvis en anden placement ejer medlemskabet.
- **Børneflok-reglen:** `private.relation_child_rule` (`schema.sql:18310`, regel `relation-child-v1`) kræver én
  `person_external_id` med linje for hovedpersonen og sammenligner børnenes `linje/nr/kuld/slaegtled` fra
  `person_external_id` (`:18327-18383`), dvs. 1939's syntetiske koordinater.
- **`samme_som`:** `public._samme_som_gruppe(bigint)` (`schema.sql:7718`) giver hele komponenten (rekursiv,
  uorienteret, intet statusfilter), INVOKER, EXECUTE frataget alle API-roller (`:7730`). Bruges i dag kun i guards.

## 3. Opdeling (*mit valg*)

Trin 6-specens §5 giver 6d en intern rækkefølge: (1) linjeskema, (2) placements, (3) relationer, (4) binding og
medlemskab med B6. Jeg deler 6d i tre dele, der hver går i prod for sig (5c-1-formen), og flytter medlemskab/B6 op
før relationerne. Begrundelse: færdigbevis (c) afhænger kun af placement og medlemskab; relationerne og narrativerne
afhænger af placements, men ikke af hinanden. Grænserne må justeres i delspec'erne (§5 i trin 6-specen); opdelingen
registreres i `docs/decisions.md` ved godkendelse, som 6c's.

| Del | Indhold | Afhænger af |
|---|---|---|
| **6d-1 — overskrifter, placement og medlemskab** | 1939's overskrifter som observationer (1939-profil til `build_header_manifest.py`); 1939's linjeskema og mapping til slægtslinjer; record- og persona-placements med bogens egne numre; ledger-disposition af de 576 legacy-rækker; medlemskab med flere grundlag og B6 | — |
| **6d-2 — narrativer og identitetsflytninger** | De 13 1939-narrativer uden record-binding (læst efter spor B), kort 122 og `P <id>`-flytningerne fra 6c-2, de 39 tekstrettelser uden læsertekst (decisions 2026-11-07) | 6d-1 |
| **6d-3 — relationer** | 5b-vejen på 1939: 271 ægteskaber, 6 forældre, 4 børn; børneflok-reglen på placementkoordinater; familieopslag og partsvalidering gennem afklarede `samme_som`; I-11's nye ægteskab (2018-20, decisions 2026-11-08) | 6d-1 |

6d-2 og 6d-3 får hver deres korte spec, når 6d-1 er i prod og har målt, hvad de bygger på. Resten af denne spec er
6d-1, med 6d-2 og 6d-3 som afgrænsning (§7).

## 4. Mål, ikke-mål og anti-mål (6d-1)

**Mål**

- Hver 1939-post med en hovedperson har en accepteret record-placement med bogens egne koordinater (gren/linje,
  slægtled, gruppe, løbenummer), og hovedpersonens persona har en accepteret persona-placement.
- 1939's grene og grupper er mappet til slægtslinjer i 1939's `lineage_scheme`; hvor en gren svarer til en
  eksisterende slægtslinje, er mappingen `canonical` eller `historical_alias`.
- Et medlemskab kan have flere kildegrundlag; en 1939-placement i samme slægtslinje som et eksisterende medlemskab i
  personens `samme_som`-komponent bekræfter det (`corroborated`) i stedet for at give konflikt.
- Alle 576 legacy-rækker for kilde 3 har en disposition (`mapped` eller `retained_legacy` med grund).
- Læseren (`public_person_source_coordinates`) viser 1939-koordinater fra placement for de placerede personer.

**Ikke-mål**

- Nye slægtslinjer, personer, familier eller medlemskaber uden en eksisterende person (opret-benet, B4). Kræver en
  1939-gren en ny linje, parkeres den synligt (trin 6-specen §6 pkt. 8).
- At sammenligne 1939's numre med 2018-20's (gruppe-lokale, trin 6-specen §6 pkt. 3).
- Relationer, narrativer og identitetsflytninger (6d-2, 6d-3). Læserens udgavevælger (6e).
- At ændre 2018-20's placements, medlemskaber eller koordinater.

**Anti-mål**

- Et 1939-grundlag overskriver eller fjerner 2018-20's grundlag for et medlemskab (i dag gør `ON CONFLICT` det).
- 2018-20-læseren ændrer sig for personer, 1939 ikke placerer anderledes.
- En ny 1939-specifik placement-writer eller -tabel ved siden af 5c-1's.
- Projektejeren skal placere hundredvis af poster i hånden.
- Personsiden bliver langsommere end anons grænse efter medlemskabsjoinet.

## 5. Design (6d-1)

### 5.1 Overskrifter som evidens

1939 har ingen overskrifts-observationer. *Mit valg:* `build_header_manifest.py` (5c-1's generelle værktøj) får en
1939-profil: profilen deklarerer overskriftsmønstrene (gren, slægtled med ordtal, gruppeoverskrifter af formen
»<Navn>s Børn [m. <Navn>]«/»Børn: <ordtal> Slægtled <romertal>.«) og den »nærmeste foregående«-regel. Overskrifterne
skrives som ankrede observationer på renditionen gennem den eksisterende observations-writer, med nye
`observation_kind`-værdier i `vocab`, hvis de nuværende (`header_linje`, `header_slaegtled`, `header_kuld`,
`header_aegteskab`) ikke dækker gren og gruppe. Værktøjet kører deterministisk og lokalt, aldrig gennem en model,
og printer kun antal, nøgler og hashes (invariant 8).

Om de 6 `structural_context`-records kan bruges som overskrift, eller overskrifterne skal være nye observationer,
afgøres af Task 0's måling.

### 5.2 Linjeskema og mapping

1939's `lineage_scheme` (stamtavle) får en entry pr. gren/gruppe på det niveau, bogen bruger som »linje«, med bogens
egen label. Hver entry mappes i `lineage_scheme_entry_lineage` til en eksisterende slægtslinje (`canonical` eller
`historical_alias`) eller til en kilde 3-linje (`source_only`, som VI i dag). Mappingen er en redaktionel afgørelse:
projektejeren får et lille ark med forslag (forudfyldt ud fra, hvilke 2018-20-linjer de placerede personers
`samme_som`-modparter er medlem af, med fordeling og afvigelser) og svarer pr. entry. En gren, der kun kan mappes til
en ny linje, parkeres med disposition (opret-benet).

### 5.3 Placements

Record-placements for 1939's poster skrives med 5c-1's writer (`write_record_placement`): `scheme_entry_id` fra
5.2, `header_observation_id` fra 5.1, `printed_number` = bogens løbenummer (gruppe-lokalt), `section_path` =
gren/slægtled/gruppe, `generation_label_raw` = bogens slægtledsbetegnelse. Unikhed gælder `section_path` +
nummer, aldrig nummeret alene. Persona-placements (`principal_member`) for hovedpersonens persona med
`write_persona_placement`. Afgørelser med 5c-1's kontrolform: maskinel accept, hvor overskrift, nummer og persona er
entydige; en blind stikprøve på 20 (`placement_control_sheet.py`) og alle tvetydige på kort (højst ~30 pr. ark,
trin 6-specen §3 (d)). Ledgeren (`legacy_placement_disposition`) får en disposition pr. legacy-række: `mapped`, når
en accepteret placement erstatter den, ellers `retained_legacy` med grund.

### 5.4 Medlemskab med flere grundlag (B6) — *mit valg*

Datamodellen (trin 6-specen §6 pkt. 3 overlader den til 6d): en ny privat grundlagstabel,
`private.membership_basis` (navn foreløbigt), med én række pr. kildegrundlag: medlemskabets nøgle (person, linje
eller slægt), `source_id`, persona-placement, identitetsversion, tilstandshash og tilstand (`current`/`stale`).
`source_basis jsonb` fryses som legacy-felt og skrives ikke længere af promotion.

Reglen pr. 1939-persona-placement (efter accepteret identitet og accepteret mapping):

- Komponenten (`_samme_som_gruppe` af personaens kanoniske mål) har et medlemskab i **samme** slægtslinje: tilføj
  et grundlag til det → medlemskabet er `corroborated` (to kilder). Ingen ny medlemskabsrække.
- Komponenten har et medlemskab i en **anden** linje: `conflict` til review; intet skrives.
- Komponenten har **intet** medlemskab (de ca. 102 enlige): nyt medlemskab på kilde 3-personrækken med ét grundlag.

Projektionen er gyldig, så længe mindst ét grundlag er `current`; mister et grundlag sin gyldighed (placement
ugyldig, `samme_som` trukket tilbage, identitet skiftet), bliver det `stale`, og medlemskabet går til review,
mens det andet grundlag står. `red_promote_placement_memberships`' overskrivning ved konflikt fjernes. Afvist
alternativ: et jsonb-array i `source_basis` (ingen FK, ingen validering pr. grundlag).

`_samme_som_gruppe` er INVOKER og frataget EXECUTE for API-rollerne; writeren er DEFINER og kan kalde den, men reglen skal
afklare, om »afklaret« `samme_som` kræver et statusfilter (funktionen har ingen i dag).

### 5.5 Læseren

`public_person_source_coordinates` (5c-2) viser placement, når personen har ét gældende medlemskab. Efter 5.4 skal
den vælge koordinater pr. kilde fra placement, også når medlemskabet har to grundlag, så begge udgavers koordinater
er læsbare hver for sig. Måles mod anons 3 s efter joinet (vej B-erfaringen). Udgavevælgeren er 6e.

### 5.6 Prod

Som 6c-3: generel DDL-blok i `schema.sql` og `db-migrations.sql` (byte-ens funktionskroppe, idempotent), privat
runner med fastlåste indholdsafledte værdier, generalprøve på en stand-in fra et frisk prod-dump, dump med ekstern
kopi før hver skrivende ceremoni, GO i projektejerens shell, vinduesvagten fra starten (memory
`vindues-vagt-ikke-kun-change-set`), fortrydelse = restore.

## 6. Projektejerens afgørelser i 6d-1

1. Mappingen af 1939's grene/grupper til slægtslinjer (5.2): ét lille ark.
2. Placementernes stikprøve (20 blinde) og de tvetydige (5.3): højst ~30 kort pr. ark.
3. Konflikter fra 5.4 (anden linje i komponenten): kort med begge udgavers placering.

## 7. 6d-2 og 6d-3 (afgrænsning, specificeres senere)

- **6d-2:** de 13 narrativer (færdigbevis fra decisions 2026-11-07: »de 13 har record-binding og er læst efter spor
  B«), kort 122 og `P <id>` (identitet `unresolved` med `ønsket_person_id`, narrativet flyttes med), de 39
  tekstrettelser (38 på 14 poster uden narrativ, 1 der kun må trækkes tilbage).
- **6d-3:** børneflok-reglen versioneres (`relation-child-v2`) til at læse placementkoordinater; 2018-20's
  eksisterende bindinger bliver på v1. 1939's børnehenvisninger er gruppe-lokale (»N Børn: Tredje Slægtled I.«), så
  parseren får en profil. Familieopslag og partsvalidering følger afklarede `samme_som`. Ægtefælle-matcheren
  (memory: partneren var ikke i top 10 i 5/5 sager) og den ustabile modelkørsel (decisions 2026-11-08) er kendte
  risici. Værktøjsnoterne fra 6c-3's kortrunde (forælder-HTML m.fl.) bygges her.

## 8. Færdigbevis (6d-1)

- **Placement:** antal 1939-poster med accepteret record-placement og persona-placement; antal uden, hver med
  disposition; 0 placements uden overskrift.
- **Ledger:** alle 576 legacy-rækker for kilde 3 har disposition; antal `mapped`/`retained_legacy`.
- **B6 (trin 6 færdigbevis c):** antal medlemskaber med to `current` grundlag (`corroborated`), antal nye med ét
  1939-grundlag, antal konflikter; mindst ét `corroborated` vist i læseren.
- **2018-20 uændret:** 2018-20's placements, grundlag og koordinater er byte-ens før og efter (hash).
- **Læseren som anon:** en 1939-person viser bogens gren/slægtled/nr. fra placement, ikke `1939`/løbenummer;
  personsiden for de tungeste personer under anons grænse med margen.
- **Status:** rækken »Placement og membership (5c-1)« for 1939 hæves til `produktionsverificeret`.

## 9. Åbne spørgsmål til projektejeren

1. **Opdelingen:** godkender du 6d-1/6d-2/6d-3 og at medlemskab/B6 rykker før relationerne?
2. **Hvad er »linje« i 1939?** Bogen er bygget af grene og slægtled. Skal en 1939-gren (fx den holstenske, den
   meklenborgske) være entry i linjeskemaet, eller et finere niveau (gruppe)? Mit forslag: gren, og gruppe/slægtled
   i `section_path`. Task 0 viser fordelingen.
3. **B6-reglen:** skal en 1939-placement i samme slægtslinje bekræfte et 2018-20-medlemskab automatisk, eller vil du
   se en stikprøve først?
4. **De ca. 102 enlige 1939-personer:** nyt medlemskab på kilde 3-rækken (mit forslag), eller kun placement uden
   medlemskab?

## 10. Plan-Task 0 (måling før planen låses)

På en frisk stand-in fra et prod-dump, og lokalt over renditionens tekst med et deterministisk script (stdout og
stderr til fil, kun antal og strukturelle labels, aldrig prosa; memory `pii-probe-omdiriger-begge-streams`):
antal overskrifter pr. mønster og niveau; de distinkte gren-/slægtled-/gruppelabels; hvor mange af de 349
person-poster der får en nærmeste foregående overskrift; unikhed af `section_path` + nummer; om de 6
`structural_context`-records dækker nogle af overskrifterne; fordelingen af `samme_som`-modparternes 2018-20-linjer
pr. 1939-gren (grundlag for mapping-arket); `public_person_source_coordinates`' tid som anon for de tungeste personer.
