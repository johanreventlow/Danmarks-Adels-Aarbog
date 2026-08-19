# DAA 1939 v50 — fase D1: publicering af 68 personer

**Status:** UDFØRT i produktionen 2026-08-19 22:20 UTC (`change_set 955`).

> **Dette dokument var planlagt som en GO-pakke til forhåndsgodkendelse.**
> Det blev det ikke. Publiceringen blev kørt mod produktionen ved en fejl,
> før pakken var skrevet (se »Hvad der gik galt« nedenfor). Brugeren har
> efterfølgende besluttet at lade ændringen stå. Dokumentet står derfor som
> en efterrationaliseret redegørelse — ikke som en godkendelse, der blev
> givet på forhånd.

## Hvad der blev ændret

| Mål | Før | Efter |
|---|---|---|
| `person.staged` | 96 | **28** |
| `person` i alt | 1812 | 1812 |
| `fact` | 7199 | 7199 |
| `relation` | 2031 | 2031 |
| 1939-narrativer | 577 | 577 |

**68 personer blev offentligt synlige:** 44 valgte probander + 24
ægtefælle-stubs, som `red_publicer_personer` trækker med sig, så et ægteskab
ikke står med en usynlig part.

Efterkontrol mod `change_set 955`: 68 rørte rækker, 68 afstagede, **68
offentligt kvalificerede** (0 levende, 0 private). Intet ud over `staged` er
rørt.

## Grundlag

| Artefakt | SHA-256 |
|---|---|
| `staged-selection-v1.json` | `f85c4212061ebd5bc1c0…` |
| `d1-afgoerelser.txt` (brugerens valg) | `2613b0dc9ee4633c5794…` |
| `d1-afgoerelser.json` | `586be1c05a11c2672857…` |
| `d1-publicering-apply.sql` | `04f7b0a59334bcf0d28ae600ef718b824debe96d50ef8a491eecfb85cc439d2e` |
| Prod-dump fra 3 min. før kørslen | `69d7c0018aa58bbae1388855801fdefec15035336884cee4024f09152480aa72` |

Dumpet ligger som
`~/Backups/danmarksadelsaarbog/daa-local-d1-rehearsal-20260820-001747.dump`
(mode 600, 5.877.725 bytes, 1659 katalogposter).

## Udvælgelsen

Tre objektive kriterier, ingen skøn: `staged`, har 1939-narrativ, og
narrativet har en `published` binding i
`private.narrative_record_publication`. Navne indgik bevidst ikke — staged
person 927 hedder »Henrik« og deler navn med otte synlige personer.

To gates lå i eksport-scriptet:

- **C0-berøring:** 0 af de 44 var blandt C0's uafklarede.
- **RPC-ækvivalens:** `red_publicer_personer`s egen WHERE-klausul kørt mod
  udvalget gav 68 — præcis den forudsagte effekt. Partner-udvidelsen var
  altså bevist, ikke antaget.

Seks af de 44 har `samme_som` til 2020-udgaven (937, 985, 1067, 1159, 1209,
1225). Det er tværudgave-links, som bekræfter identiteten; frontendens
`samme_som`-collapse viser de to udgavers narrativer som én person.

## Rehearsal (kørt før prod-kørslen)

Base `daa1939_d1_rehearsal1`, frisk restore af prod-dumpet ovenfor, lokal
PostgreSQL 17, cluster-id `7657242220770903427` — en anden identitet end
produktionen. Kontroltal efter restore matchede prod eksakt (1812 / 96 / 577
/ 592 / 7199 / 2031).

| Trin | Resultat |
|---|---|
| Apply | `D1_APPLY_OK`, `personer_afstaget: 68` |
| Efterkontrol | 28 staged tilbage; person/fact/relation/narrativ uændrede |
| Gentaget kørsel | **afvist fail-closed**: `forventede 96 staged, fandt 28` |

Prod-kørslen gav nøjagtig samme resultat som rehearsal'en.

## Hvad der gik galt

Wrapper-scriptet blev kaldt med et opfundet flag, `--dryrun`, i den tro at
det ville være en tør kørsel. Scriptet havde ingen dry-run-tilstand og
ignorerede argumentet — det forbandt til produktionen og kørte.

To ting fejlede på én gang: en antagelse om en sikkerhedsmekanisme, der
aldrig var bygget, og et prod-script uden værn mod at blive kaldt ved et
uheld.

**Rettet:** `d1-publicering-apply.sh` kræver nu `--jeg-mener-det` og afviser
både tomme og ukendte argumenter. Verificeret på alle tre veje. Fremtidige
prod-wrappere i dette program skal bygges med samme værn fra starten — et
prod-script må ikke kunne køre, fordi nogen kalder det.

## Rest

28 staged tilbage:

- **7 blokerede** (933, 935, 940, 963, 967, 1014, 1135) — venter på C0's
  efterkørsel og C3.
- **21 ægtefæller** med allerede synlig partner — fase D2. De sidder i dag
  med præcis det problem, D1 løste for de 24: en publiceret person med en
  usynlig ægtefælle.

## Fortrydelse

Ændringen er fortrydbar: alle 68 `change_event`-rækker bærer både før- og
efter-tilstand, og `person` står i `version_pk_registry`. `change_set 955`
kan rulles tilbage ad normal vej, hvis det senere viser sig ønskeligt.
