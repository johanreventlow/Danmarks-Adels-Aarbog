# Spike: fuld personsletning (november 2026)

Engangsværktøjer fra Task 0 i `docs/superpowers/plans/2026-11-14-fuld-personsletning.md`, flyttet hertil fra
`tests/sql/` (review 37 C13), så de ikke ligner tests, CI kører. Arbejdet er afsluttet (personsletningen er i prod).
Bevaret som dokumentation af, hvordan låse- og vagtinventaret blev målt; de historiske planer nævner de gamle stier.

- `spike-person-purge-laase.sh`: låse-spike med tvungne interleavings på syntetiske engangsbaser.
- `ci_jobs_lokalt.py`: kører de fire PostgreSQL-CI-jobs lokalt med spikens vagter slået til.
- `person-purge-skelet.sql`, `person-purge-fixture.sql`: vagt-skelet og syntetisk fixtur til de to.

Kør fra repo-roden, fx `bash tools/spike-personsletning/spike-person-purge-laase.sh`. Kun syntetiske data.
