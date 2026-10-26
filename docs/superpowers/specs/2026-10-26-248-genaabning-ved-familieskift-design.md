# #248 rute A: genåbning af et accepteret ægteskab ved familieskift — design

- **Issue:** #248. **Beslutning:** `docs/decisions.md` (#248, 2026-10-26), punkt 2 og 4.
- **Forudsætning:** skridt 1 (`fix_248_identitet.sql`) er kørt i prod 2026-10-26 (PR #265, GO 248 `cc3d684e`,
  `FIX248 fase=efter`; kørselsnote PR #266). De to ægtefæller peger på den rigtige
  person, og deres ægteskaber står `accepted` uden gældende binding.
- **Review:** ruterne er reviewet af Fable (GO til A med ændringer). Ændringerne er indarbejdet her.

## 1. Roadmap-kobling

| Spørgsmål | Svar |
|---|---|
| Roadmapmål | Trin 5 (#151, 5b): én identitetsvej |
| Værdikædeled | Afgørelse → promotion: en relation følger en rettet identitet |
| Leverancetype | Generel mekanisme (ægteskaber i alle udgaver); ingen udgaveprofil |
| Værdi | Læseren ser kildeteksten på den rigtige familie; redaktøren kan rette en navnefælle uden ejer-SQL |
| Færdigbevis | De to ægteskaber fra #248 er bundet til familie 65 og 194 i prod; tests i CI; 0 kanonisk delta |
| Erstatter | Hullet fra 2b-i-spec'en §13 pkt. 1 (udskudt til 2b-ii, ikke leveret); ingen ejer-SQL ved fremtidige navnefæller |

## 2. Problem

En accepteret ægteskabsfortolkning er afgjort og bundet til en familie. Rettes en parts identitet bagefter, peger
fortolkningens tilstand på en anden familie, men den kan hverken afgøres igen (`red_decide_interpretation` kræver
`proposed`, `schema.sql:8281`) eller bindes til den nye familie (`RELATION_PROMOTION_REBIND_FAMILY_CHANGED`,
`schema.sql:16875`). Spærringen er bevidst: afgørelsen blev truffet for den gamle familie (2b-i-spec §4.4). Det, der
mangler, er en ny afgørelse for den nye familie.

## 3. Design

### 3.1 Genåbning: `public.red_genaabn_relation_interpretation`

`red_genaabn_relation_interpretation(p_interpretation_id uuid, p_expected_version int, p_note text, p_context jsonb)
RETURNS uuid`, SECURITY DEFINER, `search_path=pg_catalog,public,private`.

Laver en ny version af fortolkningen med status `proposed` (`supersedes_id` = den accepterede). Derefter tager
de eksisterende `red_decide_relation_interpretations` → `red_promote_relation_interpretations_batch` den op, som
for ethvert andet ægteskab. Ingen ændring i afgørelses- eller bindingskoden: begge spærrer gælder pr. versions-id
(`schema.sql:16843-16849`), og læseren viser kun bindinger for den gældende version (`public_family_sources`,
`schema.sql:17535`).

**Egnet, kun når alt gælder (ellers en navngiven fejl):**
- rolle `redaktion` og `auth.uid()` sat;
- fortolkningen er den gældende version, `predicate='relation.marriage'`, `status='accepted'`, og afgørelsens
  `decision_evidence->>'method'='family-structure-v1'`; ingen nyere version;
- `private.relation_binding_state(id)` er ikke NULL (er en part gået `unresolved`, er der intet at binde til);
- tilstandens familie ≠ `decision_evidence->>'family_id'` (`…_NOT_NEEDED`, hvis de er ens);
- præcis én seneste familiebinding, og dens familie = `decision_evidence->>'family_id'`;
- `p_note` ikke tom; `p_context` er et hash-bundet ark: `basis='human_sheet'`, `sheet_sha256`, `rows_sha256`,
  `line` (samme form som `red_ret_aegteskabsnummer`). Ingen web-vej i denne omgang.

**Låseorden** som `red_decide_relation_interpretations` (`schema.sql:16754`): kildelås (eksklusiv) →
fortolkningsrækken `FOR UPDATE` → `lock_family_rows` for parterne.

**Den nye version:** kopi af den accepterede rækkes indholdsfelter; `decided_by`, `decided_by_name`, `decided_at`
og `decision_evidence` er tomme (konventionen for `proposed`; `interpretation_proposal_actor_check`).
Observationslinks kopieres som i `red_decide_interpretation`. Er klausulsættet revideret siden, afviser
`validate_interpretation_observation_current_clause` (`schema.sql:14978`) rent, uden halv skrivning. Id'et er et
indholds-id (nøgle + version), så genåbningen kan genspilles med samme id.

### 3.2 Proveniens: `private.relation_reopen`

Tilføj-kun tabel (som #244's `marriage_ordinal_correction`): `interpretation_key`, `from_interpretation_id`
(den accepterede), `to_interpretation_id` (den nye `proposed`), `superseded_promotion_id` (den gamle binding),
`from_family_id`, `to_family_id`, ægtefællens `source_persona_id` og identitetsversion, `note`, `context`
(arket), `reopened_by`, `reopened_by_name`, `reopened_at`. Unik på `to_interpretation_id`. Ingen adgang for anon og
authenticated; kun RPC'en skriver.

Tabellen er nødvendig: bindingspreviewet sætter `supersedes_promotion_id=null` for den nye version (intet seneste
binding på det id), så kæden fra gammel til ny binding kan ellers kun følges via nøglen.

### 3.3 Forebyggelse: dobbeltmål på menneskevejen

`private.relation_binding_state` returnerer NULL for et ægteskab, når en anden ægtefællepersona i samme forekomst
er accepteret til samme kanoniske person. Maskinvejen har allerede modparten (`FAMILY_CORROBORATION_DOUBLE_TARGET`,
`schema.sql:~16475`). Målt på en kopi af prod i dag: præcis 2 tilfælde, og de er #248's (efter skridt 1: 0).
Havde vagten fandtes, var 4° og 2° blevet stående `proposed` i stedet for at blive bundet forkert. Vigtig før
1939 (mange navnefæller).

Identitetsarket (`spouse_exception_sheet.py`) skal vise, når kandidat nr. 1 allerede er partner til hovedpersonen
i posten. Det er en Python-ændring uden DDL og kan tages i samme gren.

## 4. Følger

- **Klassifikation:** de to gældende `ordinal_afvigelse` står på den gamle version. Efter bindingen afviger 4° (nr. 4)
  og 2° (nr. 2) ikke længere; gældende `ordinal_afvigelse` falder fra 3 til 1. Historik; intet at fortryde.
- **3° og 1°:** anden nøgle og anden persona; deres tilstand bygges kun af nøglens egne parter → uberørt.
- **Klausul-disposition:** uændret (ægtefællen forbliver accepteret, nu til den rigtige person).
- **Kontrolkørsel:** allerede `failed` efter #240 (decisions #240 pkt. 4); personaerne er ikke i stikprøven.
- **Overførselsværktøjets digests** (`transfer_5ab_*`) afviger fra GO 2-pakken. Forventet; dokumenteres.
- **0 kanonisk delta:** kun private evidensrækker.

## 5. Tests

- Udvid `tests/sql/test-relation-binding.sql:775` (»anden familie«) fra negativ til genåbn → afgør → bind: den gamle
  binding forsvinder fra `public_family_sources`, den nye vises, søskendeægteskabets binding er uændret,
  `relation_reopen` har én række.
- Negativtest: samme familie (`…_NOT_NEEDED`), NULL-tilstand, ikke-ægteskab, `proposed`/`rejected`, nyere version,
  manglende eller ugyldig arkkontekst, forkert rolle, gentaget kald.
- Forebyggelsen: to ægtefællepersonas i samme forekomst til samme person → tilstand NULL; forskellige personer →
  uændret.
- Registrering i alle fire filer: `schema.sql`, `db-migrations.sql` (idempotent blok), `db-rls.sql`,
  `db-verify.sql` (ACL: anon og service_role ingen EXECUTE, authenticated ja; tabellen ingen grants).
  Opgraderingstest fra prods nuværende skema. Tjek om katalog- og ACL-fingeraftryk i overførselsværktøjet skal
  have ny basislinje. Hele CI-jobbet køres lokalt før push.

## 6. Prod

1. **DDL-ceremoni:** måling, dump, migrationsblokken i én transaktion, fingeraftryk før og efter, rådgiveren
   (ingen nye fund), `NOTIFY pgrst`. Øves på en stand-in med prods grænse på 2 minutter pr. sætning.
2. **Dataceremoni (ny GO):** et script genåbner de to ægteskaber med GO 248's arkkontekst, afgør beslutningsmængden
   (forventet netop de to) og binder dem (forventet familie 65 og 194). Preview-hashen beregnes i transaktionen,
   som i `fix_go2_dublet.sql`. For- og efterbetingelser; læsemåling.
3. **Id'er:** genåbningens version har indholds-id; afgørelsens og bindingens id'er er tilfældige, som i GO 2. Intet
   hashes eller godkendes på forhånd, der binder til dem.
4. **Fortrydelse:** DDL'en kan rulles tilbage med de gamle definitioner fra dumpet. Data: ingen fortryd-vej efter
   bindingen; dumpet er nødudvejen.
5. **Tid:** `statement_timeout='15min'` sættes og kontrolleres, som i GO 2's runner.

## 7. Uden for scope

- Genåbning af forælder- og barnerelationer (samme mønster senere, hvis behovet opstår).
- En web-vej til genåbning.
- `family_member.ordinal`'s semantik (pr. familie i praksis, pr. person ifølge `web/src/data/model.ts:45`; 92
  personer med én familie og ordinal > 1). Noteret til Fable-reviewet af trin 1-5.
