# .claude/skills/daa-presens/scripts/presens_args.R
# DB-fri argumentparser til load_presens.R — unit-testbar i testthat
# (tests/testthat/test-load-presens-args.R). Bevidst uafhængig af daa-extract.
#
# Review 2026-10-27 (fund 1c-01): --reset (uvagtet TRUNCATE … CASCADE mod prod) er
# fjernet; --jeg-mener-det er obligatorisk, og ukendte flag afvises — et opfundet
# flag må aldrig ignoreres stille (jf. fase D1's --dryrun).
PRESENS_USAGE <- "brug: load_presens.R clean.json [udgave] --jeg-mener-det"

parse_load_presens_args <- function(argv) {
  flags <- argv[startsWith(argv, "--")]
  if ("--reset" %in% flags)
    stop("--reset er fjernet (review 2026-10-27, 1c-01): præsensloaderen tømmer aldrig model-tabellerne. ",
         "Start forfra ved restore af et dump.", call. = FALSE)
  unknown <- setdiff(flags, "--jeg-mener-det")
  if (length(unknown))
    stop("Ukendt argument: ", paste(unknown, collapse = ", "), "\n", PRESENS_USAGE, call. = FALSE)
  if (!"--jeg-mener-det" %in% flags)
    stop("--jeg-mener-det er obligatorisk: load_presens.R skriver til prod.\n", PRESENS_USAGE, call. = FALSE)
  positional <- argv[!startsWith(argv, "--")]
  if (!length(positional)) stop(PRESENS_USAGE, call. = FALSE)
  if (length(positional) > 2L)
    stop("for mange positionelle argumenter: ", paste(positional, collapse = " "), "\n", PRESENS_USAGE, call. = FALSE)
  list(path = positional[[1L]],
       udgave = if (length(positional) == 2L) positional[[2L]] else "DAA 2012-2014")
}
