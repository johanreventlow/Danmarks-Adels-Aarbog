# Dual-review: ægtefælle-forankringsplanen (omtale-journal-formen)

**Dato:** 2026-07-29 · **Mål:** `docs/superpowers/plans/2026-07-29-aegtefaelle-forankring.md`
(commit 5e78935) · **Status:** udkast — fund IKKE anvendt, afventer adversarielt pass + reconcile

Planen er selv resultatet af tre reviews og har skiftet konklusion fire gange. Dette review skal
afgøre om den NUVÆRENDE form er logisk holdbar — særligt de steder hvor den siger "kan ikke lade
sig gøre".

## H1 [HIGH] — §5's "realistisk gevinst: 0" er muligvis en over-korrektion

**Lokation:** planens §5.
**Påstand i planen:** selv de 331 2018-20-ægtefæller kan ikke nøgles uden et identitetsregister,
fordi kardinalitets-indvendingen (§4) også rammer dem.
**Mit udkast-fund:** DAA 2018-20's artefakt er **591 selvstændige filer**
(`data/extracted-2026-06-18/I-1.json` …) hvor **filnavnet ER `record_key`** — det var præcis dét
der gjorde record_key-backfillen mulig. Artefaktfilen kunne derfor selv bære en én gang mintet
ægteskabsnøgle (én linje skrevet tilbage i filen posten allerede har). Kravet om et *register*
gælder da kun 1939, hvis artefakt er ét samlet dokument.
**Verifikation (Claude, empirisk):** `ls data/extracted-2026-06-18/ | wc -l` → 591;
gennemløb af filerne → 347 ægteskaber, ordinaler {1: 303, 2: 41, 3: 2, 4: 1}.
**Modspørgsmål det adversarielle pass skal afgøre:**
- Er "skriv nøglen tilbage i artefaktfilen" faktisk reload-durable? Læser `load_daa.R` ægteskaber
  fra disse filer ved genindlæsning, og ville en ny nøgle-property overleve loaderens kontrakt?
- Genskabes `data/extracted-2026-06-18/` nogensinde fra PDF'en (re-ekstraktion), hvorved
  tilbage-skrevne nøgler ville gå tabt?
- Kolliderer det med `has_reset_blocking_editorial_changes()`-spærren?

## M1 [MEDIUM] — §3's RPC-krav er muligvis undervurderet

**Lokation:** planens §3, rækken om `red_ret_ocr_felt`.
**Påstand i planen:** RPC'en "kræver i dag at ankerpersonen er den redigerede person"
(`schema.sql:443-474`).
**Tvivl:** linjenumrene er fra før flere migrationer; og kravet er reelt stærkere — RPC'en slår
anker-rækken op VIA den redigerede persons egen `person_external_id`, så en omtale-forankring er
ikke en lempelse men en ny opslags-sti. Skal verificeres mod den faktiske funktionskrop.

## M2 [MEDIUM] — §8's reload-durability nævner `import_korrektion`, men er journalen på reset-listen?

**Påstand i planen:** "`person_external_id` og `import_korrektion` nulstilles begge ved reset."
**Tvivl:** `load_helpers.R`'s `loader_model_tables()` blev citeret for `person_external_id` —
men står `import_korrektion` faktisk på listen? Hvis IKKE, er journalen reload-durable af sig
selv, og §8-punktet er delvist forkert (i den gunstige retning).

## L1 [LOW] — tal-drift i §1

627 ægtefæller er målt før dubletsletningen ramte ægtefæller? Sletningerne ramte kun
1939-hovedposter (924–1462), så 627 bør stå — men "627 af 1733" og "36 %" skal genberegnes hvis
antallet har flyttet sig.

## Adversarielt pass — fokus

For HVERT fund: bekræft / afvis / rekalibrér med fil:linje-evidens. Særligt H1's tre modspørgsmål.
Derudover: find fejl i planens §4-logik (LLM-proveniens for ordinal) og §6-rækkefølge som dette
udkast IKKE har set.

---

## Reconcile (2026-07-29, fable som modpart)

Verdict: **needs-attention** — planen omskrives på 5 punkter.

**Bekræftet (verified — reproduceret af Claude):**
- **M2:** `import_korrektion` står IKKE på `loader_model_tables()` (`load_helpers.R:75-79`) og
  `load_daa.R:285` siger eksplicit "uden for model_tables/TRUNCATE". Planens §8-sætning var
  faktuelt forkert — journalens reload-durability er selve designet.
- **Fund C:** `has_reset_blocking_editorial_changes()` whitelister KUN strengen
  `'red_ret_ocr_felt'` (`load_helpers.R:42`). Nyt operationsnavn → reset blokeres altid; genbrugt
  navn → reset tillades før loaderen kan replaye omtaler. Helper+loader skal opdateres senest
  samtidig med RPC'en.
- **Fund B:** anker og ægtefælle har begge `rolle='partner'`, og `partner_ekstern_ref`-grenen
  (`load_daa.R:379-386`) linker en eksisterende, ankret person som partner → to skrivestier til
  samme assertion. Omtale-stien skal gates til partnere UDEN eget anker.
- **Fund A:** §3's fem lag stempler aldrig `aegteskab_noegle` på en DB-række — nøglen kan ikke
  opløses uden en ny kolonne (family/family_member). Logisk hul, bekræftet ved genlæsning af planen.
- **539−515-aritmetik:** reproduceret — `nr 43` blev ALDRIG loadet (mangler i prod-dump fra før
  sletningerne; 538 rækker, nr-rum 1-539). 539 − 1 − 23 = 515. Planens "de 23 forklarer forskellen"
  var upræcis.

**Recalibreret:**
- **H1:** "realistisk gevinst: 0" er en over-korrektion (2018-20 behøver ikke 1939-kaliber
  register — ankeridentiteten er stabil, filnavn=record_key, reconciliation er intra-post). MEN
  udkastets "én linje i filen" var en under-korrektion: snapshot-mappen læses af INGEN kode
  (loader tager `clean.json`; grep: kun docs refererer mappen), en ny top-property fejler R5
  fail-closed (`validate.py:22,769`), og nøglen mangler stadig en DB-bærer. Reel kanal: nested
  property i `aegteskaber`-objekterne + validate-passthrough + loader-læsning + DB-kolonne.
- **L1:** 627 repo-attesteret; nævneren (1733) kræver DB men rykker ikke konklusionen (36 %).

**Afvist:**
- **M1:** planens linjeref og beskrivelse af ankerkravet var korrekt (`schema.sql:470`
  `IF v_anchor_person <> p_person_id`); mit modargument om opslags-stien var forkert. Fable
  fandt i stedet et ekstra krav planen manglede: personen må kun have ét anker i alt
  (`schema.sql:471-474`).

**Læring:** modparten afviste ét af mine fund (M1) og skærpede et andet i BEGGE retninger (H1) —
det er præcis den asymmetri et ekko ikke leverer.
