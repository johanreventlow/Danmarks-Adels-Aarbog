# Fuld sletning af en personprofil — design (2026-11-14)

Status: udkast til projektejerens godkendelse. Kortlægning: 58 steder i skemaet, hvor en person kan efterlade spor
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
- Efter sletningen findes personens id ikke i nogen række, der handler om personen. Den eneste tilladte rest er
  personens id-nummer i **andre** personers historik (fx en change_event på et familieled, hvor også 1791 stod), uden
  personens indhold.
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
- En kopi af personens indhold overlever i historikken, så sletningen kan fortrydes.

## 5. Det projektejeren har besluttet (2026-11-14)

1. Hård sletning, ingen tombstone, ingen indholdsløs slettelinje.
2. Bogens lag bliver stående.
3. Andre personers historik må beholde id-nummeret, ikke indholdet.
4. Kun redaktører; forhåndsvisning og bekræftelse før sletning.
5. `slet helt` må løfte skrivespærringen på de låste logs for netop den person.
6. Personens egne kildepersonas (bogens omtale) får efter sletningen en ny afgørelse »ikke en person«
   (afsnit 6.9), så de ikke vender tilbage som uafgjorte i Kildepersona-køen.

## 6. Hvordan (bundne valg)

### 6.1 Én funktion med forhåndsvisning

- `red_slet_person_helt_preview(p_person_id)` (læse-kun, redaktion): returnerer antal pr. sted, familier der slettes
  helt, Storage-stier der slettes, og **blokeringer** (afsnit 6.6). Svaret har en hash af forhåndsvisningen.
- `red_slet_person_helt(p_person_id, p_preview_sha256)` (redaktion): kører kun, hvis forhåndsvisningen genberegnet i
  transaktionen har samme hash (ingen ændring siden redaktøren så den). Alt i **én transaktion**; fejl = intet slettet.
- Den eksisterende `red_slet_person` bevares uændret (den er en almindelig sletning med historik og fortrydelse). UI'et
  får en separat, tydeligt mærket knap »Slet helt (kan ikke fortrydes)« med bekræftelse ved at skrive personens id.

### 6.2 Kontrolleret løft af append-only

- Append-only-triggerfunktionerne (`reject_*_mutation`, `trg_narrative_publication_event_append_only` osv. — fuld
  liste i kortlægningen, afsnit 4) får én undtagelse: DELETE tillades, når transaktionen har en purge-markør sat af
  `red_slet_person_helt` **og** den slettede række vedrører den markerede person. Markøren sættes med
  `set_config(..., true)` (transaktionslokal) og skal ikke kunne sættes af andre end funktionen (fx en privat
  tabel/rækkelås, som kun den definer-funktion skriver, frem for en ren GUC, som enhver session kan sætte).
- Triggerne forbliver enabled (`db-verify.sql` kræver det). Ingen `DISABLE TRIGGER`, ingen
  `session_replication_role` (kræver superuser og slår FK-tjek fra).
- UPDATE forbliver forbudt overalt.

### 6.3 Hvad der slettes

Alle steder fra kortlægningen, hvor rækken handler om personen. Grupper:

- **Kernen** (som i dag): fakta, påstande, kilder, konklusioner, noter, relationer, narrativer, record-bindinger,
  hændelsesankre (løsnes som i dag), external ids, `profiles.reventlow_person_id` (nulstilles), familieled.
- **Formidling**: stories, beskrivelser, forslag, `feed_pin` (alle nøgleformater, der bærer person-id), bogmærker,
  abonnementer, medier der **kun** hører til personen (inkl. varianter og Storage-filer).
- **Rettelsesjournaler**: `import_korrektion`, `paastand_korrektion` for personens rækker.
- **Logs** (via 6.2): personens publication-events og legacy-publikationer, identitetsstate og -events, identitets-
  kandidater, legacy-placement-dispositioner og de øvrige append-only-ledgers fra kortlægningen, hvor rækken vedrører
  personen.
- **Historik**: alle `change_event`-rækker om personens egne rækker; `change_set`, hvis subjekt er personen eller som
  efter sletningen er tomt; `change_set`-summaries, der nævner personens navn (fx `red_opret_person`'s, subjekt NULL —
  findes via sættets INSERT-event på personen). Fælles sæt med andres events bevares uden personens events.

### 6.4 Familier

- Personens familieled slettes.
- En familie, der derefter har højst én partner og ingen børn, slettes helt med sine fakta (vielse osv.) og
  evidenskæde; dens øvrige led slettes også. (1791: 742 og 743 forsvinder; 1823/1824 bliver stående uden familie og
  er fortsat foldet sammen med 815/816, hvis rigtige ægteskaber er 540/541 med 1198.)
- En familie med andre medlemmer tilbage bevares uden personen.
- `samme_som`-relationer til og fra personen slettes; sammenfoldede andre personer bevares.

### 6.5 Andres data

- Andres historik beholder id-nummeret (beslutning 3). Events i fælles sæt, der er *andres* rækker (fx en
  `family_member`-række for en ægtefælle, som nævner personens id), bevares.
- Andres publication-events og bindingshashes, der indeholder personens id (`narrative_publication_state`,
  `relation_binding_state`), bevares. Familiebindinger kan blive forældede (stale), som de også gør i dag ved en
  familieledssletning; det er det eksisterende revalideringsspor.

### 6.6 Blokeringer (forhåndsvisningen viser dem; sletningen afviser)

- Andre personers tekster indeholder `[[person:<id>|…]]`-link til personen. Redaktøren retter teksten først med den
  almindelige narrativredigering (så den andens publiceringshistorik opdateres korrekt).
- Medier delt med andre personer: koblingen til personen slettes, mediet og filen bevares.
- Personen er levende og har en brugerkonto: ikke en blokering; nævnes i forhåndsvisningen.

### 6.7 Storage

Filerne slettes efter transaktionen (Storage er ikke transaktionel). Funktionen returnerer stierne; Redaktion sletter
dem og viser dem, der fejlede, så redaktøren kan prøve igen. Sletningen i databasen står fast uanset.

### 6.8 Id-genbrug

Personens id må ikke kunne genbruges af en `max(id)+1`-allokering, så andres resterende id-nummer pludselig peger på
en ny person. Bygherren tjekker, om `person.id` altid kommer fra identitetssekvensen i de veje, der stadig er i brug,
og sikrer, at sekvensen ikke sænkes.

### 6.9 Personens kildepersonas

- Personens egne identitetsstate og -events slettes (6.3). Derefter skriver funktionen i samme transaktion en ny
  afgørelse på hver af personens kildepersonas: »ikke en person« (den eksisterende afvisningsstatus, hvis den betyder
  det; ellers afgør bygherren den nærmeste eksisterende), version 1, uden person-id, med redaktøren som afgører og en
  generisk begrundelse uden personens navn.
- Afgørelsen hører til bogens lag og er den eneste skrivning, sletningen efterlader. Den er rigtig for fejllæsninger
  som 1791 og forhindrer, at en GDPR-slettet person bliver oprettet igen fra køen.

### 6.10 Andres identitetshistorik (min afgørelse, ikke projektejerens)

- Andre kildepersonas' identitetsevents og kandidatrækker, der peger på personen (fx »post X blev først koblet til
  1791, siden til Conrad«), handler om den slettede og slettes. Den andens historik starter så ved næste version; køen
  og `red_source_persona_history` skal tåle hullet i versionsrækken og en manglende rang-1-kandidat.
- En persona, hvis **nuværende** afgørelse peger på personen, er personens egen (6.9).

### 6.11 Navne i andres tekster (min afgørelse, ikke projektejerens)

- Fjernes et `[[person:<id>|Navn]]`-link (6.6), kan navnet stå tilbage i den andens publiceringshistorik og
  `change_event`. Narrativerne er bogens ordlyd, og bogens lag bevares (beslutning 2), så det accepteres. Andres
  publication-events og hash-kæder røres ikke.

## 7. Prod og den første brug

- DDL i en ceremoni i projektejerens shell som de foregående trin (runner, GO-kode, dump før, fortryd-DDL).
- Den første sletning er 1791, udført af projektejeren i Redaktion efter DDL. Målt for 1791 på prod-kopien 13/11:
  17 steder, herunder 2 publication-events (det ene i cutover-sættet fra 6/9, som bærer alle personers baseline og
  derfor bevares uden 1791's event), 1 legacy-placement-disposition og 2 egne historikposter.
- Færdigbevis: tællingen for 1791 er 0 overalt (bortset fra id i andres historik), andre personers rækker er
  byte-ens før/efter (hash over alle andre rækker i de berørte tabeller), anon-tjek i browseren, og append-only-
  triggerne afviser fortsat DELETE uden for funktionen.

## 8. Test (krav)

- En fixtureperson med spor på alle 58 steder (eller dokumenteret, hvorfor et sted ikke kan forekomme) slettes; derefter
  er tællingen 0, og alle andre rækker er uændrede.
- Append-only-triggerne afviser DELETE uden markør, med markør for en anden person, og fra en anden session.
- Preview-hash: en ændring mellem preview og sletning afvises.
- Blokeringer: link i anden persons tekst afviser; delt medie bevares.
- Familieregel: 742/743-mønsteret (dublet med én anden partner) og en familie med børn.
- Rollegate: anon og medlem afvises.

## 9. Overladt til bygherren

- Navn og form på purge-markøren og præcis hvilke triggerfunktioner der skal ændres.
- Rækkefølgen af sletninger (FK-orden) og låsningen (genbrug af `red_slet_person`'s låse).
- Om `red_slet_person_helt` deler kode med `red_slet_person`.
- UI-detaljer i Redaktion ud over: separat knap, forhåndsvisning, bekræftelse med id.
- Hvordan summaries med navn findes, så længe der hverken er falske positive (andre personer) eller falske negative.
