# Trin 5b del 2b-ii — nye personer, de 14 ægteskaber og dispositionen: færdigbevis i restore (2018-20)

Beslutning: `docs/decisions.md` 2026-10-17 (med tillæg om aldersreglen ≤ 1906). Spec:
`docs/superpowers/specs/2026-10-17-trin5b-2b-ii-nye-personer-og-disposition-design.md` (errata §15.1-15.5).
Plan: `docs/superpowers/plans/2026-10-17-trin5b-2b-ii.md` (Task 0-8). Kørt 2026-10-17/18 på grenen
`docs/151-5b-2b-ii` i en kopi af 2b-i's bevisbase, aldrig i prod. Rapporten indeholder tal, hashes og
basenavne — ingen navne, ingen kildetekst, ingen postnøgler og ingen persona-, person- eller aktør-id'er.

## Kort svar

Kæden virker ende til ende: andet gennemløb (profil v2) → ark → personas → identitet → efterkørsel →
disposition. Men af de 14 ægteskaber uden ægtefælle-persona blev kun **2** bundet. Projektejeren
gennemgik arket og ændrede 8 af regelens 10 `S`-forslag og regelens ene `N` og ene `I` til `U`. Grunden
er tre regelfejl og fejl i klausulopdelingen, ikke usikre personer (se »Fund«).

- **0** nye personer: ingen linje blev `D`, så `relation_person_create` havde 0 elementer. **Oprettelsen af
  en ny afdød ægtefælle er derfor ikke kørt på bogens data.** Den positive vej er kun bevist på opdigtede
  personer i CI (`test-relation-person-create.sql`, e2e). Negativtest C og F her viser kun, at writeren
  afviser på rigtige data. Beviset på rigtige data kommer tidligst i næste runde, når navnereglen giver
  `D`-linjer, og det skal foreligge før en prod-overførsel af 2b-ii.
- Efterkørslen bandt **2** ægteskaber (230 → 232) uden genbindinger. 2a's tupel-digest er uændret, og en
  genkørsel giver 0.
- Dispositionen skiftede **122** klausuler (121 + 1 frigjort) til `fortolkning_foreslaaet`. En genkørsel
  giver 0.
- Det kanoniske lag er uændret (alle aggregat-hashes ens). Universet er lukket (272).
- Den offentlige læsning har **232** kilderækker (+2).
- Negativtest A-F afviser alle, med 0 skrivninger.

## Grundlag

| | |
| --- | --- |
| Commit | `4443363` (grenen `docs/151-5b-2b-ii`, ikke pushet); SQL-laget er uændret siden `1fde086` |
| Fil-hashes (SHA-256) | `schema.sql` `cc122a00…c928`, `db-migrations.sql` `db32c5de…912b`, `db-rls.sql` `f5d73ad0…bc53`, `db-verify.sql` `00488392…a5a6` |
| Arbejdsbase | `daa5b_2b_ii_bevis_20261017132417` = kopi af `daa5b_2b_i_bevis_20261012093656` (uændret, bevares), løftet med `db-migrations.sql` + `db-rls.sql` til HEAD efter 1906-rettelsen (begge writere bærer `>1906`, ingen `1921`); `db-verify.sql` grøn. system_identifier `7657242220770903427`. **Bevares.** |
| Kilde | 1 (DAA 2018-20), kontrakt 2 |
| Scripts | `~/.private/5b-2b-ii/` (0700, ikke i repo): `hashes.sql` `f05df86c…`, `univers.sql` `e7037ee0…`, `decide.sql` `05d0ac45…`, `bind-preview.sql` `7a60b94e…`, `bind.sql` `a581be75…`, `read.sql` `c2658ed6…` (samme som 2b-i), `relation_persona_apply.sql` `83106173…`, `relation_batch_apply.sql` `3dc6f0a8…`, `neg.sh` `08653b5e…`, `negC.sh` `9c9190ed…` |

Før-målingen gav 2b-i's sluttal: universet 272 (bundet 230, uden ægtefælle-persona 14, ægtefælle
`unresolved` 3, `new_person_needed` 1, struktur uentydig 7, barn 14, forælder `proposed` 2, forælder
`rejected` 1). Desuden 2a's tupel-digest `89bde760…5923` og læsningen 227 familier / 230 synlige (223
offentlige, 7 ikke-offentlige).

## Arket (spec §5, errata §15.1/15.2/15.5)

| | |
| --- | --- |
| Rækkefil | `rows.json` SHA-256 `7065dd4e…d6cb`, 14 rækker, grænseår 1906 |
| Regelens forslag | navneregel v2: `S` 10, `D` 0, `N` 1, `I` 1, `U` 2 (ingen hovedperson 1, to klausuler 1) |
| Ark | 14 linjer; godkendt SHA-256 `bb313586…7ff6` (bygget fil `14dbf6eb…257d`; 10 linjer rettet af projektejeren) |
| Udfald | `S` 2, `D` 0, `N` 0, `I` 0, `U` 12 |
| Manifest + identitet | `sql` → `SQL_OK manifest=2 identitet=2`; manifestfil `8b12793a…`, identitetsscript `d9713dcf…` |

Projektejerens rettelser fordelt på årsag (linjenumre på arket):

| Årsag | Linjer | Forslag → svar |
| --- | --- | --- |
| Titel **inde i** navnet (»rigsfriherre«, »friherreinde«, »komtesse«, »greve«): navnet stoppede ved titlen, så spændet var kun fornavnene | 4, 6, 7, 9, 10, 12, 13, 14 | `S` → `U` |
| Partnersammenligningen: fælles fornavn + »von« ramte begge partnere, så intet `S`; ægtefællen findes allerede (partner nr. 2) | 5 | `N` → `U` |
| Klausulen slutter ved linjeskiftet før »med …«: navnet står i bogen, men uden for klausulen | 1 | `I` → `U` |

De to `U`-forslag (ingen hovedperson; ægteskabet citerer to klausuler) blev stående. De to `S`, der holdt
(linje 3 og 8), har titlerne **før** navnet. Begge består navnetjekket (rent navn), partnertjekket
(identisk med partneren, ægteskabsnummeret passer) og datotjekket (fødsel og død ens i bog og database).

## Anvendelse (spec §5.4, §6)

| | |
| --- | --- |
| Persona-batch | `relation_persona` 2 elementer, `manifest_sha256` `457ed94b…`, derived `{parties 4, mentions 2, spouse_personas 2, year_interpretations 0}`, receipts `12277239…` |
| Identitetsscript | 2 × `same` gennem `red_afgoer_source_persona` med `human_sheet`-kontekst (arkets hash, rækkefilens hash, linje); begge `accepted` med kanonisk person |
| `relation_person_create` | `relation_person_create_input(1)` = 0 elementer (`expected_counts` 0); batchen er ikke kørt (en tom batch beviser intet). Kanonisk delta = 0 = summen af spec §6 pkt. 5 over 0 sager |

## Efterkørsel (spec §7)

| | |
| --- | --- |
| Afgørelse | `decide.sql`: preview 2 (1 ordinal-afvigelse, klassificeret efter 2a's regel), afgjort 2; accepterede `family-structure-v1` 225; klassifikationer 10 → 11 |
| Bind-preview | egnede 2, genbindinger 0, preview `1d0db7c5…`, manifest-digest `67438494…` |
| Binding | 2 bindinger; identisk genkald = samme batch, 0 nye rækker; efter-digest = manifest-digest |
| Genkørsel | preview: 232 `RELATION_PROMOTION_ALREADY_APPLIED`, 0 egnede; `decide.sql`: preview 0, afgjort 0 |

## Disposition (spec §8)

| | |
| --- | --- |
| Input | `relation_disposition_input(1)`: 122 elementer, manifestfil `2b9eaaba…` |
| Batch | `relation_disposition` 122, `manifest_sha256` `74565bff…`, receipts `ca113e56…`, derived `{dispositions 122}` |
| Forventet | ca. 121 + det, §5-§7 frigør. Frigjort: 1. Den ene `S`-klausul skiftede. Den anden rummer også ægteskabet fra linje 4 (`U`), hvis ægtefælle stadig mangler en persona, så den står fortsat som `afventer_identitet` (regel identitet pr. aktør, §8.2) |
| Genkørsel | input = 0 elementer |

## Kontrolmålinger (spec §10 pkt. 3-6)

| | Før | Efter |
| --- | --- | --- |
| Kanoniske aggregat-hashes (`person`, `family`, `family_member`, `fact`, `assertion`, `citation`, `conclusion`, `family_member` uden ordinal, v2-læsningen) | | **ens** (diff tom) |
| 2a's tupel-digest | `89bde760…5923` | `89bde760…5923` |
| Univers | 272 | 272 (bundet 232, uden ægtefælle-persona 12, øvrige spande uændrede) |
| Læsning: familier | 227 | 229 |
| Læsning: synlige kilderækker (offentlige / ikke-offentlige) | 230 (223 / 7) | 232 (225 / 7) |

Synlighed (spec §10 pkt. 3): ægteskaber, der kan blive synlige ved aktiveringen, er D 0 + S 2. De 2 er
allerede synlige, fordi de binder til eksisterende, aktive personer. Ventende: N 0, I 0, U 12, alle i spanden
»uden ægtefælle-persona«.

## Negativtests (spec §10 pkt. 7), hver i sin kopi

| | Udfald | Skrivninger |
| --- | --- | --- |
| **A** forældet tilstand: persona-batch og identitetsscript genkørt, efter at tilstanden har flyttet sig | `REIMPORT_WRITER_BATCH_INVALID` / `EVIDENCE_IDENTITY_VERSION_CONFLICT` | personas/identitetshændelser 823/831 før og efter genkørslerne |
| **B** ark-hash passer ikke; rækkefil-hash passer ikke | `SHEET_HASH_MISMATCH` / `ROWS_HASH_MISMATCH` (rc 1) | 0 filer skrevet |
| **C** `relation_person_create` med forældet identitetsversion (2b-i-sagen gjort afdød, manifest bygget ved version 2, identiteten derefter flyttet til version 3) | `RELATION_PERSON_CREATE_DRIFT` | personer 1811/1811 |
| **D** disposition oven på en menneskelig disposition (121-elementers manifest, én klausul fik `kraever_menneske` efter manifestet) | `RELATION_DISPOSITION_NOT_ELIGIBLE` | dispositioner 1748/1748 |
| **E** aktørforslag uden persona kom til efter manifestet | `RELATION_DISPOSITION_NOT_ELIGIBLE` | dispositioner 1747/1747 |
| **F** `relation_person_create` for 2b-i's `new_person_needed` uden `deceased` (håndbygget element) | `RELATION_PERSON_CREATE_NOT_DECEASED` | personer 1811/1811 |

A afviger fra spec'ens ordlyd: `ROWS_STALE` er 2b-i-arkets kode. 2b-ii's ark bindes med hash (B), og
forældet tilstand fanges af writerens batch-/versionskontrol. A beviser netop dette. C's første kørsel
fejlede i min testopsætning (persona-opslag mod `private` som `authenticated`), før noget blev skrevet. Den
blev gentaget med opslaget foretaget først. Kopierne er omdøbt til `slet_1018__2b_ii_bevis_20261017132417_neg{A..F}`
(6 × 82 MB; manifest `~/.private/5b-2b-ii/karantaene-1018.txt`). De slettes kun efter et nyt ja.

## Fund

1. **Navnereglen kan ikke springe titler inde i et navn over.** Den fejlede i 8 af 10 `S`-forslag. Næste
   version skal behandle titelord (»rigs-«, »-friherre«, »-inde«, »komtesse«, »greve«, »baron« …) og
   partiklerne »und«, »zu«, »dem«, »genannt« som en del af navneløbet. De 8 linjer er testtilfældene.
2. **Partnersammenligningen tæller partikler og fornavne med**, så to partnere kan ramme på én gang.
   Partikler (»von«, »af«, »de«, »der« …) skal ikke tælle, og ægteskabsnummeret skal afgøre uafgjorte
   tilfælde. Samme fejl kan give et forkert `S` hos en hovedperson med én partner. Menneskets navnetjek er
   værnet indtil da.
3. **Aldersreglen tæller henvisningsår med** (»(DAA 1937, …)«). Den fejler lukket til N, så fejlen koster
   kun dækning. Årstal inde i en DAA-henvisning bør udelades.
4. **Klausulopdelingen har tre fejltyper**, set i 5 af 14 rækker:
   - slutter for tidligt ved et linjeskift før »med …« (1);
   - starter midt i en sætning (3);
   - løber ind i næste afsnits overskrift (1).
   Desuden er der ét ægteskab, der citerer to klausuler, fordi der er delt ved punktummet i »Næstfmd.«.
   Hypotese, ikke bevist: starterne midt i sætningen er den anden halvdel af samme forkortelsesdeling. Det
   hører til segmenteringen (trin 4-kæden), ikke til 2b-ii.
5. **Arkets etiket `Navn:`** blev læst som hovedpersonens navn. Den skal hedde »Ægtefællens navn:«.
6. **Aktivering (errata §15.4):** den eksisterende cutover aktiverer kun `person_create`-personer. Når en
   `D`-linje en dag giver en ny person, skal overførselsspec'en aktivere `relation_person_create`-personer.
   I denne kørsel var der ingen. Slutreviewet viste desuden, at en ny person i hovedpersonens **eksisterende**
   familie skjuler hele familien for læseren, indtil personen aktiveres. Overførslen skal derfor aktivere i
   samme transaktion (errata §16.1, godkendt 2026-10-18). `existing`-placeringer i denne kørsel: 0.

Konsekvens for roadmappet: 2b-ii's mekanik er bevist, men dækningen er lav (2 af 14). Næste runde over de 12
`U` kræver fund 1-3 (deterministisk, ingen model) og eventuelt fund 4. Der går ikke noget tabt i ventetiden:
11 af de 12 står allerede i det kanoniske træ med den rigtige partner; den 12. venter på hovedpersonens
binding.

## Afvigelser fra planen

- `relation_person_create`-batchen er ikke kørt (0 elementer). Den positive oprettelsesvej er dermed ubevist på
  rigtige data (se opsummeringen).
- Negativtest A er omdefineret (se ovenfor).
- Bind-preview skrev første gang sit manifest til en løs fil i arbejdsmappen, fordi variablen `manifest`
  ikke var sat. Filen indeholdt kun id'er og hashes og blev flyttet til den private mappe. Den var
  byte-identisk med det manifest, der blev genereret korrekt bagefter.
