# Forældrematch — status og arbejdsliste

Værktøj til det redaktionelle arbejde med at matche forældre på tværs af
DAA 1939 og DAA 2018-20. Baggrund og tal:
`docs/reviews/kryds-udgave-udfyldning-scoping-2026-07-26.md`.

Begge scripts er **read-only** mod prod. De genimplementerer ikke
sammenlægningsreglerne, men kører den rigtige `collapseSameAs` fra
`packages/core` — det er hele pointen: to forsøg på at gengive reglen i SQL
gav upålidelige tal.

```bash
Rscript tools/foraeldrematch/dump-prod.R      # → tmp/collapse-input.json
npx vite-node tools/foraeldrematch/status.ts  # hvor mange er tilbage?
npx vite-node tools/foraeldrematch/byg-liste.ts  # → work/arbejdsliste-foraeldrematch.md
```

`dump-prod.R` bruger `SUPABASE_*` fra `~/.Renviron`.
Arbejdslisten skrives til `work/` (gitignoreret), fordi den indeholder
persondata. Nulevende personer udelades helt af listen (invariant 8) og
skal håndteres direkte i redaktør-fladen.

Kør `status.ts` undervejs: `KARANTÆNEREDE grupper` falder efterhånden som
forældrene matches.
