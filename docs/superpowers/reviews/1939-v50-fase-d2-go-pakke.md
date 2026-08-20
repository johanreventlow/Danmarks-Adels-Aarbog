# Fase D2 — GO-pakke

**Dato:** 2026-08-20 · **Status:** ✅ GODKENDT OG UDFØRT · `change_set 960`

> **Kørt 2026-08-20.** staged 28 → 7, 21 `change_events`, nul delta på
> person/fact/relation/narrative. Målt med `SET LOCAL ROLE anon`: 1.734
> personer synlige, 0 levende, 0 staged. Dokumentet bevares som det grundlag,
> der blev sagt ja til.

Task 1 og 2 er bygget, reviewet og hærdet. Task 3 (prod-kørslen) er ikke kørt.
Dette dokument er det grundlag, der skal siges ja til.

## Hvad der sker, hvis du siger GO

**21 mennesker bliver offentligt synlige.** De er gift-ind-ægtefæller uden
egen post i DAA 1939 — et navn, et ægteskab, næsten intet andet. Deres
partner er allerede synlig, så fladen viser i dag et ægteskab, hvor den ene
part mangler.

Ingen af dem er levende, ingen er privatmarkeret, alle har navn. Intet andet
end `person.staged` ændres.

## De målte tal (mod prod, 2026-08-20)

| Tal | Værdi |
|---|---:|
| Valgte | **21** |
| Staged i alt nu | **28** |
| Staged bagefter | **7** |
| Ekstra medrevne | **0** |
| Overlap med C0's uafklarede | **0** |

**Ærlighed om tallene:** det er fem tal, men tre målinger. `staged_bagefter`
og `ekstra_medrevne` udledes begge af `staged_i_alt`, antal valgte og RPC'ens
simulerede medrivning. Remainder-tjekket er derfor algebraisk det samme som
`ekstra_medrevne == 0` — det har kun tænder mod et håndbygget dokument.

Id-listen er identisk med designdokumentets 21, og 1662 er fortsat den eneste
med en `samme_som`-relation.

**Udvalgsfil:** `work/task28-1939-v50-d2-aegtefaeller/spouse-selection-v2.json`
(en tidligere `v1` fra før GDPR-gaten er slettet — den ville have passeret den
hærdede apply, som ikke læser `levende`/`privat` fra dokumentet)
SHA-256 `8487ad711164d429d0adfa54984af7bbfda7fd75217868fceb8821bf725f3463`

**Backup:** `work/task28-1939-v50-d2-aegtefaeller/pre-d2-20260820-222135.dump`
(5,7 MB, 0600) SHA-256
`2c974998df4b8f9fe3e73254dfbc254bdd7ec96b12959ea5f4def59cc2289f85`

## Rehearsal — kørt, i modsætning til hvad planen lagde op til

Planens Task 3 gik backup → eksport → apply **uden** den rehearsal, D1's plan
krævede. Det ville have været en stille lempelse af gate-kæden for repoets
*første* fail-closed prod-wrapper. Rehearsal er derfor kørt alligevel, mod en
frisk restore af dagens dump (`daa1939_d2_rehearsal1`):

| Prøve | Resultat |
|---|---|
| Eksport mod kopien | samme fem tal, samme 21 id'er |
| Apply | 21 afstaget, `staged 28 → 7` |
| Nul-delta på person/fact/relation/narrative | bestået |
| `change_events` skrevet | **21** — publiceringen er fortrydbar |
| Efterkontrol: ikke-kvalificerede blandt de 21 | **0** |
| Gentagen kørsel | afvist fail-closed (`D2_APPLY_STAGED_DRIFT`) |
| Induceret drift (én ekstra staged) | afvist, basen uændret |

Fordi kopien er en **restore af prod-dumpen**, var den `red_publicer_personer`
der blev øvet, den **live** definition — ikke `db-migrations.sql`'s. Det lukker
drift-risikoen mellem repo og base for denne fase.

## Rolle-gaten — et hul i planen, fundet og lukket

`red_publicer_personer` kræver `current_rolle() = 'redaktion'`, udledt af
`profiles WHERE id = auth.uid()`. Over en direkte forbindelse er `auth.uid()`
NULL → rollen bliver `medlem` → RPC'en kaster. **Planens R-kode gjorde intet
ved det og ville være stoppet på gaten.**

Afgjort empirisk mod prod, uden at røre data:

- `auth.uid()` coalescer `request.jwt.claim.sub` **først** — vores kald rammer rigtigt
- før `set_config`: `current_rolle()` = `medlem`; efter: `redaktion`
- RPC'en kaldt i en `READ ONLY`-transaktion fejlede på `INSERT` (fra
  `begin_change_set`), **ikke** på rolle-gaten — den var altså passeret

## Adversarial review

Codex sol reviewede wrapperne og fandt fire ægte fund, alle rettet — det
alvorligste at drift-guarden sammenlignede *antal* frem for *hvem*. Detaljer i
commit `61840e5`. Codex kunne ikke selv afgøre rolle-spørgsmålet (det kræver
et prod-opslag, som dets read-only-instruks udelukkede); det er afgjort ovenfor.

## Kommandoen, hvis du siger GO

```bash
Rscript .claude/skills/daa-extract/scripts/apply_d2_spouses_1939_v50.R \
  --selection work/task28-1939-v50-d2-aegtefaeller/spouse-selection-v2.json \
  --expect-sha256 8487ad711164d429d0adfa54984af7bbfda7fd75217868fceb8821bf725f3463 \
  --backup work/task28-1939-v50-d2-aegtefaeller/pre-d2-20260820-222135.dump \
  --jeg-mener-det
```

Forventet: `OK: staged 28 -> 7`. Fejler den, køres den **ikke** igen — den
melder selv hvad der har flyttet sig.

Bagefter: changelog + `database-current-state.md` afstemmes, og du bekræfter i
web-fladen at et af de 21 ægteskaber nu viser begge parter — særligt at 1662's
ægteskab fremgår på den collapsede person sammen med 785's.
