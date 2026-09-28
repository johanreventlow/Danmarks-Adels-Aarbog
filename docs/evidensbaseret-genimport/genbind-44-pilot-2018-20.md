# Genbinding af 4.4 — piloten om på de omsegmenterede klausuler (2018-20)

Beslutning: `docs/decisions.md` 2026-09-27, skridt 5. Plan:
`docs/superpowers/plans/2026-09-28-trin4-genbind-44-pilot-om.md`. Kørt 2026-09-28 i en lokal kopi af et
frisk prod-dump, aldrig i prod. Rapporten indeholder record-nøgler, tal og hashes — ingen klausultekst og
ingen claim-værdier.

## Kort svar

Kæden holder på de klausuler, prod faktisk har. De 34 poster (4.3b's 10 + 4.5's 24) gav **230 forslag,
46 bindinger og 24 kort for projektejeren**, alle 24 accepteret — stikprøven fuldt, så 26 forslag blev
accepteret maskinelt. Modellen brugte **ingen værktøjer** (første kørsel med P1's værn), og forbruget var
det samme som 4.3b+4.5 tilsammen. Færdigbevisets pilotdel (≥30 poster gennem hele kæden i én base,
rapport med tal og hashes) er opfyldt: 32 poster gav forslag. Den sidste del — 4.4's prod-GO-pakke
genbundet — udestår (Task 5, egen GO).

Tre mulige årsager til forskelle mod 4.5 er målt hver for sig. **Runnerens nye regler (1.1-1.3) og
basens kanoniske fakta forklarer intet** — begge er målt til nul forskel. Det, der er tilbage, er
klausulgrænserne (8 poster) og at alle poster er sendt til modellen igen. Det sidste er det største:
selv på de 26 poster med uændrede klausuler går kun 124 af 183 tidligere forslag igen ordret.

## Grundlag

| | |
| --- | --- |
| Prod-dump (læse-kun) | `ddbe94b8…`; tilstand `591\|984\|591\|1\|0\|0\|1` |
| Arbejdsbase | `daa44g_20260928170311` (restore af dumpet + `db-migrations.sql`/`db-rls.sql` fra `main`) |
| Kode | `main` `1dfce3e` (#226); `runner_code_sha256` `2c411820…` = manifestets |
| Kontrakt | profil `daa-2018-20-v2` 1.4.0, prompt `d46cda80…`, model `gpt-5.6-terra`, `evidence-runner-1.3`, codex-cli 0.155.1 |
| Pre-run-manifest (GO) | `72b8ac59b152c9ef3199a1777e811ec26e528dadb90258cc3f008291df7527fb` |
| Runner-input (GO) | `0b51ed9aeef8993d82a8eabef5c961a2f234201d7118216395d3ca653ccf8bab` |
| Ledger | `f6d251ff…` (488 `eligible` / 103 `excluded`) |
| Bedømmelsesark pr. bundt | `bundt_43b` `e9997303…`, `bundt_1` `b6bfb768…`, `bundt_2` `c6606463…`, `bundt_3` `f5098cdd…`, `bundt_4` `37db66d0…` |
| Forslagsmanifest | fil `97246619…`, indhold `75ac6e5f79768149abc754c2ae23a0bce0fb80d8fe6155cb3df210f09b3e65f2` |
| Klassifikation / rækkefil | `d7cc44ce…` / `a5faf07a…` |
| Stikprøve (seed `kontrolmodel-v1`, 20) | `bdd62bcbdce4e18d5e4802e15ae4f63f3624ce1f27e8e338d330648474a066bb` — noteret før arket blev bygget |
| Menneskets rækkefil / maskinplan | `4306e9e0…` / `4a35980f…` |
| Godkendt ark | `2500531c15ced25d2a4eb741a720f5737fc65e2af5f9542f5f621f63c919e8de` (projektejeren 2026-09-28) |
| Bindingsbatch | `f214ccf2-4926-4061-8e65-ed6bfc322f13` |

## Kørslen

1. **Modelkald** (Task 1), fem bundter fra `main`, adgangstesten før hvert kald: 34/34 dækket (27 hele,
   7 delvise), 233 gyldige claims, 16 afviste, **`tool_use` 0**, 597.185 input-tokens. I-29 og III-104
   gav 0 claims, som i 4.3b (korte poster). Gate V1: 32 ≥ 30 — reserven blev ikke brugt.
2. **Ingest** (Task 2): regnskabet 249 rå − 16 kontrakt − 3 H1 − 0 dubletter − 0 ukendt rolle = **230**
   (183 om hovedpersonen, 47 om andre). Forventningen blev skrevet før kørslen og ramt på alle tal:
   230 forslag, 32 hændelser, 41 citerede klausuler (26 `afventer_identitet`, 15
   `fortolkning_foreslaaet`), kanonisk delta 0. Dry-run før apply. `db-verify.sql` på en engangskopi:
   0 fejl.
3. **Kontrolmodellen** (Task 3): 69 promoverbare — 46 `MATCH`, 16 `SKRIVEMAADE`, 4 `REAL_DIFF`, 3
   `NO_FACT`. Arket = 20 stikprøve + 4 uoverensstemmelser = **24 kort**, under loftet på ~30.
   Forudfyldningen var snævret ind (kun hovedpersonen, kun de 26 uændrede poster, fra 4.5-arket
   `c92a6e80…` og kontrolarket `f4616fa5…`, ingen modstrid, ingen `U`): 10 kort forudfyldt, 14 tomme —
   heraf 7 fra omsegmenterede poster. Projektejeren udfyldte alle: **24 A, 0 R, 0 U**.
4. **Negativtest:** den maskinelle accept kørt før menneskets afgørelser ⇒ `SAMPLE_NOT_APPLIED`, 0 skrevet.
5. **Skrivning:** 24 (`human-sheet-kontrol-v1`), derefter 26 (`machine-corroboration-v1`); 180 forslag
   forbliver `proposed`.
6. **Mængdekontrol og binding:** `CONTROL_TARGETS_OK 46`; 46 bundet i ét batch; `fact` 7.197 og
   `assertion` 9.306 uændrede; en ny målfinding giver 0 `MATCH` og 46 `ALREADY_PROMOTED`. De 4
   accepterede uoverensstemmelser (I-24, I-43, V-18 `person.name`; IV-19 `person.title`) står
   accepteret og ubundet — nye fakta er åbent punkt 11.3. Hver af dem er et sted, hvor projektejeren
   har sagt, at kilden siger noget andet end databasen.

## Årsagerne skilt ad

| Mulig årsag | Måling | Resultat |
| --- | --- | --- |
| Runnerens regler (4.5 kørte 1.0; nu 1.3) | 4.3b's og 4.5's gemte svar genvalideret offline med dagens validator (`build_43b_proposal_manifest.py --historisk-foer-p1`) | Byte-identiske manifester (`a328ede9…`, `25732a53…`): **0 ekstra afvisninger** |
| Basens kanoniske fakta (restore 12/9 vs. prod 28/9) | Fakta og assertions for udvalgets 39 identificerede personer, hash over `to_jsonb` | 176 fakta / 182 assertions i begge, **identiske hashes** |
| Klausulgrænserne | De 8 omsegmenterede poster (I-3, I-7, I-11, I-43, I-97, I-112, I-120, I-133; 34 → 14 klausuler) mod de 26 uændrede | Se tabellen nedenfor |
| Nyt modelkald | De 26 uændrede poster: samme klausuler, prompt og model | Se tabellen nedenfor |

## Sammenligning, delt på omsegmenterede og uændrede poster

»Før« er 4.3b+4.5 (samme 34 poster). Forslag og klasser er fra kontrolmodel-kørslens artefakter
2026-09-27; dens base er slettet, så bindingerne er hentet fra 4.5's arbejdsbase
`daa45_pilot_20260924093200` (via `supersedes_id` tilbage til forslaget) — kontrolmodel-rapporten viste,
at de 43 er identiske. Bindinger er sammenlignet på (post, prædikat, mål-assertion).

| | 8 omsegmenterede<br>før → nu | 26 uændrede<br>før → nu | I alt<br>før → nu |
| --- | ---: | ---: | ---: |
| Forslag | 60 → 56 | 183 → 174 | 243 → 230 |
| — heraf ordret igen (post, prædikat, værdi, rolle) | 37 | 124 | 161 |
| `MATCH` | 13 → 11 | 30 → 35 | 43 → 46 |
| `REAL_DIFF` | 4 → 1 | 2 → 3 | 6 → 4 |
| `NO_FACT` | 2 → 2 | 4 → 1 | 6 → 3 |
| `SKRIVEMAADE` | 2 → 2 | 14 → 14 | 16 → 16 |
| Bindinger | 13 → 11 (11 fælles) | 30 → 35 (27 fælles) | 43 → 46 (38 fælles) |
| Input-tokens (nu) | 143.942 | 453.243 | 597.185 (før 596.335 + I-11-tillæg) |

| | Før | Nu |
| --- | ---: | ---: |
| Kort for mennesket | 243 (4.5) / 26 (kontrolmodellen) | **24** |
| Afgørelser på kortene | 24 A / 2 R | 24 A / 0 R |
| Maskinelt accepteret | 23 | 26 |
| `tool_use` | ikke målt (før P1) | 0 |

## Fund

**1. De to kendte fejllæsninger er væk.** I-11 og I-7 havde begge en ekstra `person.death` fra
konstruktionen »var † [dato], da …« ud over den rigtige dødsdato (kontrolmodel-rapporten). Nu er der kun
den rigtige, og den er `MATCH`. Begge poster er omsegmenteret, men da de også er sendt til modellen igen,
kan klausulgrænserne ikke gives hele æren. Promptreglen for »var †« er fortsat en kandidat.

**2. Nyt modelkald er den største kilde til forskel.** På de 26 uændrede poster er kun 124 af 183 forslag
(68 %) ordret de samme; 8 bindinger er nye, og 3 er faldet bort (alle `person.name`/`person.title`,
typisk en anden navneform). Det er ikke en fejl, men det betyder:
- en genkørsel kan ikke bruges til at bevise, at en ændring virker på enkeltposter;
- prod skal have **præcis disse forslag** (samme svar fra cachen), ikke et nyt modelkald. Da forslagets
  id er nyt ved hver ingest, skal prod-pakken bære `interpretation_key` eller køre kontrolmodellen igen
  i prod (Task 5).

**3. Den snævre forudfyldning virkede.** 14 tomme kort af 24 blev afgjort aktivt; ingen forudfyldt dom
blev ændret. Arket krævede én læsning.

**Hvad kørslen ikke beviser:** præcision på de 180 forslag, der ikke er promoverbare, eller på de 16
`SKRIVEMAADE` — de er hverken set af et menneske eller bundet. Forbeholdet fra kontrolmodellen står
ved magt: en fejl, som model og database deler, fanges kun, hvis den er i stikprøven.

## Næste

Task 5: 4.4+4.5's prod-GO-pakke genbindes til disse forslag og afgørelser — egen GO. Samme GO lukker
omsegmenteringens fortrydelsesvindue. Private artefakter: `~/.private/genbind-44/` (0600).
