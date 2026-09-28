#!/bin/zsh
# Deterministisk adgangstest for runner-gaten (#147 4.3a, Task 2 Step 1/1b).
#
# Kører INGEN model: den prøver at læse kendte stier gennem Seatbelt-profilen og
# kræver, at det spærrede nægtes og det nødvendige forbliver tilgængeligt.
# Exit 0 = gaten holder. Exit 1 = NO-GO; ingen modelkald må køre gennem profilen.
#
# VIGTIGT: kør fra call-dir. Ligger din cwd i det spærrede område, fejler alt —
# også det der burde virke — og testen ville melde falsk NO-GO.
set -u
PROFIL="${1:?brug: gate-access-test.sh <profil.sb> <call-dir> <repo>}"
CALLDIR="${2:?}"; REPO="${3:?}"
cd "$CALLDIR" || { echo "kan ikke skifte til call-dir"; exit 1; }
fejl=0
naegtet() {
  local navn="$1" sti="$2"
  if sandbox-exec -f "$PROFIL" /bin/ls "$sti" >/dev/null 2>&1; then
    printf '%-44s ** HUL — kunne læses **\n' "$navn"; fejl=1
  else
    printf '%-44s nægtet\n' "$navn"
  fi
}
tilgaengelig() {
  local navn="$1" sti="$2"
  if sandbox-exec -f "$PROFIL" /bin/ls "$sti" >/dev/null 2>&1; then
    printf '%-44s tilgængelig\n' "$navn"
  else
    printf '%-44s ** FEJL — burde være tilgængelig **\n' "$navn"; fejl=1
  fi
}
echo "— skal nægtes —"
naegtet      "work/ (PII)"             "$REPO/work"
naegtet      "work_1939_stamtavle/"    "$REPO/work_1939_stamtavle"
naegtet      "work_presens/"           "$REPO/work_presens"
naegtet      "~/.private/ (prod-dump)" "$HOME/.private"
naegtet      "hele repoet"             "$REPO"
naegtet      "hjemmemappen"            "$HOME"
# Undermapper testes SÆRSKILT: "ls $HOME fejler" beviser ikke, at hele træet er
# lukket — en åben understi ville ikke fremgå. ~/Library rummer nøgleringe, Mail,
# Beskeder og Safari-historik og var faktisk læsbar i et tidligere udkast.
naegtet      "~/Library/Keychains"     "$HOME/Library/Keychains"
naegtet      "~/Library/Application Support" "$HOME/Library/Application Support"
naegtet      "~/Documents"             "$HOME/Documents"
# Review 35, P1: PII ligger OGSÅ uden for hjemmemappen — lokale prod-kopier i
# PG-datamappen og scratch-mapper i /private/tmp og brugerens tempmappe.
naegtet      "/private/tmp"            "/private/tmp"
TMPD="$(getconf DARWIN_USER_TEMP_DIR)"
if [ -z "$TMPD" ]; then
  printf '%-44s ** FEJL — getconf gav ingen sti **\n' "brugerens tempmappe"; fejl=1
else
  naegtet    "brugerens tempmappe"     "$TMPD"
fi
naegtet      "/opt/homebrew/var (PG-data)" "/opt/homebrew/var"
naegtet      "/Users/Shared"           "/Users/Shared"
naegtet      "/Volumes"                "/Volumes"

# Lokal Postgres kører `trust`. PGHOSTADDR/PGSERVICE ville styre forbindelsen uden om -h,
# så socket-prøven kunne ende med at måle TCP; de fjernes. Tre forudsætninger før en
# nægtelse tæller: psql findes, PG svarer UDEN profil, og psql kan STARTE i profilen
# (ellers læses et nedbrud som "nægtet").
PSQL_ENV=(env -u PGHOSTADDR -u PGSERVICE -u PGSERVICEFILE -u PGHOST -u PGPORT -u PGDATABASE)
PSQL_BIN="$(command -v psql || true)"
pg_maalbar=0
if [ -z "$PSQL_BIN" ]; then
  printf '%-44s ikke målbar (psql mangler)\n' "Postgres"
elif ! "${PSQL_ENV[@]}" "$PSQL_BIN" -X -h /tmp -d postgres -Atc 'select 1' >/dev/null 2>&1; then
  printf '%-44s ikke målbar (PG svarer ikke uden profil)\n' "Postgres"
elif ! sandbox-exec -f "$PROFIL" "${PSQL_ENV[@]}" "$PSQL_BIN" --version >/dev/null 2>&1; then
  printf '%-44s ** FEJL — psql kan ikke starte i profilen; nægtelsen kan ikke måles **\n' "Postgres"; fejl=1
else
  pg_maalbar=1
fi
pg_naegtet() {
  local navn="$1" vaert="$2"
  [ "$pg_maalbar" -eq 1 ] || return 0
  if sandbox-exec -f "$PROFIL" "${PSQL_ENV[@]}" "$PSQL_BIN" -X -h "$vaert" -d postgres -Atc 'select 1' >/dev/null 2>&1; then
    printf '%-44s ** HUL — forbindelse lykkedes **\n' "$navn"; fejl=1
  else
    printf '%-44s nægtet\n' "$navn"
  fi
}
pg_naegtet   "Postgres via TCP (127.0.0.1)" "127.0.0.1"
pg_naegtet   "Postgres via TCP (::1)"  "::1"
pg_naegtet   "Postgres via socket (/tmp)" "/tmp"
# Profilens TCP-regel dækker kun loopback. Lytter PG bredere, er LAN-adressen en vej udenom.
if [ "$pg_maalbar" -eq 1 ]; then
  lytter="$("${PSQL_ENV[@]}" "$PSQL_BIN" -X -h /tmp -d postgres -Atc 'show listen_addresses' 2>/dev/null)"
  if [ "$lytter" = "localhost" ]; then
    printf '%-44s ok\n' "Postgres lytter kun på localhost"
  else
    printf '%-44s ** HUL — listen_addresses=%s **\n' "Postgres lytter kun på localhost" "${lytter:-<tom>}"; fejl=1
  fi
fi

# Skrivning uden for call-dir: kun NYE prøvefiler (aldrig en eksisterende fil); fjernes
# igen, hvis de (fejlagtigt) blev skrevet.
skriv_naegtet() {
  local navn="$1" mappe="$2" sti
  [ -d "$mappe" ] || { printf '%-44s (findes ikke)\n' "$navn"; return 0; }
  sti="$mappe/.daa-gate-write-probe-$$"
  if sandbox-exec -f "$PROFIL" /usr/bin/touch "$sti" >/dev/null 2>&1; then
    printf '%-44s ** HUL — kunne skrives **\n' "$navn"; fejl=1; /bin/rm -f "$sti"
  else
    printf '%-44s nægtet\n' "$navn"
  fi
}
CODEX_BIN_DIR="$(dirname "$(readlink -f "$(command -v codex)" 2>/dev/null)" 2>/dev/null || true)"
skriv_naegtet "skriv i hjemmemappen"   "$HOME"
skriv_naegtet "skriv i ~/.codex (config, AGENTS)" "$HOME/.codex"
skriv_naegtet "skriv ved codex-binæren" "${CODEX_BIN_DIR:-/nonexistent}"
skriv_naegtet "skriv i /opt/homebrew/bin" "/opt/homebrew/bin"
skriv_naegtet "skriv i /Users/Shared"  "/Users/Shared"
skriv_naegtet "skriv i /private/tmp"   "/private/tmp"
skriv_naegtet "skriv i brugerens tempmappe" "${TMPD:-/nonexistent}"

echo "— skal være tilgængelige —"
tilgaengelig "call-dir"                "$CALLDIR"
if sandbox-exec -f "$PROFIL" /usr/bin/touch "$CALLDIR/.skriveprove" >/dev/null 2>&1; then
  printf '%-44s tilgængelig\n' "skriv i call-dir"; /bin/rm -f "$CALLDIR/.skriveprove"
else
  printf '%-44s ** FEJL — burde være tilgængelig **\n' "skriv i call-dir"; fejl=1
fi
if [ $fejl -ne 0 ]; then
  echo "GATE_FAILED — NO-GO. Ingen modelkald må køre gennem denne profil."; exit 1
fi
echo "GATE_OK"
