# Review 18 — Design: flere narrativer pr. person (udgave-nøglede)

**Type:** Design-review (spec, ikke kode). Dual-pass: Claude-draft → Codex adversarial.
**Spec:** `docs/superpowers/specs/2026-07-03-flere-narrativer-per-person-design.md`
**Dato:** 2026-07-03

Codex gav én runde på selve designet (foldet ind i spec'en). Denne review går efter
**restgab** i det nedskrevne design før implementeringsplanen.

---

## H1 [HIGH] — Læser-selectoren afhænger af `source.aar`, men intet skrive-path sætter den

**Lokation:** spec §3.1 pkt. 1+3, §3.4; `schema.sql:983` `red_opret_kilde`.

**Symptom:** Den delte læser-selector ordner efter `source.aar DESC`. Men `red_opret_kilde`
(den genbrugte kilde-RPC) har signaturen `(p_titel, p_slags, p_udgave, p_ekstern)` — **ingen
`aar`**. Spec'en udskyder til planen om `aar` sættes via udvidet `red_opret_kilde` eller
separat. Det er et **load-bearing** valg, ikke en detalje: uden en skrive-vej får hver
redaktør-oprettet udgave `aar = NULL`, og hele "nyeste udgave"-defaulten kollapser til
tie-break (source.id) — dvs. præcis den `max(source_id)`-heuristik Codex forkastede.

**Konsekvens:** Reader-determinisme (kernemålet i "læser minimal") er ikke opnåelig for nye
udgaver med det nuværende design. Backfill af source 1 løser kun de eksisterende data.

**Foreslået fix:** Gør `aar`-skrivevejen eksplicit i designet: udvid `red_opret_kilde` med
`p_aar smallint DEFAULT NULL` (additivt, bagudkompatibelt — mobil-kaldet består). Marker
`aar` som **påkrævet felt i "+ Ny udgave"-UI** når `slags='DAA-udgave'`.

## H2 [MEDIUM-HIGH] — `slags='DAA-udgave'`-filter kan skjule en persons eneste offentlige bio

**Lokation:** spec §3.4 (selector-filter).

**Symptom:** Selectoren vælger kun blandt narrativer hvor kildens `slags='DAA-udgave'`. Hvis
en persons eneste offentlige narrativ kommer fra en ikke-DAA-kilde (TNG, ekstern bog, eller
en narrativ hvor kilden mangler `slags`), viser læseren **ingen biografi** — selv om teksten
findes. I dag ufarligt (alle 591 narrativer er DAA), men fremadrettet en stille regression
netop når TNG/enrichment-narrativer indlæses (jf. CLAUDE.md næste-skridt: TNG-enrichment).

**Konsekvens:** Bio forsvinder tavst for personer der kun har ikke-DAA-prosa.

**Foreslået fix:** Definér eksplicit fallback-kæde i selectoren: (1) foretrukne
`slags='DAA-udgave'` efter `aar DESC`; (2) ellers en hvilken som helst offentlig narrativ
(deterministisk ordnet), med byline udeladt/generisk. Filtrér kun *prioriteringen* på DAA,
ikke *synligheden*.

## M1 [MEDIUM] — `ORDER BY aar DESC` med NULL uspecificeret → nondeterminisme

**Lokation:** spec §3.4.

**Symptom:** Postgres' `ORDER BY aar DESC` placerer NULL **først** som default (NULLS FIRST
ved DESC). En ny udgave uden `aar` ville dermed vinde over en backfillet 2018-udgave. Spec'en
nævner tie-break på `source.id DESC`, men ikke NULL-placering.

**Konsekvens:** Uden `NULLS LAST` inverteres prioriteringen for NULL-aar-udgaver.

**Foreslået fix:** `ORDER BY aar DESC NULLS LAST, source.id DESC` (eller `coalesce(aar, -1)`).
Skriv det eksplicit i spec + selector-testen.

## M2 [MEDIUM] — `side = COALESCE(p_side, side)` gør sidereference umulig at rydde

**Lokation:** spec §3.1 pkt. 2.

**Symptom:** COALESCE-guarden beskytter mod utilsigtet sletning, men betyder også at en
redaktør aldrig kan sætte `side` tilbage til NULL/tom via RPC'en.

**Konsekvens:** Lav — men bevidst tradeoff bør stå i spec (rydning kræver eksplicit sentinel,
fx tom streng → NULL, ellers accepteres begrænsningen).

**Foreslået fix:** Enten acceptér + dokumentér, eller behandl `p_side=''` som eksplicit
rydning: `side = CASE WHEN p_side IS NULL THEN side WHEN p_side='' THEN NULL ELSE p_side END`.

## L1 [LOW] — To narrativ-redigerings-flader; spec dækker kun person-bio-panelet

**Lokation:** `web/src/data/redaktionRead.ts:197` (generisk entity-liste redigerer narrativ
pr. `id`), vs. person-bio-panelet spec'en adresserer.

**Symptom:** Der findes allerede en generisk sti hvor narrativer redigeres som entiteter via
`id`. Spec'en rører den ikke. Ingen konflikt, men to veje til samme tabel med forskellig
nøgle-logik (id vs. source-nøglet upsert) kan drive inkonsistens.

**Foreslået fix:** Note i spec: den generiske entity-sti er uændret og adresserer pr. `id`;
person-bio-panelet er den source-nøglede vej. Ingen kode-ændring nu.

## L2 [LOW] — DROP/CREATE af RPC kræver PostgREST schema-cache-reload

**Lokation:** spec §3.1 pkt. 2.

**Symptom:** Efter `DROP FUNCTION` + `CREATE` med ny signatur kan PostgREST's schema-cache
stadig annoncere den gamle signatur indtil reload.

**Foreslået fix:** Tilføj `NOTIFY pgrst, 'reload schema';` til migrationen (eller noter
Supabase auto-reload-adfærd). Operationelt, ikke design-blokerende.

---

## Sammenfatning (Claude-draft, før Codex)

| ID | Severity | Kerne |
|----|----------|-------|
| H1 | HIGH | Ingen skrive-vej for `source.aar` → determinisme uopnåelig for nye udgaver |
| H2 | MEDIUM-HIGH | DAA-filter skjuler ikke-DAA-bio tavst (regression ved TNG-enrichment) |
| M1 | MEDIUM | `NULLS LAST` + tie-break uspecificeret |
| M2 | MEDIUM | COALESCE-side kan ikke ryddes |
| L1 | LOW | To narrativ-redigerings-flader |
| L2 | LOW | PostgREST cache-reload efter DROP/CREATE |

Invarianterne §6/§7 er ellers respekteret; versionering/undo/mentions pr. narrativ-id er
korrekt uændret (verificeret i denne session mod `schema.sql:1032/1271`).

---

## Codex adversarial-review konsekvens (2026-07-03)

**Verdict:** needs-attention → spec revideret. Codex bekræftede kode-delene, rekalibrerede
severity på 4 fund, og fandt **3 fund jeg missede** (1 HIGH verificeret).

**Bekræftet (verified empirisk i denne reconcile):**
- **NEW-HIGH — mobil-redaktøren knækker af RPC-DROP.** Verificeret:
  `mobile/src/data/redaktionWrite.ts:105` kalder `red_upsert_narrativ` uden `p_source_id`;
  `mobile/.../redaktionRead.ts:183` læser `LIMIT 1`; editor-state holder kun `tekst`+`privat`
  (`mobile/src/app/redaktion/person/[id].tsx:273-292`). At droppe den gamle 4-arg-signatur
  bryder mobilens Gem. **Min "app er eneste klient/lockstep"-antagelse var forkert — der er
  TO klienter.**
- **NEW-MEDIUM-HIGH — mobil `samme_som`-læser-rækkefølge ikke designet.** Verificeret: mobil
  vælger bio pr. rå person (`load.ts:173`) FØR collapse, som coalescer kanonisk-først
  (`collapseSameAs.ts:263-270`). Opfylder ikke "ét foretrukket narrativ på tværs af hele
  identitetsgruppen". `buildModel` selv upåvirket — hullet er *hvornår* selector vs. collapse
  køres.
- **NEW-MEDIUM — RPC "håndhæver" ikke unikhed.** Verificeret: `schema.sql:599` er
  SELECT-derefter-INSERT uden unik-constraint; beskytter ikke mod direkte imports/andre
  skriveveje/eksisterende dubletter. Spec-ordet "håndhæver" er for stærkt.
- **RLS — ingen blocker (bekræftet):** `source` er `USING(true)` for anon+authenticated
  (`db-rls.sql:112`), så klientside-filter på `source.slags` virker; narrative-RLS filtrerer
  private rækker før klienten. Risikoen er klient-divergens, ikke lækage → "delt selector" MÅ
  være én ren funktion/kontrakt-test, ikke to parallelle dataflows.

**Rekalibreret severity:**
1. **H1 HIGH→MEDIUM.** Kode-delen (ingen `aar`, `red_opret_kilde` uden `aar`) bekræftet, men
   jeg blandede *determinisme* og *kronologisk korrekthed*: `source.id DESC` ER deterministisk,
   bare ikke "nyeste udgave". `aar`-kolonne er rimelig men ikke eneste løsning (leksikalsk
   `udgave` er skrøbelig pga. fritekst; `primær`-flag er alternativ men besværligt på tværs af
   `samme_som`). **Designet skal beslutte semantikken eksplicit** — ikke udskyde.
2. **H2 MEDIUM-HIGH→LOW/MEDIUM (produktbeslutning).** Skjult-tekst-claim teknisk korrekt, men
   min fallback "enhver offentlig narrativ" er ikke forsvarlig: kan gøre en TNG-stub/fejlklas-
   sificeret tekst autoritativ + forbliver nondeterministisk. **Bedre policy: DAA først; derefter
   kun eksplicit godkendte fallback-source-typer ELLER et "kan-bruges-som-standardbio"-flag;
   ellers ingen bio.**
3. **M1 MEDIUM→LOW.** Sekundært til H1. Fuld orden: `aar DESC NULLS LAST, source_id DESC,
   narrative.id DESC` (sidste tie-break relevant netop fordi DB-unikhed udskydes).
4. **M2 MEDIUM→LOW.** Bekræftet; konsekvens allerede lav.

**Korrigeret (faktuel fejl i min draft):**
- **L1:** Den generiske entity-sti skriver IKKE direkte til narrative — den sender `red_suggest`
  til staging (`Redaktion.tsx:784`, `redaktionWrite.ts:166`). Ikke en konkurrerende direkte
  update-sti; kun en svag label-afkortnings-parallel (48 tegn). Nedgraderet til note.
- **L2:** Dismissed som kode-fund (ingen `NOTIFY pgrst`-konvention i repo); behold som
  deploy-verifikationspunkt, ikke design-finding.

**Recalibreret løsning (RPC-back-compat) — vigtigste konsekvens:**
Min "DROP + kræv source_id, app i lockstep" var forkert pga. de to klienter. Ny plan:
- Ny signatur `red_upsert_narrativ(..., p_source_id bigint, p_side text DEFAULT NULL)`; DROP
  gammel 4-arg (undgår PostgREST-overload-tvetydighed).
- **Mobil-redaktør indgår i scope som minimal, source-korrekt ændring** (~2 linjer): read
  vælger også `source_id`, write sender `p_source_id`. Beholder single-narrativ-UI (ingen
  faner) men er source-korrekt. Fulde mobil-faner = follow-up. → **Undgår den farlige
  NULL-source-vej helt**; begge klienter forbliver lockstep.

**Impact-bucketing (Codex-værdi i denne pass):**
- Hard runtime-crash undgået: **1** (mobil-redaktør Gem knækket af DROP).
- Silent-corruption/drift undgået: **2** (H2 TNG-stub-autoritativ bio; mobil samme_som-bio pr.
  rå person).
- False-confidence/proces: **1** (RPC "håndhæver"-overclaim).
- Cleanup/sub-optimal (ej i ROI): 3 (M1/M2 severity-nedgradering, L1/L2 korrektion).

**Læring:** *Antag aldrig "eneste klient/lockstep" i en multi-app-monorepo uden at grep'e
begge klienters skrivevej.* Web+mobil deler RPC-kontrakt; en DROP af en RPC-signatur er en
cross-client breaking change. Fanget i memory-kandidat.
