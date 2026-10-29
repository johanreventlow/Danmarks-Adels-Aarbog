# Trin 5c-2 + B11: læseren ser placering og fakta med kilde — design

**Status:** udkast 2026-10-29, skrevet uden afklarende spørgsmål (projektejeren sprang dem over). Afgørelserne i §8
venter på projektejerens ja; først derefter skrives planen.
**Gren:** `docs/5c2-b11-spec` fra `main` (`39a812f7`).
**Review-budget (B13):** spec 1 Codex-runde (`gpt-6.1-sol`, Opus dømmer); plan 1 Codex-runde; implementering 1
Codex-runde. Fable kun efter projektejerens ja. Overskridelse kræver én linje i `docs/decisions.md`.
**Grundlag:** 5c-spec'en (`2026-10-26-trin5c-placement-membership-design.md` §3 og §4.4); Task 6-inventaret
(`docs/superpowers/reviews/task6-legacy-placement-consumer-inventory.md`); helhedsreviewet 1a-03 og rapport §6;
`docs/decisions.md` 2026-10-27 B11 og 2026-10-26 (5c-1 pkt. 2). Målt på en lokal kopi af prod efter A6b
(`zz_karantaene_20261104_daa5ab_ddl_standin_20261028190000_a6b`, fingeraftryk = prod efter trin B) 2026-10-29;
kun antal og strukturkoder er læst, ingen posttekst.

## 1. Roadmap-kobling

1. **Roadmapmål:** trin 5, sidste del (5c-2, #150) sammen med B11, som er en del af trin 6's færdigbevis (b).
2. **Værdikædeled:** det sidste led, offentlig læseprojektion med kildehenvisning (målarkitekturen). I dag ender
   kæden ved konklusion og placement; læseren ser kun prosaen og familiernes kildelinje.
3. **Leverancetype:** generel. To editionsneutrale offentlige læse-RPC'er og deres klienter. Ingen udgaveprofil.
4. **Værdi:** læseren ser personens fakta (dåb, død, titler …) med kilde, også for de 621 offentlige personer uden
   prosa, hvis side i dag kun har navn og leveår. Trin 4's 620 bindinger bliver synlige som »bundet til bogens
   post«. Linje, nr. og kuld i læserfladen kommer fra afgjort evidens i stedet for legacy-tabellen.
5. **Færdigbevis:** §7.
6. **Erstatter:** `person_source_coordinate_legacy` (web) og direkte læsning af `person_external_id` (mobil) som
   læserens kilde til koordinater; `fetchProveniens` (citation → source for personer uden bog-nummer) erstattes af
   fakta-RPC'en.
7. **Review-budget:** i hovedet ovenfor.

## 2. Problem og målt udgangspunkt

**Fakta (B11).**
- Offentlige personer (`entitet_offentlig`): 1.811 personer i alt, 70 levende (skjules), 0 private. 1.167 har
  narrativ; **621 offentlige personer har fakta, men ingen narrativ**.
- Afklarede personfakta for offentlige personer: 6.405. Pr. type: navn 1.745, død 1.137, fødsel 1.034,
  forældrefamilie 875, titel 753, begravelse 325, dåb 257, dekoration 131, floruit 105, dødsårsag 21,
  klosterindgang 8, tilnavn 5, forældre_ukendt 4, adling 4, overhoved 1. Alle konklusioner er `afklaret`.
  84 fakta har mere end én påstand.
- **Citationsniveauet (den oprindelige import):** hver påstand har præcis én `citation` (6.769; ingen har flere).
  Kilde 1 (DAA 2018-20) har aldrig sidetal; kilde 3 (DAA 1939) har altid. 91 citationer har ingen `source_id`; 5
  peger på kilde 2 (genealogi-database). `citat_tekst` er tom for ca. 2.400 og ellers et ordret uddrag af bogen.
- **Bindingsniveauet (trin 4):** 622 `interpretation_promotion` med `target_type='assertion'`, alle med accepteret
  fortolkning; 620 af dem rammer afklarede fakta for offentlige personer (navn 239, titel 226, død 88, fødsel 67).
  En assertion-binding har ingen tilstands-sha (evidence = `preview_hash`, `promotion_kind`), i modsætning til
  familiebindingerne.
- Læseren henter i dag hverken fakta eller bindinger til persondetaljen. Undtagelsen er `fetchProveniens`
  (`web/src/data/public.ts:184`), som for personer uden bog-nummer viser hvilke kilder, der findes, men ikke fakta.
  `fact`, `assertion`, `conclusion` og `citation` kan læses af `anon` under RLS (`db-rls.sql:465-547`);
  bindingerne ligger i `private`.

**Koordinater (5c-2).**
- Web læser `person_source_coordinate_legacy` (security invoker over `person_external_id`, `web/src/data/model.ts:72`);
  mobil læser `person_external_id` direkte (`mobile/src/data/load.ts:219`). 591 rækker for kilde 1, 576 for kilde 3.
- 5c-1 (prod 2026-10-27): ledger kilde 1 = 580 `mapped` + 11 `unresolved` (V-82..V-92); kilde 3 = 576
  `retained_legacy`. 576 gældende memberships (`private.membership_is_current`). De 4 `mapped` uden gældende
  membership har record-placement men ingen persona-placement (ingen identitet; 1 af dem er levende).
- **Placement mod legacy for de 576:** linje og begge slægtled er ens for alle. `nr` afviger for 5: placement
  bevarer bogstavsuffikset (15a/15b/15c, 41a/41b), som legacy-heltallet slog sammen. `kuld` afviger for 35:
  legacy har II/III/IV, placement har tom. Begge er rettelser, besluttet i 5c-1 (decisions 2026-10-26 pkt. 2:
  »legacy arvede kuld over slægtledsgrænser«; 37 over alle 580, heraf 2 blandt de 4 uden membership).
- `printed_number` er tekst i placement og heltal i legacy. Klienterne behandler `nr` som tal: linjens hoved
  vælges som laveste `nr` (`web/src/data/lineage.ts:104`, `mobile/src/data/buildAux.ts:101`).
- `person_lineage_membership`, `person_slaegt_membership` og `membership_is_current` kan ikke læses af `anon`.

## 3. Afgrænsning

- **5c-2 (denne spec, jf. §8.1):** de offentlige læsere af koordinater: `WebPlacementLoader`,
  `MobilePlacementLoader`, `PlacementCoordinates` og `CandidateRingPlacementParity` fra Task 6-inventaret.
- **B11:** en fakta-sektion i webbens persondetalje (`DetailPanel`). Mobilen skifter koordinat-loader, men får
  ikke fakta-sektionen i denne leverance (mobil er dev-only).
- Redaktørlæserne (`GridPlacementSummary`, `MatchPlacementPayload`) og `PresensSchemeProjection` udskydes til
  trin 6, hvis §8.1 følges.

## 4. Design

### 4.1 Fakta-RPC: `public.public_person_facts(p_person_ids bigint[])`

SECURITY DEFINER, STABLE, `search_path=pg_catalog`, `REVOKE ALL … GRANT EXECUTE TO anon,authenticated`, som
`public_family_sources`. Returnerer `[]` når `narrative_record_contract_version()<2` eller input er NULL.

Én række pr. påstand på et personfaktum:

| Kolonne | Indhold |
|---|---|
| `person_id`, `fact_id`, `faktatype` | faktummet |
| `conclusion_status` | konklusionens status; kun `afklaret` og `omstridt` returneres |
| `assertion_id`, `chosen` | påstanden, og om den er konklusionens valgte |
| `vaerdi_tekst`, `date_raw`, `date_min`, `date_max`, `date_qualifier`, `date_certainty` | påstandens værdi |
| `source_id`, `source_label`, `side` | citationsniveauet: `source.udgave`, ellers `source.titel`; NULL når citationen mangler kilde |
| `record_ref`, `record_label`, `citation_label` | bindingsniveauet; NULL medmindre bindingen er gældende (nedenfor) |

**Gates, pr. række og uanset kalderens rolle (fail-closed):** `public.entitet_offentlig('person', f.subjekt_id)`;
`f.subjekt_type='person'`; konklusion med status `afklaret` eller `omstridt`. Funktionen filtrerer ikke på
faktatype; visningsvalget ligger i klienten (§4.3), fordi alle fakta i forvejen er offentlige under RLS.

**Gældende binding (definition).** Felterne `record_*` udfyldes kun, når alle betingelser holder. Ellers står de
NULL, og faktummet vises med citationsniveauet. Betingelserne er kopieret fra `public_family_sources`
(`schema.sql:18159-18205`):

1. `interpretation_promotion` med `target_type='assertion'` og `target_id` = påstanden, og
   `interpretation_current` for fortolkningens nøgle har `id = interpretation_id` og `status='accepted'`.
2. Fortolkningen har præcis én `supporting`-observation, og den har præcis én accepteret anchor → én source record
   i fortolkningens kilde.
3. Source recorden har præcis én `narrative_record_publication` med `status='published'`, dens narrativ har
   `subjekt_type='person'` og `subjekt_id` = faktummets person, og `person_daa_narrative_publication_allowed`
   er sand.
4. Etiketterne tages fra bindingens seneste `narrative_publication_event.after_state` (`source.source_label`,
   `labels.record_label`, `labels.citation_label`), som i familie-RPC'en.

Betingelse 3 binder kun til personens egen post. Et `samme_som`-medlem, hvis post er publiceret under det
kanoniske id, får derfor ingen binding. Det er fail-closed og tælles i §7.

### 4.2 Koordinat-RPC: `public.public_person_source_coordinates()`

SECURITY DEFINER, STABLE, ingen argumenter. Returnerer `ORDER BY person_id, source_id`, så `getAll`'s
`.range()`-paginering er stabil. Hver række gates med `entitet_offentlig('person', person_id)`, som RLS på
`person_external_id` gør i dag.

Kolonner: formen fra `person_source_coordinate_legacy` (`person_id`, `source_id`, `legacy_line_code`,
`printed_number`, `generation_local`, `generation_global`, `kuld_label`) plus `printed_number_label text` og
`provenance_kind ∈ {'placement','legacy_external_id'}`.

- Én række pr. `person_external_id`-række (i dag 1.167). Har personen en gældende membership
  (`membership_is_current`), hvis record-placement hører til samme kilde, kommer linje (entryens `code`), nr.,
  slægtled og kuld fra placementen, og rækken får `provenance_kind='placement'`. Ellers kommer værdierne fra
  legacy-rækken, og rækken får `'legacy_external_id'`.
- `printed_number` (heltal) = de foranstillede cifre i placementens `printed_number`. Legacy-værdien er allerede
  heltal. `printed_number_label` = den trykte tekst (»15a«); for legacy `nr::text`. Sorteringen bevarer dermed
  sin form, og visningen får suffikset.
- En gældende membership uden legacy-række ville give en placement-række uden modpart. Målt: 0. RPC'en
  returnerer den alligevel, så intet tabes.
- Forventet forskel fra i dag for kilde 1 er netop **40 værdier: 35 `kuld_label` og 5 `printed_number_label`**.
  Nøglesættet `(person_id, felt)` måles og fastlåses i planen; et sæt, ikke et antal. De 15 kilde 1-rækker uden
  gældende membership (11 `unresolved`, 4 `mapped` uden identitet) og alle 576 kilde 3-rækker er uændrede legacy.

`person_source_coordinate_legacy` bliver stående til trin 6, så en tilbagerulning af klienten er ren.

### 4.3 Klienter

- **`packages/core`:** `RawExtId` får `nr_label?: string | null` og `provenance?: 'placement' | 'legacy_external_id'`.
  Visningen (`DetailPanel.tsx:84`, `sources.ts:20`, mobilens `person/[id].tsx:98` og `buildAux.ts:72`) bruger
  `nr_label ?? nr`. Linjehovedet vælges stadig som laveste `nr`; ved lige `nr` afgør `nr_label` (15a før 15b).
  Ny ren funktion `buildPersonFacts(rows)` i `packages/core/src/personFacts.ts` står for gruppering pr. faktum,
  udeladelser, rækkefølge og etiketter (§4.4) og testes i core.
- **Web:** `loadModel` henter koordinater med `getAll(() => supabase.rpc('public_person_source_coordinates'))`.
  Ved fejl skrives en advarsel, og der degraderes til `[]` som i dag. Der er bevidst intet fald tilbage til
  legacy-viewet, så en fejlslagen deploy ikke skjules. `fetchPersonDetail` henter fakta med
  `public_person_facts(numIds)` (union over `samme_som`-medlemmer, som narrativ og relationer) og erstatter
  `fetchProveniens`. En fejl giver teksten »Fakta kunne ikke hentes« i sektionen, ikke en tom sektion.
- **Mobil:** `load.ts` skifter til samme RPC og mapper til `RawExtId`; `tsc --noEmit` i CI er beviset. Ingen
  enhedstest.

### 4.4 Fakta-sektionen i `DetailPanel`

- **Hvad vises:** alle afklarede eller omstridte personfakta undtagen `forældrefamilie` (vises allerede som familie
  med kildelinje) og `forældre_ukendt` (har sin markering). `navn` vises, fordi det er her, de fleste bindinger er
  (239).
- **Rækkefølge:** navn og tilnavn; fødsel, dåb; titel, dekoration, adling, floruit, klosterindgang, overhoved;
  død, dødsårsag, begravelse. Inden for en type efter `date_min`, så `fact_id`.
- **Værdi:** konklusionens valgte påstand: `vaerdi_tekst` og/eller `date_raw` (originalteksten, invariant 5).
  `omstridt` får mærket »omstridt«. Har faktummet flere påstande, står de andre under »Andre udsagn«, hver med sin
  egen kilde.
- **Kilde, tre visninger der kan skelnes fra hinanden:**
  - **Bundet til bogens post:** `citation_label`/`record_label` fra bindingen, fx »DAA 2018-20, I-32«, med mærket
    »bundet til bogens post«.
  - **Fra den oprindelige import:** `source_label` og eventuelt »s. N«, fx »DAA 1939, s. 123« eller »DAA 2018-20«.
  - **Kilde ikke registreret:** når citationen mangler kilde. Faktummet vises alligevel (ingen tavse tab).
- Ordrette uddrag (`citat_tekst`) vises ikke (§8.4).
- Sektionen vises også, når personen ikke har prosa. Det er den primære gevinst for de 621.

## 5. Følger

- Ingen data ændres. To nye funktioner; ingen tabeller, ingen RLS-ændring.
- Læseren ser 35 kuld og 5 numre ændre sig (rettelser). For de 4 `mapped` uden identitet står 2 forkerte
  legacy-kuld tilbage, indtil identiteten afgøres (trin 6 / de fire `unresolved_text`).
- Kilde 1 og 3 forbliver asymmetriske (placement mod legacy) indtil trin 6, som i 5c-1.
- 5c-spec'ens åbne note (§5: `record_label` for en record uden binding med én accepteret placement) har ingen
  læserfølge her, fordi B11 kun viser etiketter fra publicerede bindinger. Den føres videre til trin 6.
- `get_advisors` forventes at melde de to nye SECURITY DEFINER-funktioner som eksponeret for `anon`, som for
  `public_family_sources`. Det er tilsigtet og noteres.

## 6. Prod

1. **To PR'er.** PR 1: DB (funktioner i `db-migrations.sql` og `schema.sql`, pg-tests, opgraderingstest fra prods
   skema, runbook). PR 2: core, web og mobil. PR 2 merges først efter ceremonien, så Vercel aldrig deployer en
   klient mod en manglende RPC.
2. **DDL-ceremoni (B2-form) fra projektejerens shell** efter PR 1's merge: privat runner efter husmønstret
   (`maal`, `go`, `dump`, `apply --jeg-mener-det --go`). Blokken er additiv i én transaktion; GO-koden binder
   commit og filer; dump med B1-disciplin. Bagefter `NOTIFY pgrst` og `get_advisors`. db-verify køres ikke mod
   prod. Øves på en stand-in med prods 2-minutters grænse. Varigheden noteres.
3. **Efter ceremonien, læse-kun som `anon`:** antal rækker fra begge RPC'er og fordelingen af `provenance_kind`.
   Bindingsniveauet tælles mod de forventede antal fra stand-in'en.
4. **Merge af PR 2** → Vercel. Browsertjek mod prod (§7).
5. **Fortrydelse (særskilt handling):** revert af PR 2 (Vercel redeployer), derefter `DROP FUNCTION` af de to.
   Ingen data er skrevet; legacy-viewet står. Dumpet er nødudvejen.

## 7. Færdigbevis

- **CI (pg-job):**
  - Begge RPC'er giver 0 rækker for en levende person og for en ikke-offentlig person, også kaldt som
    `authenticated`.
  - Bindingen udfyldes kun under alle fire betingelser. Hver betingelse brudt for sig giver NULL i `record_*`,
    mens faktummet stadig returneres.
  - Koordinater: `placement` ved gældende membership og legacy ellers; en membership gjort ugældende (sha-brud)
    falder tilbage til legacy.
  - Opgraderingstest fra prods skema.
- **CI (core/web):** `buildPersonFacts` (udeladelser, rækkefølge, flere påstande, omstridt, tre kildevisninger);
  linjehoved ved »15a/15b«; `tsc` for mobil.
- **Stand-in (kopi af prod):**
  - Forskellen mellem `public_person_source_coordinates` og `person_source_coordinate_legacy` er præcis det
    fastlåste sæt på 40 `(person_id, felt)`.
  - Fakta-RPC'en: antal fakta pr. kildevisning (bundet / import / ingen kilde), antal personer uden narrativ med
    mindst ét faktum (forventet 621), og antal bindinger der falder ud på betingelse 3. Kun antal; output til
    fil.
- **Prod-browser (anon, efter deploy):**
  - En person uden prosa viser fakta med kilde.
  - Et bundet faktum viser postreferencen.
  - En kuld-rettet person og en »15a«-person vises korrekt, og linjehovedet er uændret.
  - En kilde 3-person beholder sine koordinater.
  - En levende person har ingen fakta-sektion.
- **Status:** `status.md`-rækkerne »Læsere på placement/membership (5c-2)« og »Læserflade: fakta med
  kildehenvisning (B11)« hæves til `produktionsverificeret` for 2018-20 med dato. Trin 6's færdigbevis (b) er
  opfyldt for 2018-20, med bindingsandelen angivet (§8.2).

## 8. Afgørelser (venter på projektejeren; anbefaling først)

1. **5c-2's omfang.** *Anbefalet:* kun de offentlige læsere nu (§3). `red_person_grid`, `red_match_personer` og
   præsenslistens projektion flyttes til trin 6. De er redaktørflader, legacy-rækkerne er uændrede, og trin 6 skal
   alligevel røre dem, når 1939 får placements. *Alternativ:* alle Task 6-kontrakter nu, som 5c-spec'en §3
   oprindelig lovede. Det giver ca. en dobbelt så stor leverance og ingen ny læserværdi.
2. **Hvad tæller som »fakta med kildehenvisning« i trin 6's færdigbevis.** Langt de fleste kilder kommer fra den
   oprindelige import: kun 620 af ca. 5.500 viste fakta er bundet gennem trin 4. *Anbefalet:* begge niveauer
   tæller, de vises tydeligt forskelligt (§4.4), og færdigbeviset angiver andelen bundne. *Alternativ:* kun bundne
   fakta tæller. Så er B11 først opfyldt, når langt flere fakta er bundet, og det kræver afgørelser, som »ingen
   fulde afgørelsesark« (2026-09-27) har fravalgt.
3. **Uafklarede koordinater.** *Anbefalet:* de 15 kilde 1-rækker uden gældende membership og kilde 3's 576 vises
   fortsat fra legacy, mærket `legacy_external_id`, for at slægtstræet er komplet. Ledgeren har en disposition
   for hver. *Alternativ:* skjul dem (visionens »uafklaret er fail-closed skjult«). Så forsvinder 591 personer fra
   linjer og generationer.
4. **Ordrette uddrag.** *Anbefalet:* `citat_tekst` vises ikke nu. Uddrag fra kilde 3 kan stamme fra
   1939-narrativer, der ikke er publiceret, og RPC'en kan ikke se forskel uden en ny publiceringsgate.
   *Alternativ:* vis uddrag kun for kilde 1, hvor alle 541 narrativer er publiceret.

**Mine egne valg (kan rettes):** én fakta-RPC frem for RLS-læsning plus en bindings-RPC (én gate, ét kald; den
private del kræver alligevel SECURITY DEFINER); `navn` vises; udeladelsen af `forældrefamilie` og
`forældre_ukendt`; rækkefølgen i §4.4; to PR'er; dump trods additiv DDL (husets B1-disciplin, runneren findes);
intet klient-fald tilbage til legacy-viewet; mobil skifter loader uden fakta-sektion.

## 9. Uden for scope

Redaktørlæserne og præsenslistens projektion (hvis §8.1 følges); fjernelse af `person_external_id` og
legacy-viewet (trin 6); 1939's placements (trin 6); kildevisning for relationer ud over familiernes kildelinje;
fakta-sektion på mobil; ordrette uddrag (§8.4); konfidens fra bindingens oprindelse (2-05); `record_label` for
`unresolved_text` (§5).

## 10. Reviewlog

*(tom)*
