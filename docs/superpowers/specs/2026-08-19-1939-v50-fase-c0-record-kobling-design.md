# 1939 v50 fase C0 — kobling af de 41 »ægte nye« kilderecords: design

**Status:** godkendt i brainstorm 2026-08-19. Implementeringsplan følger.

## Problemet

Fase B erstattede 551 biografier med evidensbaseret tekst, men efterlod
**23 narrativer med gammel tekst**. Undersøgelsen 2026-08-19 viste at
årsagen ikke er manglende tekst, men en **manglende kobling**: fx person
1299 (Ferdinand Einar Julius Gottlieb) har i prod netop den tekst, som
kilderecord `record-82f49e95…` (s. 574-575) dækker — men recorden blev i
identitetsgennemgangen klassificeret
`accepted_genuinely_new_source_record` / `person_creation: forbidden`
**uden baseline-tilknytning**, så personen aldrig kom i fase B's scope.

C0 omgør altså tidligere identitetsafgørelser. Derfor skal hver enkelt
omgørelse bæres af eksplicit, genkørbar evidens — ikke af et skøn.

## Beslutninger truffet i brainstormen

| Spørgsmål | Valg |
|---|---|
| Hvor langt går denne omgang? | **Analyse + menneskeafgørelser. Stop før prod.** Prod-skrivningen bliver sin egen GO-pakke. |
| Kun det der løser de 23, eller alle 41? | **Alle 41** afgøres, mod hele prods 1939-bestand. De 23 er en delmængde af resultatet, ikke definitionen af det. |
| Fragmenter (én record ↔ to personer)? | **Dokumentér og udskyd til C3.** C0 træffer kun kobling, aldrig sammenlægning. |

Begrundelsen for stop-før-prod er ikke forsigtighed alene: **fortryd
dækker ikke narrativ-bindingerne** (`narrative_record_publication` står
ikke i `version_pk_registry`). En forkert kobling kan derfor ikke rulles
tilbage ad normal vej. Beslutningerne skal stå fast, før noget skrives.

## Datagrundlag (hash-låst, intet nyt udtræk)

| Input | SHA-256 | Bidrag |
|---|---|---|
| `work/task21-1939-v50-import-preview/import-preview-v1.json` | `04f2780b…` | `genuinely_new_pending` = **41** records m. `verbatim_text` + `source_span` |
| `work/task21-1939-v50-import-preview/database-preview-v1.json` | `a00efd43…` | `person_anchors.database_only` = **23** (person_id, visning_navn, staged), samt `matched` = 543 |
| prods 1939-narrativer | læses read-only | sammenligningsgrundlag (hele bestanden) |

Begge hashes er identiske med `LOCKED_IMPORT_PREVIEW_SHA256` og
`LOCKED_DATABASE_PREVIEW_SHA256` i
`build_phase_a_anchor_manifest_1939_v50.py` — altså nøjagtig det
grundlag, fase A og B blev reviewet og kørt på. Filnavne-versionering
(`source-record-reconciliation-v33…v49`) er **ikke** en pålidelig
ordning og må ikke bruges til at vælge input; hash-låsen er båndet.

**Verbatim er uforanderligt.** Rendition, spans og `citat_tekst` røres
ikke. Al normalisering sker i hukommelsen og skrives aldrig tilbage.

Uden normalisering er sammenligningen meningsløs: de 23 personer bærer
gammel importtekst, mens recordene bærer OCR-ombrudt Calamari-tekst — en
rå sammenligning ville vise nær-nul lighed og fejlagtigt bekræfte, at
recordene er ægte nye.

Sammenligningen sker på et **skelet** (`c0_compare_v1`): NFC, casefold,
kun alfanumeriske tegn. Det er strengere og enklere end at genbruge fase
B's `narrative_norm_v1` — ombrydning, bindestreger og OCR-indsatte
mellemrum forsvinder i ét greb, uden at arve norm_v1's beslutninger om
tvetydige bindestreger. Kalibreringsankeret «Gottlie b» → «gottlieb» er
netop den klasse. (Fastlagt under planlægningen; erstatter designets
oprindelige forslag om at genbruge norm_v1 til sammenligning.)

## Matchningskontrakt

**Ingen automatisk kobling.** Scriptet producerer en *anbefaling* pr.
record; mennesket træffer alle 41 afgørelser. Tærskler styrer derfor
kun hvilken anbefaling der er udfyldt på forhånd og hvilken rækkefølge
posterne står i — ikke hvad der sker med data. Det gør tærskelvalget
til et ergonomi-spørgsmål frem for et datasikkerhedsspørgsmål.

Tre uafhængige signaler beregnes pr. (record, person)-par:

1. **Tekstlighed** på normaliseret tekst: eksakt match, lighedsratio og
   *containment* (record ⊂ narrativ eller narrativ ⊂ record).
   Containment er det bærende signal ved fragmenter og skal måles
   særskilt, ikke skjules i en ratio.
2. **Anker**: recordens side, udledt af spannet via det eksisterende
   sidekort, mod personens registrerede sidehenvisning i prod. Kan
   siden ikke udledes deterministisk, bortfalder signalet — det
   nedgraderer anbefalingen, men spærrer ikke posten.
3. **Navn/år**: personens `visning_navn` og kendte års-fakta mod
   recordens verbatim-tekst.

**Anbefalings-klasser:**

| Klasse | Betingelse | Prefilled |
|---|---|---|
| Kobling | Præcis **én** kandidat over kandidat-tærsklen, og mindst ét bekræftende signal ud over tekstligheden | `KOBL <person-id>` |
| Gennemgang | Én kandidat, men kun ét signal, eller middel lighed | tom — kræver stillingtagen |
| Sammenlægning | **Mere end én** kandidat over kandidat-tærsklen | `FRAGMENT/ALIAS → C3` (spærret for kobling) |
| Ægte ny | Ingen kandidat over kandidat-tærsklen | `ÆGTE NY` |

Tærsklerne kalibreres i implementeringsplanen mod kendt sandhed —
person 1299 / `record-82f49e95…` er et bekræftet sandt positiv og
fungerer som ankerpunkt. Ved tvivl vælges den lavere klasse
(fail-closed mod menneskelig gennemgang, aldrig mod automatik).

## To forskellige mængder på 23 — må ikke forveksles

Verificeret 2026-08-19 under spec-arbejdet:

| Mængde | Målt | Indhold |
|---|---|---|
| `person_anchors.database_only` | 2026-08-17 (preview) | 23 personer uden v50-baseline-mapping, heraf **7 staged** |
| Gammel tekst efter fase B | 2026-08-19 (prod) | 23 personer hvis narrativ ikke blev erstattet |

De deler **22** medlemmer, ikke 23. Person **1802** har gammel tekst
uden at stå i `database_only`; person **991** står i `database_only`
uden at have gammel tekst efter fase B. At begge mængder tæller 23 er
et tilfælde, og at behandle dem som én mængde ville lade 1802 gå
uforklaret gennem hele fasen.

Planen skal derfor **genmåle listen over gammel-tekst-personer
read-only mod prod** ved kørsel — preview'ens `database_only` er
frosset 17/8 og er ikke facit for fase B's restmængde. Begge lister
indgår i lukningen nedenfor, hver for sig.

## Lukning begge veje

Rapporten skal svare på tre spørgsmål, ikke ét:

1. Har hver af de **41** records et udfald?
2. Er hver person med **gammel tekst efter fase B** (genmålt) forklaret
   af mindst én record?
3. Er hver person i **`database_only`** gjort rede for — enten som
   forklaret, eller som dokumenteret uden for C0's rækkevidde?

En af de 23 uden forklaring er et **fund**, ikke en afrunding: så er
hypotesen om at fejlklassifikationen forklarer dem alle, ufuldstændig,
og det skal stå i rapporten frem for at forsvinde i en procentsats.
Tilsvarende er records der matcher personer **uden for** de 23 et
reelt resultat — teksten er allerede rigtig, men kilde-koblingen
mangler, og det er et hul i kilderegnskabet på linje med de øvrige.

## Menneskefladen

De 41 leveres som **token-pr-linje-tekstfil** efter fase B's mønster:
udfyldt anbefaling pr. record, byte-låst kontekst, fail-closed
konverter, mistænkelige poster øverst. Ikke et markdown-læseark.

Tre lovlige tokens: `KOBL <person-id>` · `ÆGTE NY` ·
`FRAGMENT/ALIAS`. Konverteren afviser alt andet, afviser `KOBL` på en
spærret post, og afviser ukendte eller allerede-mappede person-id'er.

Hver post viser: recordens verbatim-tekst, dens span og side, de
beregnede signaler, og for hver kandidat personens id, navn,
staged-status og den tekst der i dag står i prod — nok til at afgøre
sagen uden at slå op andetsteds.

## Udfald og videre routing

| Udfald | Videre |
|---|---|
| `KOBL` | Optages i en **fase B-efterkørsel**: samme writer, nyt lille manifest. Egen GO-pakke. |
| `ÆGTE NY` | Personoprettelse efter task 25-mønstret — **egen** autorisation og eget cutover-gate; må ikke ride med i C0's apply. |
| `FRAGMENT/ALIAS` | Dokumenteret, afgøres i C3 sammen med de øvrige dublet-afgørelser. |

## Afgrænsning

Uden for C0: OCR-fejl i teksten (fx «Gottlie b» med indsat mellemrum)
er redaktionelt arbejde i redaktørfladen, ikke normalisering. De 6
strukturelle og 2 krydsreference-records skal med rette ikke kobles til
personer og indgår ikke. Selve personoprettelsen for `ÆGTE NY`.
Sammenlægningsafgørelserne. Og synlighed: **staged personer forbliver
staged** (7 af `database_only` er det) — C0 rører tekst, ikke
publicering. Det hører til fase D, og C0's apply må ikke stiltiende
implicere en publiceringsbeslutning.

## Verifikation

- Scriptet er read-only mod prod og deterministisk: samme input → samme
  output-hash, uafhængigt af `PYTHONHASHSEED` (bevises som i task 25).
- Enhedstest af signalberegning og af konverterens afvisninger.
- Kalibrerings-assert: person 1299 / `record-82f49e95…` skal lande i
  klassen Kobling; hvis ikke, er tærsklerne forkerte.
- Fail-closed gennemgående: manglende eller tvetydige data giver lavere
  klasse, aldrig en udfyldt kobling.

## Krav der arves fra programmet

- Skrivninger sker via `apply_migration` (DDL) eller hash-låste
  psql-scripts; Supabase MCP `execute_sql` er read-only.
- Prod-gate pr. fase: frisk backup (0600 + SHA-256) → rehearsal mod
  frisk produktionsækvivalent restore m. byte-identiske
  før/efter-baselines → eksplicit godkendelse m. eksakte hashes → én
  apply, ingen retry.
- Fase B's to fangne fælder skal bæres med i efterkørslen:
  replay-værnet skal dække `privat`/`side` (ikke kun tekst), og
  `digest()` skal skema-kvalificeres, fordi prods `search_path` mangler
  `extensions`.
- `work/`-artefakter committes aldrig.
- `load_daa.R` røres ikke og kaldes ikke.
