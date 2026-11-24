# Billedtype som kontrolleret ordliste (`media.slags`) — design

**Dato:** 2026-11-25 · **Gren:** `feat/media-slags-ordliste` · **Invariant 9** (kontrolleret vokabular).

## Hvorfor
`media.slags` er fritekst. Prod har 8 værdier (portræt 113, maleri 45, våben 21, gods 11, foto 9, segl 6, medalje 5,
scanning 2), og fire lokale kopier af valglisten i web og mobil (`foto, maleri, portræt, segl, dokument`) kender kun
halvdelen. Listen blander **motiv** (portræt, våben, segl, gods) og **teknik** (maleri, foto), så »alle portrætter« er
ikke en pålidelig forespørgsel: bogens portrætter står som `portræt`, `maleri` eller `foto` efter billedtekstens ordlyd.

## Beslutning (projektejeren 2026-11-25)
`slags` beskriver **kun motivet** — hvad billedet viser. Teknikken hører i det eksisterende medie-faktum `teknik`.

## Ordlisten (`public.vocab`, scheme `media_slags`)
| code | label | i dag |
|---|---|---|
| `portræt` | Portræt | 113 + 45 maleri + 9 foto |
| `våben` | Våben | 21 + 2 scanning (coat_of_arms 1-2) |
| `segl` | Segl | 6 |
| `medalje` | Medalje | 5 |
| `gods` | Gods | 11 |
| `dokument` | Dokument | 0 (findes i valglisten i dag) |

Nye motiver (fx gravsten, kirke) tilføjes som en `vocab`-række + én linje i `MEDIA_SLAGS` (se Klienter).

## Dataflytning (56 billeder) — gennemgås af projektejeren på et lokalt ark før prod
- 45 `maleri` + 9 `foto` → `portræt` (alle afbilder personer; målt 2026-11-25).
- 2 `scanning` (media 7, 8; linjevåbnene) → `våben`.
- **Teknik gemmes kun, hvor den er kendt:** bogens billeder (media ≥ 18) fik `maleri`/`foto` fra billedteksten
  (»Malet af …« / »Foto: …«) → faktum `teknik` = »Maleri« (45) / »Fotografi« (3: 141, 156, 169). De 6 ældre uploads
  (media 10-16) brugte `foto` løst om »billede« (flere er malerier) → ingen teknik; redaktøren kan tilføje den.
- Skrives gennem redaktørens RPC'er (`red_opdater_media`, `red_upsert_fakta`), så hver ændring står i historikken og
  kan fortrydes. Kører i projektejerens shell som billedindlæsningen (plan / `--jeg-mener-det`).

## Håndhævelse (DDL)
- 6 rækker i `public.vocab` (scheme `media_slags`; tabellen er allerede anon-læsbar — ingen ny grant).
- Trigger `BEFORE INSERT OR UPDATE OF slags ON media`:
  1. **Gamle værdier oversættes:** `maleri`, `foto`, `portraet` → `portræt`; `scanning` → `våben`.
  2. Derefter skal `slags` findes i `vocab` (scheme `media_slags`) — ellers fejl `23514` med dansk besked, som
     redaktionsfladen oversætter. `NULL`/tom afvises (`red_opret_media` kræver allerede en værdi; `red_opdater_media`
     afviser tom; alle 222 rækker har en værdi).
- **Hvorfor oversætte i stedet for at afvise:** fortryd (`red_fortryd_change_set`) skriver hele den gamle række tilbage
  (`_version_upsert_row`). 132 af 469 medie-hændelser i historikken bærer `maleri`/`foto`/`scanning` (målt 2026-11-25).
  Afviste triggeren dem, kunne ingen af de ændringer fortrydes; uden trigger ville en fortrydelse af fx en gammel
  titelrettelse stille sætte `slags` tilbage til `maleri`. Med oversættelsen virker fortryd, og motivet består.
  (Fortrydes selve dataflytningen, fjernes `teknik`-faktummet, og `slags` forbliver `portræt`.)
- Navngiven blok i `db-migrations.sql`, assert i `db-verify.sql`, `schema.sql` opdateret. Blokken stopper, hvis en
  eksisterende række har en værdi uden for listen — derfor kører den efter dataflytningen.

## Skrivere og læsere (sporet 2026-11-25)
- Skrivere: `red_opret_media` (via `red_upload_media`), `red_opdater_media`, R-loaderen (`R/billeder-2018-20-load.R`)
  og parseren `billeder_2018_20.py` (sætter i dag `maleri` ved »Malet af …« og `foto` ved »Foto: …« — fremover
  `portræt` + `teknik`). `R/media-janitor.R` skriver ikke `slags`.
- Læsere med logik: `erPortraetSlags`/`PORTRAIT_SLAGS` (`@daa/core`, R-loaderens `BILLEDER_PORTRAET_SLAGS`),
  `fetchMediaAfSlags('våben')` (våbengalleriet). Ingen SQL-funktion eller RPC filtrerer på `media.slags`.
- **Våbengalleriet:** efter flytningen er media 7 og 8 (`coat_of_arms` 1-2) også `våben` og ville dukke op i galleriet
  »Våben i Danmarks Adels Aarbog 2018-20« — dobbelt (de vises allerede øverst) og under forkert overskrift. Galleriet
  udelader derfor de medier, der allerede vises som hovedvåben/varianter (test i `media.galleri.test.ts`/`ArmsView`).

## Klienter (web + mobil, via `@daa/core`)
- `MEDIA_SLAGS` (koder + labels) ét sted i `@daa/core` (`mediaVisning.ts`), brugt af de fire valglister. Et nyt motiv
  kræver derfor både en `vocab`-række og en linje i `MEDIA_SLAGS` (ærligt: data + én kodelinje). `db-verify.sql`
  sammenligner `vocab`-rækkerne med en fast liste, og en core-test låser `MEDIA_SLAGS` til samme liste.
- `PORTRAIT_SLAGS` beholder `foto`/`maleri`/`portraet` som tolerance, indtil dataflytningen er i prod; ryddes bagefter.
- R-loaderen (`BILLEDER_PORTRAET_SLAGS`) og `billeder_2018_20.py` sætter fremover `portræt` + teknik i stedet for
  `maleri`/`foto`.
- Valglisterne viser label; standardvalg ved upload bliver `portræt` (i dag `foto`).

## Rækkefølge i prod (ingen nedetid)
1. Klient-PR merges (sender kun gyldige koder; tåler gamle værdier ved visning).
2. Dataflytningen køres (projektejerens shell), kontrol: 0 rækker uden for listen.
3. DDL-blokken (vocab + trigger) deployes; `get_advisors`.
4. Oprydnings-PR: `PORTRAIT_SLAGS` = kun `portræt`.

## Færdigbevis
- Efter 2: `SELECT slags, count(*) FROM media GROUP BY 1` = kun de 6 koder; 48 nye `teknik`-fakta; 56 change_sets.
- Efter 3: en `red_opdater_media` med `slags='maleri'` afvises med dansk besked (prøvet i ROLLBACK); anon læser stadig
  `vocab`.
- Tests: core (`MEDIA_SLAGS`, `erPortraetSlags`), web/mobil valglister, SQL-test af triggeren, R/py-test af nye
  standardværdier.

## Ikke med
Ændring af `teknik`-visningen i lysboksen; nye motiver; godsnavne (#471).
