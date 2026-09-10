# Klausullaget (#148) — rehearsal mod prod-restore

Kun tal og hashes. Ingen kildetekst, ingen personoplysninger, ingen record-id'er.
Artefakterne ligger i `~/.private/` (0700-mapper, 0600-filer) og committes aldrig.

## Dagsværk 4.1a (skema)

**Grundlag.** Prod-dump 2026-09-10, `pg_dump -Fc --no-owner` over Session pooler med
`sslmode=require`, taget af projektejeren (sessionens egen prod-adgang er blokeret af
harnessets klassifikator, også læse-kun).

| Artefakt | Værdi |
| --- | --- |
| Dump-SHA-256 | `c1c13f76241e8b7207eee63c4fc3190c8ad2be4020250a8992bcc6cf0aded700` |
| Dump-størrelse / filmode | 9 809 226 bytes / 0600 |
| Restore-base | `daa148a_rehearsal_20260910162112` (lokal PostgreSQL 17) |

**Restore.** 8 fejl i alt, 0 uden for `supabase_vault` (manglende extension, dens
`COMMENT`, `vault.secrets`/`vault.decrypted_secrets` og tre `vault.*`-funktioner).

> **Afvigelse fra runbooken, som kostede en kørsel.** Runbookens §1 nævner kun `anon`,
> `authenticated` og `service_role` som roller, der skal findes i clusteret på forhånd. Et
> Supabase-dump bærer også GRANTs til platformrollerne `dashboard_user` (102 sætninger),
> `supabase_auth_admin` (4), `supabase_storage_admin` (3), `supabase_realtime_admin` (1) og
> `pgbouncer` (1). Uden dem fejler 111 GRANT/OWNER-sætninger, og ACL'erne restorer ikke
> trofast — netop dét, forbuddet mod `--no-privileges` skal forhindre. Rehearsal-scriptet
> opretter dem nu som tomme NOLOGIN-roller før restoren.

**Forudsætningstjek.** 1939-ledgeren er ikke in-flight (0 udstedte autorisationer, 0 åbne
batches), så #153's opgraderingsblok kan køre.

**Migration og verifikation.**

| Trin | Resultat |
| --- | --- |
| `person_post`-observationer før migration | 591 |
| `db-migrations.sql` kørt to gange i træk | begge exit 0 |
| `db-rls.sql` | exit 0 |
| `db-verify.sql` (disponerbar runner) | `OK: #148 klausullagets skema, vokabular, triggere, ACL og hærdet legacy-writer` |
| Tal efter migration (`person_post` / `clause` / børn / 13 kinds seedet / dispositioner) | `591 \| 0 \| 0 \| t \| 0` |
| 149b's SQL-suite mod restoren | 9 NOTICE, 0 fejl |
| `test-clause-evidence-schema.sql` mod restoren | t1-t5 OK |

Migrationen er additiv: den rører ingen eksisterende observation, og klausullaget står tomt,
som det skal efter 4.1a.

**Åbent ACL-spørgsmål besvaret.** Codex' adversarial review rejste, om Supabases direkte
default-grant til `service_role` også gælder de elleve ældre private evidenstabeller. Den
lokale shim kunne ikke svare, fordi den slet ingen Supabase-default-grants har. Mod restoren,
som bærer prods rigtige GRANTs:

| Måling | Værdi |
| --- | --- |
| Relationer i `private` | 53 |
| Heraf med `SELECT` eller `INSERT` for `service_role` | **0** |
| Kontrolmåling: `service_role` på `public.person` | `true` (RLS gater den — proben er ikke tom af den forkerte grund) |

Der er altså intet efterslæb at rydde op i. `REVOKE … FROM service_role` på klausullagets
tre nye relationer er defence-in-depth, og `db-verify` håndhæver det nu.
