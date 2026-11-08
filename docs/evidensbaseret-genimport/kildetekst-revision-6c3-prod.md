# Færdigbevis: trin 6c-3 i prod — 2018-20's A6b-rest (2026-11-08)

Spec: `docs/superpowers/specs/2026-11-07-trin6c3-a6b-resten-design.md` §6. Plan: `docs/superpowers/plans/2026-11-07-trin6c3-a6b-resten.md`
Task 9. Runbook: `docs/runbooks/trin6c3-prod.md`. Kun antal, nøgler og hashes; ingen tekst eller værdier.

## Forløb

| Trin | Resultat |
|---|---|
| Repo | `main` `bdcb4184` (PR #305 + #307 + #308; #308 merget ved head `88f007a7`) |
| `maal` (før) | `tilstand=foer`, `andre=049163332f67…`, `personas=1395`, 1,3 s (stand-in 0,6 s) |
| Dump før DDL | `daa-prod-20261108183045-6c3.dump`, sha `9f3d72f6…`, age `fb421c1f…`, SFTP-rundtur ok; restore-hash `2ab09589…` og vinduesaftryk `dbbb4eb4…` = stand-in `c3h`'s før-tilstand |
| DDL (GO `432b5680`) | `T6C3_VINDUE_OK sammenligning=eksakt linjer=134`, `T6C3_APPLY_DDL_OK tilstand=ddl blok=1e8d9553eb3806df`, 11,9 s |
| Grants og lint | runneren: ingen EXECUTE for anon/authenticated på de fire private funktioner, ingen grants på kvitteringstabellen. `get_advisors` ikke kørt (MCP'en er logget ind på en anden organisation); lint-tjek på `c3h` (samme indhold og blok): alle seks 6c-3a-funktioner og triggerfunktionen har fast `search_path`, ingen API-rolle har EXECUTE, kvitteringstabellen har RLS og ingen ACL, `anon`/`authenticated` har ikke USAGE på `private`, 0 `public`-tabeller uden RLS |
| `maal` (ddl) | `tilstand=ddl`; `REV_MAAL` = den fastlåste `REV_DDL` |
| Dump før data | `daa-prod-20261108184046-6c3.dump`, sha `d22ffbfa…`, age `f1ad7f6c…`, SFTP-rundtur ok; restore-hash `efc3b453…`, vindue `1c82e0ce…` = `c3h` i ddl. Fortrydelsens grundlag |
| Data (GO `1b94d057`) | alle linjer som generalprøverne; `T6C3_APPLY_DATA_OK tilstand=faerdig tal=1,58,10,75,15,1395,13,4,1,3,16,74`, 168 s (stand-in ca. 80 s) |
| `verify` | `T6C3_VERIFY_OK kvittering genbundet=14 genfundet=30 ikke_genfundet=28 tilbagetrukket=2 andre=049163332f678113` |

Fulde B1-hashes: `database-current-state.md` §23.

## Spec §6

- **Tekst og klausuler:** revisionen er finaliseret (`T6C3_B_APPLY rev operationer=10 status=finalized`, kanonisk
  uændret): 58 nøgler `superseded`, 10 tekstversioner. 75 nye forslag (`key_version 2`) på de 9 poster med persona;
  forslagsmanifest `9592824354b4c926` = det bundne. Eligibility-ledgeren efter revisionen = den bundne (`22080ca1…`).
  At de 11 linjer står i de nye tekstversioner, og at hvert nyt klausulsæt er delstrenge af dem, er ikke målt særskilt
  i prod; det følger af, at revisionens og forslagenes indhold er byte-ens med generalprøvernes (kanoniske hashes).
- **Afstemning:** kvitteringen har 74 rækker = 58 nøgler + 16 bindinger, hver med udfald: `genbundet` 14,
  `tilbagetrukket` 2 (projektejerens svar, `tilbagetraek-ark` `974a389d…`), `genfundet` 30, `ikke_genfundet` 28.
  Writeren afviser en mængde, der ikke dækker revisionen præcist (Review Focus 6).
- **Personas:** 0 nye; de 3 eksisterende ægtefælle-personas er genbrugt som parter (`spouse_personas: 3`,
  `person_creates: 0`); personas 1.395 før og efter.
- **Narrativer:** narrativ-hash `eee1c9fb…` og publiceringshash `56e5c434…` er uændrede fra før data til efter.
- **Læseren (`REV_MAAL` efter):** af de 9 genbundne fakta er 8 bundet til bogens post og 1 vist som import
  (tilbagetrukket), 0 uden kilde. De 7 familiebindinger ligger på 6 familier; målingens `familiekilder_7` gik fra 7
  til 6 (én familiebinding tilbagetrukket). Som forventet (`REV_FAERDIG`).
- **Stikprøver som anon:** gennem prods API med appens anon-nøgle, som læserfladen bruger (ikke i en browser):
  `public_person_facts` for de 5 personer (ét kald pr. person, langsomste 0,97 s mod anon-grænsen 3 s) viser 9 af de
  9 fakta, 8 bundet med kilde »DAA 2018-20 · <post>« (I-9, I-11, I-33, I-44, I-89), 1 import.
  `public_family_sources` for de 6 familier (0,20 s) viser kildelinje på alle 6 (I-11, I-32, I-44, I-89, III-37).
- **Komparatoren (149b)** er ikke brugt som bevis (spec §6): den læser forekomstens tekst og viser fortsat de 10 som
  afvigende; afvigelsen er forklaret af tekstversionen.

## Frys og fortrydelse

Frysen gik fra dumpet før DDL til `verify`. Vinduesvagten (Codex' diffreview, fund 1) var eksakt grøn før DDL og før
data, så intet andet blev skrevet i vinduerne. Fortrydelse er nu kun mulig ved restore af data-dumpet, så længe der
ikke er skrevet andet i prod siden; `fortryd` stopper selv, hvis det er sket (`T6C3_VINDUE_BRUDT`).

## Ikke gjort

- Ingen browserstikprøve (spec §6 nævner browseren; API-kaldene er de samme, som siden laver).
- Kvitteringswriterens tilbagetræk-vagt (diffreviewets fund 2) rettes før 6m's K-sager.
