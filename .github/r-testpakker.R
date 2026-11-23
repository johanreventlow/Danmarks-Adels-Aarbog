# R-pakkerne til CI's `r · testthat` (ci.yml) og cache-opvarmningen (r-cache.yml). Begge workflows kører DENNE fil,
# og cache-nøglen indeholder dens hash: en ændret pakkeliste giver en ny nøgle i begge, uden manuel bump.
# Test-træet er DB-service-frit, men updater-testen sourcer et script, der indlæser RPostgres. Installér derfor alle
# pakker, som testtræet loader. Kun de manglende installeres, så et cache-hit ikke bygger duckdb igen (duckdb har
# ingen RSPM-binary og kompileres fra kilde: 5-40 min).
pkgs <- c("testthat", "jsonlite", "yaml", "DBI", "duckdb", "RPostgres", "stringdist", "stringi", "withr", "digest")
mangler <- setdiff(pkgs, rownames(installed.packages()))
cat("mangler:", if (length(mangler)) paste(mangler, collapse = ", ") else "ingen", "\n")
if (length(mangler)) install.packages(mangler)
stopifnot(all(pkgs %in% rownames(installed.packages())))
