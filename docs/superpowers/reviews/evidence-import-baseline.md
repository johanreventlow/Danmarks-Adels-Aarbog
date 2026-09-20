# Evidensimport: reproducerbar baseline

**Kode-snapshot:** `eb054ca8f77ed7cf5971c8494c823ca10e8b945f`
**Worktree:** `feat/evidensbaseret-genimport`
**Dato:** 2026-08-02
**Status:** kodebaseret snapshot; endnu ikke sammenholdt med en lokal database.

## Testbaseline

| Kommando | Resultat | Klassifikation |
|---|---:|---|
| `/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts` | stopper under collection: 375 testemner, 1 fejl | eksisterende arbejdsmateriale mangler |
| `npm test --workspace packages/core -- --run` | 26 filer, 403 tests bestået | grøn |
| `npm test --workspace web -- --run` | 25 filer / 276 tests bestået; 30 suites fejler | worktree-testmiljø mangler |

### Python-fejl

`test_evidenspas_v2.py` læser den ignorerede arbejdsfil
`work_1939_stamtavle/identitetsregister-1939.json`, som ikke findes i den nye
worktree. Dette er ikke behandlet som en grøn baseline og bliver ikke løst ved
at indlæse eller rekonstruere bogdata i Fase 0.

### Web-fejl

De 30 fejlede suites falder i to kendte miljøklasser:

1. `@testing-library/react` kan ikke resolves i worktree-installationen.
2. Tests, som indlæser `web/src/supabase.ts`, mangler de bevidst dummy
   `VITE_SUPABASE_URL` og `VITE_SUPABASE_ANON_KEY`.

Ingen produktions- eller testkode er ændret for at gøre denne baseline grøn.
Når en senere fase berører web, etableres en reproducerbar testopsætning og
resultatet sammenlignes med denne baseline.

## Effektivt struktursnapshot

- `source` er den bibliografiske kilde/udgave: `schema.sql:32`.
- Den nuværende kanoniske `person` og bogens eksterne identitet ligger i
  `schema.sql:125` og `schema.sql:141`; `person_external_id` bærer endnu
  `(person_id, source_id)`, rå `linje`/`nr`, valgfri `record_key` og
  `slaegtled_lokal`, `slaegtled_gennem`, `kuld`.
- Den nuværende `lineage` ligger i `schema.sql:574`; den må ikke forveksles
  med den planlagte slægt eller et kildespecifikt nummereringsscheme.
- Familier, roller, relationer, assertions og conclusions begynder ved
  `schema.sql:760`, `schema.sql:765`, `schema.sql:798`, `schema.sql:818` og
  `schema.sql:833`.
- Kildeprosa ligger aktuelt i `narrative` ved `schema.sql:863`.
- Redaktionel adgang til importkorrektion er RLS-beskyttet i `db-rls.sql:606`.

Dette snapshot beskriver kun de versioner, som `schema.sql`,
`db-migrations.sql`, `db-rls.sql` og klienterne indeholder på ovenstående
commit. Det er ikke bevis for en anvendt produktionsdatabase.

## Fase 0-stopport

Worktree og baseline findes nu. Kendte fejl er registreret med årsag og må
ikke rapporteres som grønne i senere faser.
