# 1939 menneskegodkendt efterforankring (human-anchor-adapter)

**Dato:** 2026-08-06

**Status:** Godkendt design. Implementeres i denne worktree.

**Baggrund:** Uafhængigt review 2026-08-06 af undtagelseskø-workflowet påviste,
at redaktørens 25 fagligt korrekte kandidatvalg alle parkeres, fordi den
slutkonvertering, der skulle acceptere dem, kræver en anchored-candidates-
wrapper, som intet komponent producerer. Reviewet påviste desuden, at der ikke
findes nogen reproducerbar vej til at genindlejre en eksporteret kladde i en ny
HTML-generation, og at gendannelsen i browseren er alt-eller-intet.

## 1. Beslutning

Menneskevalget behandles som det, den overordnede genimport-model kalder en
accepteret forankringsafgørelse (jf. `2026-08-02`-designets §4.5): en redaktør
forbinder en kildeforekomst med en logisk kildepost. Adapteren *validerer og
bogfører* denne afgørelse deterministisk — den gætter aldrig selv.

```text
browser-eksport (uændret format)
  → anchor_review_choices_1939.py            (NY: efterforankring, fail-closed)
      → anchored-candidates-wrapper           (input til convert_choice_export)
      → human-evidence-entries                (input til Task 6-evidensjoin)
      → parkeringsrapport                     (præcise danske årsager)
  → convert_choice_export                     (eksisterende, uændret flow)
  → decisions {accepteret | menneskeark | eksplicit_dublet}
  → materialisering/coverage                  (eksisterende validering)
```

## 2. Rå-bro-beslutningen

Efter et menneskeligt review tilfører rå-OCR-broen ikke identitetssikkerhed —
identiteten er etableret af mennesket plus det eksakte, hash-fastlåste
Calamari-span. Broen er redundant proveniens (to uafhængige OCR-gengivelser).

Derfor: **rå-broen er valgfri men registreret** for menneskegodkendte
kandidater. Den etableres deterministisk, hvor den eksisterende invariant
occurrence-alignment giver et entydigt par; ellers accepteres kandidaten med
en eksplicit `approval`-markering. For *automatiske* afgørelser er dual-
rendition-kravet uændret.

Kandidat-skemaet udvides bagudkompatibelt: en accepteret kandidat skal have
`raw_structure_bridge` **eller** `approval`:

```json
"approval": {
  "kind": "human_approved_span_v1",
  "calamari_excerpt_sha256": "<sha256 af det ordrette Calamari-udsnit>"
}
```

Globale invariants er uændrede: kandidat-id-injektivitet, ét ejerskab pr.
kandidat, ikke-overlappende Calamari-spans altid, ikke-overlappende rå-spans
hvor broer findes. `presentation:`-forbuddet er uændret.

## 3. Kandidatidentitet

Adapteren udsteder deterministiske id'er i nyt namespace:

```text
human:1939-v2:span:<sha256(profil \0 char_from \0 char_to \0 sha256(verbatim))>
```

Identiteten er kildeudsnittet, ikke posten; ejerskab bindes særskilt i
wrapperen. Samme span valgt af to poster giver samme id → fanges af
injektivitetskontrollen og parkerer begge.

## 4. Spanetablering (ingen gæt)

1. **Text-anchor-valg** (`presentation:…:text-anchor:<digest>`): digesten
   genberegnes fra baseline-narrativets entydige forekomst i Calamari med
   nøjagtig samme algoritme som generatoren. Digest-mismatch → parkering.
2. **Parserpost-valg** (`lokal_id` eller `presentation:…:post:<indeks>`):
   segmenteringen udvides til at bevare kildelinje-intervallet (`linjer:
   {fra, til}`) pr. post. Spanet udledes positionelt af intervallet — ingen
   tekstsøgning. Postens normaliserede `raw_text` er fortsat visningstekst.
3. Verbatim-udsnittet hashes og fastlåses; alle kilde-hashes valideres mod de
   samme bytes som eksporten er bundet til.
4. Rå-bro: entydigt dækkende Calamari-occurrence + invariant alignment-par →
   den parrede rå-occurrences span som bro (`kind:
   human_approved_occurrence_pair_v1`). Intet par → `approval` alene.

## 5. Bevarelse af menneskearbejde

1. **Genindlejring:** `make_human_review_1939.py --review` accepterer nu også
   en choice-eksport (detekteres på `exported_at`/`outcome`, valideres med
   `validate_choice_export` mod queue-kildens hashes) og indlejrer valgene i
   den nye HTML. Legacy-template-stien er uændret.
2. **Per-post-gendannelse:** en enkelt ugyldig kladdepost sætter posten i en
   synlig karantæne med årsag i stedet for at rydde og blokere alt.
   Karantænen round-trippes i `localStorage` og kan eksporteres som separat
   sikkerhedskopi-fil; hoved-eksporten forbliver skemaren. Kilde-/versions-
   mismatch for hele kladden blokerer fortsat (det er en migrationssituation).
3. **Ærlig UI-kontrakt:** hver kandidat mærkes enten »Forankret kildeevidens«
   (source-bound) eller »Læsehjælp — valget gemmes som redaktionel observation
   og efterforankres maskinelt«. Kvitteringen siger det samme.

## 6. Task 6-sømmen

Publikationsgatens evidensjoin (`_joined_accepted_candidate`) kræver i dag en
dual-evidence-entry med positiv proveniens, som kun de 93 automatiske poster
har. Adapteren udsteder derfor også human-evidence-entries i samme skema
(kandidat + `positive_provenance` med kind `human_approved_span_v1`), og
evidensindlæsningen accepterer approval-kandidater. Uden dette flyttes
blindgyden blot fra konverteringen til publikationsgaten.

## 7. Fejlveje (udtømmende)

Adapteren parkerer med præcis maskinkode + dansk forklaring; parkering er
ikke en programfejl:

- `text_anchor_not_reproducible` — digest kan ikke genberegnes.
- `parser_post_not_found` / `parser_post_ambiguous` — kandidat-id matcher
  ingen eller flere regenererede poster.
- `span_verbatim_mismatch` — udsnittet matcher ikke de fastlåste bytes.
- `overlaps_automatic_candidate` / `overlaps_other_manual_choice`.
- `candidate_claimed_by_multiple_records`.
- `pdf_pages_mismatch` — postens sider stemmer ikke med spanets occurrence.

Ingen fejlvej falder tilbage til navn-, nummer- eller sidebaseret gæt.

## 8. Uden for scope

- Databaser, Supabase, Vercel: ingen skrivning; alt output er private,
  eksklusivt oprettede filer under `work/`.
- Re-segmentering af slutarkets occurrence-blob (s. 595-598): udskudt —
  approval-stien gør den ikke længere blokerende. Noteret som backlog.
- Selve importen/promotion til kanonisk model: særskilt, senere godkendelse
  (jf. promotion-kontrakten 2026-08-03).
