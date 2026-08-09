# Spec: tekstflade til grænsekontrollen (1939)

**Dato:** 2026-08-09 · **Branch:** `feat/evidensbaseret-genimport` · **Status:** kontrakt, klar til implementering

Kort kontrakt, ikke en trin-for-trin-plan. Det der står her, er det en implementering
ikke må gætte: markør-grammatikken, byte-gaten og eksportformatet. Resten er
almindelig implementering efter husets vaner.

---

## 1. Hvorfor

Fase 1's grænseflade (`make_boundary_review_1939.py`) viser 446 skæringer som
adskilte kasser. Den besvarer "er *denne* skæring rigtig?" — men fase 1's egentlige
fund var et andet: **dækningen mangler.** Verificeret mod artefaktet
`menneskeark-graenser-v8.html` (2026-08-09):

| Størrelse | Værdi |
|---|---|
| Calamari-tekst | 186.655 tegn (189.671 bytes) · 3.939 linjer · 86 `### PAGE nnnn ###`-linjer |
| Accepterede spænd | 445 (352 menneskeforankrede + 93 automatiske) |
| Grænser | 446 · 248 med mindst ét signal |
| Signal om forskubbet skæring | 12 (`mangler_eget_hoved` 10 + `slugt_hoved` 2) |
| Øvrige signaler | `laengdeafvigelse` 190 · `nummerspring` 80 · `hoved_i_raa_ocr` 5 |
| Dækket tekst | 140.640 tegn = **75,3 %** |
| Ejerløst | 46.015 tegn — **45.757 i 97 huller med rigtig tekst**, resten 258 enkelt-linjeskift |
| Største hul | 8.996 tegn |
| Poster uden spænd | 101 |

**Hullerne er få og store, ikke mange og små.** 355 grænser har et hul, men 258 af
dem er blot linjeskiftet mellem to poster. Det reelle dækningsproblem sidder i
**97 steder**. To af dem er dokumentets kanter (868 og 6.330 tegn) — de er lige
så meget ejerløs tekst som resten, og må ikke falde ud fordi de mangler en nabo.

Et hul er praktisk talt usynligt i en kasse-for-kasse-flade: man ser kun skæringer
mellem spænd der allerede findes. I én sammenhængende tekst er hullet fysisk
til stede.

## 2. Hvad fladen er

Én HTML-fil, `file://`-lokal, uden netværk. Hele Calamari-teksten i én
`<textarea>`. Skæringer står som markørlinjer i teksten. Brugeren scroller
igennem, sletter forkerte markører, sætter manglende. Browserens egen søgning
(Cmd+F) er navigationen.

## 3. Brugerens beslutninger (må ikke omstødes uden at spørge)

1. **Markøren siger kun "her klippes"** — ingen post-identitet. Ejerskab afgøres
   i en senere, separat runde 2.
2. **Tavshed = godkendt.** En urørt markør er en accepteret skæring. Der findes
   ingen per-grænse-dom og intet begrundelsesfelt. Eksporten registrerer i stedet
   *ændringen* i forhold til det forudsatte sæt.
3. **Ægte tekstboks**, ren tekst, ingen farvelægning. Alle signaler er in-band.
4. **Gæt inde i huller er forslag**, ikke skæringer — de tæller kun hvis brugeren
   selv fjerner ordet `FORSLAG?`.

## 4. Markør-grammatik

**Kildeteksten bruger allerede `###`.** Derfor gælder en skarp adskillelse:

> **Alt der begynder med `===` er fladens eget. Alt med `###` er bogens og skal
> stå urørt.**

Fladens markører — hver på sin egen linje, uden indrykning:

| Markør | Betydning |
|---|---|
| `=== GRÆNSESKÆRING ===` | accepteret skæring |
| `=== GRÆNSESKÆRING · SIGNAL mangler_eget_hoved ===` | skæring med signal (signalnavne kommasepareret, kun de risikobærende — ikke `laengdeafvigelse` alene) |
| `=== FORSLAG? SKÆRING ===` | gæt inde i et hul; tæller kun hvis `FORSLAG? ` fjernes, så linjen bliver `=== SKÆRING ===` |
| `=== SKÆRING ===` | godkendt forslag, eller en skæring brugeren selv har skrevet |
| `=== EJERLØS TEKST · N tegn ===` | begyndelsen af et hul uden ejer |
| `=== PDF-SIDE n ===` | indsat umiddelbart efter kildens `### PAGE nnnn ###`, oversat via `CALAMARI_R6_TO_PDF_V1` |

Inline-tags (må stå midt i en linje):

| Tag | Betydning |
|---|---|
| `[[OCR: Rcventlow \| burde stå Reventlow]]` | OCR-note, knyttet til stedet. **Venstre side er den rå tekst uden nøgleord**; kun højre side bærer ordene `burde stå`. Skriver man "der står" på venstre side, ender nøgleordet inde i værdien |
| `[[UDELAD]] … [[/UDELAD]]` | tekst der ikke hører til nogen post (overskrifter, kolumnetitler). Betyder **ikke** "slet fra kilden" |

`[[UDELAD]]` og `[[/UDELAD]]` må stå klistret til teksten **eller alene på hver sin
linje** — overskrifter er deres egne linjer, så det er den naturlige skrivemåde. En
linje der kun består af et udelad-tag fjernes med sit linjeskift, som markørlinjerne.
Alle fire kombinationer skal give **samme `char_from`/`char_to`** for samme tekststykke;
ellers ville skrivemåden ændre betydningen. Målt: alle fire giver 43–89 på samme afsnit.

Begge tags er noteringer, ikke tekstændringer: de holder byte-gaten grøn og eksporteres
med kildekoordinater. Syntaksen kan ikke gættes, så fladen skal vise den på skærmen
(uden for tekstboksen — en nøgle inde i teksten ville forurene indholdet).

Ukendte `===`-linjer og uparrede `[[…]]` er en **fejl**, ikke stiltiende accept:
eksporten afvises med linjenummer.

## 5. Byte-gaten (ikke til forhandling)

Evidensmodellen hviler på at Calamari-teksten er uforanderlig: 445 accepterede
spænd peger på eksakte tegnintervaller i netop denne fil, og påstande overskrives
aldrig (invariant 1). Én indsat karakter forskyder alt efter sig.

**Regel:** fjern alle linjer der matcher fladens markør-mønstre *eksakt*, fjern
inline-tags, og sammenlign resten **byte for byte** med kildeteksten. Ikke
`sha256` alene — der skal også kunne peges på hvor uenigheden er.

- Strip-mønstrene er **eksakte og navngivne**, aldrig et generisk `^===`-catch-all
  og under ingen omstændigheder `^###`. Kildens `### PAGE nnnn ###` skal overleve
  strip'et; sletter brugeren en, skal gaten fange det.
- Gaten kører **løbende** (debounced, fx 300 ms), ikke kun ved eksport. En
  statuslinje viser `bogteksten er urørt` / `bogteksten er ændret ved linje N`.
  Fire timers arbejde må ikke kunne kasseres til sidst.
- Funktionen **"gendan bogteksten, behold mine markører"** skal findes: den
  genskaber kildeteksten og genindsætter markørerne på deres nærmeste gyldige
  position, eller nægter og siger hvorfor.
- Eksport med brudt gate er **umulig**, ikke frarådet.

## 6. Forudsat indhold ved generering

Alt genereres deterministisk. Ingen model involveret.

- 446 `=== GRÆNSESKÆRING ===` ved grænsepositionerne fra
  `build_boundary_view_model` (`before.char_to` / `after.char_from`).
- De 12 forskubbet-skærings-signaler får signalnavn på linjen.
- 97 `=== EJERLØS TEKST · N tegn ===` ved begyndelsen af hvert hul der indeholder
  **rigtig tekst**. Et hul der kun er whitespace får intet banner — det er
  typografi, ikke et dækningsproblem, og 258 falske bannere ville drukne signalet
  i brugerens `Cmd+F`-navigation. Et hul registreres på `gap`-koordinaterne alene:
  fraværet af en nabo (dokumentets kanter) må aldrig få hullet til at forsvinde.
- `=== FORSLAG? SKÆRING ===` inde i huller, hvor en linje matcher det trykte
  nummermønster `_PRINTED_MARKER_RE` fra `rendition_occurrences_1939.py`
  (`^\s*\??\s*(\d{1,4}[a-z]?)\.\s+\S`). Ingen anden gætte-kilde.
- 86 `=== PDF-SIDE n ===` efter kildens egne sidelinjer.

## 7. Eksportformat

Filnavn: `1939-graenseflade.json`. Indhold:

```
schema_version, source (samme hash-blok som fase 1: baseline/calamari/raw/pdf sha256,
                        edition, profile_version),
exported_at,
skaeringer:        [{char_offset, oprindelse: forudsat|forslag_godkendt|bruger}],
aendringsregnskab: {forudsat: 446, beholdt, slettet, tilfoejet,
                    forslag_forudsat, forslag_godkendt, forslag_bortfaldet},
slettede:          [{char_offset, var: GRÆNSESKÆRING|FORSLAG}],
ocr_noter:         [{char_offset, staar, burde_staa}],
udeladelser:       [{char_from, char_to}]
```

**Den redigerede tekst eksporteres ikke.** Kildeteksten er uforanderlig; kun
positioner og noter er nye. Positioner er tegnkoordinater i *kildeteksten*, ikke
i den markerede visning — omregningen er implementeringens ansvar.

Gen-indlæsning: `--markeringer <eksport>` genskaber fladen. Indlejrede markeringer
lægges ind **før** `localStorage` (fase 1's lære: `localStorage` hænger pr.
`file://`-sti, så en ny fil ellers taber arbejdet).

## 8. Filer

| Fil | Rolle |
|---|---|
| `.claude/skills/daa-extract/scripts/make_boundary_text_1939.py` | **ny** — CLI, hash-validering, tekstkomposition, HTML-udskrivning |
| `.claude/skills/daa-extract/scripts/boundary_text_1939_ui.js` | **ny** — UI-modul (gate, autogem, eksport) |
| `.claude/skills/daa-extract/scripts/test_make_boundary_text_1939.py` | **ny** — pytest |
| `review_ui_shared.js` | genbruges (`downloadJson`, `readStoredDraft`, `writeStoredDraft`) |
| `boundary_spans_1939.py`, `boundary_signals_1939.py` | genbruges — spænd og signaler beregnes ikke forfra |
| `make_boundary_review_1939.py` | **røres ikke.** Fase 1's flade bevares |

CLI, samme argumentnavne som fase 1 plus `--markeringer`:

```
python3 .claude/skills/daa-extract/scripts/make_boundary_text_1939.py \
  --baseline      $W/clean_1939_v2.json \
  --queue-manifest $P/review-queue-manifest-v2-run-e.json \
  --source-manifest $P/review-queue-manifest-v2-run-e.json \
  --calamari      $W/full_ocr_calamari_r6_clean.txt \
  --raw           $W/raw.txt \
  --anchored      $P/human-anchored-candidates-v4-faerdig.json \
  --out           $P/graenseflade-v1.html
```

`$W = work_1939_stamtavle`, `$P = work/task19-1939-pilot`. `--out` må ikke
overskrive en eksisterende fil. Hash-validering mod source-manifestet som i fase 1.

## 9. Afgrænsning

Fladen producerer et **skæringssæt**, ikke en materialisering. Grænsen fra
`docs/decisions.md` 2026-08-08 står uændret: en grænserettelse erstatter accepteret
evidens, og det kræver en navngiven, autoriseret afløsningsoperation med eksplicit
invalideringsgraf. Den bygges ikke her. Resultatet er review-/fil-GO — ingen
database, ingen loader, ingen deploy. Runde 2 (hvem ejer hvilket stykke) er en
separat opgave.

`work/` er gitignoreret og indeholder PII: artefakter må aldrig committes eller
sendes til en model.

## 9b. Sidevisning med fremskridt (tilføjet 2026-08-09 efter brugerens ønske)

4.630 linjer i én køre er for meget at forholde sig til. Fladen viser derfor **én
bogside ad gangen**, med fremskridt og en tæller over manglende sider — samme
navigationsform som menneskearket.

**Sideenheden er bogens egen.** Kildeteksten har 86 `### PAGE nnnn ###`-linjer; en side
løber fra sin `### PAGE`-linje til lige før den næste. Der opfindes ingen sideinddeling.

**Kvittering pr. side.** Knappen "Færdig med siden" markerer siden gennemgået og går
til næste. Brugeren valgte tavshed = godkendt for de enkelte skæringer, så kvitteringen
er det eneste sted, hvor fladen ved, at et stykke arbejde er *set*. Uden den er
"antal manglende sider" et gæt. 86 klik for hele bogen — ikke 446.

En side kan **ikke** kvitteres, mens dens gate er brudt: en ukendt markør eller en ændret
bogtekst skal rettes først. Ellers ville kvitteringen påstå mere, end den ved.

**Byte-gaten dækker fortsat hele dokumentet**, ikke kun den synlige side. Teksten samles
af alle sider — redigerede som urørte — og sammenlignes med kilden som hidtil. Ellers
kunne en side, man ikke kigger på, drive fra kilden i stilhed. Fejlmeldingen angiver
**både sidetal og linje inde på den side**, fordi et linjenummer i hele dokumentet er
ubrugeligt, når man kun ser én side.

**Markører på en sidegrænse tilhører præcis én side.** En markør, hvis position falder
sammen med en sides begyndelse, hører til den side, der **begynder** der, og vises øverst
på den. Reglen skal testes: en markør der optræder på to sider, ville tælles to gange i
ændringsregnskabet, og en der falder mellem to sider, ville forsvinde.

**Sidelisten erstatter `Cmd+F`.** Browserens søgning når kun den synlige side, så
navigationen flytter til en liste over de 86 sider, hver med sin status (gennemgået /
mangler) og hvad der venter på den: antal ejerløs-bannere, forslag og signal-markører.
Ellers ville sideopdelingen skjule netop det, fladen findes for at gøre synligt.

**Eksporten får sidernes tilstand:** `sider: {i_alt, gennemgaaet: [<pdf-side>, …]}`.
Et importeret sæt uden feltet betyder "ingen sider gennemgået" — det må ikke fejle.
Alt øvrigt i eksporten er uændret; sidevisningen ændrer ikke, hvad en markør betyder.

## 10. Succeskriterier

1. Byte-gaten fanger én indsat karakter et vilkårligt sted i teksten og peger på
   linjen. Mutationstestet: gaten skal fejle når en test-mutation ændrer kildetekst.
2. Gaten fanger sletning af en kilde-`### PAGE nnnn ###`-linje.
3. Eksport → gen-indlæsning giver samme flade (round-trip, byte-sammenlignet).
4. Ændringsregnskabet summer: `beholdt + slettet = 446`, forslagstallene summer.
5. **Verificeret i en ægte browser med reelle data** — ikke jsdom. Fase 1 kostede
   fire fejl som kun en rigtig browser fandt. Playwright + Chromium er installeret
   (`web/`, v1.61). Verificér mindst: fladen renderer, teksten er komplet,
   gate-statuslinjen reagerer på en indsat karakter, eksportknappen udløser en
   download med det rigtige filnavn og gyldig JSON.
6. Ydelse: 190.000 tegn i én `<textarea>` scroller og skriver uden hak; autogem
   er debounced.
7. Scriptblokken i den genererede HTML parser (`node --check`) — samme testværn
   som fase 1, hvor generatoren engang skrev `";\n"` og gav en blank side.
