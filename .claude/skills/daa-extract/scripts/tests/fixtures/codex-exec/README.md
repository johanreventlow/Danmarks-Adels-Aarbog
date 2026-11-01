# Observerede `codex exec --json`-hændelsesstrømme

Fanget 2026-09-11/12 under dagsværk 4.3a (#147) mod `codex-cli 0.153.4` /
`gpt-5.6-terra`. Rapport:
`docs/evidensbaseret-genimport/runner-usage-probe-147-4-3a.md`.

Fixturene gør, at 4.3a's usage-parser, fejlklassifikation og gate-tests kan køre
**uden at bruge Codex-kvote**. Testene injicerer en søm i stedet for at starte
CLI'en, og standardsømmen i testmiljø kaster, hvis den alligevel skulle blive
kaldt.

## Forbrugsproben

| Fil | Kørsel |
| --- | --- |
| `turn-completed-with-usage.jsonl` | Fuld probe: syntetisk post + `--output-schema`. Fire hændelser, `usage` i `turn.completed`. |
| `baseline-with-user-config.jsonl` | Tom prompt med brugerkonfiguration indlæst (21.554 input-tokens). |
| `baseline-ignore-user-config.jsonl` | Samme kald med `--ignore-user-config` (15.266 input-tokens). |

## Isolationsgaten

| Fil | Kørsel |
| --- | --- |
| `sandbox-canary-read-outside-cwd.jsonl` | Kanarietest **før** gaten: modellen eksekverer en shell-kommando og læser en fil uden for `-C`. Viser, at `--sandbox read-only` ikke er en læsegrænse. |
| `sandbox-gate-denies-model.jsonl` | Deny-baseret profil: modellen nægtes adgang til en spærret mappe. |
| `sandbox-allowlist-denies-model.jsonl` | **Allowlist-profil** (hele hjemmemappen lukket): modellen bedt om at læse repoets `CLAUDE.md` og `~/Library/Keychains` med flere metoder, svarer `KAN IKKE LÆSE`. |

Profil-skabelon og adgangstest ligger i
`.claude/skills/daa-extract/scripts/sandbox/`.

## Fejltaksonomien — **alle syntetiske**

Spec §6.3 kræver seks fejltyper. **Ingen af dem er observeret.** Filerne nedenfor
er håndskrevne ud fra den dokumenterede hændelsesform, og hver bærer strengen
`SYNTETISK FIXTURE` i sin egen tekst, så en læser ikke kan forveksle dem med en
rigtig kørsel.

| Fil | Type | Grundlag |
| --- | --- | --- |
| `failure-quota-exhausted.jsonl` | `quota_exhausted` | **Rekonstrueret.** Spec §6.5 kalder proben 2026-09-06's `turn.failed` »fixturen«, men den rå JSON findes ikke i repoet og blev eftersøgt forgæves. Formen er gengivet efter beskrivelsen — ikke efter et gemt svar. |
| `failure-model-refusal.jsonl` | `model_refusal` | Syntetisk. |
| `failure-schema-violation.jsonl` | `schema_violation` | Syntetisk. |
| `failure-timeout.jsonl` | `timeout` | Syntetisk; timeout afgøres i øvrigt af sømmen, ikke af strømmen. |
| `failure-unknown.jsonl` | `unknown` | Syntetisk — en `turn.failed` uden genkendelig `error.type`. |
| `failure-quota-no-type.jsonl` | `quota_exhausted` | Syntetisk efter beskrivelsen af produktionsfejlen (en `turn.failed`, hvis `error` mangler `type`; kun `message` med »usage limit« bærer kvotefejlen) — ikke et gemt svar. Ingen kildetekst. |

Bliver en af typerne observeret i en rigtig kørsel, så **erstat** filen og ret
tabellen.

## Hold skellet

Alt indhold er syntetisk eller trivielt (»Svar kun med ordet: ok«). Ingen
persondata, ingen tekst fra `work/` eller databasen.

Kun **ét** modelsvar her er en rigtig besvarelse af en rigtig opgave:
`turn.completed` med `usage`. Alt om fejl er opdigtet, og gate-filerne er
afvisninger, ikke besvarelser. Det skel er hele grunden til at føre listen — det
skal holdes, også når fixturene vokser.
