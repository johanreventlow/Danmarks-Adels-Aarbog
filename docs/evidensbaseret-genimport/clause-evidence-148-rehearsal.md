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

### Regelversion 2 (profilversion 1.2.0) — udført

Projektejerens GO 2026-09-10. `clause_rules.version` `clause-rules-2018-20-v2`,
profilversion `1.2.0`, 113 forkortelser tilføjet (91 → 204). Samme eksport
(`aaa5f7ec…`), ny ledger-fil-SHA `8f4a88f5803287778666c120fa36bc5e770cebe685286f0e2a4eb9bc08980210`.

| Måling | Regler v1 | Regler v2 |
| --- | --- | --- |
| Klausuler i alt | 866 | 868 |
| `unknown_abbreviation` | 424 | **53** |
| Records med mindst ét ukendt token | 332 | 45 |
| Distinkte ukendte tokens | 153 | 26 |
| `multiple_marriages` / `unbalanced_parentheses` / `uncertain_marker` / `short_clause` | 92 / 80 / 42 / 29 | uændret |
| `gap_violations` | ingen | ingen |
| `structural_header` | 0 | 0 |

De to ekstra klausuler kommer fra en motorrettelse, ikke fra profilen: et punktum **efter en
lukkeparentes** afslutter sætningen (`(5000 Kr.). Gift …`). Uden den regel fangede
flerpunkts-reglen `Kr.).` (24 forekomster) og `H.).` (12) og smeltede to ægte klausuler
sammen. Samtidig slår opslaget i forkortelseslisten nu også til, når tokenet bærer en
åbnende parentes med (`(ca.` → `ca.`).

**Hvad der bevidst IKKE kom i profilen.** Kun tokens, der med sikkerhed er standard­forkortelser,
blev tilføjet. Resten står stadig som flag — det er dét, flaget er til. De 26 tilbageværende
fordeler sig på 45 records:

- enkeltbogstaver, hvis betydning ikke kan afgøres: `a.` 12, `(b.` 12, `u.` 7, `(k.` 2, `e.`, `h.`
- almindelige ord foran et ægte punktum: `død.` 3, `maj.` 3, `krig.`, `lidt.`, `mor.`, `or.`, `pest.`, `ses.`, `ung.`, `gr.`, `anc.`
- dato- og talintervaller: `(6.-13.`, `(7.-13.`, `(8.-15.`, `95.-97.`, `aug.-13.`, `febr.-1.`, `febr.-31.`, `jan.-30.`
- `(if.` (sandsynlig OCR-variant af `iflg.`)

Til sammenligning blokerer de kendte regler nu 5719 gange fordelt på 199 distinkte tokens.

## Dagsværk 4.1c (writer) — rigtig kørsel

Samme restore som 4.1a/4.1b. Manifestet er bygget af 4.1b's ledger med
`build_clause_evidence_manifest.py`, som oversætter klausulernes offsets gennem
`project_rendition`-kortet og hash-verificerer hver enkelt undervejs.

| Binding | Værdi |
| --- | --- |
| Rendition (genskabt fra PDF, = basens `content_sha256`) | `2dd5cf8408943ccc50ac4d89dcbd08ac3b49a90fdabd1ddcbd7b22d218026563` |
| PDF | `3beadfc15e3fa1a4090589af56cd4e95599a9231e8f979dfb60c4e27bbd8252a` |
| Projektion | `645f6f33101057953b912c2ebbe3ca67f90f1025398e6bb363cb1d8193df017f` |
| Ledger-fil (fra 4.1b) | `8f4a88f5803287778666c120fa36bc5e770cebe685286f0e2a4eb9bc08980210` |
| Manifest | `0b31c5a22c1045fcfb0528b8099f1e118cb235882ca92a6341808eb56c8655f6` |
| Profil (`daa-2018-20-clause-evidence-v1`) | `7696cb87b9d5fecb3693d201d023ec84d27d25b35dee92f09bd6b75e88ce31f5` |

| Måling | Værdi |
| --- | --- |
| Operationer / klausuler i manifestet | 591 / 868 |
| Dry-run | `finalized`, ikke committet, 868 klausuler rullet tilbage, 3,7 s |
| Apply | `finalized`, committet, 2,8 s |
| Klausuler i basen efter apply | 868 |
| Heraf uden post-relativt par | 0 |
| Heraf med span uden for forælderens | 0 |
| Dispositioner | 868 (`afventer_fortolkning` 617, `maskinelt_flagget` 251) |
| `clause_evidence`-hændelser | 591 (én pr. record) |
| Helposter | 591, uændret |
| Kanonisk lag før / efter | `3dfdc1ef827f583697b9cbe73e5ebd09` / **identisk** |
| Replay | `already_applied`, 0,6 s |
| `db-verify` | begge `#148`-blokke `OK` |

**Intet kanonisk delta.** Klausullaget er ren evidens: person, fact, assertion,
conclusion, narrative, relation og family_member er uændrede, målt som én hash før og
efter skrivningen.

### Fund: en modsigelse i spec §4.1.2, som først kunne vise sig her

Dry-run stoppede første gang i 4.1a's trigger med `EVIDENCE_CLAUSE_TEXT_MISMATCH`.
Triggeren udskar klausulen som
`substr(parent.verbatim_text, NEW.char_from - parent.char_from + 1, længde)` — en
aritmetik, der forudsætter en lineær afbildning mellem helpostens rå spænd og dens gemte
tekst. Den afbildning findes ikke: `segment.py` folder whitespace, så kun 97 af 591
helposter har `char_to - char_from = length(verbatim_text)`.

Spec'en kræver begge dele på én gang: at klausulens offsets er rendition-absolutte, **og**
at klausulens tekst er forælderens tekst udskåret på de offsets. Målt på de 868 klausuler
matcher post-relativ udskæring hashen 868/868, mens triggerens subtraktion rammer rigtigt
498 og forkert 370.

Med planens oprindelige — forkerte — offsets var triggeren tilfreds hver gang, fordi begge
sider regnede galt på samme måde. Fejlen kunne først opdages, da den ene side blev rigtig.

**Løst** ved at lade `char_from`/`char_to` forblive rendition-absolutte for alle
observationer og tilføje et post-relativt par `post_char_from`/`post_char_to`, som bærer
den eksakte substring-kontrol. Begge fakta er nu sande og hver for sig kontrollerbare.
