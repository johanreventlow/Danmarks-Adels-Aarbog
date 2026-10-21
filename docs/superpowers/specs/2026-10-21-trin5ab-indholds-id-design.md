# Trin 5a + 5b — id'er af indholdet (forudsætningsled for prod-overførslen)

**Status:** designudkast. Godkendt afsnit for afsnit i brainstormen 2026-10-21. Afventer Fable-review.

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
| `source-mention` | `observation_id`, `mention_kind`, `char_from`, `char_to` | planen efterprøver; ellers persona-id + rolle |
| `identity-candidate-run` | `source_id`, `input_sha256`, `config_sha256` | UNIQUE (samme tre) |
| `identity-candidate` | kørsels-id, `source_persona_id`, `candidate_person_id` | UNIQUE (samme tre) |
| `identity-control-run` | `candidate_run_id` | UNIQUE (`candidate_run_id`) |
| `identity-control-sample` | kontrolkørsels-id, `source_persona_id` | UNIQUE (samme to) |
| `identity-control-parent-card` | kontrolkørsels-id, `interpretation_key` | UNIQUE (samme to) |
| `identity-event` | `source_persona_id`, `version` | UNIQUE (samme to) |

Alle id'er indsættes eksplicit i funktionskroppene. Tabellernes kolonnestandard (`gen_random_uuid()`) bliver
stående, så andre writere og ældre rækker er upåvirkede.

**Kollision fejler lukket.** Hvert indsæt kontrollerer, at en eksisterende række med samme id har samme
naturlige nøgle. Har den ikke, kastes `DETERMINISTIC_ID_COLLISION` med arten i beskeden. Samme indhold igen
opfører sig som i dag: kandidatkørslen er idempotent (`ON CONFLICT` + `candidates_sha256`, ellers
`IDENTITY_CANDIDATE_RUN_CONFLICT`), kontrolregistreringen returnerer den eksisterende kørsel, og writerens
`…_RELATION_PERSONA_EXISTS` gælder fortsat.

**Stikprøve og kortrækkefølge** trækkes efter indhold, ikke efter id'er:
- stikprøvens rækkefølge: `sha256(input_sha256 ‖ ':' ‖ config_sha256 ‖ ':' ‖ persona_key)` for kandidatkørslen;
- kortenes visning: `sha256(input_sha256 ‖ ':' ‖ config_sha256 ‖ ':' ‖ persona_key ‖ ':' ‖ candidate_person_id)`.

Trækningen er stadig en ensartet pseudotilfældig fordeling inden for hvert stratum. Den er nu reproducerbar i
enhver base med samme indhold.

**Uændret:** #153's writer og batch-/autorisationstabeller, `red_decide_interpretation`, ekstraktionskørsler,
bindinger og bindingsbatches, #244's rettelsestabel. Ingen offentlig funktionssignatur ændres.

## 4. Arkværktøjerne

1. **2b-i's undtagelsesark:** `spouse_exception_projection` udgiver `O`-rækker med `interpretation_key` og
   version i stedet for `interpretation_id`, og uden `state_sha256` (ligheden med den gældende tilstand tjekkes
   fortsat ved kørsel). `spouse_exception_sheet.py`'s `O`-linjer får formen `O <interpretation_key> <version>
   bog/fam`, og den genererede SQL slår det gældende id op ved kørsel (som `relation_marriage_sheet.py:121`).
   Kontrakten hæves til `spouse-exception-rows-v2`; det gamle format afvises med en tydelig fejl. Overførslens
   svaroverførsel læser de gamle godkendte ark med sin egen parser.
2. **Kontrolarkets rækkefil** får en total rækkefølge: art, post (`record_key`), nøgle (`persona_key` eller
   `interpretation_key`).
3. **v3-arket:** datoen for den tidligere afgørelse fjernes fra projektionen og fra kortet. Grundlag og note
   vises fortsat.
4. **De øvrige ark** (5a's identitetsark, 2b-ii, børnearket, nummerarket) bliver deterministiske af §3 alene.
   Deres eksisterende rækkefølger brydes i dag på persona-id, som nu er deterministisk.
5. **Note til overførslens plan:** klassifikationshændelsers evidensfelt `decision_interpretation_id` føjes til
   listen over udeladte felter i overførsels-spec'ens §7.

## 5. Test (test først)

1. **To baser giver det samme (hovedtesten).** Samme syntetiske kæde køres i to baser med forskelligt
   databasenavn og forskellig tilfældig forhistorik (fx et forskelligt antal forudgående `gen_random_uuid()`-
   kald og rækker i andre kilder): ægtefællepersonas, 5a-kandidatkørsel, kandidatkørsel 2, kontrolkørsel og
   rækkefilerne for alle ark i §4. De 8 arters id'er, stikprøven, kortrækkefølgen, rækkefilerne og den
   genererede ark-SQL skal være byte-identiske. Testen køres først mod den nuværende kode og skal fejle.
2. **Kollision:** en eksisterende række med samme id og anden naturlig nøgle giver `DETERMINISTIC_ID_COLLISION`;
   samme indhold igen er idempotent eller giver den nuværende konfliktkode.
3. **Arkværktøjer:** `O`-linjer på `interpretation_key`, opslag ved kørsel, gammelt format afvist; kontrolarkets
   rækkefølge; v3 uden dato. Eksisterende pytest, SQL-tests og e2e-scripts opdateres.
4. **Opgraderingstest fra `140a17b`:** skemaet bygges fra `git show 140a17b:…`, og den nye `db-migrations.sql`
   og `db-rls.sql` køres oven på to gange. Derefter køres alle 5a/5b-SQL-tests og `db-verify` på en
   engangsbase. At `140a17b` er prods træ, bekræftes af overførslens fase 0 (katalogfingeraftryk).
5. **Lokal CI:** hele CI-jobbene, ikke kun de nye tests (memory: repo-vide vagter).

## 6. Færdigbevis og afgrænsning

- **Færdigbevis:** §5.1 rød → grøn; §5.2-§5.4 grønne; lokal CI 7/7; Opus-slutreview af grenen; merge. Den
  egentlige generalprøve er overførslens arbejdskørsel og genspilsprøve.
- **Modenhed:** leddet er `isoleret implementeret` indtil overførslen.
- **Ikke med:** overførslens scripts og svaroverførslen af de gamle ark; ændringer af beviskæden; tilfældige
  id'er i delte RPC'er og batch-/bindingstabeller; en `generator_version` i kandidatkørslens unikke nøgle (et
  eksisterende forhold, ikke skabt af determinismen).
