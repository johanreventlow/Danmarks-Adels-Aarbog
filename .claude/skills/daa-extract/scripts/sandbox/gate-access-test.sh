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
echo "— skal være tilgængelige —"
tilgaengelig "call-dir"                "$CALLDIR"
if [ $fejl -ne 0 ]; then
  echo "GATE_FAILED — NO-GO. Ingen modelkald må køre gennem denne profil."; exit 1
fi
echo "GATE_OK"
