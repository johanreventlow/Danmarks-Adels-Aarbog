# Review 31 — F-02 authenticated fail-close (dual-review)

**Dato:** 2026-07-16
**Scope:** Codex fundament-review F-02 — authenticated-tier lækkede levende personer + deres media.
**PR'er:** #43 (person-lag, MERGED til main) + #45 (media-lag, draft).
**Metode:** TDD mod daa_test2 (RED→GREEN + regression). Codex adversarial-review af påstandene nedenfor.

## Problem

`auth_read`-policies for authenticated-rollen filtrerede kun `person.privat`, ikke `levende`. Enhver
logget-ind bruger (medlem-tier — bl.a. bogmærke-brugere) kunne læse alle ikke-private LEVENDE personer
+ personbundne fakta/relationer/narrativer/evidens **og fotos** uden samtykke. Bryder invariant #8.

## Fix (påstande til adversariel verifikation)

- **P1** — `auth_read` på `person` er nu `levende=false AND coalesce(privat,false)=false` (spejler `anon_read`).
- **P2** — `auth_read` på personbundne tabeller (`person_external_id`, `family_member`, `fact`, `relation`,
  `narrative`, `note`) bruger nu `person_offentlig()` (fail-closed på levende) i stedet for `privat`-only.
- **P3** — `assertion`/`conclusion`/`citation` auth_read var ALLEREDE korrekt (gater på fact/relation-eksistens,
  som selv er person-gated via RLS-kaskade) → **ingen ændring**. Påstand: dette er korrekt uden ændring.
- **P4** — media-laget: `media`/`media_variant`/`storage.objects` auth_read brugte `media_synlig_auth`
  (→ `media_afbilder_privat`, kun privat) → skiftet til `media_synlig_anon` (→ `media_afbilder_skjult`,
  skjuler levende). Påstand: lukker foto-lækken uden at røre redaktion.
- **P5** — `redaktion_read` (additivt lag, `current_rolle()='redaktion'`) er URØRT → redaktion ser stadig
  alt (levende+privat). Verificeret regression.
- **P6** — `using(true)`-tabellerne (vocab/source/place/estate/coat_of_arms/lineage/family/organisation/
  historical_event/repository) er ikke-PII reference-data → `using(true)` for authenticated er OK.

## Spørgsmål til Codex (led efter det jeg missede)

1. Er der en person-PII-bærende tabel med en `to authenticated`-læsepolicy jeg IKKE fail-closede? (fx
   `suggestion`, `bookmark`, versions-/historik-tabeller, eller en jeg overså i person-lag-loopet)
2. P3: er assertion/conclusion/citation-kaskaden reelt fail-closed for authenticated, eller kan en påstand
   om en levende persons fact/relation stadig ses (fx hvis fact/relation-RLS for authenticated selv lækker)?
3. P4: fanger `media_synlig_anon` ALLE media-stier for authenticated? Er der en write-policy
   (`media_obj_write`/`media_obj_update`) eller en variant-sti der stadig eksponerer levende-media?
4. `note`/`narrative`: jeg beholdt `coalesce(privat,false)=false` for eget-flag OG tilføjede
   `person_offentlig(subjekt/target)` — er kombinationen korrekt, eller er der et hul når subjekt_type≠'person'?
5. Interaktion med `person_offentlig` (SECURITY DEFINER): kan en authenticated bruger via en anden policy
   omgå fail-closen (fx læse levende via en join fra en ikke-gated tabel)?

## Verifikation (Claude, empirisk)

- db-verify Task 8b (daa_test2): authenticated ser person levende=0/afdød=1, media levende=0/afdød=1. GREEN.
- RED-demo: gammel `media_synlig_auth`-policy → authenticated ser levende-foto=1 (læk bekræftet).
- Regression: redaktion (seedet profil) ser stadig levende=1.
- Fuld db-verify: `OK: authenticated fail-close` + `OK: media-gating` + `OK: anon afvist`.

## Dual-review konsekvens (2026-07-16)

**Codex utilgængelig — IKKE en godkendelse.** Codex adversarial-review returnerede "No material findings",
MEN med caveat: dens code-mode-host (`~/.local/bin/codex-code-mode-host`) er brudt → den kunne IKKE læse
den faktiske db-rls.sql, kun mit review-notat. Per dual-review-skillens anti-pattern (peer-review-laundering)
tælles "No material findings" derfor IKKE som verifikation. Selv-audit substitueret (rigorøs, mod faktisk fil).

**Selv-audit (alle 20 `to authenticated` SELECT-policies gennemgået mod db-rls.sql):**

| Kategori | Policies | Verdict |
|---|---|---|
| Person + 6 personbundne (373-396) | fail-close via `person_offentlig`/eksplicit levende=false | ✅ inspektion |
| assertion/conclusion/citation (401-411) | gater på fact/relation-EXISTS → RLS-kaskade | ✅ **empirisk (Q2)** |
| media ×3 (201/219/242) | `media_synlig_anon` (skjuler levende) | ✅ empirisk (Task 8b) |
| redaktion_read ×5 | `current_rolle()='redaktion'` (additivt, tilsigtet) | ✅ regression |
| self-scoped ×3 (profiles/bookmark/suggestion) | `auth.uid()`/`user_id`/`forslagsstiller` | ✅ inspektion |
| `using(true)` ×10 reference | vocab/source/place/estate/coat_of_arms/lineage/family/organisation/historical_event/repository | ✅ kolonne-scan: ingen levende-PII |

**Q2 (den eneste påstand med reel usikkerhed) empirisk bekræftet:** seedet levende person + fact + assertion +
conclusion + citation → authenticated ser ALLE fire = 0. RLS-kaskaden (fact/relation-auth_read er person-gated,
og EXISTS-subqueryen i evidens-policyerne respekterer den RLS) fail-closer korrekt. Ingen "claim om levende
persons fact"-læk.

**Ingen nye huller fundet.** F-02 er komplet (person + personbundne + evidens-kaskade + media).

**Noteret uden for F-02-scope (Wave 3):** media WRITE-policies (`media_obj_write`/`media_obj_update`) er ikke
dybde-auditeret — de handler om skrive-adgang (kan authenticated uploade/ændre), ikke F-02's læse-læk. Værd at
tjekke separat.

**Læring:** Codex code-mode-host var brudt → "No material findings" var et falsk-grønt. Verificér ALTID at
Codex faktisk kunne læse koden (dens egen caveat afslørede det) før accept — ellers er det peer-review-laundering.
Substituér rigorøs selv-audit mod den faktiske fil når peer-revieweren er blind. [[codex-flip-patterns]]
