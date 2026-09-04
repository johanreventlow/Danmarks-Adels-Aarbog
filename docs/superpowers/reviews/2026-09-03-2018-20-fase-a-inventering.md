# 2018-20 fase A: læse-kun inventering (issue #149, §8)

**Dato:** 2026-09-03
**Kilde:** `public.source.id = 1` ("Dansk Adels Aarbog – DAA 2018-20")
**Restore:** prod-dump `pre-c0f-20260821-112005.dump`, SHA-256
`fcfeb22532975d45803b98813e51bdde33b5a79537547b7ce202a28eaf7046b3`, restaureret til
lokal PostgreSQL 17 (`127.0.0.1:55441`), database `daa149_inventory_20260903`.
Alle SQL-målinger kørt i `BEGIN TRANSACTION READ ONLY`. Ingen navne, ingen
narrativtekst, ingen `raw_text` er printet eller skrevet undervejs — kun
`record_key`/`lokal_id`, tal og SHA-256.

**Metode-afvigelse fra opgavens "typiske" opskrift:** `evidence-promotion-bootstrap.sql`s
minimale `auth.users`-stub (2 kolonner) kolliderede med dumpets fulde
`auth`-skema (217 objekter, ejer `supabase_auth_admin`) — `pg_restore` fejlede
på indeks/FK mod manglende kolonner. Løsning: droppede den delvist gendannede
base, oprettede kun de Supabase-roller dumpet refererer (`postgres`, `anon`,
`authenticated`, `service_role`, `authenticator`, `supabase_admin`,
`supabase_auth_admin`, `supabase_storage_admin`, `supabase_realtime_admin`,
`dashboard_user`, `pgbouncer`) og lod dumpet bygge sit eget `auth`-skema
uforstyrret via `pg_restore --no-owner`. 3 ignorerede fejl tilbage, alle fra den
lokalt utilgængelige `supabase_vault`-extension (irrelevant for `public`/`private`).
`public`/`private`-data er fuldt gendannet (verificeret ved rækketal).

## Måling 1 — `public.source`

| id | titel | udgave | aar |
|---|---|---|---|
| 1 | Dansk Adels Aarbog – DAA 2018-20 | DAA 2018-20 | 2020 |
| 2 | Reventlow TNG-genealogi (TNG-dump) | (tom) | (tom) |
| 3 | Dansk Adels Aarbog – DAA 1939 | DAA 1939 | 1939 |
| 4 | Præsensliste — indledning | (tom) | (tom) |

## Måling 2 — source 1: proveniens-tabeller

| Tabel | Antal |
|---|---|
| `narrative` (subjekt_type='person') | 591 |
| `narrative` (subjekt_type='slaegt') | 1 |
| `person_external_id` | 591 |
| `private.source_record` (source_id=1) | **0** |
| `private.source_rendition` (source_id=1) | **0** |
| `private.narrative_record_publication` (join via source_record.source_id=1) | **0** |

Bekræfter spec'ens forudsætning: source 1 har **intet** proveniens-lag endnu —
fase A starter fra et rent bord for rendition/records/ankre/bindinger.

## Måling 3 — `person_external_id`: kolonner og record_key-formatklasser

Kolonner: `person_id, source_id, linje, nr, slaegtled_lokal, slaegtled_gennem, kuld, record_key`.

| Klasse (regex) | Antal | Eksempler |
|---|---|---|
| `^[IVX]+-\d+$` | 586 | I-1, I-10, I-100 |
| `^[IVX]+-\d+[a-z]$` | 5 | I-15a, I-15b, I-15c |

586 + 5 = 591. `record_key`-formen er `linje + "-" + nr_label` (bekræftet
empirisk mod DB, ikke kun antaget fra `load_helpers.R`).

## Måling 4 — injektivitet person ↔ external_id (source 1)

| Måling | Antal |
|---|---|
| Personer med >1 external_id for source 1 | **0** |
| `record_key`-værdier delt af >1 person | **0** |

Fuldt injektiv i begge retninger.

## Måling 5 — mængdeforskel `lokal_id` (posts.json) ↔ `record_key` (DB)

`lokal_id` konverteret til `record_key`-form via `linje + "-" + nr_label`
(ikke streng-erstatning af `.`→`-`, for at være robust mod bogstav-suffikser).

| Måling | Antal |
|---|---|
| Nøgler kun i posts.json | 0 |
| Nøgler kun i DB | 0 |
| Fælles | 591 |

Mængderne er identiske. Ingen afvigende nøgler.

## Måling 6 — narrativ ↔ person (source 1)

| Antal narrativer pr. person | Antal personer |
|---|---|
| 0 | 0 |
| 1 | 591 |
| >1 | 0 |

591/591 personer har præcis 1 narrativ med source_id=1.

## Måling 7 — tekstlighed `narrative_norm_v1(narrativ.tekst)` vs `narrative_norm_v1(post.raw_text)`

Join: person (præcis 1 external_id for source 1, 591/591 er entydige — 0
ambiguøse) → `record_key` → posts.json `raw_text`. Begge sider normaliseret med
den ægte `normalize_narrative_v1()` fra `normalize_narrative_1939_v50.py`
(`corpus` = regenereret `raw.txt`).

| Måling | Antal |
|---|---|
| Byte-lig efter norm | 587 |
| Ulig | 4 |
| Uden matchende post | 0 |
| Ambiguøse personer (>1 external_id) udeladt | 0 |
| Normaliserings-fejl (assert-brud, fx lækket sidemarkør) | 0 |

Længdeforskel-fordeling for de 4 ulige: `>200 tegn`: 4 (ingen i 0-10/11-50/51-200).

De 4 ulige, med fortegn (hvilken side er længst) og længdeforskel i tegn:

| record_key | fortegn | længdeforskel |
|---|---|---|
| IV-94 | raw_text længst | 2.362 |
| I-133 | raw_text længst | 3.187 |
| II-35 | raw_text længst | 1.990 |
| III-129 | raw_text længst | 3.916 |

Alle 4 har **samme fortegn** — `raw_text` (pilotens kildeudtræk) er 2.000-3.900
tegn længere end `narrative.tekst` i prod for alle 4. Det ensartede fortegn
peger mod systematisk indholdstab i prod-narrativet (fx en tidligere
trunkering/redigering), snarere end tilfældig OCR-støj. To af de fire
(**II-35, III-129**) er også blandt måling 8's 68 nøgler — for de resterende
to (**IV-94, I-133**) findes `raw_text` fint som eksakt delstreng i
renditionen, så deres afvigelse er uafhængig af `NOISE_RE`-problemet og en
separat kandidat til 149b's `unresolved_text`.

## Måling 8 — eksakt delstreng i renditionen

To tests: rå `raw.txt` uændret, og en normaliseret projektion (sidemarkør-linjer
`### PAGE n ###` fjernet, derefter `segment.py`s ægte `norm()`).

| Test | Fundet | Ikke fundet |
|---|---|---|
| Rå `raw.txt` | 97 | 494 |
| Normaliseret projektion | **523** | **68** |

Rå-testen fejler bredt som forventet (posts' `raw_text` er allerede
whitespace-normaliseret af `segment.py`, rå renditionen er det ikke).

**De 68 fejler i normaliseret projektion, og fejler stadig selv når AL
whitespace fjernes fra begge sider** (diagnostisk kontrol, ikke en officiel
måling) — dvs. det er ikke et whitespace-problem, men et **indholdstab**.

**Root cause bekræftet empirisk** (diagnostisk måling, ægte `segment.NOISE_RE`/
`segment.PAGE_RE` fra `segment.py`, ikke reimplementeret): `segment.py`s
`_segment_2018_20`-tilstandsmaskine springer linjer over der matcher `NOISE_RE`
(`von\s+R\s*E.*|Ridder\s+.+sønner`, case-insensitivt) **midt i en igangværende
post**, uden at flushe posten først — de springes stille ud af `_lines`, så den
lagrede `raw_text` ikke længere er et sammenhængende udsnit af renditionen. En
projektion, der OGSÅ fjerner de 100 `NOISE_RE`-matchende linjer, giver
**591/591 fund** — hypotesen er bekræftet, ikke kun sandsynliggjort.

Linjeafstand fra forudgående `### PAGE n ###`-markør for de 100
`NOISE_RE`-match (aggregat-histogram, ingen linjer citeret):

| Afstand fra sidemarkør | Antal |
|---|---|
| 1 | 87 |
| 9, 11, 13, 15, 23, 25, 34, 46, 56, 57, 59 (hver) | 1 |
| 21 | 2 |

87/100 ligger på afstand 1 — dvs. umiddelbart efter et sideskift, som er den
eneste position et fast sidehoved/-fod kan optræde på. De resterende 13/100
ligger spredt (afstand 9-59), hvilket **ikke** er foreneligt med et fast
sidehoved — et sidehoved gentager sig på samme relative position hver side.
Den brede regex `von\s+R\s*E.*` matcher enhver linje der begynder "von Re…",
uanset om den er en sidehoved-frase eller starten af en prosasætning (fx en
biografilinje der begynder "von Reventlow, f. …"). De 13 spredte match kan
derfor være ægte narrativ-indhold, ikke støj — dette er **ikke afklaret** her
(kræver kildelæsning, som ligger uden for denne opgaves aggregat-mandat) og
skal undersøges før nogen rettelse af `NOISE_RE`/`extract_text.sh` besluttes.
Hvis nogen af de 13 er indhold, er det ikke kun et fase-A-ankerproblem, men et
potentielt datatab i den eksisterende `narrative.tekst` for source 1.

De 68 nøgler (`record_key`), for reproduktion:
I-9, I-11, I-17, I-18, I-32, I-33, I-44, I-89, II-17, II-25, II-35, III-3,
III-7, III-10, III-37, III-61, III-64, III-73, III-81, III-89, III-91, III-99,
III-129, IV-2, IV-4, IV-11, IV-13, IV-17, IV-19, IV-25, IV-32, IV-36, IV-45,
IV-51, IV-84, IV-86, V-1, V-3, V-7, V-17, V-20, V-41, V-42, V-43, V-47, V-54,
V-58, V-62, V-69, V-75, V-89, V-94, V-101, V-108, V-111, V-123, V-129, V-135,
V-141, V-144, V-149, V-158, V-160, V-163, V-173, V-178, V-181, V-195

## Måling 9 — rendition-SHA og regenerering

| Måling | Værdi |
|---|---|
| Matchet PDF | `Dansk Adels Aarbog - Reventlow - Særudgave.pdf` |
| PDF-SHA-256 | `3beadfc15e3fa1a4090589af56cd4e95599a9231e8f979dfb60c4e27bbd8252a` (matcher pilotmanifest) |
| Pilot `raw.txt` SHA-256 | `2dd5cf8408943ccc50ac4d89dcbd08ac3b49a90fdabd1ddcbd7b22d218026563` |
| Regenereret `raw.txt` SHA-256 | `2dd5cf8408943ccc50ac4d89dcbd08ac3b49a90fdabd1ddcbd7b22d218026563` |
| Manifest `raw_text_sha256` | `2dd5cf8408943ccc50ac4d89dcbd08ac3b49a90fdabd1ddcbd7b22d218026563` |
| Alle tre SHA'er identiske | **ja** |
| `pdftotext -v` | 26.07.0 (poppler, Homebrew) |
| Sideinterval brugt (`### PAGE n ###`) | 93–247 |
| Linjeafvigelse (før/efter) | ikke relevant — SHA er byte-lig, ingen diff nødvendig |
| Regenererede poster (`posts.regenerated.json` via `segment.py`) | 591 |
| `lokal_id`-mængde identisk med pilotens `posts.json` | **ja** (591/591, 0 kun-i-den-ene) |
| `raw_text` SHA-256 pr. `lokal_id` identiske | **ja** (0 afvigende af 591 fælles) |

Rendition-regenereringen er fuldt deterministisk og byte-identisk med pilotens
artefakter — ingen pdftotext-versionsdrift.

**Proveniens-bemærkning:** `raw.regenerated.txt` og `posts.regenerated.json` er
genbrugt fra en tidligere agents kørsel i `work/task31-.../` (tomt
`extract.stderr`, tidsstempel forud for denne session) — de er **ikke**
gen-kørt i denne session. SHA-identiteten på tværs af tre uafhængige kilder
(pilot, den genbrugte regenerering, manifestet) er stærk evidens, men
regenereringen er ikke reproduceret to gange inden for denne opgave.

## Måling 10 — levende/staged/privat blandt de 591

| Status | Antal |
|---|---|
| `levende` | 47 |
| `staged` | 0 |
| `privat` | 0 |

47/591 (7,9 %) er levende og skal have `draft`-disposition i 149b.

## Måling 11 — dækning af renditionen

Beregnet på den normaliserede projektion (samme som måling 8), da rå `raw.txt`
ikke er den relevante nævner (se måling 8's resultat).

| Måling | Værdi |
|---|---|
| Projektionens længde (tegn, uden sidemarkører) | 452.479 |
| Tegn dækket af de 591 posters spænd (sekventiel, ikke-overlappende søgning) | 286.446 |
| Dækningsandel | **63,3 %** |
| Poster uden match (indgår ikke i dækning) | 68 (samme sæt som måling 8) |

Dækningstallet er en nedre grænse: de 68 uden match bidrager 0 dækkede tegn,
og resten af projektionen er strukturelle blokke (grenoverskrifter,
slægtled-overskrifter, ægteskabs-indledninger) som fase A bevidst ikke skriver
records for (spec §2, §4).

**Genberegnet mod den støj-strippede projektion** (samme projektion som
bekræftede måling 8's rodårsag, §"Konsekvens" nedenfor) — dette er den nævner
fase A faktisk ville ankre imod, hvis §4's `NOISE_RE`-problem løses ved at
flytte filtreringen ind i renditionslaget:

| Måling | Værdi |
|---|---|
| Projektionens længde (støj-strippet) | 449.384 |
| Tegn dækket af de 591 posters spænd | 432.025 |
| Dækningsandel | **96,1 %** |

De resterende ~3,9 % er fortsat strukturelle blokke uden for §4's scope.

## Konsekvens for spec §3/§4 og for 149b §5

**Stopkriterier fra spec §1 punkt 5 og §4, vurderet enkeltvis:**

| Kriterium | Status | Note |
|---|---|---|
| PDF-match (SHA mod pilotmanifest) | **Opfyldt** | Entydigt match, én kandidat |
| Rå-tekst-SHA (rendition mod pilotmanifest) | **Opfyldt** | Byte-lig, 3/3 SHA'er identiske |
| Paritet 591 (segmentering) | **Opfyldt** | 591/591, `lokal_id`- og `raw_text`-SHA identiske med pilot |
| Nøglemængde identisk (`record_key` ↔ `lokal_id`) | **Opfyldt** | 591/591 fælles, 0 afvigende, injektiv begge veje |
| Eksakt delstreng i renditionen (§4, "ingen fuzzy-match") | **IKKE opfyldt for 68/591 (11,5 %)** | Se måling 8 |

**Det sidste punkt er blokerende for spec §4 som skrevet.** §4 kræver at hver
posts `raw_text` findes som eksakt delstreng i renditionen, ellers "fejler
byggeren for posten, og fasen stopper (ingen fuzzy-match)". Med den nuværende
`segment.py`-pipeline (uændret siden pilotens `posts.json`) vil en bygger, der
implementerer §4 bogstaveligt, stoppe på **68 poster** — rodårsagen er
**bekræftet empirisk** (ikke kun sandsynliggjort): `_segment_2018_20`'s
`NOISE_RE`-filtrering fjerner linjer *midt i* en igangværende post uden at
afbryde den, hvilket bryder kontiguitet; en projektion der også fjerner de 100
`NOISE_RE`-linjer giver 591/591 fund. Hvorvidt disse 100 linjer alle er
harmløs sidehoved/-fod-støj er **ikke** afklaret — 87/100 sidder på den eneste
position et fast sidehoved kan sidde (linje 1 efter et sideskift), men 13/100
sidder spredt og kan være ægte prosa, se afklaringspunktet ovenfor. Tre veje
frem, ingen valgt her (læse-kun opgave):

1. **Ret `segment.py`/`extract_text.sh`** til at bevare kontiguitet — men kun
   for den delmængde af de 100 linjer der faktisk er sidehoved/-fod (skal
   afklares først; at fjerne alle 100 uden afklaring risikerer at
   institutionalisere et eksisterende indholdstab i stedet for at rette det).
2. **Byg ankeret på et ikke-sammenhængende spænd** (flere `char_from`/`char_to`-par
   pr. post) — udvider §4's datamodel for `source_record_occurrence`, ikke
   trivielt inden for "generel mekanik, ingen nye tabeller" (adgangskrav §1.3).
3. **Aflever fase A med 523/591 ankre og en dokumenteret parkering** af de 68,
   under §1 punkt 5's krav om "accepterede ankre (591)" — kræver
   projektejer-beslutning, jf. spec §10 (ændringsmyndighed).

**Konsekvens for 149b:** 149b's identitets- og tekstlighedsregler (§5 punkt
1-2) afhænger af måling 4 (0 brud) og måling 7 (587/591 byte-lige efter norm,
4 med differens >200 tegn, alle med samme fortegn — se måling 7), begge
overvejende sunde. Men 149b's narrativ-binding forudsætter en *færdig* fase
A-forekomst pr. post (§5 er eksplicit bygget ovenpå §4's ankre) — de 68 uden
gyldigt anker kan ikke få `bound_published`/`bound_draft` før §4-spørgsmålet er
afklaret, og vil alene af den grund ende i 149b's `unresolved_text`-boks.

68/591 = **11,5 %, hvilket overskrider** 149b §5 punkt 4's
10 %-`unresolved_*`-stopgrænse, hvis alle 68 tælles som `unresolved_text` uden
yderligere handling. Dette er ikke en 149b-måling i sig selv (149b er ikke
kørt), men en tidlig advarsel: uden en rettelse af §4-problemet (vej 1 eller 3
ovenfor) vil 149b sandsynligvis ramme sin egen stopgrænse ved første forsøg.

De 2 poster med narrativ-tekstforskel >200 tegn der **ikke** overlapper med de
68 (IV-94, I-133 — se måling 7) er en uafhængig `unresolved_text`-kandidatgruppe
for 149b, adskilt fra `NOISE_RE`-problemet.

## Artefakter

- `work/task31-2018-20-fase-a-inventering/inventory.py` — målescript (aggregat-only), dækker målinger 1-11 samt diagnostiske 8b/11b
- `work/task31-2018-20-fase-a-inventering/measurements.json`, `run.stdout` — alle målinger inkl. 8b/11b som struktureret JSON
- `work/task31-2018-20-fase-a-inventering/raw.regenerated.txt`, `posts.regenerated.json` — genbrugt regenereret rendition/segmentering (fra tidligere agent, se måling 9's proveniens-bemærkning)
- `work/task31-2018-20-fase-a-inventering/pg_restore.log` — restore-log (3 ignorerede vault-fejl)
- Database: `daa149_inventory_20260903` på `127.0.0.1:55441` (ikke droppet, jf. opgavebeskrivelsen)
