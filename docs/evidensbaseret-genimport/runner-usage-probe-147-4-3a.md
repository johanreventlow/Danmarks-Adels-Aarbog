# Forbrugsprobe til dagsværk 4.3a (#147)

**Kørt:** 2026-09-11. **Formål:** at afgøre spec §6.6's eneste ubekræftede
antagelse — rapporterer `codex exec --json` reelt tokenforbrug? Proben
2026-09-06 kunne ikke svare, fordi turen døde på kvote (`turn.failed`).
Spec'en er eksplicit: kan CLI'en ikke rapportere forbrug, **stopper 4.3 med et
navngivet fund**.

**Svar: ja.** `turn.completed` bærer et `usage`-objekt. 4.3 er ikke blokeret.

## Miljø

| | |
| --- | --- |
| CLI | `codex-cli 0.153.4` (samme version som proben 2026-09-06) |
| Model | `gpt-5.6-terra` (profilens frosne model, valg 1) |
| Flag | `--sandbox read-only --ephemeral --ignore-rules --skip-git-repo-check --json --output-schema -o`, stdin lukket |

Alle flag fra spec §6.2 findes og accepteres af 0.153.4.

## Datagrundlag: syntetisk, ikke-identificerende

Proben brugte en **opdigtet** post (»Testperson Opdigtsen«, Fiktivby, årstal
1800-1870) med fire nummererede klausuler. Ingen tekst fra `work/`,
`work_1939_stamtavle/` eller databasen forlod maskinen; udelukkelsesreglerne i
§9.2 er derfor ikke i spil for denne probe. Prompt-SHA-256:
`92d03bfce05bd5ca76f7017b8d81496d6da1a15f2d71aecd81b62701b6cdce85`.

## Hændelsesstrøm

`--json` udsendte fire hændelser: `thread.started`, `turn.started`,
`item.completed`, `turn.completed`. Proben 2026-09-06 nåede kun til
`turn.failed`; `item.completed` og `turn.completed` er dermed nye, observerede
hændelsestyper, som runneren i 4.3a kan bygge på.

## Forbrugsrapportering (hovedfundet)

`turn.completed` bærer:

```json
{"type":"turn.completed","usage":{"input_tokens":21801,"cached_input_tokens":0,
 "cache_write_input_tokens":0,"output_tokens":218,"reasoning_output_tokens":84}}
```

Fem felter, herunder `reasoning_output_tokens` særskilt. Spec §6.4's regnskab
(»token-tal fra Codex' JSON-hændelser«) kan implementeres som beskrevet.

## To målinger, der ændrer budgetantagelsen

En ekstra baseline-kørsel (prompten »Svar kun med ordet: ok«) gav:

```json
{"input_tokens":21554,"cached_input_tokens":11008,
 "cache_write_input_tokens":0,"output_tokens":5,"reasoning_output_tokens":0}
```

1. **Overheadet er næsten hele regningen.** Et tomt kald koster 21.554
   input-tokens; vores fulde prompt + record kostede 21.801. Selve
   nyttelasten var altså ~250 tokens — **1,1 %** af kaldet. Resten er CLI'ens
   egen systeminstruktion, som sendes pr. kald. Konsekvens for §6.4's
   »batches 5-10 records«: batchning er ikke en optimering, den er
   bærende for økonomien. Én record pr. kald ville betyde ~21,5k
   input-tokens × 591 records ≈ 12,7 M tokens, hvoraf under 1 % er data.
2. **Prompt-caching virker på tværs af kald.** Andet kald rapporterede
   `cached_input_tokens: 11008` — godt halvdelen af overheadet blev
   genbrugt. Runnerens svar-cache (§6.3) har dermed en gratis allieret i
   udbyderens egen cache, men kun hvis kaldene ligger tæt nok i tid.
   Effekten bør måles pr. batch i 4.3b, ikke antages.

## Output-skemaet

`--output-schema` blev respekteret: sidste besked var ren JSON, der validerede
mod det medsendte skema, med fire claims der hver citerer en klausul-ordinal.
Det bekræfter, at kontrakten `evidence-claims-1.0` (§6.1) kan håndhæves på
CLI-niveau og ikke kun i Python-validatoren.

## Hvad proben **ikke** viser

- Fejltaksonomien (§6.3) er uprøvet her. `quota_exhausted` har stadig kun
  fixturen fra 2026-09-06; `model_refusal`, `schema_violation`, `timeout` og
  `validation_failed` mangler observationer. De hører til 4.3a's plan.
- Priser (§6.4) er ikke aflæst; profilens `pricing`-nøgle findes ikke endnu og
  kræver en ny profilversion med GO.
- Intet er kørt mod rigtige records. Det er 4.3b og kræver særskilt GO med
  hash-bundet udelukkelsesliste.

## Konsekvens

Blokeringen »4.3a's Codex-forbrugsprobe udestår« i `status.md` er hermed lukket.
Planerne for 4.3-4.5 kan skrives. Plan 4.3a bør bære de to målinger ovenfor som
dimensionerende antagelser og begrunde batchstørrelsen på overheadmålingen frem
for på spec'ens oprindelige skøn.
