# .claude/skills/daa-presens/scripts/presens_args.R
# DB-fri argumentparser til load_presens.R — unit-testbar i testthat
# (tests/testthat/test-load-presens-args.R). Bevidst uafhængig af daa-extract.
#
# Review 2026-10-27 (fund 1c-01): --reset (uvagtet TRUNCATE … CASCADE mod prod) er
# fjernet; --jeg-mener-det er obligatorisk, og ukendte flag afvises — et opfundet
# flag må aldrig ignoreres stille (jf. fase D1's --dryrun).
#
# Review 37, E6: --dry-run kører hele loaden i én transaktion og ruller den tilbage
# (ingen sekvens-sync). Præcis ét af --dry-run og --jeg-mener-det skal angives.
PRESENS_USAGE <- "brug: load_presens.R clean.json [udgave] (--dry-run | --jeg-mener-det)"

parse_load_presens_args <- function(argv) {
  flags <- argv[startsWith(argv, "--")]
  if ("--reset" %in% flags)
    stop("--reset er fjernet (review 2026-10-27, 1c-01): præsensloaderen tømmer aldrig model-tabellerne. ",
         "Start forfra ved restore af et dump.", call. = FALSE)
  unknown <- setdiff(flags, c("--jeg-mener-det", "--dry-run"))
  if (length(unknown))
    stop("Ukendt argument: ", paste(unknown, collapse = ", "), "\n", PRESENS_USAGE, call. = FALSE)
  dry_run <- "--dry-run" %in% flags
  skriv <- "--jeg-mener-det" %in% flags
  if (dry_run && skriv)
    stop("--dry-run og --jeg-mener-det udelukker hinanden.\n", PRESENS_USAGE, call. = FALSE)
  if (!dry_run && !skriv)
    stop("--jeg-mener-det er obligatorisk: load_presens.R skriver til prod (ellers --dry-run).\n",
         PRESENS_USAGE, call. = FALSE)
  positional <- argv[!startsWith(argv, "--")]
  if (!length(positional)) stop(PRESENS_USAGE, call. = FALSE)
  if (length(positional) > 2L)
    stop("for mange positionelle argumenter: ", paste(positional, collapse = " "), "\n", PRESENS_USAGE, call. = FALSE)
  list(path = positional[[1L]],
       udgave = if (length(positional) == 2L) positional[[2L]] else "DAA 2012-2014",
       dry_run = dry_run)
}
