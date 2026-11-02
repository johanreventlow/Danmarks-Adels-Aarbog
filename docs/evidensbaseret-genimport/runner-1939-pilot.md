# Runneren på 1939: pilot (trin 6c-1, Task 8 step 2)

Spec: `docs/superpowers/specs/2026-11-01-trin6c1-runner-og-identitet-design.md` §4.5. Plan:
`docs/superpowers/plans/2026-11-01-trin6c1-runner-og-identitet.md` Task 8. Kørt 2026-11-01 lokalt mod stand-in'en
`daa5ab_ddl_standin_20261101190252_6c1` (kopi af `_6bm` = prod efter 6b-B, plus 6c-1's `db-migrations.sql`), aldrig mod
prod. Rapporten indeholder record-antal, koder og hashes — ingen kildetekst og ingen claim-værdier.

## Kort svar

30 af 30 poster dækket (21 hele, 9 delvise), 163 gyldige claims, 0 fejl, 0 `tool_use`, 0 navne med titelord eller
»til <gods>«. Andelen af afviste claims (13 af 176, 7,4 %) er højere end 2018-20's fulde kørsel (203 af 3.961, 5,1 %),
så gatens ene tal er ikke opfyldt efter ordlyden. Forskellen er 13 mod forventet ca. 9 på 176 claims; afviste claims
når aldrig databasen. Afgørelse: se »Gaten«.

## Grundlag

| | |
| --- | --- |
| Stand-in | `daa5ab_ddl_standin_20261101190252_6c1`; `T6C1_MAAL tilstand=a forslag_k3=0 identiteter_k3=8 afventer=555` |
| Eligibility-ledger | `exclusion-1939-v1`: 592 records, **500 `eligible`**, 92 `excluded` (63 privatlivsregler + 21 uden publiceret binding + 8 uden helpost); sha `cbed2e7f…` |
| Runner-input | 584 records, 912 klausuler, 8 uden helpost, 0 uden entydig persona; sha `0f9c5cd9…` |
| Udvalg | `--limit 30 --seed 6c1-pilot-v1`, strata `eligible-pilot-v1` (klausulantal × postlængde, medianer), `6f87be65…`; 2 bundter (25 + 5) |
| Manifest (GO) | `17de7c54a30b74d0f75df882df4056df191f24fcf0039244481ddb90928fde5c`; dagsværk `6c-1`, profil `daa-1939-v2` 1.4.0, prompt 1.1.0 `7affb8f3…`, `gpt-5.6-terra`, kontrakt `evidence-runner-1.4`, codex-cli 0.164.0 |
| Sandbox | `gate-access-test.sh` `GATE_OK` på codex-cli 0.164.0 (før hvert kald) |

## Kørslen

- **Første forsøg fejlede 30/30 som `unknown` med 0 tokens.** `codex` på PATH var terminalens shim under
  `~/.cmuxterm/`, som Seatbelt-profilen spærrer (rc 126, »Operation not permitted«). Intet blev sendt. Med PATH uden
  shim'en bruges `~/.local/bin/codex` (samme version, åben i profilen); et syntetisk kald gik igennem. Runbooken skal
  køre runneren med en sådan PATH.
- **Andet forsøg:** bundt_01 25/25 dækket (9 delvise, 144 claims, 462.888 input-tokens), bundt_02 5/5 (19 claims,
  94.191 input-tokens). I alt 557.079 input-tokens (151.808 fra cache), 16.559 output-tokens (6.814 tænkning).
- **Afvisninger:** 10 `RUNNER_CLAIM_VALUE_INVALID`, 3 `RUNNER_CLAIM_PREDICATE_INVALID`.
- **Prædikater** (antal poster med mindst ét claim): `person.name` 23, `person.death` 19, `person.birth` 16,
  `relation.marriage` 14, `mention.place` 12, `person.estate` 12, `person.title` 9, `person.education` 6,
  `person.office` 5, `person.occupation` 4, `person.burial` 3, `event.marriage` 2, `person.baptism` 2,
  `person.decoration` 2, `person.residence` 2, `relation.parent` 2, `event.acquisition` 1, `mention.person` 1.
- **7 af 30 poster gav intet `person.name`.** Deres personas får ved C ingen navnefortolkning og ender sandsynligvis
  som kort (spec §4.7 pkt. 4).

## Gaten (spec §4.5 pkt. 1)

| Krav | Pilot | |
| --- | --- | --- |
| 0 fejlede poster efter genforsøg | 0 | ✅ |
| Andel afviste claims højst som 2018-20's (5,1 %) | 7,4 % (13/176) | ❌ efter ordlyden |
| 0 `tool_use` | 0 | ✅ |
| 0 `person.name` med titelord | 0 af 29 | ✅ |
| Forslagsregnskabet går op | måles ved ingest (step 4) | — |

Afvisningerne er runnerens kontraktværn (værdi eller prædikat uden for skemaet); de stopper fejlbehæftede claims, før
de ingestes. Om 7,4 % skyldes 1939's ældre retskrivning og OCR eller blot den lille stikprøve, kan piloten ikke afgøre.
Afgørelsen om at fortsætte til den fulde kørsel ligger hos projektejeren sammen med Codex-kvoten (se næste).

## Næste

Den fulde kørsel af de øvrige 470 poster: ca. 8,7 mio. input-tokens anslået fra piloten (18.600 pr. post), dvs.
væsentligt over 2018-20's 6,2 mio. Den kan ramme Codex-kvoten; runneren stopper rent ved kvotefejl og fortsætter fra
cachen.
