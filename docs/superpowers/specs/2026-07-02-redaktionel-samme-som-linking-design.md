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
gyldige. Collapse-fetchen kræver kun `relation` + `afklaret` conclusion (`model.ts`/`load.ts`) — kontrakten er dækket.

## 4. Graf-invarianter i RPC'en (H1) + retnings-semantik (H2)

`samme_som` skal danne **stjerner**: én kanonisk sink pr. komponent, N aliaser der peger ind. `red_samme_som`
håndhæver dette transaktionelt (efter `begin_change_set`), med `SELECT … FOR UPDATE` på de berørte
`samme_som`-rækker i komponenten (concurrency-sikkerhed):

- **G0 self-link:** `p_alias_id <> p_objekt_id`, ellers `RAISE`.
- **G1 eksistens:** begge personer findes.
- **G2 idempotens (præcis retning):** findes `alias→objekt` allerede → returnér eksisterende relation-id (no-op).
- **G3 out-degree ≤ 1:** `p_alias_id` må ikke allerede være subjekt (alias) i et samme_som-link mod en ANDEN
  kanonisk → forhindrer multi-sink (A→B + A→C, der ville karantænere hele komponenten).
- **G4 alias er ikke en eksisterende kanonisk:** `p_alias_id` må ikke være objekt (sink) i noget eksisterende
  samme_som-link → forhindrer stille re-root (at demote en sink til alias flytter komponentens kanoniske identitet).
- **G5 acyklisk:** følg kanonisk-pointere fra `p_objekt_id`; hvis `p_alias_id` nås, ville kanten lukke en cyklus → `RAISE`.

**Retningsskift (re-root) er eksplicit (H2):** modsat-retning-add (`B→A` mens `A→B` findes) rammer G4/G5 →
afvist. For at skifte kanonisk: **fjern linket og genopret modsat** (to versionerede, eksplicitte trin). Ingen
dedikeret `red_reroot`-RPC i v1 (YAGNI — komponenter er par i praksis; UI'ens "Byt retning" planlægger fjern+opret).
Preview/resultat viser altid den **effektive retning** (hvem der er kanonisk).

## 5. Slette-sekvens (H3) — komplet + fortrydbar

`red_fjern_samme_som(p_relation_id)`: redaktion-gated, egen `begin_change_set` (ikke nested — B7-mønster).
Validér at target er en **person→person `samme_som`**-relation (ellers `RAISE` — RPC'en må ikke bruges til
vilkårlige relationer). Genbrug derefter `red_slet_relation`'s KOMPLETTE evidens-sletning (verificeret
`schema.sql`), i FK-orden:

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
  G5 cyklus afvist.
- ikke-redaktion afvist (`current_rolle`).
- fjern → alle evidens-rækker væk; **fjern + fortryd af de 2 eksisterende citerede links** (change_set-restore).

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

- `schema.sql` + `db-migrations.sql` — `red_samme_som` + `red_fjern_samme_som` (idempotent).
- `db-verify.sql` — nye asserts.
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
