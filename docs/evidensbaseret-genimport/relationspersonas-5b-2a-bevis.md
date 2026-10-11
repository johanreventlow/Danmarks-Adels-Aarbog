# Trin 5b del 2a — afgjorte ægteskaber og forældre bundet til familien, kilden vist: færdigbevis i restore (2018-20)

Beslutning: `docs/decisions.md` 2026-10-11 (del 2 i tre skiver; 2a binder og viser kilden). Spec:
`docs/superpowers/specs/2026-10-11-trin5b-2a-binding-design.md`. Plan:
`docs/superpowers/plans/2026-10-11-trin5b-2a-binding.md` (Task 0-8; to plan-reviews, se planens sidste
afsnit). Kørt 2026-10-11 på grenen `docs/151-5b-2a-binding` i en kopi af del 1's bevisbase, aldrig i prod.
Rapporten indeholder tal, hashes og basenavne — ingen navne, ingen kildetekst og ingen persona-, person-
eller aktør-id'er.

## Kort svar

De **203** ægteskaber, hvor del 1 har afgjort begge parter, er afgjort maskinelt ud fra familiestrukturen,
og sammen med de **7** accepterede forældrepåstande er de bundet til deres kanoniske familie: **210**
bindinger i én batch. Læseren ser nu »Kilde: ‹udgave› · ‹post›« ved ægteskab og forældrelinje: den
offentlige læsefunktion giver **210** rækker (203 ægteskab, 7 forælder) for 209 familier. Det kanoniske
lag er uændret (7 aggregat-hashes), og den offentlige biografilæsning for 50 faste personer er uændret.
Bindingen er hash-autoriseret, idempotent ved genkald og fejler lukket ved drift (4 negativtests).

## Grundlag

| | |
| --- | --- |
| Commit | `07f4b12` (grenen `docs/151-5b-2a-binding`, ikke pushet) |
| Fil-hashes (SHA-256) | `schema.sql` `e136ed35…a0f6`, `db-migrations.sql` `63450306…9224`, `db-rls.sql` `4ae2f3f5…5ede`, `db-verify.sql` `ffcf3667…f015` |
| Arbejdsbase | `daa5b_2a_bevis_20261011183247` = kopi af `daa5b_bevis_20261010093638` (del 1's bevisbase, uændret), løftet med `db-migrations.sql` + `db-rls.sql`; `db-verify.sql` grøn inkl. de fire nye 2a-blokke. Databaseidentitet: system_identifier `7657242220770903427`. **Bevares.** |
| Kilde | 1 (DAA 2018-20), kontrakt 2 |
| Scripts | `~/.private/5b-2a/` (0700, ikke i repo): `hashes.sql` `712ad559…`, `decide.sql` `05d0ac45…`, `bind-preview.sql` `c1f4c5ea…`, `bind.sql` `f4917bb3…`, `read.sql` `efdc1e60…`, `neg.sql` `7278c545…` |

## Afgørelse (spec §4.3)

| | |
| --- | --- |
| Preview | 203 egnede ægteskaber, 3 ordinal-afvigelser; set-hash `d21ac556…6815` |
| Afgjort | 203 (`red_decide_relation_interpretations(1, ‹set-hash›)`), metode `family-structure-v1` |
| Nøgle-digest | md5 af de 203 sorterede fortolkningsnøgler `9873bfe0733b3c5491c747b838135da7` |
| Klassifikationer | 3 `ordinal_afvigelse` (bogens og familiens ægteskabsnummer afviger; bundet trods afvigelsen, M9) |

## Binding (spec §4.4, §7.2)

| | |
| --- | --- |
| Elementer | 210 (203 `relation-marriage-v1`, 7 `relation-parent-v1`), alle egnede |
| Previewhash | `a142b147…c29c` |
| Manifest (skrevet **før** bindingen) | `~/.private/5b-2a/manifest.json` (0600), fil-SHA-256 `d67addd9…d6c9`; tupel-digest over (interpretation_id, family_id, rule_key, rule_version, state_sha256) `475b6598b80873d4d0531293aae6507622eb7bd166e01d50c020014f3d70843f` |
| Batch | 210 bindinger, `target_type='family'` |
| Efter-digest | samme tupler læst fra `interpretation_promotion`: `475b6598…843f` = manifestet |
| Identisk genkald | samme batch-id, 0 nye rækker (replay via `items_sha256`) |
| Vielsesfaktum | `vielse_fact_id` sat i 179 af 210 (ægteskaber med netop ét vielsesfaktum); forældre og ægteskaber uden faktum har `null` |

## 0 kanonisk delta og læsning

| Tabel | Før = efter (md5 af rækkerne i nøgleorden, `TimeZone=UTC`) |
| --- | --- |
| `person` | `1d530c9e…4a3d` |
| `family` | `6519ecc6…2385` |
| `family_member` (nøgle `family_id, person_id, rolle`) | `499bcd6b…054a` |
| `fact` | `fb9728a6…e0e0` |
| `assertion` | `b47d13f8…2d48` |
| `citation` | `77ab9491…cc60` |
| `conclusion` | `7d99b7d6…b994` |
| v2-biografilæsning som `anon`, 50 faste personer (de laveste accepterede id'er i kilde 1; liste-md5 `4a3abe2d…c084`) | 50 rækker, `1447d4ec…8579` |

`public_family_sources` som `anon` for de 209 bundne familier: **210 rækker** (203 `aegteskab`, 7
`foraelder`); digest af (family_id, slags, source_record_ref) `e28a8dc1d3275a20c07fc03bb34fceee`. Skjult
af familiegaten: 0. Bindinger hvis tilstand har ændret sig siden bindingen: 0.

## Negativtests (spec §7.2; hver i sin egen kopi)

| Kopi | Indgreb | Udfald |
| --- | --- | --- |
| A | afgørelse med forkert set-hash | `RELATION_DECISION_SET_DRIFT`, 0 afgjort |
| B | binding med forkert previewhash | `RELATION_PROMOTION_PREVIEW_STALE`, 0 bindinger |
| C | en bærende familierække sat til `omstridt` efter preview | `RELATION_PROMOTION_PREVIEW_STALE`, 0 bindinger |
| D | et medlem af en bundet familie gjort levende | familien synlig med 1 række før, 0 efter |

Kopierne (og deres fælles løftede udgangsbase) er omdøbt til `slet_1011__daa5b_2a_neg{A,B,C,D,base}_20261011183247`
(karantæne; sletning kun efter måling og projektejerens ja).

## Test og webspor

- **SQL i CI's friske sti** (`test-relation-binding.sql`, job `evidence-promotion-db`): regeltype og begge
  validatorer (inkl. mutationsbevis for triggeren), tilstand og klassifikationer, afgørelse, binding,
  replay, partielt unikt indeks og fem to-sessionstests (family_member-write, identitetsgenafgørelse og
  konkurrerende batch venter/fejler lukket med 0 delvise writes; mutationsbevis for afgørelsens låse).
- **SQL i kontrakt 2** (`test-family-sources.sql`, job `writer-1939-v50-db`): ni cases med én frisk
  fixture pr. gate (synlig → én gyldig ændring → skjult): kontrakt 1, levende barn, `staged`, ny
  identitetsversion, tilbagetrukket post, afvist påstand, to supporting-observationer, privat narrativ.
  Hver gatebetingelse er mutationstestet (fjernes den, bliver mindst én case rød).
- **Opgraderingstest** fra `ebf2022` (`test-relation-binding-upgrade.sh`, kun lokalt): `UPGRADE_OK`.
- **Hele CI lokalt**: alle 7 jobs grønne (de fire PostgreSQL-jobs i hver sin midlertidige klynge; node:
  core 421, feed 129, identity-candidates 20, web 949, build, mobil-tsc, mobil 450; python 15 + 37 + 880;
  R 3295).
- **Playwright** (`web/e2e/family-sources.spec.ts`, kun lokalt, spec §8): kildelinjen er en knap hos
  hovedpersonen og ren tekst hos ægtefællen; familie-id'er sendes som decimalstrenge. Fund uden for 2a:
  `web/e2e/feed.spec.ts` fejler lokalt også på koden før 2a (0 feed-kort); e2e kører ikke i CI.

## Advisors

`get_advisors` kan ikke pege på en lokal restore-kopi; 2a's DDL rammer først Supabase ved overførslen.
Afvigelsen fra specens ordlyd er accepteret af projektejeren 2026-10-11: `db-verify.sql` er grøn i
bevisbasen (inkl. ACL- og `prosecdef`-asserts for de nye funktioner), og **`get_advisors` køres som gate i
overførslens runbook umiddelbart efter DDL**.

## Review

Spec: Codex r1 (NO-GO, 3 BLOCKER/8 MAJOR/1 MINOR) og r2 (NO-GO, 0/8/1), alle rettet (specens §12-§13).
Plan: Codex r1 (NO-GO, 4/10/2) og Opus r2 (NO-GO, 4/3/6), alle efterprøvet og rettet (planens sidste
afsnit); ingen GO-stempel på planens sidste revision. Kode-review udestår.

## Status

5b del 2a er **bevist i restore, ikke deployet**. Intet fra 5a eller 5b er i prod; overførslen kræver
5a's ceremoni først og en separat overførsels-spec (spec §9). Næste skive er 2b (nye personer,
familiekorrektion, klausul-disposition).
