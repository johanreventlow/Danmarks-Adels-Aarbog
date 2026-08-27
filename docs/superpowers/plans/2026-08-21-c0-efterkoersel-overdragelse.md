# Overdragelse til Codex — 1939-sporet efter C0's efterkørsel

**Skrevet:** 2026-08-21 · **Branch:** `feat/evidensbaseret-genimport` · **Alt er pushet.**

## Læs dette først

Arbejdet ligger **ikke** i repoets hovedmappe, men i en worktree:

```
/Users/johanreventlow/TypeScript/danmarksadelsaarbog/.claude/worktrees/evidensbaseret-genimport
```

Hovedmappen står på `feat/union-redigering` og har intet med dette at gøre.
Alle stier nedenfor er relative til worktree'en.

## Hvad der lige er sket

C0's efterkørsel er kørt i produktion (`change_set 965`, bindinger 550 → 559).
Ni personers 1939-narrativ blev erstattet med normaliseret kildetekst, og ni
kildebindinger blev oprettet. Fuld beskrivelse i `docs/changelog.md`, øverste
post. Grundlaget står i:

- Spec: `docs/superpowers/specs/2026-08-21-1939-v50-fase-c0-efterkoersel-design.md`
- Plan: `docs/superpowers/plans/2026-08-21-1939-v50-fase-c0-efterkoersel.md`
- GO-pakke m. hashes: `docs/superpowers/reviews/1939-v50-fase-c0-efterkoersel-go-pakke.md`
- Afklaringer (hvorfor 1017 blev flyttet): `docs/superpowers/reviews/1939-v50-fase-c0-efterkoersel-afklaringer.md`

## Miljø-fælder, der koster tid at genopdage

**Python er `/usr/bin/python3` (3.9.6), ikke `python3` fra PATH.** Homebrews
3.14 har ikke `pytest`. 3.9 er sprogniveauet: `Dict`/`List` fra `typing`, ikke
`dict[str, int]`.

**R-scriptenes forbindelse:** `env_or("PGHOST", "SUPABASE_HOST")` falder tilbage
**per variabel**. Sætter du kun nogle af `PGDATABASE`/`PGHOST`/`PGPORT`/`PGUSER`/
`PGPASSWORD`, peger de resterende på **produktionen**. Sæt alle fem eller ingen.
`--expect-database-name` er nettet.

**Prod-RPC'er gates på rollen.** `red_*`-funktioner kræver
`current_rolle()='redaktion'`, udledt af `profiles WHERE id = auth.uid()`. Over
en direkte forbindelse er `auth.uid()` NULL → rollen bliver `medlem`. Sæt
`set_config('request.jwt.claim.sub','ba4ce28d-42a0-48af-a47c-773c26934236',true)`
inde i transaktionen. Vil du **prøve** gaten uden at skrive: kald RPC'en i
`BEGIN READ ONLY` — passerer den, fejler den på `INSERT`, ikke på rollen.

**Kør R-suiten fra worktree-roden:** `Rscript run-tests.R`. Den giver ~11
harmløse `path[1]="run-tests.R"`-warnings.

## To ting, der SKAL laves, hvis kæden genbruges

Begge er parkeret med ruling, og begge blev afvist som utilstrækkeligt begrundet
af den endelige helhedsgennemgang:

1. **Beslutnings-JSON'en bærer ingen `flags_sha256`.** Et gammelt menneskeark kan
   parses mod et nyt flag-dokument, hvis de synlige haler er ens. Hashen kan
   bæres i beslutningsfilen eller som et CLI-krav **uden at ændre én byte i
   arket** — det var min oprindelige begrundelse for at lade være, og den holdt
   ikke.
2. **`render_review` og `_expected_sequence` implementerer rækkefølgen to gange**
   (`build_c0_followup_review_1939_v50.py:41` vs.
   `convert_c0_followup_decisions_1939_v50.py:100`). Ændres kun den ene, bliver
   et nygenereret ark uparsbart — eller værre, positionssemantikken flytter sig.
   En fælles sekvensgenerator kan udtrækkes og bevises med golden-hash.

## Åbne spor, i den rækkefølge de blev efterladt

**1 · C3-sammenlægninger — inkl. 1017/1021.** Person 1021's samlede narrativ er
57 tegn: `"low († 1752), hvis Søn Friederich Adolph døde ugift 1773."` Den
begynder midt i det orddelte »Revent- low« og er halen af person **1017's**
afsnit B). Den skal slås sammen med 1017, ikke bevares som post. Plus de 7
øvrige C3-poster fra C0's afgørelser.

**2 · Grænsefejl er en klasse, ikke enkelttilfælde.** 12 af de 576
1939-narrativer begynder midt i en sætning (lille begyndelsesbogstav): 929, 930,
956, 977, 1013, 1014, 1021, 1308, 1413, 1771, 1772, 1791. To par — 929/930 og
1013/1014 — har **byte-identisk tekst**, altså både afskårne og duplerede. Fem
af de tolv står på C0's uafklarede-liste. Det er talt, ikke fikset, og det
antyder C3's reelle størrelse.

**3 · De 16 `[NY]`-records.** Personoprettelse fra records uden modstykke. Eget
autorisations-gate; ikke påbegyndt.

**4 · 7 staged personer tilbage:** 933, 935, 940, 963, 967, 1014, 1135. Alle har
1939-narrativ og external_id, men 0 published bindinger. **963 og 967 fik netop
deres binding i denne fase**, men forbliver staged — bevist ufarligt, da
`private`-skemaet ikke er eksponeret gennem API'et og `anon` hverken ser
personerne eller deres narrativer.

**5 · Strukturerede fakta er usynlige i læserfladen.** `fetchPersonDetail`
(`web/src/data/public.ts:171`) forespørger aldrig `fact`. Kun leveår (via
`visning_*`-cachen) og titel når skærmen. Se `docs/decisions.md`.

**6 · Hændelsesudtrækket er aldrig kørt.** `haendelse`-tabellen har 0 rækker;
`/daa-haendelser` blev parkeret som issue #130 til efter genimporten. 1939-
narrativerne alene er 166.518 tegn prosa. Punkt 5 og 6 hænger sammen som ét
stykke arbejde: der er ingen grund til at udtrække mere, før der er et sted at
vise det, og ingen grund til at bygge visningen, hvis den kun kan vise fødsel
og død.

**7 · 16 tomme unioner** (1 partner, 0 børn) af 682 familier. Familie-id 715-731
er en næsten sammenhængende blok, hvilket peger på én loader-kørsel. Se
`docs/decisions.md`.

## Arbejdsmapper indeholder PII

`work/` er gitignoreret og rummer prosa om personer. Commit den aldrig, og send
den aldrig til en model — invariant 8 i `CLAUDE.md`.
