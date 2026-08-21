# C0's efterkørsel — GO-pakke

**Dato:** 2026-08-21 · **Status:** afventer brugerens GO · **Intet skrevet til prod.**

Task 1–5 er bygget, reviewet og rehearsal-kørt. Task 6's prod-apply er ikke kørt.
Dette er det grundlag, der skal siges ja til.

## Hvad der sker, hvis du siger GO

**Ni personers biografi erstattes**, og ni kildebindinger oprettes. Otte af de ni
får en renset tekst; **person 991's tekst er uændret** — dér tilføjer koblingen
udelukkende bindingen.

Person **1017 er ikke med**. Dens kobling ville have slettet 149 tegn, hvoraf de
første ~92 ikke findes noget andet sted i korpus. Den er flyttet til C3.

## Din godkendelse

Du gennemgik menneskearket og godkendte alle otte orddelinger som `MERGE`
(Efter+slægt, For+pagter, For+mand, Folke+tinget, Rigs+raad, Katedral+skole og
to gange Legationssekre+tær), samt alle ni personer som `ACCEPT`.

Arket er genbygget mod prod umiddelbart før denne pakke og er **byte-identisk**
med det, du så: SHA-256 `98fbb11b4132dfea1ac77bf3de9cb1a2cfbac63dd0bfc0b6eca545a48f1ffd58`.

## Hvad der ændrer sig

| Person | Nu | Bliver | Δ | Karakter |
|---|---:|---:|---:|---|
| **991** | 32 | **32** | **0** | uændret — kun bindingen tilføjes |
| 963 | 103 | 101 | −2 | orddeling opløst |
| 992 | 107 | 105 | −2 | orddeling opløst |
| 1296 | 278 | 275 | −3 | ordenstal + linjeskift |
| 1298 | 349 | 344 | −5 | ordenstal + linjeskift |
| 1299 | 666 | 655 | −11 | ordenstal + linjeskift + `### PAGE` fjernet |
| 1297 | 731 | 688 | −43 | normalisering + strukturlinjen »Børn: Ottende Slægtled IIl.« |
| **978** | 100 | **140** | **+40** | **nyt indhold** |
| **967** | 149 | **193** | **+44** | **nyt indhold** |

Kun 967 og 978 tilfører reelt nyt indhold. De negative delta er normalisering —
samme rensning, fase B gav de øvrige 551.

De ni tekstlængder er krydskontrolleret ad to uafhængige veje: direkte kald af
`normalize_narrative_v1`, og hele kæden gennem manifestet. De mødes byte for byte.

## Artefakter

| Fil | SHA-256 |
|---|---|
| `prod-manifest.json` | `f067a4c3ec3e2b925afd4026c4caf369e2a503eb9d6c0d797515d7a36d86a352` |
| `pre-c0f-20260821-112005.dump` (5,7 MB, 0600) | `fcfeb22532975d45803b98813e51bdde33b5a79537547b7ce202a28eaf7046b3` |
| `prod-ark.txt` (dit godkendte ark) | `98fbb11b4132dfea1ac77bf3de9cb1a2cfbac63dd0bfc0b6eca545a48f1ffd58` |

## Rehearsal — kørt mod en restore af dagens prod-dump

Basen `daa1939_c0f_rehearsal1` startede identisk med prod: 550 bindinger, 1.169
narrativer, 1.811 personer, 7.197 fakta, 2.030 relationer.

| Prøve | Resultat |
|---|---|
| Apply | `OK: 9 koblinger; bindinger 550 → 559` |
| Tabelantal (narrativ/person/fakta/relation) | **uændrede** |
| De ni tekstlængder | præcis som manifestet |
| `privat` på alle ni | `false` |
| `side` på alle ni | uændret |
| Narrativer med `### PAGE` | **0** |
| Enlige linjeskift i de ni | **0** |
| Gentagen kørsel | afvist: `C0F_APPLY_OLD_SHA_MISMATCH` |
| Rehearsal-manifest kørt mod **prod** | afvist: `C0F_APPLY_DATABASE_MISMATCH` |

Fordi kopien er en **restore af prod-dumpen**, var de `red_upsert_narrativ` og
`red_publicer_narrative_record`, writeren kaldte, de **live** definitioner — ikke
repoets SQL.

`change_set` fik **8** change_events, ikke 9: person 991's tekst er byte-identisk
før og efter, så UPDATE'en skrev samme værdi og triggeren så ingen ændring. Det er
beviset for succeskriteriet, ikke et tabt spor.

## Fortrydelse — ærligt

| Skrivning | Fortrydbar? |
|---|---|
| `narrative.tekst` | **Ja** — `narrative` står i `version_pk_registry` → `change_events` |
| `narrative_record_publication` | **Delvist** — `red_tilbagetraek_narrative_record(narrative_id)` findes i prod, men efterlader intet `change_event`, så web-fladens fortryd-panel viser den ikke |
| Sidste udvej | Dumpen ovenfor |

Svagere end D2, hvor ét `change_set` dækkede alt. Derfor var rehearsal obligatorisk.

## Kommandoen, hvis du siger GO

```bash
cd .claude/worktrees/evidensbaseret-genimport
Rscript .claude/skills/daa-extract/scripts/apply_c0_followup_1939_v50.R \
  --manifest work/task30-1939-v50-c0-efterkoersel/prod-manifest.json \
  --expect-sha256 f067a4c3ec3e2b925afd4026c4caf369e2a503eb9d6c0d797515d7a36d86a352 \
  --backup work/task30-1939-v50-c0-efterkoersel/pre-c0f-20260821-112005.dump \
  --jeg-mener-det
```

Forventet: `OK: 9 koblinger; bindinger 550 -> 559`.

Fejler den, køres den **ikke** igen — den melder selv, hvad der har flyttet sig.

## Bagefter

Efterkontrol mod prod (bindingstal, de ni tekstlængder, nul-delta, ingen rå
sidemarkører), changelog og `database-current-state.md` afstemmes, og C0-punktet i
`decisions.md` markeres udført, mens C3-punktet forbliver åbent — 1017/1021 hører
til dér.
