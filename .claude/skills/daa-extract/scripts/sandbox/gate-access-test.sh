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
naegtet      "brugerens tempmappe"     "$(getconf DARWIN_USER_TEMP_DIR)"
naegtet      "/opt/homebrew/var (PG-data)" "/opt/homebrew/var"
naegtet      "/Users/Shared"           "/Users/Shared"
naegtet      "/Volumes"                "/Volumes"

# Lokal Postgres kører `trust`. Forsøget skal FØRST lykkes uden profilen — ellers
# måler en nægtelse indenfor ingenting (PG nede, psql mangler) og ville melde falsk OK.
pg_naegtet() {
  local navn="$1" vaert="$2" psql_bin
  psql_bin="$(command -v psql)" || { printf '%-44s ikke målbar (psql mangler)\n' "$navn"; return; }
  if ! "$psql_bin" -X -h "$vaert" -d postgres -Atc 'select 1' >/dev/null 2>&1; then
    printf '%-44s ikke målbar (PG svarer ikke uden profil)\n' "$navn"; return
  fi
  if sandbox-exec -f "$PROFIL" "$psql_bin" -X -h "$vaert" -d postgres -Atc 'select 1' >/dev/null 2>&1; then
    printf '%-44s ** HUL — forbindelse lykkedes **\n' "$navn"; fejl=1
  else
    printf '%-44s nægtet\n' "$navn"
  fi
}
pg_naegtet   "Postgres via TCP (127.0.0.1)" "127.0.0.1"
pg_naegtet   "Postgres via TCP (::1)"  "::1"
pg_naegtet   "Postgres via socket (/tmp)" "/tmp"
# Profilens TCP-regel dækker kun loopback. Lytter PG bredere, er LAN-adressen en vej udenom.
if command -v psql >/dev/null 2>&1; then
  lytter="$(psql -X -h /tmp -d postgres -Atc 'show listen_addresses' 2>/dev/null)"
  if [ -n "$lytter" ] && [ "$lytter" != "localhost" ]; then
    printf '%-44s ** HUL — listen_addresses=%s **\n' "Postgres lytter kun på localhost" "$lytter"; fejl=1
  else
    printf '%-44s ok\n' "Postgres lytter kun på localhost"
  fi
fi

# Skrivning uden for call-dir: prøvefilen fjernes igen, hvis den (fejlagtigt) blev skrevet.
skriv_naegtet() {
  local navn="$1" sti="$2"
  if sandbox-exec -f "$PROFIL" /usr/bin/touch "$sti" >/dev/null 2>&1; then
    printf '%-44s ** HUL — kunne skrives **\n' "$navn"; fejl=1; /bin/rm -f "$sti"
  else
    printf '%-44s nægtet\n' "$navn"
  fi
}
skriv_naegtet "skriv i hjemmemappen"   "$HOME/.daa-gate-write-probe-$$"
skriv_naegtet "skriv i /private/tmp"   "/private/tmp/daa-gate-write-probe-$$"

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
