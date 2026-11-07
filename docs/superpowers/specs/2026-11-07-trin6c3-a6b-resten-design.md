# Trin 6c-3: A6b-resten — 2018-20's kildetekst får de manglende linjer — design

**Status:** GODKENDT af projektejeren 2026-11-07 med alle anbefalinger i §8 (pkt. 1-6: ja); revideret efter
Fable-review samme dag (§10: NO-GO → 12 fund, alle indarbejdet). Næste: plan, derefter B13's Codex-runde på
spec+plan. Projektejeren sprang afklaringsrunden over og bad om bedste skøn efter måling (som ved
6a); valg, der ikke er projektejerens, er markeret *mit valg*, og §8 samler det, kun projektejeren kan afgøre.
**Gren:** `docs/trin6c3-spec` fra `main` (`e5a0f83b`).
**Overordnet spec:** `docs/superpowers/specs/2026-10-29-trin6-1939-gennem-kaeden-design.md` (§4 mål, §5 6c, §6 pkt. 1,
6 og 7, §8).
**Mekanismen:** delspec 6a, `docs/superpowers/specs/2026-10-29-trin6a-klausuler-og-kildetekst-revision-design.md`
§2.3, §4.4, §5 og §8 (deployet 2026-10-30, ubrugt).
**Beslutninger:** `docs/decisions.md` 2026-10-28 (A6b afgrænset til narrativerne), 2026-10-29/30 (I-84 parkeret),
2026-11-02 (A6b-resten bliver 6c-3), 2026-11-04 (driftsregel for bindinger), 2026-11-07 (`BEGGE` til 6c-3).
**Review-budget (B13):** 1 Codex-runde på spec+plan (`gpt-6.1-sol`, Opus dømmer), 1 på diffen før prod — samme form
som 6c-1 og 6c-2 (`docs/decisions.md` 2026-11-01). Overskredet med én Fable-læsning af specen på projektejerens
anmodning 2026-11-07 (én linje i decisions).

## 1. Roadmap-kobling

1. **Roadmapmål:** trin 6, overordnet spec §4's mål »A6b-resten« og §8's færdigbevis for den. Sidste del af 6c.
2. **Værdikædeled:** kildetekst → klausuler → forslag → parter → afgørelse → binding for 10 af 2018-20's poster;
   første brug af kildetekst-revisionen (»genkørsel, stale beslutninger« i målarkitekturen) på rigtige data.
3. **Leverancetype:** brug af 6a's generelle mekanisme med 2018-20's eksisterende profiler, én lille generel DDL-blok
   (§4.7) og to ceremonier (DDL, data). Ingen editionsnavngiven permanent overflade.
4. **Værdi:** bogens tekst i databasen bliver hel for de 10 poster. I dag mangler 11 prosalinjer i kildeteksten og
   klausulerne, selv om læseren har dem i narrativet (A6b, 2026-10-28). Når ceremonien er slut, står de 16
   kildehenvisninger, læseren ser i dag, der igen; undervejs er der et kort, deklareret vindue (§4.5).
5. **Færdigbevis:** §6.
6. **Erstatter:** 6a's kopi-bevis som eneste brug af revisionen. »Kendt følge« i decisions 2026-10-28 pkt. 3
   (narrativ ≠ kildetekst) indsnævres: helpostens *gældende* tekst får linjerne, forekomstens tekst forbliver
   bevidst urørt (§6).
7. **Review-budget:** som i hovedet.

## 2. Målt udgangspunkt

Målt 2026-11-07 på en lokal kopi af prod (stand-in `daa5ab_ddl_standin_20261107201240_c3a`, restoret fra
`daa-prod-20261107194057-6m2.dump`, sha `76b5c7e9…`). 6m del 2's ceremoni A, der kom efter dumpet, skrev kun på
kilde 3; kilde 1's tal er derfor prods. Kun antal og nøgler. Planen genmåler mod prod før GO. Fable-reviewet
genmålte §2.1-2.3 uafhængigt med samme resultat.

### 2.1 Afhængigheder (`source_text_revision_dependencies.sql`, profil `daa-2018-20-source-text-revision-v1`)

| Post | Klausulsæt | Nøgler, der forældes | Bindinger, der falder ud |
|---|---|---|---|
| I-9 | 2 | 5 | 2 assertion |
| I-11 | 2 | 6 | 2 assertion, 1 family |
| I-17 | 1 | 6 | – |
| I-18 | 1 | 4 | – |
| I-32 | 1 | 1 | 1 family |
| I-33 | 1 | 1 | 1 assertion |
| I-44 | 1 | 5 | 1 assertion, 1 family |
| I-89 | 1 | 9 | 3 assertion, 2 family |
| III-37 | 2 | 21 | 2 family |
| III-129 | 2 | 0 | – |
| **I alt** | | **58 nøgler (74 rækker)** | **16: 9 assertion, 7 family** |

Tallene er de samme som 6a §2.3 (2026-10-29). Alle 10 har helpost-status `ok`; ingen menneskelige
klausuldispositioner. 2 af de 7 familiebindinger deler familie-mål med en anden afhængig nøgles binding.

### 2.2 De 58 nøglers aktuelle tilstand

| Status | Antal | Afgjort med |
|---|---|---|
| `accepted`, fakta (navn 4, død 3, fødsel 1, titel 1) | 9 | `machine-corroboration-v1` (trin 4's kontrolmodel) |
| `accepted`, `relation.marriage` | 3 | `family_structure` (5b) |
| `accepted`, `relation.parent` 2 / `relation.child` 2 | 4 | `human_sheet` (projektejerens ark i 5b) |
| `proposed` (embede 9, steder 10, gods 4, hændelser 7, øvrige 12) | 42 | – |

Alle forslag er lavet af `gpt-5.6-terra` med prompt-hash `d46cda80…` (trin 4's kørsel). 13 partsrækker på 8 nøgler.

### 2.3 Personas, narrativer og persondata

- 12 personas på 9 poster, alle med `accepted` identitet. 3 er ægtefælle-personas med mention på en klausul (I-89 ×2,
  III-37 ×1), oprettet af `write_relation_persona` med indholds-id `<post>#rel-marriage-<post_offset>-<længde>`. Både
  I-89 og III-37 er i dag ét klausul over hele posten, og begge krydser et sideskift.
- 9 publicerede narrativer (A6b har allerede linjerne). III-129 har hverken persona, fortolkning eller
  narrativbinding (en af 149b's fire `unresolved_text`); trin 4 skrev intet forslag for den.
- Ingen af personerne er levende. Alle 10 poster er `eligible` under `exclusion-2018-20-v1` (ledger 591/488/103,
  samme regler som trin 4); I-84 er `excluded` (`spouse_undated_marriage`) og parkeret uanset.
- **Drift i udelukkelsesgrundene (noteres, ikke 6c-3's sag):** pr. regel, overlappende (en post kan ramme flere),
  er tallene nu principal 47, relative 56, spouse 68, text 2 mod trin 4's 46+4 / 13 / 62 / 2. Totalen 488/103 er
  uændret; skiftet i `relative_living` skyldes sandsynligvis 5b's flere relationer. Ingen af de 10 er berørt.

### 2.4 Genbinding under 6c-2's vagt (verificeret i koden)

`ALREADY_BOUND_OTHER` (decisions 2026-11-04) tæller kun en anden nøgles binding, hvis `assertion_binding_current`
er sand, og den kræver, at bindingens fortolkning *er* nøglens aktuelle version og står `accepted`. Efter
forældelsen er den aktuelle version `superseded`, så den gamle binding spærrer ikke for en ny nøgle mod samme
påstand. Unikhedsindeksene på `interpretation_promotion` er pr. fortolkningsversion. Læserens bindingstælling tæller
kun gyldige. Kørt bevis følger i øvelsen (§5 pkt. 1).

## 3. Afgrænsning

**I 6c-3:**
- Kildetekst-revisionen af de 10 poster med A6b's sidehovedregel (`page_header`, profil `2018-20-v2`).
- Genkørsel af modellen på de 9 poster med persona, parter, kontrol, afgørelse og genbinding.
- DDL-blokken i §4.7.
- Nøglet afstemning af alle 58 gamle nøgler og alle 16 bindinger.
- Én DDL-ceremoni og én data-ceremoni i prod.
- Registrering af `BEGGE` (§4.6).

**Ikke i 6c-3:**
- I-84 (grænserevision, B4-sporet; uændret fra 6a §5).
- Nye påstande, personer eller familier fra de genfundne linjer (opret-benet, B4). Forslag uden påstand at binde til
  står `NO_FACT` og venter, som i 6c-2 §3 pkt. 2.
- III-129's genkørsel og narrativbinding (ingen persona; årsagen er ukendt og ikke linjerne; decisions 2026-10-28).
- Forekomstens tekst (`source_record_occurrence.verbatim_text`) og 149b's komparator (§6).
- 1939 (6d, 6e) og datogrænse-backloggen (decisions 2026-11-07).

## 4. Design

### 4.1 Revisionen (6a's operation, uændret)

Én `source-text-revision:`-operation pr. post gennem reimport-writerens kæde (authorize → preflight → apply), som én
batch under READ COMMITTED. Den nye tekst er helpostens spænd projiceret med `page_header`-reglen; spændet og
renditionen er de samme. Preflighten måler afhængigheder for hele batchen og binder mængden pr. post; drift i
bindingsmængden (mængde, ikke antal) stopper. Forældelsen gør de 58 nøgler `superseded` og lægger et nyt klausulsæt
mod den nye tekstversion. III-129 revideres som de andre (0 afhængige). Revisionen låser berørte personer og
familier `FOR UPDATE` i hele batch-transaktionen (§5 pkt. 4).

### 4.2 Genkørslen sker uden for prod (*mit valg*)

- Modellen kører på en stand-in, efter at revisionen er kørt dér. Prod og stand-in har 0 tekstversioner i dag, så
  revisionen giver version 1 begge steder, og nøglens `key_version 2` er deterministisk over tekstversionens *nummer*
  (6a §4.4 pkt. 6). Stand-in'ens forslag har derfor samme nøgler i prod.
- **Overførsel:** forslagene går til prod ad 6c-1's vej: runner-manifest → `build_43b_proposal_manifest.py` →
  reimport-writeren, der genberegner nøglen i prod. Afgørelser og bindinger refererer `interpretation_key` + version,
  familie-id og promotionsmål, aldrig række-id'er (`interpretation.id` er tilfældigt pr. base). `transfer_pack.py`
  bruges kun til fakta-afgørelser og -bindinger, som i 6c-2.
- **Model og prompt (*mit valg*):** den oprindelige kørsels `gpt-5.6-terra` og prompt `d46cda80…`. Det giver den
  bedste chance for at genfinde de 16 afgjorte værdier; prompt 1.1.0 er tilpasset 1939. Øvelsen bekræfter, at
  modellen kan kaldes, og at prompten kan hentes i præcis den version; ellers kommer valget tilbage i §8.
- **Kun de 9 poster med persona køres.** III-129 har ingen primary-persona; writeren afviser den
  (`REIMPORT_WRITER_PRINCIPAL_WITHOUT_PERSONA`), og runner-eksporten udelader den. Den revideres (§4.1), men genkøres
  ikke. Inputtet er helpostens gældende tekst (`helpost_text_current`).

### 4.3 Parter og afgørelser

- **Fakta:** kontrolmodellen `control_model_v2.py` som i 6c-2 (overordnet spec §6 pkt. 1; trin 4 brugte v1).
  Øvelsen viser, at v2 klassificerer de 9 gamle værdier som trin 4 gjorde. `MATCH` accepteres maskinelt og bindes.
  Stikprøven er `min(20, n)` `MATCH`, i praksis dem alle (*mit valg*). `REAL_DIFF` går på kort.
- **Parter først:** relationsafgørelser kræver parter på de nye nøgler. En `relation_persona`-batch med profilen
  `relation-persona-2018-20` (v1, deterministisk, intet ark — den, 5b brugte for alle 7), afgrænset til de nye nøgler
  på de 9 poster (`relation_persona_input` er kildebred: 4 andre rækker i dag), skriver principal- og ægtefælleparter.
  Forælderparten skrives af afgørelsen selv; en `child`-part findes ikke.
- **Ægteskaber (3):** de 3 eksisterende ægtefælle-personas *genbruges* som part på de nye nøgler via DDL-blokken
  (§4.7); ingen nye personas, ingen ny mention (partstriggeren kræver kun en ægtefælle-mention i samme forekomst, og
  den gamle består). Afgørelsen sker maskinelt med `red_preview_relation_decisions` → `red_decide_relation_interpretations`
  (`family_structure`), når familiens tilstand er den samme. Funktionen tager hele kilden, og preview-RPC'en viser ikke
  nøglerne; ceremonien sammenligner derfor `private.relation_decision_set(1)`'s nøglemængde med de forventede nye
  ægteskabsnøgler i samme transaktion umiddelbart før afgørelsen, under frysen (Codex fund 8). Ingen kort.
- **Børn (2):** genbesvares på kort (*mit valg*, se §8 pkt. 2) med `relation_child_sheet.py` (svar B/R/U), afgrænset
  til de nye nøgler, og afgøres med `red_afgoer_relation_interpretation(key, version, 'same', NULL, …)`: familien
  afledes af reglen; `p_family_id` afvises for børn.
- **Forældre (2):** i 5b afgjort via kontrolkørslens forældrekort, som ikke gælder nye nøgler. De genbesvares på et nyt
  forælderark (samme form som børnearket) og afgøres med `red_afgoer_relation_interpretation(key, version, 'same',
  <familie>, …, {basis:'human_sheet', sheet_sha256, rows_sha256, line})`; familien skal være den eneste i
  `relation_structural_candidates` og lig den gamle bindings mål.
- **Binding af relationer:** `red_preview_relation_promotions` → `red_promote_relation_interpretations_batch` med den
  gamle bindings familie pr. ny nøgle. `supersedes_promotion_id` dækker kun samme fortolkningsversion, så koblingen
  gammel → ny binding ligger i afstemningskvitteringen (§4.4).
- **Kortene:** fakta i 6c-2's kortform (`persona_kort.py`, svar B/D/V), børn og forældre i 5b's arkform. Forventet
  under 25 punkter (op til 9 `MATCH`-stikprøve, `REAL_DIFF`, 4 relationer, ikke-genfundne); over 30 stopper planen og
  spørger. Svarene nøgles på `interpretation_key` + version (række-id'er er tilfældige pr. base) og oversættes til
  prods id'er i ceremonien.

### 4.4 Nøglet afstemning

- **Bindingerne afstemmes pr. `promotion_id`** mod revisionsevent'ets `expected_binding_loss`. Hver af de 16 ender i
  én af to tilstande: genbundet til en ny nøgles gældende, accepterede version mod *samme* mål, eller tilbagetrukket
  med projektejerens udtrykkelige svar på et kort. En tilbagetrækning er synlig i læseren som »fra den oprindelige
  import« (fakta) eller som en familie uden kildelinje.
- **»Genfundet«** har én kontrakt pr. art (Codex fund 5); klausulordinalen kræves aldrig (den flytter, når en linje
  indsættes):
  - fakta: samme persona + prædikat, og den nye værdi matcher den gamle bindings påstand (`binding_value_matches`);
  - ægteskab: samme principal, prædikat og ægtefælle-persona (efter genbrug, §4.7 pkt. 1), og `relation_binding_state`
    peger på den gamle familie;
  - forælder: samme principal og prædikat, og den eneste kandidat i `relation_structural_candidates` er den gamle
    familie; efter afgørelsen kontrolleres den skrevne forælderpart;
  - barn: samme principal og prædikat, og børnereglens afledte familie (`relation_child_rule`) er den gamle;
  - ubundne `proposed`: samme persona + prædikat og `saml_blanktegn_v1`-lige værdier.
  Tvetydige eller manglende kandidater er »ikke genfundet«.
- **Alle 58 gamle nøgler** står på listen med udfald (genfundet → ny nøgle, eller ikke genfundet). Listen er beviset,
  ikke et antal.
- At modellen ikke genfinder en værdi, er et forventeligt udfald, ikke en fejl. Det går på kort med valget
  »tilbagetræk« (T) eller »ved ikke« (V). Begge giver udfaldet `tilbagetrukket`, og bindingen falder ud; svaret står
  i kvitteringen (`ved_ikke` for V). Der er intet åbent udfald, så kvitteringen er endelig, og en senere ny binding er
  en ny, selvstændig afgørelse (Codex fund 9).
- **Hvor afgørelsen gemmes:** en tilbagetrækning kan ikke ligge på den gamle nøgle (den er `superseded`) og har ingen
  ny nøgle. Udfaldet pr. binding skrives i en generel, append-only og aktørbundet afstemningskvittering i basen
  (DDL-blokken, §4.7), med svarfilens hash, som GO'en binder, og en reference til revisionsevent'et. Se §8 pkt. 6
  for alternativet uden tabel.
- **De 42 `proposed`** var uafklarede før og må være det bagefter. De afstemmes, men intet kræves.
- **Nye forslag fra de genfundne linjer** uden en påstand at binde til bliver `NO_FACT` og tælles (§3).

### 4.5 Én ceremoni, ét deklareret vindue

Revision, overførsel, parter, afgørelser og genbinding kører i én ceremoni, men ikke i én transaktion: revisionen er
sin egen batch, forslags-writeren kræver revisionsevent'et committet, før S4 åbner, og bindingstrinnet kører for sig.
Mellem revisionens commit og genbindingens commit viser læseren de 9 fakta som »fra den oprindelige import«, og de 7
familier mangler kildelinjen. Vinduet deklareres i runbooken, måles i øvelsen og skaleres med prod/stand-in-forholdet.
Svarene på kortene ligger *før* ceremonien (fra stand-in'ens kørsel); ceremonien venter ikke på et menneske midt i.

**Hvad der overføres, og hvad der beregnes i prod (Codex fund 2 og 6):**
- Revisionsmanifestet og forslagsmanifestet bærer kun deterministiske nøgler og overføres som de er.
- Partsmanifestet bærer klausul-id'er, der er tilfældige pr. base. Det udtrækkes derfor *i prod* af den
  deterministiske v1-udtrækker efter forslagene; GO binder et logisk manifest fra stand-in'en (record, prædikat,
  `post_offset`, spændlængde, hash af værdien), og prods udtræk skal være logisk lig, ellers stop.
- Kortsvarene nøgles på `interpretation_key` + version og bindes sammen med et id-uafhængigt beslutningsgrundlag pr.
  felt (persona-identitet, klasse, rettelsesmål, forventet måltilstand, datogrænser). I prod genberegnes grundlaget;
  det skal være eksakt lig, ellers stop. Et persona-svar `P` på et kort er en identitetsændring og stopper ceremonien
  før prod (Codex fund 7).

### 4.6 `BEGGE` registreres, bygges ikke (*mit valg*, se §8 pkt. 3)

6m del 2 registrerede 62 af modellens markeringer »begge kan være rigtige« (41 titler) til 6c-3; projektejeren har
ikke svaret på dem. At give et »begge rigtige« virkning kræver en ny påstand for 1939's værdi ved siden af
databasens, altså et nyt faktum: opret-benet (B4), som trin 6 udelukker. Visningen af flere udgavers værdier er 6e
(fakta pr. udgave). 6c-3 bygger derfor intet for `BEGGE`; de 62 forslag står `proposed`. Decisions får én linje, der
flytter spørgsmålet fra 6c-3 til opret-benet/6e.

### 4.7 DDL-blok (generel, lille)

6a deployede revisionen, S4-åbningen, `key_version 2` og reservationen af grundlaget `source_text_revision`. Fable
viste, at to ting mangler:

1. **Genbrug af en relations-persona efter tekstrevision.** `write_relation_persona` opretter altid ægtefælle-personaen
   med indholds-id af `post_offset` og længde. Står navnet samme sted, giver det samme id, og writeren fejler på
   `unique_violation`; flytter linjen navnet, opstår en ny dubletpersona uden identitet. Blokken lader writeren
   genbruge den eksisterende persona som part på en ny nøgle, når præcis én persona opfylder: ægtefællepart i samme
   forekomst på en nøgle, hvis gældende version er `superseded` med grundlaget `source_text_revision`, samme
   `marriage_ordinal`, **samme ægtefællenavn** (personaens mention-tekst og det nye spænd er lige efter
   `saml_blanktegn_v1`; sammenlignes i basen, Codex fund 1), og ikke ægtefællepart på en levende nøgle. Ingen kandidat
   → oprettelse som i dag; flere → fejl lukket. Ved genbrug skrives ingen ny mention. Reglen før skrivning og
   kontrollen i finalize (`verify_relation_persona_receipts`) er adskilte: finalize godtager præcis batchens egen nye
   part på den genbrugte persona og afviser enhver anden levende anvendelse (Codex fund 3). `relation_derived_counts`'
   nøgler er uændrede.
2. **#248-rivalvagten** (`private.relation_binding_state`) tæller en rival, hvis dens seneste version ikke er
   `rejected`; en `superseded` rival ville derfor blokere. Vagten rammer ikke de 7 (ingen af personerne har to
   accepterede personas), men rettes som generel følge af forældelsen: `superseded` falder ud.
3. **Én part pr. persona antages to steder:** `persona_family_context` og `spouse_principal_person` slår
   ægtefælleparter op uden statusfilter og giver NULL, når en genbrugt persona har to. De får samme filter som 6a gav
   `relation_persona_v3_input` (partens nøgle `proposed` eller `accepted`).
4. **Afstemningskvitteringen** (§4.4): ny append-only tabel efter `private.relation_reopen`'s mønster (aktør, kontekst,
   append-only-trigger, RLS, ingen adgang for anon/authenticated/service_role) og en privat writer, som ceremonien
   kalder med aktøren sat i transaktionen. Referencen til revisionen er `reimport_event`'s `(batch_id, element_id)`.
   Writeren kontrollerer hele kæden pr. item (Codex fund 4): den gamle nøgle og promotion er i revisionsevent'ets
   mængder; den nye promotion tilhører den nye nøgle; den nye nøgles gældende version er `accepted`, i samme kilde,
   citerer det nye klausulsæt under samme helpost, har samme prædikat og (fakta) samme persona eller (relationer) samme
   principal; samme måltype og mål; bindingen er gyldig nu. `genfundet`-rækker kontrolleres på samme måde uden
   promotion. Udfaldene er `genbundet`, `tilbagetrukket`, `genfundet` og `ikke_genfundet`.

Blokken går i prod i sin egen DDL-ceremoni før data-ceremonien, med pg-tests, opgraderingstest fra prods skema og
db-verify. Den er generel (ingen udgavenavne) og bruges af enhver fremtidig tekstrevision med relationer.

## 5. Prod

1. **Øvelse først** (planens første opgave efter DDL-blokken): revision → genkørsel → parter → afgørelser →
   genbinding på stand-in'en, med prods 2-minutters grænse. Den skal vise §2.4 og §4.7 i praksis: hver af de 9
   påstande og 7 familier kan genbindes til en ny nøgle, og de 3 ægtefælle-personas genbruges. Vinduet (§4.5) måles.
   Fejler øvelsen, kommer spec'en tilbage til projektejeren før næste opgave.
2. **Runner:** ny privat runner efter 6c-2/6m-formen (`maal`, `dump`, `go-*`, `apply-* --jeg-mener-det --go`,
   `verify`, `fortryd*`); præcise allow-regler for læse-trin og `go-*` (memory: runner-allowlist). Apply og fortryd
   kun i projektejerens shell.
3. **DDL-ceremonien:** dump (B1) → DDL-blokken + `db-rls.sql` i én transaktion → `NOTIFY pgrst` og advisors.
   Fortrydelse: `fortryd-ddl` fra et snapshot, så længe data-ceremonien ikke er kørt.
4. **Data-ceremonien:** dump med B1 (to kopier, hash noteret) → genmåling (afhængighedsfil = den bundne) → revision
   ×10 → overførsel af forslagene (9 poster) → `relation_persona`-batch (parter) → afgørelser og bindinger (fakta med
   `control_model_v2.py`'s SQL; ægteskaber via `red_decide_relation_interpretations`; forældre/børn via
   `red_afgoer_relation_interpretation`; relationsbindinger via `red_promote_relation_interpretations_batch`) →
   afstemningskvittering → verify. GO binder manifest,
   afhængighedsfil, forslagsmanifest, partsmanifest og svarfil.
5. **Vindue og frys:** fortrydelse af data-ceremonien er restore af dumpet (forældelse er endelig, 6a §4.4 pkt. 7).
   Fra dump til godkendt verify skrives intet andet i prod, heller ikke på 1939, og driftsreglen fra 2026-11-04
   gælder. Revisionens `FOR UPDATE`-låse på de berørte personer og familier gør, at også læser- og
   bogmærkeskrivninger på dem venter og kan ramme deres `statement_timeout`; vinduet deklareres derfor for alle,
   ikke kun redaktører.
6. **Varighed:** prod/stand-in-forholdet måles på genmålingen, før en varighed bruges som bevis (memory:
   standin-tid; 6a's runbook målte ca. 55× for skrivninger).

## 6. Færdigbevis

- **Tekst og klausuler:** de 10 posters gældende helposttekst (`helpost_text_current`) indeholder de 11 linjer;
  hvert nyt klausulsæt er delstrenge af netop den tekst.
- **Afstemning:** afstemningskvitteringen lister alle 58 nøgler og alle 16 bindinger (pr. `promotion_id`), hver med
  udfald (§4.4). Ingen binding uden udfald.
- **Personas:** ingen nye ægtefælle-personas; de 3 eksisterende er parter på de nye ægteskabsnøgler.
- **Narrativer:** de 9 publicerede narrativers `publication_state`-hash er uændret.
- **Læseren:** de genbundne fakta viser »DAA 2018-20 · <post>« som før, og de genbundne familier har kildelinjen;
  tre stikprøver som anon i browseren.
- **Komparatoren (149b) er ikke et bevis her.** Den læser bevidst forekomstens tekst (6a Task 13, R13-b), som
  revisionen ikke rører, og vil fortsat vise de 10 som afvigende. Afvigelsen er forklaret af tekstversionen.
- **Status:** rækken »Kildetekst-revision« for 2018-20 hæves til `produktionsverificeret`. Decisions 2026-10-28 pkt.
  3's kendte følge omformuleres: narrativ ≠ *forekomstens* tekst består som kendt, begrundet følge; helpostens
  gældende tekst = narrativets for de 9.

## 7. Følger

- Trin 6c er afsluttet; næste er 6d.
- Kildetekst-revisionen og genbrug af relations-personas er bevist på rigtige data og kan bruges af 6m's `K`-sager og
  6d, hvis de får brug for dem.

## 8. Afgørelser til projektejeren

1. **Genkørsel med den oprindelige model og prompt** (§4.2) i stedet for prompt 1.1.0. *Anbefaling: ja.*
2. **De 4 forældre/barn-afgørelser genbesvares på kort** (§4.3) i stedet for en regel, der flytter dem
   automatisk. *Anbefaling: ja.*
3. **`BEGGE` flyttes til opret-benet/6e** (§4.6) med én linje i decisions. *Anbefaling: ja.*
4. **I-84 forbliver parkeret** (uændret fra 2026-10-29). *Anbefaling: ja.*
5. **De 3 ægteskaber:** DDL-blokken (§4.7 pkt. 1-2) og genbinding, eller ingen DDL og de 3 ægteskabers kildelinje
   trækkes tilbage (synligt tab i læseren). *Anbefaling: DDL-blokken.*
6. **Afstemningskvitteringen:** ny generel tabel i samme DDL-blok, eller GO-bundet privat fil plus revisionsevent og
   promotionsrækker som det auditerbare grundlag (tilbagetrækningens beslutning ligger så kun i filen). *Anbefaling:
   tabellen, da der alligevel er en DDL-ceremoni.*

## 9. Uden for scope

Grænserevision; opret-benet; forekomsttekst og komparator; 1939's relationer, placements og medlemskaber (6d); fakta
pr. udgave (6e); datogrænse-backloggen; samtidigheds-backloggen fra 2026-11-04.

## 10. Reviewlog

**Fable, 2026-11-07 (på projektejerens anmodning; B13-overskridelse noteret i decisions):** NO-GO på første udkast,
12 fund; §2's målinger, §2.4 og nøgledeterminismen bekræftet. Afvejning (fund 1, 2, 3 og 6 efterprøvet i koden af
mig):

| # | Alvor | Fund | Afgørelse |
|---|---|---|---|
| 1 | HIGH | Komparatoren læser bevidst forekomstens tekst; færdigbevis-punktet uopnåeligt | nødvendig: §6 omskrevet, kendt følge omformuleres |
| 2 | HIGH | Ægteskabsbindinger kan ikke genbindes uden DDL (indholds-id, #248-rivalvagt, arkbundne parter) | nødvendig: §4.3, §4.7, §8 pkt. 5 |
| 3 | HIGH | Ingen kvitteringstabel i basen | nødvendig: §4.4, §4.7 pkt. 3, §8 pkt. 6 |
| 4 | MEDIUM | Ceremonien er ikke atomisk; vindue | nødvendig: §1.4, §4.5 |
| 5 | MEDIUM | Parts-trinnet mangler; kort-form passer ikke til 5b's writere | nødvendig: §4.3, §5 pkt. 4 |
| 6 | MEDIUM | III-129 kan ikke genkøres (ingen persona) | nødvendig: §3, §4.2 |
| 7 | MEDIUM | »Samme ordinal« uhandlebart; afstem pr. `promotion_id` | nødvendig: §4.4 |
| 8 | MEDIUM | Forkert overførselsværktøj; pin nøgler, ikke id'er | nødvendig: §4.2 |
| 9 | LOW | Udelukkelsestal pr. regel overlapper | rettet: §2.3 |
| 10 | LOW | `BEGGE` er modellens markeringer, ikke projektejerens svar | rettet: §4.6 |
| 11 | LOW | `FOR UPDATE`-låse rammer også læser-/bogmærkeskrivninger | rettet: §5 pkt. 5 |
| 12 | LOW | Kontrolmodellens version ikke navngivet | rettet: §4.3 (v2, øvelsen sammenligner med v1) |

**Kortlægning til planen (Opus, læse-kun, 2026-11-07), efter godkendelsen.** Rettede fire detaljer uden at ændre §8:
ægteskabernes parter kom fra v1 uden ark (ægteskaber maskinelt, ingen kort); børn afgøres uden `p_family_id`;
forældre fik et nyt ark, da kontrolkortene ikke gælder nye nøgler; DDL pkt. 1 omfatter også finalize-kontrollen,
og pkt. 3 (én part pr. persona) er tilføjet. #248-vagten rammer ikke de 7, men rettes generelt.

**Codex (`gpt-6.1-sol`), B13's runde på spec+plan, 2026-11-07:** NO-GO, 10 fund (6 HIGH). Kørt read-only fra en ren
worktree uden `work*/`. Fund 2 og 8 efterprøvet i koden af mig; Opus-afvejning:

| # | Alvor | Fund | Afgørelse |
|---|---|---|---|
| 1 | HIGH | Genbrug på ordinal alene kan vælge forkert ægtefælle | nødvendig: samme navn efter `saml_blanktegn_v1` (§4.7 pkt. 1) |
| 2 | HIGH | Partsmanifestet bærer klausul-id'er (ikke portabelt) | nødvendig, forenklet: udtræk i prod, logisk lighed med stand-in (§4.5) |
| 3 | HIGH | Finalize-kontrollen modsiger kandidatreglen | nødvendig: før- og efterregel adskilt (§4.7 pkt. 1) |
| 4 | HIGH | Kvitteringen kan godkende en uvedkommende promotion | nødvendig: hele kæden kontrolleres (§4.7 pkt. 4) |
| 5 | HIGH | Relationsmatch uhandlebar (forælderpart findes først efter afgørelse; børn uden part) | nødvendig: kontrakt pr. art (§4.4) |
| 6 | HIGH | Oversættelsen binder ikke beslutningsgrundlaget | nødvendig: id-uafhængigt grundlag, eksakt lighed (§4.5) |
| 7 | MEDIUM | Persona-svar (P) forsvinder i overførslen | nødvendig: P stopper før prod (§4.5) |
| 8 | MEDIUM | Preview viser ikke nøglemængden | nødvendig: `relation_decision_set` i samme transaktion (§4.3) |
| 9 | MEDIUM | `aaben` uden afslutning | forenklet: udgår; V = `tilbagetrukket` med `ved_ikke` (§4.4) |
| 10 | LOW | Paritetslisten mangler ændrede funktioner | nødvendig: planens Task 2 |
