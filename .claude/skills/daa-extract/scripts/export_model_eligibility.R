#!/usr/bin/env Rscript
# Eligibility-ledger for modelkald (#147 dagsværk 4.3a, Task 5 — spec §9.1-9.2).
#
# Eksporterer HELE batchuniverset: én række pr. source record med eksplicit
# `eligible` eller `excluded`. Grundreglen er, at FRAVÆR IKKE ER TILLADELSE —
# runneren må kun sende en record, der står her som `eligible`, så en record,
# eksporten ikke nåede, bliver afvist i stedet for at slippe igennem.
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
allowed <- c("--source-id", "--output-dir", "--restore-identity")
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

POLICY_VERSION <- "exclusion-2018-20-v1"

con <- DBI::dbConnect(RPostgres::Postgres(),
                      dbname = Sys.getenv("PGDATABASE"), host = Sys.getenv("PGHOST"),
                      port = Sys.getenv("PGPORT"), user = Sys.getenv("PGUSER"),
                      password = Sys.getenv("PGPASSWORD"))
on.exit(DBI::dbDisconnect(con), add = TRUE)
DBI::dbExecute(con, "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")

# Fire regler fra §9.2. Hver record kan rammes af flere; alle årsager bæres med,
# så en redaktør kan se HVORFOR en post ikke blev sendt — ikke bare at den ikke blev.
#
# Regel 3 fortjener en forklaring: en partner uden dødsdato, hvor vielsen er fra
# 1950 eller senere ELLER slet ikke er dateret. Den udaterede halvdel er med vilje
# streng — uden vielsesdato kan reglen ikke frikende nogen, og 62 poster i basen
# har en partner markeret ikke-levende uden dødsdato. Partnerstatus er altså
# upålidelig, og tvivlen skal falde ud til udelukkelse.
rows <- DBI::dbGetQuery(con, "
WITH record_person AS (
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
),
-- Record-input-hashen binder ledgerens godkendelse til ÉT bestemt input.
--
-- Definitionen SKAL være identisk med `evidence_runner.canonical_record_input`:
-- sha256 af HELPOSTENS ordrette tekst, intet andet. Et tidligere udkast hashede
-- string_agg over alle observationer — inklusive klausulbørnene, når writeren var
-- kørt — mens Python hashede en JSON-serialisering af record-objektet. De to kunne
-- aldrig matche, så kontrollen ville enten afvise alt eller blive omgået.
-- (Anden læsers fund 3 ved reviewet af plan 4.3b.)
--
-- Helposten er det rigtige anker: klausulerne er udskåret af netop den tekst, så
-- ændrer teksten sig, er klausulerne også andre.
--
-- Trin 6a: teksten er helpostens GÆLDENDE tekst (private.helpost_text_current), samme
-- som runner-inputtet. Uden tekstversion er det basisteksten, så input_sha for en
-- urørt post er uændret.
record_input AS (
  SELECT sr.record_key,
         encode(extensions.digest(cur.verbatim_text, 'sha256'), 'hex') AS input_sha
    FROM private.source_record sr
    JOIN private.source_record_anchor_current a ON a.source_record_id = sr.id
                                               AND a.decision_status = 'accepted'
    JOIN private.source_observation ob ON ob.occurrence_id = a.occurrence_id
                                      AND ob.parent_observation_id IS NULL
    CROSS JOIN LATERAL private.helpost_text_current(ob.id) cur
   WHERE sr.source_id = $1
)
SELECT sr.record_key,
       COALESCE(principal.hit, TRUE)   AS principal_living,
       COALESCE(relatives.hit, FALSE)  AS relative_living,
       COALESCE(spouse_risk.hit, FALSE) AS spouse_undated_marriage,
       COALESCE(text_filter.hit, FALSE) AS birth_year_text_filter,
       record_input.input_sha
  FROM private.source_record sr
  LEFT JOIN principal   ON principal.record_key   = sr.record_key
  LEFT JOIN relatives   ON relatives.record_key   = sr.record_key
  LEFT JOIN spouse_risk ON spouse_risk.record_key = sr.record_key
  LEFT JOIN text_filter ON text_filter.record_key = sr.record_key
  LEFT JOIN record_input ON record_input.record_key = sr.record_key
 WHERE sr.source_id = $1
 ORDER BY sr.record_key COLLATE \"C\"", params = list(source_id))

DBI::dbExecute(con, "ROLLBACK")
if (nrow(rows) == 0L) stop("EXPORT_NO_ROWS", call. = FALSE)

# BEMÆRK `COALESCE(principal.hit, TRUE)` ovenfor: en record UDEN koblet person kan
# ikke frikendes, så den regnes som levende. Fail-closed også her — det er den
# samme grundregel som "fravær er ikke tilladelse", blot inde i forespørgslen.

records <- list()
for (i in seq_len(nrow(rows))) {
  reasons <- character(0)
  if (isTRUE(rows$principal_living[i]))        reasons <- c(reasons, "principal_living")
  if (isTRUE(rows$relative_living[i]))         reasons <- c(reasons, "relative_living")
  if (isTRUE(rows$spouse_undated_marriage[i])) reasons <- c(reasons, "spouse_undated_marriage")
  if (isTRUE(rows$birth_year_text_filter[i]))  reasons <- c(reasons, "birth_year_text_filter")
  input_sha <- rows$input_sha[i]
  if (is.na(input_sha)) {
    # Uden et input at binde godkendelsen til kan recorden ikke være eligible.
    reasons <- c(reasons, "principal_living")
    input_sha <- strrep("0", 64)
  }
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
cat(sprintf("  pr. regel: principal=%d relative=%d spouse=%d text=%d\n",
            sum(rows$principal_living, na.rm = TRUE),
            sum(rows$relative_living, na.rm = TRUE),
            sum(rows$spouse_undated_marriage, na.rm = TRUE),
            sum(rows$birth_year_text_filter, na.rm = TRUE)))
cat("  SAMMENLIGN med spec §9.2's tal fra 2026-09-06 (46+4 / 13 / 62 / 2).\n")
cat("  En afvigelse er ikke nødvendigvis en fejl — men den skal ses og rapporteres.\n")
