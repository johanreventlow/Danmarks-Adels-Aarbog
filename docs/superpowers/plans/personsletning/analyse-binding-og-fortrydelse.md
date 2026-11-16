# Analyse: binding, fortrydelse og låse-spike (fuld personsletning)

**Nyt stop: intet påvist ved den statiske gennemgang.** Q6-afvisningen er accepteret af projektejeren i **R29**:
en fortolkning, hvor P er part, kan ikke genåbnes efter sletningen. Genåbningsfunktionerne er uændrede.
Del 3 fra Task 0 er bevaret uændret.

**Bevisgrænse:** hovedsessionen oplyser `FRISK_OK` for udgangspunktet før denne korrektionsrunde (16/11).
De fem nødvendige reviewrettelser er nu implementeret med nye assertions; deres databasekørsel og måling på
prod-skala afventer hovedsessionen. Denne runde har kun kørt statiske kontroller i arbejdsmappen;
ingen databasekommandoer, commits eller produktionsmålinger er kørt her. Q6-ruling R29 er uændret.

**Roadmapkobling:** trin 6's oprydning efter 6d-3; værdikædeled identitet og publicering. Leverancen er generel og
skal give redaktionen fuld fjernelse af en fejlprofil som afløser for at skjule den. Task 4's isolerede færdigbevis
er plan/facit-paritet, historiklukning og en afklaret konsekvens for bindinger/fortrydelse; det samlede
læser-/produktionsbevis hører fortsat til Task 13. Der er ikke oprettet en ny editionsspecifik overflade.

## Del 1: Binding til en bevaret familie (Task 4b / Q6)

### 1.1 NULL-state og samtlige kaldere

`private.relation_binding_state` (`schema.sql:19884`) læser fortolkning, parter, accepterede identiteter og den
relevante familiestruktur. Den læser ikke promotions. Fjernes P's partnerled, mangler parrets fælles familie
(19948-19955); resultatet bliver SQL-NULL. Identitetsafvisning af P's persona giver også NULL (19923-19938).
At slette promotionen alene ændrer derfor ikke state. `relation.child` har sin særskilte regel (19890-19919).

Tabellen omfatter alle direkte kald fundet ved `rg relation_binding_state schema.sql`, også kald til hash-wrapperen.
Kommentaren i `private.write_source_text_revision` (4760) er ikke et yderligere kald.

| Kalder (funktionsnavn) | Adfærd ved NULL for binding med P som part | Test eller begrundelse |
| --- | --- | --- |
| `private.relation_binding_state_sha256` (20005) | Returnerer SQL-NULL; hasher ikke JSON-null. | `binding_forsvinder`: både state og hash skal være NULL. |
| `public.red_ret_aegteskabsnummer` (19073) | Et relevant rettelseskald kan ende med `MARRIAGE_ORDINAL_CORRECTION_STATE_INVALID`; tidligere struktur-/nummerkrav kan afvise først. Hele kaldet rulles tilbage. | Statisk: 19052-19076. Gælder den valgte ægteskabspåstand med P som part, ikke andre fortolkninger på familien. Fixturen har ingen reel ordinaldrift, så der fabrikeres ikke en falsk rettelseskæde. |
| `private.append_relation_classification` (20050; via hash-wrapper) | Kaster `RELATION_CLASSIFICATION_STRUCTURE_INVALID` for netop den valgte fortolkning. | `binding_forsvinder` fanger præcis denne kode; alle andre fejl genkastes. |
| `private.relation_decision_set` (20076) | Proposed-ægteskaber med NULL-state springes over (`st.s IS NOT NULL`); ingen kildeglobal fejl. `red_preview_relation_decisions` og `red_decide_relation_interpretations` bruger samme mængde. | `binding_andres_bevaret` opretter efter ændringen både en ugyldig proposed-påstand med P og en uafhængig gyldig proposed-påstand i SAMME kilde. Præcis den gyldige skal vælges og afgøres. |
| `public.red_genaabn_relation_interpretation` (20197, 20209) | Låselisten bliver tom; genlæsningen kaster præcis `RELATION_REOPEN_STATE_INVALID`. En gyldig uændret familie ville give `RELATION_REOPEN_NOT_NEEDED`. Genåbning er til et gyldigt skift til en ANDEN familie. | `binding_forsvinder`, samme kode som hovedsessionens observation. At fortolkningen med P som part ikke kan genåbnes er accepteret i **R29**. |
| `private.preview_relation_promotions` (20285, 20296) | Låsegrenen springer NULL-parties over. Elementet får `eligible=false`, `RELATION_PROMOTION_STRUCTURE_INVALID`; previewet kaster ikke. `red_promote_relation_interpretations_batch` kaster elementets kode, hvis redaktøren forsøger at anvende en batch med det ugyldige element. | Begge `p_lock`-grene i `binding_forsvinder`. En eksplicit indsendt batch med P's ugyldige element må opdeles/fravælge det; dette er ikke en familieglobal spærring. |
| `private.spouse_exception_projection` (20479) | O-rækken er forældet og filtreres væk af `cur.st IS NOT NULL`/hashkravet. S-rækker beregnes særskilt fra proposed-identiteter og kandidater. | Kildens projektion kaldes i `binding_forsvinder`; den NULL-afhængige O-gren er statisk verificeret (20494-20500). |
| `public.public_family_sources` (21016) | NULL-bindingen springes over i `ok`; ingen undtagelse, ingen fallback til en forældet kilde. Andre gyldige bindinger på familien behandles fortsat. | `binding_andres_bevaret`: to rigtige publicerede kilder før, kun barnets gyldige kilde efter. Familien og barnet skal bestå. |
| `private.text_revision_binding_set` (21195; via hash-wrapper) | NULL-lighed giver ikke TRUE; familiebindingen tæller ikke som gældende. Tekstrevision kan fortsætte uden at føre den gamle binding over som kildehenvisning. | `binding_forsvinder` kræver tomt sæt for P's ægteskab; `binding_andres_bevaret` kræver stadig barnets anden binding. |
| `public.red_corroborate_family_identities` (19828) | Kalder ikke state eller promotions. En failed-kørsel returnerer 0. En passed-kørsel behandler kun manglende/proposed-identiteter; accepterede parter genbekræftes ikke. En stale kontrolkørsel kan blive failed eller en ny kandidat afvises pga. ændret struktur/kontekst; det er kontrol-/kandidatgrundlaget, ikke en NULL-promotion. | `binding_familiebekraeftelse`: fixturens failed-kørsel giver 0 uden fejl. Den positive maskinvej er ikke konstrueret i fixturen: den kræver en ny gældende kandidatkørsel og passed-kontrol med korrekte hashes. Statisk 19843-19872 og `private.check_family_corroboration` (19727). Q4-advarslen om en påvirket passed-kørsel består. |

**Andre personers fortolkninger:** en fortolkning om barnet/partneren, hvor P selv er nødvendig part, mister også
sit grundlag. Det gælder fx barnets forælderbinding til P eller partnerens ægteskab til P. Det er ikke et bevis på,
at deres øvrige fortolkninger fejler. Prøven opretter barnets forælderbinding til den tilbageværende partner gennem
den rigtige afgørelses- og promotionsvej på en anden kilde; dens state/hash og offentlige kilde skal være uændrede.
`relation.parent` læser kun barnet og sin valgte forælder. `relation.child` for den tilbageværende partner læser
partneren og børnene, ikke P's partnerled; P's egen child-fortolkning mister derimod sin principal. De to sidste
child-scenarier er statisk begrundede via `private.relation_child_rule`, ikke særskilt målt i denne fixtur.

**Mulig afvisning, der skal skelnes fra en ny global spærring:** en bruger, der sender P's ugyldige element sammen
med andre elementer til promotion, får hele denne eksplicit valgte batch afvist. Kildens automatiske afgørelsesvej
filtrerer NULL fra, og læsevejene filtrerer den enkelte binding. R29 accepterer den manglende genåbning for
fortolkninger med P som part; et nyt stop kræver fejl eller blokering for andres arbejde på den bevarede familie.

### 1.2 Prøvens afgrænsning

Gruppe `binding` bruger en rigtig kilde/persona/party-kæde, en beregnet bindingshash og rigtige publicerings-RPC'er.
R21's syntetiske `prom_egen_fam`-hash bruges ikke som bevis. Prøven fjerner kun P's medlemskab af den bevarede familie;
promotionen bliver stående, fordi Task 5/8 endnu ikke har leveret den lovlige append-only-slettevej. Dens tilstedeværelse
kan ikke reparere NULL-state, og prøven omgår ingen trigger. `SET CONSTRAINTS ALL IMMEDIATE` validerer de opbyggede kæder.

Som `test-family-sources.sql` og `fixtures/person-facts.sql` kræver publiceringsopsætningen afdøde, offentlige
narrativsubjekter. `red_opret_person` sætter `privat=true` (`schema.sql:8478`); derfor sætter denne gruppes egen
rollback-kopi P og barnet til `levende=false, privat=false, staged=false` før kædeopbygningen. De rigtige
publiceringsfunktioner og deres politik er uændrede. Familie-RPC'en afprøves med redaktørens adgang; familien kan
stadig have en privat partner, som redaktøren må se.

Forventet: `OK binding_forsvinder`, `OK binding_andres_bevaret`, `OK binding_familiebekraeftelse`. Dette er fortsat
ikke en ende-til-ende-personsletning. Den kommer i Task 8.

## Del 2: Fortrydelsesveje (Task 4c / Q3)

### 2.1 Fælles prædikater og måling

Den eksekverbare SQL er [person-purge-reversal-count.sql](../../../../tests/sql/person-purge-reversal-count.sql).
CTE'erne er statiske og kan flyttes ind i Task 7's preview; parameteren `p.id` er personen, `plan` er dens rækkeplan.
`generic_ready` og `publication_ready` beskriver muligheden for at gennemføre kaldet med en ny, gyldig autorisation
og korrekt redaktørrolle. De udsteder ingen autorisation. `generic_lost`/`publication_lost` udvælger de berørte batches.
Der er intet krav om en allerede udstedt, endnu ikke udløbet autorisation i previewet: den kan udstedes ved fortrydelsen.

Kør på en rigtig base som ejer, med det relevante syntetiske eller godkendte person-id:

```sh
psql -X -v ON_ERROR_STOP=1 -d BASE -v pid=PERSON_ID -f tests/sql/person-purge-reversal-count.sql
```

Output er én række med otte antal (`*_kan_nu`, `*_mistes` for de fire veje). Ingen navne, tekster, payloads eller
batch-id'er printes. SQL'en skriver intet og bruger `narrative_record_state(...,false)`, altså uden låsegrenen.
Tal fra en rigtig database er ikke tilgængelige her. Grundfixturens S42-kæde er kun en ledger-tilnærmelse og mangler
et reelt aktiveringsreceipt. `fortrydelse_praedikater_fixture` asserterer de faktiske otte antal: publication 1/1,
øvrige veje 0/0, samt præcis C-batch i begge publication-mængder og tomme generelle mængder.

En separat rollback-fixtur (`tests/sql/fixtures/person-purge-reimport.sql`) bygger nu en rigtig generel kæde via
person_create → name_completion → activation for Q. Q's narrativ har præcis én hændelse med subjekt P (S26),
indsat før aktiveringen. Begge fortrydelses-RPC'er skal lykkes før ændringen (lokale subtransaktioner med rollback
og `SET CONSTRAINTS ALL IMMEDIATE`). Prædikaterne skal vise netop Q's batch som ready/lost for begge API-navne:
otte antal 1/1, 1/1, 0/0, 1/1. En uberørt person giver derimod 1/0, 1/0, 0/0, 1/0. Efter fysisk fjernelse af den
almindelige S26-række skal `has_haendelse` skifte true → false, state-hashen afvige fra receiptet og begge API'er
afvise med deres præcise reversal-invalid-kode. Append-only-ledgers og triggere røres ikke.
Testens `purge_reversal_assert` forbruger samme SQL som målingen; batch-id'er går kun til sessionsvariabler.
En tom `generic_lost` eller `publication_lost` får dermed en assertion til at fejle.

### 2.2 `public.red_reverse_reimport` (`schema.sql:5762`)

| Punkt | Betingelse, konsekvens og bevis |
| --- | --- |
| Kan fortrydes nu | Kontrakt 2, parent `activated`, præcis ét `finalized` name-completion-barn på samme source/profil/hash og `source_batch_id`; barnets expected=observed, resultatantal=`name_completions`, canonical_delta-antal=`operations`; person_create/result/child-event matcher begge veje på person, record og kildeelement. Seneste activation har receipts-object. Hvert result har korrekt id-hash, matchende parent/receipt og eksisterende identitetsversion; det citerede draft_updated-event er sidste, ikke fortrudt, med gyldige før/efter-hashes og uændret aktuel narrativtilstand. Aktiveringswriteren (5976-6003) opdaterer en eksisterende kladde, som kan gendannes og derefter kasseres. |
| P-rækker der ødelægger den | S41a-parent/child-events og S42-resultater giver tælle-/bijectionfejl. Fjernelse af P's narrativ/publicering/identitetsstate bryder receipt/state. S26 kan også bryde Q's receipt indirekte: fjernes den sidste hændelse under Q's bevarede narrativ, ændres `has_haendelse` i tilstandsgrundlaget. Selv hvis antallet rammer et hul i en defekt ledger, er det ikke længere den samme autoriserede fortrydelse. |
| SQL-prædikat for `fortrydelse_mistes` | `EXISTS (SELECT 1 FROM generic_lost g WHERE g.id=b.id)`. `generic_lost` kræver først `generic_ready` og derefter en planlagt mutation af et parent-/child-event, resultat/domænerække, person, narrativ eller dets hændelser, recordens binding-/eventhistorik eller en placeret identitetsstate. Hændelser medtages konservativt, også hvis andre hændelser bliver tilbage eller kun S27 løsnes; placerede identiteter omfatter historiske placeringer som overmængde. Hele prædikatet står i SQL-filen. |
| Test/bevisgrænse | `fortrydelse_reimport` kræver præcis `REIMPORT_WRITER_REVERSAL_INVALID` på den syntetiske S42-kæde. Den nye `fortrydelse_generel_positiv` kræver en vellykket reversal gennem den rigtige RPC; `fortrydelse_s26_advarsel` kræver antal og batchmængder, og `fortrydelse_s26_receipt_drift` viser fejlen efter fjernelse af hændelsen. Prod-måling og Task 13's generalprøve afventer stadig hovedsessionen. |

### 2.3 `public.red_reverse_1939_v50_reimport` (`schema.sql:6112`)

| Punkt | Betingelse, konsekvens og bevis |
| --- | --- |
| Kan fortrydes nu | Funktionen er en ren wrapper om `red_reverse_reimport(b,a)` og har ingen selvstændig editions-/source-gate. Samme status, tællinger og receipts som ovenfor. |
| P-rækker der ødelægger den | Samme som den generelle vej. Kun fejlteksten `REIMPORT_WRITER_REVERSAL_INVALID` oversættes til `REIMPORT_1939_REVERSAL_INVALID`. |
| SQL-prædikat for `fortrydelse_mistes` | `EXISTS (SELECT 1 FROM generic_lost g WHERE g.id=b.id)`. Task 7 viser batch + vej, som Q3 kræver; den samme batch kan derfor nævnes ved begge API-navne. |
| Test/bevisgrænse | `fortrydelse_wrapper` kalder wrapperen med samme fixturbatch/autorisation og kræver præcis den oversatte kode. `fortrydelse_generel_positiv` og S26-prøven dækker også wrapperens succes før og præcise afvisning efter. Ingen ny editionsnavngiven overflade oprettes. |

### 2.4 `public.red_reverse_reimport_cases` (`schema.sql:13166`)

| Punkt | Betingelse, konsekvens og bevis |
| --- | --- |
| Kan fortrydes nu | **Ingen ved kontrakt v2.** `private.apply_narrative_record_contract_acl` tilbagekalder klienternes EXECUTE; C3-vejen står i legacy-listen (17335), men ikke i v2-facadelisten (17348-17358), og får derfor ikke et nyt grant. Et kald som ejer rammer desuden `contract_version()>=2` og `NARRATIVE_RECORD_LEGACY_WRITER_DISABLED` før batch-, autorisations- og tælleopslag. `db-rls.sql:1188` undlader også det gamle C3-grant, når den generelle writer findes. Den historiske v1-vej krævede bl.a. finalized c3/apply-batch, change_set, ingen eksisterende reversal, eventplan/receipt-hash, alle anvendte events og uændrede mål (13015-13080, 13256-13478). Den er historik og skal ikke gøres tilgængelig af sletningen. |
| P-rækker der ville være berørt | S43a record_assign-event samt dens narrativ/binding/historik. `reimport_case_batch` bevares altid og holder en indgående change_set-FK, som historikfunktionen respekterer. De kan ikke skabe et NYT tab af en v2-fortrydelsesmulighed, der allerede er lukket. |
| SQL-prædikat for `fortrydelse_mistes` | `FALSE` under denne opgaves kontrakt v2; måle-SQL returnerer 0/0. Det er ikke et generelt prædikat for en eventuel fremtidig genåbning af v1-API'et. |
| Test/bevisgrænse | `fortrydelse_cases` kontrollerer manglende authenticated-EXECUTE, kræver præcis SQLSTATE 42501 (`insufficient_privilege`) ved klientkaldet og kræver derefter præcis `NARRATIVE_RECORD_LEGACY_WRITER_DISABLED` ved ejerkaldet. Testen giver ingen nye rettigheder. Harnessen bygger kontrakt 2; v1-data rekonstrueres ikke for et lukket API. |

### 2.5 `public.red_reverse_reimport_publication` (`schema.sql:18552`)

| Punkt | Betingelse, konsekvens og bevis |
| --- | --- |
| Kan fortrydes nu | Kontrakt 2, batch `finalized`, mindst én event, ALLE events er `publication_identity`. Hvert receipt har numerisk identity_version, lig den gældende state-version for payloadens source_persona_id. En ny gyldig reversal-autorisation skal matche batch/source/profil/hash/manifest/preview. Ingen kontrol af batchens oprindelige expected/observed-tællinger i denne RPC. |
| P-rækker der ødelægger den | Er alle C-events fjernet, giver kaldet `REIMPORT_WRITER_REVERSAL_INVALID`. Er en tilbageværende events persona i X, giver n+1-state versiondrift. Fjernes kun P's event, og andre uændrede C-events står tilbage, kan RPC'en stadig fortryde disse andre identiteter. Den laver da en delvis fortrydelse i forhold til den oprindelige batch. |
| SQL-prædikat for `fortrydelse_mistes` | `EXISTS (SELECT 1 FROM publication_lost l WHERE l.id=b.id)`: `publication_ready` og (mindst ét S41a-event fjernes **eller** en bevaret event refererer til en state, planen erstatter). Dette er den konservative advarsel, hovedsessionen har bedt om indtil Q3-afklaringen: også delvist tab medtages. Den hævder ikke, at ethvert advaret fremtidigt kald fejler. |
| Test/bevisgrænse | `fortrydelse_publication` udfører rigtig autorisation og reversal af fixturens to-personers C-batch og validerer kvittering/deferred constraints i en subtransaktion, som rulles tilbage. Det læste fravalg af S41a viser præcis én uændret event tilbage. Den fysiske efter-sletningstest afventer Task 5/8; append-only løftes ikke her. |

**Åbent spørgsmål til Q3, ingen ny ruling:** Skal `fortrydelse_mistes` også advare, når et C-kald fortsat lykkes,
men kun for den tilbageværende del af den oprindelige batch? Hovedsessionen afklarer dette efter grøn Task 4.
Indtil da medtager prædikatet konservativt `publication_ready AND EXISTS (S41a-event i denne batch)`, som
hovedsessionen har instrueret. Fixturens to-personers C-batch skal derfor nu tælles i `publication_mistes`,
selv om én uændret event bliver tilbage og kan fortrydes. En eventuel indsnævring af advarslen afventer afklaringen.

### 2.6 Plan/historik-kontrakt til de næste tasks

`person_purge_historik` beregner historiske F*/R*/A*/S*/M*/PEI*, begge eventsider selvstændigt, E og derefter D0/C/Frev.
Fortryd-sæt med et bevaret original-sæt kommer ikke i D0 alene pga. subjekt P. Indgående FK fra en bevaret npe,
paastand_korrektion eller case_batch holder sættet uden for C. Der slettes ingen bogtabeller.

`person_purge_plan` bruger statisk SQL og kanoniske tabelnavne/sted-id'er (R24/R25). Én fysisk række forekommer én
gang: S19 prioriteres over S14, NY-B over S32, og sletning/blokering over bevar_andres. S48/S58 og S47/S58
medfører ikke flere poster for samme række (M3). `ekstra.forrige_version` findes på S10-state-rækken (Q7),
`ekstra.bucket/storage_path` på media og varianter. S24 har én slet-post med `ekstra.nulstil_latest_event_id` til
fase 3a's mellem-UPDATE; dens endelige sletning er fase 3c. Facit indeholder tilsvarende én slet-række.

`plan_matcher_count` dokumenterer den kendte S11-forskel (+2 for X2's ældre events), summerer tællerens delsteder
og bruger facit som uafhængigt bevis for D, fordi tællerens S52/S53/S55 er kandidater/heuristik. Den ændrer ikke
tælleren. Nye testgrupper i standardharnessen er `binding`, `plan`, `historik` og `fortrydelse`.

### 2.7 Reviewrettelser: Q5, NULL og S48

Q5-familieejerskab bruger nu `rf_all`, den fulde R_fam, inklusive overlap med R. Kun `rf` til S14b er disjunkt.
Promotions til både overlappets relationer og deres assertions kræver derfor principal-persona ∈ X;
andres promotions giver S39b/blokér. `plan_q5_overlap` bygger netop P → faktum i F_fam med en accepteret persona
for tredje ∉ X og kræver blokering af begge promotionmål. Grundfixturens plan/facit-tal ændres ikke.

S34b bruger ejerskab `IS NOT TRUE`: både helt og delvist NULL-subjekt med et personlink i payload skal blokere.
`plan_null_subjekt_token` kræver tre S34b-poster. Gennemgangen fandt samme hul for nullable
`citation.assertion_id`; `plan_null_citation_token` kræver S29/blokér for et linkcitat uden assertion.
De øvrige tokenkomplementer (S29, også text_mention) bruger samme NULL-sikre form. De resterende `NOT`-udtryk i plan/historik er gennemgået: medlemskab bygger på NOT NULL-id'er;
promotionernes flag bygger på NOT NULL target-type/-id og id-mængder; change_set bruger coalesce og
IS NOT DISTINCT FROM, og historiske JSON-billeder bruger `NOT coalesce(...,false)`. Ingen yderligere NULL-hul
påvist i disse prædikater.

S48 afgrænses nu fra fam's partnerled → accepteret principal-identitet → gældende principal-part → spouse-part
→ personas med kandidater. Det følger `persona_family_context`'s faktiske retning: ægtefællens egen kanoniske
identitet behøver ikke tilhøre fam. `family_context_personas` deduplikerer før en materialiseret
`family_contexts` beregner højst ét funktionskald pr. relevant persona. Det oprindelige familiesnit verificeres
stadig på hver beregnet kontekst; afgrænsningen er en overmængde, også ved flere/forældede relationer.
`plan_s48_paritet` sammenligner mængden med det oprindelige fuldt scannende prædikat, kræver mindst to positive
kandidater på samme spouse-persona og bruger en spouse, som selv er uden for fam. S12 har fortsat prioritet.

Hovedsessionens førmåling: hele `person_purge_plan(1791)` 153 s på ca. 10.000 personer; ca. 5.455 gentagne
kontekstkald dominerede. Eftermåling (hovedsessionen, samme kopi efter migrationen): 1,1 s, samme resultat (32 rækker, 15 steder);
`person_purge_historik(1791)` 0,07 s. S58's `candidate.basis::text ~ regex` scanner fortsat alle basis-felter
og skalerer med rækketal × tekststørrelse. Den er billig ved de oplyste ca. 335 bytes pr. række; markant vækst
kræver ny måling. Ingen ny indeks-/lagringsarkitektur indføres i denne afgrænsede rettelse.

### 2.8 Kendt begrænsning: S26-grenen overadvarer

Afsluttende review (Task 4): `generic_lost` og wrapper-grenen medtager en batch, når Q's narrativ har en S26-hændelse
for P, også hvis narrativet har en anden, bevaret hændelse. Så forbliver `has_haendelse` true, receiptets tilstand er
uændret, og fortrydelsen virker fortsat; S27-løsning giver samme overadvarsel. Hovedsessionen har vurderet det som
en kendt begrænsning: Q3 er en advarsel, ikke en blokering, og prædikatet er bevidst konservativt (hellere en advarsel
for meget). Task 7, der bygger advarslerne, kan begrænse grenen til sletning af narrativets sidste hændelse og tilføje
negative kontroller (bevaret hændelse, ren S27-løsning).

---

## Del 3: Låse-spike (Task 0)

Kort fortalt (hverdagssprog):

- Vi har afprøvet låseordenen L1-L13 med L5b i praksis med et skelet af sletningen og rigtige skrivere, der tvinges
  til at mødes på de værst tænkelige tidspunkter.
- **Med planens orden (L8 = ROW EXCLUSIVE, L5b slået til) gav ingen af de tvungne sammenstød deadlock (40P01).** Hver
  gang ventede den ene på den anden, og bagefter lykkedes den ene, mens den anden enten også lykkedes eller afviste med
  en forståelig fejl. Der blev aldrig efterladt forældreløse rækker.
- De to cykler, delta-reviewet forudsagde, er reproduceret: med L8 = SHARE ROW EXCLUSIVE (v2.1) eller uden L5b kommer
  der deadlock hver gang. Testopsætningen kan altså fremtvinge cyklerne, og planens to rettelser fjerner dem.
- **CI med vagterne er ikke grøn.** Alle fejl, vi har set, skyldes testdata, der skriver rækker om personer eller
  fakta, som ikke findes (klasse a). Ingen rigtig skriver bliver brudt af vagterne (klasse b: 0). Detaljer i 3.5.
- Et nyt fund: `SET LOCAL statement_timeout` inde i sletningen virker ikke på selve kaldet (3.4, F-4).

Afgørelsen go/no-go træffes af hovedsessionen.

### 3.1 Hvad blev bygget

| Fil | Indhold |
|---|---|
| `tests/sql/spike/person-purge-skelet.sql` | Vagterne og skelettet. Lægges oven på en engangsbase; idempotent. |
| `tests/sql/spike/person-purge-fixture.sql` | Syntetisk fixtur (P, Q, L, persona X_P placeret i record P-REC, uafgjort persona Z). |
| `tests/sql/spike-person-purge-laase.sh` | Harnessen med de tvungne interleavings. |
| `tests/sql/spike/ci_jobs_lokalt.py` | Kører de 4 PostgreSQL-CI-jobs lokalt med vagterne slået til (step 2). |

**Vagterne** (som Global Constraints; markør `SPIKE_PERSON_PURGE_VAGT_V1` i hver funktion):

- `enforce_relation_evidence_target` udvidet til `target_type='fact'` (`FOR KEY SHARE` på faktummet), og med
  D-6's tidlige retur ved uændret (type, id).
- `private.validate_polymorf_subjekt_findes` (SECURITY DEFINER, `FOR KEY SHARE`, `lower()`, tidlig retur ved uændret,
  personer før familier i id-orden) på `fact`, `note`, `narrative`, `story`, `suggestion`, `relation` (begge ender),
  `assertion.objekt_*` og `haendelse.subjekt_*`.
- `validate_entity_description_subject` med `FOR KEY SHARE`. Den er bevidst stadig SECURITY INVOKER som i
  `schema.sql`; se F-6.
- Fakta-slettevagten `private.guard_fact_evidence_delete` (BEFORE DELETE OR UPDATE OF id på `fact`) med
  `FACT_HAR_EVIDENS`.
- `feed_pin` (fix 1): en spike-kopi af `red_set_feed_pin` (schema.sql l. 7121) låser nøglens mål FOR KEY SHARE før
  upserten. Det gælder person P for `portrait|citat|naevnt|dagensperson:P`, `jubilaeum|embede:P:…` og
  `slaegt:P:x`/`slaegt:x:P`, og familie F for `forbundet:F`. Personer låses før familier i id-orden. Hvorfor låsen skal
  ligge i skriveren og ikke i en trigger, står i F-8.
- En `warn`-tilstand (tabelrækken `spike.indstilling`, så `createdb -T` arver den) giver `RAISE WARNING
  SPIKE_VAGT_BRUD … stak=<funktioner>` i stedet for en fejl. Den bruges kun til CI-inventaret.

**Skelettet** `spike.red_slet_person_helt_skelet(P, opt)` tager L1-L13 med L5b i slettegrafens orden:

- `lock_timeout = 5s` og `statement_timeout = 30s` sættes med `set_config`.
- L3 og L12 beregner kilderne for `person_external_id`, X∪Y, kandidatrækker og kontrolstikprøver.
- L5b låser de records, hvor X∪Y-personas er placeret, plus records med P's narrativbindinger.
- L13 sammenligner et forenklet preview: P's fakta, påstande, relationer, noter, X∪Y, kandidater, memberships og
  feed_pins med P i nøglen.
- Derefter sletter skelettet noget repræsentativt, børn før forældre: citation, conclusion, assertion, note,
  haendelse-ankre, relationer (også med en fakta-ende), fakta, memberships og P's feed_pins. Med `slet_person` slettes også
  external ids, family_member og selve personen.
- Det skriver ingen manifest og rører ingen ledgers.
- Valg (kun til spiket):
  - `l5b`: false giver positiv kontrol for D-2.
  - `l8_mode`: `SHARE ROW EXCLUSIVE` giver positiv kontrol for D-1.
  - `pause_after`: `pg_sleep`, mens låsene holdes.
  - `slet_person`.

**Pausemekanik i harnessen:**

- Hver session er en baggrunds-psql med sit eget `application_name`.
- En observatør poller `pg_blocking_pids` og logger, hvem der venter på hvem. Ved rækkelåse viser loggen tabellen fra
  ventertens tuple-lås. Et resultat tæller kun, når sammenstødet er observeret.
- Skelettet standses på to måder:
  - med `pause_after`;
  - ved L7, mens en tredje session holder `samme_som_mutation`. Det er præcis D-2's »mellem L6 og L8«.
- Skriveren standses med et **testinstrument**: en kopi af `begin_change_set` med uændret krop plus et pausepunkt
  først. Kopien findes kun i spikens base.
  - Pausepunktet venter på advisory-nøglen `spike_pause_cs`, når sessionen har `spike.pause_cs=on`.
  - Så står skriveren præcis i D-1's vindue: efter sine rækkelåse og før sin første lås på `change_set`.
- Narrativskriverne standses ved, at en tredje session holder P's narrativrække. Så har skriveren record → change_set
  ACCESS EXCLUSIVE → person, men endnu ikke personaen.
- Helt-først-scenarierne kører hele skriveren i en transaktion med `pg_sleep(3)` før COMMIT, så alle dens låse holdes.

**Fixturen** bruger negative id'er og syntetiske navne. Den følger formen fra
`tests/integration/test-narrative-record-concurrency.R` (`seed_record`). Den rigtige fixtur med positive id'er bygges
i Task 2a.

- P (-9101) har:
  - fakta med påstand, citat fra kilde S og afklaret konklusion;
  - en note og en evidensfri medieafbildning;
  - en membership fra en placement;
  - persona X_P, placeret i P-REC og accepteret som P;
  - et forslag fra X_P til titlen.
- P's narrativ på P-REC oprettes og publiceres gennem de rigtige RPC'er (`red_upsert_…`, `red_publicer_…`).
- Q (-9102) er en anden person i samme kilde.
- L (-9103) har ingen ledger, så skelettet kan slette den helt. L har en eksisterende pin `portrait:-9103` (fix 1).
- Z er en uafgjort persona i S.
- Kontrakt v2 kommer fra `tests/sql/reimport-writer-v2-bootstrap.sql`, altså den rigtige cutover.

**Kørsel:** `bash tests/sql/spike-person-purge-laase.sh [præfiks] [scenarie …]`. Alle scenarier tager ca. 3 min.
Scriptet opretter `<præfiks>_base` og én kopi pr. scenarie og sletter kun dem. Resultatet står i
`$SPIKE_OUT/resultat.tsv`.

### 3.2 Resultater pr. scenarie

Kørt tre gange (to af gangene, mens CI-jobbene belastede maskinen). Udfald og observerede ventninger var ens alle tre
gange. feed_pin-scenarierne (fix 1) er kørt to gange med samme udfald, sammen med D-1 OCR-gruppen som kontrol. OCR-
gruppen gav samme udfald som før.

»Ingen kollision mulig ved RE« betyder: skriveren rører intet, skelettet holder, så længe skelettet kun har L1-L8.
Scenariet beviser derfor ikke serialisering. Det viser kun, at der ikke opstår en ventning.

S = skelettet, W = skriveren, H = holder-sessionen. »Venter« er observeret med `pg_blocking_pids`.

**Planens konfiguration** (L8 ROW EXCLUSIVE, L5b til):

| Scenarie | Observeret | S | W | Udfald |
|---|---|---|---|---|
| D-1 `red_ret_ocr_felt` på Q (samme kilde), W først | W ved change_set-pausen; S venter på W's række i `source` (L9) | OK | OK | serialiseret |
| D-1 OCR, S først (holder L1-L8) | W venter ikke (L9 er ikke taget endnu) | OK | OK | ingen kollision mulig ved RE |
| D-1 `red_ret_paastand`, W først | S venter på W's række i `source_persona_identity` (L6) | OK | OK | serialiseret |
| D-1 `red_ret_paastand`, S først | W venter på S i `source_persona_identity` | OK | `PAASTAND_DRIFT` | serialiseret, fail-closed |
| D-1 `red_reverse_placement_membership`, W først | S venter på W's række i `person_lineage_membership` (DELETE) | OK | OK | serialiseret |
| D-1 membership, S først | W venter ikke; W committer før S's L13 | `PURGE_PREVIEW_AENDRET` | OK | ingen kollision mulig ved RE; fail-closed via L13 |
| D-1 `red_slet_medierelation_uden_evidens`, W først | S venter på W's række i `relation` | OK | OK | serialiseret |
| D-1 medie, S først | W venter ikke | `PURGE_PREVIEW_AENDRET` | OK | ingen kollision mulig ved RE; fail-closed via L13 |
| D-2 `mutate_person_narrative_record` (revider), S først, stoppet ved L7 | W venter på S's række i `source_record` (L5b) | OK | OK | serialiseret |
| D-2 revider, W først (record+AE+person holdt) | S venter på W's række i `source_record` (L5b) | OK | OK | serialiseret |
| D-2 `reverse_narrative_publication_event` (fortryd), S først, L7 | W venter på S i `source_record` | OK | OK | serialiseret |
| D-2 fortryd, W først | S venter på W i `source_record` | OK | OK | serialiseret |
| Task 11 (f) `red_upsert_fakta(L)`, W først | S venter på W's KEY SHARE på `person` (L10) | `PURGE_PREVIEW_AENDRET` | OK | som planen forventer |
| (f), S først (sover efter sletningen) | W venter på S i `person` | OK | `POLYMORF_SUBJEKT_FINDES_IKKE: person` | som planen forventer |
| Task 11 (g) `red_tilfoej_oplysning` på L's faktum, W først | S's DELETE venter på W's KEY SHARE på `fact` | `FACT_HAR_EVIDENS` | OK | som planen forventer |
| (g), S først | W venter på S i `fact` | OK | `POLYMORF_SUBJEKT_FINDES_IKKE: fact` | som planen forventer |
| (g) note på L's faktum uden change_set, W først | S venter i `fact` | `FACT_HAR_EVIDENS` | OK | som planen forventer |
| (g) note uden change_set, S først | W venter i `fact` | OK | `POLYMORF_SUBJEKT_FINDES_IKKE: fact` | som planen forventer |
| `red_afgoer_source_persona` (Z same P), W først | S venter på W's delte kildelås (L5) | `PURGE_PREVIEW_AENDRET` | OK | serialiseret, fail-closed |
| `red_afgoer_source_persona`, S først | W venter på S's eksklusive kildelås | OK | OK | serialiseret |
| `red_record_identity_candidates` (S, Z→P), W først | S venter på W's kildelås (L5) | `PURGE_PREVIEW_AENDRET` | OK | serialiseret, fail-closed |
| `red_record_identity_candidates`, S først | W venter på S's kildelås | OK | `IDENTITY_CANDIDATE_INPUT_DRIFT` | serialiseret, fail-closed |
| `red_set_feed_pin('portrait:L')`, eksisterende pin (ON CONFLICT DO UPDATE), W først | S venter på W's KEY SHARE på `person` (L10) | OK (sletter den opdaterede pin og L) | OK | serialiseret |
| `red_set_feed_pin`, S først (sover efter sletningen) | W venter på S i `person` | OK | `POLYMORF_SUBJEKT_FINDES_IKKE: person` | serialiseret, fail-closed |
| `red_set_feed_pin`, S holder L10 og sover; W's upsert; S sletter pins (låsen før upserten) | W venter på S i `person`, før pin-rækken | OK | `POLYMORF_SUBJEKT_FINDES_IKKE: person` | serialiseret |
| (h) en anden session holder P FOR UPDATE i 10 s | S venter i `person` | `55P03` efter 5 s | (holder) | intet ændret |

Tabellen bagefter blev målt efter hvert scenarie: 0 forældreløse påstande, 0 forældreløse fakta, 0 forældreløse
noter og (fix 1) 0 forældreløse pins i alle kørsler.

**Positive kontroller** (beviser, at harnessen fremtvinger cyklerne):

| Kontrol | Observeret | Offer |
|---|---|---|
| D-1 OCR, W først, L8 = SHARE ROW EXCLUSIVE | S holder SRE og venter på W's række i `source`. W slippes og skal have RE på change_set | **40P01**, S |
| D-1 membership, W først, SRE | som ovenfor, række i `person_lineage_membership` | **40P01**, S |
| D-1 medie, W først, SRE | som ovenfor, række i `relation` | **40P01**, S |
| D-1 `red_ret_paastand`, W først, SRE | S venter allerede ved L6 (identitet) før L8 | ingen deadlock (se F-2) |
| D-2 revider, S først, UDEN L5b | W har record+AE+person og venter på S's persona; S slippes ved L7 og vil have RE på change_set | **40P01**, W |
| D-2 revider, W først, UDEN L5b | S venter på W's ACCESS EXCLUSIVE (L8); W slippes og vil have personaen | **40P01**, S |
| D-2 fortryd, S først, UDEN L5b | som revider | **40P01**, W |
| D-2 fortryd, W først, UDEN L5b | som revider | **40P01**, S |
| `red_set_feed_pin`, låsen KUN i en BEFORE UPDATE-trigger på `feed_pin`; S holder L10 | W har den eksisterende pin-række (DO UPDATE) og venter på S i `person`; S's DELETE af pins venter på W i `feed_pin` | **40P01**, S |
| `red_set_feed_pin`, låsen i en BEFORE INSERT OR UPDATE-trigger; S holder L10 | W venter på S i `person`, før pin-rækken | ingen deadlock (se F-8) |

### 3.3 Hvad spiket ikke dækker

- **Skelettet er ikke sletningen.** Den rigtige sletning sletter langt flere tabeller efter L13 (manifest, ledgers,
  historik, narrativer) og holder låsene længere. Den tager desuden flere rækkelåse sent i transaktionen. Task 11 skal
  køre de samme scenarier mod den rigtige funktion. Harnessen er bygget, så skabelonerne kan genbruges.
- Skelettet sletter ikke P selv i D-2-scenarierne, fordi P har publiceringshistorik (append-only). Kollisionen sker
  før sletningen, så det ændrer ikke låseudfaldet.
- `red_fortryd_change_set` (Task 11 e) og `red_fjern_feed_pin` er ikke med. `red_fjern_feed_pin` sletter kun
  pin-rækken og låser ingen person.
- Pausen i `begin_change_set` er et testinstrument. Uden den kan vinduet mellem en skrivers rækkelås og dens
  change_set-lås ikke rammes deterministisk.
- Step 1b's statiske tjek af helpers og triggere er ikke lavet. Spiket tester kun de navngivne skrivere.

### 3.4 Fund

- **F-1 (låseorden):** L1-L13 med L5b og L8 = ROW EXCLUSIVE serialiserer alle tvungne sammenstød.
  - Der kom 0 deadlocks i de 23 scenarier med en observeret kollision: 20 fra første runde × 3 kørsler og 3
    feed_pin-scenarier × 2 kørsler.
  - De 3 D-1 »S først«-scenarier tæller ikke med. Der var ingen kollision mulig ved RE.
  - Begge rettelser fra delta-reviewet er nødvendige. Uden dem giver de positive kontroller 40P01 hver gang.
- **F-2 (`red_ret_paastand` kan ikke danne D-1-cyklussen):** Skriveren kræver altid et forslag fra en persona med
  accepteret identitet til faktummets person, altså en persona i X. Den tager `source_persona_identity FOR SHARE`, før
  den tager personen.
  - Sletningen venter derfor ved L6, før den har L8. Selv med SHARE ROW EXCLUSIVE kom der ingen deadlock.
  - [læst] Uden forslag afviser funktionen med `PAASTAND_FORSLAG_UOVERENS`, før den åbner sættet, og låsene slippes ved
    rollback.
  - Delta-reviewets formulering »når påstanden ikke kommer fra en fortolkning« dækker altså ingen sti, der når
    `begin_change_set`.
- **F-8 (feed_pin: låsens placering afgør udfaldet; fix 1):**
  - `kort_noegle` er tekst uden FK. Eksistensvagten for et pin-mål skal derfor tages et sted, og placeringen er
    afgørende.
  - Med en `INSERT … ON CONFLICT DO UPDATE` på en eksisterende pin låser PostgreSQL pin-rækken (konfliktrækken), før
    BEFORE UPDATE-triggeren kører.
  - En lås på personen i en ren BEFORE UPDATE-trigger tages altså efter pin-rækken. Skelettet tager personen (L10) før
    pins (DELETE). Det giver en cyklus, og kontrollen gav **40P01** (offer: skelettet).
  - Med låsen i skriveren før upserten (planens placering) venter skriveren på personen, før den rører pin-rækken. Der
    kom ingen deadlock: skrivningen afvises med `POLYMORF_SUBJEKT_FINDES_IKKE`, efter at sletningen har committet.
  - En BEFORE INSERT OR UPDATE-trigger gav også serialisering i spiket. Den BEFORE INSERT-trigger, der hører til
    upserten, kører før konfliktarbitreringen, altså før pin-rækken låses. Den beskytter dog ikke en ren `UPDATE` af
    `kort_noegle`.
  - **Task 8 skal kopiere:** låsen i `red_set_feed_pin` selv, før `INSERT … ON CONFLICT`. Rækkefølgen er
    `begin_change_set` → KEY SHARE på nøglens personer (id-orden), derefter familier → upsert. Låsen må ikke lægges i
    en BEFORE UPDATE-trigger.
  - Funktionen er defineret i `schema.sql` l. 7121 og to gange i `db-migrations.sql` (l. 3220 og 4523). Samme
    forhold som F-5: den nye krop skal vinde ved genkørsel.
  - Nøglemønstrene står i `spike.feed_pin_maal` i skelettet. De følger slettegrafens S32 for person- og
    familienøgler.
- **F-3 (fail-closed, ikke deadlock):** Når en skriver når at committe, mens sletningen holder L1-L8, fanger L13's
  preview-sammenligning ændringen (`PURGE_PREVIEW_AENDRET`). Det gælder membership, medie, afgørelse og
  kandidatkørsel. Planens L12/L13 er altså det, der lukker, ikke låsene alene. Det kræver, at det rigtige preview
  indeholder memberships, medierelationer, X∪Y og kandidatrækker. Skelettets forenklede preview gør det.
- **F-4 (`statement_timeout` virker ikke inde i funktionen):** Målt på PG 17. `set_config('statement_timeout','1s',
  true)` og en funktions `SET statement_timeout` afbryder ikke det kald, der er i gang. `pg_sleep(2.5)` gik igennem
  i begge tilfælde.
  - Timeren armeres, når statementet starter. Global Constraints' »`SET LOCAL statement_timeout = '30s'` som samlet
    loft« (D-3) virker derfor kun på senere statements i samme transaktion, ikke på sletningen selv.
  - Loftet kommer i praksis fra den rolle eller session, RPC-kaldet kører under (PostgREST's rolle-indstilling).
  - Task 8 skal enten dokumentere det eller bruge en anden mekanisme, fx en tidsgrænse i klienten eller
    `lock_timeout` alene.
  - `lock_timeout` virker, fordi den læses ved hver låseventning (scenarie h: 55P03 efter 5 s).
- **F-5 (genanvendelse af vagterne):** `db-migrations.sql` (l. 2969 og l. 7520) genskaber de gamle kroppe af
  `enforce_relation_evidence_target` og `validate_entity_description_subject`.
  - Spiket måtte derfor lægge vagterne på efter hver kørsel af `db-migrations.sql`. CI-kørslen gør det ved at hægte
    skelettet på begge filer.
  - Task 8 retter funktionerne, hvor de står (V2-6). Den skal også rette de to historiske blokke i
    `db-migrations.sql` eller sikre, at den nye blok sidst i filen vinder. Ellers mister en genkørt migration lydløst
    vagterne. Opgraderingstesten i Task 11 step 2 fanger det kun, hvis den sammenligner netop disse funktionskroppe.
- **F-6 (`entity_description` og SECURITY INVOKER) [udledt, ingen fejl målt]:** `FOR KEY SHARE` kræver UPDATE-ret
  på måltabellen.
  - I dag er det uden praktisk betydning. `authenticated` har kun SELECT på `entity_description` (`db-rls.sql`
    l. 342), så alle skrivninger går gennem SECURITY DEFINER-RPC'er. Triggeren kører derfor som ejeren.
  - CI gav ingen fejl.
  - Får en rolle senere direkte INSERT, rammer den »permission denied«. Task 8 bør gøre funktionen SECURITY DEFINER
    som de andre vagter, for robusthedens skyld.
- **F-7 (vagterne rammer skrivere uden eksistenstjek):** `red_relation` validerer ikke, at personen findes.
  db-verify bruger den med ikke-eksisterende personer (3.5). Med vagten afvises det nu. Det er vagtens formål og ikke en
  regression, men testene skal seede personen.

### 3.5 CI med vagterne slået til (step 2)

Kørt med `tests/sql/spike/ci_jobs_lokalt.py`:

- Kopierer de git-sporede filer til en scratch-mappe og hægter skelettet på `schema.sql` og `db-migrations.sql`.
  Repo'et ændres ikke.
- Oversætter hvert jobs trin fra `ci.yml` og giver alle basenavne et unikt præfiks.
- Et fejlet trin stopper ikke jobbet. Senere trin kan derfor være følgefejl.
- Fire varianter:
  - `base`: uden vagter (referencen);
  - `enforce`: vagterne som i planen;
  - `warn`: vagterne skriver en advarsel i stedet for at fejle, så hele inventaret kommer med, også efter første
    brud;
  - `enforce_kendte`: som enforce, men en undtagelsesliste giver kun en advarsel. Listen er efter type:id, ikke
    efter sted, og er tjekket mod loggene. Alt andet fejler. Kørslen viser, at der ikke findes andre brud end dem
    med disse type:id-par. Det gælder også i dblink- og R-sessioner, hvis advarsler aldrig når en log.

Lokale afvigelser fra CI:

- macOS og en lokal superbruger i stedet for `postgres`.
- PGPASSWORD er en dummy (trust-login).
- Trinnene `install.packages(...)` fejler lokalt (intet CRAN-spejl). Pakkerne er installeret, så det er uden betydning.

**Resultat pr. job.** Uden vagter er alle trin grønne. To trin var først røde af miljøgrunde (tomt PGPASSWORD) og
blev grønne, da de blev genkørt med en dummy. Med vagterne (enforce) er disse trin røde:

| Job | Trin | Første fejl (enforce) |
|---|---|---|
| evidence-promotion-db | 02 kumulativ migrationssti | `db-verify.sql:6724` fact på person -99 |
| evidence-promotion-db | 03 frisk schema-sti | samme (sidste kommando i trinnet; alle tidligere tests og ceremonier i trinnet er grønne) |
| interpretation-proposal-db | 02 og 03 (begge katalogrækkefølger) | samme, i scriptets db-verify |
| writer-1939-v50-db | 06 reimport writer fra pre-153 | `test-reimport-name-completion.sql:880` fact på person -153109 |
| writer-1939-v50-db | 35, 36, 37, 41 (opgraderingsharnesses 6d-1, 6d-2a, 6d-3, 6e-2) | `db-verify.sql:6724` |
| writer-1939-v50-db | 42 og 46 | `test-publication-persona.sql:54` narrativ omdøbt til familie -621017, som ikke findes |
| narrative-record-contract-db | 08 fuld historisk db-verify | `db-verify.sql:6724` |

Alle andre trin er grønne med vagterne.

I ren enforce stopper hvert rødt trin ved første fejl, så resten af trinnet når ikke at køre. Det gælder fx db-verify
efter l. 6724 og R-testene i trin 42. **Kørslen `enforce_kendte` dækker resten: alle trin i alle 4 jobs er grønne.** Den bygger på en undtagelsesliste
efter type:id (person -99, 1, -999904, -999951, -999941, -999942, -999943, -153109; familie -621017; faktum -1). Et
nyt brud på et af de samme id'er et andet sted ville derfor ikke blive set. Alle 201 advarsler i loggene ligger på
de 13 kendte steder.
Kun `install.packages` fejler, af miljøgrunde. Vagterne ramte kun de 13 kendte steder (201 advarsler i alt).

- Det gælder også alle R-baserede samtidighedstests:
  - `test-reimport-writer-locking.R`;
  - `test-narrative-record-concurrency.R` med 34 asserts;
  - `test-publication-persona-concurrency.R` og `test-publication-identity-concurrency.R`;
  - `test-source-text-revision-concurrency.R`.
- Vagternes `FOR KEY SHARE` gav altså ingen nye deadlocks eller timeouts i de eksisterende racetests.

**Inventar (warn).** Warn-varianten kører alt til ende og tager de samme låse som enforce. Hele CI rammer vagten 13
steder. Linjenummeret er sætningens linje. psql melder slutningen af DO-blokken.

| Sted | Række | Vej | Klasse |
|---|---|---|---|
| `db-verify.sql:6724` | fact på person -99 | testens INSERT | a |
| `db-verify.sql:7199/7202` | note på person 1 | `_version_upsert_row` (restore-hjælperen) kaldt af testen | a |
| `db-verify.sql:7305` | narrative på person 1 | testens INSERT | a |
| `db-verify.sql:7407` | narrative på person 1 | testens INSERT | a |
| `db-verify.sql:7502` | narrative på person -999904 | testens INSERT | a |
| `db-verify.sql:7625` | note på person 1 | testens INSERT | a |
| `db-verify.sql:8565-8574` | 6 påstande på fact -1 (CHECK-test for `date_certainty`) | testens INSERT; vagten fyrer før CHECK | a |
| `db-verify.sql:8810/8819` | relation person -999951 → medie | `red_relation` kaldt af testen | a |
| `db-verify.sql:8888` | relation person -999941 | `red_relation` | a |
| `db-verify.sql:9008` | relation person -999942 | `red_relation` | a |
| `db-verify.sql:9212/9213` | relation person -999943 | `red_relation` | a |
| `tests/sql/test-publication-persona.sql:54` | narrative omdøbt til `family` med personens id | testens UPDATE | a |
| `tests/sql/test-reimport-name-completion.sql:880` | fact på person -153109 | testens INSERT | a |

- **Klasse a** (13): testen skriver om en forælder, der ikke findes. Den rettes i Task 8 ved at seede forælderen.
  Ved `test-publication-persona.sql:54` skal testen have en familie med det id eller pege på en eksisterende familie.
  I alle 13 tilfælde ville den rigtige skriver have gjort det samme med en eksisterende forælder.
- **Klasse b** (en rigtig skriver, vagten bryder): **0.** Det er understøttet af `enforce_kendte` (undtagelser efter type:id, tjekket mod loggene). De fire `red_relation`-steder er en skriver, men den kaldes
  med ikke-eksisterende personer. Det er netop det, vagten skal afvise (F-7).
- `FACT_HAR_EVIDENS` blev ikke ramt nogen steder i CI.
- Delta-reviewets D-5-liste (6724, 7304, 7500, 7625) er bekræftet. De øvrige 9 steder er nye. Det samlede antal er
  13.

Kontrol af, at vagterne var aktive: warn-loggene har 12 gennemførte db-verify-kørsler og 12 brud ved l. 6724.

**Ikke dækket:** ingen trin er sprunget over. Opgraderingsharnesses, der bygger deres egen base, fik vagterne gennem
den påhæftede `db-migrations.sql`. Den gamle `schema.sql` fra `git show <commit>` fik dem ikke, men skemaet bliver
altid migreret bagefter.

### 3.6 Anbefaling til hovedsessionen

Fakta til go/no-go-kriterierne i planen:

1. **»Ingen 40P01 i de serialiserede tilfælde«: opfyldt.**
   - Alle scenarier med planens orden gav 0 deadlocks i tre kørsler.
   - Positive kontroller viser, at cyklerne ville være kommet med v2.1-ordenen eller uden L5b.
2. **»Alle CI-jobs grønne«: ikke opfyldt, men kun af klasse a.**
   - 13 teststeder skriver om ikke-eksisterende forældre.
   - Planen tillader at rette dem i Task 8 ved at seede forælderen.
   - Ingen rigtig skriver brydes.

Min anbefaling er **go med betingelser**:

- Task 8 retter de 13 teststeder (seed forælderen).
- Task 8 lægger vagterne i `schema.sql` og sørger for, at `db-migrations.sql` ikke genskaber de gamle kroppe bagefter
  (F-5).
- Task 8 gør `validate_entity_description_subject` til SECURITY DEFINER (F-6).
- Global Constraints' samlede loft via `SET LOCAL statement_timeout` ændres (F-4), fordi det ikke virker inde i
  funktionen.
- Task 11 kører de samme scenarier mod den rigtige `red_slet_person_helt`. Skelettet sletter langt mindre og kan
  derfor ikke stå i stedet for den rigtige funktion (3.3).
- Det rigtige preview skal mindst indeholde memberships, medierelationer, X∪Y og kandidatrækker. Ellers bliver de
  fail-closed-udfald fra F-3 til stille tab.
