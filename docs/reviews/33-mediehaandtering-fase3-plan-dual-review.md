# Review 33 — Mediehåndtering fase 3-plan (dual-review)

**Dato:** 2026-07-20
**Genstand:** `docs/superpowers/plans/2026-07-20-mediehaandtering-fase3-hygiejne.md`
(implementeringsplan mod den mergede spec `docs/superpowers/specs/2026-07-20-mediehaandtering-fase3-hygiejne-design.md`).
**Type:** PLAN-review (ingen kode implementeret endnu). Read-only.

**Metode-note:** Husets normale mønster er Claude + Codex som to uafhængige reviewere.
Codex er ikke tilgængeligt som værktøj i denne sessions miljø (det er brugerens separate
implementerings-agent, ikke en tilgængelig tool her). Fase 3 er derfor kørt som en anden,
fuldt uafhængig subagent — samme kontrakt som Codex-rollen i tidligere reviews (egen
læsning af spec+plan, egen empirisk reproduktion af Fase 1's fund, egen søgning efter nye
fund) — men det er værd at bemærke eksplicit, da det afviger fra præcedensen i review 21/22.

Codex-trigger (Phase 2 = JA, jf. Fase 1's egen vurdering): executable SQL i migrationsblok
(Task 2), en SECURITY DEFINER-guard for concurrency (Task 4/6), og en klient-orkestreret
multi-trins-sekvens uden transaktionsgaranti (Task 8).

---

## Phase 1 — egne fund (verificeret empirisk mod branch `claude/media-fase3-plan`)

### H1 [HIGH→nedjusteret, se Phase 3] — evidens-sikker DELETE overser en fjerde FK mod `relation`
**Lokation:** Plan Task 2, linje 153-166; spec §3.2 linje 143-150.
**Symptom:** Evidens-sikkerheden i migrationsblokkens DELETE begrunder sig kun i
`assertion`/`conclusion`/`note` (`target_type='relation'`). `schema.sql:445` har imidlertid
`haendelse.relation_id BIGINT REFERENCES relation(id)` UDEN `ON DELETE` (default RESTRICT)
— en fjerde reel FK ind mod `relation(id)`, nævnt hverken i spec eller plan.
**Konsekvens:** Skulle en `'afbildet'`-dublet nogensinde få en `haendelse`-tilknytning, ville
DELETE'en (og Task 9's janitor-kategori a, samme mønster) fejle med en rå
foreign-key-violation — et andet fejlmønster end det Task 2 Step 2(c) er designet til at
teste.
**Foreslået fix:** dokumentér `haendelse` eksplicit i evidens-enumerationen, eller tilføj et
eksplicit `NOT EXISTS`-tjek mod den.

### M1 [MEDIUM] — TOCTOU-race i dedup-guarden kan give en misvisende fejltekst
**Lokation:** `schema.sql:1884-1887` (`red_opret_media`); plan Task 4 §4.2 punkt 2.
**Symptom:** Guarden er et almindeligt `IF EXISTS`-tjek uden `FOR UPDATE`/exception-wrap om
selve INSERT'en. Ved en ægte samtidig race rammer taberen Postgres' rå `unique_violation`,
som ikke matcher planens nye specifikke `oversaetFejl`-regex og falder i den generiske
`/duplicate key|unique/i`-fallback ("Findes allerede.") i stedet for den lovede
"Billedet findes allerede i biblioteket — brug 'Tilknyt eksisterende' i stedet."
**Foreslået fix:** wrap INSERT'en i `red_opret_media` i egen `unique_violation`-fangst, eller
dokumentér grenen som accepteret race-vindue.

**Ingen fund** i: cross-platform-kontrakten (web/mobile matcher tegn-for-tegn/linje-for-linje),
GDPR-lækage (redaktion ser allerede alt via `redaktion_read`, jf. `db-rls.sql:231/246` —
pre-flight-opslaget lækker intet nyt), scope-dækning mod spec §1, eller afhængighedskæden.

---

## Phase 3+4 — uafhængig anden-reviewer + reconcile (2026-07-20)

**Verdict:** needs-attention → 1 fund nedjusteret og dokumenteret, 1 accepteret som
restrisiko, 1 nyt fund fundet og fikset i planen (rækkefølge-ombytning).

### Fase 1-fund revurderet

| ID | Verdikt | Reproduktion (verified) | Konsekvens |
|---|---|---|---|
| H1 | **confirmed, nedjusteret** | `schema.sql:445` bekræftet. Men eneste skrivevej til `haendelse.relation_id` (`.claude/skills/daa-haendelser/scripts/load_haendelser.R:73`) kræver `JOIN conclusion … status='afklaret'` — conclusion-bærende rækker er allerede udelukket af DELETE'en. De to mængder er strukturelt disjunkte i dagens kodebase. | Reelt et dokumentationshul, ikke en driftsrisiko i dag — men et hærdningspunkt mod FREMTIDIGE skrivere af `relation_id` der ikke nødvendigvis respekterer conclusion-forudsætningen. |
| M1 | **confirmed** | `schema.sql:1885-1887` bekræftet uden `FOR UPDATE`. `redaktionWrite.ts:497`s eneste dedup-regex er den generiske fallback før Task 4's ændring. | Bekræftet præcist, men severity nedjusteret til L: brugeren får stadig en forståelig fejl i et sjældent, af specen selv erkendt vindue — UX-polering, ikke en funktionel fejl. |

### Nye fund

**M — Task 8: "Flet ind i…" kan efterlade en relations-løs kopi uden planlagt afslutningsvej**
**Lokation:** plan Task 8 / spec §6.3 punkt 2-4.
**Symptom:** Den oprindelige rækkefølge (flyt alle relationer → `fjernMedia` sidst) er
konsistent ved afbrydelse MELLEM to relations-flytninger, men ikke hvis afbrydelsen rammer
EFTER sidste `sletRelation` og FØR `fjernMedia`: kopien har da 0 relationer, er stadig
`upload_status='klar'`, og lander i "løse"-køen uden en tydelig, planlagt vej til at
afslutte netop dét flet.
**Konsekvens:** intet datatab (relationerne er korrekt flyttet), men en uafklaret
robusthedskant.
**Fix (indarbejdet i planen):** rækkefølgen byttes om — `fjernMedia`(kopien) køres FØRST
(parkér i papirkurven), derefter flyttes relationerne én for én. Et afbrudt flow lander da
altid i den allerede velkendte, håndterede tilstand "medie i papirkurv med resterende
relationer" (synlig via papirkurvens "bruges på"), i stedet for en ny, uhåndteret tilstand.

**Verificeret uden fund:** `expo-crypto ~56.x` matcher det eksisterende `~56.x`-mønster i
`mobile/package.json` (Expo SDK 56), ingen config-plugin-behov; `db-verify-media.sql`/
`db-verify.sql` har i dag ingen sha256/`created_at`/`relation_afbildet_uidx`-blokke — Task 1
er korrekt beskrevet som nybygning, ikke en ændring af eksisterende asserts; DELETE-
selvjoinet håndregnet for 3+-dubletgrupper med blandet evidens-status — bevarer korrekt
laveste id, fejler korrekt højlydt på en overlevende evidens-bærende dublet.

### Impact-bucketing
- **Silent-corruption/race:** Ingen — begge oprindelige fund er enten strukturelt lukkede
  (H1) eller giver en korrekt, blot mindre hjælpsom fejl (M1).
- **Robusthed/proces:** Task 8-fundet (uafsluttet flet-mellemtrin) — rettet via rækkefølge.
- **Sikkerhed/hærdning:** H1 nedjusteret til fremtidssikring — `haendelse` tilføjet til
  FK-dokumentationen (Task 2) + defensiv `foreign_key_violation`-fangst i janitorens
  kategori a (Task 9).
- **Scope/afklaring:** M1 dokumenteret som accepteret restrisiko (Task 4) — ingen
  kodeændring i denne fase.

**Ændringer i planen som følge af denne review:**
1. Task 2: `haendelse`-FK dokumenteret som strukturelt udelukket, ikke overset.
2. Task 9 kategori (a): defensiv `foreign_key_violation`-fangst tilføjet som krav.
3. Task 4: M1 dokumenteret som accepteret restrisiko (ingen kodeændring).
4. Task 8: flet-flowets rækkefølge byttet om (`fjernMedia` først, relationer derefter);
   Step 2's verifikation udvidet med et afbrydelses-scenarie.

**Læring:** en evidens-sikker DELETE på én tabel (`relation`) kan ikke uden videre antages
at dække FK-grafen fuldt ud — enhver ny tabel der senere refererer samme mål (`haendelse`
her) skal enten indgå i evidens-enumerationen eller mødes med en defensiv fangst i
oprydningskode, fremfor en stiltiende antagelse om at listen er komplet.
