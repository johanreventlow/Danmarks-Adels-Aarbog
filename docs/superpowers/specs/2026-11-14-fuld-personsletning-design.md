# Fuld sletning af en personprofil — design (2026-11-14)

Status: v2 (2026-11-14) — revideret efter planreview og projektejerens svar på slettegrafens Q1-Q11
(`docs/superpowers/plans/personsletning/slettegraf.md`, afsnittet »Afgørelser«). Reviewbudget: spec 1 fable-runde
(udført), plan 2 fable-runder (v1 og v2 udført) + én smal Opus-review af v2.1 (overskredet med en låse-spike, Task 0; noteret i decisions), kode 1-2 Opus/Codex-runder pr. DB-task; overskridelse noteres i
decisions. Kortlægning: 58 steder i skemaet, hvor en person kan efterlade spor
(gennemgået 2026-11-14 og målt for 1791 på en prod-kopi af 13/11). Afgør den åbne post »hvad skal en person-sletning
gøre ved `source_persona_identity`?« (decisions 2026-08-20) **anderledes end** dens anbefaling (tombstone +
udtømning): projektejeren vælger hård sletning uden nogen rest.

## 1. Hvorfor

En personprofil kan være en fejl, fx 1791 »fyenske Rytterreg.)«, der blev oprettet ved at et stykke af Conrads post
(1198, PDF 541) blev læst som en person. Det kan også være en testperson, eller en levende person, der efter GDPR
kræver at blive slettet. Fælles for dem: profilen burde aldrig have eksisteret. Sletningen skal derfor efterlade
**intet** om personen — ingen tekst, ingen fakta, intet familieled, ingen publicerings- eller ændringshistorik med
personens indhold, og heller ikke en indholdsløs linje om, at sletningen fandt sted.

Det sker sjældent, måske aldrig for GDPR. Men muligheden skal findes, og i dag findes den ikke: `red_slet_person`
afviser personer med publiceringshistorik og kildeidentitet, og de personer, den kan slette, efterlader en fuld kopi
i historikken (så sletningen kan fortrydes) og spor på ca. 15 andre steder.

## 2. Mål

- En redaktør kan slette én personprofil helt fra Redaktion.
- Før sletningen ser redaktøren en forhåndsvisning: hvad der slettes (antal pr. sted), hvilke familier der forsvinder,
  hvilke filer der slettes, og hvad der forhindrer sletningen.
- Efter sletningen findes personens id ikke i nogen række, der handler om personen. Tilladt rest er udtømmende:
  personens id-nummer i **andre** personers rækker og historik, og **bogtekst**, der står i andres eller fælles rækker:
  genimportkvitteringer (Q1), andres narrativhistorik (Q2, 6.11), et delt medies titel (Q8), vielsesfakta i
  bevarede familier (beslutning 7) og fritekst hos andre, som forhåndsvisningen viste til kontrol (Q9). Listen står
  i planens Global Constraints.
- Andre personer er uændrede, bortset fra de rækker, der direkte forbinder dem med den slettede (familieled,
  `samme_som`).
- Læsere, medlemmer og anon kan ikke se, at personen har eksisteret.

## 3. Ikke-mål

- **Bogens lag** røres ikke: `private.source_record` og dens observationer, tekster, mentions og fortolkninger, samt
  `private.source_persona` og dens placements. At teksten står på siden er stadig sandt (schema.sql-kommentaren ved
  `red_slet_person`). Projektejeren har accepteret, at en GDPR-slettet person stadig står i bogens transkription.
- Backups, Supabase-PITR, lokale dumps i `~/.private` og klient-cache (PWA, localStorage). De ældes ud; de er ikke
  en del af funktionen. Nævnes i runbooken.
- Brugerkonti (`auth.users`/`profiles`). En levende person, der også er bruger, slettes som bruger ad anden vej;
  sletningen nulstiller kun `profiles.reventlow_person_id`.
- Tombstone/soft-delete. Fravalgt af projektejeren (afsnit 1).
- En spærring på person-id'et mod genoprettelse. Personens kildepersonas står som »ikke en person« (6.9); en ny udgave
  med nye personas er altid en ceremoni, projektejeren godkender.

## 4. Anti-mål (fejl, selv om det »virker«)

- Sletningen rammer andre personers indhold, fx 815/816's ægteskab med Conrad, når 1791's dubletægteskaber fjernes.
- Halve rester: en familie med kun én partner og ingen børn, en tom post i en fælles historikpost, et dødt link.
- Append-only-beskyttelsen svækkes generelt. Den må kun løftes for netop den person, i netop den transaktion, inde i
  den ene funktion.
- En kopi af personens indhold overlever i historikken, så sletningen kan fortrydes. (Bogtekst i andres eller
  fælles rækker, jf. §2, er ikke en sådan kopi.)

## 5. Det projektejeren har besluttet (2026-11-14)

1. Hård sletning, ingen tombstone, ingen indholdsløs slettelinje.
2. Bogens lag bliver stående.
3. Andre personers historik må beholde id-nummeret, ikke indholdet. Præciseret 2026-11-14 (Q1, Q2): »indholdet« er
   personens egen profil; bogtekst i andres biografier og i fælles kvitteringer bevares.
4. Kun redaktører; forhåndsvisning og bekræftelse før sletning.
5. `slet helt` må løfte skrivespærringen på de låste logs for netop den person.
6. Personens egne kildepersonas (bogens omtale) får efter sletningen en ny afgørelse »ikke en person«
   (afsnit 6.9), så de ikke vender tilbage som uafgjorte i Kildepersona-køen.
7. Vielsesfakta i en familie, der bevares, bliver stående (6.4).
8. Er personen knudepunkt i en sammenfoldning med to eller flere andre, afvises sletningen, til de er koblet direkte (6.4).
9. (2026-11-14, slettegrafens Q1-Q11) Genimportkvitteringer røres ikke (Q1). En kørsel, der ikke længere kan
   fortrydes, er en advarsel, ikke en blokering (Q3); det samme gælder en `passed` kontrolkørsel (Q4). Fritekster
   hos andre, der kan nævne personen, vises til manuel kontrol uden at blokere (Q8, Q9). Personens egne
   familiebindinger til en bevaret familie slettes (Q6). »Ikke en person« får version n+1 (Q7).

## 6. Hvordan (bundne valg)

Revideret efter fable-review 2026-11-14 (fund K1-K5, V1-V7, M1-M6). Linjenumre er `schema.sql` på `main` 14/11.

### 6.1 Forhåndsvisning og sletning

- `red_slet_person_helt_preview(p_person_id)` (læse-kun): rollegaten `redaktion` kommer **før** enhver læsning, så
  funktionen ikke bliver et eksistens-oracle. Returnerer pr. sted de berørte rækkers id'er (ikke kun antal), familier
  og vielsesfakta der slettes eller bliver stående, Storage-stier, `samme_som`-komponenten, forældede narrativer og
  bindinger hos andre (6.5), blokeringer (6.6) og personens visningsnavn. Hash = sha256 over hele svaret.
- `red_slet_person_helt(p_person_id, p_preview_sha256)`: tager låsene (6.12), genberegner forhåndsvisningen **efter**
  låsene og afviser ved anden hash. Alt i én transaktion; fejl = intet slettet.
- **Ingen historik fra sletningen selv (K2):** funktionen afviser, hvis `app.change_set_id` allerede er sat (fremmed
  aktivt sæt, som l. 3312/4428), og åbner intet sæt. `log_change` skriver derfor intet. Test: ingen ny
  `change_set`/`change_event` efter sletningen.
- Den eksisterende `red_slet_person` bevares uændret. UI'et får en separat knap »Slet helt (kan ikke fortrydes)«;
  bekræftelse ved at skrive personens id, og dialogen viser navnet (så 1791 ikke forveksles med 1719). UI'et sletter
  det rå id, ikke den sammenfoldede profil, og siger det.
- Grants: `REVOKE … FROM PUBLIC, anon` med navngivne roller (db-rls 985-992), `GRANT EXECUTE … TO authenticated`;
  `SET search_path = pg_catalog, public, private`.

### 6.2 Kontrolleret løft af append-only (K1)

- **Manifest, ikke GUC.** En privat tabel `private.person_purge_manifest(xid, backend_pid, person_id, tabel, pk, grund,
  forrige_version)` efter
  mønstret i `identity_relation_update_prelock` (l. 7521-7551). Kun `red_slet_person_helt` skriver den; den beregner
  den fulde sletteliste, skriver manifestet, sletter, og **tømmer manifestet før retur**. Intet overlever commit (en
  overlevende række ville være den slettelinje, beslutning 1 forbyder). db-verify: manifestet er tomt.
- **Eksplicit tilladelsesliste.** De append-only-triggerfunktioner, der skal kunne slette (bl.a. den generiske
  `private.reject_evidence_mutation`, l. 916), får en tabel-tilladelsesliste med standard-afvisning. Bogens tabeller
  (`source_record`, `source_persona`, `source_observation*`, `interpretation`, `interpretation_party` m.fl.) står
  **aldrig** på listen. DELETE tillades kun, hvis `(pg_current_xact_id(), pg_backend_pid(), TG_TABLE_NAME, pk)` står i
  manifestet.
- **Uafhængigt tjek pr. `grund`** (`egen`, `hel_stroem`, `andres_ref`, `afledt`): triggeren efterprøver rækken efter
  slettegraf §3.2 med Q5-rettelsen. `hel_stroem` tillader ældre events med NULL eller en anden person, når personaens
  nuværende afgørelse peger på personen.
- Triggerne forbliver enabled. Ingen `DISABLE TRIGGER`, ingen `session_replication_role`. TRUNCATE-triggerne røres
  ikke. UPDATE forbliver forbudt **uden undtagelse**: `narrative_legacy_publication` har ingen append-only-trigger, og
  dens validator tillader allerede `latest_event_id := NULL` (l. 14035).
- db-verify asserter funktionskroppene (tilladelseslisten indeholder ingen bogtabel) og den nye funktions
  låserækkefølge (M4).

### 6.3 Hvad der slettes

Alle steder fra kortlægningen (S1-S58 + reviewets M5: `identity_control_parent_event` når dens `parent_card` slettes),
hvor rækken handler om personen:

- **Kernen:** fakta, påstande, kilder, konklusioner, noter, relationer, narrativer, record-bindinger, external ids,
  `profiles.reventlow_person_id` (nulstilles), familieled, hændelser forankret i personens rækker (løsnes som i dag)
  og hændelser med personen som subjekt under en andens narrativ (S26), samt S19/S20 fra kortlægningen.
- **Formidling:** stories, beskrivelser, forslag, `feed_pin` (alle nøgleformater med person-id), bogmærker,
  abonnementer, medier der kun hører til personen (inkl. varianter; filer efter 6.7).
- **Rettelsesjournaler:** `import_korrektion`, `paastand_korrektion` for personens rækker.
- **Logs (via 6.2):** personens publication-events og legacy-publikationer, identitetsstrømme (6.9/6.10),
  kandidatrækker, legacy-placement-dispositioner og de øvrige ledgers fra kortlægningen, hvor rækken vedrører personen.
- **Promotions (K5, Q5, Q6):** `interpretation_promotion`-rækker, hvis mål er personens egne rækker, slettes, også
  når fortolkningen sidder på en andens record (fx `relation_person_create` fra en forælders post). Personens egne
  personas' bindinger til en familie, der bevares, slettes også (Q6). Afhængige `relation_reopen`/
  `text_revision_reconciliation` slettes først. En promotion fra **en andens** persona til en familie, der slettes
  (fx en ægtefælles `relation.marriage`), er en **blokering** (6.6).

### 6.3a Historik på eventniveau (K3)

- Slet hver `change_event`, hvis række er en af de slettede rækker (personens egne, de slettede familiers rækker og
  deres evidens, den andens familieled i en familie der slettes helt).
- Events slettes også, når deres `foer` eller `efter` bærer personens indhold, selv om rækken er slettet tidligere
  (lukningen over nøglestier, slettegraf §2.2-2.3).
- Et `change_set` slettes kun, når (a) det ikke har events tilbage, (b) det ikke har indgående FK (publication-event,
  `paastand_korrektion`, `reimport_case_batch`; S56), og (c) det havde events, der blev slettet nu, **eller** har
  personen som subjekt og `reverterer_id IS NULL` (fx `withdraw_legacy_narrative`, der ingen events har), **eller**
  havde en publication-event/`paastand_korrektion`, der slettes nu — eller det er et fortryd-sæt (`reverterer_id`)
  for et sæt, der slettes (slettegraf §2.4). Fortryd-sæt for bevarede sæt røres ikke. Sletteorden: fortryd-
  sæt før det sæt, de peger på.
- `change_set` med personen som subjekt, men med andres events (fx `red_opret_union`, l. 8023), bevares med de andres
  events; summary med kun id er dækket af beslutning 3 (M1). Summaries med navn (`red_opret_person`, l. 8641, og dens
  »Fortrød: …«-kopi) forsvinder, fordi sættene slettes efter reglen ovenfor; bygherren beviser, at der ikke findes
  andre summaries med navn.
- `red_fortryd_change_set` på et bevaret fælles sæt efter sletningen skal fejle lukket eller give et korrekt resultat
  (test, med og uden force). Den må aldrig genskabe en række, der hører til den slettede (fx en `family`-række), og
  afviser (`FORTRYD_DOED_LINK`) at genskabe tekst med et link til en person, familie eller et medie, der ikke findes.

### 6.4 Familier og identitet

- Personens familieled slettes.
- En familie, der derefter har højst én partner og ingen børn, slettes helt med fakta og evidenskæde; dens øvrige led
  slettes også. (1791: 742/743 forsvinder; 1823/1824 bliver stående uden familie og er fortsat foldet sammen med
  815/816, hvis rigtige ægteskaber er 540/541 med 1198.)
- En familie med andre medlemmer tilbage bevares uden personen.
- **Vielsesfakta (projektejeren 2026-11-14):** bevares familien (børn eller anden partner tilbage), bevares også dens
  vielsesfakta med evidens; de hører også ægtefællen til og bærer ikke den slettedes navn. Slettes familien (6.4 ovenfor),
  slettes vielsen med den. Forhåndsvisningen viser hvilke vielser der bliver stående.
  **Tilføjet 2026-11-20 (review 37 P1+P2, projektejeren):** var personen ikke-offentlig før sletningen
  (`NOT public.person_offentlig`), slettes også vielser på bevarede familier, hvor personen var partner, med hele
  evidenskæden og historikken (ellers bliver de offentlige via `family_offentlig`). Forhåndsvisningen viser
  `vielser_slettes` og `vielser_staar` (kun dem, der faktisk står).
  **Udvidet 2026-11-20 (løsning A, projektejeren):** for en ikke-offentlig person slettes ALT familieindhold (som for en
  slettet familie: fakta med evidens, noter, narrativer, hændelser, stories, forslag, relationer med familieende) på
  bevarede familier, hvor personen var partner eller barn — også tidligere (fortrudte) rækker i historikken. Familien og
  de øvrige medlemskaber bevares. Fail-closed, også hvis familien bliver offentlig bagefter. Forhåndsvisningen viser
  `familieindhold_slettes` pr. familie (erstatter `vielser_slettes`) og `vielser_staar`. Fra 2026-11-20 (Codex-fund B)
  udledes de berørte familier af hele sletteplanen, med kategorierne `fakta`, `noter` (også på familiens fakta og
  relationer), `narrativer`, `haendelser`, `stories`, `relationer` (familien eller dens fakta som ende), `forslag` og
  `historik` (antal slettede historik-events om familien, uden medlemskaber), så også en familie med fx kun en story,
  en relation eller kun historik vises.
  **Undtagelse 2026-11-20 (projektejeren):** en kobling *direkte* mellem et billede og en sådan bevaret familie (fx
  forældrenes familiefoto, når et levende barn slettes) bevares med sin historik, og billedet låses
  (`maa_publiceres=false`, vist under `medier_skjules`), så redaktionen kan finde og genfrigive det. Et billede, der kun
  var koblet til slettet familieindhold (fx et vielsesfoto på vielsen), slettes helt inkl. filen. På en bevaret
  kobling står evidenskæden (påstand, citat, konklusion), mens noter og forslag på den slettes med historik.
  Tidligere (slettede/fortrudte) hændelser på personen eller en sådan familie fjernes også fra historikken: deres
  snapshot har kun id+feed_status, så ejerskabet kræver et entydigt bevis pr. hændelse: et sæt, som feed-dommen åbnede
  for netop den hændelse (med personen/familien som subjekt), eller et sæt, hvor hvert slettet narrativ var personens
  eller familiens (kaskadesletningen). Et blandet sæt beviser intet; andres hændelses-events og sættet bevares.
- **`samme_som` (projektejeren 2026-11-14):** har personen to eller flere identitetsnaboer (andre personer, der kun er
  forbundet gennem den), er det en **blokering** (6.6); en redaktør kobler dem direkte først. Med én nabo slettes kanten,
  og naboen er uændret. Forhåndsvisningen viser komponenten.
- Låse ved familier: også `lock_family_rows` (l. 18910).

### 6.5 Andres data

- Andres historik beholder id-nummeret (beslutning 3).
- Andres publication-events og bindingshashes bevares. Forhåndsvisningen lister de narrativer og familiebindinger
  hos andre, der bliver forældede (V5); personens egne bindinger slettes (Q6): `narrative_publication_state` (l. 14978-15005) medtager accepterede
  medhovedpersoner, så når personens persona afvises (6.9), ændres en anden persons tilstandshash på samme record.
  Revalidering sker ad det eksisterende spor.
- Kandidatkørslers `candidates_sha256`/`candidate_count` og `identity_control_run`-hashes stemmer ikke længere efter
  sletning (M2). Ingen kode genberegner dem i dag; det skrives som kendt konsekvens og må ikke blive en gate.

### 6.6 Blokeringer (forhåndsvisningen viser dem; sletningen afviser)

- `[[person:<id>|…]]` i **enhver** prosakolonne hos andre (V2): `narrative`, `note`, `story.tekst`,
  `entity_description.tekst`, `haendelse.klausul`, `suggestion` m.fl. — skannet med `parse_mentions`, ikke kun via
  `text_mention`. Redaktøren retter teksten først.
- Promotions, der hører til en andens persona (6.3, K5).
- En identitetskontrolkørsel, der endnu ikke er `passed` eller `failed` (også `sealed`), og som omfatter personens
  personas, personen som kandidat eller på et forældrekort (slettegraf §4.3).
- En åben reimport-/C3-batch, en `finalized` batch, der ikke er aktiveret, en gyldig `issued` autorisation, eller en
  `publication_identity`, der er den eneste for sin B-batch (slettegraf §4.4 med præciseringerne); `persona_awaiting_control`.
- En andens påstand, hvis værdi er personen eller en familie, der slettes (S20, NY-A).
- `[[family:…]]`/`[[media:…]]`-links til en familie eller et medie, der slettes.
- **Advarsler, ikke blokeringer:** kørsler, der ikke længere kan fortrydes (Q3, alle fortrydelsesveje); en `passed`
  kontrolkørsel, der bliver `failed` (Q4); forældede bindinger hos andre (6.5).
- **Til kontrol, ikke blokering (Q8, Q9):** fritekster hos andre og titler på delte medier, der kan nævne personen.
- Personen er knudepunkt i en `samme_som`-komponent med to eller flere andre (6.4).
- Medier delt med andre: ingen blokering; koblingen slettes, mediet og filen bevares. **Tilføjet 2026-11-20 (review 37
  P1+P2):** var personen ikke-offentlig, får hvert bevaret medie, personen var afbildet på, `maa_publiceres=false` i
  samme transaktion (en redaktør må frigive det igen). Intet sæt er åbent, så ændringen efterlader ingen historik.
  Forhåndsvisningen viser dem som `medier_skjules`.
- Levende person med brugerkonto: ingen blokering; nævnes i forhåndsvisningen.

### 6.7 Storage (V3)

Stier skrives i transaktionen til en privat udbakke (kun bucket + sti, intet person-id). Redaktion sletter filerne
efter commit og tømmer udbakken pr. bekræftet fil; en fejlet fil står i udbakken og vises igen, til den er væk. Da
stierne er indholdsadresserede og ikke indeholder person-id, er udbakken ikke en slettelinje.

### 6.8 Id-genbrug (V6)

- Gælder `person`, `narrative`, `fact`, `relation`, `assertion`, `family`, `media` og `change_set`.
- Sekvensgulvet (`db-migrations.sql` 4826-4860) bruger i dag også max i `change_event`; efter sletningen beskytter
  kun sekvensens `last_value`. Krav: ingen aktiv skrivevej allokerer med `max(id)+1` eller sænker en sekvens
  (`red_fortryd_change_set`'s fallback l. 9558 rettes; v1-narrativskriveren l. 12648 er slået fra ved kontrakt v2 og
  bekræftes død). db-verify-assert + test: slet højeste id, opret ny, id'et genbruges ikke.

### 6.9 Personens kildepersonas (K4)

- For hver persona, hvis **nuværende** afgørelse peger på personen, slettes **hele** identitetsstrømmen (også ældre
  events uden person-id, fordi de kan bære indhold om personen, fx `deceased.clause_years`).
- Derefter skrives version n+1 (n = den slettede strøms højeste version, aflæst før sletningen og båret i manifestet;
  Q7) med status `rejected` og en **ny oprindelse `person_purge`** i
  `private.decide_source_persona_identity`, med fast evidence `{"reason":"not_a_person"}`, uden person-id, uden navn.
  Køen viser allerede `evidence->>'reason'` (l. 11046), så redaktøren kan skelne den fra »different«.
- `rejected` med version ≥ 1 forhindrer genoprettelse: `person_create`/`legacy_match` kræver version 0 (l. 10470,
  10478), og `relation_person_create` kræver `unresolved` + `new_person_needed` (l. 10501).
- Funktionen tager samme låse som `red_afgoer_source_persona` (kildelåsen `daa-identity-candidates:<source>`) og
  respekterer `persona_awaiting_control` (6.6).

### 6.10 Andres identitetshistorik (min afgørelse)

- Andre personas' identitetsevents og kandidatrækker, der peger på personen, slettes. Den andens historik starter så
  ved næste version. `red_source_persona_history` tåler hullet (ren liste, l. 11178-11192), og køens `best_tier` tåler
  en manglende rang 1 (NULL) (M3).

### 6.11 Navne i andres tekster (min afgørelse)

- Navnet i et fjernet link kan stå tilbage i den andens publiceringshistorik og `change_event`. Narrativerne er bogens
  ordlyd, og bogens lag bevares (beslutning 2). Andres publication-events og hash-kæder røres ikke. Bekræftet af
  projektejeren 2026-11-14 (Q2).

### 6.12 Låse og samtidighed

Rettet 2026-11-14 (planreview V-1): rækkefølgen er slettegraf §6.2 L1-L13 — kontrakt delt → rollegate →
`lock_reimport_writer` (sorteret) → kildelås `daa-identity-candidates:<source>` **eksklusiv**, sorteret efter kilde →
`source_record FOR UPDATE` for personens records (L5b; mod narrativskriverne) → persona/identitet `FOR UPDATE` →
`samme_som_mutation` + generation → `LOCK change_set IN ROW EXCLUSIVE MODE` →
source/external-id → `lock_identity_people` → `lock_family_rows` → genberegn låsemængden (drift → afvis) og preview.
Kildelåsen sidst gav en låsecyklus mod `red_afgoer_source_persona`. Funktionen kommer på db-verify's liste over
låserækkefølger (M4).

**Eksistensvagt (V2-5, godkendt af projektejeren).** Polymorfe rækker kan ikke længere oprettes eller flyttes, så
de peger på en person, familie, et faktum eller en relation, der ikke findes. Det gælder `fact`, `note`,
`narrative`, `story`, `suggestion`, `relation`, `assertion`, `conclusion`, `haendelse`, `entity_description` og
feed-pins. Det gælder også en skrivning fra en forældet redaktørside efter sletningen. Vagten udvider det
eksisterende `enforce_relation_evidence_target` og låser målet som en FK. Et faktum kan ikke slettes, så længe der er
evidens på det (som relationer i dag). Målt 14/11: 0 forældreløse rækker i prod-kopien, bortset fra note 72 på den
tidligere slettede familie 54. Den slettes i DDL-ceremonien efter projektejerens afgørelse 14/11.

**Ingen skrivepause.** Andre redaktører skriver videre under en sletning. Sletningen giver op efter 5 s ventetid på en
enkelt lås eller 30 s i alt og ændrer da intet. Deadlock eller timeout vises som »Prøv igen om lidt«.

## 7. Prod og den første brug

- DDL i en ceremoni i projektejerens shell som de foregående trin (runner, GO-kode, dump før, fortryd-DDL). Et nyt
  dump tages umiddelbart før sletningen af 1791: fortryd-DDL fjerner funktionerne, men fortryder ikke en udført
  sletning.
- Generalprøve 2 på en separat kopi: en person fra en aktiveret genimportkørsel slettes; `db-verify.sql` grøn, og
  fortrydelsen af kørslen fejler lukket.
- **Generalprøve på en restoret prod-kopi med planner-statistik:** forhåndsvisning og sletning af 1791, målt køretid
  under `authenticated`-rollens timeout (lukningen over `change_event` bruger jsonb-opslag), og **hele `db-verify.sql`
  grøn efter sletningen**.
- Den første sletning er 1791, udført af projektejeren i Redaktion efter DDL. Målt for 1791 på prod-kopien 13/11:
  17 steder, herunder 2 publication-events (det ene i cutover-sættet fra 6/9, som bevares uden 1791's event), 1
  legacy-placement-disposition og 2 egne historikposter.
- Færdigbevis: tællingen for 1791 er 0 overalt (bortset fra id i andres historik), andre rækker byte-ens før/efter
  (hash over alle ikke-slettede rækker i de berørte tabeller), kun tilladt rest ved en inventaruafhængig søgning,
  manifest og udbakke tomme (eller fejlede filer vist i Redaktion og janitor-tjek 0), ingen ny historikrække,
  anon-tjek i browseren, og append-only-triggerne afviser fortsat DELETE uden for funktionen.

## 8. Test (krav)

- En fixtureperson med spor på alle steder (eller dokumenteret, hvorfor et sted ikke kan forekomme) slettes; derefter
  er tællingen 0, og alle andre rækker er uændrede.
- **Mekanisk vagt:** en test fejler, når en ny tabel eller kolonne med person-reference (FK, polymorf type/id eller
  kendt jsonb-nøgle) kommer til uden at stå i sletteinventaret.
- Append-only-triggerne afviser DELETE uden manifest, med manifest for en anden person/transaktion/backend, og for en
  bogtabel uanset manifest.
- Ingen ny `change_set`/`change_event`; afvisning ved fremmed aktivt sæt.
- Preview-hash: en ændring af id-mængden mellem preview og sletning afvises, også ved uændret antal.
- Blokeringer: link i hver prosakolonne; andens promotion; åben kontrolkørsel; delt medie bevares.
- Familieregel: 742/743-mønsteret og en familie med børn; vielsesfakta efter projektejerens svar.
- `red_fortryd_change_set` (med og uden force) på et bevaret fælles sæt efter sletningen.
- Samtidighed: sletning mod parallel identitetsafgørelse, publicering og kandidatkørsel.
- Id-genbrug: slet højeste id, opret ny.
- Rollegate og oracle: anon og medlem afvises, før noget læses.

## 9. Overladt til bygherren

- ~~Den præcise slettegraf~~ — leveret: `docs/superpowers/plans/personsletning/slettegraf.md`.
- Navne på manifest- og udbakketabeller og præcis hvilke triggerfunktioner der ændres.
- Om `red_slet_person_helt` deler kode med `red_slet_person`.
- UI-detaljer ud over 6.1.
- Beviset for, at der ikke findes andre summaries med navn end dem i 6.3a.
