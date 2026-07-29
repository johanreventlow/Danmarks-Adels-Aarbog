<!-- prompt-version: 2026-07-29b (omtale vs. afhugget tekst adskilt efter kalibrering) -->
<!-- Frossen, autoritativ prompt for trin ③ (fakta-udtræk). Rediger DENNE fil (ikke
     ad hoc pr. kørsel) og bump prompt-version ved ændringer, så modeller/kørsler
     kan sammenlignes uden prompt-drift. Se SKILL.md §③. -->

# Trin ③ fakta-udtræk — instruktioner (DAA stamtavle)

Arbejdsmappe: /Users/johanreventlow/TypeScript/danmarksadelsaarbog

LÆS FØRST:
- docs/daa-extraction-archetype.md (§3 fælder, §4 datoer)
- .claude/skills/daa-extract/references/extraction-schema.json (skemaet)

For HVER post i din batch-fil → ét JSON-objekt der validerer mod skemaet. Skriv ét
objekt per post til `work/extracted/<linje>-<nr_label>.json` (overskriv). Brug Write.

Postens input (fra `posts.json`): `raw_text`, `linje`, `nr`, `nr_label`,
`slaegtled`, `aegteskab_kontekst`, `kuld`.

> **`aegteskab_kontekst` er et HINT fra segmenteringen (`segment.py`), ikke facit.**
> Feltet er den nærmeste "af X ægteskab med Y:"-overskrift over posten. Kendte
> fejlkilder: (a) headings der slutter på ":-" (kolon+bindestreg) matchede før ikke
> og lod den FORRIGE heading klæbe til næste barn — rettet i `MARR_RE`; (b) for
> enkelt-gifte forældre uden egen heading kan en tidligere forælders heading "bløde"
> igennem (inert: loaderen bruger KUN feltet ved 2+ ægteskaber, og `match_barn_union`
> parkerer frem for at gætte hvis navnet ikke er blandt forælderens ægteskaber).
> Kopiér feltet VERBATIM — validér det ikke og find ikke på en mor ud fra det;
> retten mor bindes deterministisk ved load. Se `docs/reviews/boern-mor-mismatch-review-2026-07-03.md`.

## Regler
- Kopiér `linje`, `nr`, `nr_label` VERBATIM fra posten. `usikker` = postens værdi. UDLED IKKE `narrative` (den flettes deterministisk ind fra `raw_text` i trin ④).
- `date_raw` er OBLIGATORISK og VERBATIM for alle dato-fakta (fødsel/dåb/død/begravelse/floruit). Det er det vigtigste dato-felt — få det ordret rigtigt.
- `date_min`/`date_max`: **udledes nu DETERMINISTISK i trin ④ fra `date_raw`** — du MÅ udfylde dem, men de OVERSKRIVES. Brug din energi på `date_raw`, ikke på ISO-syntese. Syntetisér ALDRIG en normaliseret span i `vaerdi`.
- `koen` fra kontekst (Greve/søn→mand; Komtesse/datter→kvinde). Sæt ALTID `koen_kilde`: `"bog"` hvis teksten siger det (Datteren, hans Søn, Comtesse), `"udledt"` hvis du slutter det af fornavnet. Skøn skal kunne skelnes fra kildens udsagn.
- `navn` er KUN egennavnet. Titel, rang, gods og parenteser hører i titel-fakta og `godser` — ALDRIG i navnefeltet. Forkert: `"Kammerherre Christian Ditlev Reventlow til Grevskabet Christianssæde"`. Rigtigt: `navn="Christian Ditlev"`, titel-fakta `"Kammerherre"`, gods `"Grevskabet Christianssæde"`.
- Opret ALDRIG tredjeparts-personer (konger, paver, vidner, svigerforældre) — de nævnes kun i kontekst/tekst.

## er_omtale — BLOKERENDE, læs denne først

Nogle "poster" er ikke opslag, men **omtaler inde i løbende prosa**: bogens
oversigtsafsnit nævner personer i sætninger som *"Fader til Otto til Brunsholm
(† 1700)"*, *"hvis Sønner var a-d"*, *"B) Ditlev til Wittenberg († 1690),"*.

Sæt `er_omtale: true` på dem. **En omtale må aldrig blive til en person** — den samme
person har næsten altid sit rigtige, nummererede opslag et andet sted i bogen.

Kendetegn: personen **introduceres som led i en anden persons beskrivelse** · teksten
står i et oversigts- eller indledningsafsnit · den har **intet eget løbenummer** i
bogens nummerserie · personen har tydeligvis sit rigtige opslag et andet sted.

Dette gav **~30 spøgelsespersoner** i DAA 1939, som senere måtte slettes manuelt.

### ⚠ Forveksl IKKE en omtale med en fejlklippet post

At teksten **starter eller slutter midt i en sætning** er IKKE et kendetegn på en
omtale. Det er kendetegnet på en post hvis prosa er klippet forkert af segmenteringen
— og det rammer helt almindelige, rigtige personer:

> `"1628 i Lübeck. Gift 1° før 1609 m. Anna Pogwisch (F.: Henrik P. …"`
> `"stenske Stænder, 1856 Medlem af Rigsraadet † 4 Febr. 1873 paa Jersbek. …"`

Begge er **rigtige poster med et afhugget hoved**, ikke omtaler. Sætter du
`er_omtale: true` på dem, forsvinder et virkeligt menneske ud af korpus.

Brug i stedet `tekst_afhugget: true`. Så bliver posten flagget til re-segmentering
frem for kasseret.

**Ved tvivl mellem de to:** spørg om personen *introduceres inde i en anden persons
sætning* (→ omtale) eller om teksten bare *begynder for sent* (→ afhugget). En omtale
har ingen egen post; en afhugget post har sin egen — vi har bare ikke fået det hele
med.

## kilde_span (proveniens) — BLOKERENDE (R7)
For hvert fakta og hvert ægteskab: kopiér den mindste klausul fra `raw_text` der
indeholder ankeret (dato-token, partnernavn, godsnavn). Den SKAL være en ordret
substring af `raw_text` — `validate.py` afviser poster hvor et span ikke findes
ordret. Opfind ALDRIG spanet; typografiske apostroffer/parenteser skal matche kilden.

## Hvad er rygrad (struktureres)
- Fakta: navn, tilnavn, fødsel, dåb, død, begravelse, floruit, titel, adling, dekoration (vaerdi = HVILKEN orden, fx "R."; date_raw = datoen).
- `godser`: navn + periode_raw + sogn/kreds i `sted`.
- `begivenheder` RESTRIKTIVT: kun navngivne, DELTE historiske events (slag, kroning, mord på greve Adolph 1315). Rutine-gerninger (vidne, stadfæstede, lenshyldning, immatrikulation) er IKKE events → de bliver i narrativen.
- `boern`: nr_range [lav,høj] + antal + evt. linje. (NB: udledes også deterministisk i trin ④ fra prosaen; dit felt ignoreres, men udfyld gerne.)
- `aegteskaber`: ordinal, partner_navn (uden at oprette personen), partner_ekstern_ref, type, dato_raw/date_min/date_max/sted/skilt, kilde_span.
  - `ordinal_kilde`: `"bog"` KUN når bogen selv skriver 1°/2°/3°. Tæller du selv rækkefølgen, er det `"udledt"`. Et udledt nummer kan ikke bære en varig nøgle.
  - **Ægtefællens rygrad skal udfyldes** — hun har ingen egen post, så dette er den eneste kilde til hende: `partner_foedsel`{date_raw,sted}, `partner_daab`, `partner_doed`, `partner_koen` (+ `partner_koen_kilde`), `partner_titel`, `partner_godser`[], `partner_erhverv`[], `partner_foraeldre` (tekst fra "(F.: …)").
  - Efter DAA 1939-udtrækket havde ægtefæller **præcis ét faktum** — navnet. Ingen datoer, intet køn, ingen godser. Det er dét disse felter skal rette.
  - `partner_navn` er KUN navnet. `"Henning Pogwisch til Grünholz"` → `partner_navn="Henning Pogwisch"`, `partner_godser=["Grünholz"]`.

## VIGTIGT — embeder vs karriere
- `embeder` = KUN institutionelle embeder/grader (amtmand, kannik, provst, abbed, militær rang, hofjægermester, kammerherre, klosterprovst, gehejmeråd, landråd). Brug ÉN ren rolle (ikke "landråd i Slesvig og Holsten" → bare "landråd"; sted/detalje udelades).
- **Civile karriere-stillinger** (Project Officer, konsulent, direktør, arkivar osv.) og **uddannelse/grader** (cand.*, ph.d., student) er IKKE rygrad — lad dem blive i narrativen, udtræk dem IKKE som embeder eller fakta. (For gift-ind ægtefæller: deres erhverv/grader hører i `partner_erhverv`.)

## Model-tier
Default er den mellemste tier (Sonnet / gpt-5.6-terra). Flagger trin ④ en post,
gen-kør KUN den post med den høje tier (Opus / gpt-5.6-sol). De tætte
middelalderposter med tredjeparts-personer er hvor svagere modeller fejler.

Den laveste tier er **målt utilstrækkelig** til dette udtræk: den rammer den
genealogiske rygrad, men taber på klassifikations-nuancer (karriere vs embede) og er
flakier. Se `docs/decisions.md` → "Model-tier".

Returnér kort status (antal poster + evt. tvivl), IKKE fuld JSON.
