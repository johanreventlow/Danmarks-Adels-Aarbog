# Trin 6c-3: A6b-resten — 2018-20's kildetekst får de manglende linjer — design

**Status:** UDKAST 2026-11-07 til projektejerens godkendelse. Projektejeren sprang afklaringsrunden over og bad om
bedste skøn efter måling (som ved 6a); valg, der ikke er projektejerens, er markeret *mit valg*, og §8 samler det,
kun projektejeren kan afgøre.
**Gren:** `docs/trin6c3-spec` fra `main` (`e5a0f83b`).
**Overordnet spec:** `docs/superpowers/specs/2026-10-29-trin6-1939-gennem-kaeden-design.md` (§4 mål, §5 6c, §6 pkt. 1,
6 og 7, §8).
**Mekanismen:** delspec 6a, `docs/superpowers/specs/2026-10-29-trin6a-klausuler-og-kildetekst-revision-design.md`
§2.3, §4.4, §5 og §8 (deployet 2026-10-30, ubrugt).
**Beslutninger:** `docs/decisions.md` 2026-10-28 (A6b afgrænset til narrativerne), 2026-10-29/30 (I-84 parkeret),
2026-11-02 (A6b-resten bliver 6c-3), 2026-11-04 (driftsregel for bindinger), 2026-11-07 (`BEGGE` til 6c-3).
**Review-budget (B13):** 1 Codex-runde på spec+plan (`gpt-6.1-sol`, Opus dømmer), 1 på diffen før prod — samme form
som 6c-1 og 6c-2 (`docs/decisions.md` 2026-11-01).

## 1. Roadmap-kobling

1. **Roadmapmål:** trin 6, overordnet spec §4's mål »A6b-resten« og §8's færdigbevis for den. Sidste del af 6c.
2. **Værdikædeled:** kildetekst → klausuler → forslag → afgørelse → binding for 10 af 2018-20's poster; første
   brug af kildetekst-revisionen (»genkørsel, stale beslutninger« i målarkitekturen) på rigtige data.
3. **Leverancetype:** brug af 6a's generelle mekanisme med 2018-20's eksisterende profiler plus én ceremoni. Ingen ny
   permanent overflade; ny DDL forventes ikke (§4.7).
4. **Værdi:** bogens tekst i databasen bliver hel for de 10 poster. I dag mangler 11 prosalinjer i kildeteksten og
   klausulerne, selv om læseren har dem i narrativet (A6b, 2026-10-28). Læseren mærker intet, hvis det lykkes: de 16
   kildehenvisninger, læseren ser i dag, står der også bagefter.
5. **Færdigbevis:** §6.
6. **Erstatter:** »kendt følge« i decisions 2026-10-28 pkt. 3 (narrativ ≠ kildetekst for 10 poster) og 6a's
   kopi-bevis som eneste brug af revisionen.
7. **Review-budget:** som i hovedet.

## 2. Målt udgangspunkt

Målt 2026-11-07 på en lokal kopi af prod (stand-in `daa5ab_ddl_standin_20261107201240_c3a`, restoret fra
`daa-prod-20261107194057-6m2.dump`, sha `76b5c7e9…`). 6m del 2's ceremoni A, der kom efter dumpet, skrev kun på
kilde 3; kilde 1's tal er derfor prods. Kun antal og nøgler. Planen genmåler mod prod før GO.

### 2.1 Afhængigheder (`source_text_revision_dependencies.sql`, profil `daa-2018-20-source-text-revision-v1`)

| Post | Klausulsæt | Nøgler, der forældes | Bindinger, der falder ud |
|---|---|---|---|
| I-9 | 2 | 5 | 2 assertion |
| I-11 | 2 | 6 | 2 assertion, 1 family |
| I-17 | 1 | 6 | – |
| I-18 | 1 | 4 | – |
| I-32 | 1 | 1 | 1 family |
| I-33 | 1 | 1 | 1 assertion |
| I-44 | 1 | 5 | 1 assertion, 1 family |
| I-89 | 1 | 9 | 3 assertion, 2 family |
| III-37 | 2 | 21 | 2 family |
| III-129 | 2 | 0 | – |
| **I alt** | | **58 nøgler (74 rækker)** | **16: 9 assertion, 7 family** |

Tallene er de samme som 6a §2.3 (2026-10-29). Alle 10 har helpost-status `ok`.

### 2.2 De 58 nøglers aktuelle tilstand

| Status | Antal | Afgjort med |
|---|---|---|
| `accepted`, fakta (navn 4, død 3, fødsel 1, titel 1) | 9 | `machine-corroboration-v1` (trin 4's kontrolmodel) |
| `accepted`, `relation.marriage` | 3 | `family_structure` (5b) |
| `accepted`, `relation.parent` 2 / `relation.child` 2 | 4 | `human_sheet` (projektejerens ark i 5b) |
| `proposed` (embede 9, steder 10, gods 4, hændelser 7, øvrige 12) | 42 | – |

Alle forslag er lavet af `gpt-5.6-terra` med prompt-hash `d46cda80…` (trin 4's kørsel). 13 partsrækker på 8 nøgler.

### 2.3 Personas, narrativer og persondata

- 12 personas på 9 poster, alle med `accepted` identitet. 3 er relations-personas med mention på en klausul (I-89 ×2,
  III-37 ×1); deres mentions står gyldigt mod den klausultekst, de blev skåret af (6a §4.4 pkt. 5).
- 9 publicerede narrativer (A6b har allerede linjerne). III-129 har hverken persona, fortolkning eller
  narrativbinding (en af 149b's fire `unresolved_text`).
- Ingen af personerne er levende. Alle 10 poster er `eligible` under `exclusion-2018-20-v1` (ledger 591/488/103,
  samme regler som trin 4); I-84 er `excluded` (`spouse_undated_marriage`) og parkeret uanset.
- **Drift i udelukkelsesgrundene (noteres, ikke 6c-3's sag):** fordelingen pr. regel er nu principal 47, relative 56,
  spouse 68, text 2 mod trin 4's 46+4 / 13 / 62 / 2. Totalen 488/103 er uændret; skiftet i `relative_living`
  skyldes sandsynligvis 5b's flere relationer. Ingen af de 10 er berørt.

### 2.4 Genbinding under 6c-2's vagt (statisk)

`ALREADY_BOUND_OTHER` (decisions 2026-11-04) tæller kun en anden nøgles binding, hvis `assertion_binding_current`
er sand, og den kræver, at bindingens fortolkning *er* nøglens aktuelle version og står `accepted`. Efter
forældelsen er den aktuelle version `superseded`, så den gamle binding spærrer ikke for en ny nøgle mod samme
påstand. Unikhedsindeksene på `interpretation_promotion` er pr. fortolkningsversion. Det er læst i koden, ikke
kørt: planens første opgave er en øvelse af hele kæden på stand-in'en (§5 pkt. 1).

## 3. Afgrænsning

**I 6c-3:**
- Kildetekst-revisionen af de 10 poster med A6b's sidehovedregel (`page_header`, profil `2018-20-v2`).
- Genkørsel af modellen på de 10 poster, kontrol, afgørelse og genbinding.
- Nøglet afstemning af alle 58 gamle nøgler og alle 16 bindinger.
- Én samlet prod-ceremoni.
- Registrering af `BEGGE` (§4.6).

**Ikke i 6c-3:**
- I-84 (grænserevision, B4-sporet; uændret fra 6a §5).
- Nye påstande, personer eller familier fra de genfundne linjer (opret-benet, B4). Forslag uden påstand at binde til
  står `NO_FACT` og venter, som i 6c-2 §3 pkt. 2.
- III-129's manglende narrativbinding (årsagen er ukendt og ikke linjerne; decisions 2026-10-28).
- 1939 (6d, 6e) og datogrænse-backloggen (decisions 2026-11-07).

## 4. Design

### 4.1 Revisionen (6a's operation, uændret)

Én `source-text-revision:`-operation pr. post gennem reimport-writerens kæde (authorize → preflight → apply). Den nye
tekst er helpostens spænd projiceret med `page_header`-reglen; spændet og renditionen er de samme. Preflighten måler
afhængigheder for hele batchen og binder mængden pr. post; drift i bindingsmængden (mængde, ikke antal) stopper.
Forældelsen gør de 58 nøgler `superseded` og lægger et nyt klausulsæt mod den nye tekstversion. III-129 revideres
som de andre (0 afhængige).

### 4.2 Genkørslen sker uden for prod (*mit valg*)

- Modellen kører på en stand-in, efter at revisionen er kørt dér. Nøglens `key_version 2` binder til
  tekstversionens *nummer* (6a §4.4 pkt. 6), ikke til et tilfældigt id, så forslag beregnet på stand-in'en har samme
  nøgler i prod og kan overføres med 6c-1's pakke.
- **Model og prompt (*mit valg*):** den oprindelige kørsels `gpt-5.6-terra` og prompt `d46cda80…`. Det giver den
  bedste chance for at genfinde de 16 afgjorte værdier; prompt 1.1.0 er tilpasset 1939. Planen bekræfter, at
  modellen stadig kan kaldes; ellers vælges den nærmeste, og det står i §8.
- Alle 10 poster køres (også III-129). Inputtet er helpostens gældende tekst (`helpost_text_current`, som 6a
  flyttede runner-inputtet til).

### 4.3 Afgørelser

- **Fakta:** kontrolmodellen som i trin 4 og 6c-2 (overordnet spec §6 pkt. 1). `MATCH` accepteres maskinelt og
  bindes. Stikprøven er `min(20, n)` `MATCH`, i praksis dem alle (*mit valg*). `REAL_DIFF` går på kort.
- **Ægteskaber:** 5b's `family_structure`-vej, maskinelt som før, når familiens tilstandshash er den samme.
- **Forældre og børn:** de 4 `human_sheet`-afgørelser genbesvares af projektejeren på kort (*mit valg*, se §8 pkt. 2).
  Ved det antal koster det mindre end en regel, der flytter en menneskelig afgørelse fra en nøgle til en anden, og
  det kræver ingen ny DDL.
- **Relations-personas:** genbruges efter 5b's regler (6a §6).
- **Kortene** har 6c-2/6m's form: lokal HTML med posttekst, side og forældre, svar i en token-fil. Forventet under 20
  kort (4 relationer, `REAL_DIFF`, ikke-genfundne); over 30 stopper planen og spørger.

### 4.4 Nøglet afstemning

- **Alle 58 gamle nøgler** afstemmes mod de nye: genfundet (samme persona, prædikat, ordinal og værdi efter
  kontrolmodellens normalisering) eller »ikke genfundet«. Listen pr. nøgle er beviset, ikke et antal.
- **De 16 bindinger** skal hver ende i én af to tilstande: genbundet til en ny nøgles gældende, accepterede version
  mod *samme* mål, eller tilbagetrukket med projektejerens udtrykkelige svar på et kort. En tilbagetrækning er
  synlig i læseren som »fra den oprindelige import« (fakta) eller som en familie uden kildelinje.
- **Hvor afgørelsen gemmes:** en tilbagetrækning kan ikke ligge på den gamle nøgle (den er `superseded`) og har ingen
  ny nøgle. Udfaldet pr. binding (genbundet til ny nøgle / tilbagetrukket / åben) skrives derfor i ceremoniens
  kvittering i basen, sammen med svarfilens hash, som GO'en binder, og med revisionskvitteringens
  `expected_binding_loss` som den liste, der afstemmes imod. Kvitteringen er append-only og aktørbundet, ikke kun
  en privat fil.
- At modellen ikke genfinder en værdi, er et forventeligt udfald, ikke en fejl. Det går på kort med valget
  »tilbagetræk« eller »ved ikke« (bindingen falder ud, og sagen står åben i afstemningen).
- **De 42 `proposed`** var uafklarede før og må være det bagefter. De afstemmes, men intet kræves.
- **Nye forslag fra de genfundne linjer** uden en påstand at binde til bliver `NO_FACT` og tælles (§3).

### 4.5 Én ceremoni

Forældelse og genbinding ligger i samme prod-ceremoni, så læseren aldrig ser de 16 bindinger forsvinde (6a §6).
Svarene på kortene ligger *før* ceremonien (fra stand-in'ens kørsel); ceremonien venter ikke på et menneske midt i.

### 4.6 `BEGGE` registreres, bygges ikke (*mit valg*, se §8 pkt. 3)

6m del 2 registrerede 62 svar »begge kan være rigtige« (41 titler) til 6c-3. At give et »begge rigtige« virkning
kræver en ny påstand for 1939's værdi ved siden af databasens, altså et nyt faktum: opret-benet (B4), som trin 6
udelukker. Visningen af flere udgavers værdier er 6e (fakta pr. udgave). 6c-3 bygger derfor intet for `BEGGE`; de 62
forslag står `proposed`. Decisions får én linje, der flytter spørgsmålet fra 6c-3 til opret-benet/6e.

### 4.7 DDL

6a deployede revisionen, S4-åbningen, `key_version 2` og reservationen af grundlaget `source_text_revision`. 6c-3
forventer ingen ny DDL. Viser øvelsen et behov (fx at 5b's ark-writer ikke kan afgøre en `key_version 2`-nøgle),
kommer det som egen blok med egen DDL-ceremoni, og B13-budgettet gælder uændret.

## 5. Prod

1. **Øvelse først** (planens første opgave): revision → genkørsel → afgørelser → genbinding på stand-in'en, med
   prods 2-minutters grænse. Den skal vise §2.4 i praksis: hver af de 9 påstande og 7 familier kan genbindes til en ny
   nøgle. Fejler den, kommer spec'en tilbage til projektejeren før anden opgave. Øvelsen bekræfter også, at prompten
   bag `d46cda80…` kan hentes i præcis den version, og at 5b's partswriter godtager en modpart, hvis mention sidder
   på en `erstattet` klausul (det mest sandsynlige sted, §4.7's »ingen DDL« kan vise sig forkert).
2. **Runner:** ny privat runner efter 6c-2/6m-formen (`maal`, `dump`, `go`, `apply --jeg-mener-det --go`, `verify`,
   `fortryd`); præcise allow-regler for læse-trin og `go-*` (memory: runner-allowlist). Apply og fortryd kun i
   projektejerens shell.
3. **Ceremonien:** dump med B1 (to kopier, hash noteret) → genmåling (afhængighedsfil = den bundne) → revision ×10 →
   overførsel af forslagene → afgørelser (maskinelle og kortenes) → genbinding → verify. GO binder manifest,
   afhængighedsfil, forslagspakke og svarfil.
4. **Vindue og frys:** fortrydelse er restore af dumpet (forældelse er endelig, 6a §4.4 pkt. 7). Fra dump til
   godkendt verify skrives intet andet i prod, heller ikke på 1939, og driftsreglen fra 2026-11-04 gælder.
5. **Varighed:** prod/stand-in-forholdet måles på genmålingen før en varighed bruges som bevis (memory:
   standin-tid).

## 6. Færdigbevis

- **Tekst og klausuler:** de 10 posters gældende helposttekst indeholder de 11 linjer; hvert nyt klausulsæt er
  delstrenge af netop den tekst.
- **Afstemning:** listen over de 58 nøgler og de 16 bindinger, hver med udfald (§4.4). Ingen binding uden udfald.
- **Narrativer:** de 9 publicerede narrativers `publication_state`-hash er uændret.
- **Komparatoren** (149b, læser nu `helpost_text_current`) viser ingen af de 9 bundne poster som afvigende.
  6a §8's betingelse er opfyldt, så punktet er ubetinget her.
- **Læseren:** de genbundne fakta viser »DAA 2018-20 · <post>« som før; tre stikprøver som anon i browseren.
- **Status:** rækken »Kildetekst-revision« for 2018-20 hæves til `produktionsverificeret`; decisions 2026-10-28 pkt.
  3's kendte følge lukkes.

## 7. Følger

- Trin 6c er afsluttet; næste er 6d.
- Kildetekst-revisionen er bevist på rigtige data og kan bruges af 6m's `K`-sager og 6d, hvis de får brug for den.

## 8. Afgørelser til projektejeren

1. **Genkørsel med den oprindelige model og prompt** (§4.2) i stedet for prompt 1.1.0. *Anbefaling: ja.*
2. **De 4 forældre/barn-afgørelser genbesvares på kort** (§4.3) i stedet for en regel, der flytter dem
   automatisk. *Anbefaling: ja.*
3. **`BEGGE` flyttes til opret-benet/6e** (§4.6) med én linje i decisions. *Anbefaling: ja.*
4. **I-84 forbliver parkeret** (uændret fra 2026-10-29). *Anbefaling: ja.*

## 9. Uden for scope

Grænserevision; opret-benet; 1939's relationer, placements og medlemskaber (6d); fakta pr. udgave (6e);
datogrænse-backloggen; samtidigheds-backloggen fra 2026-11-04.

## 10. Reviewlog

(tom)
