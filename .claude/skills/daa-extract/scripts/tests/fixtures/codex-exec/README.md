# Observerede `codex exec --json`-hændelsesstrømme

Fanget under dagsværk 4.3a (#147) mod `codex-cli 0.153.4` / `gpt-5.6-terra`.
Alt indhold er syntetisk eller trivielt. Ingen persondata, ingen tekst fra
`work/` eller databasen.

## Isolationsgaten (denne gren)

| Fil | Kørsel |
| --- | --- |
| `sandbox-gate-denies-model.jsonl` | Deny-baseret profil: modellen nægtes adgang til en spærret mappe. |
| `sandbox-allowlist-denies-model.jsonl` | **Allowlist-profil** (hele hjemmemappen lukket): modellen bedt om at læse repoets `CLAUDE.md` med flere metoder, svarer `KAN IKKE LÆSE`. |

Profil og adgangstest ligger i `.claude/skills/daa-extract/scripts/sandbox/`.
Rapport: `docs/evidensbaseret-genimport/runner-usage-probe-147-4-3a.md`.

## Forbrugsproben (kommer fra PR #179)

Grenen `feat/147-runner-forbrugsprobe` bidrager med fire filer mere til samme
mappe — `turn-completed-with-usage.jsonl`, `baseline-with-user-config.jsonl`,
`baseline-ignore-user-config.jsonl` og `sandbox-canary-read-outside-cwd.jsonl`.
De to grene er skrevet parallelt, så denne liste samles, når begge er merget.

## Hvad fixturene er til

4.3a's usage-parser og gate-tests kan køre uden at bruge Codex-kvote. Bemærk
skellet: `turn.completed` med `usage` er **observeret**; fixtures for de øvrige
fejltyper i §6.3 (`model_refusal`, `schema_violation`, `timeout`,
`validation_failed`) vil være **syntetiske**, og `quota_exhausted` er
**rekonstrueret** ud fra den dokumenterede form — den rå JSON fra proben
2026-09-06 findes ikke i repoet. Det skel skal holdes, også når fixturene
vokser.
