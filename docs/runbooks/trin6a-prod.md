# Runbook — trin 6a i prod: ceremoni A (DDL) og B (1939's klausuler)

Spec: `docs/superpowers/specs/2026-10-29-trin6a-klausuler-og-kildetekst-revision-design.md` §7. Plan:
`docs/superpowers/plans/2026-10-29-trin6a-klausuler-og-kildetekst-revision.md` Task 14 og 16.

- **Ceremoni A** lægger trin 6a's DDL i prod: blokken fra `-- ===== trin 6a: helpost-regel =====` til slutningen af
  `db-migrations.sql`, i én transaktion. Den er additiv: 12 nye funktioner (heraf `clause_write_set` med 5
  argumenter, der erstatter udgaven med 4), nye kolonner og views, og klausul-writeren skiftet til helpost-reglen
  og den rå tekstform. Den eneste data er to nye rækker i `private.reimport_writer_profile`.
- **Ceremoni B** skriver 1939's klausuler: 584 helposter og 954 klausuler med profilen `daa-1939-clause-evidence-v1`,
  gennem reimport-writerens kæde (authorize → apply → finalize). Det kanoniske lag og læserfladen ændres ikke.
- **Kildetekst-revisionen anvendes ikke i prod i 6a.** Første brug er 6c's samlede ceremoni (spec §7 pkt. 5).

Runneren er privat: `~/.private/5ab-overfoersel/25-trin6a.sh` med `25-trin6a-b.R` og 5c-2's `lib.zsh`/`koer.zsh`.
Projektejeren kører alt, der rører prod, fra egen shell. AI-sessionen læser kun rapporter med tal, koder og hashes.

## Forudsætninger

- PR 1 (#281) og PR 2 er merget. `main` er checket ud rent i `/Users/johanreventlow/TypeScript/danmarksadelsaarbog`.
- **Vindue og skrivepause:** fra dumpet i skridt 3 til skridt 12 skrives der ikke redaktionelt i prod (projektejeren
  er den eneste aktive redaktør; meld det, hvis andre er aktive). Vinduet er fortrydelsens grænse: en restore af et
  dump fra vinduet sletter alt, der er skrevet efter dumpet. Samtidige skrivninger kan desuden få B's kanoniske
  kontrol til at fejle efter commit (se Stoppunkter).
- Runnerens faste værdier passer til `main`:
  - `T6A_BLOK`: blokkens sha;
  - `T6A_MANIFEST_CONTENT`: manifestets indholds-sha;
  - `T6A_RENDITION_SHA`: `020123a3…6da37`, Calamari-renditionen i `work_1939_stamtavle/`.

  Ændres `db-migrations.sql`, 1939-reglerne, segmenteringen eller manifest-byggeren efter øvelsen, skal øvelsen
  gentages, og værdierne skal opdateres, før der tages GO.
- `DAA_EXPECTED_TARGET` (prods målidentitet) står i `prod/go-env.txt`, som ved 5c-2.

## Forløb (projektejerens shell)

Alle kommandoer køres som `/bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 25-trin6a.sh …`.

### Ceremoni A

1. `maal` → `T6A_MAAL_OK tilstand=foer`. 2018-20-delen (`k1_klausuler`, `k1_poster`, `k1_hash`) noteres. Målingen er
   ceremoniernes første læsning mod prod og dermed tidsprøven: tager den over 60 s, stoppes der og måles igen.
   Tag samtidig `get_advisors(security)` som før-billede (skridt 5 sammenligner med det).
2. `go-a` → `GO_6A_A_KODE=<8 hex>`. Projektejeren skriver `GO 6a-A <kode>`. Koden binder ceremonien, commit'en,
   `db-migrations.sql`, målingen, målidentitetens SQL, runneren, R-scriptet og hjælperne.
3. `dump` → `DUMP_6A_OK tilstand=foer …` og `EKSTERN_6A_OK … rundtur=ok`. B1: en `age`-krypteret kopi lægges på
   SFTP-serveren, hentes tilbage, sammenlignes og dekrypteres; den dekrypterede rundtur-kopi slettes efter kontrollen.
   Kvitteringen bærer basens tilstand; `apply-a` kræver `foer`.
4. `apply-a --jeg-mener-det --go <kode>` →
   - `B1_6A_OK …`: dumpet og den eksterne kopi er kvitteringens bytes;
   - målingen før skal være `foer`;
   - blokken (sha bundet) køres i én transaktion med `lock_timeout` 5 s, derefter `NOTIFY pgrst, 'reload schema'`;
   - `T6A_APPLY_A_OK funktioner=12 profiler=2 view=t k1_…`: målingen efter er tilstand `a`, og 2018-20 er uændret.
5. `get_advisors(security)` igen (som ved 5c-2; CLI-tjekket `22-trin-b.sh advisors` er låst til 5c-1's fund og
   kan ikke bruges her). Diff mod før-billedet fra skridt 1: forventet er højst ét nyt fund, den nye
   `public.red_apply_reimport_source_text_revision` (SECURITY DEFINER, kan kaldes af `authenticated`, som de øvrige
   `red_apply_reimport_*`). Alt andet undersøges, før B køres.

### Ceremoni B

6. `eksport` → `T6A_EKSPORT_OK helposter=584 uden_helpost=8`. Læse-kun. Kræver tilstand `a`. Postteksterne lægges
   i en 0700-mappe under `prod/6a/` og forlader ikke maskinen.
7. `manifest` → `T6A_MANIFEST_OK operationer=584 indhold=e35f72be…`. Bygges lokalt. Indholdet skal være øvelsens:
   afviger det, er teksten i prod en anden end i dumpet fra 2026-10-29, og B stopper her.
8. `go-b` → `GO_6A_B_KODE=<8 hex>`. Projektejeren skriver `GO 6a-B <kode>`. Koden binder også manifestet.
9. `dump` igen → `DUMP_6A_OK tilstand=a …`. `apply-b` kræver et dump taget i tilstand `a` (altså efter A); ellers
   `STOPPORT: DUMP_6A_TILSTAND`.
10. `apply-b --jeg-mener-det --go <kode>` →
    - `B1_6A_OK …`;
    - målingen før skal være `a`;
    - `25-trin6a-b.R` kører dry-run, authorize (som `service_role`), apply og replay. Det kanoniske lag skal være
      uændret;
    - `T6A_FLAG k3 record_text:954 | multiple_marriages:1,page_marker_in_clause:77,possible_layout_line:21,
      short_clause:42,unbalanced_parentheses:74,uncertain_marker:7,unknown_abbreviation:60`;
    - `T6A_APPLY_B_OK k3_klausuler=954 k3_poster=584 k3_afventer=719 k3_flagget=235 k3_batch=1 status=finalized …`.
11. `maal` → `T6A_MAAL_OK tilstand=b`.
12. Vinduet slutter. Redaktionen kan skrive igen.

## Varighed og prods tidsgrænse

Prods `statement_timeout` er 2 minutter. Grænsen gælder pr. sætning, ikke pr. ceremoni.

| | Stand-in | Forventet i prod |
|---|---|---|
| Blokken (A) | 0,04 s; hele `db-migrations.sql` 0,67 s | sekunder |
| Ceremoni B, apply alene | 3,7-3,8 s | ca. 3-4 min |
| Ceremoni B i alt (dry-run + apply + replay) | ca. 2 × apply | ca. 7-8 min |
| Målingen | < 1 s | sekunder (stop ved > 60 s, skridt 1) |

Forholdet mellem prod og stand-in er målt tidligere og ikke på ny for 6a (ingen ekstra prod-berøring):
- 2018-20's klausulkørsel tog 230 s i prod mod 4 s på stand-in (148c, 2026-09-18), altså ca. 55×;
- 5c-2's måling tog over 120 s i prod mod 6 s (2026-10-29).

Ceremoni B består af mange små kald, så 55× er det relevante forhold. Dry-run'et udfører alle 584 operationer og ruller
tilbage, så B's samlede tid er omtrent det dobbelte af apply. Den forventede varighed er et skøn, ikke et bevis. Det, der
tæller mod grænsen, er den længste enkelte sætning; i øvelsen var hele apply under 4 s, så ingen sætning er i
nærheden.

## Stoppunkter

Alle `STOPPORT:`-linjer stopper uden at skrive yderligere. Hvor langt man er nået, læses af `maal` og af batchens status.

| Hvor | Tilstand bagefter | Gør |
|---|---|---|
| Før `apply-a`'s blok | `foer`; intet skrevet | Ret årsagen, kør skridtet igen |
| I A's blok (`DDL_6A fejlede`) | `foer`; rullet tilbage | Ret årsagen; ny GO, hvis filer ændres |
| Efter A's commit (`DDL_6A_NOTIFY`, `T6A_EFTER_A`, `T6A_K1_UAENDRET`) | A er committet | Kør `maal`. Er den `a` og `k1` uændret: kør `NOTIFY pgrst` manuelt og fortsæt. Ellers: stop og undersøg; fortrydelse af A (nedenfor) |
| B før apply eller midt i kæden (fejl i dry-run, authorize eller apply) | `a`; batchen rullet tilbage eller ikke `finalized` | Læs koden i `apply-b-*.out`; ret; `apply-b` igen med samme GO (dumpet i tilstand `a` gælder stadig) |
| Efter B's commit: `T6A_B_KANONISK_AENDRET` | batchen `finalized` | **Fortrydelsestilfælde:** det kanoniske lag ændrede sig under B. Stop; afgør om det var en samtidig redaktionel skrivning (vinduet brudt) eller B. Var det B: restore af dumpet fra skridt 9 |
| Efter B's commit: `T6A_B_REPLAY_STATUS`, `T6A_EFTER_B` | batchen `finalized` | Kør `maal`. Er den `b` og `k1` uændret, lykkedes B; undersøg replay-fejlen bagefter. Ellers stop og undersøg |

Kør aldrig `apply-b` igen, når batchen er `finalized`: tilstanden er så ikke længere `a`, og runneren stopper selv.

## Fortrydelse

- **Ceremoni B:** klausulerne har ingen afhængige, før 6c kører. Fortrydelse er restore af dumpet fra skridt 9 i det
  deklarerede vindue (`db-rls.sql` igen bagefter). Er det kun reglerne, der var forkerte, kan et nyt sæt i stedet
  lægges med `clause_revision`.
- **Ceremoni A:** de tidligere funktionskroppe fra dumpet fra skridt 3 (ikke scriptet og ikke øvet; bygges kun,
  hvis det bliver nødvendigt). Det kræver: genskab `clause_write_set` med 4 argumenter og dens REVOKE'er, drop
  udgaven med 5 argumenter og de 11 andre nye funktioner, og tag stilling til de to profilrækker. Nye kolonner kan
  blive stående. Alternativt restore af dumpet fra skridt 3, hvis intet andet er skrevet i vinduet.

## Kendte begrænsninger i 1939-segmenteringen (røgtest 2026-10-30)

Røgtesten gennemgik 2 × 20 poster om personer død før 1800 (seed 20261030 og 20261031) og fandt fejlsnit efter
`Aarb.`, `Kbhvn.`, `(5.`, `Sunds-H.` samt enkeltstående `Test.`, `Jfr.`, `Supp.` og `Prot.` De er rettet (profil
`daa-1939-v1` 1.2.0). Tilbage står, med flag:

- Et kort ord med lille begyndelsesbogstav før `. ` behandles som en ukendt forkortelse (fx `… endnu ses. Gift …`).
  Der splittes ikke, og klausulen flages `unknown_abbreviation` (60 klausuler).
- Semikolon inde i en parentes splitter (fx i en henvisning `(Aarb. LII, 96; LIII, 60)`). Klausulen flages
  `unbalanced_parentheses` (74 klausuler).
- Et bynavn med punktum inde i en parentes splitter (`(Kiel. 8 Maj)`).
- `Kbhvn.` splitter ikke længere, heller ikke i de 3-5 tilfælde, hvor det står ved sætningsslut før `Gift`. Det sker
  **uden flag**: forkortelseslisten og initial-/ordenstalsreglen splitter ikke og flager ikke, så sådanne
  sammensmeltninger er tavse (det samme kan ske med `Test.` ved sætningsslut). Teksten er bevaret; klausulen er blot
  længere.
- Sidemarkøren `### PAGE n ###` hænger ved klausulen før sig, når den står sidst i posten (flag
  `page_marker_in_clause`, 77).

## Øvelse (2026-10-30)

Stand-in'erne blev bygget af 5c-2-dumpet (`0e988082…`, taget før 5c-2-blokken). Derefter kom 5c-2-blokken (sha
`97a69759…` = `C2B11_BLOK`), `db-rls.sql` fra `main` før 6a, ICU, `ANALYZE` og prods 2-minutters grænse.

- **Stand-in svarer til prod:** 5c-2's egen måling gav `C2B11_MAAL_OK tilstand=efter` og `C2B11_DIFF n=37 noegler=ens`.
  `db-migrations.sql` og `db-rls.sql` fra `main` før 6a ændrer ingen af de 362 funktioner, så `main` før 6a = prod.
- **Blokken alene er lig hele stien:** de 373 funktioner (krop, SECURITY DEFINER og EXECUTE for anon, authenticated
  og service_role) og de 1.484 linjer med kolonner, views, tabelrettigheder og profiler er identiske med
  `db-migrations.sql` + `db-rls.sql`.
- **Øvelsen fandt en fejl** i PR 1's blok: `private.clause_observation_current` (`o.*`) manglede `parent_text_id`
  efter én kørsel. Den er rettet i PR 2, og CI's nye view-paritet (`tests/sql/inspect-6a-view-parity.sql`) fanger
  den slags fremover.
- **Runneren er øvet to gange fra ende til anden.** Anden øvelse brugte runneren efter Task 14-reviewet (I1-I4,
  M1-M7, M11), på `daa5ab_ddl_standin_20261030190000_6ar2`:

| Skridt | Resultat |
|---|---|
| `maal` | `foer`; `k1_klausuler=984 k1_poster=591 k1_hash=2c530d0a…` |
| `go-a` → `apply-a` uden dump | `STOPPORT: DUMP_6A_MANGLER` |
| `dump` → `apply-a` | `DUMP_6A_OK tilstand=foer`; `T6A_APPLY_A_OK funktioner=12 profiler=2 view=t`, `k1` uændret |
| `eksport` | 584 / 8 |
| `manifest` | indhold `e35f72be…` |
| `go-b` → `apply-b` med dumpet fra tilstand `foer` | `STOPPORT: DUMP_6A_TILSTAND` |
| `apply-b` med forkert kode (første øvelse) | `STOPPORT: GO_MISMATCH` |
| `dump` → `apply-b` | `DUMP_6A_OK tilstand=a`; `T6A_FLAG` som i skridt 10; `T6A_APPLY_B_OK … sekunder=3.8 inkl_dryrun=7.7`, replay `already_applied`, kanonisk uændret, `k1` uændret |
| `maal` | `b` |

De dekrypterede rundtur-kopier blev slettet efter kontrollen; dumpet og `.age` blev liggende.

## Efter ceremonierne

- `docs/evidensbaseret-genimport/status.md`: 1939-rækken »Klausuler« bliver `produktionsverificeret` med dato.
  Revisionen og genkørslen bliver `isoleret implementeret`.
- `docs/database-current-state.md` og `docs/changelog.md`.
- Til 6c (måles på stand-in i Task 15 og igen før 6c's ceremoni): antallet af kvitterede forslagsnøgler med
  `key_matches=false`. Forventet 0. Det samme gælder, hvis en records accepterede anker er ændret efter forslaget, og
  for links til forekomster for to forskellige records.
