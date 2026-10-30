# Hvad en ny udgave koster — erfaringer fra 1939 gennem den fælles kæde

Levende note, der skrives efter hvert delskridt i trin 6 (projektejerens ønske 2026-10-30). Formålet er at give
beslutningspunktet efter trin 6 (`docs/decisions.md` 2026-10-28; roadmap trin 7a/7b) et konkret grundlag for, hvad
det koster at føre en ny årbogsudgave igennem kæden. Det er **ikke** en opskrift eller et værktøj. Skalering
planlægges ikke før beslutningspunktet. Målarkitekturens krav står uændret: kun profil, kontrolleret vokabular og
dokumenterede mappingregler må ændres (`teknisk-maalarkitektur.md`, »Generalisering er først bevist, når …«).

Hvert afsnit sorterer erfaringerne i tre bunker:

- **Målt:** hvad der skulle måles på udgavens tekst, før der kunne besluttes noget.
- **Indstilling:** hvad der blev løst i profilen (data). Det skal gentages for hver ny udgave.
- **Ny fælles kode:** hvad profilen ikke kunne udtrykke. Mekanismen er generel og kan genbruges, men en ny udgave med
  en ny slags afvigelse vil koste det samme igen.

Sidst i noten: **Faste omkostninger pr. udgave** og **Faldgruber**.

## 6a — klausuler, helpost-regel og kildetekst-revision (2026-10-29/30)

Spec: `docs/superpowers/specs/2026-10-29-trin6a-klausuler-og-kildetekst-revision-design.md`. DB-delen er merget
(#281); scripts-delen er i PR 2.

### Målt

- **Tør kørsel af segmenteringen** på de 584 helposter med 2018-20's regler (kun antal; spec §2.2): klausuler pr.
  post, brud på mellemrumsreglen, ukendte forkortelser, sideombrud og orddelinger.
  - Granulariteten svarede til 2018-20's (ca. 1,7 klausuler pr. post). Bogens sætningsmønster var altså ikke
    problemet.
  - 77 poster krydser et sideskift; 48 af ombruddene står midt i en sætning. 641 orddelinger ved linjeskift.
- **Ukendte forkortelser:** tokentælling efter reglerne. 15 forkortelser med mindst 3 forekomster blev taget ind;
  `unknown_abbreviation` faldt fra 324 til 62 klausuler, og 3 forkerte opdelinger forsvandt (1028 → 1025 klausuler).
  Ordenstal, initialer, bynavne og tvetydige enkeltbogstaver blev holdt ude ved skøn.
- **Records og forekomster:** 592 records, 584 med en helpost og 8 uden. En record kan have flere forekomster, så
  det skulle afgøres, hvilken der er personens egen post.
- **Renditionens fingeraftryk** (`raw_text_sha256`) blev bekræftet mod en eksport fra prod-kopien.

### Indstilling (profil)

- `clause_rules` (`clause-rules-1939-v1`): terminatorer inkl. `".\n"` og `";\n"`, `gap_charset` med linjeskift,
  forkortelseslisten, mønster for sidemarkøren `### PAGE n ###` og for mulig sidestøj.
- `text_form` = `raw` (B7): 1939 bruges som den står i OCR-renditionen; 2018-20 renses for sidehoveder
  (`folded_projection@…`). Formen erklæres pr. udgave, og writeren tjekker den.
- `helpost_observation_kind` = `person`.
- `rendition_metadata` (udgave, rendition-art) og `expected_counts` (584 klausul-evidenser).

### Ny fælles kode

- **Sidemarkør og mulig sidestøj som valgfri regler** i segmenteringen (`clause_segment.py`). Uden reglerne er
  2018-20's resultat byte-identisk.
- **Rå tekstform** i klausul-manifestet og et offset-tjek i DB-writeren (`CLAUSE_EVIDENCE_RAW_OFFSET_MISMATCH`).
  Tekstformer er en lukket liste; en ny form kræver kode, og ukendte former afvises (`CLAUSE_TEXT_FORM_UNSUPPORTED`).
- **Helpost-reglen** (`private.record_helpost_status`): basen vælger helposten for records med flere forekomster;
  eksporten følger den.
- **Tekstversioner af helposten og kildetekst-revision.** Bygget for 2018-20's 11 A6b-poster, men generelt:
  en udgave kan senere få renset eller rettet tekst, uden at gamle klausuler mister deres tekst.

### Erfaring

1939's afvigelser var i **tekstens form** (OCR, sidemarkører, linjeskift), ikke i sætningerne. Indstillingerne var
billige at finde med den tørre kørsel. Den fælles kode var dyrere, men skulle kun skrives én gang. En udgave med PDF-
tekstlag (som 2018-20) vil sandsynligvis kunne nøjes med indstillinger; en ny OCR-kilde eller en anden opsætning
(fx to spalter) vil kræve ny kode. Det sidste er ikke målt.

## 6b — (udfyldes efter 6b)

## 6c — (udfyldes efter 6c)

## Faste omkostninger pr. udgave (indtil videre)

- **Én profilfil pr. formål** (kildeevidens, klausul-evidens, revision …) under
  `.claude/skills/daa-extract/references/reimport-profiles/`. I dag laves de ved at kopiere en eksisterende og
  rette den til.
- **En DB-migration pr. profil:** profilens fingeraftryk seedes i `schema.sql` og `db-migrations.sql`, så en ny
  udgave er en PR med migration, ikke kun en ny fil.
- **Tør kørsel på bogens tekst lokalt.** Teksten kan handle om levende personer og må ikke sendes til en model
  (invariant 8). Optællingen og skønnet over forkortelser laves derfor af et menneske eller af controlleren på egen
  maskine, kun med antal i output.
- **Postgrænserne** (segmenteringsprofil i `segment.py`) er stadig udgavens egne regler og var det dyreste i 1939's
  tidligere spor (grænsefejl, OCR med manglende sider). Det er ikke berørt af 6a.

## Faldgruber

- **Repo-vide vagter rammer nye profilseeds.** Writer-inventaret (`test-reimport-writer-source-inventory.R`) tæller
  udgavespecifikke literaler (fx kilde-id) i writer-sektionen, også i kommentarer. 1939-seedet gjorde R-jobbet rødt
  i CI (#281). Hver ny udgaves seed skal klassificeres dér.
- **`segmenter_version` er pinnet i profilerne** som en hash af segmenteringskoden. Ændres koden, skal profilen
  udstedes på ny, før en ny kørsel.
- **Kør hele CI lokalt før push**, også R-jobbet. Flere vagter fanger først nye filer, når de er committet.
