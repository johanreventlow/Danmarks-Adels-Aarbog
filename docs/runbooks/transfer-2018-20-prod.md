# Runbook — samlet prod-overførsel af 2018-20's fortolkningskæde (#147)

Autoritativ ceremoni for spec `docs/superpowers/specs/2026-10-03-trin4-2018-20-prod-overfoersel-design.md`
(§5-§9), bygget i plan A (pakken) og plan B (`docs/superpowers/plans/2026-10-04-trin4-2018-20-overfoersel-b-ceremoni.md`).
Overførslen skriver 3.739 forslag, 676 afgørelser og 622 bindinger i prod fra den nøglede pakke
`07355ccc…` (`DAA_PACK_SHA256`). Alle tal og hashes i denne runbook er målt; der står aldrig
kildetekst, claim-værdier eller aktør-uuid.

Prod rammes **kun** af projektejeren i egen shell (`! /bin/zsh -f …`). AI-sessionen kører intet mod prod.

## 1. Formål og forudsætninger

- **Pakken** ligger i `~/.private/2018-20-overfoersel/pack/` (`pack-manifest.json` `37fb9b01…`,
  `decisions-keyed.json` `c39a5f5c…`). Skrive-SQL'en `sql/07.sql` (`af7e51a7…`) og `sql/08.sql`
  (`b903896f…`) er genereret fra den og byte-bundet i `lib.zsh`.
- **Scripts:** `~/.private/2018-20-overfoersel/` (`00`-`05`, `07`, `08`, `09`, `lib.zsh`, tre R-filer,
  `rollback-preflight.sql`). `koer.zsh` bærer GO-miljøet mellem trinnene (`prod/go-env.txt`, kun
  `DAA_NAVN=<sti/hash/kode>`). Den er ikke i GO; scriptene verificerer selv alt, de får.
- **`DAA_REPO` er hovedcheckouten** `/Users/johanreventlow/TypeScript/danmarksadelsaarbog` på `main` ved
  GO-commit'en, ikke en worktree. R-filerne kræver netop den sti. Før `01`:

  ```
  ! git -C /Users/johanreventlow/TypeScript/danmarksadelsaarbog switch main && git -C /Users/johanreventlow/TypeScript/danmarksadelsaarbog pull --ff-only
  ```

  Commit'en gemmes i GO-miljøet (afsnit 3); `03`-`09` stopper med `COMMIT_MISMATCH`, hvis checkouten
  flytter sig, og med `REPO_DIRTY`, hvis en af de 13 eksekverede repo-filer har lokale ændringer.
- **Skrivepause:** ingen redaktionelle skrivninger fra `00 begin` til `00 end`. Andre sessioner må ikke
  skrive i prod imens.
- **Kun Session pooleren** (`*.pooler.supabase.com:5432`); alt andet giver `POOLER_REQUIRED`.

## 2. Proben (læse-kun, kan gentages)

```
! /bin/zsh -f ~/.private/2018-20-overfoersel/probe.zsh
```

Udskriver `PROBE_OK <sti> <hash>`. Sessionen sammenligner med en lokal ren restore af 1/10-dumpet
(`probe-compare.py`): G1 version, G2 tegn, G3 drift, G4 `EMPTY`, G5 katalog, G6 aktør, G7 timeouts,
G8 levende. Målt 2026-10-04: alle OK; I1 viste 0 `change_set` siden dumpet 1/10.

**G7 (beslutning 2026-10-04):** prod afbryder enkeltsætninger efter 2 min (`statement_timeout`).
Prod-indstillingen røres ikke. I stedet kræver generalprøven ≤ 30 s pr. trin lokalt, og `07`/`08`
sætter selv `statement_timeout = '15min'` for deres egen forbindelse (bekræftet med `SHOW`, ellers
`TIMEOUT_NOT_SET`). R-trinnene (dry-run og apply) har kun luften: lokalt 10-15 s pr. trin.

## 3. Ceremonien

Kør trinnene i rækkefølge, i én session. Hver linje forventer præcis det angivne udfald; alt andet er
STOP (afsnit 5).

```
! /bin/zsh -f ~/.private/2018-20-overfoersel/koer.zsh --saet DAA_FREEZE_RESPONSIBLE=<kort ansvarskode>
```
```
! /bin/zsh -f ~/.private/2018-20-overfoersel/koer.zsh --saet DAA_EXPECTED_TARGET=71ca6e452cc7d596d8470807e29084cd9d99f8ac24155556afd635da84ffe0f0
! /bin/zsh -f ~/.private/2018-20-overfoersel/koer.zsh --saet DAA_EXPECTED_COMMIT=$(git -C /Users/johanreventlow/TypeScript/danmarksadelsaarbog rev-parse HEAD)
```
Gemmer din ansvarskode (ikke-følsom), prods faste mål-identitet og hovedcheckoutens commit. Forventet:
tre gange `gemt: …`. Commit'en er den, GO binder.

**1. Skrivepause.** Fra nu må ingen skrive i prod.
```
! /bin/zsh -f ~/.private/2018-20-overfoersel/koer.zsh 00-freeze.sh begin
```
Forventet: `FREEZE_BEGIN_OK active_other_connections=0 state=EMPTY`. Er der andre aktive forbindelser,
stopper den; tilføj `--accepter-forbindelser <antal>` kun, når du ved, hvad de er.

**2. Preflight (læser).** Rolleprobe, drift, `EMPTY`, ledger, levende-gate, aktør, restore-forudsætninger,
grants og tegnprobe.
```
! /bin/zsh -f ~/.private/2018-20-overfoersel/koer.zsh 01-preflight.sh
```
Forventet: `PREFLIGHT_OK state=EMPTY levende=471|471|471|471|471`.

**3. Dump (læser).** Backup taget i pausen; kvitteringen bærer restore- og uberørt-hash.
```
! /bin/zsh -f ~/.private/2018-20-overfoersel/koer.zsh 02-dump.sh
```
Forventet: `DUMP_OK bytes=… sha256=…`. Dumpet er den eneste vej tilbage (afsnit 6).

**4. Generalprøve (lokalt; rører ikke prod).** Restorer netop dette dump i en ny lokal base og kører de
samme lib-funktioner som prod: `04` → `07` → `08` → `05`, derefter en øvet fortrydelse.
```
! /bin/zsh -f ~/.private/2018-20-overfoersel/koer.zsh 03-rehearsal.sh
```
Forventet: `REHEARSAL_OK base=… restore=…s dryrun=…s apply=…s decide=…s bind=…s undo=…s undo_errors=…`.
Stand-in målt 2026-10-04/05: dry-run 12-15 s, apply 10-12 s, `07` 16-17 s, `08` 3-4 s, 5 fejllinjer ved fortrydelsen.

**5. GO** (afsnit 4). Uden GO: `00-freeze.sh end --uden-skrivning`.

**6. Forslag (skriver).** Dry-run og apply gennem gatewayen.
```
! /bin/zsh -f ~/.private/2018-20-overfoersel/koer.zsh 04-apply.sh --jeg-mener-det
```
Forventet: `APPLY_OK` (tilstand `PROPOSED`).

**7. Afgørelser (skriver).** 676 afgørelser, hver med pakkens hash.
```
! /bin/zsh -f ~/.private/2018-20-overfoersel/koer.zsh 07-decide.sh --jeg-mener-det
```
Forventet: `DECIDE_OK` (tilstand `DECIDED`).

**8. Bindinger (skriver).** 622 bindinger.
```
! /bin/zsh -f ~/.private/2018-20-overfoersel/koer.zsh 08-bind.sh --jeg-mener-det
```
Forventet: `BIND_OK` (tilstand `COMPLETE`).

**9. Verifikation (læser).** Tilstand `COMPLETE`, alle tre digests og antal = pakkens, 676 med pakkens
hash, baseline uændret, uberørte tabeller uændret, grants uændret, `anon` kan ikke læse kædens tabeller.
```
! /bin/zsh -f ~/.private/2018-20-overfoersel/koer.zsh 05-verify.sh
```
Forventet: `VERIFY_OK`.

**10. Pausen slutter.**
```
! /bin/zsh -f ~/.private/2018-20-overfoersel/koer.zsh 00-freeze.sh end
```
Forventet: `FREEZE_END_OK mode=verify state=COMPLETE …`.

## 4. GO-pakken (spec §7)

Før GO ser projektejeren, fra `rehearsal.json` og `go-env.txt` (kun tal og hashes):

- `REHEARSAL_OK` med varighederne (alle ≤ 30 s), `undo_n_errors` og fortrydelsens efterkrav
  (tilstand `EMPTY`, restore-hash, katalog og baseline lig prods målinger);
- digests efter generalprøven = pakkens: `proposal_digest` `bb808efe…`, `decision_digest` `33fc4b56…`,
  `binding_digest` `5762ceaa…`; 3.739 / 676 / 622;
- `go_hashes_sha256` over inventarets 33 linjer (16 private + 4 input + 13 repo), commit og dumpets hash.

GO binder: GO-hashfilen (`DAA_GO_HASHES_FILE`), commit (`DAA_EXPECTED_COMMIT`), prods mål
(`DAA_EXPECTED_TARGET` = `71ca6e45…`), pausens rapport, dumpkvitteringen, preflight og rehearsal.
`04`/`07`/`08`/`05`/`09` tjekker dem alle før første forbindelse eller lige efter, og intet skrives,
før de holder.

## 5. Stopregler

Hvert skrivende trin måler først tilstanden ud fra digests (`EMPTY`/`PROPOSED`/`DECIDED`/`COMPLETE`/`MIXED`)
og skriver kun i sin indgangstilstand. I en senere tilstand melder det `ALREADY_APPLIED` og skriver intet.

| Tilstand | Næste skridt |
| --- | --- |
| `EMPTY` | `04` (også efter et afbrud før gatewayens commit) |
| `PROPOSED` | `07` (`04` igen giver `ALREADY_APPLIED`) |
| `DECIDED` | `08` (`07` igen giver `ALREADY_APPLIED`) |
| `COMPLETE` | `05`, derefter `00 end` |
| `MIXED` | STOP; fortrydelse (afsnit 6) |

**Afbrud i `04`** (forbindelsen dør, maskinen sover):
- før gatewayens commit: tilstand `EMPTY`; kør `04` igen. Genforsøget kræver, at de uberørte tabeller er
  uændrede siden første forsøg (`NO_WRITE_SINCE_FIRST_ATTEMPT`), og rapporten viser `attempt: 2`;
- efter commit: tilstand `PROPOSED`; `04` igen giver `ALREADY_APPLIED`; fortsæt med `07`;
- alt andet (`MIXED`, `PROPOSAL_DIGEST_MISMATCH`): fortrydelse.

`07` og `08` kører hver i én transaktion: en fejl ruller alt tilbage (`intet committet, tilstanden
uaendret`). Navngivne koder fra `07`: fx `MACHINE_PREMISE_DRIFT` (prods klassifikation afviger fra
pakkens), `TRANSFER_ACTOR_MISMATCH`, `DECISION_FINGERPRINT_MISMATCH`. Ingen af dem skriver; de kræver,
at årsagen findes, før noget køres igen.

**Tidsgrænse i `07`/`08` (`STATEMENT_TIMEOUT`):** trinnet afbrydes efter 15 min for én sætning, og
transaktionen rulles tilbage; tilstanden er uændret. Normalt tager `07` 16-17 s. En stand-in-kørsel
2026-10-04 hang én gang i 15 min i klassifikationen og kunne ikke genskabes (12 andre kørsler 16-17 s,
og forsøg med forældet statistik gav 15 s). Kør ikke trinnet igen i blinde: se efter låse og
samtidige skrivere (`pg_stat_activity`), og fortsæt først, når årsagen er kendt eller udelukket.

**`UNDO_ERRORS_DIFFER`:** fortrydelsens fejlliste afviger fra generalprøvens. I prod vil den **næsten
sikkert** afvige, fordi realtime-/graphql-afhængigheder kun findes i prod. Beviset er efterkravene:
tilstand `EMPTY`, restore-hash = kvitteringens, katalog = preflightens og baseline = pakkens. Holder de,
vurderer projektejeren fejllisten (`undo.json`), og pausen afsluttes med `00-freeze.sh end --uden-skrivning`.

## 6. Fortrydelse

```
! /bin/zsh -f ~/.private/2018-20-overfoersel/koer.zsh 09-undo.sh --jeg-mener-det
! /bin/zsh -f ~/.private/2018-20-overfoersel/koer.zsh 00-freeze.sh end --efter-fortrydelse
```

`09` kører netop den kommando, generalprøven øvede:
`pg_restore --clean --if-exists --no-owner --schema=private --schema=public` af pausens dump mod prod.
Den kræver en aktiv pause fra før dumpets start, dumpets byte-hash = kvitteringens og ejerskab over alt i
`private`/`public` (`RESTORE_PRIVILEGES`).

- **Prisen:** alt skrevet i `private`/`public` efter dumpets start går tabt. Under pausen er det kun
  overførslen.
- **Rester:** de RLS-afhængige funktioner (`current_rolle()`, `media_object_synlig_anon(text)`) hverken
  droppes eller genskabes, og det er forventede fejllinjer. Efterkravene beviser, at data og katalog er
  tilbage.

Forventet: `UNDO_OK` og derefter `FREEZE_END_OK mode=undo state=EMPTY`.

## 7. Efter `VERIFY_OK`

- **Modenhed (spec §9):** ingest og afgørelse ⇒ `produktionsverificeret` for 2018-20; promotion kun for
  bindingsdelen og markeret sådan. Statuslinjer i `docs/evidensbaseret-genimport/status.md` og
  `docs/changelog.md`.
- **Omsegmenteringens fortrydelsesvindue lukker** ved overførslens GO (`docs/decisions.md`, 2026-10-01).
- **Oprydning** af stand-in-, probe- og rehearsal-baser, dumps og forældede private mapper: kun efter
  måling og projektejerens ja. Prod-dumpet og `go-env.txt` bevares.
