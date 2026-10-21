# Trin 5a + 5b — id'er af indholdet (forudsætningsled for prod-overførslen)

**Status:** **GODKENDT af projektejeren 2026-10-21.** Godkendt afsnit for afsnit i brainstormen 2026-10-21. **Revideret efter Fable-review** (2026-10-21: GO med rettelser, 3 MAJOR og 8 MINOR, alle indarbejdet; se §7).

**Formål:** opfylde §4 i den godkendte overførsels-spec
(`docs/superpowers/specs/2026-10-21-trin5ab-2018-20-prod-overfoersel-design.md`, draft-PR #250): en arbejdskørsel på
en lokal restore og et genspil i prod skal give identiske ark, rækkefiler, stikprøver og genereret ark-SQL.
Leddet ændrer kun mekanikken; dataene i beviskæden og prod røres ikke.

## 1. Adgangskrav (roadmap)

| Krav | Svar |
| --- | --- |
| Roadmapmål | Trin 5 (#151), forudsætning for prod-overførslen af 5a+5b |
| Værdikædeled | Identitetsafstemning og relationspersonas: id-dannelse, kontrolstikprøve og arkværktøjer |
| Leverancetype | Generel: deterministiske id'er og indholdsbaseret stikprøve i fælles funktioner; ingen udgaveprofil |
| Redaktionel værdi | Projektejerens svar kan genspilles i prod uden at afgøre noget igen; kontrolarket kan besvares én gang i øvelsen |
| Færdigbevis | Testen »to baser giver det samme« (§5.1) grøn efter at have været rød mod den nuværende kode; opgraderingstest fra prods træ `140a17b`; lokal CI 7/7 |
| Erstatter | Tilfældige id'er (`gen_random_uuid()`/kolonnestandard) i de 8 rækkearter i §3 og id-baseret stikprøvetrækning |

**Prod-spørgsmålene** (memory 2026-10-21): leddet deployes som en del af overførslens DDL-ceremoni. Det
indeholder kun `CREATE OR REPLACE FUNCTION` og ændrede arkværktøjer, ingen nye tabeller, kolonner eller
fremmednøgler. Prod har ingen rækker i de berørte tabeller ud over 149b-personas, som ikke ændres. Ingen
menneskelig godkendelse binder til noget, leddet skaber, før arbejdskørslen.

## 2. Udgangspunkt (kortlagt og efterprøvet 2026-10-21)

- **Præcedens:** `private.deterministic_uuid(text)` (`schema.sql:3791`) giver en uuid af de første 16 bytes af
  SHA-256 (versionsnibble 5, ikke RFC-v5). Den bruges allerede til `interpretation_key` og til 5b's
  årstalsnøgler (`schema.sql:15210`: `jsonb_build_object('kind',…)::text` som input). Kun `pgcrypto` er
  installeret; `uuid-ossp` bruges ikke.
- **Tilfældige id'er, der bærer et menneskeligt artefakt eller stikprøven** (resten forbliver tilfældige og
  verificeres pr. nøgle i overførslen):

  | Række | Dannes i | Bærer |
  | --- | --- | --- |
  | ægtefællepersona `source_persona.id` | `write_relation_persona` (`schema.sql:15188`) | arklinjer (5a, kontrol, 2b-i, v3 P), rækkefiler, kandidatinputtets hash |
  | ægtefællens omtale `source_mention.id` | samme (`:15191`) | kun intern; afledes for ensartethed (overførsels-spec §4) |
  | kandidatkørsel | `red_record_identity_candidates` (`:8914`) | rækkefiler, ark-SQL-kontekst, evidens, stikprøvens hash |
  | kandidat | samme (`:8923`) | rækkefiler, ark-SQL-kontekst, kontrolarkets visning, evidens |
  | kontrolkørsel | `red_register_identity_control_run` (`:16101`) | rækkefil, ark-SQL (forsegling, kontekst), evidens, kortrækkefølgen |
  | stikprøve | samme | intern; afledes (overførsels-spec §4) |
  | forældrekort | samme | intern; afledes (overførsels-spec §4) |
  | identitetshændelse | `decide_source_persona_identity` (`:8350`) | intern; afledes (overførsels-spec §4) |

- **Arkværktøjer med problemer, uafhængigt af id'erne:**
  - 2b-i's `O`-linjer nøgles på den gældende afgørelsesversions `interpretation_id` (tilfældig, fra den delte
    `red_decide_interpretation`), som hårdkodes i den genererede SQL (`spouse_exception_sheet.py:17,147-150`).
    Rækkefilen indeholder også `state_sha256`, som hasher `relation_binding_state` med databasens id'er
    (`schema.sql:16853-16871`).
  - Kontrolarkets rækkefil samler sine linjer uden `ORDER BY` (`identity_control_rows.sql:56`).
  - v3-arket viser datoen for den tidligere afgørelse (`relation_marriage_sheet_v3.py:77`, projektionen
    `schema.sql:17319`). Arkets hash indgår i alle v3-payloads, så hashen ville afhænge af kørselsdagen.
- **Prods skema** stammer fra repo `140a17b` (deploy 2026-09-17, `docs/database-current-state.md`). Overførslen
  2026-10-05 indeholdt ingen DDL.

## 3. Deterministiske id'er

**Afledning (tilgang A, valgt):** serveren afleder id'et selv:

```
private.deterministic_uuid(jsonb_build_object('kind',<art>,'key_version',1, <naturlig nøgle>)::text)
```

`kind` og `key_version` forhindrer, at to arter eller to nøgleversioner giver samme id. Fravalgt (B):
klientleverede id'er i manifestet som 149b; serveren skulle stole på klienten, og payloads og signaturer skulle
ændres.

| Art (`kind`) | Naturlig nøgle | Eksisterende unikhed |
| --- | --- | --- |
| `source-persona` | `source_id`, `persona_key` | UNIQUE (`source_id`,`persona_key`) |
| `source-mention` | persona-id (deterministisk), rolle `spouse`, ordinal 1 | UNIQUE (`persona_id`,`ordinal`) (`schema.sql:823`); klausulspændet er ikke unikt, fordi 149b også skriver `person`-omtaler |
| `identity-candidate-run` | `source_id`, `input_sha256`, `config_sha256` | UNIQUE (samme tre) |
| `identity-candidate` | kørsels-id, `source_persona_id`, `candidate_person_id` | UNIQUE (samme tre) |
| `identity-control-run` | `candidate_run_id` | UNIQUE (`candidate_run_id`) |
| `identity-control-sample` | kontrolkørsels-id, `source_persona_id` | UNIQUE (samme to) |
| `identity-control-parent-card` | kontrolkørsels-id, `interpretation_key` | UNIQUE (samme to) |
| `identity-event` | `source_persona_id`, `version` | UNIQUE (samme to) |

Alle id'er indsættes eksplicit i funktionskroppene. Tabellernes kolonnestandard (`gen_random_uuid()`) bliver
stående, så andre writere og ældre rækker er upåvirkede.

**Kollision fejler lukket.** Hvert indsæt kontrollerer, at en eksisterende række med samme id har samme
naturlige nøgle. Har den ikke, kastes `DETERMINISTIC_ID_COLLISION` med arten i beskeden. Writeren holder kun en
delt kildelås (`schema.sql:15066`), så to samtidige batches kan ramme primærnøglen: `unique_violation` fanges,
den naturlige nøgle tjekkes igen, og `DETERMINISTIC_ID_COLLISION` kastes, når nøglen afviger (ellers den
eksisterende konfliktkode). Samme indhold igen
opfører sig som i dag: kandidatkørslen er idempotent (`ON CONFLICT` + `candidates_sha256`, ellers
`IDENTITY_CANDIDATE_RUN_CONFLICT`), kontrolregistreringen returnerer den eksisterende kørsel, og writerens
`…_RELATION_PERSONA_EXISTS` gælder fortsat.

**Stikprøve og kortrækkefølge** trækkes efter indhold, ikke efter id'er:
- stikprøvens rækkefølge: `sha256('control-sample-v2:' ‖ input_sha256 ‖ ':' ‖ config_sha256 ‖ ':' ‖ persona_key)`
  for kandidatkørslen;
- kortenes visning: `sha256('control-display-v2:' ‖ input_sha256 ‖ ':' ‖ config_sha256 ‖ ':' ‖ persona_key ‖ ':'
  ‖ candidate_person_id)`.

Metodemærket (`-v2`) sikrer, at gamle og nye trækninger ikke kan falde sammen. Garantierne i 5b-spec'ens
§23.3 er uændrede: strata, navnefæller, K, udelukkelser og `IDENTITY_CONTROL_PRIOR_FAILED`; hashen er
uafhængig af svarene. Trækningen flytter sig med `config_sha256`, som i forvejen kræver en ny kørsel. 5b-spec'ens
§23.3 pkt. 4 citerer den gamle formel og får et erratum, og `decisions.md` får en linje.

**Fælles funktion:** `decide_source_persona_identity` bruges også af 149b's `person_create`/`legacy_match` og 2b-ii's
`relation_person_create`. Hændelses-id'et bliver deterministisk for alle. Det er harmløst (nøglen er versioneret),
men #153's writer er kun uændret i sin egen krop.

**Uændret:** #153's writer og batch-/autorisationstabeller, `red_decide_interpretation`, ekstraktionskørsler,
bindinger og bindingsbatches, #244's rettelsestabel. Ingen offentlig funktionssignatur ændres.

## 4. Arkværktøjerne

1. **2b-i's undtagelsesark:** `spouse_exception_projection` udgiver `O`-rækker med `interpretation_key` og
   version i stedet for `interpretation_id`, og uden `state_sha256` (ligheden med den gældende tilstand tjekkes
   fortsat ved kørsel). `spouse_exception_sheet.py`'s `O`-linjer får formen `O <interpretation_key> <version>
   bog/fam`, og den genererede SQL slår det gældende id op ved kørsel (som `relation_marriage_sheet.py:121`).
   Kontrakten hæves til `spouse-exception-rows-v2`; det gamle format afvises med en tydelig fejl. Overførslens
   svaroverførsel læser de gamle godkendte ark med sin egen parser. Opslaget sker på (`interpretation_key`,
   version) og fejler, hvis ingen række findes; `append_relation_classification` har ingen versionsparameter,
   så det er rækkefil-vagten (`$chk$`) under den eksklusive kildelås, der sikrer, at tilstanden er den godkendte.
   Projektionens `ORDER BY cur.cur_id` erstattes af `interpretation_key COLLATE "C"`.
2. **Kontrolarkets rækkefil** får en total rækkefølge: art, post (`record_key`), nøgle (`persona_key` eller
   `interpretation_key`).
3. **v3-arket:** datoen for den tidligere afgørelse fjernes fra projektionen og fra kortet. Grundlag og note
   vises fortsat.
4. **De øvrige ark** (5a's identitetsark, 2b-ii, børnearket, nummerarket) bliver deterministiske af §3 alene.
   Deres eksisterende rækkefølger brydes i dag på persona-id, som nu er deterministisk.
5. **Sortering og miljø uafhængigt af platformen.** Arbejdskørslen kører på en lokal restore (Homebrew/macOS),
   prod på Supabase/Linux, og de sorterer tekst forskelligt (memory: rækketekst-hash afhænger af locale). Hver
   tekst-`ORDER BY`, `DISTINCT` og `min/max` over tekst, der føder en rækkefil, en projektion, et ark eller en
   hash, får `COLLATE "C"`. Mindst `identity_control_rows.sql` (l. 11, 19), `identity_sheet_rows.sql` (l. 26) og
   `persona_family_context` (`schema.sql:15375`); planen gennemgår alle rækkefiler og projektioner. Brud på
   lighed sker på `interpretation_key COLLATE "C"`, ikke på et tilfældigt `interpretation.id` (fx
   `identity_sheet_rows.sql:23,26`, `identity_candidate_input` `schema.sql:8811-8821`). Rækkefilernes SQL låser
   `TimeZone` og `search_path`.
6. **Note til overførslens plan:** klassifikationshændelsers evidensfelt `decision_interpretation_id` føjes til
   listen over udeladte felter i overførsels-spec'ens §7.

## 5. Test (test først)

1. **To baser giver det samme (hovedtesten).** Samme syntetiske kæde køres i to baser med forskelligt
   databasenavn, **forskellig collation og tidszone** (fx `createdb --template=template0 --locale=C` mod
   `en_US.UTF-8`, forskellig `TimeZone`) og forskellig tilfældig forhistorik.
   **Fixturkontrakt:** alt, der simulerer restoren (personer, familier, klausulobservationer, 149b-hovedpersoner
   med omtaler og fortolkninger, aktørprofilen), seedes med identiske eksplicitte id'er i begge baser. Intet af
   det, kæden selv skriver, seedes på forhånd. Den tilfældige forhistorik indføres kun i uvedkommende tabeller og
   sekvenser. Kæden er: ægtefællepersonas, 5a-kandidatkørsel, kandidatkørsel 2, kontrolkørsel og
   rækkefilerne for alle ark i §4. De 8 arters id'er, stikprøven, kortrækkefølgen, rækkefilerne og den
   genererede ark-SQL skal være byte-identiske. Testen køres først mod den nuværende kode og skal fejle, og
   den røde kørsel skal udpege, hvilke af de 8 arter og artefakter der afviger.
2. **Kollision:** en eksisterende række med samme id og anden naturlig nøgle giver `DETERMINISTIC_ID_COLLISION`,
   også når den opstår som `unique_violation` på primærnøglen; samme indhold igen er idempotent eller giver den
   nuværende konfliktkode.
3. **Arkværktøjer:** `O`-linjer på `interpretation_key`, opslag ved kørsel, gammelt format afvist; kontrolarkets
   rækkefølge; v3 uden dato. Eksisterende pytest, SQL-tests og e2e-scripts opdateres.
4. **Migrationsvejen.** Alle ændrede funktioner defineres i **én ny afsluttende blok** sidst i
   `db-migrations.sql`. Den sidste definition vinder lydløst, og `write_relation_persona` er i dag defineret 4
   gange (l. 20293, 22752, 23091, 23942), `decide_source_persona_identity` 2 gange (l. 6487, 22327). CI's
   paritetsliste (`tests/sql/inspect-reimport-writer-catalog.sql`, `pg_get_functiondef`-hash mellem frisk
   skema og migreret base) udvides med alle ændrede funktioner, herunder `spouse_exception_projection`,
   `relation_persona_v3_input`, `write_relation_persona`, `decide_source_persona_identity`,
   `red_record_identity_candidates` og `red_register_identity_control_run`.
5. **Opgraderingstest fra `140a17b`:** skemaet bygges fra `git show 140a17b:…`, og den nye `db-migrations.sql`
   og `db-rls.sql` køres oven på to gange. Derefter køres alle 5a/5b-SQL-tests, **hovedtesten (§5.1)** og
   `db-verify` på den opgraderede engangsbase. At `140a17b` er prods træ, bekræftes af overførslens fase 0
   (katalogfingeraftryk). Ingen har kørt hele 5a→#244-sekvensen fra det træ før (ACL-porten
   `db-migrations.sql:18945` ramte del 1 én gang), så planen afsætter tid til fejl, der ikke skyldes leddet.
6. **Lokal CI:** hele CI-jobbene, ikke kun de nye tests (memory: repo-vide vagter).

## 6. Færdigbevis og afgrænsning

- **Færdigbevis:** §5.1 rød → grøn; §5.2-§5.4 grønne; lokal CI 7/7; Opus-slutreview af grenen; merge. Den
  egentlige generalprøve er overførslens arbejdskørsel og genspilsprøve.
- **Modenhed:** leddet er `isoleret implementeret` indtil overførslen.
- **Ikke med:** overførslens scripts og svaroverførslen af de gamle ark; ændringer af beviskæden; tilfældige
  id'er i delte RPC'er og batch-/bindingstabeller; dispositionsmanifesternes `citing_interpretation_ids`
  (tilfældige afgørelsesversions-id'er), så dispositionsmanifester og deres autorisationshashes er ikke
  byte-identiske, men verificeres pr. nøgle i overførslen (overførsels-spec §6.2, §7); en `generator_version` i kandidatkørslens unikke nøgle (et
  eksisterende forhold, ikke skabt af determinismen).

## 7. Revision efter Fable-review (2026-10-21)

Uafhængig Fable-agent uden samtalekontekst; dom GO med rettelser. Collation-fundet (`identity_control_rows.sql`
l. 11/19) og de konkurrerende definitioner i `db-migrations.sql` er efterprøvet mod koden.

| Fund | Ændring |
| --- | --- |
| M1 — collation på tværs af platforme | §4 pkt. 5 (`COLLATE "C"`, brud på `interpretation_key`, låst `TimeZone`/`search_path`); §5.1 to baser med forskellig collation og tidszone |
| M2 — hovedtestens fixturkontrakt | §5.1 fixturkontrakt; rød kørsel udpeger afvigende arter |
| M3 — konkurrerende definitioner | §5.4 én afsluttende blok og udvidet paritetsliste; §5.5 hovedtesten på den opgraderede base |
| m1 — O-opslag uden version | §4 pkt. 1 |
| m2 — omtalens nøgle | §3 (persona, rolle, ordinal) |
| m3 — kollision ikke race-sikker | §3, §5.2 |
| m4 — stikprøvens metode | §3 metodemærke, erratum og decisions-linje |
| m5 — tilfældige brud på lighed | §4 pkt. 5 |
| m6 — dispositionsmanifester | §6 |
| m7 — `decide_source_persona_identity` er fælles | §3 |
| m8 — v3-datoen | Uændret (godtaget af reviewet) |
