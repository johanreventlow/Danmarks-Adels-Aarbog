#!/usr/bin/env Rscript
# =====================================================================
#  replace_dryrun.R — MATCH-RAPPORT for source-scoped replace (READ-ONLY).
#
#  Første leverance af replay-laget (docs/replay-source-scoped-design.md,
#  issue #123): viser hvad et --replace-load VILLE gøre, uden at skrive.
#  Rapporten er facit for §Ejerskab-afgrænsningen — den opdeler hver matchet
#  persons rækker i source-ejede (replace må røre) vs. rækker med
#  change_event-spor (redaktionelle, må ALDRIG røres).
#
#  Udfald pr. artefaktpost (identitetsregisterets fire + tombstone-vagt):
#    entydig     record_key ∈ registerets aktive OG i prods external_id
#    kun_register record_key aktiv i registeret men ingen prod-person (hul!)
#    tombstonet  record_key er tombstone — må ALDRIG genindsættes
#    ny          record_key ukendt af registeret (kræver mint + menneske)
#  + bortfalden: prod/register-poster som artefaktet ikke længere har.
#
#  Brug:  Rscript .claude/skills/daa-extract/scripts/replace_dryrun.R \
#           "DAA 1939" work_1939_stamtavle/clean_1939.json \
#           work_1939_stamtavle/identitetsregister-1939.json
#  Output: work_1939_stamtavle/replace-dryrun-<dato>.md (gitignoreret) + resumé.
# =====================================================================
suppressMessages({library(DBI); library(jsonlite)})

argv <- commandArgs(trailingOnly = TRUE)
udgave   <- if (length(argv) >= 1) argv[1] else "DAA 1939"
art_path <- if (length(argv) >= 2) argv[2] else "work_1939_stamtavle/clean_1939.json"
reg_path <- if (length(argv) >= 3) argv[3] else "work_1939_stamtavle/identitetsregister-1939.json"
out_path <- file.path(dirname(art_path), paste0("replace-dryrun-", Sys.Date(), ".md"))

host <- Sys.getenv("SUPABASE_HOST"); user <- Sys.getenv("SUPABASE_USER"); pw <- Sys.getenv("SUPABASE_PASSWORD")
if (host == "" || user == "" || pw == "") stop("Sæt SUPABASE_HOST/USER/PASSWORD i ~/.Renviron.")
con <- dbConnect(RPostgres::Postgres(), host = host,
                 port = as.integer(Sys.getenv("SUPABASE_PORT", "5432")),
                 dbname = Sys.getenv("SUPABASE_DB", "postgres"),
                 user = user, password = pw,
                 sslmode = Sys.getenv("SUPABASE_SSLMODE", "require"), bigint = "integer")
on.exit(dbDisconnect(con), add = TRUE)
q <- function(sql, p = list()) if (length(p)) dbGetQuery(con, sql, params = p) else dbGetQuery(con, sql)

# READ-ONLY-vagt: hele sessionen låses til læsning; enhver skrivning fejler.
invisible(dbExecute(con, "SET default_transaction_read_only = on"))

# ---- input ----
art <- fromJSON(art_path, simplifyVector = FALSE)
reg <- fromJSON(reg_path, simplifyVector = FALSE)$poster
reg_aktiv <- vapply(Filter(function(r) r$status == "aktiv", reg), `[[`, "", "book_post_id")
reg_tomb  <- vapply(Filter(function(r) r$status == "tombstone", reg), `[[`, "", "book_post_id")

src_rows <- q("SELECT id FROM source WHERE udgave = $1", list(udgave))
if (nrow(src_rows) != 1) stop(sprintf("source '%s': %d kandidater (fail-closed).", udgave, nrow(src_rows)))
src <- as.integer(src_rows$id[1])

prod <- q("SELECT person_id, record_key, linje, nr FROM person_external_id WHERE source_id = $1", list(src))

# ---- udfald pr. artefaktpost ----
art_keys <- vapply(art, function(p) as.character(p$record_key %||% NA_character_), character(1))
`%||%` <- function(a, b) if (is.null(a)) b else a
art_keys <- vapply(art, function(p) { v <- p$record_key; if (is.null(v) || is.na(v)) NA_character_ else as.character(v) }, character(1))
udfald <- ifelse(is.na(art_keys), "uden_record_key",
          ifelse(art_keys %in% reg_tomb, "tombstonet",
          ifelse(!(art_keys %in% reg_aktiv), "ny",
          ifelse(art_keys %in% prod$record_key, "entydig", "kun_register"))))
bortfaldne_prod <- setdiff(prod$record_key, art_keys[!is.na(art_keys)])
tomb_i_prod <- intersect(reg_tomb, prod$record_key)   # SKAL være tom

match_ids <- prod$person_id[prod$record_key %in% art_keys[udfald == "entydig"]]
ids_sql <- paste(match_ids, collapse = ",")
stopifnot(length(match_ids) > 0, grepl("^[0-9,]+$", ids_sql))

# ---- ejerskabsopdeling (aggregat over alle matchede personer) ----
# Diskriminator: (tabel, (row_pk->>'id')::bigint) i change_event = redaktionelt
# spor. Loaderen logger aldrig (bulk-sti), så ETHVERT spor er RPC-vejens.
red_pk <- function(tabel) sprintf(
  "(SELECT DISTINCT (row_pk->>'id')::bigint pk FROM change_event WHERE tabel='%s')", tabel)

fakta <- q(sprintf("
  SELECT count(*) n, count(ce.pk) n_red,
         count(DISTINCT f.subjekt_id) FILTER (WHERE ce.pk IS NOT NULL) pers_med_red
  FROM fact f LEFT JOIN %s ce ON ce.pk = f.id
  WHERE f.subjekt_type='person' AND f.subjekt_id IN (%s)", red_pk("fact"), ids_sql))

narr <- q(sprintf("
  SELECT n.source_id, count(*) n, count(ce.pk) n_red
  FROM narrative n LEFT JOIN %s ce ON ce.pk = n.id
  WHERE n.subjekt_type='person' AND n.subjekt_id IN (%s)
  GROUP BY 1 ORDER BY 1", red_pk("narrative"), ids_sql))

rel <- q(sprintf("
  SELECT r.rolle, count(*) n, count(ce.pk) n_red
  FROM relation r LEFT JOIN %s ce ON ce.pk = r.id
  WHERE (r.subjekt_type='person' AND r.subjekt_id IN (%s))
     OR (r.objekt_type='person' AND r.objekt_id IN (%s))
  GROUP BY 1 ORDER BY n DESC", red_pk("relation"), ids_sql, ids_sql))

fm <- q(sprintf("
  SELECT count(*) n,
         count(*) FILTER (WHERE EXISTS (
           SELECT 1 FROM change_event ce WHERE ce.tabel='family_member'
             AND (ce.row_pk->>'family_id')::bigint = fm.family_id
             AND (ce.row_pk->>'person_id')::bigint = fm.person_id)) n_red
  FROM family_member fm WHERE fm.person_id IN (%s)", ids_sql))

# gift-ind-stubs: personer UDEN external_id-række men i familie med matchede —
# designdokets 'source-ejede stubs' (åbent spørgsmål: familie-ejerskab)
stubs <- q(sprintf("
  SELECT count(DISTINCT fm2.person_id) n
  FROM family_member fm1
  JOIN family_member fm2 ON fm2.family_id = fm1.family_id AND fm2.person_id <> fm1.person_id
  WHERE fm1.person_id IN (%s)
    AND NOT EXISTS (SELECT 1 FROM person_external_id e WHERE e.person_id = fm2.person_id)", ids_sql))

# familier med redaktionelt tilføjede medlemmer (replace-konflikt-klassen)
fam_red <- q(sprintf("
  SELECT count(DISTINCT fm.family_id) n
  FROM family_member fm
  WHERE fm.family_id IN (SELECT family_id FROM family_member WHERE person_id IN (%s))
    AND EXISTS (SELECT 1 FROM change_event ce WHERE ce.tabel='family_member'
          AND (ce.row_pk->>'family_id')::bigint = fm.family_id)", ids_sql))

# konflikt-klassen: source-ejede fact-rækker der EFTERFØLGENDE er redigeret
konflikt <- q(sprintf("
  SELECT f.subjekt_id person_id, f.id fact_id, f.faktatype, cs.operation
  FROM fact f
  JOIN change_event ce ON ce.tabel='fact' AND (ce.row_pk->>'id')::bigint = f.id
  JOIN change_set cs ON cs.id = ce.change_set_id
  WHERE f.subjekt_type='person' AND f.subjekt_id IN (%s)
  ORDER BY f.subjekt_id LIMIT 200", ids_sql))

# ---- rapport ----
u <- table(factor(udfald, levels = c("entydig","kun_register","tombstonet","ny","uden_record_key")))
linjer <- c(
  sprintf("# Replace dry-run — %s (%s)", udgave, Sys.Date()),
  "",
  "Read-only match-rapport (replay-designets trin 2). Intet skrevet.",
  "",
  "## Udfald pr. artefaktpost",
  sprintf("- artefaktposter i alt: %d", length(art)),
  sprintf("- **entydig** (person-id bevares): %d", u[["entydig"]]),
  sprintf("- **kun_register** (aktiv i register, ingen prod-person — HUL, kræver forklaring): %d", u[["kun_register"]]),
  sprintf("- **tombstonet** (genindsættes ALDRIG): %d", u[["tombstonet"]]),
  sprintf("- **ny** (ukendt record_key — mint + menneske): %d", u[["ny"]]),
  sprintf("- **uden_record_key**: %d", u[["uden_record_key"]]),
  sprintf("- **bortfaldne** (prod-nøgler uden artefaktpost): %d", length(bortfaldne_prod)),
  sprintf("- tombstonede nøgler stadig i prod (SKAL være 0): %d %s",
          length(tomb_i_prod), if (length(tomb_i_prod)) paste("⚠", paste(tomb_i_prod, collapse=", ")) else "✓"),
  "",
  "## Ejerskabsopdeling for de matchede personer",
  sprintf("Matchede personer: %d", length(match_ids)),
  "",
  sprintf("**Fakta:** %d i alt, heraf %d med redaktionelt spor (%d personer berørt)",
          fakta$n, fakta$n_red, fakta$pers_med_red),
  "",
  "**Narrativer pr. source** (source-ejet = denne udgaves; red-spor = patches der skal overleve):",
  paste(sprintf("- source %s: %d narrativer, %d med red-spor", narr$source_id, narr$n, narr$n_red), collapse = "\n"),
  "",
  "**Relationer pr. rolle** (samme_som/ikke_samme_som er ALTID redaktionelle):",
  paste(sprintf("- %s: %d, heraf %d med red-spor", rel$rolle, rel$n, rel$n_red), collapse = "\n"),
  "",
  sprintf("**Familie-kanter:** %d, heraf %d med red-spor", fm$n, fm$n_red),
  sprintf("**Familier med redaktionelt ændrede medlemslister** (replace-konflikt-klasse): %d", fam_red$n),
  sprintf("**Gift-ind-stubs** (uden external_id, i familie med matchede): %d", stubs$n),
  "",
  "## Konflikt-klassen: source-ejede fakta med efterfølgende redigering",
  "Disse rækker er BÅDE source-ejede og redigerede — replace skal bevare den",
  "redaktionelle konklusion oven på den nye påstand (evidensmodellens kerne):",
  if (nrow(konflikt)) paste(sprintf("- person %d, fact %d (%s): %s",
      konflikt$person_id, konflikt$fact_id, konflikt$faktatype, konflikt$operation), collapse = "\n")
  else "- ingen ✓",
  "")
writeLines(linjer, out_path)
cat(paste(linjer, collapse = "\n"))
cat(sprintf("\n\nRapport skrevet: %s\n", out_path))
