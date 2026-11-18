# Runbook: fuld personsletning i prod — sletteliste 18/11

Plan: `docs/superpowers/plans/2026-11-14-fuld-personsletning.md` (Task 13). Spec og beslutninger:
`docs/decisions.md` 2026-11-14 (fuld personsletning) og 2026-11-17 (R41/R42 »prøv igen«).

## Udgangspunkt

- **Der er ingen DDL i denne ceremoni.** Al personsletningens DDL (#369, #377, #380) kom i prod med record_persona-
  ceremonien 18/11: main `aca139a0` (PR #382), halen fra `-- Fuld personsletning (2026-11-14)` til filens slutning
  (sha `af15ee3e…`) og `db-rls.sql` i én transaktion. **Note 72 (familie 54)** blev slettet i samme transaktion efter
  projektejerens betingelser fra 14/11 (eneste forældreløse polymorfe række, `target_type='family'`,
  `target_id=54`). Derfor har denne runbook hverken GO-koder, `apply-ddl` eller `fortryd-ddl`.
- **Sletningen kan ikke fortrydes.** Den eneste vej tilbage er dumpet, der tages lige før (trin 2). Fortryd-DDL kan
  ikke genskabe en udført sletning.
- **Sletteliste (projektejeren):** 1791, 963, 1795, 1620, 1135, 940, 1814 (16/11) og 1823, 1824 (18/11: dubletter af
  1613/1614, der kun var gift med fejlprofilen 1791). Runneren afviser andre id'er.
- **Runner:** `~/.private/5ab-overfoersel/43-personsletning.sh` (aldrig i repoet). Kaldes fra operatørens cwd (repo-
  roden) med `/bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 43-personsletning.sh <tilstand>`. Den skriver aldrig i
  basen. Count/rest/db-verify læses med `git show` ved den fastlåste commit `PS_COMMIT_FAST` (sættes til merge-commit
  af Task 13-PR'en, før runneren bruges i prod).

## Tidsgrænsen (målt 18/11)

`authenticated` har `statement_timeout=8s` i prod, `authenticator` `lock_timeout=8s`
(`43-personsletning.sh roller`). Funktionens egen `set_config('statement_timeout','30s',true)` forlænger IKKE kaldet:
timeren startes, når sætningen begynder (R4). Et klik i Redaktion har altså 8 s.

| Måling | Stand-in (prod-dump 18/11) | Prod (`tid`, læse-kun) |
|---|---|---|
| Forhåndsvisning, varm | 0,87–0,95 s | 1,2–1,5 s typisk, udsving til 3,9 s |
| Forhåndsvisning, første kald i kold base | 0,9–1,2 s | **> 8 s (timeout)** |
| Sletning + commit | 2,3–3,0 s (963 er langsomst) | ikke målt (skriver) |

Sletningen tager ca. 2,6× forhåndsvisningen, så den forventes på 3–4 s i prod. Et udsving kan ramme 8 s. Så rulles
alt tilbage, og Redaktion viser »Det tog for lang tid — intet er slettet. Prøv igen.« (57014, Task 13-PR'en).

## Generalprøver (stand-in fra prod-dump `daa-prod-20261118164838-laes.dump`, sha `111c3e34…`)

1. **1791** (generalprøve 1): `db-migrations.sql` + `db-rls.sql` 1× og 2× ændrer intet i funktioner, triggere eller
   politikker (kun ejer-ACL fra den lokale `--no-owner`-restore). Fuld `db-verify.sql` grøn før og efter. Som
   `authenticated` med 8 s: forhåndsvisning 0,94 s (32 steder, 0 blokeringer, 0 advarsler, familie 742+743 slettes),
   sletning 2,49 s, commit 1 ms. `count.sql` = 0. Rækkediff mod forhåndsvisningen: alle 33 slettede rækker står i
   listen, intet andet slettet; eneste anden ændring er `identity_mutation_generation`. De øvrige otte på listen:
   0 blokeringer, sletning 2,3–3,0 s.
2. **1846 fra den aktiverede kørsel 18/8** (generalprøve 2, valgt ved tal): sletning 2,5 s; `db-verify.sql` grøn.
   Rækkediff = forhåndsvisningens `slet` plus personaens nye version 2 med `not_a_person` (+ ny identitetshændelse),
   som designet. Kørslen kan allerede i dag ikke fortrydes (`red_reverse_reimport` → `REIMPORT_WRITER_REVERSAL_INVALID`
   både før og efter), så forhåndsvisningen viser korrekt ingen `fortrydelse_mistes` (R30: kun tab af en virkende
   fortrydelse advares).
3. **Runner-øvelse** (frisk kopi, via `koer.zsh` fra repo-roden): `foer 1791` → sletning → `efter 1791` → `verify`, alle
   OK; `efter` før sletningen stopper; id uden for listen afvises.

**Rest-kontrollens forventede fund for 1791:** 1791's »navn« (»fyenske Rytterreg.)«) er et brudstykke af DAA 1939's
tekst om Conrad Reventlow (1198). Navnet står derfor bagefter (a) i fire `reimport_event`-kvitteringer af typen
`source_evidence`, kun i `verbatim_text` (bogens lag, løftet som `S41b/bog`), og (b) i narrativ **867** (kilde 3 =
DAA 1939, person 1198) — bogtekst, ikke redaktørtekst, derfor ikke i forhåndsvisningens `til_kontrol`. `efter`
udskriver `q9 narrativ: 867 | kilde 3 | person 1198`. Alt andet end netop det er et fund.

## Ceremoni pr. person (1791 først)

Forudsætning: Task 13-PR'en er merget, Vercel har bygget main (57014-teksten), `PS_COMMIT_FAST` er sat til
merge-commit'en, og `origin/main` har ingen nyere SQL-ændringer end den commit (memory: parallel DB-ændring).

1. **Opvarmning og blokeringer** (læse-kun): `… 43-personsletning.sh tid`. Forventet: 0 blokeringer for alle;
   advarsler 963:2, 1620:2, 940:2, 1814:1, resten 0. En `TIMEOUT` i første kald er kold start; kør igen.
2. **Dump lige før** (det eneste fortryd): `… koer.zsh 39-laesedump.sh` → `LAESEDUMP_OK fil=… sha256=…`.
3. **Før-måling:** `… 43-personsletning.sh foer <pid>` → `PURGE_FOER_OK`. Før-filen ligger i
   `~/.private/5ab-overfoersel/prod/personsletning/<pid>/`.
4. **Projektejeren sletter i Redaktion:** personen → »Slet helt«. Gennemgå forhåndsvisningen (for 1791: 32 steder,
   0 blokeringer, 0 advarsler, familie 742 og 743 slettes, 40 til kontrol). Skriv id'et og slet.
   - »Det tog for lang tid — intet er slettet. Prøv igen.« eller »Noget ændrede sig undervejs …«: hent ny
     forhåndsvisning og prøv igen. Intet er slettet.
   - »Blokering: …«: stop og vis beskeden til hovedsessionen.
5. **Udbakken:** »Filer der venter på sletning« skal være tom eller vise de filer, sletningen frigjorde (1791 har
   ingen medier). Ved filer: kør oprydningen dér; `Rscript R/media-janitor.R` (uden flag = læse-kun) skal derefter vise
   0 forældreløse for de stier.
6. **Efter-måling:** `… 43-personsletning.sh efter <pid>` → `count: nul-kontrol OK`, `REST_OK` og `PURGE_EFTER_OK`.
   Linjer `tilbage (til kontrol/bevaret)` og Q9-linjer afstemmes mod tabellen nedenfor.
7. **Verify:** `… 43-personsletning.sh verify` → `PURGE_VERIFY_OK` (personsletningens afsnit af `db-verify.sql`,
   Task 8a + Task 10, i en READ ONLY-session).

Gentag 2-7 for de næste id'er. 1823 og 1824 slettes efter 1791 (deres eneste familier forsvinder med 1791). Et dump
kan dække flere personer i træk; det gendanner så dem alle.

## Efter-kontrollen (rettet under ceremonien 18/11)

- **Tælleren** gater med `count.sql`'s egen nul-kontrol (`purge_assert_nul`) og de før-mængder, `foer` gemmer
  (`personas.json`, `families.json`). Heuristik- og bevar-steder (S44, S46, S52, S53, S54b, S57, S58*) står ikke på
  dens liste og vises som `tilbage (til kontrol/bevaret)`. Første version krævede 0 overalt og stoppede på 1823's
  S58c (matchkørsler for 815 med 1823 som klyngemedlem: andres historik, til kontrol, ikke sletning).
- **Navnefæller:** `foer` tæller andre personrækker med navnet. Er der nogen, køres rest-kontrollen på id og link
  alene, fordi navne-delstrengen ikke kan skelne P's rester fra navnefællernes data (1823/1824 er dubletter af
  1613/1614; 1795's navn står i 1806 andre rækker). Id-tælleren er uændret streng.
- **Bogens udtræk:** S41b/bog løfter også `source_evidence.payload.legacy_payload` (1620 står som `partner_navn` i en
  vielses udtræk). Kræver commit'en fra rettelses-PR'en; runneren fastlåses til den.

## Forventede tal pr. person (øvelse på stand-in i listens rækkefølge, 18/11)

| id | steder | blok. | advarsler | familier slettes | til kontrol | navnefæller | `tilbage` | Q9 (bogtekst) |
|---|---|---|---|---|---|---|---|---|
| 1791 | 32 | 0 | – | 742, 743 | 40 | 0 | – | narrativ 867 (1198) |
| 1823 | 25 | 0 | – | – | 23 | 1 | S58c=5 | – |
| 1824 | 20 | 0 | – | – | 19 | 1 | – | – |
| 963 | 1118 | 0 | kontrolkoersel_failer ×2 | – | 15 | 1 | S44=2, S52=1, S54b=1, S57=7 | – |
| 1795 | 14 | 0 | – | – | 15 | 1806 | – | – |
| 1620 | 199 | 0 | kontrolkoersel_failer ×2 | – | 6 | 0 | – | narrativ 875 (1206) |
| 1135 | 818 | 0 | – | – | 91 | 49 | S53=1 | – |
| 940 | 1132 | 0 | kontrolkoersel_failer ×2 | – | 64 | 20 | – | – |
| 1814 | 10 | 0 | kontrolkoersel_failer ×1 | – | 9 | 0 | – | narrativ 596 (927) + én citation |

`kontrolkoersel_failer`: en bestået identitetskontrolkørsel holder ikke længere efter sletningen, fordi personen
indgik i den. Det er en advarsel, ikke en blokering; kørslen må laves om, hvis dens resultat skal bruges igen. Tal i
steder kan afvige en smule i prod, hvis data er ændret siden dumpet; afvigelser i blokeringer eller nye advarsler er
et stop.

## Færdigbevis (spec §7)

Pr. person: `foer`/`efter`-linjerne, forhåndsvisningens tal fra dialogen og `verify`. Samlet: dumpenes sha og
`tid`-tabellen. Ingen navne eller rækkeindhold i beviset; kun id'er, antal og tabelnavne.
