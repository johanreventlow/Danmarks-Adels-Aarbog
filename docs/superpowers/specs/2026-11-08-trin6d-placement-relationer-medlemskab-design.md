# Delspec 6d — placement, relationer og medlemskab for 1939

**Status:** godkendt af projektejeren 2026-11-08 (§9 pkt. 1-2 ja). Fable-review samme dag (§11: NO-GO, 10 fund,
indarbejdet). B6-modellen er afgjort af projektejeren (afledt bekræftelse, decisions 2026-11-08). Mine valg er
markeret *mit valg*.
**Overordnet spec:** `docs/superpowers/specs/2026-10-29-trin6-1939-gennem-kaeden-design.md` §5 (6d), §6 pkt. 3 (B6)
og pkt. 8 (hvor 1939 hører hjemme), §8 (færdigbevis b og c).
**Forudgående mekanisme:** 5c-1 (`docs/superpowers/specs/2026-10-26-trin5c-placement-membership-design.md`), 5b
(`2026-10-06-trin5b-relationspersonas-design.md` og 2a/2b-i/2b-ii/2b-iii), 5c-2 (læserne).
**Review-budget (B13):** 1 Codex-runde (`gpt-6.1-sol`) på spec+plan for 6d-1 og 1 på diffen før prod; Opus afvejer
hvert fund. Overskredet med én Fable-læsning af udkastet (projektejerens anmodning; decisions 2026-11-08). 6d-2 og
6d-3 får hver deres eget budget i deres spec.

## 1. Roadmap-kobling

1. **Roadmapmål:** trin 6, færdigbevis (a) for placement og (c): »et medlemskab kan bæres af to kilder — en anden
   kildes placement bekræfter (`corroborated`) i stedet for at give konflikt« (B6), her i den afledte form (§5.4).
2. **Værdikædeled:** source record → overskrift som observation → placement (record og persona) → medlemskab;
   derefter (6d-2/6d-3) narrativbinding for de records, der mangler persona eller placement, og relationer.
3. **Leverancetype:** generelle mekanismer (overskriftsscanner styret af profil, ledger-kobling via identitet, afledt
   komponenttilstand for medlemskab) plus en lille 1939-profil (overskriftsmønstre, linjeskema). Ingen
   editionsnavngiven permanent overflade.
4. **Værdi:** 1939-personerne får bogens egne koordinater (gren, slægtled, gruppe, løbenummer) som evidens i stedet
   for det syntetiske `1939`/løbenummer; en person, begge udgaver placerer i samme linje, står som bekræftet af to
   kilder; 6d-2 og 6d-3 (narrativer, identitetsflytninger, børneflokke) får det, de mangler. Læseren viser
   koordinaterne i 6e.
5. **Færdigbevis:** §8.
6. **Erstatter:** 1939's legacy-koordinater (`person_external_id.linje='1939'`, globale nr. 1-539 fra
   `convert_1939_stamtavle.py`) som eneste placering; ledgeren går fra `retained_legacy` til `mapped`.
7. **Review-budget:** som i hovedet.

## 2. Målt udgangspunkt

Målt på stand-in `daa5ab_ddl_standin_20261108164526_c3h` (prods indhold fra før 6c-3's data; 6c-3 rørte kun
2018-20's private tabeller, så 1939-tallene gælder for prod) og efterprøvet af Fable-reviewet. Kun antal. Genmåles i
plan-Task 0.

- **Records (kilde 3):** 592 source records: 349 `person`, 72 `marriage`, 101 `fact`, 62 `relationship`, 6
  `structural_context`, 2 `cross_reference`. Postnøglerne er præfiks + uuid. Records har 1-5 ankrede forekomster
  (178 med 2, 57 med 3+); placement-validatoren bruger den tidligste (`schema.sql:2404`).
- **Personas og identitet:** 563 source personas: 560 med accepteret identitet, 1 `unresolved` (kort 122), 2 uden
  identitetsrække. 328 sidder på `person`-records, 235 på `fact`/`marriage`/`relationship`-records (præcis én
  persona hver). **21 `person`-records har ingen persona**; det er de samme 21, der ikke har en publiceringsbinding.
  Alle 560 kanoniske mål er kilde 3-personrækker.
- **Narrativpublicering:** 563 `published` bindinger for kilde 3. `narrative_publication_state` (`schema.sql:14374`)
  medtager placements i provenansen (`:14457-14472`), så en accepteret record- og persona-placement gør bindingen
  `stale_published`, som i 5c-1 (§4.5 der: 498 revalideret i samme transaktion med
  `red_revalider_person_narrative_record`, `:15764`).
- **Overskrifter:** **0** `header_*`-observationer for kilde 3 (2018-20: 5 `header_linje`, 61 `header_slaegtled`,
  99 `header_kuld`, 101 `header_aegteskab`). Overskriftstyperne er hardkodet fire steder: vocab (`:613`),
  placement-validatoren, der som overskrift for en placement kun accepterer en uankret `header_linje` før posten
  (`:2393-2411`), `placement_header_violations`' niveautabel (`:2725`) og `write_header_evidence` (`:2847`).
  Renditionens tekst ligger ikke i basen (kun `content_sha256`); overskrifterne mellem posterne findes kun i
  arbejdsmappen. De 6 `structural_context`-records kan ikke bruges som overskrift: de er ankrede og har en anden type.
  `build_header_manifest.py`'s profil rummer kun `raw_text_sha256` og `entry_codes` (`:327`); grammatikken er
  `segment.py`'s regexer. **1939 er bygget op om grene og slægtled, ikke linjerne I-V** (plan-1939 A3c:
  gruppe-for-gruppe nummerering; løbenumrene er gruppe-lokale, 22 distinkte).
- **Linjeskema:** kilde 3 har ét `lineage_scheme` (stamtavle) med én entry, `VI` »Den fyenske Linje«, mappet
  `canonical` til lineage 7 (kilde 3's egen). `lineage_of_entry` kræver præcis én `canonical` pr. entry
  (`:2993-2995`), ellers `PLACEMENT_ENTRY_LINEAGE_INVALID` for hele kilden. 2018-20's skema har 5 entries (I-V).
- **Legacy-koordinater og ledger:** 576 `person_external_id` for kilde 3: 542 `linje='1939'` (globale nr.), 26 `VI`,
  8 uden linje; ingen `kuld`/`slaegtled_lokal`. Alle `retained_legacy`. `record_legacy_disposition` kan kun give
  `mapped`, når `source_record.record_key` = `person_external_id.record_key` (`:2967-2973`); det gælder **8 af 576**
  (C3's records).
- **Placements:** 0 for kilde 3 (2018-20: 580 placements, 576 memberships efter 5c-1).
- **Medlemskab:** 576 `person_lineage_membership` og 576 `person_slaegt_membership`, alle på 2018-20-rækker. Af de 560
  kanoniske mål for 1939's identiteter har **0** selv et medlemskab, og **458** har et i deres `samme_som`-komponent.
  2 komponenter har medlemskaber i to linjer; ca. 10 komponenter med flere personer har intet medlemskab; 92 1939-
  personer står helt alene. `placement_membership_set` tjekker konflikt på det rå `person_id` (`:3063-3075`), så en
  1939-persona på en kilde 3-række er `eligible` i dag.
- **`samme_som`:** 719 relationer, alle med `afklaret` konklusion, konfidens NULL. `public._samme_som_gruppe`
  (`:7718`) har intet statusfilter, INVOKER, EXECUTE frataget API-rollerne (`:7730`).
- **Relationsforslag (kilde 3, fra 6c-1):** 271 `relation.marriage`, 6 `relation.parent`, 4 `relation.child`, alle
  `proposed`. Børneflok-reglen (`relation_child_rule`, `:18310`, `relation-child-v1`) læser `person_external_id`'s
  `linje/nr/kuld/slaegtled` (`:18327-18383`), dvs. 1939's syntetiske koordinater.
- **Læseren:** `public_person_source_coordinates` returnerer linjekode, nr., slægtled, kuld, ikke `section_path`;
  hele RPC'en tager 354 ms på stand-in (prod-forhold ukendt).

## 3. Opdeling (*mit valg*)

Trin 6-specens §5 giver 6d en intern rækkefølge: (1) linjeskema, (2) placements, (3) relationer, (4) binding og
medlemskab med B6. Jeg deler 6d i tre dele, der hver går i prod for sig (5c-1-formen), og rykker medlemskab/B6 op
før relationerne, fordi færdigbevis (c) kun afhænger af placement og medlemskab. Grænserne må justeres i
delspec'erne (trin 6-specen §5); opdelingen registreres i `docs/decisions.md` ved godkendelse, som 6c's.

| Del | Indhold | Afhænger af |
|---|---|---|
| **6d-1 — overskrifter, placement og medlemskab** | 1939's overskrifter som observationer; linjeskema og mapping; record- og persona-placements med bogens egne koordinater; revalidering af de berørte publiceringer; ledger-disposition af de 576 legacy-rækker; medlemskab på 1939-rækkerne og den afledte B6-tilstand | — |
| **6d-2 — narrativer og identitetsflytninger** | Personas og identitet for de 21 records uden (6b-vejen); de 13 narrativer uden record-binding (læst efter spor B); kort 122 og `P <id>`-flytningerne fra 6c-2; de 39 tekstrettelser uden læsertekst (decisions 2026-11-07) | 6d-1; 6b-indgangen for de 21 |
| **6d-3 — relationer** | 5b-vejen på 1939: 271 ægteskaber og 6 forældre (kræver ikke placement); 4 børn og børneflokke med `relation-child-v2` på placementkoordinater (kræver 6d-1); familieopslag og partsvalidering gennem afklarede `samme_som`; I-11's nye ægteskab (2018-20, decisions 2026-11-08) | 6d-1 for børnene |

6d-2 og 6d-3 får hver deres korte spec, når 6d-1 er i prod. Resten af denne spec er 6d-1; 6d-2 og 6d-3 er afgrænset
i §7. Koordinaterne i læseren (gruppe/sektion, udgavevælger) hører til 6e (trin 6-specen §5).

## 4. Mål, ikke-mål og anti-mål (6d-1)

**Mål**

- Hver kilde 3-record med en persona (563) har en accepteret record-placement med bogens egne koordinater (gren som
  linje, slægtled, gruppe, løbenummer), og personaen en accepteret persona-placement. De 21 persona-løse
  `person`-records får record-placement, hvor overskriften er entydig, men ingen persona-placement og intet
  medlemskab (6d-2).
- 1939's grene er entries i 1939's `lineage_scheme`, hver med præcis én `canonical` slægtslinje.
- De publiceringer, placementerne gør `stale_published`, revalideres i samme transaktion; 0 stale før og efter.
- Hver placeret 1939-person med accepteret identitet får medlemskab på sin kilde 3-række; komponenttilstanden
  (`corroborated`/`conflict`/`single`) kan læses for hver komponent.
- Alle 576 legacy-rækker for kilde 3 har en disposition; `mapped`, hvor en accepteret placement via identitet
  erstatter rækken.

**Ikke-mål**

- Nye slægtslinjer, personer, familier eller relationer (opret-benet, B4). Kræver en 1939-gren en ny linje, parkeres
  den synligt (trin 6-specen §6 pkt. 8).
- At sammenligne 1939's numre med 2018-20's (gruppe-lokale, trin 6-specen §6 pkt. 3).
- Relationer, narrativer, identitetsflytninger (6d-2, 6d-3); læserens visning af koordinaterne og udgavevælgeren (6e).
- At ændre 2018-20's placements, medlemskaber, koordinater eller publiceringer.

**Anti-mål**

- Et 1939-medlemskab overskriver eller fjerner et 2018-20-medlemskab.
- 2018-20-læseren ændrer sig: `public_person_source_coordinates` og personsiden for 2018-20-rækker er byte-ens før og
  efter (5c-2-formen).
- En ny 1939-specifik placement-writer, -tabel eller overskriftstype ved siden af 5c-1's.
- Projektejeren skal placere hundredvis af poster i hånden.
- En publicering står `stale_published`, efter ceremonien er færdig.

## 5. Design (6d-1)

### 5.1 Overskrifter som evidens

*Mit valg:* ingen nye overskriftstyper. 1939's niveauer mappes til de eksisterende: gren → `header_linje`, slægtled →
`header_slaegtled`, gruppe (»<Navn>s Børn [m. <Navn>]«, »Børn: <ordtal> Slægtled <romertal>.«) → `header_kuld`.
`header_aegteskab` bruges kun, hvis bogen har ægteskabsoverskrifter. Placementens `header_observation_id` er grenens
`header_linje` (validatorens krav); slægtled og gruppe er overskrifts-evidens for `generation_*` og `section_path` og
kontrolleres med `placement_header_violations`. Hvis grenen ikke har en overskrift før hver post i renditionen,
kræver validatoren en ændring: det afgøres af Task 0.

**Overskrifternes kilde (Gate A, 2026-11-08):** Calamari-renditionen, som records er forankret i, har mistet
centreringen (segment.py finder 5 linjer, 5 slægtled, 0 gruppe-romertal; raw.txt 6, 48, 75). raw.txt er derfor guide og
kontrol: hver af dens overskrifter søges i Calamari mellem samme naboposter og skrives som uankret observation på
Calamari-renditionen, hvor den genfindes (målt: linje 6/6, stamme 2/2, slægtled 44/48, beskrivelser 68/77, romertal
29/75; en gruppe er genfundet via romertal eller beskrivelse). Ikke genfundne → kort. Validatoren ændres ikke.
Stammens 2 sektioner bliver entries. `docs/decisions.md` 2026-11-08.

`build_header_manifest.py` får en **overskriftsscanner styret af profil**: profilen deklarerer mønstrene pr. niveau
(regexer, ordtal) og »nærmeste foregående«-reglen; 2018-20's nuværende grammatik flyttes ind i 2018-20's profil
uændret (byte-ens manifest som test). Det er ny kode i et generelt værktøj, ikke kun en profil. Scanneren kører
deterministisk og lokalt over renditionens tekst, aldrig gennem en model, og printer kun antal, nøgler og hashes
(invariant 8). Overskrifterne skrives med `write_header_evidence` som uankrede observationer på renditionen.

### 5.2 Linjeskema og mapping

1939's `lineage_scheme` får en entry pr. gren med bogens label. Hver entry får præcis én `canonical`-mapping: til en
eksisterende slægtslinje, hvor grenen er den samme linje, eller til en kilde 3-linje som VI (lineage 7). Andre
2018-20-linjer, en gren svarer til historisk, kan tilføjes som `historical_alias` ved siden af. Mappingen er en
redaktionel afgørelse på et lille ark: forudfyldt ud fra, hvilke 2018-20-linjer de placerede personers
`samme_som`-modparter er medlem af (fordeling og afvigelser pr. gren). En gren, der kun kan mappes til en ny,
ikke-eksisterende linje, parkeres med disposition (opret-benet).

### 5.3 Placements

Record-placements skrives med `write_record_placement`: `scheme_entry_id` fra 5.2, `header_observation_id` fra 5.1,
`printed_number` = bogens løbenummer, `section_path` = gren/slægtled/gruppe, `generation_label_raw` = bogens
slægtledsbetegnelse. Unikhed gælder `section_path` + nummer, aldrig nummeret alene. Den tidligste forekomst bestemmer
overskriften (validatoren). Persona-placements (`principal_member`) med `write_persona_placement`.

**Maskinel accept** kræver 1939-invarianter, da 5c-1's legacy-enighed ikke findes (1939-legacy har ingen slægtled
eller kuld): fortløbende løbenumre inden for hver gruppe; slægtledsordinaler, der vokser monotont inden for en gren;
hver gruppe har én overskrift; krydstjek mod de eksisterende `family_member`-rækker (en gruppes børn har samme
forældrefamilie). Brud → kort. Desuden en blind stikprøve på 20 (`placement_control_sheet.py`), højst ~30 kort pr.
ark (trin 6-specen §3 (d)).

**Revalidering:** hver publicering, der bliver `stale_published`, revalideres i samme transaktion som placementerne
accepteres, med 5c-1's blok (§4.5 der: `red_revalider_person_narrative_record`, `\gexec`, GUC-rydning,
`SET LOCAL statement_timeout`). Forbetingelse: identitetspersonen = bindingens person for hver berørt publicering.
Efterbetingelse: 0 `stale_published` for kilde 3. Ceremonien kører under sin egen `SET LOCAL statement_timeout='15min'`
(som 5c-1 i prod); generalprøvens langsomste sætning × prod/stand-in-forholdet skal ligge under 15 min. Prods
2-minuttersgrænse gælder læserne (Codex r1 #5).

**Ledger:** `record_legacy_disposition` udvides generelt: `mapped` er også gyldig, når legacy-rækkens person er det
accepterede kanoniske mål for en persona med accepteret persona-placement på placementens record (koblingen via
identitet, ikke postnøgle). Ellers `retained_legacy` med grund.

### 5.4 Medlemskab og afledt B6 (projektejerens valg 2026-11-08)

Hver udgave giver sin egen personrække et medlemskab, som 5c-1 gør i dag: en placeret 1939-persona med accepteret
identitet får medlemskab på sin kilde 3-række gennem 5c-1's `placement_membership_set` og
`red_promote_placement_memberships`. Medlemskabstabellerne og `source_basis` ændres ikke. Den eneste ændring i
promotionen er en vagt: `ON CONFLICT` må aldrig overskrive et medlemskab med et grundlag fra en anden kilde
(fejl i stedet).

**B6 afledes på komponentniveau.** En ny læse-kun funktion (navn foreløbigt `membership_component_state(person)`)
samler medlemskaberne i personens `samme_som`-komponent, kun gennem `samme_som`-relationer med `afklaret` konklusion:

- `corroborated`: mindst to kilder placerer komponenten i samme slægtslinje, ingen i en anden;
- `conflict`: kilderne placerer komponenten i forskellige slægtslinjer (inkl. de 2 eksisterende komponenter med to
  linjer) → review, intet ændres;
- `single`: kun én kilde.

To 1939-personas i samme komponent (en `samme_som` mellem to 1939-rækker) giver to 1939-medlemskaber; det vises som
fund, ikke som bekræftelse (bekræftelse kræver to kilder). Fortrydelse sker pr. række med 5c-1's
`red_reverse_placement_membership`; tilstanden genberegnes. Dette er en afvigelse fra trin 6-specens §6 pkt. 3 (»flere
kildegrundlag pr. medlemskab«) og registreres i decisions (2026-11-08).

### 5.5 Prod

Som 6c-3: generel DDL-blok i `schema.sql` og `db-migrations.sql` (byte-ens funktionskroppe, idempotent):
ledger-koblingen via identitet, `ON CONFLICT`-vagten, `membership_component_state`, eventuel validator-ændring fra
5.1. Privat runner med fastlåste indholdsafledte værdier, generalprøve på en stand-in fra et frisk prod-dump, dump med
ekstern kopi før hver skrivende ceremoni, GO i projektejerens shell, vinduesvagten fra starten (memory
`vindues-vagt-ikke-kun-change-set`), fortrydelse = restore. Placements, revalidering og medlemskab i samme
data-ceremoni, så læseren aldrig ser `stale_published`.

## 6. Projektejerens afgørelser i 6d-1

1. Mappingen af 1939's grene til slægtslinjer (5.2): ét lille ark.
2. Placementernes stikprøve (20 blinde) og invariantbrud (5.3): højst ~30 kort pr. ark.
3. `conflict`-komponenter (5.4): kort med begge udgavers placering.

## 7. 6d-2 og 6d-3 (afgrænsning, specificeres senere)

- **6d-2:** først personas og identitet for de 21 persona-løse records (6b-vejen); `narrative_publication_state` finder
  identitet gennem persona-placements (`:14485-14499`) og blokerer ellers (`NARRATIVE_RECORD_IDENTITY_REQUIRED`,
  `:14610`). Så de 13 narrativer (færdigbevis fra decisions 2026-11-07: »de 13 har record-binding og er læst efter
  spor B«; ingen af deres subjekter har i dag en 1939-identitet), kort 122 og `P <id>` (identitet `unresolved` med
  `ønsket_person_id`, narrativet flyttes med), de 39 tekstrettelser (38 på 14 poster uden narrativ, 1 der kun må
  trækkes tilbage).
- **6d-3:** ægteskaber og forældre kan køre uafhængigt af 6d-1; børneflok-reglen versioneres (`relation-child-v2`)
  til at læse placementkoordinater, og 2018-20's eksisterende bindinger bliver på v1. 1939's børnehenvisninger er
  gruppe-lokale, så parseren får en profil. Familieopslag og partsvalidering følger afklarede `samme_som`.
  Ægtefælle-matcheren (memory: partneren var ikke i top 10 i 5/5 sager) og den ustabile modelkørsel (decisions
  2026-11-08) er kendte risici. Værktøjsnoterne fra 6c-3's kortrunde bygges her.
- **6e:** læserens visning af 1939-koordinaterne fra placement, inkl. et sektionsfelt (gruppe), som
  `public_person_source_coordinates` ikke har i dag, og visningen af en komponents `corroborated`.

## 8. Færdigbevis (6d-1)

- **Placement:** antal kilde 3-records med accepteret record-placement og persona-placement (persona-placements =
  |nummereret post ∩ ikke parkeret gren ∩ accepteret placement ∩ accepteret identitet|, højst 534 — 29 personas
  sidder på records uden nummereret post, og de 3 uden accepteret identitet får kun record-placement; Gate A, Codex
  r1 #1); de 21 persona-løse og de 37
  records uden nummereret post med deres disposition; 0 placements uden overskrift; invariantbrud og kort talt.
- **Publiceringer:** 0 `stale_published` for kilde 3 før og efter; antal revalideret.
- **Ledger:** alle 576 legacy-rækker for kilde 3 har disposition; antal `mapped`/`retained_legacy`.
- **B6 (trin 6 færdigbevis c, afledt):** antal komponenter `corroborated`, `conflict`, `single`; mindst én
  `corroborated` vist med begge kilders medlemskab (SQL; læservisningen er 6e).
- **2018-20 uændret:** 2018-20's placements, medlemskaber og publiceringer byte-ens (hash), og
  `public_person_source_coordinates` for 2018-20-rækker byte-ens før og efter.
- **Tid:** `public_person_source_coordinates` og personsiden for de tungeste personer som anon under 3 s med margen.
- **Status:** rækken »Placement og membership (5c-1)« for 1939 hæves til `produktionsverificeret`.

## 9. Projektejerens afgørelser (2026-11-08)

1. **Opdelingen:** ja til 6d-1/6d-2/6d-3, og at medlemskab/B6 rykker før relationerne (decisions 2026-11-08).
2. **»Linje« i 1939:** grenen er entry i linjeskemaet; slægtled og gruppe står i `section_path`. Viser Task 0 en
   gren uden overskrift før posterne, kommer spørgsmålet tilbage til projektejeren før planen låses.
3. **Gate A efter Task 0 (ja til alle anbefalinger):** overskrifter guidet af raw.txt og forankret i Calamari (5.1);
   stammesektionerne er entries; 37 records uden nummereret post får ingen placement; læserens koordinat-RPC bruger kun
   placementkoordinater for en kilde med entydige `(entry, nummer)` (1939 vises som i dag indtil 6e; §8's
   2018-20-paritet suppleres med 1939-rækkernes hash, uændret, og en baseline af 2018-20-koordinaterne taget før DDL);
   persona-placements beregnet af manifestet (højst 534). `docs/decisions.md` 2026-11-08.

## 10. Plan-Task 0 (måling før planen låses)

På en frisk stand-in fra et prod-dump, og lokalt over renditionens tekst med et deterministisk script (stdout og
stderr til fil, kun antal og strukturelle labels, aldrig prosa; memory `pii-probe-omdiriger-begge-streams`):

- overskrifter pr. mønster og niveau; de distinkte gren-, slægtled- og gruppelabels;
- om hver af de 584 records' tidligste forekomst har en uankret gren-overskrift før sig (validatorens krav), og hvor
  den mangler;
- unikhed af `section_path` + nummer; de foreslåede invarianter (5.3) og deres brud;
- fordelingen af `samme_som`-modparternes 2018-20-linjer pr. gren (grundlag for mapping-arket) og
  komponenttilstandene, som 5.4 ville give;
- antal publiceringer, placementerne gør `stale_published`, og revalideringens tid;
- `public_person_source_coordinates`' tid som anon for de tungeste personer (prod-forhold fra `maal`).

## 11. Reviewlog

**Fable, 2026-11-08 (projektejerens anmodning; B13-overskridelse noteret i decisions):** NO-GO på første udkast,
10 fund. Påstandene om ledger (8/576), `canonical`-kravet, `header_linje`-kravet og de hardkodede typer efterprøvet
af mig i koden og på stand-in'en.

| # | Alvor | Fund | Afgørelse |
|---|---|---|---|
| 1 | KRITISK | Revalidering af 1939's 563 publiceringer mangler | nødvendig: 5c-1's blok i 5.3/5.5, 0 stale før/efter (§8) |
| 2 | KRITISK | B6 med grundlagstabel kolliderer med PK og fem forbrugere af `source_basis`; dublet på kilde 3-rækken; reversal | projektejerens valg: afledt bekræftelse (5.4); `ON CONFLICT`-vagt; decisions 2026-11-08 |
| 3 | KRITISK | Ledgerens `mapped` kun mulig for 8/576 | nødvendig: kobling via identitet (5.3) |
| 4 | HØJ | Overskrifter kræver DDL fire steder; `structural_context` ubrugelig; profilen har ingen mønstre | forenklet: eksisterende typer (5.1); scanneren er ny kode og siges sådan |
| 5 | HØJ | Læseren har intet sektionsfelt; 1939-koordinater i læseren er 6e | nødvendig: flyttet til 6e (§7), ude af §8 |
| 6 | HØJ | Dækning talt forkert (235 på fakta-/ægteskabsposter, 21 uden persona) | nødvendig: §2, §4, §8 rettet |
| 7 | HØJ | 6d-2 kræver 6b-indgang for 21 records | nødvendig: §3, §7 |
| 8 | HØJ | Præcis én `canonical` pr. entry; VI er `canonical` | nødvendig: 5.2 |
| 9 | MIDDEL | Maskinel accept uden 1939-invarianter; flere forekomster pr. record | nødvendig: invarianter i 5.3, tidligste forekomst |
| 10 | MIDDEL | `samme_som`-statusfilter; 6d-3's afhængighed overdrevet | nødvendig: filter i 5.4; §3 indsnævret |

**Codex `gpt-6.1-sol`, 2026-11-08 (B13-runden på spec+plan, efter Gate A):** NO-GO, 8 fund; Opus-dom, projektejeren ja
til alle 8.

| # | Alvor | Fund | Afgørelse |
|---|---|---|---|
| 1 | BLOKERENDE | 560 persona-placements uforeneligt med Gate A (29 personas uden nummereret post) | nødvendig: tallet beregnes af manifestet, højst 534 (§8) |
| 2 | BLOKERENDE | Parkeret gren kan ikke passere `lineage_of_entry` | nødvendig: ingen entry, records udelukkes, ledger `parkeret_gren` |
| 3 | HØJ | Koordinatunikhed afviser flere records i samme post | nødvendig: unikhed pr. fysisk post |
| 4 | HØJ | Forhåndstjek beskytter ikke mod samtidig promotion | forenklet: atomisk `ON CONFLICT … WHERE source_id`, ingen tosessionstest |
| 5 | HØJ | 15 min i ceremonien gør 2-minutsbeviset tomt | forenklet: 15 min (som 5c-1); generalprøven måler mod 15 min × forhold; 2 min gælder læserne (5.3) |
| 6 | MIDDEL | Fremmed-kilde-fejlen nås ikke (konflikt-stop først) | nødvendig: tjek fremmed kilde først |
| 7 | MIDDEL | Paritet tages efter DDL | nødvendig: baseline før DDL i målescriptet |
| 8 | MIDDEL | Kontrolarket kan ikke besvare beskrivelsesgrupper | forenklet: svar med romertal fra PDF, sammenlign med guidens romertal (kun kontrol) |
