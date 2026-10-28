# Arkiv — historiske scripts, kører ikke

Filerne her er bevaret som historik og kører ikke i CI. Brug dem ikke som
verifikation, og læs dem ikke som dækning.

| Fil | Hvorfor arkiveret | Dækning i dag |
|---|---|---|
| `test_apply_reimport_1939_v50.R` | Rød siden #153: 1939-adapteren delegerer til den generelle `execute_reimport`, og testens falske gateway giver ingen preflight (`REIMPORT_DATABASE_PROFILE_MISMATCH`). Review 2026-10-27, fund 1c-04. | `tests/testthat/test-apply-reimport-1939-v50.R`, `tests/integration/test-1939-v50-production-writer.R` (CI) |
| `test_apply_name_completion_1939_v50.R` | Rød af samme årsag (`subscript out of bounds` i `execute_name_completion_generic`). Review 2026-10-27, fund 1c-04. | `tests/testthat/test-apply-name-completion-1939-v50.R`, `tests/integration/test-1939-v50-name-completion.R` (CI) |

Planerne `docs/superpowers/plans/2026-08-18-1939-v50-production-writer.md` og
`…-name-completion.md` nævner de gamle stier som verifikationskommando. Planerne er historik.
