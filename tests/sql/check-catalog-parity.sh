#!/usr/bin/env bash
# Sammenligner to udtræk fra tests/sql/inspect-catalog-parity.sql (kodereview 36, D1).
# Brug: check-catalog-parity.sh <udtræk-a> <udtræk-b> [undtagelsesfil]
# Fejler ved enhver forskel, hvis nøgle (art|nøgle) ikke står i undtagelsesfilen, og ved undtagelser, der ikke
# bruges. Uden undtagelsesfil skal udtrækkene være ens.
set -euo pipefail
a=$1; b=$2; undt=${3:-/dev/null}
export LC_ALL=C
for f in "$a" "$b"; do
  [ -s "$f" ] || { echo "KATALOGPARITET: $f er tomt" >&2; exit 1; }
  n=$(grep -c '^fn|' "$f" || true)
  [ "$n" -ge 100 ] || { echo "KATALOGPARITET: $f har kun $n funktioner — udtrækket ser ufuldstændigt ud" >&2; exit 1; }
done
tmp=$(mktemp -d); trap 'rm -r "$tmp"' EXIT
sort "$a" > "$tmp/a"; sort "$b" > "$tmp/b"
comm -3 "$tmp/a" "$tmp/b" | sed 's/^\t//' > "$tmp/forskel"
grep -v '^[[:space:]]*\(#\|$\)' "$undt" | sort -u > "$tmp/undt" || true
cut -d'|' -f1,2 "$tmp/forskel" | sort -u > "$tmp/noegler"
uforklaret=$(comm -23 "$tmp/noegler" "$tmp/undt")
ubrugt=$(comm -13 "$tmp/noegler" "$tmp/undt")
status=0
if [ -n "$uforklaret" ]; then
  echo "KATALOGPARITET: forskelle mellem $(basename "$a") og $(basename "$b"):" >&2
  while IFS= read -r k; do
    grep -F -- "$k|" "$tmp/a" | sed "s/^/  kun $(basename "$a"): /" >&2 || true
    grep -F -- "$k|" "$tmp/b" | sed "s/^/  kun $(basename "$b"): /" >&2 || true
  done <<< "$uforklaret"
  status=1
fi
if [ -n "$ubrugt" ]; then
  echo "KATALOGPARITET: undtagelser uden forskel (fjern dem fra $(basename "$undt")):" >&2
  sed 's/^/  /' <<< "$ubrugt" >&2
  status=1
fi
[ "$status" -eq 0 ] && echo "KATALOGPARITET OK: $(wc -l < "$tmp/a") / $(wc -l < "$tmp/b") objekter, $(wc -l < "$tmp/undt" | tr -d ' ') undtagelser"
exit "$status"
