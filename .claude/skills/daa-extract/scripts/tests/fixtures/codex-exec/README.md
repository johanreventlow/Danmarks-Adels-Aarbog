# Observerede `codex exec --json`-hændelsesstrømme

Fanget 2026-09-11 under forbrugsproben til dagsværk 4.3a (#147) mod
`codex-cli 0.153.4` / `gpt-5.6-terra`. Rapport:
`docs/evidensbaseret-genimport/runner-usage-probe-147-4-3a.md`.

| Fil | Kørsel |
| --- | --- |
| `turn-completed-with-usage.jsonl` | Fuld probe: syntetisk post + `--output-schema`. Fire hændelser, `usage` i `turn.completed`. |
| `baseline-with-user-config.jsonl` | Tom prompt med brugerkonfiguration indlæst (21.554 input-tokens). |
| `baseline-ignore-user-config.jsonl` | Samme kald med `--ignore-user-config` (15.266 input-tokens). |

Alt indhold er syntetisk eller trivielt (»Svar kun med ordet: ok«). Ingen
persondata, ingen tekst fra `work/` eller databasen.

Fixturene findes, så 4.3a's usage-parser kan testes uden at bruge Codex-kvote.
