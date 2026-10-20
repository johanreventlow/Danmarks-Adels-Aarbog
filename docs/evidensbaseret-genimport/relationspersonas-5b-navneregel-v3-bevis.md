# Trin 5b del 2b-ii, runde 2: navneregel v3 over de 12 `U`-ægteskaber og P-linjen — færdigbevis i restore (2018-20)

**Grundlag:**
- Spec: `docs/superpowers/specs/2026-10-17-trin5b-2b-ii-nye-personer-og-disposition-design.md` §17 (godkendt 2026-10-18).
- Plan: `docs/superpowers/plans/2026-10-18-trin5b-2b-ii-runde2-navneregel-v3.md` (Task 1-6).
- Kørsel: 2026-10-19/20 på grenen `docs/151-5b-navneregel-v3`, i en kopi af 2b-ii's bevisbase. Aldrig i prod.

Rapporten indeholder kun tal, hashes og basenavne. Den indeholder ingen navne, ingen kildetekst, ingen postnøgler og ingen persona-, person- eller aktør-id'er.

## Kort svar

**Navneregel v3 løser rundens hovedfund.** Titler inde i adelsnavne stopper ikke længere navnet. Af de 12 ægteskaber, der stod `U` i 2b-ii, foreslog reglen `S` for 9. Projektejeren bekræftede alle 9 på arket uden en eneste navnerettelse.

| Område | Resultat |
| --- | --- |
| Bindinger | **9** nye (232 → 241). Ingen genbindinger. En genkørsel giver 0. |
| Klausuler | **9** skiftede til `fortolkning_foreslaaet`. En genkørsel giver 0. |
| Kanoniske tabeller | Uændrede (alle aggregat-hashes er ens). |
| 2a's tupel-digest | Uændret. |
| Universet | Lukket (272). |
| Offentlig læsning | **241** synlige kilderækker (+9), **238** familier (+9). |
| Nye personer | **0**. Se nedenfor. |

**§17.1's mål »den første nye person på bogens data« er ikke nået.** Projektejeren læste P-linjen (2b-i's `new_person_needed`, år 1314) og fandt, at selve fortolkningen er forkert:
- hovedpersonen er kun nævnt som vidne;
- kvinden var gift med en anden mand.

Linjen blev besvaret `U`. Derfor havde `relation_person_create` 0 elementer. Oprettelsen af en ny afdød ægtefælle er stadig **kun bevist på opdigtede personer i CI**, og den skal bevises på rigtige data før en prod-overførsel af 2b-ii.

## Grundlag

| | |
| --- | --- |
| Commit | `de024e5` (grenen `docs/151-5b-navneregel-v3`, ikke pushet). SQL-laget er uændret siden `cc4e5f3`. |
| Fil-hashes (SHA-256) | `schema.sql` `23719f14…f004`, `db-migrations.sql` `bf638f95…3410`, `db-rls.sql` `f20f3b27…fe60`, `db-verify.sql` `adf00a1e…4774` |
| Arbejdsbase | `daa5b_navnv3_bevis_20261019200958` er en kopi af `daa5b_2b_ii_bevis_20261017132417`. Originalen er uændret og bevares. Kopien er løftet med `db-migrations.sql` og `db-rls.sql`, og `db-verify.sql` er grøn med den nye v3-blok. system_identifier er `7657242220770903427`. **Kopien bevares.** |
| Kilde | 1 (DAA 2018-20), kontrakt 2 |
| Scripts | Ligger i `~/.private/5b-navneregel-v3/` (0700, ikke i repo): `hashes.sql` `f05df86c…`, `univers.sql` `e7037ee0…`, `decide.sql` `05d0ac45…`, `bind-preview.sql` `7a60b94e…`, `bind.sql` `a581be75…`, `read.sql` `c2658ed6…`, `relation_persona_apply.sql` `83106173…` og `relation_batch_apply.sql` `3dc6f0a8…` (alle som i 2b-ii). Nye i denne runde: `disp-input.sql` `6d693308…` og `neg.sh` `2ede919b…`. |

**Før-målingen gav 2b-ii's sluttal:**
- Bindinger: 232.
- Antal `person/family/family_member/fact/assertion/citation/conclusion`: 1811/682/2258/7197/9306/8579/9217.
- Universet: 272, heraf 12 uden ægtefælle-persona.
- 2a's tupel-digest: `89bde760…5923`.
- Læsningen: 229 familier og 232 synlige kilderækker (225 offentlige, 7 ikke-offentlige).

## Tørkørsel (Task 2)

**De 12 rækker:** navneregel v3 gav `S` 9, `I` 1 og `U` 2:
- `I`: klausulen slutter, før navnet står.
- `U`: én række mangler en hovedperson, og én citerer to klausuler.

**P-rækken** blev målt i SQL:
- 1 element, identitetsversion 1, ét årstal (1314);
- navnet har 3 ord, intet titelord og 1 partikel;
- fortolkningens status er `proposed`, og rækken er ikke i stikprøven.

Ingen afvigelse fra spec'ens forventning.

## Arket (spec §17.6)

| | |
| --- | --- |
| Rækkefil | `rows.json` SHA-256 `d6263513…f2c7`: 12 `M`-rækker og 1 `P`-række, grænseår 1906 |
| Regelens forslag | `S` 9, `D` 0, `N` 0, `I` 1, `U` 2; P: `D` 1 |
| Ark | 13 linjer. Godkendt SHA-256 `fb53ab46…f4dc` (bygget fil `d55faf16…`). 0 `navn:`-rettelser. |
| Udfald | `S` 9, `U` 3; P: `U` |
| Manifest og identitet | `sql` gav `SQL_OK manifest=9 identitet=9`. Persona-manifestet har hash `6c16e103…`, identitetsscriptet `b0e5b0b5…`, og scriptet har ingen P-linje. |

**Projektejerens ændringer i forhold til regelen:**
- **`I` → `U`:** klausulen er afskåret før navnet (klausulopdelingen, trin 4).
- **P `D` → `U`:** fortolkningen »ægteskab« er forkert, se »Kort svar«.

**Skævt nummer ved `S`:** 2 linjer. I begge siger bogen »Gift 1°«, mens systemets ægteskabsnummer er 2. Partneren er rigtig og bekræftet; årsagen er beskrevet i fund 1.

## Anvendelse (spec §17.6, §6)

| | |
| --- | --- |
| Persona-batch | `relation_persona` 9 elementer (profil v3, arkets hash i hver kvittering). `manifest_sha256` `ce3b4c66…`, derived `{parties 18, mentions 9, spouse_personas 9, year_interpretations 0}`, receipts `81228cd7…`. |
| Identitetsscript | 9 × `same` med `human_sheet`-kontekst. Alle 9 identiteter bærer samme `sheet_sha256` som persona-kvitteringerne (9 = 9). |
| P-identiteten | Uændret: version 1, `unresolved`. |
| `relation_person_create` | `relation_person_create_input(1)` gav 0 elementer, så batchen er ikke kørt. |

## Efterkørsel (spec §7)

| | |
| --- | --- |
| Afgørelse | `decide.sql`: preview 9 (heraf 2 ordinal-afvigelser), afgjort 9, klassifikationer 11 → 13 |
| Bind-preview | 9 egnede, 0 genbindinger. Preview `98ae75e4…`, manifest-digest `259f04f1…`. |
| Binding | 9 bindinger. Et identisk genkald gav samme batch og 0 nye rækker. Efter-digesten er lig manifest-digesten. |
| Genkørsel | `decide.sql`: preview 0, afgjort 0. Bind-preview: 241 `RELATION_PROMOTION_ALREADY_APPLIED` og 0 egnede (en tom liste afvises som `RELATION_PROMOTION_ITEMS_INVALID`). |
| Ordinal-klassifikationer i alt | `ordinal_afvigelse` 7, `ordinal_beholdt` 3 |

## Disposition (spec §8)

| | |
| --- | --- |
| Input | `red_relation_disposition_input(1)`: 9 elementer, manifestfil `26bc7f6a…` |
| Batch | `relation_disposition` 9. `manifest_sha256` `6a6ba99b…`, receipts `f3e6e209…`, derived `{dispositions 9}`. |
| Skiftede | 9 klausuler gik fra `afventer_identitet` til `fortolkning_foreslaaet` |
| Venter stadig | 259 klausuler står i `afventer_identitet` (268 før) |
| Genkørsel | Input gav 0 elementer |

## Kontrolmålinger (spec §17.8)

| | Før | Efter |
| --- | --- | --- |
| Kanoniske aggregat-hashes (`person`, `family`, `family_member`, `fact`, `assertion`, `citation`, `conclusion`, `family_member` uden ordinal, v2-læsningen) | | **ens** (diff tom) |
| Antal `person/family/family_member/fact/assertion/citation/conclusion` | 1811/682/2258/7197/9306/8579/9217 | uændret |
| 2a's tupel-digest | `89bde760…5923` | `89bde760…5923` |
| Univers | 272 | 272. Bundet 241, uden ægtefælle-persona 3, de øvrige spande uændrede. |
| Læsning: familier | 229 | 238 |
| Læsning: synlige kilderækker (offentlige / ikke-offentlige) | 232 (225 / 7) | 241 (234 / 7) |

Kontrollerne af den nye person i §17.8 er ikke relevante, fordi der ikke blev oprettet nogen person. Kontrollerne omfatter `staged`, `levende=false`, titelfrit visningsnavn, kæden fra faktum til konklusion, familie og kvitteringer.

## Negativtests (spec §17.8), hver i sin kopi

| | Udfald | Skrivninger |
| --- | --- | --- |
| **A** Identitetsscriptet køres igen efter den første anvendelse. | `EVIDENCE_IDENTITY_VERSION_CONFLICT` | Personas/identitetshændelser 832/840 både før og efter genkørslen (823/831 før den første anvendelse) |
| **C** En `U`-linje hæves i hånden til `S` uden regelbekræftelse og får en frisk hash. | `SHEET_TOKEN_NOT_ALLOWED` (rc 1) | 0 filer skrevet |

Planen ville også køre P-linjens `red_afgoer_source_persona` alene i A. Da P blev besvaret `U`, har identitetsscriptet ingen P-linje. P-identiteten står derfor uændret på version 1, og der findes ingen forældet version at afvise. P-låsen er bevist i CI's e2e-test (`test-relation-marriage-sheet-v3.sh`, separat kald med `EVIDENCE_IDENTITY_VERSION_CONFLICT`).

Kopierne er omdøbt til `slet_1020__navnv3_bevis_20261019200958_neg{A,C}` (2 × 83 MB; manifest `~/.private/5b-navneregel-v3/karantaene-1020.txt`). De slettes kun efter et nyt ja.

## Fund

1. **Ægteskabsnummeret bliver forkert, når påstandens tekst rækker ud over klausulen.**
   - **Mekanisme:** `private.relation_marriage_ordinals` nummererer en posts ægteskaber efter, hvor påstandens rå tekst står i posten. Står den rå tekst ikke ordret i klausulen, bliver positionen NULL. NULL sorteres sidst, så »Gift 1°« kan blive nr. 2. Årsagen er klausulopdelingen: tekstens begyndelse står i klausulen, men resten gør ikke.
   - **Omfang i kilden:** 248 ægteskabspåstande. 6 har NULL-position, og 4 af dem ligger i poster med flere ægteskaber. Bogens »N°« står i 40 påstande og afviger fra systemets nummer i 4. De 4 ligger i 2 poster: de 2 skæve `S`-linjer i denne runde og deres to »søstre«.
   - **Hvad det har givet:** Søstrene blev bundet allerede i 2a/2b-i med det omvendte fejlnummer. De står derfor i forvejen som falske `ordinal_afvigelse`.
   - **Projektejerens valg (2026-10-20):** bind alle 9 og notér fejlen. Familiernes numre i databasen er rigtige og røres ikke. De 4 falske afvigelser (2 nye og 2 gamle) skal besvares »behold familiens nummer« (`ordinal_beholdt`), når de kommer på et undtagelsesark.
   - **Opfølgning:** Rodfejlen rettes i en separat runde, der også genafgør søstrene. Den bruges 5 steder og har eksisteret siden 2a.
2. **P-fortolkningen skal afvises særskilt.** Arkets `U` opretter blot ingen person. Det afviser ikke fortolkningen »de to var gift«, som står som `proposed` (version 1, ikke bundet). Den skal afvises med `red_decide_interpretation`, så den ikke senere tages for gyldig. **Udestår.**
3. **Slutreviewets rettelser af navneregel v3** (commit `de024e5`):
   - **Afkortning:** Et småord med bindestreg eller punktum foran et versalord (»rigs-grevinde«, »f.«) tæller nu som afkortning (`U navn_afkortet`). Før ville navnet være blevet `D` afkortet til fornavnet.
   - **Partnertræf ved `S`:** kræver nu efternavnet plus mindst ét fælles kerneord mere.
   - **Løst dubletværn før `D`/`N` og på P-linjen:** kræver 0 træf, hvor v2's halvdelsregel eller blot ét fælles kerneord tæller som træf (grunden hedder `partner_ligner`).

   Ingen af de 12 rækker blev ændret af rettelserne: arkets, manifestets og identitetsscriptets hashes er byte-identiske med de godkendte.
4. **Fem mindre fund er udskudt** (ledger):
   - partnerens nummer i inputtet bør komme fra ægteskabets egen række;
   - P-forespørgslen kan give dubletrækker (fejler lukket);
   - fortolkningstjekket i `write_relation_person_create` er ikke bundet til nummerrækken;
   - et partnernavn med bogstaver i parentes giver `U`;
   - `sheet_line` (nummer blandt `M`/`P`-linjer) bør dokumenteres.

## Hvad der stadig mangler bevis

- **`relation_person_create` på bogens data.** Ingen af rundens linjer var en ægte ny, afdød ægtefælle. Beviset kræver en anden kandidat, tidligst blandt børnene i 2b-iii eller i en senere kilde. Det skal foreligge før en prod-overførsel af 2b-ii.
- **`existing`-placering** (errata §16.1): stadig 0 forekomster.
- **De tre `U`:**
  - én klausul er afskåret (trin 4-segmenteringen);
  - én mangler en hovedperson;
  - én citerer to klausuler.

## Afvigelser fra planen

- **Ingen ny person (P = `U`):** Step 3's `relation_person_create`-batch og Step 6's kontrol af den nye person er ikke kørt.
- **Negativtest A** er kørt uden P-delen (se ovenfor).
- **Bindingen** blev sat på pause efter preview, så slutreviewet kunne komme først (projektejerens ønske). Rettelserne af F1/F2 blev lagt ind, inden bindingen blev genoptaget, og invarianskontrollen viste, at det godkendte ark stadig gjaldt.
