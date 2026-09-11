#!/bin/zsh
# Deterministisk adgangstest for runner-gaten (#147 4.3a, Task 2 Step 1).
# Kører INGEN model: den prøver at læse kendte stier gennem Seatbelt-profilen og
# kræver, at de spærrede nægtes og de nødvendige forbliver tilgængelige.
# Exit 0 = gaten holder. Exit 1 = NO-GO; dagsværket standser med et navngivet fund.
set -u
PROFIL="${1:?brug: gate-access-test.sh <profil.sb> <call-dir> <repo>}"
CALLDIR="${2:?}"; REPO="${3:?}"
fejl=0
naegtet() {
  local navn="$1" sti="$2"
  if sandbox-exec -f "$PROFIL" /bin/ls "$sti" >/dev/null 2>&1; then
    printf '%-42s ** HUL — kunne læses **\n' "$navn"; fejl=1
  else
    printf '%-42s nægtet\n' "$navn"
  fi
}
tilgaengelig() {
  local navn="$1" sti="$2"
  if sandbox-exec -f "$PROFIL" /bin/ls "$sti" >/dev/null 2>&1; then
    printf '%-42s tilgængelig\n' "$navn"
  else
    printf '%-42s ** FEJL — burde være tilgængelig **\n' "$navn"; fejl=1
  fi
}
echo "— skal nægtes —"
naegtet      "work/"                  "$REPO/work"
naegtet      "work_1939_stamtavle/"   "$REPO/work_1939_stamtavle"
naegtet      "work_presens/"          "$REPO/work_presens"
naegtet      "~/.private/"            "$HOME/.private"
echo "— skal være tilgængelige —"
tilgaengelig "call-dir"               "$CALLDIR"
if [ $fejl -ne 0 ]; then
  echo "GATE_FAILED — NO-GO. Ingen modelkald må køre gennem denne profil."; exit 1
fi
echo "GATE_OK"
