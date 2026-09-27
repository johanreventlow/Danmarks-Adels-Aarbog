# Kontrolmodellen — første kørsel (2018-20, pilotens 32 poster)

Beslutning: `docs/decisions.md` 2026-09-27. Plan: `docs/superpowers/plans/2026-09-27-trin4-kontrolmodel.md`.
Spec: trin 4 §8.2 ERRATA 2026-09-27. Kørt 2026-09-27 i en kopi af restoren, aldrig i prod.
Rapporten indeholder record-nøgler, tal og hashes — ingen klausultekst og ingen claim-værdier.

## Kort svar

Kontrolmodellen gav **samme resultat som 4.5's fulde ark — med 26 kort i stedet for 243**. De 43
bindinger er identiske med 4.5's (samme forslag, samme mål), og 48 af 49 afgørelser er de samme; den
ene forskel er en fejl, projektejeren fandt under gennemlæsningen af det korte ark. Begge fejl, piloten
har kendt, lå blandt uoverensstemmelserne — det menneske-sete udsnit — ingen blandt de forslag, der
matcher databasen.

## Grundlag

| | |
| --- | --- |
| Base | `daa_kontrol_20260927101655` = kopi af restoren `daa43b_20260912192527` (84 forslag, hash `7171190b…` som forventet), løftet med `db-migrations.sql` + `db-rls.sql` (0 fejl) |
| Ingest | 4.5's forslagsmanifest (`25732a53…`) genafspillet med 4.5's dry-run og apply: 243 `proposed`, 27/21 dispositioner, kanonisk delta 0 |
| Samme forslag som 4.5 | Nøgle-, prædikat- og værdihash over alle 243: `742d5b89a726a24e10063efd1bdb109e` i både kopien og 4.5's arbejdsbase |
| Klassifikation | `223784e3f8faf99a547056ff1a042adac9c8679dab6af1c6f109d8c8d5387e98` |
| Rækkefil | `3d053e7d0bae42f48fc388b982476ea6ab622244d2d24bace5180f3f8e99bfcc` |
| Stikprøve (seed `kontrolmodel-v1`, 20) | `1ceec43cd3d21eb44459f69ea966fefde2e0488aa3a91e61136d3c9495b60f70` |
| Menneskets rækkefil / maskinplan | `50e1096c…f1e3` / `fdfec503…45fb` |
| Godkendt ark | `f4616fa5ac73e9a1b8d54d463edf9f1febee5e99f700a3023ab4aafbe3c690df` (projektejeren 2026-09-27) |
| Bindingsbatch | `711c2482-3e00-451a-b534-0be74ee27e4d` |

## Klassifikationen

| Prædikat | `MATCH` | `SKRIVEMAADE` | `NO_FACT` | `REAL_DIFF` |
| --- | ---: | ---: | ---: | ---: |
| `person.name` | 16 | 0 | 0 | 3 |
| `person.birth` | 13 | 6 | 0 | 0 |
| `person.death` | 11 | 10 | 2 | 2 |
| `person.title` | 3 | 0 | 4 | 1 |
| **I alt (71 promoverbare)** | **43** | **16** | **6** | **6** |

`AMBIGUOUS`, `MATCH_SINGLETON`, `NO_IDENTITY`, `NO_PLACEMENT`, `UNSUPPORTED_RULE`: 0. De 172
ikke-promoverbare forslag indgår ikke.

## Kørslen

1. **Stikprøve:** 20 af de 43 `MATCH`, trukket og hash-bundet før arket blev bygget.
2. **Arket:** 26 kort (20 stikprøve + 6 uoverensstemmelser), forudfyldt med projektejerens egne
   4.5-afgørelser. Projektejeren læste arket, rettede ét kort og godkendte hashen: **24 A, 2 R**, begge
   R blandt uoverensstemmelserne ⇒ stikprøven fuldt accepteret, ingen STOP.
3. **Negativtest:** den maskinelle accept kørt *før* menneskets afgørelser ⇒ `SAMPLE_NOT_APPLIED`, 0
   skrevet. Første forsøg afviste med `permission denied for schema private` — rigtigt udfald af forkert
   grund: kontrollen kørte efter rolleskiftet til `authenticated`. Rettet med test først (commit
   `6e8752a`) og gentaget.
4. **Skrivning:** menneskets 26 (`human-sheet-kontrol-v1`), derefter 23 maskinelle
   (`machine-corroboration-v1`), rc=0 begge. 194 forslag forbliver `proposed`.
5. **Mængdekontrol:** målfindingens `MATCH`-sæt = maskinsættet ∪ stikprøven — `CONTROL_TARGETS_OK 43`.
6. **Binding:** 43 i ét batch; `fact` 7.197 og `assertion` 9.306 uændrede; ny målfinding giver 0 `MATCH`
   og 43 `ALREADY_PROMOTED`.

## Sammenligning med 4.5

| | 4.5 (fuldt ark) | Kontrolmodellen |
| --- | ---: | ---: |
| Kort for mennesket | 243 | **26** |
| Afgjort af mennesket / maskinen | 243 / 0 | 26 / 23 |
| Bindinger | 43 | 43 — **identiske** (forslag og mål) |
| Afgørelser enige med 4.5 | — | 48 af 49 |

Den ene uenighed er `person.death` på I-7, som projektejeren accepterede i 4.5 og afviste nu: teksten
siger, at personen *var død* på datoen, ikke at han døde den dag. Claimet var aldrig bundet (databasens
dødsdato er en anden), så ingen binding var forkert.

## Fund

**Begge kendte fejl lå hos mennesket, ikke hos maskinen.** Pilotens to fejl (I-11 og I-7) er samme
fejllæsning: modellen læser »var † [dato], da …« som dødsdag. Begge var `REAL_DIFF` — databasen havde en
anden værdi — og blev derfor vist. Ingen af de 43 `MATCH` er kendt forkerte; alle 43 er set af
projektejeren i 4.5, heraf 20 igen i stikprøven. En tredje formulering (I-96, »† 1632, før 20. okt.«)
blev drøftet og står som sand: der er kvalifikatoren bevaret i værdien.

**Forslag til rettelse af prompten:** en regel om »var død/† [dato], da …« (seneste grænse, ikke
dødsdag). Det kræver en ny promptversion og dermed en ny runner-kontrakt; afgøres for sig.

**Hvad kørslen ikke beviser:** at stikprøven fanger en fejl, som model og database *deler* — ingen
sådan fejl optrådte. Forbeholdet i beslutningen står ved magt.

## Konsekvens for 4.5

Projektejerens rettelse af I-7 gør 4.5's præcision til **241/243 = 99,2 %** (1 fejl blandt 159 nye
forslag, ikke 0). Dommen er uændret. I 4.5's arbejdsbase står I-7 som `accepted` (ubundet) og kan ikke
rettes via RPC'en, som kun afgør `proposed`; det godkendte 4.5-ark skal derfor rettes og godkendes med
ny hash, før pilotens afgørelser overføres til prod.
