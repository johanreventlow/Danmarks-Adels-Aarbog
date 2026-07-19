#!/usr/bin/env bash
# Deterministisk tekstudtræk fra DAA-PDF (born-digital -> rent tekstlag).
# Brug: extract_text.sh <pdf> <første-side> <sidste-side> > raw.txt
#
# Fjerner sidehoved/footer-støj men BEVARER en sidemarkør pr. side
# (### PAGE n ###) så segmentering kan udlede sidetal til citationer.
set -euo pipefail

pdf="${1:?angiv PDF-sti}"
first="${2:?angiv første side}"
last="${3:?angiv sidste side}"

command -v pdftotext >/dev/null || { echo "pdftotext mangler (brew install poppler)" >&2; exit 1; }

for ((p=first; p<=last; p++)); do
  printf '### PAGE %d ###\n' "$p"
  pdftotext -f "$p" -l "$p" -layout "$pdf" - 2>/dev/null \
    | grep -vE '\.indd|DAA 2018-20_saer|^[[:space:]]*[0-9]+[[:space:]]*$' \
    | grep -vE 'von Reventlow [-–] i linje|^[[:space:]]*Reventlow\.[[:space:]]*$'
done
