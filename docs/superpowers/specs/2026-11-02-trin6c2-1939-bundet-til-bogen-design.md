# Trin 6c-2: 1939-fakta bundet til bogen — design

**Status:** UDKAST 2026-11-02, til projektejerens godkendelse; builder-tjek indarbejdet, §8 pkt. 1-2 afgjort. Skrevet efter en afklaringsrunde med projektejeren
(§3); valg, der ikke er projektejerens, er markeret *mit valg*.
**Gren:** `docs/trin6c2-spec` fra `main` (`ded0404a`).
**Overordnet spec:** `docs/superpowers/specs/2026-10-29-trin6-1939-gennem-kaeden-design.md` (§3, §5 6c, §6 pkt. 1, 2,
5 og 8, §8).
**Delspec 6c-1:** `docs/superpowers/specs/2026-11-01-trin6c1-runner-og-identitet-design.md` (§4.8 retning 2).
**Review-budget (B13):** 1 Codex-runde på spec+plan (`gpt-6.1-sol`, Opus dømmer), 1 på diffen før prod
(`docs/decisions.md` 2026-11-01). 6c-3 (§3 pkt. 5) får sit eget budget.

## 1. Roadmap-kobling

1. **Roadmapmål:** trin 6, færdigbevis (a) og (b) for 1939's fakta: kontrol, afgørelse, rettelse og binding går gennem
   de samme RPC'er og writere som 2018-20's; læseren viser 1939-fakta som bundet til bogens post.
2. **Værdikædeled:** forslag → afgørelse → promotion (trin 4's anden halvdel) for 1939, plus læserens fakta-kald
   (vej B).
3. **Leverancetype:** generelle udvidelser (set-baseret bindingstjek, deterministisk version af et forslag,
   rettelsesvej med eksplicit mål, identitetsflytning gennem kort), kortværktøjet ind i repo'et og ceremonier.
   Ingen editionsnavngiven permanent overflade.
4. **Værdi:** ca. 1.000 af 1939's navne, titler, fødsler og dødsfald skifter i læseren fra »fra den oprindelige
   import« til »DAA 1939, s. N · <post>« med link til posten; bogens værdi står, hvor projektejeren har valgt den.
5. **Færdigbevis:** §7.
6. **Erstatter:** at 1939's fakta kun er bundet til importen fra august (citation uden post), og at
   `red_ret_ocr_felt` er den eneste rettelsesvej (fire felter, selvvalgt mål, spærret for 1939 af ankernøglen,
   `docs/decisions.md` linje ~2596).

## 2. Målt udgangspunkt (prod, læse-kun, kun antal, 2026-11-02)

### 2.1 1939's forslag (kilde 3, alle `proposed`)

| | Antal |
|---|---|
| forslag i alt | 2.774 |
| med aktiv assertion-regel (navn 401, titel 249, fødsel 302, død 296) | 1.248 |
| med aktiv family-regel (ægteskab 271, forælder 6, barn 4) → 6d | 281 |
| uden aktiv regel (steder 344, embede 240, gods 201, …) → bliver `proposed`, tælles | 1.245 |
| identiteter: `accepted` / `unresolved` | 560 / 1 |

Ingen aktiv regel kræver placering (`requires_principal_placement=false` for alle), så 6d blokerer ikke 6c-2.

### 2.2 Kontrolmodellens klassifikation af de 1.248 (uændret `interpretation_control_classification.sql`, kilde 3)

| | navn | titel | fødsel | død | i alt |
|---|---|---|---|---|---|
| `MATCH` | 337 | 196 | 0 | 11 | 544 |
| `SKRIVEMAADE` | 6 | 0 | 300 | 273 | 579 |
| `REAL_DIFF` | 48 | 44 | 2 | 6 | 100 |
| `NO_FACT` | 9 | 9 | 0 | 5 | 23 |
| `NO_IDENTITY` | 1 | – | – | 1 | 2 |

**Datoerne er et formatartefakt.** Formen af de 579 (cifre→9, bogstaver→a) viser, at prompten
`daa-1939-interpretation-proposal-v1` skriver markøren med (`f. 99 a. 9999`, `† 9999`), mens importens `date_raw` kun
har datoen. Med markøren (`f.`, `†`) fjernet og mellemrum samlet i forslaget:

| | fødsel | død | i alt |
|---|---|---|---|
| bliver `MATCH` | 265 | 216 | 481 |
| matcher kun, hvis importens `date_raw` også får samlet mellemrum (linjeskift midt i datoen) | 32 | 38 | 70 |
| stadig forskellige | 3 | 19 | 22 |

**Alle 100 `REAL_DIFF` har præcis ét mål, og kun kilde 3 citerer det** (ingen uden citation, ingen delt med 2018-20).
Alle er dermed rettelige efter overordnet spec §6 pkt. 2. Navne og titler: 48 af 92 har samme antal ord, men anden
ordlyd; resten er del/helhed (ét ord mere eller mindre).

### 2.3 Hvad der ikke virker i dag

1. **Ingen writer** laver en ny version af et forslag, der forbliver `proposed` med `derivation_kind='deterministic'`.
   `red_decide_interpretation` (`schema.sql:9340`) laver kun afgjorte versioner; `red_genaabn_relation_interpretation`
   (`:18976`) er relationsspecifik; `write_interpretation_proposal` (`:4978`) laver kun version 1.
2. **Rettelsesvejen** `red_ret_ocr_felt` (`:2034`) retter kun `navn`/`foedsel`/`doed`/`koen` (ikke titel), vælger
   selv målet (personens valgte påstand med citation i kilden) og ankrer på `person_external_id.record_key`, som for
   1939 kun matcher 8 poster (6c-1 §2.2).
3. **Bindingens gyldighed** (`private.assertion_binding_current`, `:19872`) kræver byte-lighed under
   `lower(btrim(normalize(...)))` mellem forslagets værdi og påstandens `vaerdi_tekst`/`date_raw`. En binding mod en
   påstand med linjeskift midt i datoen er derfor kun gyldig, hvis forslaget har samme linjeskift.
4. **Fakta-kaldet** `public.public_person_facts` (`:20045`) kalder `assertion_binding_current` pr. promotion-række,
   og hvert kald læser `interpretation_current` (~130 ms pr. kald i prod; decisions 2026-10-29). De tungeste
   personer tager i dag op til ~1,9 s mod `anon`'s 3 s. Hver ny 1939-binding lægger til.
5. **Identitetsflytning:** `private.decide_source_persona_identity` (`:9456`) kan genafgøre en accepteret identitet
   med `expected_version` (origin `human`, `evidence.basis` ∈ `web_detail`/`human_sheet`). Retning 2's identiteter
   har origin `publication_binding` og er afledt af C3-publiceringens person (`publication_persona_binding`,
   `:9719`); en flytning alene efterlader publiceringen pegende på den gamle person.

## 3. Projektejerens afgørelser (2026-11-02)

1. **Målet** er, at 1939-fakta kan ses i læseren *bundet til bogen*: klikbare, sporbare, med bogens rettede værdi.
   Adskillelsen pr. udgave (udgavevælgeren) er 6e, ikke 6c-2.
2. **`NO_FACT` venter på opret-benet.** Personer uden navnepåstand (9 navneforslag; de 13/576 fra 2026-10-31) får ingen
   ny påstand i 6c-2; de står synligt uafklarede og tælles.
3. **Fjerde svar »forkert person«.** Ud over »bogen har ret«, »databasen har ret« og »ved ikke« (overordnet spec §6
   pkt. 2) kan projektejeren svare, at personaen er koblet til den forkerte person.
4. **Kort 122** (oversigtspost B, persona for Ditlev †1690, bundet til barnebarnet Friederich Adolph †1773) rettes i
   6c-2; identiteten trækkes ikke tilbage (2026-11-02, handoff).
5. **A6b-resten skilles ud som 6c-3** efter 6c-2: 2018-20's 10 poster (kildetekst, klausuler, genkørsel, nøglet
   genbinding i én ceremoni, overordnet spec §6 pkt. 7). Begrundelsen i §6 pkt. 7 (»hvor runneren alligevel kører«)
   holder ikke længere, da runneren kørte i 6c-1, og en samlet 6c-2 ville holde 1939 ude af prod, til 2018-20's
   ceremoni også var klar. Kræver en linje i `docs/decisions.md`.

## 4. Design

### 4.1 Vej B: set-baseret bindingstjek (først, egen DDL-ceremoni)

1. `public_person_facts` afgør bindingernes gyldighed for alle personens promotion-rækker i én mængdeoperation:
   `interpretation_current` læses én gang for de berørte `interpretation_key`, ikke én gang pr. binding. Resultatet
   skal være **identisk** med i dag for enhver person (samme rækker, samme kildelinjer); `test-person-facts.sql`'s
   låsning af, at validator og læser er enige, udvides til det set-baserede tjek.
2. `assertion_binding_current` bevares som enkeltopslag (andre læsere), og begge går gennem samme udtryk, så de ikke
   kan glide fra hinanden (memory »konkurrerende definition degraderer lydløst«).
3. **Mål, *mit valg*:** fakta-kaldet som `anon` for de 10 tungeste personer (målt på promotion-rækker) er højst
   **1,0 s** i prod, median af 5 kald, både før og efter 1939's bindinger (§4.6). Stand-in-tid er ikke bevis
   (memory »stand-in-tid er ikke prod-tid«); før/efter måles i prod i ceremonien.
4. Vej B går i prod som egen ceremoni før enhver 1939-binding. Kan målet ikke nås, stopper 6c-2 før bindingerne.

### 4.2 Identitetsflytning (kort 122 og »forkert person«)

1. **Én vej** for begge: en kortafgørelse `P <person-id>` flytter personaens identitet til den angivne person;
   `P` alene sætter den `unresolved` (ingen person). Begge går gennem `decide_source_persona_identity` som nye
   versioner med `expected_version`; event-loggen bevarer den gamle identitet. **Målet skal være en række med
   personaens egen kilde** (en person med påstande citeret af `source_persona.source_id`; for 1939 kilde 3),
   håndhævet udgaveneutralt i writeren, *mit valg*: 1939's personas peger på
   kilde 3-rækken (overordnet spec §6 pkt. 8), og en flytning til en 2018-20-række ville sammenligne 1939's værdier
   med 2018-20's fakta, som 6c-2 ikke må rette. Findes ingen kilde 3-række for den rigtige person, svares `P` alene
   (opret-benet).
2. **Publiceringen skal følge med.** For identiteter med origin `publication_binding` skal C3-publiceringens person og
   identiteten pege på samme person efter flytningen, eller uoverensstemmelsen skal være synlig og blokere promotion
   af personaens forslag. Hvordan (ny publiceringsversion, eller en markering) er byggerens valg (§8); tavs
   uoverensstemmelse er ikke tilladt.
3. **Kort 122 køres før kontrollen** (§5 trin 2), så dens forslag klassificeres mod den rigtige person. Målt
   2026-11-02 (prod, læse-kun): der findes præcis én kilde 3-række med navnet Ditlev og en kilde 3-citeret død med
   1690 (person 1054); én anden persona har allerede identitet på den. Projektejeren bekræfter målet med
   person-id i afgørelsen for kort 122; to personas på samme person (oversigtspost + egen post) er tilladt.
4. »Forkert person« på et kort fryser **alle** personaens forslag i den kontrolrunde: ingen af dem bindes eller
   rettes. **Opfølgningsrunde, *mit valg*:** er der identiteter flyttet med `P <id>`, køres én lille kontrolrunde
   mere i 6c-2 med kun de flyttede personas (samme værktøj, stikprøve kun hvis > 20 automatiske). `P` alene giver
   ingen opfølgning; personaen står `unresolved` og tælles.

### 4.3 Deterministisk version af datoforslag

1. **Ny udgaveneutral writer** laver version n+1 af et `proposed` forslag med `status='proposed'`,
   `derivation_kind='deterministic'`, `supersedes_id` = version n, samme `source_id`/`interpretation_key`, nyt
   `extraction_run_id` og observationslinks kopieret (som `red_decide_interpretation`). Den gamle version bevares.
2. **Normaliseringen er en lukket liste, *mit valg*:** værdien får fjernet én indledende markør fra listen
   `f.`, `†` (præcis de to, målt) med efterfølgende mellemrum, og mellemrum (inkl. linjeskift) samles til ét og
   trimmes. Intet andet ændres. Reglen versioneres (navn + version i `decision_evidence`) og anvendes kun på
   `person.birth`/`person.death`.
3. Det, der er `SKRIVEMAADE` efter normaliseringen, rapporteres med antal; reglen udvides ikke for at få tallet ned.
4. Årsagen opstrøms (prompten skriver markøren) noteres som punkt til næste promptversion; **ingen genkørsel** af
   modellen i 6c-2.

### 4.4 Kontrol og kort

1. Klassifikationen kører uændret (`interpretation_control_classification.sql`) efter §4.2 pkt. 3 og §4.3, afgrænset
   til kilde 3.
2. **Automatisk:** `MATCH` accepteres og bindes (kontrolmodellen B8, overordnet spec §6 pkt. 1).
3. **Kort til projektejeren:** alle `REAL_DIFF`; dato-`SKRIVEMAADE`, der er tilbage efter §4.3 (forventet ~22),
   *mit valg* — de er få og ligner reelle forskelle; og navne-`SKRIVEMAADE` (6). Plus en **blind stikprøve på 20**
   blandt de automatiske `MATCH`, **stratificeret**, projektejeren 2026-11-02 (valg b): 10 trækkes blandt personas,
   hvis identitet kom fra retning 2 uden generatorens bekræftelse (udfald `svag` eller `ingen_kandidat`, også fra
   `excluded` poster), 10 blandt resten.
   **Stikprøvens regel, *mit valg*:** på et stikprøvefelt er `B` og `D` i orden (bogen og databasen siger det samme
   som forslaget); `V` og `P` er fejl. Én fejl stopper anvendelsen: ingen afgørelser, rettelser eller bindinger fra
   denne kontrolrunde skrives; årsagen findes, og en ny kontrolrunde med ny stikprøve og nyt GO køres. Ingen
   udvidelse til kort på alle `MATCH`.
4. **Højst 70 datoer med linjeskift i importen** (§2.2; øvre grænse, afgrænsningen nedenfor kan gøre tallet mindre), projektejeren 2026-11-02 (valg c): 1939's egen påstand får en
   deterministisk transskriptionsrettelse — mellemrum (inkl. linjeskift) i `date_raw` samles til ét og trimmes;
   intet andet ændres. Afgrænsning: kun påstande, der er det eneste mål for et 1939-datoforslag, hvis version fra §4.3
   bliver lig påstanden efter rettelsen; kun påstande, som alene forslagets egen kilde citerer (for 1939 kilde 3;
   udgaveneutralt håndhævet, ikke `source_id=3` i koden); ingen eksisterende gyldig binding
   må blive ugyldig. Originalen i `import_korrektion` og `change_event` (B12-formen) med reglens navn og version.
   Ingen kort; listen (påstands-id'er) er en del af GO-pakken. Strukturerede datoværdier (`date_min`/`date_max`)
   genberegnes ikke, da kun mellemrum ændres; det verificeres.
5. **`NO_FACT`, `NO_IDENTITY`, `AMBIGUOUS`** og forslag uden aktiv regel bliver `proposed` og tælles.
6. **Kortene grupperes pr. persona**, *mit valg* (følger af §3 pkt. 3): navn, titel, fødsel og død for samme persona
   står samlet, med posttekst, side og familie, som C's kortværktøj. Højst ~30 personas pr. ark.
7. **Svar pr. felt:** `B` (bogen har ret), `D` (databasen har ret), `V` (ved ikke). **Svar pr. persona:** `P`
   (forkert person) eller `P <person-id>`; det overtrumfer feltsvarene. Svarreglerne står i kortets hjælpetekst; HTML
   viser aldrig maskinens klasse eller stikprøvemarkering. Kendt svækkelse: med kort pr. persona kan en persona, hvor
   alle felter stemmer, genkendes som stikprøve; blindheden er svagere end i C's identitetskort og accepteres.
8. **Kortværktøjet ind i repo'et** under `.claude/skills/daa-extract/scripts/` (i dag `~/.private/5ab-overfoersel/
   28-c-kort.sh` + `c-kort/`), generaliseret fra identitetskort til persona-kort med faktafelter. Round-trip-test
   (svarfil → tokenark → hash) med **syntetiske** fixtures; rigtige ark bliver i `~/.private`.
9. Godkendelsen hash-bindes som i 6c-1 (arkenes sha i GO).

### 4.5 Rettelse (»bogen har ret«)

1. **Udgaveneutral rettelsesvej** med eksplicit mål, *mit valg* om form overladt til bygger (udvid `red_ret_ocr_felt`
   eller ny RPC), men med kontrakten fra overordnet spec §6 pkt. 2:
   - målet er ét versionsbundet påstands-id fra kortet med forventet konklusion og citationsmængde, verificeret i
     skrive-transaktionen (afvis ved drift);
   - målet må kun være citeret af kilde 3 (alle 100 er det i dag, §2.2);
   - dækker faktatyperne med aktive assertion-regler: navn, titel, fødsel, død (`byname` med);
   - transskriptionsrettelse (B12): påstanden beholder sit id; originalen gemmes i `import_korrektion` og
     `change_event`;
   - ingen tavse tab: en eksisterende gyldig binding på målet, der ville blive ugyldig, afviser rettelsen.
2. **Ny værdi = forslagets værdi** (efter §4.3), *mit valg*, så bindingen er gyldig fra starten. Er bogens værdi en
   tredje, svarer projektejeren `V` med en note; der skrives ingen fri værdi i 6c-2.
3. For datoer genberegnes `date_min`/`date_max`/kvalifikator fra den nye `date_raw` med den eksisterende
   dato-parser; ændringer i strukturerede værdier måles og rapporteres for sig.
4. Rettelsen sker **før** bindingen i samme ceremoni (overordnet spec §6 pkt. 2).

### 4.6 Afgørelse og binding

1. Afgørelser via `red_decide_interpretation` (`:9340`): `MATCH` og `B` → `accepted`; `D` → `rejected` med grunden
   `database_har_ret` i evidensen (uenigheden noteret; som 2018-20's `R` i `interpretation_decision_sheet.py`, så
   trin 4's semantik bevares); `V` og `P` → `unresolved` med grund.
2. Bindinger via `red_preview_interpretations_promotions` / `red_promote_interpretations_batch` (`:10855`, `:10866`),
   mål fra `interpretation_promotion_targets_scoped.sql` med `daa.transfer_scope` sat til de accepterede nøgler.
3. Overførselspakken (`transfer_pack.py`, docstring »for 2018-20«, parameteriseret med `daa.src`) bruges med kilde 3
   eller generaliseres; den får ikke et 1939-navn.
4. Efter bindingen: vej B's mål (§4.1 pkt. 3) genmåles i prod.

## 5. Rækkefølge og ceremonier

Hver ceremoni med 5c-1-formen (B2): dump med ekstern kopi (B1), flag + GO-kode via projektejerens shell, måling før
og efter. Rækkefølgen er bindende; byggeren kan samle trin i færre GO'er, hvis rækkefølgen bevares.

1. **Vej B** (DDL) → mål i prod (§4.1).
2. **DDL for 6c-2's writere** (version-writer, rettelsesvej inkl. linjeskift-rettelsen, publiceringens følge ved identitetsflytning) og
   **kort 122's identitetsflytning**.
3. **Datoversionerne** (§4.3) og **linjeskift-rettelserne** (§4.4 pkt. 4) skrives.
4. **Kontrol:** klassifikation, kortark (lokal HTML), stikprøve; projektejerens svar flettes og hash-bindes.
5. **Anvend:** identitetsflytninger fra kortene → rettelser → afgørelser → bindinger → genmåling af vej B.
6. **Opfølgningsrunde** for personas flyttet med `P <id>` (§4.2 pkt. 4): trin 4-5 igen for kun dem; springes over ved 0.

## 6. Mål, ikke-mål og anti-mål

**Mål:** §1 pkt. 4; §7.

**Ikke-mål:** udgavevælgeren og fakta pr. udgave (6e); familierelationer og placement (6d); nye påstande, personer
eller familier (opret-benet), herunder `NO_FACT` og oversigtsposterne »A) …/B) …« med flere generationer;
nye promotionsregler (steder, embeder, godser); genkørsel af modellen; A6b-resten (6c-3); at rette 1939 efter
2018-20.

**Anti-mål:**
- 1939 ændrer det, læseren ser som 2018-20's viden (rettelser kun på påstande, som kun kilde 3 citerer).
- En rettelse eller identitetsflytning fjerner en binding uden at nogen ser det.
- »Bogen har ret« retter en forkert persons værdi (derfor »forkert person« pr. persona og grupperede kort).
- Personsiden bliver langsommere end i dag eller nærmer sig `anon`'s grænse.
- Mere end ~5 ark à ~30 personas.

## 7. Færdigbevis

- **(a) Samme operationer:** tjekliste — klassifikation, afgørelse, rettelse, identitet og promotion gik gennem
  udgaveneutrale RPC'er og writere; ingen ny editionsnavngiven permanent overflade.
- **(b) Læseren** (browsertjek som `anon` mod prod):
  - en 1939-person uden 2018-20-modpart viser bundne 1939-fakta med »DAA 1939, s. N · <post>« og link;
  - en rettet værdi (»bogen har ret«) viser bogens værdi og er bundet;
  - kort 122's persona viser Ditlevs 1939-fakta på Ditlev, ikke på barnebarnet;
  - fakta-kaldet for de 10 tungeste personer ≤ 1,0 s (median af 5) som `anon`.
- **Tal i prod:** forslag pr. klasse før og efter §4.3; afgørelser (maskine/menneske, pr. svar); rettelser;
  identitetsflytninger; bindinger; uafklarede pr. grund. Hver binding, der var gyldig før en ceremoni, er gyldig
  efter (nøglet liste, ikke kun antal).
- **Status:** `status.md`'s 1939-kolonne for »Forslag og afgørelse« og promotion hæves med dato.

## 8. Afgjort i spec-runden og overladt til byggeren

1. **De 70 datoer med linjeskift i importen:** (c), projektejeren 2026-11-02 — deterministisk transskriptionsrettelse
   (§4.4 pkt. 4).
2. **Retning 2's ubekræftede identiteter:** (b), projektejeren 2026-11-02 — behandles som alle andre, men stikprøven
   stratificeres (§4.4 pkt. 3).
3. **Overladt til byggeren:** rettelsesvejens form (§4.5 pkt. 1); publiceringens følge ved identitetsflytning (§4.2
   pkt. 2); vej B's tekniske form; antal GO'er; om `transfer_pack.py` generaliseres eller kaldes med kilde 3; om
   versionswriteren kun rører de forslag, normaliseringen ændrer.
