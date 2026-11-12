# Færdigbevis: 2018-20's fødsler og dødsfald bundet til bogens post i prod (2026-11-12)

Spec: `docs/superpowers/specs/2026-11-12-2018-20-dato-bindinger-design.md` (§7). Plan:
`docs/superpowers/plans/2026-11-12-2018-20-dato-bindinger.md` Task 6. Runbook:
`docs/runbooks/2018-20-dato-bindinger-prod.md`. Kun udfald, antal, id'er og koordinater; Conrad (392) er spec'ens
offentlige eksempel.

## Forløb

| Trin | Resultat |
|---|---|
| Kode | PR #322 (regel `dato-markoer-v2`, måling, kontrolværktøj), runbook #324 + #326; GO'erne bundet til `main` @ `2ac193a9` |
| Runner | `~/.private/5ab-overfoersel/38-dato-bindinger.sh` (sha `8d923049…`), projektejeren kørte alle skrivende trin i sin shell |
| `maal` foer | `tilstand=foer`, tal `0,0,0,568,15,0,0,67,88,1759`, bindingshash `fa08bb8a…`, 17,6 s (sekunderne fra ceremoniens session; tallene står også i DDL-loggen) |
| `vejb` foer | største median 132 ms (405), 0 kolde fejl |
| `dump` foer | `a7add600…` (age `736c4031…`, SFTP-rundtur ok) |
| DDL (GO `7f9e6656`) | `tilstand=ddl verify=ok`, 16,8 s (kvitteringen læst i ceremoniens session; loggen `apply-ddl-20261112211138.log` viser målingen foer → ddl); writerens definition og ACL gemt i `prod/dato/fortryd-ddl-20261112211215/`. Målingen bagefter: tal uændrede, bindingshash uændret |
| `dump` ddl | `ef227696…` (age `a8710a7e…`, rundtur ok) |
| `forbered-n` | 565 af kilde 1's 583 datoforslag får en v2-version; listen = øvelsens (sha `f1e6d2e3…`) |
| `apply-n` (GO `50178e6e`) | `DATO_APPLY_N_OK tilstand=n versioner=565`, 57,1 s. Aftryk: kun `extraction_run` +1, `interpretation` +565, `interpretation_observation` +565 |
| `maal` n | `565,509,0,59,15,0,0,67,88,1759`, bindingshash uændret `fa08bb8a…` |
| `kort` | 20 personas, 1 side, eksport 44,9 s |
| Svar | projektejeren: 20 × `-` (personas), 20 × `B` (felter); `flet` → ark `03890f38…`, 65 linjer (antallet følger personas; øvelsen havde 18 personas og 61 linjer) |
| `dump` n | `96a3f303…` (age `16f3a0fa…`, rundtur ok), restore-hash `9ca72cd5…`, 0 forældreløse, 162 s + 43 s måling |
| `apply-k` (GO `75ef1336`) | `DATO_APPLY_K_OK unresolved=0 rettelser=0 afgoerelser=0 stikproeve=20 maskine=489 bundet=509 … bindinger=tabt:0,nye:509`, 95,4 s (verify 24,6 s). Aftryk: kun `interpretation` +509, `interpretation_observation` +509, `interpretation_promotion` +509, `interpretation_promotion_batch` +1 |
| `maal` k | `tilstand=k`, tal `565,0,0,59,15,509,509,334,330,2268`, bindingshash `c4ef58de…` (= accept) |
| `verify` | `DATO_VERIFY_OK bundet=509 p_personas=0 udeladt_proposed=59 bindinger=tabt:0,nye:509`, 42,2 s |
| `vejb` k | største median 137 ms (405; før 132), alle 10 under 1.000 ms; 10 kolde kald ok (0,6-0,7 s, grænse 3 s) |

## Spec §7

- **Læseren:** se browsertjekket nedenfor. **Opfyldt.**
- **Tal i prod:** fakta-rækker med postens koordinat for kilde 1 steg fra 67 til **334** (fødsel) og fra 88 til **330**
  (død), målt som det læseren viser (`public_person_facts`). Bindingslisten er nøglet: alle 1.759 bindinger fra n-dumpet
  findes stadig, og præcis 509 er nye. Aftrykket viser, at kun de fire ceremonitabeller er ændret. **Opfyldt.**
- **Kæden:** 583 datoforslag (568 `SKRIVEMAADE`, 15 `NO_FACT`) → 565 v2-versioner → 509 `MATCH` → stikprøve 20 (0 fejl) → 509 afgørelser (20 fra arket, 489 maskinelt) →
  509 bindinger. Resten (74): 59 `SKRIVEMAADE` (13 fødsler, 46 dødsfald) står `proposed`, 15 `NO_FACT` (dødsfald). **Opfyldt.**
- **Fart:** de 10 tungeste personers fakta-kald som `anon` har median ≤ 137 ms. **Opfyldt.**
- **Status:** `status.md` er opdateret.

## Browsertjek som anon mod `danmarks-adels-aarbog.vercel.app` (headless Chromium)

| Side | Udfald |
|---|---|
| Conrad `/person/392` | Født og død: »DAA 2018-20, s. 201-202 · V-1« med »✓ også i DAA 1939« |
| `/person/399` (stikprøven; har kun et dødsforslag) | Død: »DAA 2018-20, s. 224-225 · V-105«. Fødslen har intet 2018-20-forslag og viser fortsat »DAA 2018-20« |
| `/person/514` (stikprøven) | Født og død: »DAA 2018-20, s. 208 · V-29« |
| `/person/405`, `/442`, `/546` (blandt de tungeste) | Født og død med »DAA 2018-20, s. N · V-…« |
| Resten: `/person/10` (I-107, død = `SKRIVEMAADE`) | Død: kun »DAA 2018-20« (uændret) |
| Resten: `/person/20` (I-116, fødsel = `SKRIVEMAADE`) | Født: kun »DAA 2018-20« (uændret) |
| Alle otte sider | **0** forekomster af `record-<uuid>` og `legacy-source:` i DOM'en |

Rest-personerne er fundet ved at slå `SKRIVEMAADE`-elementernes personas op i den lokale prod-kopi
(`private.source_persona_identity`, alle `accepted`).

## Fortrydelse

Grundlaget er n-dumpet `daa-prod-20261112220624-dato.dump` for `k` og ddl-dumpet `daa-prod-20261112212606-dato.dump`
for `n` (runbookens `fortryd`). Fra nu af er rettelser almindelig redigering.

## Ikke gjort

- **Security Advisor** efter DDL'en: sessionen kan ikke køre `get_advisors` (Supabase-MCP'en ser ikke projektet).
  Grants, `search_path` og RLS er tjekket af runneren og statisk.
- **Del 2** (spec): kortene over de 59 `SKRIVEMAADE` er ikke kørt. Det afgør projektejeren.
- Prod-filerne (dumps, `.foer-codex`-backup af runneren) og den lokale stand-in `daa5ab_ddl_standin_20261112154600_dato`
  er ikke ryddet. De måles før oprydning.
