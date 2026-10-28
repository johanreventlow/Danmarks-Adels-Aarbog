# Spor 1e — bevisernes dækning (Codex gpt-6.1-terra, reasoning high)

> Rå Codex-output, screenet. Kommandolog revideret: ingen adgang uden for den rene eksport. Opus-afvejning: `afvejning-codex.md`.

## Sammendrag

Beviserne viser betydeligt arbejde med drift, rollback og negative tilfælde. De viser ikke en ensartet, fuldstændig produktionskontrol for hele kæden.

Den alvorligste konkrete svaghed, jeg fandt, er trin 5c’s fasemåling: Den kan sige `bundet`, selv om forventede persona-placements og memberships mangler. Det er en svaghed i **eftermålingen**; det er ikke i sig selv bevis for, at produktionskørslen mangler dem.

`db-verify.sql` kan desuden afslutte grønt med oversprungne kontroller eller ikke-gældende memberships. De forhold skal læses særskilt.

Trin 5b’s kendte 2a-digest dækker de oprindelige 210 bindinger. En senere rapport dokumenterer begrænsningen og tilføjer en bredere digest.

Trin 1–4 og 5a har nyttige, men afgrænsede beviser. Syntetiske prøver, restore og menneskelig stikprøve kan ikke alene bevise, at alle produktionsdata er korrekte.

## Fund

### 1e-01 — Trin 5c · Alvor: P1

**Sted:** `.claude/skills/daa-extract/scripts/fix_150_maal.sql:55`

**Påstand:** Fasemålingen kan rapportere `bundet`, selv om ikke alle placerede hovedpersoner med accepteret identitet har persona-placement og membership.

**Evidens:** `bundet` kræver `record_placements>0`, `persona_placements<=record_placements` og `memberships=med_identitet`. Begge sidste tal kan være nul; der er ingen sammenligning med den forventede mængde hovedpersoner. Runbooken beskriver derimod `bundet` som placements og memberships for de placerede hovedpersoner med accepteret identitet: `docs/runbooks/150-placement-prod.md:69`.

**Konsekvens:** En tilstand med record-placements, men ingen persona-placements eller memberships, kan bestå de nævnte ligheder, hvis ledger, slægtsstatus og publicering også opfylder betingelserne. En grøn fasemåling beviser derfor ikke den beskrevne fuldstændighed. Ceremonien har yderligere kontroller; fundet fastslår ikke, at denne tilstand faktisk findes i prod.

**Forslag:** Sammenlign de forventede og faktiske nøgler med anti-joins i begge retninger: forventet record → principal persona-placement → accepteret identitet → begge memberships. Tilføj en negativ test, hvor en forventet persona-placement og dens membership mangler, mens øvrige betingelser er opfyldt.

**Sikkerhed:** Verificeret ved læsning af prædikatet; den konkrete tilstand er et statisk modeksempel, ikke kørt mod database.

### 1e-02 — `db-verify` og 5c · Alvor: P2

**Sted:** `db-verify.sql:10387`

**Påstand:** En grøn `db-verify.sql` er ikke en assertion om, at alle placement-memberships er gældende.

**Evidens:** Kontrollen udskriver `PLACEMENT_MEMBERSHIP_NOT_CURRENT n=...` som `NOTICE` og kaster ikke fejl ved et positivt antal. Hjælperen tæller faktisk ikke-gældende linjememberships i `db-migrations.sql:26190`. Testen verificerer, at en ændret identitet kan give tallet 1: `tests/sql/test-placement-membership.sql:88`.

**Konsekvens:** En kørsel kan afslutte uden SQL-fejl, selv om `n>0`; hvis `client_min_messages` dæmper `NOTICE`, kan tallet også være usynligt. Det er en helbredsmåling med vilje, men den kan ikke bruges som automatisk grønt bevis for nul drift. Runbookens særskilt observerede `n=0` er stærkere end blot betegnelsen grøn: `docs/runbooks/150-placement-prod.md:113`.

**Forslag:** Lad en produktionsgate eksplicit assert’e det forventede antal, eller udskriv et maskinlæsbart resultat og kræv, at runneren kontrollerer det. Behold eventuelt den ikke-blokerende helbredsmåling til almindelig drift.

**Sikkerhed:** Verificeret ved læsning.

### 1e-03 — Tværgående `db-verify` · Alvor: P2

**Sted:** `db-verify.sql:7992`, `db-verify-media.sql:389`, `tests/sql/run-db-verify-disposable.sql:81`

**Påstand:** En succesfuld fuld verifier-kørsel garanterer ikke, at storage-politikkerne blev testet.

**Evidens:** Begge verificeringsfiler returnerer efter en `NOTICE`, hvis storage-kataloget eller media-bucketen mangler. Disposable-wrapperen kræver efterfølgende, at syv dblink-gates blev udført, men har ingen tilsvarende assertion for storage-testen.

**Konsekvens:** En manglende bucket kan give exit 0 og wrapperens afsluttende OK uden en faktisk rollebaseret prøve af storage-politikkerne. Ved dæmpede notices kan overspringet være usynligt. #153-rapporten oplyser selv denne begrænsning og tæller den ikke som #153-dækning: `docs/evidensbaseret-genimport/reimport-writer-153-rehearsal.md:100`.

**Forslag:** Adskil resultatet i `PASS` og `SKIP` med maskinlæsbar optælling. I miljøer, hvor storage-politikker er en påkrævet gate, skal manglende forudsætninger fejle lukket.

**Sikkerhed:** Verificeret ved læsning.

### 1e-04 — Trin 5b · Alvor: P2

**Sted:** `docs/evidensbaseret-genimport/relationspersonas-5b-2b-iii-bevis.md:88`, `docs/evidensbaseret-genimport/aegteskabsnumre-244-bevis.md:37`

**Påstand:** Den uændrede 2a-tupel-digest beviser ikke, at senere bindinger er uændrede.

**Evidens:** #244-rapporten forklarer, at digesten udvælger promotion-rækker uden nøglen `supersedes_promotion_id`; siden 2b-i skrives nøglen også ved første binding med JSON-null. Den angiver derfor dækningen som de 210 ældre bindinger. #244-rapporten rapporterer også en separat digest over gældende bindinger, som ændrer sig ved genbindingerne.

**Konsekvens:** En ændring i en senere binding kan sameksistere med en uændret 2a-digest. Digesten kan stadig sige noget om det oprindelige 2a-udsnit, men må ikke læses som en kontrol af alle bindinger. Den anvendte private måle-SQL var ikke tilgængelig under læseforbuddet; jeg har verificeret rapporternes beskrivelse, ikke genudført forespørgslen.

**Forslag:** Angiv mængde og antal direkte ved hver digest, og brug en nøglebaseret digest over alle relevante gældende bindinger til den bredere påstand. Bevar en separat historik-digest, hvis historiske rækker også skal sikres.

**Sikkerhed:** Verificeret i dokumentationen; SQL-beregningen er indirekte dokumenteret.

### 1e-05 — Trin 5a · Alvor: P2

**Sted:** `docs/evidensbaseret-genimport/identitetsvej-5a-bevis.md:11`, `docs/evidensbaseret-genimport/identitetsvej-5a-bevis.md:94`

**Påstand:** Rapportens webspor viser RPC- og payloadparitet, men prøver ikke den faktiske webkø ende til ende mod bevisbasen.

**Evidens:** Indledningen beskriver afgørelse gennem webkøens RPC; afsnittet om webspor siger, at webkøen ikke blev startet mod arbejdsbasen, og at en payload fastlagt i vitest blev sendt som `authenticated`.

**Konsekvens:** RPC’en kan have skrevet den forventede evidens, selv om en fejl i den virkelige webklients indlæsning, visning eller afsendelse ville forhindre eller ændre redaktørens afgørelse. Rapporten beskriver selv prøveformen, men dens korte sammenfatning kan læses bredere.

**Forslag:** Formulér resultatet som RPC-payloadparitet og tilføj en separat browser-til-database-prøve med en reel afgørelse, hvis websporet skal kaldes ende til ende.

**Sikkerhed:** Verificeret ved læsning.

## Dom pr. område

- **Trin 1 — solidt.** Cutover-testen prøver konkret drift i live-baseline og kræver den specifikke fejl; rehearsalrapporten afgrænser samtidig sit syntetiske restore-bevis. Det beviser ikke i sig selv produktionsindholdet.
- **Trin 2 — solidt.** Writer-prøven kontrollerer en konkret afvisningskode og uændrede rækkeantal ved ugyldig source-evidence. Rapporten skelner mellem lokale tests og produktionsautorisation.
- **Trin 3 — solidt men overbygget.** Rapporten skelner syntetisk prøve, restore-forsøg, fejl og genforsøg; dens hash- og talbeviser er nyttige, men den private måle- og produktionshistorik kunne ikke genafspilles her.
- **Trin 4 — solidt men overbygget.** `CONTROL_TARGETS_OK` sammenligner en sorteret mængde identiteter, ikke blot antal. Det beviser den valgte MATCH-mængde, ikke semantisk korrekthed af alle forslag; rapporten oplyser selv stikprøvens og de uafgjorte forslags begrænsninger.
- **Trin 5a — hul.** Kandidat-writertesten har præcise negative assertions, men webprøven er ikke fuld ende til ende, og kalibreringens facit er cirkulært. Rapporten angiver selv sidstnævnte som en øvre grænse.
- **Trin 5b — solidt men overbygget.** Der er konkrete negativtests og senere en bredere bindingsdigest, men den gamle digest er let at overvurdere og dækker ikke senere bindinger.
- **Trin 5c — hul.** Ceremonien har mange kontroller, men den efterfølgende fasemåling beviser ikke den medlemskabsfuldstændighed, dens beskrivelse giver indtryk af.
- **Fælles verifier — hul.** Skip og helbredstal kan være forenelige med exit 0; grøn status skal derfor ledsages af dokumenterede dæknings- og resultatkrav.

## Læst fuldt

Følgende er fuldt læste filer eller sammenhængende sektioner; øvrigt er læst via søgning og udsnit. Listen holder sig under loftet på 40.

- `docs/evidensbaseret-genimport/source-evidence-149a-rehearsal.md` — hele.
- `docs/evidensbaseret-genimport/2018-20-fuld-koersel.md` — hele.
- `docs/evidensbaseret-genimport/relationspersonas-5b-2b-iii-bevis.md` — hele.
- `docs/runbooks/150-placement-prod.md` — hele; eksporten indeholder ingen separat 5c-bevisrapport.
- `tests/sql/run-db-verify-disposable.sql` — hele.
- `.claude/skills/daa-extract/scripts/fix_150_maal.sql` — hele.
- `.claude/skills/daa-extract/scripts/interpretation_transfer_digests.sql` — hele.
- `docs/evidensbaseret-genimport/narrative-record-key-152-rehearsal.md` — linje 1–38, 125–146, 283–305, 350–364 og 615–628.
- `docs/evidensbaseret-genimport/reimport-writer-153-rehearsal.md` — linje 1–32, 75–106, 170–193 og 435–450.
- `docs/evidensbaseret-genimport/identitetsvej-5a-bevis.md` — linje 1–106.
- `docs/evidensbaseret-genimport/aegteskabsnumre-244-bevis.md` — linje 1–80.
- `.claude/skills/daa-extract/scripts/fix_150_placement.sql` — linje 28–69, 196–245 og 258–336.
- `.claude/skills/daa-extract/scripts/control_model.py` — linje 175–205.
- `tests/sql/test-identity-candidates.sql` — linje 125–210.
- `tests/sql/test-placement-membership.sql` — linje 80–105.
- `tests/sql/test-150-ceremoni.sh` — linje 84–106.
- `tests/sql/test-narrative-record-cutover.sql` — linje 350–380, 400–430 og 460–480.
- `tests/sql/test-reimport-writer.sql` — linje 360–382.
- `db-migrations.sql` — linje 23828–23890, 25910–25978 og 26156–26200.
- `db-verify.sql` — linje 7980–8005 og 10360–10389.
- `db-verify-media.sql` — linje 380–405.

Styringsgrundlaget, projektinvarianterne og systemkortet blev også gennemgået, men værktøjsoutputtet var afkortet; jeg regner dem derfor ikke som fuldt læste.

Vigtigste søgninger: `SPRINGER OVER`, `client_min_messages`, `RAISE NOTICE`, `>= 0`, `supersedes_promotion_id`, `tupel.digest`, `PLACEMENT_MEMBERSHIP_NOT_CURRENT`, `CONTROL_TARGETS_OK`, `EXCEPT`, `count(`, `hash` og `FIX150_OK`.

## Hvad jeg ikke nåede

Jeg har ikke gennemgået alle bevisrapporter, SQL-tests, ceremonier eller CI-forløb. Jeg har ikke genudført tests eller undersøgt produktions- eller restoredata. Private målescripts bag flere historiske rapporter var uden for den tilladte eksport; deres præcise beregninger er derfor ikke selvstændigt verificeret. Jeg har heller ikke fundet grundlag for at erklære alle øvrige kontroller korrekte, blot fordi de udvalgte eksempler så rimelige ud.

| Rapport/kontrol | Påstand | Faktisk målt | Dækker |
|---|---|---|---|
| Trin 1: #152 rehearsal og cutover-test | Cutover, drift og recovery virker | Syntetisk restore samt fixtures, bl.a. specifik afvisning ved baseline-drift | **Delvist** — dækker prøvede scenarier, ikke produktionsmængden |
| Trin 2: #153 rehearsal og writer-test | Writer afviser ugyldige input uden delvis skrivning | Specifik fejlkode og før/efter-antal i en fixture | **Delvist** — den prøvede fejlklasse, ikke alle mulige writes |
| Trin 3: #149a rehearsal | Source-evidence virker på rigtige boginput og restore | Manifest med 591 elementer, restore-tal og rapporterede før/efter-hashes; syntetisk del særskilt | **Delvist** — restorebevis, ikke en selvstændig produktionsverifikation |
| Trin 4: `CONTROL_TARGETS_OK` | Målmængden svarer til stikprøve plus maskinsæt | Sorteret JSON-mængde af fortolkningernes forgængere, samt krav om ingen singleton-items | **Ja** for netop den mængdepåstand; **delvist** for semantisk korrekthed |
| Trin 5a: kalibrering og webspor | Kandidater og menneskelig afgørelse understøtter identitetsvejen | Cirkulært facit, 30 blindt gennemgåede personas og RPC-payload uden startet webkø mod basen | **Delvist** |
| Trin 5b: 2a-tupel-digest | Det oprindelige bindingsudsnit er uændret | Ifølge senere rapport kun rækker uden supersedes-nøglen, de 210 ældre | **Ja** for det afgrænsede udsnit; **nej** for senere bindinger |
| Trin 5c: `fase=bundet` | Forventede placements og memberships er på plads | Antalsrelationer, ledger- og statustjek; nul persona-placements kan opfylde tællebetingelserne | **Delvist** |
| `db-verify` storage | Storage-politikker er testet | Faktiske rolleprøver kun hvis katalog og bucket findes; ellers `NOTICE` og return | **Delvist** |
| `db-verify` membership-helbred | Gældende memberships er kontrolleret | Udskriver antal ikke-gældende; positivt antal fejler ikke verifieren | **Delvist** |