# Review 32 — A3 1939-konverter-pipeline (dual-review)

**Scope:** `convert_1939_stamtavle.py`, `segment_1939.py`, `facit_1939.py` (PR #50, branch `feat/1939-konverter-a3`).
**Kontekst:** Deterministisk konverter fra 1939-stamtavlens ekstraktion (`work_1939_stamtavle/linked_clean.json`,
539 poster) → `load_daa.R`-format. PROD-GATENDE: falske forældre-links = datakorruption; forkert levende-flag =
GDPR-læk. Alt output gitignoreret (levende-PII). A4 dry-run bestået mod frisk isoleret DB.

Claude-side: `/code-review` (high, 4 fund) + `/simplify` (4 agenter) allerede kørt. Denne doc konsoliderer til
Codex adversarial-verifikation af de EMPIRISKE claims + fix-recipes.

---

## EMPIRISKE CLAIMS Codex skal adversarielt verificere

Disse er bevist ved kørsel/DB-query i denne session; Codex skal forsøge at REFUTERE dem mod koden:

**C1 — nr_range-integritet (0 falske børn).** `convert_1939_stamtavle.py` gruppe-for-gruppe-nummererer
(`build_units` ~L382: enheder sorteret på min-_id, medlemmer på _id → hver gruppe = kontinuert nr-blok
"by construction"). `_link_units` sætter `boern.nr_range=[lo,hi]` = barn-gruppens blok. **Claim:** intet range
rummer en ikke-barn. Selv-verificeret: `falske_boern_i_range=0` (L543-550, `_link_foraelder_nr`-tjek) + uafhængig
query. **Refuter-vinkel:** kan et range spænde ikke-kontinuerte poster hvis to grupper deler `(_window,gruppe,note)`-nøgle
forkert, eller hvis nr-tildelingen ikke er kontinuert for en gruppe med interleaved _id?

**C2 — Tier2 navnematch fail-closed (0 modsigelser).** `_tier2_resolve` (~L411): matcher gruppens
`foraeldre_note`-forælder-navn mod poster i slægtled g-1; linker KUN ved præcis ét kandidat; ægtefælle-navn er
eneste disambiguator. Modsigelses-vagt (L471-481): Tier2 må aldrig modsige Tier1 `_foraelder_id` → link ikke.
**Claim:** 0 modsigelser mod 17 ground-truth-grupper; 364/539 linket, 0 implausible fødselsår-links (forælder<barn).
**Refuter-vinkel:** kan `names_match` (delsekvens) matche en FORKERT forælder unikt når den korrekte ikke er
ekstraheret? (Se H1 — ikke linje-scopet.)

**C3 — GDPR/levende.** `load_daa.R`-sweep (L438-449) sætter `levende=TRUE` for født <100 år uden død. A4-load
bekræftede: præcis de 7 født ≥1926 uden dødsfakta → `levende=TRUE` (skjult). **Refuter-vinkel:** findes en 1939-post
med uparsbar/manglende fødselsdato OG plausibelt-nyligt liv der fejlagtigt får `levende=FALSE` (anon-synlig)?
Måling: 0 fødsler uden årstal i 1939, men verificér claim.

**C4 — union_tom_kontekst (73).** A4-load: 73 uopløste barn-opslag = alle `union_tom_kontekst` (børn af forældre
m. 2+ ægteskaber; konverteren sætter ikke `aegteskab_kontekst` pr. barn → loaderen defaulter/parkerer).
**Refuter-vinkel:** er default-adfærden fail-closed (barn placeret i FØRSTE union eller parkeret), eller kan et barn
lande i FORKERT union med falsk evidens? Gruppe-noterne HAR "af første/andet Ægteskab" (uudnyttet).

---

## H1 [MEDIUM] — Tier2 forælder-navnematch er ikke linje/gren-scopet

**Lokation:** `convert_1939_stamtavle.py:424-426` (`_tier2_resolve` kandidat-filter)
**Symptom:** Kandidat = poster hvor `gen_af_id[r._id] == g-1` + navnematch. Filteret begrænser til generation g-1,
men IKKE til samme `_ctx.linje`/gren. Da slægtled-nummerering genstarter per linje, kan en forælder med samme
fornavn i en ANDEN gren (fynsk vs. holstensk — Conrad/Ditlev gentages) blive unikt matchet.
**Verifikation:**
```python
cands = [r for r in records
         if gen_af_id[r["_id"]] == g - 1 and r["_id"] not in medlem_ids
         and names_match(ptoks, name_tokens(r["navn"]))]
if len(cands) == 1: return cands[0]["_id"], "ok_navn"
```
**Konsekvens:** falsk cross-gren forælder-link HVIS korrekt forælder ikke er ekstraheret men wrong-gren same-name er
den unikke kandidat. Empirisk 0 fejl (0 implausible fødselsår, 0 modsigelser) — fail-closed på tvetydighed dækker
delvist. Latent risiko.
**Foreslået fix:** tilføj `and same_linje(r, unit)` til kandidat-filteret — men `_ctx.linje` er upålidelig fritekst;
kræver normalisering, ellers tabes sande links. DEFER til `_ctx.linje`-normalisering findes.

## H2 [LOW-MEDIUM] — Selvreference-vagt dropper hele børne-sæt

**Lokation:** `convert_1939_stamtavle.py:531-534`
**Symptom:** `if lo <= foraelder_post["nr"] <= hi: continue` dropper ALLE børn hvis forælderens eget nr falder i
barn-blokkens [lo,hi] (muligt ved de rapporterede gen-orden-inversioner), i stedet for kun at ekskludere forælderens
eget nr.
**Konsekvens:** fail-closed (taber sande links, laver ikke falske), sjælden. En mere præcis vagt ville ekskludere
kun forælder-nr'et fra range.

## M1 [LOW] — Struktureret kryds_ref når ikke DB

**Lokation:** `convert_1939_stamtavle.py:227` (top-niveau `note`)
**Symptom:** kryds_ref (41 poster) + noter samles i top-niveau `note`, men `load_daa.R` læser kun aegteskab/family-noter,
ikke post-niveau `note`. Struktureret krydsreference tabes ved load (Codex min-krav #3).
**Konsekvens:** mitigeret — teksten bevares i narrative-prosaen (fuldtekstsøgbar). Struktureret navigation tabt (PoC-grænse).

## M2 [FIXED] — aegteskab-datoer manglede A2-felter
Rettet i #4 (`convert_aegteskab` bevarer nu qualifier/certainty/calendar via `_date_fields`-helper).

---

## Codex adversarial-review konsekvens (2026-07-17)

**Verdict: needs-attention (PARTIEL) — Codex stallede mid-stream** (samme "response stalled"-fejl som ramte A3c-
subagenten; pid døde efter foreløbig vurdering, ingen fuld findings-pass). Nåede at trace + rekalibrere 2 fund
(begge REPRODUCERET af mig — ingen peer-review-laundering); C1/C2/C3/H1 forblev Claude-verificeret.

**Recalibreret (Codex, verificeret empirisk):**
1. **C4 → parkeringsadfærd, IKKE "første union".** Codex: "ved 2+ ægteskaber og tom kontekst oprettes en særskilt
   union." REPRODUCERET mod `load_daa.R:355-387`: kommentaren siger ordret "parkeres på en dedikeret union for
   forælderen (**aldrig fejl-tilknyttet 1. ægteskab**)"; `park_union()` (L362-364) opretter en separat union +
   logger `union_<reason>`. Min oprindelige C4/U1-beskrivelse ("placeret i første union") var FORKERT. Konsekvens:
   de 73 er allerede fail-closed (korrekt forælder, parkeret union — ingen falsk ægteskabs-attribution). **U1
   nedgraderes fra "korrekthed" til ren FIDELITY-forbedring** (flyt fra parkeret til korrekt union via gruppe-noter).

**Dismissed (Codex, verificeret):**
2. **H2 → dead code, ikke reproducerbar.** Codex: "en parent kan ikke ligge i sin egen valgte gruppeblok, fordi
   Tier1 afviser medlems-ID og Tier2 udelukker medlemmer." REPRODUCERET: `_tier2_resolve` L423-425 ekskluderer
   `medlem_ids`; Tier1 L482 afviser `fid in unit`-medlemmer (`tier1_ugyldig`). Da nr tildeles gruppe-blokvist er
   forælderens blok DISJUNKT fra børnenes → `lo <= foraelder_nr <= hi` (selvreference-vagt L532) kan aldrig blive
   sand. **H2 fjernes** (defensiv dead code, harmløs — ingen fix nødvendig).

**Ikke fuldført af Codex (forblev Claude-verificeret i denne session):** C1 (nr_range-integritet: DB-query
`falske_boern_i_range=0`), C2 (Tier2 0 modsigelser + 0 implausible fødselsår-links), C3 (GDPR: 7 → levende=TRUE,
A4-load-query), H1 (Tier2 ikke linje-scopet — latent, empirisk 0 fejl).

**Læring:** Codex' partielle pass tilførte reel værdi selv uden fuld gennemløb — den fjernede ét falsk fund (H2)
og korrigerede min misforståelse af parkerings-adfærden (C4). Codex-stabilitet i denne bg-session er upålidelig
(stallede 2×); et fuldt adversarial-pass kræver formentlig retry eller en ny session.

---

## KONSOLIDEREDE ULØSTE TING (lukke-klar liste)

Alle uløste tråde efter A3, grupperet efter gate. Codex-fund foldes ind efter reconcile.

### 🔴 Blokerende før PROD-load (Konvergens/Spor B)
| ID | Emne | Beslutning der skal træffes |
|----|------|------------------------------|
| **K2** | **Staging-strategi.** Umatchede 1939-dubletter (1939-Conrad + 2018-20-Conrad) er anon-synlige straks ved load — intet draft/published-felt, RLS gater ikke på match-status (verificeret). | Vælg: (a) `privat=TRUE` på nye 1939-poster ved load indtil redaktør-matchet, eller (b) nyt source-`draft`-flag + RLS-gate. **Kræver bruger-beslutning.** |
| **Spor B** | Fase 4-cutover: prod-skema-deploy (Problem 2 + A1 + F-01/F-02 + F-02c) + backfill. | Gated på eksplicit prod-godkendelse der navngiver prod-målet + GATE 0-rehearsal mod prod-dump. Prod har INGEN backup. |

### 🟡 Kvalitets-forbedringer (fail-closed/mitigeret — ikke prod-blokerende)
| ID | Emne | Handling |
|----|------|----------|
| **U1** | `union_tom_kontekst` (73 børn af 2+-ægteskabs-forældre → **dedikeret parkerings-union**, Codex-verificeret fail-closed — IKKE korrektheds-fejl). | Ren FIDELITY-forbedring: udled `aegteskab_kontekst` pr. barn fra gruppe-noternes "af første/andet Ægteskab" (data findes) → flyt fra parkeret til korrekt union. |
| **H1** | Tier2-navnematch ikke linje/gren-scopet (latent cross-gren falsk-match; empirisk 0 fejl). | Tilføj linje-scope til kandidat-filter — kræver `_ctx.linje`-normalisering (upålidelig fritekst) først. |
| **M1** | Struktureret `kryds_ref` når ikke DB. | Mitigeret (bevaret i narrative-prosa). Kræver post-note-håndtering i loader (rører delt kode) hvis struktureret navigation ønskes. |
| ~~H2~~ | ~~Selvreference-vagt~~ | **LUKKET** — Codex-verificeret dead code (forælder altid i disjunkt gruppeblok → vagt fyrer aldrig). Ingen fix nødvendig. |

### 🟢 Data/dokumentation
| ID | Emne | Handling |
|----|------|----------|
| **D1** | 18 review.json-poster i karantæne (5 mangler navn = unloadable, 13 ufuldstændige). | Manuel efterbehandling hvis ønsket; ellers accepteret fail-closed udeladt. |
| **D2** | Bibliografi: Holstein "2024" vs "2018-20", 1893 Thiset uafklaret. | Bekræft mod primærkildens titelblad før 1893 evt. importeres. |

_(Codex-fund tilføjes her efter reconcile.)_
