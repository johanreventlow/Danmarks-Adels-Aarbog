# Analyse 25 — Generations-visning uden kendt forældre-forbindelse: den manglende epistemiske primitiv

**Dato:** 2026-07-09
**Anledning:** Brugerens observation ved genbesøg af `feat/generations-browser-v2`-worktree'et: løsningssporet (Step 1 "kun beviste kanter" + evt. Step 2 "kilde-register") bevæger sig væk fra det oprindelige ønske, fordi *"modellen ikke kan skelne mellem slægtsled hvor forbindelsen ikke er kendt, og slægtsled der måske bare ikke har en forbindelse."*
**Grundlag:** `docs/reviews/20-generations-browser-v2-logik.md` (worktree), design-spec 2026-07-05, `generations.ts`/`tree.ts` (v1 på main + v2 på branch), memory `generations-browser-v2-paused`/`generations-reparation`, `schema.sql`, `datamodel-oversigt.md`.

---

## Status (2026-07-09): IMPLEMENTERET på `feat/generations-browser-v2` (4 commits, ikke merget)

Analysen er bygget. Brugerens beslutninger (interview 2026-07-09) afgjorde tre åbne punkter — de **erstatter** §4.3(b)'s side-panel-lean og §8's åbne spørgsmål:

1. **Betydning (§8-Q, §5): BEGGE grader skelnes.** To vaerdi_tekst-grader på markeringen: `'forælder ukendt'` (forælder findes, men ukendt → "Mulige forældre") og `'ingen forbindelse angivet'` (bogen forbinder ikke opad → neutral "andre i forrige slægtled").
2. **Visningsform (§4.3b): INLINE distinkt kolonne — IKKE separat side-panel.** Ved gennemlæsning viste det sig, at det side-panel-register, §4.3(b) hældede mod, netop var det spor, der gled væk fra brugerens ønske om *inline* generations-bladring. Markeringen gør inline ærligt (gatet på markering, ikke fravær), så kandidaterne vises i selve Kolonner-træet — visuelt/semantisk distinkt (stiplet/amber, grad-ordlyd, "muligt slægtled"-tag, Kilde-footer), aldrig blandet med beviste kanter (Codex H3 respekteret via den distinkte styling, ikke via adskilt flade).
3. **Verifikation: markér én reel klynge nu** (mod review-20-fælden). Udestår kun prod-adgang (se nedenfor).

**Leveret (web+mobil, TDD, byte-identisk delt kerne):**
- Phase A: fjernet ugated fallback + activeCoord; kun beviste kanter + slægtled-labels fra faktisk koordinat.
- Phase B: `buildParentsUnknown`-resolver + `fetchParentsUnknown` + `parentsUnknownByPerson` på model/store; vokabular seedet i `db-migrations.sql`. INGEN skema-ændring (fact/assertion/citation/conclusion, red_upsert_fakta).
- Phase C: `unknownParentRing` — inline marker-gatet kandidat-kolonne (forrige slægtled, kuld-grupperet, cross-linje via samme_som-collapse uden founder-hop).
- Phase D: redaktør-authoring (markér/opdatér/fjern med grad + kilde) web+mobil.

**Udestår:** empirisk verifikation mod prod (markér én reel klynge via §6-query + redaktør-UI, se ringen rendere) — kræver brugerens prod-adgang/redaktør-login. Dual-review + /simplify + merge.

---

## 1. Problemet, præciseret

Din formulering er korrekt — og den kan skærpes. Når stamtræet mangler en forældre-kant for en person, dækker det ene DB-signal "ingen `family_member`-række" over **fire forskellige virkeligheder**:

| # | Tilstand | Eksempel | Kan modellen udtrykke det i dag? |
|---|---|---|---|
| 1 | **Bevist kant** — bogen angiver forælderen | Langt de fleste af de 922 | ✅ `family_member` (konfidens sikker/NULL) |
| 2 | **Formodet kant til en konkret person** — bogen skriver "formentlig søn af N" | Enkelttilfælde spredt i stamtavlen | ✅ `family_member` m. `konfidens='formodet'` (invariant 7) — findes, bruges bare ikke systematisk endnu |
| 3 | **Kilden angiver ingen forbindelse** — bogen placerer personen i linje + slægtled, men forbinder ham ikke opad (de ALLER-tidligste generationer; middelalder-klyngerne) | I. linjes 1.-3. slægtled m.fl. | ❌ **ingen repræsentation** |
| 4 | **Kanten står i bogen, men er ikke udtrukket** — udtræks-hul i pipelinen | Person 210 (bogen siger klart 209's søn; linket mangler i basen) | ❌ **ingen repræsentation** |

(Der findes en femte nuance — personen har måske *slet ingen* forbindelses-påstand, kun slægtsmedlemskab. I praksis er den uadskillelig fra tilstand 3 set fra kilden: bogen forbinder ikke personen opad. Nuancen kan bæres i markeringens værditekst, se §4.)

**Kernediagnosen:** Modellen er *closed-world* om forældre-kanter — fravær af en kant er ét signal, men virkeligheden er *open-world* (fravær er polysemt). v1/v2-fallback'en tolkede **alt** fravær som tilstand 3 og viste generations-kandidater — deraf person-210-fejlen og de "forkerte forslag over hele træet". Redesignets Step 1-tilbagetog (kun beviste kanter) er det modsatte yderpunkt: det tolker alt fravær som "vis intet", hvilket er *sikkert* men opgiver dit oprindelige ønske for de generationer, hvor bogen genuint ikke kan forbinde.

**Din fornemmelse er altså rigtig, og det er ikke UI-logikken der er problemet: det er at datamodellen mangler en epistemisk primitiv.** Så længe tilstand 3 og 4 er repræsentationsmæssigt identiske, vil *enhver* UI-heuristik enten vise forkerte kandidater (v1/v2) eller ingenting (Step 1). Ingen mængde frontend-arbejde kan skelne to tilstande, databasen ikke skelner.

---

## 2. Løsningen ligger i evidenslaget — "bogen angiver ingen forældre" er selv en kildepåstand

Den afgørende omvending: **at kilden IKKE angiver en forbindelse er en positiv oplysning OM kilden** — en påstand på linje med alle andre. "DAA 1939 angiver ingen forældre for Hartvig (I, 3. slægtled)" er et kildebundet, citerbart udsagn, der hører hjemme i påstand/konklusion-modellen:

- **Invariant 2** ("nye behov = nye faktatyper, ikke nye tabeller") — det er præcis en ny `faktatype`, ingen skemaændring.
- **Invariant 1** (påstande uforanderlige, konklusion ovenpå) — hvis en senere DAA-udgave eller kirkebog *beviser* forbindelsen, tilføjes den beviste kant + en ny påstand, og markeringens konklusion sættes til `'forældet'`. Historikken om at 1939-udgaven ikke kunne forbinde, bevares — det er netop "årbogens egen udvikling over tid" (datamodel-oversigt §6).
- **Interoperabilitet:** GEDCOM 7 har en dedikeret struktur til negative udsagn (`NO`-strukturen, fx "ingen kendte børn") — markeringen fladgøres altså rent ved eksport. *(antaget ud fra GEDCOM 7-kendskab; slå efter i spec'en ved implementering)*

### Read-time-kontrakten (det nye, entydige semantiske grundlag)

| Databasen siger | UI viser |
|---|---|
| Bevist kant | Bevist aner-ring (som i dag) |
| Kant m. `konfidens='formodet'` | Kanten vist med konfidens-markering (eksisterende mekanisme, invariant 7) |
| Ingen kant **+ afklaret `forældre_ukendt`-markering** | Generations-kandidater/kilde-register MÅ vises — ærligt mærket *"kilden angiver ingen forbindelse; personer i forrige slægtled:"* med proveniens (citation på markeringen) |
| Ingen kant **+ ingen markering** | **Intet spekulativt.** Ærlig dødende (Step 1-adfærd) — for dette ER et udtræks-hul indtil andet er dokumenteret |

Dermed bliver fraværet **handlingsbart** i stedet for tvetydigt: enhver ulinket person er enten markeret (kilden siger ikke mere) eller en kendt udtræks-TODO. En redaktions-dashboard-query — "personer med `slaegtled_lokal > 1`, ingen `barn`-kant, ingen markering" — bliver arbejdslisten for pipeline-opfølgning. Person-210-klassen af fejl er elimineret *ved konstruktion*, ikke ved heuristik.

---

## 3. Løsningsrum — tre måder at repræsentere tilstand 3

### Option A (anbefalet): per-person epistemisk fact — `faktatype='forældre_ukendt'`

`fact(subjekt_type='person', faktatype='forældre_ukendt')` + assertion (kildebundet til DAA-udgaven, `vaerdi_tekst` kan bære nuancen: `'ingen angivet'` / `'kun slægtsmedlemskab'` / bogens egen formulering) + citation (sidetal) + conclusion.

- **Ingen skemaændring.** `red_opret_fakta` kan skrive den i dag; kun en `vocab`-række (`scheme='faktatype', code='forældre_ukendt'`) + read-lag-fetch mangler.
- Præcis per person — gaten fyrer kun hvor markeringen står.
- Følger hele det eksisterende maskineri gratis: versionering (change_set), RLS, fortryd, evidens-visning i redaktøren.

### Option B (afvist): pladsholder-ane + formodet kant

Datamodel-oversigt §2 nævner at "en ukendt junction kan hænges på en pladsholder-ane". Det ville give graf-traversal gennem hullet (slægtskabsfinderen kunne rute igennem med vist konfidens), **men det oversætter "ukendt" til "formodet fælles forælder" — en stærkere påstand end kilden bærer.** Bogen hævder ikke at slægtled-2-personerne har én fælles far; den hævder kun at de hører til slægtled 2. Syntetiske personer forurener desuden lister/søgning/tælling og skaber en ny klasse af specialtilfælde (må pladsholderen collapses? bogmærkes? vises i registret?). Reservér pladsholder-mønsteret til de tilfælde hvor kilden *faktisk* postulerer en ukendt-men-eksisterende enkeltperson ("N.N., fader til brødrene X og Y") — det er tilstand 2 med anonym forælder, ikke tilstand 3.

### Option C (muligt supplement, ikke primær): linje-segment-fact

`fact(subjekt_type='lineage', faktatype='slægtled_forbindelser_uafklarede', vaerdi='1-3')` — matcher at bogens udsagn ofte gælder et *segment* ("de tidligste led kan ikke forbindes med sikkerhed"), færre rækker, proveniens på det niveau kilden faktisk taler. Men: upræcis pr. person (kræver interval-fortolkning ved read-time), og linje/`person_external_id`-joinet gør gaten mere skrøbelig end et direkte person-fact. **Vurdering:** start med Option A; Option C kan senere tilføjes som redaktionel *authoring-genvej* der udfoldes til per-person-markeringer (eller blot som dokumenterende linje-status — `lineage.status` findes allerede til fri tekst).

---

## 4. Hvad det betyder for det eksisterende arbejde (worktree + main)

Den konvergerede Step 1/Step 2-retning fra review 20 **består** — den får bare sit manglende fundament, så Step 2 ikke længere er en resignation men en præcis gengivelse:

1. **Step 1 uændret (byg først):** rul til kun-beviste kanter + faktiske slægtled-labels (læst fra koordinat, konsensus-regel jf. Codex-reconcilen — aldrig `activeLokal ∓ depth`-aritmetik). Slet `adjacentGen`-founder-hoppet (inert i prod, `parent_lineage_id` NULL; dobbelt-listede founders + `samme_som` dækker allerede linje-broerne), `fallbackRing`, `buildAnchorPeers`. **Rydder også v1's aner-fallback der stadig er live på main/prod** — den har person-210-problemet i produktion i dag.
2. **Nyt datalags-trin (lille):** `vocab`-række + redaktionel markering af de reelle klynger. Volumen er lille — det er de tidligste slægtled i (nogle af) de fem linjer; find kandidaterne med queryen i §6 og markér via `red_opret_fakta` med kilde-citation. *Ingen migration, ingen ny tabel.*
3. **v3 = marker-gated kandidat-visning:** genindfør kandidat-UI'et — men (a) **kun** for ankre med afklaret `forældre_ukendt`, (b) som **eksplicit separat visning** (Codex H3-rekalibrering: ikke blandet ind i den beviste stribe — Step 2's side-panel-form er fin), (c) med proveniens fra markeringens citation ("DAA 1939, s. 97: forbindelse ikke angivet"), (d) aner-retning først (det var det oprindelige behov; efterkommer-retningen kræver sin egen `børn_ukendte`-overvejelse og har patrilinearitets-fælden). Meget af v2-branchens kode (kuld-gruppering, genLabel, cap/"+N flere") kan genbruges direkte i denne indpakning.
4. **Read-lag:** model-load skal hente markerings-facts (i dag hentes kun geo-facts i `model.ts`) — én ekstra `getAll` på `fact` filtreret på `faktatype='forældre_ukendt'` + tilhørende afklarede konklusioner, projiceret til et `parentsUnknown: Set<personId>` i modellen. Husk `.order('id')` (jf. review 24 fund 5) og samme_som-kanonisering af subjekt-id.
5. **Loader-politik:** udtræks-pipelinen må **ikke** selv skrive markeringer — LLM'ens manglende udtræk ≠ kildens manglende angivelse (det er netop tilstand 4 vs. 3!). Højst: loaderen kan *foreslå* kandidater til `suggestion`-køen, redaktionen bekræfter. I PoC: ren redaktionel markering.

### Hvorfor det genopretter det oprindelige ønske

Dit ønske (memory, 2026-07-05): *"bogen kan ikke bevise hvem der er forælder til hvem — den angiver bare hvem der hører til 1./2./3. slægtled. Ønske: bladre gennem generationerne alligevel, vise forældre-barn hvor kendt, og skrive generationsnummeret."* Med markeringen kan UI'et gøre præcis dét — **dér hvor bogen faktisk siger det** — og forblive tavst hvor hullet bare er manglende udtræk. Codex' åbne spørgsmål 1 ("rammer registret idéen?") får også sit svar: registret/kandidat-ringen er den ærlige gengivelse af tilstand 3, og markeringen sikrer at den kun optræder dér.

---

## 5. Skelnen mellem "forbindelsen ikke kendt" og "måske ingen forbindelse" (din sidste pointe)

De to er *epistemisk* uadskillelige set fra kilden — bogen kan ikke sige mere end den siger. Men de kan **gradueres i markeringens indhold**, uden ny mekanik:

- `vaerdi_tekst = 'forbindelse ikke angivet'` — bogen placerer personen i slægtled N uden opadgående kant (default).
- `vaerdi_tekst = 'kun slægtsmedlemskab'` — bogen hævder alene at personen hører til slægten (fx registeropslag/præsens uden stamtavle-placering).
- Bogens egen formulering ("formentlig af samme slægt", "vistnok en broder til…") gemmes rå i assertion — og hvor den peger på en *konkret* person, er det slet ikke en markering men en `konfidens='formodet'`-kant (tilstand 2, eksisterende mekanisme).

UI'et kan vælge at vise de to værdier ens i første omgang; det vigtige er at kildens præcise udsagn er bevaret og kan differentieres senere — samme substrat-plus-overlag-filosofi som narrativ/fakta.

---

## 6. Verifikations- og arbejdsqueries (read-only)

```sql
-- Kandidater til redaktionel markering: i et slægtled > 1, ingen barn-kant, (endnu) ingen markering
SELECT pei.linje, pei.slaegtled_lokal, pei.nr, p.id, p.visning_fuldt_navn
FROM person_external_id pei
JOIN person p ON p.id = pei.person_id
WHERE pei.slaegtled_lokal > 1
  AND NOT EXISTS (SELECT 1 FROM family_member fm
                  WHERE fm.person_id = p.id
                    AND fm.rolle IN ('barn','adopteret_barn','plejebarn','stedbarn'))
  AND NOT EXISTS (SELECT 1 FROM fact f
                  WHERE f.subjekt_type='person' AND f.subjekt_id=p.id
                    AND f.faktatype='forældre_ukendt')
ORDER BY pei.linje, pei.slaegtled_lokal, pei.nr;
-- Denne liste ER arbejdskøen: hver række afgøres som enten (3) markér, eller (4) udtræks-TODO.

-- Sundhedstjek efter markering: ingen person må have BÅDE bevist barn-kant OG afklaret markering
SELECT p.id FROM person p
WHERE EXISTS (SELECT 1 FROM fact f JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id
              WHERE f.subjekt_type='person' AND f.subjekt_id=p.id
                AND f.faktatype='forældre_ukendt' AND c.status='afklaret')
  AND EXISTS (SELECT 1 FROM family_member fm WHERE fm.person_id=p.id AND fm.rolle='barn');
-- (>0 rækker = markering skal sættes 'forældet' — kandidat til trigger/verify-assert senere)
```

---

## 7. Anbefalet rækkefølge

1. **Step 1 fra review 20 bygges/merges** (proven-tree + labels; slet fallback-maskineriet på både branch og main). Uafhængigt af alt andet — det er rent oprydning + korrekte labels.
2. **Vocab + markér de reelle klynger** (query §6 → redaktionel gennemgang mod bogen → `red_opret_fakta` m. citation). Lille, afgrænset dataarbejde; giver samtidig et faktisk tal for hvor stor tilstand 3 er.
3. **v3: marker-gated kandidat-visning** (side-panel/register-form, aner først, genbrug v2-byggeklodser). Først her genåbnes UI-diskussionen — og med Codex' åbne spørgsmål 2 besvaret af dig: *skal der bladres ét slægtled ad gangen (liste) eller 2-3 generationer side om side?*
4. **Senere:** evt. `børn_ukendte` (efterkommer-retning), loader-forslag via suggestion-køen, Option C-authoring-genvej, verify-assert for §6-sundhedstjekket.

## 8. Åbne spørgsmål (kræver dit svar før v3-design)

1. **Browse-følelsen** (uændret fra pausen): (a) ét slægtled ad gangen som liste i side-panel, eller (b) 2-3 generationer side om side i træ-fladen?
2. **Markerings-granularitet i bogen:** siger DAA noget *eksplicit* om de tidligste leds uforbundethed (en indledning/note pr. linje), eller er det implicit i opsætningen? Det afgør hvor god citationen på markeringerne kan blive (side-tal vs. "fremgår af stamtavlens struktur").
3. **Skal `formodet`-kanter (tilstand 2) samtidig efterses?** Queryen i §6 vil også afsløre "formentlig søn af"-tilfælde der i dag ligger som prosa — de skal have en formodet kant, ikke en markering.
