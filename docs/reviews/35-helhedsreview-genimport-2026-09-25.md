# 35 — Helhedsreview: genimporten 1. august – 25. september 2026

**Dato:** 2026-09-25
**Spørgsmål fra projektejeren:** Er vi samlet set på rette vej? Tilfører vi reel værdi? Er der
opstået fejl, huller eller udeladelser i koden undervejs?
**Status:** færdigt review. Ingen kode er ændret. Anbefalingerne i §6 er beslutningspunkter til
`docs/decisions.md`, ikke en omprioritering af roadmappen.

## Kort svar

1. **Retning: ja — siden 22. august, men generaliteten er endnu ikke bevist.** Den fælles kæde
   fra bog til kildevisning er den rigtige, og selve prod-fladen er i god stand: ingen lækage til
   `anon`, og prod svarer præcist til migrationerne. Men kæden er kun bevist på 2018-20: kun 8 af
   1939's 592 poster kan i dag kobles til en person ad samme vej.
2. **Reel værdi: ja, men lidt, og mest i august.** Den største læserværdi var den rensede
   1939-tekst og kildehenvisningerne pr. biografi. Siden 6/9 er der ikke leveret noget, en læser
   kan se. Trin 4 ændrer ved design intet for læseren, klausullaget deler kun 17 % af posterne op,
   og ca. 71 % af de menneskelige afgørelser, som trin 4 kræver, kan ikke føre til noget
   kanonisk. Kernefunktionen »er vi i familie?« er urørt siden 14/7.
3. **Fejl og huller: få i data, flere i værnene.** To værn holder ikke det, de lover:
   model-sandboxen (P1 — og lokale prod-kopier kan læses uden adgangskode) og deploy-gatens
   negative tests (S1). Intet tjekker, at et claims værdi står i den klausul, det citerer (P10).
   Ingen af dem har gjort skade endnu.
4. **Tidskritisk:** klausul-segmenteringen har en fejlklasse (P3), og writeren nægter at skrive
   klausuler om. Rettes 2018-20 ikke, før 4.4's forslag køres i prod, lukker det sidste
   fortrydelsesvindue for 4.1c, og de defekte klausuler bliver permanente.
5. **Udeladelser:** der er ingen vej til sletning for levende personer, og deres biografitekst er
   i perioden kopieret ind i append-only-tabeller (G1). Fakta vises ikke for læseren (U1), og
   status-dokumenterne modsiger sig selv (F-C).
6. **Det vigtigste at beslutte:** hvordan kæden skal give læserværdi før trin 6-7, og om
   afgørelsesarket skal begrænses til det, der kan promoveres.

## Grundlag og metode

- **Kode:** `73e0363` (1/8 kl. 23:06) → `origin/main` (`77a0c22`): 903 commits, 653 filer,
  +223.634 / −3.083 linjer. Union-redigeringen fra 1/8 ligger dermed i basen. Grenen
  `feat/147-4-5-pilot` (4.5-piloten, ikke merget) er kun medtaget, hvor den ændrer et fund.
- **Prod-tilstand:** målt læse-kun i en lokal restore af prod-dumpet fra 2026-09-23
  (`daa44_rehearsal_20260923181256_20852_tpl`). Kun tællinger, katalogopslag og nøgle-eksistens i
  jsonb; ud over det er kun korte klausulfragmenter fra afdøde personers poster læst (de
  forkortelser, der citeres i P3). Intet er sendt til en ekstern model. Ifølge decisions.md 23/9
  (4.4 parkeret) er der ikke skrevet programdata til prod siden; changelog slutter 20/9 (se F-C).
  Live-prod og `get_advisors` kunne ikke nås (F-E).
- **Review:** tre læse-kun review-agenter (SQL-prod-fladen; pipeline/GDPR; web/tests) og en
  uafhængig adversarial agent på udkastet (§5). Hvert HIGH- og MEDIUM-fund er efterprøvet af mig
  ved kodelæsning, en målt tælling eller en lille reproduktion; det, jeg ikke selv har
  reproduceret, er markeret. Et planlagt Codex-krydstjek blev ikke kørt: det krævede, at Codex'
  egen sandbox blev slået fra, og det blev afvist af sessionens sikkerhedsfilter.
- **Sammenligningspunkt:** helhedsreviewet 2026-07-30 og afvigelsesvurderingen 2026-08-22.

## 1. Retning — er vi på rette vej?

**Ja, siden 22. august. Ikke i de tre uger før. Og generaliteten er ikke bevist endnu.**

Tilføjede linjer efter commit-dato (`--no-merges`):

| Område | 1/8 → 22/8 | 22/8 → 25/9 |
| --- | ---: | ---: |
| Scripts, 1939-specifikke (navne med 1939/v50/C0/C3/D1/D2) | 65.979 | 8.582 |
| Scripts, generelle | 3.792 | 14.772 |
| SQL (skema, migrationer, RLS, verify) | 13.085 | 22.463 |
| Tests under `tests/` | 4.105 | 23.377 |
| Planer (`docs/superpowers/plans`) | 21.883 | 17.218 |
| Øvrige docs | 11.368 | 14.861 |
| web + mobil + `packages` | 4.932 | 2.460 |

De første tre uger gik til en udokumenteret drejning mod et 1939-specifikt provenance-lag
(vurderingen 22/8 fastslog det selv). Kursrettelsen virkede: 1939-specifik kode faldt til en
ottendedel, og det generelle fundament — skrivevej, klausullag, prædikat-navnerum, runner,
ingest — fik hovedparten. Målarkitekturen følger visionen: kilde → observation → fortolkning →
afgørelse → promotion → publicering, med fail-closed gater, append-only historik og hash-bundne
GO'er. Samtidig **halveredes arbejdet på læser- og redaktørfladerne** (4.932 → 2.460 linjer).

**Generaliteten er kun bevist på én udgave.** 2018-20's 591 kildeposter kan alle kobles til en
person via `person_external_id.record_key`; for 1939 gælder det 8 af 592. Trin 6 (»begge udgaver
gennem samme kæde«) forudsætter altså identitetsarbejdet i trin 5, og 1939's modelkald udelukkes
i dag automatisk, fordi hovedpersonen ikke kan afgøres.

**Driften har været sikker for data, ikke for eksponering.** Omkring 18 prod-skrivninger siden
1/8 uden registreret datatab; oprydningshændelsen 18/9 (worktrees og tre prod-dumps slettet) blev
gendannet fra snapshot. Men tre anon-huller var live i prod, indtil de blev lukket 19-20/9:
familie-oraklet (35 af 682 familier) og `media_afbilder_skjult`, begge fra før perioden, og
læsbare fakta (fotograf, kreditlinje, datering) om billeder af levende, som medie-rettelsen MM-01
6/8 kun lukkede halvt. Tidligere advisor-kørsler havde noteret fundene som »kendte mønstre«
(database-current-state 22/7; changelog: »117 fund, alle kendte mønstre«).

**Fejl er opstået undervejs, og gaterne har fanget dem:** `red_slet_person` blev brudt for alle
551 bundne 1939-personer af augusts nye bindingstabel (rettet 20/8); #153's migrationsguard ville
have blokeret sig selv i prod (fundet 3/9); #152's læsefunktioner gav dubletter efter fuld
fortrydelse (fundet i 149b); svar-cachen havde tre nøglekollisioner i rigtige data (#188);
eligibility-værnets inputbinding havde et hul (#185); `red_*`-vagten var versionsblind (#209). Det
er et sundhedstegn — og forklaringen på, hvorfor hvert skridt koster så meget.

**Prisen pr. skridt er høj, og reglerne mod den bider kun nogle gange.** Planer er 39.000 linjer
på otte uger — dobbelt så meget som al generel script-kode og mere end al SQL. Projektejeren har
selv diagnosticeret mønstret to gange (3/9 og 23/9). Reglen fra 3/9 om »én dags synligt trin«
virkede, da planerne var korte: 4.3a, 4.3b og 4.4 havde planer på 311-379 linjer og blev leveret
på få dage. Men den bider ikke konsekvent: planerne for 2018-20 fase A, klausul-projektionen, 4.5
og fase B er 2.413, 2.197, 1.780 og 1.397 linjer. Ingen regel sætter loft over det, der faktisk
vokser — planens længde og antallet af gater pr. skridt — og netop de korte planer viser, at et
loft virker.

## 2. Reel værdi — hvem har fået hvad?

### 2.1 Det, som læseren kan se (leveret siden 1/8)

| Leverance | Dato | Omfang |
| --- | --- | --- |
| 1939-biografier erstattet af renset tekst fra menneskeverificerede grænser (fase B) | 19/8 | 551 biografier |
| 1939-personer gjort offentlige (D1) og gift-ind-ægtefæller (D2) | 19-20/8 | 68 + 21 personer |
| Record-koblinger (C0) og fem rettede 1939-sager (C3) | 21/8, 29/8 | 9 + 5 |
| Biografiversioner med kildehenvisning til konkret kildepost | 1939: aug.; 2018-20: 6/9 | 1.104 publicerede bindinger (563 + 541) |
| Medie: kreditlinje, kildelink, alt-tekst; feed-billeder | 6/8, 20/9 | — |

Fase B er periodens største læserværdi: 1939-teksten var fejlbehæftet og er nu ren. For
biografierne er visionens succeskriterium — »en troværdig, sporbar kildevisning« — indfriet for
begge referenceudgaver.

**Risikoreduktion (ikke læserværdi):** lukningen af de tre anon-orakler og medie-indkapslingen
19-20/9.

### 2.2 Det, som redaktøren kan bruge

Historik-panel med fortryd (6/8), 12 medie-metadatafelter (7/8), record-bundet narrativ-editor
(#152). Fortolkninger kan ses i kildepersona-køen (`KildepersonaKo.tsx`), men køen er ikke den
aktive identitetsvej (status.md).

### 2.3 Det, der er bygget, men ikke synligt — og ikke bliver det med den nuværende plan

Målt i prod-kopien 23/9:

| | Antal |
| --- | ---: |
| Personer / fakta i den kanoniske model | 1.811 / 7.197 — **samme tal som 20/8** |
| Klausuler (privat lag) | 868 på 591 poster |
| — poster med kun én klausul | **490 (83 %)**; 113 poster har en klausul på over 1.000 tegn |
| Fortolkninger / promotions | 0 / 0 |
| Placements / slægts- og linjemedlemskaber | 0 / 0 |
| Hændelser (`haendelse`) | 0 |
| Accepterede kildepersona-identiteter | 595 |
| Promoverbare prædikater | 5 af 50 (`person.birth`, `.byname`, `.death`, `.name`, `.title`) |

Fire forhold gør, at trin 4 — også når det er færdigt — hverken ændrer noget for læseren eller
beviser så meget, som det ser ud til:

1. **Promotion i trin 4 er binding, ikke oprettelse** (beslutning 6/9, valg 6; spec §8.3). Der
   kommer ingen nye fakta, personer eller citationer.
2. **Læseren ser kilder pr. biografi, ikke pr. faktum.** `DetailPanel.tsx` viser biografiversioner
   og »Kilde i Aarbogen«, men ingen fakta-sektion — kun leveår og titel fra cachen; `fact` hentes
   kun for at finde kilden for personer uden bog-nummer (`fetchProveniens`). Beslutningen om en
   fakta-sektion har været ÅBEN siden 20/8. En binding på faktum-niveau har derfor intet sted at
   blive vist.
3. **Klausulgranulariteten (#148) er i praksis ikke opnået.** 83 % af posterne består af én
   klausul, ofte på flere hundrede tegn. Metrikken »klausulbinding 100 %« er dermed triviel for de
   fleste poster, og metodebeviset er svagere, end tallene antyder.
4. **Den menneskelige byrde er stor, og det meste fører ingen steder hen.** 4.5-piloten har 243
   beslutningslinjer for 34 poster (≈ 7 pr. post); fremskrevet til 2018-20's 488 `eligible`
   poster er det ≈ 3.400 afgørelser. Kun 46 af pilotens 160 gyldige claims (29 %) har et
   promoverbart prædikat; **ca. 71 % af afgørelserne kan i trin 4 ikke føre til noget kanonisk —
   heller ikke en binding** (spec 11.2 og 11.3 er uafklarede). Til gengæld viser 4.3b's domme
   (85 af 86 »J«), at stikprøvekontrol er realistisk.

Trin 4 er ikke værdiløst: det er metodebeviset, roadmappens trin 7 hviler på. Men programmet har
i sin nuværende form **ingen planlagt læserværdi før trin 6-7**, og med det tempo, trin 1-4 har
haft (2-3 uger pr. trin plus GO-pakker), ligger det flere måneder ude.

### 2.4 Kernefunktionen og forretningsmodellen står stille

- »Er vi i familie?« (`packages/core/src/relationship.ts`) er sidst ændret 14/7.
- Helhedsreviewet 30/7 rangerede som størst værdi pr. indsats: hændelser (#130), geo (#131),
  fuldtekstsøgning (#132) og forslagskøens godkend-flade (#128). Alle fire er mærket
  `uden-for-genimport` og urørt siden 3/9 — et bevidst fravalg (se §4.2). `haendelse` har stadig
  0 rækker.
- Medlem/forsker-tier (forretningsmodellen) har ingen teknisk bærebjælke; præsenslisten er reelt
  kun for redaktionen.

## 3. Fejl og huller i koden

### 3.1 Oversigt

»I perioden« = indført eller væsentligt ændret siden 1/8. »Latent« = kan ikke ramme de data, der
findes i dag.

| ID | Alvor | Område | Kort | Tilstand |
| --- | --- | --- | --- | --- |
| P1 | HIGH | GDPR/modelkald | Sandbox spærrer kun hjemmemappen; lokale prod-kopier kan læses uden adgangskode; intet tjek for kommandokørsel | I perioden · intet lækket |
| S1 | HIGH | Deploy-gate | ~30 negative tests i `db-verify` består, selvom vagten mangler | I perioden |
| G1 | MEDIUM | GDPR/sletning | 46 levende kan ikke slettes; deres tekst ligger i append-only-tabeller | I perioden |
| P3 | MEDIUM | Klausuler | Forkortelser med stort forbogstav splitter tavst; kan ikke skrives om | I perioden · i prod · tidskritisk |
| P4 | MEDIUM | Runner-cache | Cachen binder ikke klausulsættet; segmenter-versionen står stille | I perioden · latent |
| S4 | MEDIUM | Writer | Ny forslags-kørsel lægger sig ved siden af den gamle | I perioden · latent |
| P10 | MEDIUM | Proveniens | Intet tjekker, at et claims værdi står i den citerede klausul | I perioden |
| P2 | MEDIUM | GDPR/modelkald | Regel 4 leder efter en notation, bogen ikke bruger; 1939 ikke dækket | I perioden · latent |
| S2 | MEDIUM | RLS/ACL | Nye `public`-funktioner er anon-kaldbare som standard | Ældre · vagten fra 20/9 dækker kun `red_%` |
| S3 | MEDIUM | Skema | `schema.sql` er forældet for id-tildeling | Ældre · delvis rørt |
| W1 | MEDIUM | Web | Narrativ-editoren nulstiller »privat« ved gem | I perioden · latent |
| W2 | MEDIUM | Web | Hentefejl for medie-fakta vises som »ingen data« | I perioden |
| P6 | MEDIUM | CI | CI navngiver 10 af 85 Python-testfiler; segmenteringen er ude | I perioden |
| P5 | MEDIUM | Runner | `main`s runner stoler på manifestets egen hash | Rettet på grenen |
| F-C | MEDIUM | Styring | status.md og database-current-state.md modsiger sig selv | I perioden |
| F-D | MEDIUM | PII lokalt | 83 fulde prod-kopier (5,5 GB); harnesset rydder ikke op | I perioden |
| S5, S6 | LOW-MED | Writer, skema | Blandede batches ved reversal; forældet C3-migrationsfil | Latent / i perioden |
| øvrige | LOW | — | Se §3.4 | — |

**Tre af fundene hænger sammen — og tiden er knap.** Rettes P3 (eller #189), skal posterne
segmenteres om. Men writeren afviser nye klausuler for en post, der allerede har dem
(`REIMPORT_WRITER_CLAUSE_EVIDENCE_EXISTS`, `schema.sql:3392`), så en omsegmentering af 2018-20
kræver enten restore eller en ny writer-operation. Og når 4.4's forslag køres i prod, lukker
backuppen 4.1c's fortrydelsesvindue (decisions.md 23/9) — en restore ville i øvrigt også rulle
anon-hærdningen 19-20/9 tilbage. Bliver klausulerne alligevel skrevet om, genbruger cachen gamle
svar mod nye klausuler (P4), og en ny forslags-kørsel lægger sig ved siden af den gamle (S4). De
tre bør afgøres samlet og **før 4.4-GO**.

### 3.2 HIGH

#### P1 Model-sandboxens grænse holder ikke det, dokumentationen lover
**Lokation:** `.claude/skills/daa-extract/scripts/sandbox/runner-gate.sb.template`
(`(allow default)` + `(deny file-read* (subpath "__HOME__"))`); `gate-access-test.sh` tester kun
stier under `$HOME` og repoet; `evidence_runner.py` og `run_evidence_43b.py` indeholder intet tjek
for `command_execution`.
**Påstanden:** profilen skal gøre »modellen ser én record ad gangen« til en OS-håndhævet grænse,
med præmissen »hjemmemappen er den interessante grænse, fordi al PII bor der«. status.md gentager
det. Templaten modsiger sig selv om indlejring (l. 24 »nestet Seatbelt fejler«, l. 26 »virker
fint«).
**Målt (kun returkoder, intet indhold læst):** inde i den udfyldte profil kan en proces liste
`/opt/homebrew/var/postgresql@17` (datamappen med de lokale prod-kopier), `/private/tmp`,
`/Users/Shared` og `/Volumes`, og `psql -h /tmp -d postgres -c 'select 1'` lykkes. Den lokale
Postgres kører med **`trust` på både socket og TCP** (`pg_hba.conf`: `local all all trust`,
`host all all 127.0.0.1/32 trust`), så enhver lokal proces kan læse alle 718 baser uden
adgangskode — inkl. de 70 levende personer i hver prod-kopi. Den adversariale agent målte desuden
psql via TCP og udgående https (200) inde i profilen og læseadgang til scratchpad-mapper med PII.
`~/.private` og `work/` er korrekt spærret.
**Hvorfor intet er sket:** de gemte fixtures med gate har ingen `command_execution`-items, mens
kanarien uden gate har én. Beskyttelsen hviler på, at Codex' egen `--sandbox read-only` ikke kan
starte indlejret (`sandbox_apply: Operation not permitted`, rc=71), og at Codex så undlader at
køre kommandoen — en utilsigtet egenskab ved en selvopdaterende binær (i dag 0.155.1; 0.153.4 d.
11/9), som ikke er bundet i runner-manifestet.
**Konsekvens:** projektets hårdeste invariant (8) hviler på en grænse, hvis dokumenterede præmis
er forkert. Ingen lækage er observeret — hullet er i værnet, ikke i en hændelse.
**Retning:** (1) lad runneren afvise en record, hvis strømmen indeholder et `command_execution`-item
— det billigste og mest robuste tjek; (2) `scram-sha-256` i stedet for `trust` i den lokale
`pg_hba.conf`; (3) spær PG-datamappen, `/private/tmp`, `/private/var/folders`, `/Users/Shared` og
`/Volumes` og genåbn call-dir til sidst — at spærre kun socket'en er ikke nok, og udgående net kan
ikke spærres, fordi API'et kræver det; (4) bind Codex-versionen i manifestet; (5) udvid
adgangstesten med de nye stier og et psql-forsøg.

#### S1 `db-verify` — deploy-gaten — kan ikke se, om en vagt forsvinder
**Lokation:** `db-verify.sql`, fx 4038-4046 og dblink-testen 3185-3213:
```sql
v_error:=NULL;
BEGIN
  UPDATE private.source_persona_identity_event SET evidence='{"rewritten":true}' WHERE …;
EXCEPTION WHEN others THEN v_error:=SQLERRM; END;
IF v_error NOT LIKE 'EVIDENCE_APPEND_ONLY%' THEN RAISE EXCEPTION 'FEJL: …'; END IF;
```
Lykkes den forbudte handling, forbliver `v_error` NULL; `NULL NOT LIKE …` er NULL, og `IF` udløses
ikke. Reproduceret med en tilsvarende `DO`-blok: »TESTEN BESTOD selvom handlingen lykkedes«. I
dblink-testene ruller den efterfølgende `ROLLBACK` desuden B's vellykkede skrivning tilbage, så
optællingen bagefter altid giver 1: testen beviser, at B *venter*, ikke at B *afvises*.
Promotion-previewets `reason_code <> …` (8 steder) har samme svaghed.
**Omfang:** 42 `IF v_error NOT LIKE` uden NULL-værn (3 har det). Heuristisk optælling: ca. 12 er
reddet af en `RAISE` inde i blokken; **ca. 30 er blinde**. Ingen anden test nævner
`EVIDENCE_APPEND_ONLY` eller konfliktkoderne. Samme klasse: medie-gate-testen (9918-9919) kører
aldrig sin rigtige gren, fordi hverken CI eller prod har et upubliceret medie, og bio-læsetesten
(2216-2236) springes altid over ved kontrakt v2.
**Konsekvens:** vagterne findes i prod i dag. Men fjerner eller brækker en fremtidig migration en
append-only-trigger eller en konfliktvagt, forbliver CI og rehearsal grønne — og invariant 1
(»påstande overskrives aldrig«) hviler netop på de triggere.
**Retning:** `IF v_error IS NULL OR v_error NOT LIKE …` / `IS DISTINCT FROM` overalt, plus en
statisk CI-vagt, der afviser mønstret uden NULL-værn.

### 3.3 MEDIUM

#### G1 Levende personer: ingen sletning, og deres tekst er gjort uforanderlig i perioden
**Målt:** 1.161 af 1.811 personer kan ikke slettes via `red_slet_person` (`schema.sql:5362-5398`)
— heraf **46 af de 70 levende**, der blokeres af begge vagter (`PERSON_HAR_NARRATIVE_PUBLICATION_HISTORY`
og `PERSON_HAR_KILDEIDENTITET`). Publiceringsblokeringen er godkendt design (29/8, ud fra 563 +
591 narrativer); kildeidentitets-blokeringen omfattede 8 personer, da tombstone-beslutningen blev
udsat 20/8 (»det haster ikke«), og omfatter nu 595.
**Det egentlige hul:** godkendelsen 29/8 nævner ikke levende personer, og i perioden er deres
tekst kopieret ind i tre append-only-lag: de 46 levendes eneste publiceringshændelser
(149b's `draft_created`) bærer hver hele biografiteksten i `after_state.narrative.text`
(`trg_narrative_publication_event_append_only`); 4.1c skrev 59 klausuler for 47 levende
hovedpersoner; og 149a's helpost-observationer omfatter de samme 47 poster. En tombstone fjerner
ingen af disse tekster — det konstaterede beslutningen 20/8 selv for kildeteksten.
**Konsekvens:** en sletteanmodning fra en levende person (GDPR art. 17) kan i dag hverken
gennemføres gennem produktet eller i hånden uden at bryde append-only-designet. Det er ikke en
fejl, men en bevidst midlertidig tilstand **uden udløbskriterium**, som perioden har gjort større.
**Retning:** tag stilling til en art. 17-vej for append-only tekst (dokumenteret
behandlingsgrundlag, eller en teknisk vej); indtil da: udeluk levende hovedpersoner fra
append-only-writerne, som modelkaldene allerede gør, og overvej at lade publiceringshændelser
bære hash og reference frem for hele teksten.

#### P3 Klausul-segmenteringen splitter tavst ved forkortelser med stort forbogstav
**Lokation:** `clause_segment.py:49` — kun *små* ukendte forkortelser på ≤ 4 tegn beskyttes og
flages:
```python
if bare and bare.isalpha() and len(bare) <= 4 and not bare[0].isupper():
    return True, True  # ukendt kort forkortelse: split ikke, men flag
...
return False, False
```
`Sr.`, `Pol.`, `Jahrg.` falder igennem til `return False, False` = split *uden* flag, og `; ` har
ingen forkortelsesvagt (isolerer `1908;`). Det bryder modulets eget løfte (linje 5): »Tvivl
segmenteres konservativt (længere klausul) og flagges.«
**Målt i prod (4.1c):** 26 af 868 klausuler er under 8 tegn, fordelt på 21 poster. 21 er romertal
(#189); resten er forkortelser klippet midt i en sætning — `Sr.` efterfulgt af »Excellenz des
Herrn …«, `Jahrg.` efterfulgt af »10. 1909, s. 113-121);«. #189 dækker kun romertallene.
**Konsekvens:** modellen læser sønderdelte sætninger (#189 tilskriver 4.3b's eneste usande claim
netop det), redaktøren får meningsløse klausuler i afgørelsesarket, og 4.5-pilotens tal måles på
den defekte segmentering. Se desuden tidsvinduet i §3.1.
**Retning:** flag altid en ukendt forkortelse, uanset forbogstav, og udvid profilens
forkortelsesliste (`Sr.`, `Pol.`, `Jahrg.` m.fl.). At blokere split efter ethvert kort versal-ord
vil også ramme ægte sætningsslut efter korte stednavne, så split-politikken for versaler bør
afgøres på en måling.

#### P4 Svar-cachen binder ikke klausulsættet, og segmenter-versionen står stille
**Lokation:** `evidence_runner.py` — `canonical_record_input` = `sha256(post_verbatim_text)`;
`CACHE_KEY_FIELDS` indeholder profil, model, prompt, record_key og denne hash, men ikke
klausulernes `(ordinal, tekst)`. Profil-versionen er bumpet ved hver ændring af `clause_rules`
(1.0 → 1.3), men rettelser i *koden* bumper intet: `segmenter_version` er den hårdkodede streng
`clause_segment.py@v1` (`build_clause_ledger.py:93`), uændret gennem de fire kodeændringer 10/9
(d5c5591, 4fd4488, a22830e, 4399146).
**Konsekvens:** rettes P3 i koden, genbruges gamle svar; et claim, der citerede ordinal 2, peger nu
på en anden klausul, og `build_43b_proposal_manifest.py` henter `verbatim_sha256` fra det
*aktuelle* input, så writeren accepterer det forkerte citat. Pipeline-agenten reproducerede det
med en syntetisk falsk model; jeg har efterprøvet mekanismen i koden. Ledgeren kan heller ikke
fortælle, hvilken segmenterkode der skrev prod-klausulerne.
**Retning:** læg en hash over sorteret `(ordinal, verbatim_sha256)` i nøglen, bump
`RUNNER_CONTRACT_VERSION`, og afled `segmenter_version` af kodens hash.

#### S4 En ny forslags-kørsel lægger sig ved siden af den gamle
**Lokation:** `schema.sql:3649-3653`: dublet-tjekket er afgrænset til samme `batch_id`, så et nyt
batch for samme post afvises ikke, og nye `proposed`-fortolkninger lægges ved siden af de gamle.
`3770-3780`: den seneste *maskinelle* klausuldisposition overskrives, så et `afventer_identitet`
kan blive til `fortolkning_foreslaaet`, og signalet om manglende identitetsarbejde forsvinder.
Menneskelige dispositioner er beskyttet. Ifølge SQL-agenten kræver spec'erne fail-closed
afvisning og en menneskelig superseded-beslutning (ikke selv efterprøvet). 0 fortolkninger i prod
i dag; første genkørsel kommer, når P3 rettes.

#### P10 Intet tjekker, at et claims værdi står i den klausul, det citerer
`validate_claim_value` (`evidence_extract.py:58`) tjekker kun formen (ikke-tom streng, `raw`
findes); runneren kalder kun den, og writeren binder kun `(ordinal, hash)`. Ordrethed er alene en
»mekanisk hjælp, ikke en afgørelse« i afgørelsesarket (`decision_sheet_html.py`, `verbatim()`).
4.5-pilotrapporten på grenen skriver det modsatte (»runnerens validering afviser et claim, hvis
værdien ikke står i den citerede klausul, så de 9 `VALUE_INVALID` …«) — de 9 var formfejl.
**Konsekvens:** visionens »ingen evidens uden anker« håndhæves på klausulniveau kun af mennesket.
**Retning:** gør ordret-tjekket til en runner-afvisning (billigt), og ret pilotrapporten.

#### P2 GDPR-regel 4 leder efter en notation, bogen ikke bruger — og 1939 er ikke dækket
**Lokation:** `export_model_eligibility.R:124-133`:
`verbatim_text ~ 'f\\.[^0-9]{0,20}(19[5-9][0-9]|20[0-9][0-9])'`.
**To fejl i reglen:** `[^0-9]{0,20}` kan ikke passere dagtallet — `'f. 12. Maj 1955'` giver `false`
(verificeret), selvom kommentaren lige over siger, at reglen er bygget til netop den form. Og
2018-20 skriver fødsel som `*`: kun 4 poster har `f.` som selvstændigt ord, mens 41 har `*` + et år
≥ 1950.
**Målt effekt i dag: ingen.** Af de 41 har 40 en levende hovedperson (regel 1), og den sidste
(V-167) har fire levende i egne familier (regel 2). Ingen af de 34 poster, der er sendt til
modellen, har en `*`-fødselsangivelse med år ≥ 1950 (to har et andet år ≥ 1950, fx dødsår — ikke
klassificeret). De to træf, målingen 6/9 talte som »berørt af regel 4«, var falske positiver.
**1939 er ikke dækket:** regel 1-2 læser rækkens eget `levende`-flag, men 3 ikke-levende
personrækker er `samme_som`-koblet til en levende person, og en 1950-grænse kan aldrig slå til i en
bog fra 1939. Det holder i dag kun, fordi 1939-poster ikke kan kobles (8 af 592) og derfor
udelukkes automatisk.
**Retning:** notation og tærskel i udgaveprofilen; regel 1-2 på den `samme_som`-kollapsede
identitet; en testtabel med positive og negative former. SQL'en har i dag 0 tests. Skal være på
plads før trin 6.

#### S2 Nye funktioner i `public` bliver anon-kaldbare som standard
`pg_default_acl` i prod-kopien: `postgres | public | f | {anon=X/postgres,authenticated=X/postgres,…}`.
`db-rls.sql:14-15` kører `alter default privileges revoke execute on functions from public, anon, …`
uden `for role postgres in schema public` og rammer derfor ikke den skema-specifikke post.
Kommentaren lige over (»Fremtidige funktioner skal derfor altid have en eksplicit, gennemset
grant«) beskriver en virkning, filen ikke har, og slut-vagten fra 20/9 dækker kun `red_%`. Det er
samme klasse som anon-orakel-hændelsen 19/9: den næste `SECURITY DEFINER`-hjælper i `public` bliver
anon-kaldbar, uden at noget opdager det. I dag er 24 ikke-`red_`-funktioner anon-kaldbare, alle
vurderet bevidste. *(Katalogposten er målt; virkningen på nye funktioner følger af PostgreSQL's
regler for default privileges.)*

#### S3 `schema.sql` — den erklærede source of truth — er forældet for id-tildeling
`schema.sql:4945-4947` (`red_upsert_fakta`): `INSERT INTO fact(id, …) VALUES ((SELECT
coalesce(max(id),0)+1 FROM fact), …)`, mens sidste definition i `db-migrations.sql` (= prod) bruger
sekvensen. `schema.sql` har 27 `max(id)+1`-forekomster, og tabellerne er IDENTITY. En base bygget
fra `schema.sql` alene blander eksplicitte id'er med sekvensen og giver duplicate key ved første
sekvens-insert efter et redaktørkald. CI opdager det ikke, fordi alle CI-veje kører
`db-migrations.sql` oven på. Ældre end perioden, men C3-arbejdet rørte seks af funktionerne uden at
rette dem i `schema.sql`. Relevant ved gendannelse: Supabase free tier har ingen backup.

#### W1 [latent] Web-narrativeditoren nulstiller »privat« ved hvert gem
`web/src/components/PersonNarrativeRecordEditor.tsx:67`:
`...(text === undefined ? {} : { tekst: text, privat: false })`. Serveren anvender værdien
ubetinget (`schema.sql:12641-12644`: `SET tekst=p_text,privat=p_private`), og web-typerne for
record-editoren kender ikke feltet. Mobilens `NarrativEditor.tsx` har en synlig privat-kontakt og
sender den korrekt. En narrativ, en redaktør bevidst har gjort privat, mister markeringen ved næste
gem i web — og `narrative_publication_allowed` afhænger netop af den. **Målt:** 0 af 1.169
narrativer er private i dag.

#### W2 Hentefejl for medie-fakta vises som »ingen data«
`web/src/data/media.ts:300-317` (`fetchMediaFakta`): tre Supabase-kald uden `error`-tjek. Ved en
fejl mister Lightbox tavst kreditlinjen (et krav ved CC-licenser), og redaktørens medie-overlay
viser tomme felter. Overlayets værn mod dublet-påstande diffes mod netop dette resultat, så en
redaktør, der udfylder felterne igen, opretter nye påstande oven på de eksisterende. Kaldestedernes
`.catch()` i `Redaktion.tsx` er død kode. Resten af web-laget følger `orThrow`/`getAll`-konventionen.

#### P6 CI navngiver 10 af 85 testfiler i `daa-extract/scripts`
`ci.yml` lister pytest-filerne eksplicit, så nye testfiler er udelukket som standard. Ude er bl.a.
`test_clause_segment.py`, `test_clause_ledger.py` og `test_build_clause_ledger.py` — altså
segmenteringen, der skrev prod-klausulerne. GDPR-SQL'en (`export_model_eligibility.R`) og
`export_43b_runner_input.R` har ingen tests, og `test_gate_profile_*` tester profilens *tekst*, ikke
at operativsystemet håndhæver den — derfor fangede ingen test P1. Playwright-suiten (`web/e2e`)
kører heller ikke i CI. Mange af de 75 udelukkede filer hører til engangsværktøjer for 1939, men
listen skelner ikke. Lokalt er alt grønt: 245 pipeline-tests, web 927 og `@daa/core` 417 (0 spring).

#### P5 [rettet på grenen] `main`s runner stoler på manifestets egen hash
`run_evidence_43b.py` på `main`: `if manifest.get("manifest_sha256") != args.approved_sha256` —
feltet læses fra filen og genberegnes ikke, så en ændret bundtliste eller model kan passere GO, og
klausulerne er ikke bundet til den godkendte helpost. Grenen lukker begge (`check_contract`,
`MANIFEST_TAMPERED`, `verify_runner_manifest`, `check_clauses_within_post`). **Kør ikke runneren fra
`main`, før grenen er merget.**

#### F-C status.md og database-current-state.md modsiger sig selv
CLAUDE.md pålægger enhver agent at læse `status.md` først. Den er vokset ved, at tillæg sættes
foran, mens brødteksten ikke rettes (gælder `origin/main` og grenen):
- »Det aktive programmål er nu #152.« — trin 4 er aktivt.
- #152-rækken: »`produktionsverificeret` (2026-09-06)« og i samme celle »Ingen production cutover
  eller produktions-GO er givet.«
- 149a- og 149b-rækkerne: »`produktionsverificeret` (2026-09-06)« og i samme celle »Ikke
  `produktionsverificeret` …«.
- »Fortolknings- og promotionlaget findes, men ingen reel extractor-runner udfylder det.« —
  runneren er kørt på 34 rigtige poster.
- »2018-20 har … ikke source records« — 591 records i prod siden 6/9.
- »Funktionelt kodegrundlag: commit `cc9d7d5`« — forældet.
- Klausulgranularitet står som `specificeret`, mens 868 klausuler er skrevet i prod.
- `database-current-state.md` §4: »`interpretation_proposal` … mangler fortolknings-projektionen
  (#196)« — merget 23/9 (at der ingen prod-fortrydelse er, er derimod stadig sandt: restore er
  valgt). Og »1939-publicering: Pauset« — 563 publicerede 1939-bindinger.
- `changelog.md` slutter 20/9; #212-#215 (23-24/9) mangler.
- Issues #195 og #196 er åbne, selvom deres PR'er (#197, #212) er merget. #157
  (dokumentationsdrift) blev lukket 3/9, og trin 4-spec'ens åbne punkt 11.6 (»status.md … ikke
  afstemt med GO 1-4; rettes i en docs-PR før plan 4.1a«) blev aldrig indfriet.

Konsekvens: en ny session får modstridende instrukser om, hvad der er i prod, og hvad der er næste
skridt. status.md's egen opdateringsregel (»nyt evidensafstemt snapshot ved afslutningen af en
roadmapfase«) er i praksis erstattet af tillæg.

#### F-D 83 fulde prod-kopier (5,5 GB) med levende personers data ligger lokalt
**Målt:** 718 lokale Postgres-baser (15 GB); 83 er fulde prod-kopier (≥ 60 MB), fx
`daa44_rehearsal_20260923181256_20852_f1…f30` + `_tpl` + `_verify` pr. kørsel. Rehearsal-harnesset
(`~/.private/147-44-prod/03-restore-rehearsal.sh`) kalder `createdb` fire steder og `dropdb` ingen
steder; `trap` rydder kun `PGPASSWORD`. Kun hovedbasen skal bevares ifølge runbooken. Hver kopi
indeholder de 70 levende personer og præsenslistens data, alle kan læses uden adgangskode (P1), og
hukommelsen noterede »PII i /tmp + lokale baser afventer slet-ja« allerede 3/9.

### 3.4 LOW og LOW-MEDIUM

- **S5 [LOW-MED, latent]** Reversal afviser ikke blandede batches (`schema.sql:4242-4244`): en
  `legacy_migration`-reversal afviser `person_create`/`source_evidence`/`canonical_delta`/
  `activation`, men ikke `clause_evidence` eller `interpretation_proposal`. Kun wrapperens rene
  manifester forhindrer det i dag.
- **S6 [LOW-MED]** `db-migrations-c3-identity.sql` siger i hovedet »Function bodies are the bounded
  deploy mirror of current schema.sql«, men mangler de nyere vagter
  (`PERSON_HAR_NARRATIVE_PUBLICATION_HISTORY`, `NARRATIVE_RECORD_DEDICATED_REVERSAL_REQUIRED`) og
  ville ifølge SQL-agenten rulle ni live-funktioner tilbage. Ingen runbook, CI eller doc nævner den.
  Mærk den som historisk, eller arkivér den.
- **W3** Slet-forhåndsvisningen viser nuller ved en fejlende RPC (`web/src/data/redaktionRead.ts:720ff`,
  `mobile/src/data/redaktionRead.ts:289`). Sletningen kan fortrydes via `red_fortryd_change_set`
  (`schema.sql:7639`), og de fleste personer er blokeret alligevel.
- **W2b** `fetchProveniens` (`web/src/data/public.ts:186-194`) ignorerer fejl, så læseren ser »ingen
  kilde«. Den kører inde i `safe()`, så `orThrow` ville tømme hele panelet; brug en lokal
  fejltilstand.
- **W4** `web/src/data/historik.ts:89`: `Promise.all` over to RPC'er — fejler den ene, forsvinder
  hele historikken.
- **S7** Replay kan stoppe halvvejs (`db-migrations.sql:6720-6753`: `ON CONFLICT` dækker ikke
  `UNIQUE(scheme_id,sort_order)`; 0 berørte i dag). Promotion-gaten (`schema.sql:8369-8373`) joiner
  mod reglen, ikke mod prædikatets status, så et `retired` prædikat lukker ikke for promotion.
  Katalogdrift mellem `schema.sql` og prod (parameternavn i `require_reimport_open_batch`,
  `ensure_reimport_operations(text[])` kun i migrationer, 7 funktioner defineret to gange i
  `schema.sql`). Ingen TRUNCATE-trigger på de append-only tabeller (kun ejeren kan truncate).
  `validate_reimport_name_completion` tager låse før rollegaten.
- **P8** `run_evidence_43b.py:110` sender `persona_id` (en `gen_random_uuid()`) i prompten; spec
  §9.1 siger »aldrig database-UUID'er«. Ingen afvigelsesbeslutning fundet.
- **P9** Ikke-atomisk cacheskrivning: en halvskrevet fil stopper batchen, til den fjernes i hånden
  (fail-closed; formodet ud fra kodelæsning).
- **F-E** Supabase-MCP'en er i dag koblet til et andet projekt (»BFH Metadata«, anden
  organisation). Rutinen »kør `get_advisors` efter DDL« kan ikke udføres fra en session, og en
  fremtidig session kan komme til at køre DAA-SQL mod det forkerte projekt.
- **F-F** Synlige restfejl i 1939-teksten: 5 publicerede biografier begynder midt i en sætning (var
  12 d. 20/8), og 16 tomme unioner står uændret. Begge parkeret (#162, #163).
- **Uden for perioden, men værd at vide:** `data/extracted-2026-06-18/` (591 filer, committet 18/6)
  indeholder strukturerede data (navne, datoer, ægteskaber, børn) om 47 levende personer i
  git-historikken. Repoet er privat.

### 3.5 Tjekket og fundet i orden

Prod-funktioner = sidste migration (0 forskelle, ingen ABA-mønstre blandt 80 flerdefinerede); alle
204 `SECURITY DEFINER` har `search_path`; RLS er slået til på alle `public`-tabeller; ingen
anon-kaldbar `red_*`; append-only-triggere på alle evidens- og hændelsestabeller; fail-closed læsning
i `person_daa_narrative_publication_allowed` og `public_person_bio_source_versions(_v2)`; alle 33
identity-sekvenser foran `max(id)`; `red_decide_interpretation` og promotion skriver intet i
`public`. GDPR-regel 1-3 er fail-closed. 4.4-wrapperne rydder nedarvede `PG*`-variabler, kræver
`--jeg-mener-det` og kører R med `env -i --vanilla`; ingen `assert` bruges som gate. Web: `dryRun` er
ikke hardkodet nogen steder; fortryd-fladen holder publiceringsbundne narrativer ude af den
generiske fortryd; record-editoren er fail-closed ved ukendt kontraktversion; web og mobil viser de
samme slet-preview-felter.

## 4. Udeladelser og fravalg

### 4.1 Udeladelser — uafgjort, men burde være afgjort

| # | Udeladelse | Åben siden | Konsekvens |
| --- | --- | --- | --- |
| U1 | Fakta-sektion i læserens persondetalje | 20/8 | 7.197 fakta og al faktum-evidens har intet sted at blive vist; personer uden biografi er navn + leveår |
| U2 | En vej til sletning for levende personer (G1) | 20/8 | Tombstone-beslutningen udsat på et grundlag, der er vokset fra 8 til 595 personer; art. 17 for append-only tekst ikke behandlet |
| U3 | Fase-pakke-afstemningen »prod = sum af manifester« (#156) | 3/9 | Lukket som INCOMPLETE; fase-pakke-modellens kendte svaghed er derfor ikke kompenseret |
| U4 | GO 4's restpunkter: 4 `unresolved_text` (I-133, II-35, III-129, IV-94) og 13 mulige `NOISE_RE`-linjer | 6/9 | Uændret |
| U5 | Spec 11.2 (promotion-regler ud over 5 prædikater) og 11.3 (oprettelse fra fortolkninger) | 6/9 | Bestemmer, om ~71 % af afgørelserne nogensinde kan føre til noget |

### 4.2 Fravalg med en pris — bevidst truffet, men værd at genbesøge

- Hændelser (#130), geo (#131), fuldtekstsøgning (#132) og forslagskøens godkend-flade (#128):
  mærket `uden-for-genimport` efter reglen fra 3/9 om ét aktivt mål. Prisen er, at helhedsreviewet
  30/7's fire højest rangerede værdiforslag har stået stille i otte uger.
- Medlem/forsker-tier: ikke designet; forretningsmodellen har fortsat ingen teknisk bærebjælke.

**Ikke udeladelser (tjekket):** loader-guarden `navn≠ref` fra juli er moot, så længe #152 holder de
gamle DAA-loadere frosset; `get_advisors` blev kørt ved anon-hærdningen 19-20/9; `story_kilde`-hullet
fra 30/7 er lukket (#143).

## 5. Krydstjek og afstemning (2026-09-25)

**Dom fra den uafhængige adversariale agent:** needs-attention. Retningsdommen er fair; værdidommen
er i hovedsagen rigtig, men lagde for meget vægt på brugerfladen (U1) og for lidt på, at
klausullaget næsten ikke opdeler, at ~71 % af afgørelserne ikke kan føre til noget kanonisk, og at
levende personers tekst er blevet mere permanent.

**Bekræftet af mig (reproduceret eller målt):** 1939-kobling 8 af 592 · 490 af 591 poster med én
klausul · 5 af 50 promoverbare prædikater (46 af 160 pilot-claims) · `validate_claim_value` tjekker kun
form · `segmenter_version` hårdkodet gennem fire kodeændringer · writeren afviser omsegmentering
(`schema.sql:3392`) · 46 publiceringshændelser med fuld biografitekst for levende + 59 klausuler for
47 levende hovedpersoner · 3 ikke-levende rækker `samme_som`-koblet til levende · intet
`command_execution`-tjek · `trust` på socket og TCP · app-rækken falder efter commit-dato · basen
ligger 1/8 kl. 23:06 · 89 »ufuldendte« klausuler er 76 på `;` (terminator med vilje) + 9 på `:` + 4
andet, så tallet er udeladt.

**Inferred (agentens måling, ikke reproduceret af mig):** udgående https og psql via TCP *inde i*
profilen; at de 3 `samme_som`-rækker er familiemedlemmer til fire 1939-hovedpersoner; spec-citaterne
i S4.

**Rekalibreret:** F-B blev til G1 (publiceringsblokeringen er godkendt design; hullet er levende
personers tekst uden art. 17-vej, og »145 gange« sammenlignede med den forkerte vagt) · P3's
rettelse: flag altid + udvid listen frem for »versal ⇒ ingen split« · §2.3 grund 2: kilde vises pr.
biografi, ikke pr. faktum · retning: »generaliteten ikke bevist« · »reglerne bider ikke« → »bider
nogle gange« · anon-rettelserne flyttet fra læserværdi til risikoreduktion · W2's proveniens-del og
W3 ned til LOW · P2: »irrelevant for 1939« var forkert begrundet · F-C: »ingen prod-fortrydelse« er
stadig sandt · #130-#132/#128 flyttet fra udeladelse til fravalg.

**Afvist:** to af agentens påstande kunne ikke genfindes på `origin/main` (en formulering i
roadmap.md og at status.md kalder 4.1c ukørt) og er ikke medtaget.

**Læring:** et værn, der aldrig er set fejle, er ikke et værn — P1 (profil testet på tekst, ikke
virkning), S1 (negative tests, der ikke kan fejle) og P10 (ordrethed, der kun er en visning) er samme
fejltype.

## 6. Anbefalinger — beslutningspunkter

1. **Før 4.4-GO (tidskritisk):** afgør P3/#189 for 2018-20 sammen med P4 og S4, og gør antal
   klausuler pr. post til et succeskriterium for klausullaget. Efter 4.4-GO kan klausulerne kun
   rettes med en ny writer-operation.
2. **Før næste modelkørsel:** P1 — afvis en record ved `command_execution`, skift lokal Postgres fra
   `trust` til `scram-sha-256`, bind Codex-versionen; P10 — ordret-tjek som runner-afvisning; merge
   grenen (P5).
3. **Før afgørelsesbyrden accepteres:** afgør spec 11.2/11.3, eller begræns afgørelsesarket til de 5
   promoverbare prædikater og brug stikprøve for resten. 4.5 bør måle tid pr. afgørelse (planlagt i
   pilotrapportens §8).
4. **Giv kæden et læser-udløb:** beslut U1 (fakta-sektion, evt. med kilde pr. faktum). Kræver en
   udtrykkelig beslutning, fordi reglen fra 3/9 kun åbner arbejde for det aktive mål.
5. **GDPR:** tag stilling til en art. 17-vej for append-only tekst; udeluk indtil da levende
   hovedpersoner fra append-only-writerne (G1). P2 før trin 6.
6. **Værnene i databasen:** S1 (NULL-værn + statisk CI-vagt), S2 (default privileges + bredere vagt),
   S3 (`schema.sql` på linje med migrationerne), P6 (CI-listen som mønster, ikke navneliste).
7. **Styring:** loft over planlængde (fx 400 linjer — 4.3a-4.4 viser, at det virker) og over antal
   gater pr. skridt; omskriv status.md i stedet for at tillægge; luk #195/#196.
8. **Lokale prod-kopier:** mål og karantænér frem for at slette; lad harnesset rydde sine
   hjælpebaser (F-D).
9. **Genbesøg fravalgene i §4.2** som et afgrænset værdispor ved siden af programmet.

## Hvad blev ikke undersøgt

- Live-prod: alle prod-tal er fra dumpet 23/9; `get_advisors` kunne ikke køres (F-E).
- Placement-kæden og aktiveringen i `red_apply_reimport_person_create`; serialiseringen mellem
  anker-writeren og klausul/forslag-writerne; `db-verify` 5641-5895 og dele af 6916-9471 (kun set
  som diff); en frisk schema-build mod prod (kolonner, constraints, ACL).
- Om modellens kommandoer faktisk kan nå netværket inde i profilen (kræver et modelkald).
- Mobil-jest, R-, SQL- og integrationssuiterne blev ikke kørt; web, `@daa/core` og pipeline-pytest
  blev.
- Feed-komponenter, `Folgesvend.tsx`, TreeView/TreeSearch og PresensView er kun stikprøvet.
