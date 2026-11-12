# 2018-20's fødsler og dødsfald bundet til bogens post — design

**Status:** udkast 2026-11-12. Projektejeren har valgt vej 1 (nye forslagsversioner, sammenligningen uændret) og
variant (a) (én lille DDL og én datagang, ikke dødsfald først). Valg markeret *mit valg* er mine, ikke projektejerens.
**Gren:** `docs/2018-20-dato-bindinger` fra `main` (`73684118`).
**Udløser:** projektejerens kommentar på Conrad Reventlow (392) efter 6e-1 i prod. Conrads fødsel »21. april 1644«
står med kilden »DAA 2018-20« uden postens koordinat, mens hans navn og titel er bundet til III-58 og V-1.
**Arv:** decisions 2026-09-27 pkt. 2-4 (maskinel accept ved enighed, skrivemåde står `proposed` »indtil en
normaliseringsregel er besluttet«, stikprøve på 20); 6c-2-spec'en (`2026-11-02-trin6c2-1939-bundet-til-bogen-design.md`)
§4.3 (`dato-markoer-v1`, lukket liste »præcis de to, målt« på 1939), §4.4 (kildescope, stikprøve), §4.6 (afgørelse og
binding direkte i prod); runbook `docs/runbooks/trin6c2-prod.md` ceremoni 3a og 4.
**Review-budget (B13):** 1 Codex-runde (`gpt-6.1-sol`) på spec+plan og 1 på diffen før prod; Opus afvejer hvert fund.
Projektejeren 2026-11-12: budgettet gælder ikke i dag; en ekstra Codex-tjekrunde på rettelserne er kørt (§9).

## 1. Roadmap-kobling

1. **Roadmapmål:** trin 6, færdigbevis (b): »læseren ser fakta med kildehenvisning i persondetaljen« (B11), her for
   2018-20, hvis fødsler og dødsfald i dag kun i 67 og 88 tilfælde vises med postens koordinat.
2. **Værdikædeled:** forslag og afgørelse → promotion (binding). Lukker decisions 2026-09-27 pkt. 3's åbne
   normaliseringsregel for datomarkører på 2018-20.
3. **Leverancetype:** generel. Regelversionen `dato-markoer-v2` er udgaveneutral (ingen `source_id` i koden). Den
   anvendes her på kilde 1, fordi det er der, markøren `*` findes. Ingen ny tabel og ingen ny editionsnavngiven flade.
4. **Værdi for læseren:** cirka 509 flere fødsler og dødsfald i 2018-20 viser »DAA 2018-20, s. N · <post>« i stedet
   for kun »DAA 2018-20«. Det gælder fx Conrads fødsel og død.
5. **Færdigbevis:** §7.
6. **Erstatter:** at 2018-20's datoforslag står `proposed` på ubestemt tid. Ingen parallel vej.

## 2. Målt udgangspunkt

Alle tal er fra den lokale kopi af prod `daa5ab_ddl_standin_20261111191901_slut` (prod pr. 2026-11-11). De måles
igen i prod før GO.

### 2.1 Hvorfor de ikke er bundet

Modellen skrev datomarkøren med i begge udgaver (2018-20: `* 21. april 1644`, `† 21. juli 1708`; 1939: `f. 1701`,
`† 1760`). Importens `date_raw` har ingen markør. `private.binding_value_matches` (`schema.sql:20914`) sammenligner
`lower(btrim(normalize(…)))`, så markøren gør værdierne forskellige.

For 1939 fjernede 6c-2's ceremoni 3a markøren med `red_normaliser_forslag` og regel `dato-markoer-v1` (574 versioner),
før ceremoni 4 accepterede og bandt. Den regel blev målt og afgrænset på 1939 (`f.`, `†`) og aldrig kørt på 2018-20.
Alle 2018-20's datoforslag har derfor stadig `method='model'`.

### 2.2 2018-20's datoforslag (kilde 1, aktuelle versioner)

| Prædikat | accepted | proposed | Ændres af v1 | Ændres af v2 | Bliver lig en påstand (v1) | Bliver lig en påstand (v2) |
|---|---|---|---|---|---|---|
| `person.birth` | 67 | 280 (alle `* …`) | 0 | 280 | 0 | **267** |
| `person.death` | 88 | 303 | 286 | 286 (§4.1) | **242** | **242** |

Alle 583 `proposed` har en accepteret identitet. De 509 kandidater rammer hver præcis én påstand med kilde 1, og
ingen af de 509 påstande er bundet i dag (ingen tvetydighed, ingen konflikt med en eksisterende binding).

**Rest efter v2 (74):**

| | Fødsel | Død |
|---|---|---|
| Afviger kun i tegnsætning eller mellemrum | 2 | 11 |
| Samme år, anden tekst | 11 | 34 |
| Andet år | 0 | 11 |
| Intet dødsfald med kilde 1 i databasen | 0 | 5 |

Denne inddeling er grov (min egen SQL), ikke kontrolmodellens klassifikation. Planen måler klassifikationen.

### 2.3 Hvad læseren viser i dag

`public_person_facts` over alle personer, rækker med `record_label` (»med post«) mod rækker uden:

| Kilde | Fødsel | Død | Navn | Titel | Dåb | Begravelse |
|---|---|---|---|---|---|---|
| 2018-20 | 67 / 585 | 88 / 678 | 243 / 852 | 225 / 385 | 0 / 201 | 0 / 237 |
| 1939 | 299 / 448 | 272 / 453 | 359 / 881 | 198 / 366 | 0 / 56 | 0 / 88 |

## 3. Projektejerens afgørelser (2026-11-12)

1. **Vej 1:** nye forslagsversioner med markøren fjernet, derefter maskinel accept og binding med de eksisterende
   writere. `binding_value_matches` ændres ikke.
2. **Variant (a):** én lille DDL (regel v2) og én datagang, der tager fødsler og dødsfald sammen.
3. **Mærkerne** »bundet til bogens post«/»fra den oprindelige import« er fjernet fra læseren (PR #320, decisions
   2026-11-12). Bindingen ses alene på kildeteksten.

## 4. Design

### 4.1 Regel `dato-markoer-v2` (DDL)

1. **Ny funktion** `private.normaliser_dato_markoer_v2(p_value text, p_predicate text)`: samler blanktegn som v1 og
   fjerner én indledende markør. For `person.birth` er markørerne `f.` og `*`, for `person.death` er markøren `†`.
   Derefter trimmes. Intet andet ændres.
2. **Markøren følger prædikatet, *mit valg*.** Én 2018-20-dødsværdi har formen `* og † 9999` (født og død samme år).
   v2 med `*` på død ville gøre den til `og † 9999`. Med markøren bundet til prædikatet røres den ikke og står i
   resten. v1 fjernede `f.` og `†` på begge prædikater. v2 er strengere for død (`f.` fjernes ikke) og har samme
   effekt på alle målte værdier: ingen af 2018-20's eller 1939's dødsforslag har formen `f. …`. Planen måler det i
   prod før GO.
3. **`red_normaliser_forslag`** accepterer `p_regel IN ('dato-markoer-v1','dato-markoer-v2')`. v1 og dens funktion
   er uændrede, så 1939's 574 versioner stadig kan genberegnes med deres egen regel. Signaturen er uændret, og
   `method` bliver `deterministisk-normalisering:dato-markoer-v2`.
4. **Tests** (`tests/sql/test-interpretation-normalisering.sql`): v2 på `* `, `f. `, `† `, `* og † ` (død: uændret →
   `NORMALISERING_UAENDRET`), `*` på død (uændret) og ukendt regel. Opgraderingstest fra prod-skemaet: v1-kald giver
   samme resultat før og efter.
5. **Kandidatlisterne** (`normaliser_kandidater.sql`, `normaliser_kandidat_liste.sql`) får regel og kildescope som
   parametre, ellers uændrede. 1939's liste genskabes byte-ens med v1 og kilde 3 (regression).

### 4.2 Datagang (én ceremoni efter 6c-2's form)

1. **Normalisering:** ét `red_normaliser_forslag(…, 'dato-markoer-v2')` pr. kandidat. Kandidaterne er 2018-20's
   aktuelle `proposed` fødsler og dødsfald, som v2 ændrer: forventet 280 + 286 = 566 versioner. Også resten
   normaliseres, *mit valg*: kortene i del 2 viser så bogens værdi uden markør, og en v2-version er aldrig dårligere end
   modellens. Listen er fastlåst fra øvelsen (antal + sha), og afviger den, stopper runneren.
2. **Klassifikation** med `interpretation_control_classification.sql` og kildescope 1 (`daa.control_src`) og
   **prædikatscope** `person.birth`/`person.death` (Codex fund 1): kilde 1 har andre aktive regler (fx 15 `proposed`
   titler), og deres `MATCH` må hverken accepteres eller bindes her. Scopet gælder klassifikationen, rækkeeksporten,
   planen og ceremoniens kontrol i transaktionen. Forventet `MATCH` = 509. Afviger tallet fra øvelsen, stopper runneren.
3. **Stikprøve:** 20 tilfældige blandt `MATCH`, trukket med fast seed før svarene (decisions 2026-09-27 pkt. 4).
   Projektejeren får dem som kort (persona-kortværktøjet fra 6c-2, posttekst og side med). Reglen er som i 6c-2:
   `B` er i orden, mens `D`, `V` og `P` er fejl. Én fejl stopper anvendelsen, og intet fra kontrolrunden skrives.
   Normaliseringen står og genbruges.
4. **Afgørelse:** `MATCH` → `accepted` via `red_decide_interpretation` med `decision_evidence.method =
   'machine-corroboration-v1'`, eller `-v2`, hvis planen genbruger `control_model_v2.py`. Planen afgør, om v2's
   stratificering giver mening for 2018-20's identiteter, og falder ellers tilbage til v1's ustratificerede trækning.
5. **Binding:** `red_preview_interpretation_promotions` → alle 509 `eligible` → `red_promote_interpretations_batch`.
   Målene kommer fra `interpretation_promotion_targets_scoped.sql`, som i 6c-2 §4.6. Afgørelser og bindinger
   skrives direkte i prod gennem ceremonien, ikke via overførselspakken (den antager version 1, 6c-2 §4.6 pkt. 3).
6. **Resten (74) står `proposed`** og tælles pr. klasse. Intet afgøres uden kort.

### 4.3 Del 2 (valgfri): kort over resten

Kun `REAL_DIFF` med et faktum (cirka 56) bliver kort, i højst 2 ark à ca. 30 personas. De 13, der kun afviger i
skrivemåde, står `proposed` (decisions 2026-09-27 pkt. 3), og de 5 uden et dødsfald kan ikke bindes (opret-benet).
Svarene `B`/`D`/`V`/`P` og rettelsesvejen er som i 6c-2 §4.4-4.6. Del 2 får sit eget GO, og projektejeren afgør efter
del 1, om den køres. »Vis tab før kortrunde« gælder: del 1's tal og læservisning lægges frem først.

## 5. Rækkefølge og ceremonier

Hver ceremoni følger 5c-1-formen: dump med ekstern kopi, flag og GO-kode via projektejerens shell, måling før og
efter, runner i `~/.private/5ab-overfoersel/`, og output med kun antal, nøgler og hashes.

1. **DDL** (§4.1) → deploy og `get_advisors` → mål. **Fortrydelse af DDL'en** (Codex fund 3): en restore fjerner ikke
   objekter, dumpet ikke kender. Derfor genskaber `fortryd-ddl` `red_normaliser_forslag` fra et snapshot taget lige før
   og dropper `normaliser_dato_markoer_v2`. Det er kun tilladt, så længe ingen version med v2's `method` findes. Øves.
2. **Data** (§4.2): dump → normalisering → klassifikation → stikprøvekort → svar hash-bindes → GO → afgørelser og
   bindinger i én transaktion → efterkontrol → browsertjek. Normaliseringen kan få sit eget GO før kortene, som i 6c-2's
   3a, *mit valg*. Svarene kan så tage dage uden et gammelt dump.
3. **Del 2** (valgfri, §4.3).

Forholdet til 6e-2 er uafhængigt. 6e-2 skriver publiceringshændelser og postdel, ikke fortolkninger eller bindinger.
Denne leverance udføres før 6e-2, *mit valg*, fordi den er lille og forbedrer de 2018-20-fakta, som 6e-2's
færdigbevis browsertjekker.

## 6. Mål, ikke-mål og anti-mål

**Mål:** §1 pkt. 4 og §7.

**Ikke-mål:** dåb og begravelse (ingen promotionsregel findes, og kun 52 af 311 forslag er lig en påstand: egen
backlog); at ændre `binding_value_matches`; at genkøre modellen; at rette påstande efter bogen (kun i del 2's `B`);
1939.

**Anti-mål:**
- En eksisterende gyldig binding bliver ugyldig. Kontrolleres med en nøglet liste før og efter, ikke kun antal.
- En værdi ændres ud over markøren. v2 er en lukket liste, og resten rapporteres i stedet for at regelen udvides.
- Personsiden bliver mærkbart langsommere. Fakta-kaldet (`public_person_facts`) for de 10 tungeste personer som
  `anon` må ikke komme over 1,0 s (median af 5), samme grænse som 6c-2. Desuden skal det **første kald i en frisk
  session** med `statement_timeout='3s'` lykkes for hver af dem (Codex fund 4: medianen skjuler et koldt første kald).
  Måles i øvelsen og efter apply. Over → stop og restore.

## 7. Færdigbevis

- **Læseren** (browsertjek som `anon` mod prod): Conrad (392) viser fødsel og død med »DAA 2018-20, s. N · <post>«.
  En person med en v2-normaliseret, bundet dødsdato gør det samme. En person i resten viser uændret »DAA 2018-20«.
  0 forekomster af `record-<uuid>` og `legacy-source:`.
- **Tal i prod:** rækker med `record_label` for kilde 1 stiger fra 67 til ≈ 334 for fødsel og fra 88 til ≈ 330 for død.
  De andre typer og kilde 3 er uændrede. Antallet er det, læseren viser (§2.3's måling), ikke bindingerne.
- **Kæden:** versioner (566), `MATCH` (509), stikprøve (20, 0 fejl), afgørelser (509), bindinger (509) og rest pr.
  klasse (74). Hver binding, der var gyldig før, er gyldig efter (nøglet).
- **Fart:** de 10 tungeste personers fakta-kald som `anon` ≤ 1,0 s (median af 5).
- **Status:** `status.md`'s 2018-20-kolonne for promotion og B11-rækken opdateres med dato og nye tal.

## 8. Afgjort i planen (`docs/superpowers/plans/2026-11-12-2018-20-dato-bindinger.md`)

1. `control_model_v2.py` bruges med kildescope 1 og et nyt flag `--kun-stikproeve` (arket bærer kun stikprøven;
   `REAL_DIFF`/`SKRIVEMAADE` får ingen afgørelse). Strata 0/20, medmindre målingen viser retning 2-udfald for 2018-20.
   Metoden er derfor `machine-corroboration-v2` (plan Task 4).
2. Normaliseringen får sit eget GO før kortene (`go-n`/`apply-n`, plan Task 5).
3. De ti tungeste 2018-20-personer og deres fakta-tid måles på en frisk stand-in (plan Task 0) og i prod før GO.

## 9. Codex-runde (B13, spec+plan) 2026-11-12, `gpt-6.1-sol`: NO-GO, 7 fund — afvejet

Alle 7 accepteret; rettet i spec og plan samme dag.

1. *Major:* klassifikationen og kontrolværktøjet tager alle aktive regler for kilde 1, så en tilbageværende titels
   `MATCH` kunne blive bundet → prædikatscope (§4.2 pkt. 2; plan Task 4).
2. *Major:* `_load_plan` kræver `real_diff_ids`/`skrivemaade_ids` på topniveau, så det foreslåede `udeladt_ids` ville
   knække `persona_kort.py` → topnøglerne bevares; fuld CLI-rundtur i testen (plan Task 4).
3. *Major:* ingen fortrydelse af DDL'en → `fortryd-ddl` (§5 pkt. 1; plan Task 5).
4. *Major:* medianen af 5 varme kald skjuler et koldt første kald over anons 3 s → koldt kald under 3 s (§6; plan
   Task 5).
5. *Minor:* preview afviser `proposed` → Task 0's simulering accepterer syntetisk i samme rollback.
6. *Minor:* GUC'en hedder `daa.control_src`, ikke `daa.src` (§4.2 pkt. 2).
7. *Minor:* `test-control-model-v2.sh` ligger i `tests/sql/` (plan Task 4).

Bekræftet af Codex: paritet 61 → 62; `red_decide_interpretation` kopierer derivation, metode, kørsel og
observationer korrekt; ingen læser afhænger af v1's `method`-tekst; kortværktøjet virker med kun stikprøven, når
planskemaet bevares.

**Tjekrunde 2026-11-12** (samme Codex-session, kun rettelserne): GO. Alle 7 lukket, ingen nye fund. Skærpet: `fortryd-ddl`
kræver, at ingen version i nogen kilde har v2's `method` (plan Task 5).
