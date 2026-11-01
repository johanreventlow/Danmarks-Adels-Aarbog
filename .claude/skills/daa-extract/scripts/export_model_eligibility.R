#!/usr/bin/env Rscript
# Eligibility-ledger for modelkald (#147 dagsværk 4.3a, Task 5 — spec §9.1-9.2; trin 6c-1 Task 5).
#
# Eksporterer HELE batchuniverset: én række pr. source record med eksplicit
# `eligible` eller `excluded`. Grundreglen er, at FRAVÆR IKKE ER TILLADELSE —
# runneren må kun sende en record, der står her som `eligible`, så en record,
# eksporten ikke nåede, bliver afvist i stedet for at slippe igennem.
#
# Trin 6c-1: én politik pr. udgave (--policy, påkrævet):
#   exclusion-2018-20-v1  §9.2's fire regler, uændrede (principal_living, relative_living,
#                         spouse_undated_marriage, birth_year_text_filter);
#   exclusion-1939-v1     spec 6c-1 §4.3 (no_published_persona, principal_living,
#                         same_as_partner_living, relative_living, text_year_ge_1915).
# Andet → EXPORT_POLICY_UNKNOWN. Helposten vælges med writerens regel, som runner-inputtet
# (export_43b_runner_input.R): slagsen fra --writer-profile (private.writer_config_helpost_kind),
# helposten med private.record_helpost_status(record, slags). Status `ok` giver input_sha over
# helpostens gældende tekst; `none` (ingen helpost af slagsen, fx en strukturpost) giver en
# udelukket række med 64 nuller; `ambiguous`/`outside` stopper eksporten med
# EXPORT_HELPOST_NOT_UNIQUE (samme kode som runner-inputtet: ledgeren skal ikke godkende et input,
# runner-inputtet ikke kan producere). Før trin 6c-1 joinede input_sha alle rodobservationer på
# alle accepterede forankringer, hvilket gav flere rækker pr. record ved flere forankringer.
#
# Læse-kun: REPEATABLE READ READ ONLY, altid ROLLBACK. Samme form som
# export_clause_source_texts.R.
#
# INGEN TEKST OG INGEN NAVNE i outputtet. Ledgeren rejser mellem maskiner og skal
# kunne læses af et menneske uden at eksponere det, den beskytter. Kun
# record-nøgler, status, årsagskoder og hashes.

suppressPackageStartupMessages({ library(DBI); library(RPostgres); library(jsonlite); library(digest) })

args <- commandArgs(trailingOnly = TRUE)
flags <- args[grepl("^--", args)]
allowed <- c("--source-id", "--output-dir", "--restore-identity", "--policy", "--writer-profile")
if (any(!flags %in% allowed) || anyDuplicated(flags) || !all(allowed %in% flags)) {
  stop("EXPORT_CLI_INVALID", call. = FALSE)
}
value <- function(flag) {
  i <- match(flag, args)
  if (is.na(i) || i == length(args) || grepl("^--", args[[i + 1L]])) stop("EXPORT_CLI_INVALID", call. = FALSE)
  args[[i + 1L]]
}
script_dir <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1L])))
source(file.path(script_dir, "export_legacy_migration_candidates_helpers.R"))  # lmc_validate_output_dir

POLICIES <- c("exclusion-2018-20-v1", "exclusion-1939-v1")
POLICY_VERSION <- value("--policy")
if (!nzchar(POLICY_VERSION)) stop("EXPORT_CLI_INVALID", call. = FALSE)
if (!POLICY_VERSION %in% POLICIES) stop("EXPORT_POLICY_UNKNOWN", call. = FALSE)
writer_profile <- value("--writer-profile")
if (!nzchar(writer_profile)) stop("EXPORT_CLI_INVALID", call. = FALSE)

source_id <- suppressWarnings(as.integer(value("--source-id")))
if (is.na(source_id) || source_id <= 0L) stop("EXPORT_CLI_INVALID", call. = FALSE)
output_dir <- lmc_validate_output_dir(value("--output-dir"))
restore_identity <- value("--restore-identity")
if (!nzchar(restore_identity)) stop("EXPORT_CLI_INVALID", call. = FALSE)

out_path <- file.path(output_dir, "eligibility-ledger-v1.json")
if (file.exists(out_path)) stop("EXPORT_OUTPUT_EXISTS", call. = FALSE)

# Ledgeren bærer sin egen regelkildes hash, så en senere læser kan se, hvilken
# implementering der afgjorde hver række (anden læsers R3: hashen må ikke kun
# dække resultatet).
rules_script_sha256 <- digest::digest(file = normalizePath(sub("^--file=", "",
  grep("^--file=", commandArgs(), value = TRUE)[1L])), algo = "sha256")

con <- DBI::dbConnect(RPostgres::Postgres(),
                      dbname = Sys.getenv("PGDATABASE"), host = Sys.getenv("PGHOST"),
                      port = Sys.getenv("PGPORT"), user = Sys.getenv("PGUSER"),
                      password = Sys.getenv("PGPASSWORD"))
on.exit(DBI::dbDisconnect(con), add = TRUE)
DBI::dbExecute(con, "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")

# Helpost-slagsen læses fra writerprofilen, aldrig hardkodet (2018-20: person_post, 1939: person).
# Samme opslag og fejlkode som export_43b_runner_input.R.
kinds <- DBI::dbGetQuery(con, "
  SELECT DISTINCT private.writer_config_helpost_kind(writer_config) AS kind
    FROM private.reimport_writer_profile
   WHERE source_id = $1 AND profile_id = $2", params = list(source_id, writer_profile))
if (nrow(kinds) != 1L) {
  DBI::dbExecute(con, "ROLLBACK")
  stop("EXPORT_WRITER_PROFILE_UNKNOWN", call. = FALSE)
}
helpost_kind <- kinds$kind[[1L]]

# Fælles for begge politikker: én række pr. source record (ALLE records i kilden, også dem uden
# forankring) med helpost-status og, ved `ok`, input_sha over helpostens gældende tekst.
#
# Record-input-hashen binder ledgerens godkendelse til ÉT bestemt input.
#
# Definitionen SKAL være identisk med `evidence_runner.canonical_record_input`:
# sha256 af HELPOSTENS ordrette tekst, intet andet. Et tidligere udkast hashede
# string_agg over alle observationer — inklusive klausulbørnene, når writeren var
# kørt — mens Python hashede en JSON-serialisering af record-objektet. De to kunne
# aldrig matche, så kontrollen ville enten afvise alt eller blive omgået.
# (Anden læsers fund 3 ved reviewet af plan 4.3b.)
#
# Helposten er det rigtige anker: klausulerne er udskåret af netop den tekst, så
# ændrer teksten sig, er klausulerne også andre.
#
# Trin 6a: teksten er helpostens GÆLDENDE tekst (private.helpost_text_current), samme
# som runner-inputtet. Uden tekstversion er det basisteksten, så input_sha for en
# urørt post er uændret. Trin 6c-1: helposten er writerens (record_helpost_status), så
# input_sha er sha256 af præcis runner-inputtets post_verbatim_text.
RECORD_CTE <- "
rec AS (
  SELECT sr.id AS record_id, sr.record_key, h.status AS helpost_status, h.observation_id AS helpost_id
    FROM private.source_record sr
    CROSS JOIN LATERAL private.record_helpost_status(sr.id, $2) h
   WHERE sr.source_id = $1
),
helpost AS (
  SELECT rec.record_key, rec.record_id, rec.helpost_id, cur.verbatim_text
    FROM rec
    CROSS JOIN LATERAL private.helpost_text_current(rec.helpost_id) cur
   WHERE rec.helpost_status = 'ok'
),
record_input AS (
  SELECT record_key, encode(extensions.digest(verbatim_text, 'sha256'), 'hex') AS input_sha
    FROM helpost
)"

# ---- exclusion-2018-20-v1 ------------------------------------------------------------------------
# Fire regler fra §9.2. Hver record kan rammes af flere; alle årsager bæres med,
# så en redaktør kan se HVORFOR en post ikke blev sendt — ikke bare at den ikke blev.
#
# Regel 3 fortjener en forklaring: en partner uden dødsdato, hvor vielsen er fra
# 1950 eller senere ELLER slet ikke er dateret. Den udaterede halvdel er med vilje
# streng — uden vielsesdato kan reglen ikke frikende nogen, og 62 poster i basen
# har en partner markeret ikke-levende uden dødsdato. Partnerstatus er altså
# upålidelig, og tvivlen skal falde ud til udelukkelse.
#
# Trin 6c-1: reglerne 1-4 er uændrede; kun record_input (helpost-reglen ovenfor) er ny. Tekstreglen
# læser fortsat alle rodobservationer på accepterede forankringer (grupperet, så én række pr. record,
# og mindst lige så streng som helposten alene).
SQL_2018_20 <- paste0("WITH ", RECORD_CTE, ",
record_person AS (
  SELECT sr.record_key, pei.person_id
    FROM private.source_record sr
    JOIN person_external_id pei
      ON pei.source_id = sr.source_id AND pei.record_key = sr.record_key
   WHERE sr.source_id = $1
),
-- 1. hovedpersonen er levende eller uafklaret
principal AS (
  SELECT rp.record_key,
         bool_or(p.levende IS DISTINCT FROM FALSE) AS hit
    FROM record_person rp JOIN person p ON p.id = rp.person_id
   GROUP BY rp.record_key
),
-- 2. en partner eller et barn i samme family er markeret levende
relatives AS (
  SELECT rp.record_key,
         bool_or(rel.levende IS DISTINCT FROM FALSE) AS hit
    FROM record_person rp
    JOIN family_member fm_self ON fm_self.person_id = rp.person_id
    JOIN family_member fm_rel  ON fm_rel.family_id = fm_self.family_id
                              AND fm_rel.person_id <> rp.person_id
    JOIN person rel ON rel.id = fm_rel.person_id
   GROUP BY rp.record_key
),
-- 3. partner uden dødsdato, og vielsen er >=1950 eller udateret.
--    NB: datoer bor på `assertion`, ikke på `fact` — fact er slottet, assertion
--    er kildens udsagn om det. En dødsdato kræver derfor BÅDE et 'død'-faktum og
--    en assertion med en faktisk dato; et dateløst dødsfaktum frikender ikke.
spouse_risk AS (
  SELECT rp.record_key, bool_or(
           NOT EXISTS (
             SELECT 1 FROM fact f
               JOIN assertion a ON a.target_type = 'fact' AND a.target_id = f.id
              WHERE f.subjekt_type = 'person' AND f.subjekt_id = sp.id
                AND f.faktatype = 'død'
                AND (a.date_min IS NOT NULL OR a.date_max IS NOT NULL
                     OR NULLIF(btrim(a.date_raw), '') IS NOT NULL))
           AND (marriage.date_min IS NULL
                OR EXTRACT(YEAR FROM marriage.date_min) >= 1950)
         ) AS hit
    FROM record_person rp
    JOIN family_member fm_self ON fm_self.person_id = rp.person_id AND fm_self.rolle = 'partner'
    JOIN family_member fm_sp   ON fm_sp.family_id = fm_self.family_id
                              AND fm_sp.rolle = 'partner'
                              AND fm_sp.person_id <> rp.person_id
    JOIN person sp ON sp.id = fm_sp.person_id
    LEFT JOIN LATERAL (
      SELECT a.date_min
        FROM fact f
        JOIN assertion a ON a.target_type = 'fact' AND a.target_id = f.id
       WHERE f.subjekt_type = 'family' AND f.subjekt_id = fm_self.family_id
         AND f.faktatype = 'vielse'
       ORDER BY a.date_min NULLS LAST
       LIMIT 1
    ) marriage ON TRUE
   GROUP BY rp.record_key
),
-- 4. tekstfilter: posten skriver 'f.' efterfulgt af et fødselsår >=1950.
--    Mønsteret tillader op til 20 ikke-cifre mellem 'f.' og årstallet, fordi
--    bogen skriver 'f. 12. Maj 1955' — ikke 'f. 1955'. En snæver \\s*-form fandt 0.
--    Den brede form fanger også FALSKE positiver som 'f. Bechs Legat, 1966' (hvor
--    'f.' betyder *født* som pigenavn). Det er med vilje: §9.2 kalder selv reglen
--    en MANUEL udelukkelse, så filteret skal rejse tvivlen, ikke afgøre den.
--    Fail-closed — hellere en post for meget i køen end en levende person i et
--    modelkald.
text_filter AS (
  SELECT sr.record_key,
         bool_or(cur.verbatim_text ~ 'f\\.[^0-9]{0,20}(19[5-9][0-9]|20[0-9][0-9])') AS hit
    FROM private.source_record sr
    JOIN private.source_record_anchor_current a ON a.source_record_id = sr.id
                                               AND a.decision_status = 'accepted'
    JOIN private.source_observation ob ON ob.occurrence_id = a.occurrence_id
                                      AND ob.parent_observation_id IS NULL
    CROSS JOIN LATERAL private.helpost_text_current(ob.id) cur
   WHERE sr.source_id = $1
   GROUP BY sr.record_key
)
SELECT rec.record_key, rec.helpost_status,
       COALESCE(principal.hit, TRUE)   AS principal_living,
       COALESCE(relatives.hit, FALSE)  AS relative_living,
       COALESCE(spouse_risk.hit, FALSE) AS spouse_undated_marriage,
       COALESCE(text_filter.hit, FALSE) AS birth_year_text_filter,
       record_input.input_sha
  FROM rec
  LEFT JOIN principal   ON principal.record_key   = rec.record_key
  LEFT JOIN relatives   ON relatives.record_key   = rec.record_key
  LEFT JOIN spouse_risk ON spouse_risk.record_key = rec.record_key
  LEFT JOIN text_filter ON text_filter.record_key = rec.record_key
  LEFT JOIN record_input ON record_input.record_key = rec.record_key
 ORDER BY rec.record_key COLLATE \"C\"")

# ---- exclusion-1939-v1 (spec 6c-1 §4.3) ------------------------------------------------------------
# Alle regler er fail-closed: NULL (og en manglende person-række) tæller som et hit.
#   1. Hovedpersonen er bindingspersonen for helpostens ENE primære persona
#      (private.publication_persona_binding): ingen persona, flere end én, binding_status ≠ 'published',
#      person_id NULL eller en binding til en anden record → no_published_persona. Bindingspersonen
#      levende/privat ≠ false eller staged → principal_living. (staged læses som levende/privat:
#      IS DISTINCT FROM false, så også NULL udelukker.)
#   2. En afklaret samme_som-partner — en relation rolle='samme_som' person↔person i én af de to
#      retninger, direkte (ikke transitivt) — er levende/privat ≠ false → same_as_partner_living.
#   3. Et andet medlem af en family, hvor hovedpersonen eller en af dens samme_som-partnere er medlem,
#      er levende ≠ false → relative_living. »Andet« = ikke hovedpersonen og ikke en af dens partnere
#      (de læses af regel 1-2 med den strengere levende/privat-test).
#   4. Tekst: helpostens gældende tekst indeholder et årstal ≥ 1915 → text_year_ge_1915. To dele, der
#      tælles hver for sig (stdout):
#      - streng: en delstreng 1[6-9][0-9]{2} med værdi ≥ 1915, også klistret til et ord. Skrevet som
#        det ækvivalente 19(1[5-9]|[2-9][0-9]), så overlappende kandidater ikke kan skjule hinanden
#        (regexp_matches 'g' ville i '161919' kun se 1619);
#      - OCR-tolerant: et firetegnsord [1lI][0-9OoSBlI]{3}, der efter rettelse (l,I→1; O,o→0; S→5;
#        B→8) er ≥ 1915. Ordgrænserne er Postgres' \m/\M; en locale, der ikke kender et bogstav som
#        ordtegn, giver flere grænser og dermed flere hits (fail-closed).
#   Reglerne 2-3 kan kun beregnes med en hovedperson; tekstreglen beregnes for enhver helpost.
SQL_1939 <- paste0("WITH ", RECORD_CTE, ",
persona AS (
  SELECT h.record_key, h.record_id,
         count(DISTINCT spm.persona_id) AS n,
         min(spm.persona_id::text)::uuid AS persona_id
    FROM helpost h
    LEFT JOIN private.source_mention sm ON sm.observation_id = h.helpost_id
    LEFT JOIN private.source_persona_mention spm ON spm.mention_id = sm.id AND spm.mention_role = 'primary'
   GROUP BY h.record_key, h.record_id
),
principal AS (
  SELECT pe.record_key, b.person_id
    FROM persona pe
    CROSS JOIN LATERAL private.publication_persona_binding(pe.persona_id) b
   WHERE pe.n = 1 AND b.binding_status = 'published' AND b.person_id IS NOT NULL
     AND b.source_record_id = pe.record_id
),
principal_hit AS (
  SELECT pr.record_key,
         bool_or(p.id IS NULL OR p.levende IS DISTINCT FROM FALSE OR p.privat IS DISTINCT FROM FALSE
                 OR p.staged IS DISTINCT FROM FALSE) AS hit
    FROM principal pr LEFT JOIN person p ON p.id = pr.person_id
   GROUP BY pr.record_key
),
partners AS (
  SELECT pr.record_key, r.objekt_id AS person_id
    FROM principal pr
    JOIN relation r ON r.rolle = 'samme_som' AND r.subjekt_type = 'person' AND r.objekt_type = 'person'
                   AND r.subjekt_id = pr.person_id
  UNION
  SELECT pr.record_key, r.subjekt_id
    FROM principal pr
    JOIN relation r ON r.rolle = 'samme_som' AND r.subjekt_type = 'person' AND r.objekt_type = 'person'
                   AND r.objekt_id = pr.person_id
),
same_as_hit AS (
  SELECT pa.record_key,
         bool_or(p.id IS NULL OR p.levende IS DISTINCT FROM FALSE OR p.privat IS DISTINCT FROM FALSE) AS hit
    FROM partners pa LEFT JOIN person p ON p.id = pa.person_id
   GROUP BY pa.record_key
),
circle AS (
  SELECT record_key, person_id FROM principal
  UNION
  SELECT record_key, person_id FROM partners
),
relative_hit AS (
  SELECT c.record_key, bool_or(p.id IS NULL OR p.levende IS DISTINCT FROM FALSE) AS hit
    FROM circle c
    JOIN family_member fm_self ON fm_self.person_id = c.person_id
    JOIN family_member fm_rel  ON fm_rel.family_id = fm_self.family_id
    LEFT JOIN person p ON p.id = fm_rel.person_id
   WHERE NOT EXISTS (SELECT 1 FROM circle c2
                      WHERE c2.record_key = c.record_key AND c2.person_id = fm_rel.person_id)
   GROUP BY c.record_key
),
text_hit AS (
  SELECT h.record_key,
         COALESCE(h.verbatim_text ~ '19(1[5-9]|[2-9][0-9])', TRUE) AS strict_hit,
         COALESCE(EXISTS (
           SELECT 1 FROM regexp_matches(h.verbatim_text, '\\m([1lI][0-9OoSBlI]{3})\\M', 'g') m
            WHERE translate(m[1], 'lIOoSB', '110058')::integer >= 1915), TRUE) AS tolerant_hit
    FROM helpost h
)
SELECT rec.record_key, rec.helpost_status,
       (principal_hit.record_key IS NULL)       AS no_published_persona,
       COALESCE(principal_hit.hit, FALSE)       AS principal_living,
       COALESCE(same_as_hit.hit, FALSE)         AS same_as_partner_living,
       COALESCE(relative_hit.hit, FALSE)        AS relative_living,
       COALESCE(text_hit.strict_hit, FALSE)     AS text_strict,
       COALESCE(text_hit.tolerant_hit, FALSE)   AS text_tolerant,
       record_input.input_sha
  FROM rec
  LEFT JOIN principal_hit ON principal_hit.record_key = rec.record_key
  LEFT JOIN same_as_hit   ON same_as_hit.record_key   = rec.record_key
  LEFT JOIN relative_hit  ON relative_hit.record_key  = rec.record_key
  LEFT JOIN text_hit      ON text_hit.record_key      = rec.record_key
  LEFT JOIN record_input  ON record_input.record_key  = rec.record_key
 ORDER BY rec.record_key COLLATE \"C\"")

rows <- DBI::dbGetQuery(con, if (POLICY_VERSION == "exclusion-1939-v1") SQL_1939 else SQL_2018_20,
                        params = list(source_id, helpost_kind))
DBI::dbExecute(con, "ROLLBACK")
if (nrow(rows) == 0L) stop("EXPORT_NO_ROWS", call. = FALSE)
# ambiguous/outside: writeren ville afvise recorden (RECORD_HELPOST_AMBIGUOUS/_SUBOCCURRENCE_OUTSIDE), og
# runner-inputtet stopper med samme kode. Ledgeren skrives ikke halvt.
if (!all(rows$helpost_status %in% c("ok", "none"))) stop("EXPORT_HELPOST_NOT_UNIQUE", call. = FALSE)
# Én række pr. record er invarianten; en dublet ville lydløst overskrive en afgørelse nedenfor.
if (anyDuplicated(rows$record_key)) stop("EXPORT_LEDGER_ROW_NOT_UNIQUE", call. = FALSE)

# BEMÆRK `COALESCE(principal.hit, TRUE)` i 2018-20's forespørgsel: en record UDEN koblet person kan
# ikke frikendes, så den regnes som levende. Fail-closed også her — det er den
# samme grundregel som "fravær er ikke tilladelse", blot inde i forespørgslen.
# 1939's modstykke er no_published_persona.
reasons_of <- function(i) {
  reasons <- character(0)
  if (POLICY_VERSION == "exclusion-2018-20-v1") {
    if (isTRUE(rows$principal_living[i]))        reasons <- c(reasons, "principal_living")
    if (isTRUE(rows$relative_living[i]))         reasons <- c(reasons, "relative_living")
    if (isTRUE(rows$spouse_undated_marriage[i])) reasons <- c(reasons, "spouse_undated_marriage")
    if (isTRUE(rows$birth_year_text_filter[i]))  reasons <- c(reasons, "birth_year_text_filter")
    # Uden et input at binde godkendelsen til kan recorden ikke være eligible.
    if (is.na(rows$input_sha[i])) reasons <- c(reasons, "principal_living")
  } else {
    # isFALSE: kun et eksplicit FALSE frikender (NA tæller som ingen hovedperson).
    if (!isFALSE(rows$no_published_persona[i]) || is.na(rows$input_sha[i]))
                                                 reasons <- c(reasons, "no_published_persona")
    if (isTRUE(rows$principal_living[i]))        reasons <- c(reasons, "principal_living")
    if (isTRUE(rows$same_as_partner_living[i]))  reasons <- c(reasons, "same_as_partner_living")
    if (isTRUE(rows$relative_living[i]))         reasons <- c(reasons, "relative_living")
    if (isTRUE(rows$text_strict[i]) || isTRUE(rows$text_tolerant[i]))
                                                 reasons <- c(reasons, "text_year_ge_1915")
  }
  reasons
}

records <- list()
for (i in seq_len(nrow(rows))) {
  reasons <- reasons_of(i)
  input_sha <- rows$input_sha[i]
  if (is.na(input_sha)) input_sha <- strrep("0", 64)
  # unbox() på skalarerne og en ren character-vektor til reasons. Uden unbox
  # skriver jsonlite {"status":["excluded"]} og {"reasons":[["..."]]}, som
  # Python-validatoren korrekt afviser (LEDGER_STATUS_INVALID). Fanget ved den
  # første rigtige kørsel 2026-09-12.
  records[[rows$record_key[i]]] <- list(
    status = jsonlite::unbox(if (length(reasons) == 0L) "eligible" else "excluded"),
    reasons = reasons,
    record_input_sha256 = jsonlite::unbox(input_sha)
  )
}

ledger <- list(
  schema_version      = jsonlite::unbox("evidence-eligibility-1.0"),
  policy_version      = jsonlite::unbox(POLICY_VERSION),
  rules_script_sha256 = jsonlite::unbox(rules_script_sha256),
  source_id           = jsonlite::unbox(source_id),
  restore_identity    = jsonlite::unbox(restore_identity),
  records             = records
)

writeLines(jsonlite::toJSON(ledger, auto_unbox = FALSE, pretty = TRUE), out_path)
Sys.chmod(out_path, "0600")   # §9.1: private artefakter

n_excl <- sum(vapply(records, function(r) r$status == "excluded", logical(1)))
cat(sprintf("ELIGIBILITY_LEDGER_OK records=%d eligible=%d excluded=%d\n",
            length(records), length(records) - n_excl, n_excl))
if (POLICY_VERSION == "exclusion-2018-20-v1") {
  cat(sprintf("  pr. regel: principal=%d relative=%d spouse=%d text=%d\n",
              sum(rows$principal_living, na.rm = TRUE),
              sum(rows$relative_living, na.rm = TRUE),
              sum(rows$spouse_undated_marriage, na.rm = TRUE),
              sum(rows$birth_year_text_filter, na.rm = TRUE)))
  cat("  SAMMENLIGN med spec §9.2's tal fra 2026-09-06 (46+4 / 13 / 62 / 2).\n")
} else {
  text_any <- rows$text_strict | rows$text_tolerant
  cat(sprintf("  pr. regel: uden_helpost=%d no_published_persona=%d principal=%d same_as=%d relative=%d text=%d (text_strict=%d text_tolerant=%d text_kun_tolerant=%d)\n",
              sum(rows$helpost_status == "none"),
              sum(vapply(records, function(r) "no_published_persona" %in% r$reasons, logical(1))),
              sum(rows$principal_living, na.rm = TRUE),
              sum(rows$same_as_partner_living, na.rm = TRUE),
              sum(rows$relative_living, na.rm = TRUE),
              sum(text_any, na.rm = TRUE),
              sum(rows$text_strict, na.rm = TRUE),
              sum(rows$text_tolerant, na.rm = TRUE),
              sum(rows$text_tolerant & !rows$text_strict, na.rm = TRUE)))
  cat("  SAMMENLIGN med spec 6c-1 §2.3's tal (målt på _6bm: 2 / 3 / 11 / 60; 63 udelukket af 563).\n")
}
cat("  En afvigelse er ikke nødvendigvis en fejl — men den skal ses og rapporteres.\n")
