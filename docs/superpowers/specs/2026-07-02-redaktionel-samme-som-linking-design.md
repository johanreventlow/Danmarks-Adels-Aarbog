# Redaktionel identitets-sammenkædning (`samme_som`) — Design

**Dato:** 2026-07-02
**Status:** Godkendt (design) + Codex-reviewet (needs-attention → løst inline)
**Relateret:** `docs/superpowers/specs/2026-07-02-samme-som-collapse-design.md` (frontend-forbrugeren, implementeret),
`docs/decisions.md` § "Identitetssammenkædning: samme_som-relation + collapse i app (løsning A)".

## 1. Formål

Give redaktøren en **rigtig app-funktion** til at markere to `person`-poster som samme fysiske person,
så frontend-collapse'et automatisk folder dem. I dag skabes `samme_som`-links kun via R-scriptet
`post_load_fixup.R` (`link_samme_som`) eller manuel SQL — der er ingen redaktionel UI/RPC. Denne feature
bygger **producenten**; forbrugeren (collapse) er allerede live og ændres ikke.

## 2. Arkitektur: ren ansvarsfordeling

Collapse-review'et (Codex 2026-07-02) fastslog at pre-flight ikke kan være sikkerheds-grænsen (den kører
på et andet datasæt end det offentlige collapse — §7). Derfor:

| Lag | Ansvar | Håndhævelse |
|---|---|---|
| **DB-RPC** (`red_samme_som`/`red_fjern_samme_som`) | Graf-struktur: self-link, eksistens, **ingen cyklus, præcis én sink pr. komponent**, retnings-semantik, komplet evidens-skrivning, komplet slet | **Autoritativ** (transaktionel, låst) |
| **Collapse-kerne** (`collapseSameAs`, uændret) | Vital/køn/konkurrerende-forældre-konflikter → **karantæne** (foldes ikke, fail-safe) | Fail-safe, klient-side |
| **Pre-flight UI-hint** | Advarer redaktøren om de fail-safe-konflikter FØR skrivning | **Rådgivende**, mærket "redaktionel projektion" |

Nøgle: **DB er den eneste sikkerhedsgrænse for graf-invarianterne.** Pre-flight håndhæver intet.

## 3. Datakontrakt (evidens-rækker — hver kolonne)

`red_samme_som(p_alias_id, p_objekt_id)` skriver, i én transaktion (spejler `post_load_fixup.R:65-74`
MINUS citation):

1. `relation(id, subjekt_type='person', subjekt_id=p_alias_id, objekt_type='person', objekt_id=p_objekt_id, rolle='samme_som')`
2. `assertion(id, target_type='relation', target_id=<relation.id>, vaerdi_tekst='samme_som')`
3. `conclusion(id, target_type='relation', target_id=<relation.id>, valgt_assertion_id=<assertion.id>, status='afklaret', blaastemplet_af='redaktionel identitetssammenkædning')`

**Ingen `citation`.** En manuel redaktionel identitets-beslutning har ingen ekstern kilde — provenansen er
`change_set` (via `begin_change_set`, fortrydbart) + `conclusion.blaastemplet_af`. Dette adskiller sig
bevidst fra data-afledte links (R-scriptet citerer en DAA-kilde). Assertions uden citation er strukturelt
gyldige (Codex-2: ingen CHECK/NOT NULL/trigger kræver citation). Collapse-fetchen kræver kun `relation` +
`afklaret` conclusion (`model.ts`/`load.ts`) — kontrakten er dækket.

**ID-allokering (Codex-3 H2 — ærlig afgrænsning):** de tre id'er allokeres via den etablerede `red_*`-konvention
`(SELECT coalesce(max(id),0)+1 …)`. Dette er **codebase-bredt race-følsomt**: ENHVER anden samtidig `red_*`-skriver
(og `begin_change_set`/`log_change` selv) kan vælge samme id og få en PK-fejl → rollback. samme_som-advisory-låsen
serialiserer kun samme_som-mutationer, IKKE andre skrivere — så allokeringen er **ikke** race-fri, og det påstås
ikke. Denne feature indfører ikke problemet og kan ikke løse det lokalt (fixet er sequences/identity på de delte
evidens-tabeller = en tværgående migration, uden for scope). Konsekvens i praksis: en sjælden PK-kollision ruller
identitets-operationen tilbage; redaktøren prøver igen. **Åbent punkt til brugeren:** acceptér denne arvede
begrænsning for v1, eller prioritér den globale sequence-migration separat.

## 4. Graf-invarianter håndhævet i en TRIGGER (Codex-3 H1) + retnings-semantik + concurrency

`samme_som` skal danne **træer med præcis én sink pr. komponent** (kanonisk = den unikke sink); den kanoniske
identitet må aldrig skifte som stille sideeffekt. Collapse KARANTÆNERER en multi-sink-komponent → én forkert kant
kan slå et helt collapse fra. Invarianten beskytter altså delte data og **skal håndhæves under RPC-laget**, ellers
omgår andre skrive-veje den (Codex-3: `red_relation` med vilkårlig `rolle`, `red_slet_*`, `red_fortryd_change_set`,
`post_load_fixup.R`, manuel SQL).

**Enforcement-grænse = trigger `enforce_samme_som_invariants` BEFORE INSERT ON `relation`** (kun når
`rolle='samme_som' AND subjekt_type='person' AND objekt_type='person'`). Den fyrer for ENHVER insert-vej (RPC,
undo-restore, load-script, manuel) og validerer, under en tabel-bred advisory-lås:

1. **`pg_advisory_xact_lock(hashtext('samme_som_mutation'))`** — serialisér samme_som-inserts (reentrant; også
   taget af `red_samme_som` tidligt, se nedenfor). Fjerner phantom-edge-racet (Codex-2 H1).
2. **G0 self-link:** `NEW.subjekt_id <> NEW.objekt_id`.
3. **G3 out-degree ≤ 1:** `NEW.subjekt_id` er ikke allerede subjekt (alias) mod en ANDEN kanonisk → ingen multi-sink.
4. **G4 alias er ikke en eksisterende kanonisk:** `NEW.subjekt_id` er ikke objekt (sink) i noget samme_som-link →
   ingen stille re-root.
5. **G5 acyklisk:** følg kanonisk-pointere fra `NEW.objekt_id`; hvis `NEW.subjekt_id` nås → cyklus → `RAISE`.

(G1 eksistens dækkes af FK'er på `relation.subjekt_id/objekt_id`.) DELETE behøver ingen check (fjernelse af en kant
kan kun gøre grafen mere gyldig) — så undo-restore (re-insert) valideres af INSERT-triggeren; en restore der ville
bryde invarianten (fx en konkurrerende kant tilføjet i mellemtiden) afvises rent.

**`red_samme_som(p_alias_id, p_objekt_id)`** er en tynd, evidens-komplet wrapper OVENPÅ triggeren. Rækkefølge
(Codex-2 M1 — idempotens FØR change_set):
1. `IF current_rolle() <> 'redaktion' THEN RAISE`.
2. `PERFORM pg_advisory_xact_lock(hashtext('samme_som_mutation'))` (samme nøgle som triggeren; reentrant — gør
   G2+insert atomisk).
3. **G2 idempotens FØR `begin_change_set`:** findes `alias→objekt` → returnér eksisterende relation-id (intet change_set).
4. `PERFORM begin_change_set(...)`.
5. Indsæt relation (**triggeren validerer G0/G3/G4/G5**) + assertion + conclusion (§3).

**`red_relation` (generisk) afviser `rolle='samme_som'`** → tvinger brug af `red_samme_som` (så man ikke kan skabe
en evidens-ufuldstændig samme_som-relation uden conclusion). `post_load_fixup.R` bliver nu governet af triggeren
(dens 2 links er gyldige). Manuel privilegeret SQL er stadig en eksplicit invariant-brydende vedligeholdelses-vej
(dokumenteret) — men den normale + undo + load-veje er alle dækket.

Codex-2 verificerede at **G3+G4+G5 bevarer præcis én sink pr. komponent** — også når `objekt` selv er et alias
(kæder D→A1→C er tilladt/benigne: sink C uændret; træer, ikke bogstavelige stjerner). Intet sekventielt modeksempel.
Kæder rører ikke rute/bogmærke-stabilitet (sinken flytter ikke); UI'ens "effektiv retning"-visning er tilstrækkelig.

**Retningsskift (re-root) er eksplicit:** modsat-retning-add (`B→A` mens `A→B` findes) rammer G4/G5 → afvist. For at
skifte kanonisk: **fjern linket og genopret modsat** (to versionerede trin). Ingen `red_reroot`-RPC i v1 (YAGNI —
komponenter er par; UI'ens "Byt retning" planlægger fjern+opret). Preview/resultat viser den **effektive retning**.

## 5. Slette-sekvens (H3) — komplet + fortrydbar

`red_fjern_samme_som(p_relation_id)`: redaktion-gated, **samme advisory-lås som §4 trin 2** (så en samtidig add
ikke racer en delete), egen `begin_change_set` (ikke nested — B7-mønster). Validér at target er en
**person→person `samme_som`**-relation (ellers `RAISE` — RPC'en må ikke bruges til vilkårlige relationer).
Genbrug derefter `red_slet_relation`'s KOMPLETTE evidens-sletning (verificeret `schema.sql`), i FK-orden:

```
DELETE citation  WHERE assertion_id IN (SELECT id FROM assertion WHERE target_type='relation' AND target_id=p_relation_id);
DELETE conclusion WHERE target_type='relation' AND target_id=p_relation_id;
DELETE assertion  WHERE target_type='relation' AND target_id=p_relation_id;
DELETE note       WHERE target_type='relation' AND target_id=p_relation_id;
DELETE relation   WHERE id=p_relation_id;
```

De 2 eksisterende links (Conrad/Detlef) HAR citations (`post_load_fixup.R:70`) — sekvensen håndterer dem;
nye manuelle links har ingen (DELETE citation = no-op). **Test: slet + fortryd begge eksisterende links.**

## 6. Pre-flight UI-hint (M1) — rådgivende, mærket

Før skrivning kan UI'et køre `collapseSameAs` på **redaktions-datasættet** med den hypotetiske kant tilføjet
og vise et **ikke-blokerende** hint hvis komponenten ville blive karantæneret (køn/levetid/konkurrerende
forældre): *"⚠ Foldes ikke endnu — <årsag>. Linket oprettes, men personerne vises separat til konflikten er løst."*

Tydeligt mærket **"redaktionel projektion — offentlig visning kan afvige pga. synlighed (RLS)"**, fordi
redaktions-datasættet er ukollapset + privat-inkluderende, mens det offentlige collapse kører på RLS-synlige
data med completeness-gating. Hintet er en bekvemmelighed, ikke en garanti. Graf-invarianterne (§4) er DB'ens
job og blokerer autoritativt.

## 7. App-lag (web + mobile spejlet)

- **`redaktionWrite.ts`:** to nye `Change`-arter:
  - `sammeSom` `{aliasId, objektId}` → `{ fn: 'red_samme_som', args: { p_alias_id, p_objekt_id } }`
  - `fjernSammeSom` `{relationId}` → `{ fn: 'red_fjern_samme_som', args: { p_relation_id } }`
  Router gennem eksisterende `planCall`/`submitChange` (dry-run viser fn+args; LIVE kalder `supabase.rpc`).
  Redaktion-only: begge er "kendte arter" → direkte RPC (ikke `red_suggest`). Ikke-redaktion har ingen adgang (v1).
- **`redaktionRead.ts`:** hent eksisterende `samme_som`-links for en person (begge retninger) + modpartens navn/år,
  til listen med fjern-knap.
- **UI:** i person-editorens relations-sektion (web `Redaktion.tsx`, mobile `redaktion/person/[id].tsx`):
  "Marker som samme person…" → `PersonPicker` → retningsvælger (default: redigeret person = kanonisk, "Byt
  retning"-knap) → pre-flight-hint → dry-run/preview-ark → LIVE. Samme sektion lister eksisterende links + fjern.

## 8. RLS / GDPR

`red_samme_som` er `SECURITY DEFINER` + `current_rolle()='redaktion'`-gated (som alle `red_*`). Redaktøren ser
alt, så linking af levende/private personer er tilladt på evidens-laget. **Offentligt** foldes et sådant link
IKKE (collapse's completeness-gate: en privat/levende tvilling + kanten er usynlig for anon/medlem → komponenten
er ufuldstændig → karantæne). Dette er kryds-synligheds-broen (Beke-typen) der venter på server-side privacy
(collapse-spec §9) — links kan oprettes nu, men folder først offentligt når den klasse findes. Ingen ny
GDPR-eksponering: RPC'en ændrer kun evidens-laget; RLS + completeness styrer offentlig synlighed uændret.

## 9. Test

**DB (`db-verify.sql`-asserts, kørt mod lokal prod-kopi):**
- opret → relation(samme_som) + assertion(vaerdi_tekst) + conclusion(afklaret, valgt_assertion_id sat) findes.
- G0 self-link afvist; G1 ukendt person afvist; G2 idempotens (samme retning → samme id, ingen dublet).
- G3 multi-sink afvist (A→B eksisterer, A→C afvises); G4 re-root-add afvist (A→B eksisterer, B→A afvises);
  G5 cyklus afvist; kæde D→A1→C tilladt (sink forbliver C, komponent folder til C).
- G2-idempotens (samme retning → samme id) opretter **INGEN** ny change_set (tom-audit-tjek).
- ikke-redaktion afvist (`current_rolle`).
- **trigger-enforcement (Codex-3):** en bar `INSERT` af en samme_som-relation uden om RPC'en der bryder G0/G3/G4/G5
  afvises af triggeren; `red_relation` med `rolle='samme_som'` afvises; undo-restore af et link der ville bryde
  invarianten afvises rent.
- fjern → alle evidens-rækker væk; **fjern + fortryd af de 2 eksisterende citerede links** (change_set-restore).
- **concurrency** (Codex-2): serialiseret via advisory-lås — verificér at to `red_samme_som`-kald der deler
  et alias ikke begge kan committe (anden ser førstes kant → G3 afviser), og at disjunkte kald ikke
  ID-kolliderer. (Testes med to transaktioner mod den lokale prod-kopi.)

**App (`redaktionWrite`-tests, web+mobile):**
- `sammeSom`/`fjernSammeSom` Change → korrekt RPC-kald (fn+args), dry-run vs LIVE.
- pre-flight: `collapseSameAs` med hypotetisk kant → karantæne-tilfælde returnerer et mærket hint; rent tilfælde intet.
- `redaktionRead`: eksisterende links hentes i begge retninger med modpart-navn.

## 10. YAGNI / bevidst fravalg

- Ingen medlems-forslag/staging (redaktion-only).
- Ingen "muligvis samme som"-kladde-tilstand (spec §9 out-of-scope) — links er afklarede med det samme.
- Ingen dedikeret re-root-RPC (fjern+opret dækker par).
- Ingen bulk/auto-matching (crosswalk for støjende).
- Ingen citation på manuelle links (change_set + blaastemplet_af er audit).

## 11. Berørte filer (forventet)

- `schema.sql` + `db-migrations.sql` — trigger `enforce_samme_som_invariants` (BEFORE INSERT ON relation) +
  `red_samme_som` + `red_fjern_samme_som` + guard i `red_relation` (afvis `rolle='samme_som'`). Alt idempotent.
- `db-verify.sql` — nye asserts (inkl. at trigger-veje uden om RPC'en også afvises).
- `web/src/data/redaktionWrite.ts` + `mobile/src/data/redaktionWrite.ts` — Change-arter.
- `web/src/data/redaktionRead.ts` + `mobile/src/data/redaktionRead.ts` — link-fetch.
- `web/src/Redaktion.tsx` + `mobile/src/app/redaktion/person/[id].tsx` — UI.
- Tests: `web/src/data/__tests__/`, `mobile/src/data/__tests__/`.

## 12. Codex adversarial-review reconcile (2026-07-02)

Verdict: **needs-attention → løst inline.** Alle fund verificeret empirisk mod kode før accept.

- **H1** (unik-sink ikke håndhævet) → §4 G3/G4/G5 i RPC'en, transaktionelt + låst. DB er autoritativ (M1).
- **H2** (enten-retning skjuler retnings-rettelse) → §4: modsat-retning afvises (G4/G5); re-root = eksplicit fjern+opret; effektiv retning vises.
- **H3** (slette-orden fejler på citations) → §5: verificeret at de 2 links HAR citations (`post_load_fixup.R:70`); genbrug komplet `red_slet_relation`-sekvens; test slet+fortryd.
- **M1** (pre-flight kan ikke forudsige offentlig adfærd) → §2/§6: pre-flight nedgraderet til mærket rådgivende hint; RPC-graf-check er porten.
- **M2** (evidens-kontrakt underspecificeret) → §3: hver kolonne opremset (valgt_assertion_id, blaastemplet_af); citation-fravalg begrundet.

**Læring:** I et RLS-gated system kan en klient-side pre-flight ikke være sikkerheds-grænsen for invarianter —
den ser et andet datasæt end den offentlige forbruger. Invarianter der beskytter delte data (unik sink, acyklisk)
skal håndhæves transaktionelt i DB'en. Klient-checks er rådgivende, mærket med hvilken projektion de gælder.

### Codex-review runde 2 (på spec'en, 2026-07-02)

Verdict: **needs-attention → løst inline.** Codex bekræftede at G0-G5 er korrekte (intet sekventielt modeksempel;
kæder benigne, sink unik), no-citation er skema-sikkert, og redaktion-gaten holder gennem SECURITY DEFINER.
Concurrency-fund:

- **H1** (`SELECT FOR UPDATE` låser kun eksisterende rækker → phantom-edge-race A→B/A→C) → §4 trin 2:
  én transaktions-`pg_advisory_xact_lock` serialiserer alle identitets-mutationer (sjælden op → ingen praktisk pris).
- **M1** (G2-idempotens efter `begin_change_set` → tom change_set) → §4: G2 flyttet FØR `begin_change_set`.
- **M2** (`max(id)+1` race-følsom for disjunkte kald) → §3: advisory-låsen serialiserer allokeringen; global
  sequence-hærdning er tværgående og uden for scope.

**Læring 2:** row-level `FOR UPDATE` beskytter ikke mod *phantom* kanter (rækker der endnu ikke findes). En tabel-bred
advisory-lås lukker phantom-edge-racet for de veje der TAGER låsen.

### Codex-review runde 3 (på revideret spec, 2026-07-02)

Verdict: **needs-attention → løst inline.** Codex fandt at en RPC-lokal lås ikke håndhæver en invariant som andre
veje omgår:

- **H1** (`red_relation`/`red_slet_*`/`red_fortryd`/`post_load_fixup.R`/manuel SQL omgår RPC-låsen) → §4:
  invarianten flyttet til en **BEFORE INSERT-trigger på `relation`** (dækker ALLE insert-veje, tager selv låsen) +
  `red_relation` afviser `rolle='samme_som'`. red_samme_som er nu en tynd evidens-wrapper ovenpå triggeren.
- **H2** (`max(id)+1` race mod ANDRE red_*-skrivere, ikke kun samme_som) → §3: **falsk "race-fri"-påstand fjernet**;
  dokumenteret som arvet codebase-bred begrænsning; ærligt åbent punkt til brugeren (accept v1 vs. global
  sequence-migration).

**Læring 3:** en invariant der beskytter DELTE data skal håndhæves på den laveste fælles skrive-grænse (trigger/
constraint), ikke i én RPC — ellers er den kun sand "hvis alle bruger min RPC". Og en RPC-lokal lås kan ikke gøre en
codebase-bred `max(id)+1`-allokering race-fri; det er ærligt at afgrænse frem for at påstå en garanti mekanismen ikke giver.
