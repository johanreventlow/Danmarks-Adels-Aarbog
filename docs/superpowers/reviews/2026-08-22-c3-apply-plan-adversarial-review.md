# C3 apply-plan — adversarial review (Codex sol) + vurdering

**Dato:** 2026-08-22 · **Reviewet:** `plans/2026-08-22-1939-v50-c3-atomisk-apply.md` mod
`specs/2026-08-22-1939-v50-fase-c3-apply-design.md` · **Snapshot:** `9d2c2b2`
**Codex' dom:** NO-GO — 6 blockers, 6 high/medium, 10 spec-krav uden dækning.
**Min vurdering:** dommen står. Alle seks blockers er reelle. To af dem (B3, H6) er
fejl i *min* ændring fra samme dag — generaliseringen blev navngivet, men ikke
ført igennem til signaturer og filkort.

## Blockers — alle tiltrådt

| # | Fund | Vurdering |
|---|---|---|
| **B1** | Prod-bundet manifest kan ikke bruges på den disposable restore: finalmanifestet binder databasenavn + system identifier, og restoren har nødvendigvis et andet navn. Rehearsal er dermed ueksekverbar som beskrevet. | **Tiltrådt.** Verificeret i spec'ens artefaktkæde og i `export_c3_current_state_1939_v50.R`'s `--expect-database-name`. Kræver to eksplicitte artefaktforløb: restore-bundet → disposable apply/reversal, derefter frisk prod-bundet → prod-GO. **Følgespørgsmål til brugeren:** skal tekstgodkendelsen bindes til *teksthashes* frem for hele manifestet, så mennesket ikke skal godkende de samme fem diffs to gange? Teksten afhænger af record-verbatim + normaliseringsprofil, ikke af databasen, så det er forsvarligt — men det ændrer spec'en. |
| **B2** | Den restorede base får aldrig C3-migrationerne; backupen er af umuteret prod, så `reimport_case_*` findes ikke. Task 9 ville fejle på manglende objekter. | **Tiltrådt.** Kræver et selvstændigt trin efter restore: atomisk `psql -1 -v ON_ERROR_STOP=1` af migration + RLS, DDL-fejlinjektion, katalog-/ACL-/signaturkontrol og `db-verify` mod netop den base. |
| **B3** | De »generiske« signaturer mangler `source_id`, `phase` og `state_sha256`. `record_key` er kun unik sammen med `source_id` (`schema.sql:467-474`), så kilden kan ikke udledes af record key. | **Tiltrådt — min fejl.** Jeg omdøbte ti forekomster, men førte ikke parametrene igennem. Signaturerne skal have eksplicit `p_source_id bigint`, `p_phase text` og alle upstream-hashes som typede felter, ikke skjult i fri JSON. Negativ test: samme `record_key` i to kilder. |
| **B4** | Fravær af en binding kan ikke låses med `FOR UPDATE`. `narrative_record_publication` har unikhed på `narrative_id` og `record_ref`, men **ikke** på `source_record_id`, så en samtidig `red_publicer_narrative_record` kan publicere et andet narrativ for samme record. Begge kan committe. | **Tiltrådt, og skærpet.** Selv verificeret mod prod: kun `narrative_id` og `record_ref` er unikke. Låsedisciplin på `source_record`-rækken er Codex' fix, men et **partielt unikt indeks** på `source_record_id WHERE status IN ('draft','published')` håndhæver det deklarativt og dækker også writere, der glemmer låsen. Foreslås som tillæg, ikke erstatning. |
| **B5** | Reversal genbruger original batch + statusflip; spec'en kræver »reversal er en ny batch« med egen authorization, nonce, counts og kvittering. Events ville desuden kollidere på `UNIQUE(batch_id, element_id)`. | **Tiltrådt.** Uden egen batch-identitet kan commit-unknown for reversal ikke afklares. |
| **B6** | »Ingen receipt« er ikke bevis for rollback: en ny session kan tage snapshot, mens den gamle backend stadig committer. | **Tiltrådt.** Fixet — reconciliation skal først erhverve den samme globale advisory lock; når den er erhvervet, kan ingen tidligere C3-transaktion være in flight — er den rigtige og billige protokol. Gælder både apply og reversal. |

## High/medium — tiltrådt, ét med skærpelse og ét nedskaleret

- **H1 (to preview-sandheder):** tiltrådt. RPC'en skal være eneste state-orakel; R-scriptet må kun kalde den og byte-publicere dens canonical output. Mutationstest på preview-hash.
- **H2 (ingen guard mod `staged`/`levende`/`privat`):** tiltrådt, og **ikke hypotetisk** — prod har 7 staged personer, og 1014 er blandt de kendte grænsefejl-sager. En binding til en staged person ville give en »published« kvittering, mens den offentlige projektion viser intet. Manifest og låst preflight skal binde `person.levende=false`, `person.privat=false`, `person.staged=false`, `narrative.privat=false`.
- **H3 (`haendelse` som forældet projektion):** tiltrådt i princippet, **nedskaleret i omfang.** Codex kunne ikke måle prod; det kan jeg: `haendelse` har **0 rækker** i hele basen. Der skal derfor ikke bygges regenerering — previewet skal måle ID-sættet og **kræve det tomt**, og reversal skal kontrollere det samme. Bliver hændelsesudtrækket kørt senere (issue #130), skal kravet genbesøges. Jf. princippet i [[latent-er-ikke-harmloest]]: målingen afgør hastigheden, ikke om det skal gøres.
- **H4 (loader/post-load uden global lock):** tiltrådt. Task 9's filscope forbyder i dag den rettelse, spec'en kræver. `load_daa.R` og `post_load_fixup.R` skal ind i planens tilladte filer, tage writer-locken før `samme_som_mutation`, og testes i begge startordener.
- **H5 (service_role → authenticated-grænsen):** tiltrådt. JWT-subject ændrer `auth.uid()`, ikke `current_user`. Kræver eksplicit `SET LOCAL ROLE`-forløb eller to forbindelser, med assertion på `current_user`, `auth.uid()`, profil og `current_rolle()` ved hvert trin.
- **H6 (Task 4 siger stadig »Create«):** tiltrådt — **min fejl.** Jeg skrev genbrugsbeslutningen i indledningen, men lod filkortet stå. En udførende agent ville følge tasken ordret og bygge en parallel renderer. Task 4's filkort, tests og commitliste skal skrives om til »Modify«.
- **M1 (previewet er ikke ét snapshot):** tiltrådt. `BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY`.
- **M2 (`red_upsert_narrativ` vælger `ORDER BY id LIMIT 1`):** tiltrådt, og **direkte forbundet til #152** — netop fordi nøglen er `(subjekt, source_id)` og ikke record, kan RPC'en ramme den forkerte række, hvis der findes dubletter. C3 skal skrive mod det låste target-ID og kræve, at det returnerede ID er manifestets.
- **M3 (operationskoder afviger):** tiltrådt som dokumentfejl. Planens `operation IN ('apply','reversal')` med fasen i `phase` er den rigtigere model (ortogonal), men **spec'en skal rettes til det samme** frem for at planen rettes tilbage. Event-/payload-skemaversion tilføjes begge steder.

## Hvad Codex ikke kunne se

Reviewet var read-only uden DB-adgang. To af dets hypoteser er derfor afgjort her: `haendelse` er tom (H3 nedskaleres), og `narrative_record_publication` mangler faktisk unikhed på `source_record_id` (B4 bekræftes). Om de fem konkrete targets er staged/private/dublerede er stadig ikke afgjort — det kræver beslutnings-JSON'en i `work/`.

## Konsekvens

Planen revideres mod alle 12 fund, før den forelægges til godkendelse. Task 1 er upåvirket (færdig og verificeret). B1's følgespørgsmål om tekstgodkendelsens binding skal afgøres af brugeren, da det ændrer spec'en.
