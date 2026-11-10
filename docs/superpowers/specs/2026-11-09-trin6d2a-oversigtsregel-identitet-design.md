# Delspec 6d-2a — oversigtsreglen og 1939's resterende identitetssager

**Status:** godkendt af projektejeren 2026-11-09 (revision 3); revision 4 efter Codex-runden, projektejerens to valg
godkendt samme dag (§10). Brainstorm med projektejeren; to bygherre-tjek (Opus) på revision 1 og 2
(§10). Projektejeren delte 6d-2 i **6d-2a** (denne spec) og **6d-2b** (kildetekst og binding, §9). Projektejerens
afgørelser står i §3; mine valg er markeret *mit valg*.
**Overordnet spec:** `docs/superpowers/specs/2026-11-08-trin6d-placement-relationer-medlemskab-design.md` §3 og §7,
`2026-10-29-trin6-1939-gennem-kaeden-design.md` §5.
**Forudgående mekanismer:** 6d-1 (placements og medlemskab, i prod 2026-11-09; `private.membership_is_current`),
narrativvagten `public.person_daa_narrative_publication_allowed`, redaktionel `samme_som` (`red_samme_som`, trigger
`enforce_samme_som_invariants`), appens sammenlægning (`packages/core/src/collapseSameAs.ts`), 6c-2's kort 122.
**Review-budget (B13), *mit valg*:** 1 Codex-runde (`gpt-6.1-sol`) på spec+plan og 1 på diffen før prod; Opus afvejer
hvert fund. Bygherre-tjekkene tæller ikke med.

## 1. Roadmap-kobling

1. **Roadmapmål:** trin 6, færdigbevis (a): 1939's narrativer og publicering går gennem de samme operationer som
   2018-20 — her den del, der afgør, *hvilke* 1939-tekster læseren tilbydes som biografi.
2. **Værdikædeled:** identitet på tværs af personrækker (`samme_som`, persona-identitet) → biografilæser.
3. **Leverancetype:** én generel, afledt regel for biografiteksten (kildeparametriseret), én generel udvidelse af
   `samme_som`-skrivevejen (retningen afgøres af data) og tre redaktionelle identitetsafgørelser med eksisterende
   skriveveje. Ingen editionsnavngiven permanent overflade.
4. **Værdi:** læseren ser ikke længere bogens oversigtsstumper som ekstra biografier på en person, der har sin fulde
   post — heller ikke efter fremtidige koblinger; de sidste tre 1939-oversigtspersonas uden identitet afgøres.
5. **Færdigbevis:** §8.
6. **Erstatter:** visningen af 1939's oversigtsomtaler som biografi; den uafklarede identitet fra kort 122 og de to
   personas uden identitetsrække.
7. **Ændrer to tidligere beslutninger** (registreres i `docs/decisions.md`):
   - decisions 2026-11-07: 6d's færdigbevis for de 13 narrativer uden record-binding (»de 13 har record-binding og er
     læst efter spor B«). Oversigtsomtalerne blandt dem vises ikke; bindingen af de øvrige flyttes til 6d-2b.
   - decisions 2026-11-09 B: dubletterne skulle ryddes op ved redaktionel sammenlægning (identiteten peget om, den
     overflødige person udgår). Læservirkningen opnås nu med reglen; sammenlægningen bliver backlog (§3 pkt. 8).

## 2. Målt udgangspunkt

Målt 2026-11-09 på stand-in `daa5ab_ddl_standin_20261109142426_6d1c` (prod-dumpet `1653c8f7…` + 6d-1; dens `maal` er
byte-ens med prods `verify` efter 6d-1). Kun antal og id'er på personer/narrativer fra importen. Genmåles mod en frisk
prod-kopi i plan-Task 0 med §4.1's endelige definition.

- **1939's narrativer** (kilde 3, personer), efter om personen selv har et 1939-medlemskab og om dens afklarede
  `samme_som`-komponent har en *anden* person med et:

  | Selv medlem | Anden medlem | Synlig i dag | Antal |
  |---|---|---|---|
  | nej | nej | ja / nej | 32 / 6 |
  | nej | **ja** | ja / nej | **9** / 1 |
  | ja | ja | ja | 6 |
  | ja | nej | ja | 522 |

  Rækken *nej/ja* er reglens mængde: narrativerne for personerne 967, 974, 977, 978, 991, 992, 1013, 1017, 1021 og
  1802. 6 er bundet og publiceret (967, 978, 991, 992, 1017, 1021), 4 er ubundne (grandfathered eller ikke synlige).
  0 af de 10 har hændelser. For kilde 1 (2018-20) er mængden tom.
- **De fire »dubletpar«** (decisions 2026-11-09 B: 991↔995, 992↔996, 1017↔1071, 978↔1136) er allerede i samme
  afklarede komponent: begge er alias for samme 2018-20-person (94, 97, 25, 259); den placerede er 995/996/1071/1136.
  Ingen ny kobling er nødvendig.
- **1014** (»Bertram«, † 1666) står i samme oversigtslinje på PDF 504 som 1013 og er ukoblet. Kandidat: **1048**
  Bertram 1611-1666, placeret i 1939, alias for 2018-20-person 134.
- **Henning (1849):** ukoblet, eneste 1939-tekst på PDF 508; uden for reglen.
- **Oversigtspersonas uden accepteret identitet:** 1 `unresolved` (kort 122: persona på `record-5fc1a041…`;
  6c-2's kortsvar peger på **1054** Ditlev 1646-1690, placeret) og 2 personas *uden identitetsrække* (decisions
  2026-11-09 B: Ditlev †1664 og Cay Friedrich †1762). En `unresolved` identitet har `canonical_person_id IS NULL`
  (`schema.sql:1649`); ønsket person står i evidensen.
- **Appens sammenlægning:** den kanoniske person er komponentens entydige sink — her 2018-20-personen; alle
  publicerede tekster i komponenten vises som versioner på kortet.

## 3. Projektejerens afgørelser (brainstorm 2026-11-09)

1. **Læseren tilbydes ikke en oversigtsomtale** som biografi for en person, der har sin egen detaljepost. Grænsen
   trækkes **maskinelt**.
2. **Er oversigtens tekst den eneste tekst** om personen i udgaven (Henning), er den hans og vises.
3. **Skjult er ikke slettet:** teksten består som kildens udsagn og kan ses af redaktøren (invariant 1).
4. **Skjulningen sker automatisk,** også ved fremtidige ændringer — man kan ikke regne med manuel tilbagetrækning.
5. **Redaktøren vælger *om*, systemet vælger *retningen*,** når data kan afgøre den.
6. **Dubletter kobles i 6d-2a** (målingen viste, at kun 1014 mangler).
7. **6d-2 deles** i 6d-2a og 6d-2b; de tekster, der skal vises, bliver stående som i dag, til 6d-2b binder dem.
8. **Reglen i stedet for sammenlægningen:** dubletternes læservirkning løses af reglen; den redaktionelle
   sammenlægning fra decisions 2026-11-09 B (identitet peget om, person udgår) bliver backlog.
9. **Reglen skjuler kun biografiteksten:** fakta og hændelser beholder deres kildelinje til oversigtsposten (den er en
   gyldig kilde for de udsagn).
10. **De to personas uden identitet** (Ditlev †1664, Cay Friedrich †1762) afgøres i 6d-2a på kort som kort 122.

## 4. Design

### 4.1 Oversigtsreglen (generel, afledt, kildeparametriseret)

**Definition.** En kilde-*K*-narrativ for person *P* er en **oversigtsomtale**, når
- *P* ikke selv har et gældende linjemedlemskab med kildegrundlag *K* (`person_lineage_membership` med
  `source_basis.source_id = K` og `private.membership_is_current`), og
- *P*'s komponent (kun `samme_som` med `afklaret` konklusion, uanset retning) indeholder en *anden* person *Q*, der
  har et, **og** *Q* er offentlig (`entitet_offentlig`) og har en *K*-biografi, som læseren må se. *(Mit valg: ellers
  ville *P*'s tekst forsvinde uden erstatning — anti-målet i §5.)*
- Stien fra *P* til *Q* går kun gennem offentlige personer (*P* selv undtaget). *(Rev. 4, Codex-fund 8: anon ser kun
  relationer med offentlige endepunkter, så appen kan kun folde *P* ind i *Q*'s kort ad en offentlig sti.)*

*Q*'s egen *K*-narrativ kan aldrig selv være en oversigtsomtale (*Q* har medlemskabet, som *P* mangler), så reglen
kræver ingen rekursion over narrativer.

**Virkning (§3 pkt. 9).** En oversigtsomtale vises ikke som biografi: den udelades af biografilæseren
`public_person_bio_source_versions_v2` — under kontrakt v2 appens eneste vej til biografitekst
(`web/src/data/public.ts:231-246`, `mobile/src/data/load.ts:283`, `web/src/data/feedAux.ts`). **Narrativ-RLS ændres
ikke** *(rev. 4, projektejeren 2026-11-09)*: teksten er publiceret bogtekst og ikke hemmelig; reglen styrer, hvad der
præsenteres som biografi, ikke adgang. Et filter i RLS ville desuden skjule hændelser (`haendelse`-politikken kræver,
at narrativet er læsbart, `db-rls.sql:498`, `:593`) og koste tid pr. række. Kald, der kun bruger vagten til
*kildelinjer* på fakta og familier (`public_person_facts`, `public_family_sources`) og hændelsers synlighed, er
uændrede; faktalæsernes resultat er byte-ens før/efter. Narrativ, binding, record og publiceringshændelser ændres ikke
(§3 pkt. 3).

**Form (*mit valg*, rev. 4).** Reglen beregnes **live** i biografilæseren af én privat funktion over de forespurgte
personer — ingen gemt markering, ingen triggere. Den er dermed altid i takt med sine indgange (komponent, medlemskab,
offentlighed, publiceringsvagt) og automatisk reversibel. Billig forfiltrering uden funktionskald (*P* har en kant;
*Q* ≠ *P* i komponenten har en medlemskabsrække og en narrativ i *K*) før de dyre kald (`membership_is_current`,
`person_daa_narrative_publication_allowed`); ingen `MATERIALIZED`-CTE'er (de taber indeksene). *Begrundelse:* Task 0
målte live-beregningen for alle personer til ca. 135 ms med samme mængde (10), mens Codex-runden viste, at en gemt
markering kræver triggere på reglens fulde afhængighedslukning (placements, beslutninger, slægtsmedlemskab, hele
publiceringstilstanden) og en samtidighedskontrakt — kode, der kan blive forældet uden at nogen ser det.

**Tidsbudget** *(rev. 4, projektejeren 2026-11-09)*. Ingen af disse anon-kald må blive mere end 10 % langsommere end
målingen før DDL'en (median af 3, samme base): `public_person_bio_source_versions_v2` for den største personmængde,
feedet sender (`web/src/data/feedAux.ts`); `public_person_facts` og `public_family_sources` for de tungeste personer;
koordinat-RPC'en. At biografilæseren med alle personer og den direkte narrativlæsning allerede ligger omkring 3 s på
stand-in'en *før* 6d-2a, er backlog (`docs/decisions.md`), ikke en del af 6d-2a.

**Redaktøren** ser stadig teksten; *mit valg:* redaktørens narrativvisning får en markering af, at teksten er en
oversigtsomtale og derfor ikke vises som biografi (formen er bygherrens; den bruger samme funktion).

### 4.2 Retningen i `samme_som` (generel regel i skrivevejen)

*Mit valg* at udvide `red_samme_som`/`enforce_samme_som_invariants` frem for en ny vej. For en kobling mellem *A* og
*B*: har *B* et gældende linjemedlemskab med kildegrundlag *K*, og har *A* ikke et, men en accepteret persona-identitet
eller en `person_external_id`-række i *K*, foreslås *A* → *B* (*A* alias). Afviser de eksisterende vagter (G3 flere
sinks, G4 alias er allerede sink, cyklus) den retning, gælder redaktørens retning; afvises også den, afvises
koblingen som i dag. Kan data ikke afgøre retningen, gælder redaktørens. Målet er, at en oversigtsperson ikke bliver
det direkte mål for en detaljepersons kobling; komponentens sink (som appen viser) styres ikke af reglen, og
læservirkningen sikres af §4.1 uanset retning. **Idempotens** *(rev. 4, Codex-fund 12)*: findes kanten allerede i
én af de to retninger, returneres den uændret før retningsvalget (ingen ny audit eller evidens). Tests: begge retninger på et oversigts-/detaljepar, en
oversigtsperson, der allerede er alias for en 2018-20-person (G3-tilfældet), et 2018-20-par og et par uden placering
(uændret adfærd).

### 4.3 1014 (kort)

Projektejeren bekræfter på et kort med oversigtslinjen og kandidatens post, om 1014 er 1048. Ja → `samme_som`
1014 → 1048 (afklaret) gennem `red_samme_som`; 1014's tekst bliver en oversigtsomtale efter §4.1. Nej → 1014 står
som egen tekst (§3 pkt. 2). Kortformen følger memory `kortark-kraever-kontekst-html` og `menneske-gennemgang-token-fil`.

### 4.4 Tre oversigtspersonas uden accepteret identitet (kort)

Kort 122 (Ditlev †1690 → 1054) og de to personas uden identitetsrække (Ditlev †1664, Cay Friedrich †1762): hver får
et kort med oversigtsteksten og kandidatens detaljepost (kandidaterne findes i Task 0 efter decisions 2026-11-09 B:
»sidehenvisningerne i oversigterne er det stærkeste bevis«). Svaret skrives som en accepteret identitet med den
menneskelige afgørelsesvej. Task 0 afklarer, om den vej kræver, at kandidaten står i den gældende kandidatkørsel; gør
den, og står kandidaten der ikke, er det et stop til en lille tilføjelse i planen (ikke en omgåelse). Personaernes
records er oversigtsposter uden narrativ, så der er intet narrativ at flytte (6c-2's antagelse om en
narrativflytning bortfalder).

## 5. Ikke-mål og anti-mål

- Ingen nye personer eller bindinger; ingen sletning af narrativer, records, observationer, hændelser eller personer.
- Ingen kildetekst-rettelser og ingen grænserettelser (6d-2b).
- Fakta, familiekilder og hændelser uændrede (§3 pkt. 9).
- 2018-20 uændret: placements, medlemskaber, publiceringer og koordinater byte-ens; reglens mængde for kilde 1 er tom
  (målt; genmålt i Task 0: tom).
- Ingen læserændring ud over, hvilke 1939-biografier der vises (koordinater, udgavevælger: 6e).
- Identitet på tværs af udgaverne for personer uden 1939-detaljepost (fx 1849↔210, 960↔211) og den redaktionelle
  sammenlægning af dubletterne er backlog.
- **Anti-mål:** en oversigtsstump, der stadig står som biografi på en person med fuld post; en tekst, der er den eneste
  om en person, og som forsvinder; en ny kobling, der giver en karantæneret komponent; et anon-kald, der bliver mere
end 10 % langsommere.

## 6. Vejen til prod

Som 6d-1 i mindre skala: privat runner, dump før hver skrivende ceremoni (B1 + age-kopi), frys, vinduesvagt, GO pr.
ceremoni, fortryd ved restore, generalprøve fra operatørens cwd på en stand-in fra en frisk prod-`dump-kopi`.
- **DDL-ceremoni:** regelfunktionen, biografilæserens brug af den, redaktørens RPC, retningsreglen (§4.2) og
  `db-rls.sql`, i én transaktion.
- **Data-ceremoni:** 1014's kobling og de tre identiteter efter kortsvarene; pinnes på indhold (person-id'er og record
  keys, der findes i prod før ceremonien) og på et hashet **kortmanifest** *(rev. 4, Codex-fund 9)*: for hvert kort
  persona-id og -nøgle, forventet identitetsstatus og -version, kandidatens person-id, sha over den viste
  oversigtstekst og kandidatposten samt handlingen; svarfilen refererer manifestets sha, og ceremonien efterprøver
  førtilstandene under lås. Identiteterne skrives gennem `red_afgoer_source_persona` med `basis=human_sheet` og uden
  kandidat-id (Task 0: ingen kandidatkørsel kræves, ingen af personaerne er i en kontrolstikprøve) *(Codex-fund 10)*;
  ceremonien efterlader en kvittering, også ved nul skrivninger. Aldrig id'er oprettet af ceremonien. Er
  `begin_change_set` åben for hele transaktionen, nulstilles `app.change_set_id` mellem kaldene (kendt mønster).
- **Mål før/efter:** reglens mængde, synlige 1939-biografier som anon, faktalæsernes resultat (hash), KOORD- og
  paritetshashes som 6d-1, og tidsbudgettets kald (§4.1).

## 7. Overladt til bygherren

Regelfunktionens forespørgselsform (inden for §4.1's tidsbudget); funktionsnavne og signaturer; redaktørmarkeringens form; kortformen; testopdelingen.

## 8. Færdigbevis

- **Regel:** regelfunktionens mængde målt i prod før og efter (forventet 10 narrativer, 9 synlige før; 11 efter
  1014's kobling, stadig 9 synlige — 1014 er staged); 0 af dem leveret som biografi til anon efter; narrativ,
  binding og record findes.
- **Reversibilitet** (stand-in): fjern én kobling → teksten vises igen; kobl igen → skjult; tilbagetræk et medlemskab
  på *Q* → *P*'s tekst vises igen.
- **Uberørte:** de 6 *ja/ja* og de 522 *ja/nej* vises som før; Henning vises; `public_person_facts` og
  `public_family_sources` byte-ens for alle offentlige personer; hændelser uændrede.
- **Retning:** stand-in-testene fra §4.2.
- **1014 og de tre identiteter:** kanten findes (eller kortets nej er registreret); de tre personas har accepteret
  identitet (eller kortets svar er registreret); 0 `unresolved` og 0 personas uden identitetsrække i 1939 bortset fra
  registrerede nej-svar.
- **2018-20 og 6d-1:** paritetshashes som 6d-1 uændrede; 528 placements og medlemskaber uændrede.
- **Tid:** tidsbudgettet i §4.1.

## 9. 6d-2b (afgrænsning, specificeres senere)

- **Binding af de tekster, der vises** (egne tekster uden binding, fx 929, 933, 934, 935, 940, 1135, 1791, 1795):
  149b's `migrate_legacy_narrative_record` kræver `person_external_id.record_key` = postens nøgle, hvilket kun gælder
  8 af 1939's 576 rækker (bevidst). Kræver en ny identitetskilde i skrivevejen eller en ny writer. Ikke-offentlige
  personer kan kun få en kladdebinding. **Oversigtsomtaler bindes ikke** (de ville støde mod reglen; jf.
  `LEGACY_MIGRATION_PUBLICATION_GATE_MISMATCH`).
- **De 38 tekstrettelser** (6m's `legacy-sager.json`, `kun_rapport`): kildetekst-revisionen har kun en 2018-20-profil
  (`folded_projection@page_header`); 1939 bruger `raw` med eksakte offsets i klausulgenskæringen. Kræver en
  1939-profil og afklaring af længdeændrende rettelser; revisionen kræver et eksisterende klausulsæt på posten.
- **De 6 grænsefejl:** revisionen låser teksten til postens spænd (`TEXT_REVISION_SPAN_MISMATCH`); en grænserettelse
  er ny forekomst + nyt anker (6a-spec'en), ikke bygget, og gør publicerede tekster forældede.
- **Bindinger, en revision taber:** 6c-3's afstemningswriter har en kendt fejl, der skal rettes, før den får en ny
  kalder (6c-3-spec'en).
- **Rettelsen på narrativ 632** (person 963, staged) trækkes kun tilbage fra rapporten.

## 10. Bygherre-tjek (Opus, 2026-11-09)

**Revision 1** (8 fund, efterprøvet mod koden): 149b's migration kan ikke binde 1939-tekster (record_key 8/576);
grænsefejl kræver en ny mekanisme; ingen 1939-profil til kildetekst-revision; tabte bindinger ved revision; ikke-
offentlige personer kan ikke få publiceret binding → alle til 6d-2b. Reglens rækkevidde → defineret og målt.
`samme_som`-vagterne → de fire par er allerede koblet.

**Revision 2** (7 fund, efterprøvet): (1) tidsbudget og læserkald manglede, og et komponentopslag pr. række er ikke
muligt → §4.1 Form og Tidsbudget; (2) »placeret« var uklart, og *Q* uden synlig tekst ville gøre *P* tekstløs →
§4.1 Definition; (3) reglen skal også slå om ved medlemskabs- og konklusionsændringer, og `red_samme_som` indsætter
relationen før konklusionen → §4.1 Form; (4) retningsreglen mod G3/G4 → §4.2 fallback; (5) en `unresolved` identitet
har ingen person, og decisions nævner tre oversigtspersonas → §2, §4.4; (6) vagten bruges også til faktakildelinjer
og hændelser → §3 pkt. 9, §4.1 Virkning; 6d-2b må ikke binde oversigtsomtaler → §9; (7) ændringen af decisions B var
ikke registreret → §1 pkt. 7, §3 pkt. 8.

**Revision 4 — Codex-runde på spec+plan (`gpt-6.1-sol`, 2026-11-09; 12 fund, NO-GO; Opus afvejede).** Task 0 målte
først: reglens mængde 10/9/kilde 1 tom som forventet; live-beregning for alle personer ≈ 135 ms med samme mængde
(+4 % på biografilæseren); biografilæseren med alle personer og den direkte narrativlæsning ligger allerede omkring
3 s på stand-in'en før 6d-2a. Afvejning:
- **Fund 1-5** (gemt markering: samtidighed, ufuldstændig triggerdækning af medlemskabs- og publiceringstilstanden,
  »én gang pr. transaktion« uspecificeret, POST læser før deferred refresh): reelle mod rev. 3's form → **bortfalder**
  ved live-beregning (§4.1 Form; projektejerens valg).
- **Fund 6** (spec krævede filter i narrativ-RLS; det ville skjule hændelser): reelt → **narrativ-RLS uændret**
  (§4.1 Virkning; projektejerens valg).
- **Fund 7** (tidskrav uopfyldeligt): → relativt budget (+10 %); 3 s-niveauet før 6d-2a er backlog (projektejerens
  valg).
- **Fund 8** (skjult mellemled; appens karantæne): sti kun gennem offentlige personer (§4.1 Definition; mængden
  uændret 10); appens øvrige karantæneårsager er en kendt begrænsning — Task 7 efterprøver de berørte komponenter
  gennem `collapseSameAs` på stand-in-data.
- **Fund 9** (hash bandt kun svarene): kortmanifest (§6). **Fund 10** (skrivevej, kvittering ved nul skrivninger):
  §6. **Fund 11** (GO bandt ikke alle artefakter; ekstern dump ikke efterprøvet før hver skrivning): planens Task 7.
  **Fund 12** (idempotens ved vendt retning): §4.2.
