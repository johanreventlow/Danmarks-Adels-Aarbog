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

## Dagsværk 4.1b (segmentering)

Regelversion `clause-rules-2018-20-v1`, profilversion `1.1.0` (projektejerens GO
2026-09-10). Samme restore-base som 4.1a.

| Artefakt | Værdi |
| --- | --- |
| Eksport-SHA-256 (`clause-source-texts-v1.json`) | `aaa5f7ecb9c276670b427d23ff832805c5f88f460757d2b0d92f8569d389b7e9` |
| Ledger-fil-SHA-256 | `0e873b1613934bf0bd9d06ed4dc84ef1a8e29e19b95ff48ba805e5811fbd9ac0` |

Eksporten kørte i en `REPEATABLE READ READ ONLY`-transaktion, der altid rulles tilbage, og
med `R_ENVIRON_USER=/dev/null`, så child-R'et umuligt kunne nå prod. En fail-closed probe
bekræftede, at R ikke kunne se prod-credentials.

| Måling | Værdi |
| --- | --- |
| Records | 591 |
| Klausuler i alt / min / median / max pr. record | 866 / 1 / 1 / 29 |
| `unknown_abbreviation` | 424 |
| `multiple_marriages` | 92 |
| `unbalanced_parentheses` | 80 |
| `uncertain_marker` | 42 |
| `short_clause` | 29 |
| `non_gap_whitespace_in_clause` | 0 |
| `structural_header`-klausuler | 0 (ingen strukturelt kildemateriale i 2018-20's helposter, som spec 4.1.3 forudsagde) |
| Mellemrumstegn uden for hvidlisten | **ingen** — `gap_charset` `[" "]` er rigtigt målt |

### Fund: flerpunkts-forkortelser gav tavse splits

Første kørsel gav 1297 klausuler. En måling af, hvor splittene faktisk faldt, viste at
**394 af dem lå lige efter en forkortelse med indlejret punktum**, fordelt på 152 af de 591
records:

| Token | Splits / forekomster |
| --- | --- |
| `s.å.` | 238 / 569 |
| `m.a.` | 58 / 189 |
| `s.st.` | 23 / 63 |
| `cand.jur.` | 14 / 34 |
| `D.M.` | 13 / 13 |
| `s.m.`, `S.K.`, `cand.med.`, `a.d.`, `R.St.`, `Pr.R.Ø.1.`, `dr.phil.`, `Feld-Art.-Reg.` m.fl. | 1-6 hver |

De klippede grader, embeder og dekorationer midt over — og **uden flag**, fordi
`_is_non_terminal` afgjorde sagen med `bare.isalpha()`, som er falsk, når tokenet selv
indeholder et punktum. Motoren behandler dem nu som al anden tvivl: konservativ
segmentering plus `unknown_abbreviation`. Efter rettelsen: 0 splits efter
flerpunkts-forkortelser, 866 klausuler, og flagtallet steg fra 141 til 424, fordi tvivlen nu
er synlig i stedet for at være afgjort forkert i stilhed.

**Planens egen gennemgangsmekanisme var blind for fejlklassen.** Summaryens
`unknown_abbreviation_tokens` opsamler kun tokens i klausuler, der *allerede* er flagget, og
den skærer ved de 50 hyppigste. `s.å.`, `cand.jur.` og `D.M.` ville derfor aldrig være dukket
op på den liste, projektejeren skulle godkende. Listen indeholdt til gengæld uskyldige
naboer — datotal som `1.` og `(30.` — fordi den tæller alle korte punktum-tokens i en
flagget klausul, ikke det token der blokerede. Skal listen bruges som beslutningsgrundlag,
skal den udtrække det faktisk blokerende token.

### Åbent: regelversion 2 (profilversion 1.2.0)

Efter rettelsen er 424 klausuler flagget `unknown_abbreviation`. De 51 tokens, der faktisk
blokerede en split, fordeler sig i to grupper (kun tokens, ingen kontekst):

- **Ægte danske forkortelser, hyppige:** `best.` 60, `fmd.` 42, `vedr.` 16, `u.` 7,
  `komp.` 4, `ml.` 4, `reg.` 4, `rdl.`/`rdlr.` 3+3, `gl.` 2, `afd.`, `div.`, `dr.`, `begr.`,
  `diss.` m.fl.
- **Kendte forkortelser bag en parentes,** som listen ikke matcher, fordi tokenet bærer
  parentesen med: `(b.` 12, `(ca.` 9, `(udst.` 6, `(k.` 2, `(if.`, `(iflg.`, `(ml.`, `(udg.`,
  `[ca.`, `[jf.`
- **Flerpunkts-forkortelser** fra tabellen ovenfor: `s.å.`, `s.m.`, `s.st.`, `s.d.`, `m.a.`,
  `bl.a.`, `m.fl.`, `f.eks.`, `cand.*`, `dr.*`, `D.M.`, `S.K.`, `R.St.` m.fl.

At føje dem til `non_terminal_abbreviations` ændrer **ikke** segmenteringen — de blokerer
allerede — men fjerner flaget, så de 424 reduceres til den ægte rest. Det er en
profilændring med `requires_human_go_for_change` og afventer projektejerens afgørelse.
