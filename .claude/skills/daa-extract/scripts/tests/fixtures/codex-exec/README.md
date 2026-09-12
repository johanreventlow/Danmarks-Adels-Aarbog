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

## Fejltaksonomien (Task 3) — **alle syntetiske**

Spec §6.3 kræver seks fejltyper. **Ingen af dem er observeret.** Filerne nedenfor er
håndskrevne ud fra den dokumenterede hændelsesform, og hver bærer strengen
`SYNTETISK FIXTURE` i sin egen tekst, så en læser ikke kan forveksle dem med en
rigtig kørsel.

| Fil | Type | Grundlag |
| --- | --- | --- |
| `failure-quota-exhausted.jsonl` | `quota_exhausted` | **Rekonstrueret.** Spec §6.5 kalder proben 2026-09-06's `turn.failed` »fixturen«, men den rå JSON findes ikke i repoet og blev eftersøgt forgæves. Formen er gengivet efter beskrivelsen — ikke efter et gemt svar. |
| `failure-model-refusal.jsonl` | `model_refusal` | Syntetisk. |
| `failure-schema-violation.jsonl` | `schema_violation` | Syntetisk. |
| `failure-timeout.jsonl` | `timeout` | Syntetisk; timeout afgøres i øvrigt af sømmen, ikke af strømmen. |
| `failure-unknown.jsonl` | `unknown` | Syntetisk — en `turn.failed` uden genkendelig `error.type`. |

Bliver en af typerne observeret i en rigtig kørsel, så **erstat** filen og ret denne
tabel. Skellet mellem observeret og opdigtet er hele pointen med at føre det.

## Hvad fixturene er til

4.3a's usage-parser, fejlklassifikation og gate-tests kan køre uden at bruge
Codex-kvote. Testene injicerer en søm i stedet for at starte CLI'en, og
standardsømmen i testmiljø kaster, hvis den alligevel skulle blive kaldt.

Kun **én** ting i denne mappe er et observeret modelsvar: `turn.completed` med
`usage`. Alt om fejl er opdigtet. Hold det skel.
