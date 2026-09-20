# Source-scoped evidence V3 — RLS-runner

Dette er en lokal/rehearsal-protokol for #153. Den er ikke autorisation til at
ændre produktion.

## Atomisk RLS-pass

`db-rls.sql` bevarer bevidst sin komposable SQL-form, fordi eksisterende
kontrakttests inkluderer filen inde i deres egen transaktion. Når passet møder
eller binder #153 Task 4C-/4D-receipts, skal den ydre deployer derfor altid
starte den atomiske grænse:

```bash
LC_ALL=C psql -X --single-transaction -v ON_ERROR_STOP=1 -f db-rls.sql
```

Kør aldrig dette receipt-bundne pass direkte i SQL Editor eller med en almindelig
autocommit-`psql`-kørsel. Task 4C-preflighten afviser eksisterende drift, før
den kumulative RLS-fil ændrer receipt-bundne policies eller ACL'er; den ydre
transaktion sikrer, at et senere fejlstop ruller hele passet tilbage.

## Lokal proof

Med alle fem lokale PG-variabler sat til en disposable PostgreSQL-instans:

```bash
R_ENVIRON_USER=/dev/null Rscript tests/integration/test-source-scoped-evidence-v3-rls-atomic.R
```

Testen opretter og fjerner sin egen database, kører frisk apply og rerun med
`--single-transaction`, injicerer derefter en manglende allow-list-RPC efter
Task 4C-preflighten og kræver, at receipt og Task 4C-publicerings-RPC-ACL er
uændrede efter rollback.
