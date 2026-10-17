#!/usr/bin/env bash
# Trin 5b 2b-i (spec §5.3, §10): arket ende til ende i en engangsbase. Printer kun antal og koder.
set -euo pipefail
db=${1:?database}
actor=11000000-0000-0000-0000-0000002b0501
root=$(mktemp -d); chmod 700 "$root"; trap 'rm -rf "$root"' EXIT
tool=.claude/skills/daa-extract/scripts/spouse_exception_sheet.py
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$db" "$@"; }
q -f tests/sql/fixtures/spouse-exception-2bi.sql >/dev/null
PGCLIENTENCODING=UTF8 env -u PGOPTIONS psql -X -Atq -v ON_ERROR_STOP=1 -v source=-21501 -d "$db" \
  -f .claude/skills/daa-extract/scripts/spouse_exception_rows.sql > "$root/rows.json"
python3 "$tool" render --rows "$root/rows.json" --out "$root/ark.txt" --private-root "$root" >/dev/null
# udfyld: S1 = S, S2 = A (undtagelse), S3 = S; O1 = B (ret), O2 = F (behold).
# S1 og O2 får en note med apostrof og backslash, som skal nå databasen tegn for tegn (Opus kode-review I1).
python3 - "$root/ark.txt" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read().splitlines()
s = [i for i, l in enumerate(t) if l.startswith("S ")]; o = [i for i, l in enumerate(t) if l.startswith("O ")]
note = "  # O'Brien \\ x"
t[s[0]] += note
t[s[1]] = re.sub(r": S$", ": A  # O'Brien", t[s[1]]); t[o[0]] = re.sub(r": [BF]$", ": B", t[o[0]]); t[o[1]] = re.sub(r": [BF]$", ": F", t[o[1]]) + note
open(p, "w", encoding="utf-8").write("\n".join(t) + "\n")
PY
rows_sha=$(shasum -a 256 "$root/rows.json" | cut -d' ' -f1); ark_sha=$(shasum -a 256 "$root/ark.txt" | cut -d' ' -f1)
python3 "$tool" sql --sheet "$root/ark.txt" --approved-sha256 "$ark_sha" --rows "$root/rows.json" \
  --expect-rows-sha256 "$rows_sha" --source -21501 --out "$root/apply.sql" --private-root "$root" >/dev/null
# scriptet skal selv låse strengsemantikken: kør det i en session, hvor backslash er escape-tegn
env PGOPTIONS='-c standard_conforming_strings=off' psql -X -q -v ON_ERROR_STOP=1 -d "$db" -v actor="$actor" -f "$root/apply.sql" >/dev/null 2>"$root/err0" || { grep -m1 ERROR "$root/err0"; exit 1; }
q -At <<SQL | grep -qx 't'
SELECT (SELECT count(*) FROM private.source_persona_identity i JOIN private.source_persona p ON p.id=i.source_persona_id
         WHERE p.source_id=-21501 AND i.decision_status='accepted' AND i.evidence->>'sheet_sha256'='$ark_sha')=2
   AND (SELECT count(*) FROM private.relation_classification_event e JOIN private.interpretation q ON q.id=e.interpretation_id
         WHERE q.source_id=-21501 AND e.classification='ordinal_beholdt' AND e.evidence->>'sheet_sha256'='$ark_sha')=1
   AND (SELECT count(*) FROM public.change_event WHERE tabel='family_member' AND op='UPDATE'
         AND change_set_id=(SELECT max(change_set_id) FROM public.change_event WHERE tabel='family_member'))=1
   AND (SELECT count(DISTINCT change_set_id) FROM public.change_event WHERE tabel='family_member')=1;
SQL
q -At <<SQL | grep -qx 't'
SELECT (SELECT i.evidence->>'note' FROM private.source_persona_identity i JOIN private.source_persona p ON p.id=i.source_persona_id
         WHERE p.source_id=-21501 AND i.evidence->>'sheet_sha256'='$ark_sha' AND (i.evidence->>'line')::int=1)
       = 'ark 2b-i '||left('$ark_sha',12)||' linje 1 — O''Brien '||chr(92)||' x'
   AND (SELECT e.evidence->>'note' FROM private.relation_classification_event e JOIN private.interpretation q ON q.id=e.interpretation_id
         WHERE q.source_id=-21501 AND e.classification='ordinal_beholdt' AND e.evidence->>'sheet_sha256'='$ark_sha')
       = 'O''Brien '||chr(92)||' x';
SQL
# genkoersel (Review Focus 1): samme script fejler lukket og skriver 0
before=$(q -At -c "SELECT count(*) FROM private.source_persona_identity_event")
if q -v actor="$actor" -f "$root/apply.sql" >/dev/null 2>"$root/err"; then echo "FEJL: genkoersel godtaget"; exit 1; fi
grep -q SPOUSE_SHEET_ROWS_STALE "$root/err"
[ "$(q -At -c "SELECT count(*) FROM private.source_persona_identity_event")" = "$before" ]
# koe_imellem (Review Focus 3): nyt udtræk, en persona afgøres i køen før anvendelsen ⇒ ROWS_STALE, 0 skrivninger
PGCLIENTENCODING=UTF8 env -u PGOPTIONS psql -X -Atq -v ON_ERROR_STOP=1 -v source=-21501 -d "$db" \
  -f .claude/skills/daa-extract/scripts/spouse_exception_rows.sql > "$root/rows2.json"
rm -f "$root/ark2.txt" "$root/apply2.sql"
python3 "$tool" render --rows "$root/rows2.json" --out "$root/ark2.txt" --private-root "$root" >/dev/null
rows2_sha=$(shasum -a 256 "$root/rows2.json" | cut -d' ' -f1); ark2_sha=$(shasum -a 256 "$root/ark2.txt" | cut -d' ' -f1)
python3 "$tool" sql --sheet "$root/ark2.txt" --approved-sha256 "$ark2_sha" --rows "$root/rows2.json" \
  --expect-rows-sha256 "$rows2_sha" --source -21501 --out "$root/apply2.sql" --private-root "$root" >/dev/null
# personaen findes som ejer (private); afgørelsen sker som redaktør gennem webkøens RPC
pid=$(q -At -c "SELECT p.id FROM private.source_persona p LEFT JOIN private.source_persona_identity i ON i.source_persona_id=p.id WHERE p.source_id=-21501 AND i.source_persona_id IS NULL AND EXISTS (SELECT 1 FROM private.source_persona_mention m WHERE m.persona_id=p.id AND m.mention_role='spouse') LIMIT 1")
q -c "BEGIN" -c "SELECT set_config('request.jwt.claim.sub','$actor',true)" -c "SET LOCAL ROLE authenticated" \
  -c "SELECT red_afgoer_source_persona('$pid'::uuid,0,'unresolved',NULL,'koe imellem','{}')" -c "COMMIT" >/dev/null
before=$(q -At -c "SELECT count(*) FROM private.source_persona_identity_event")
if q -v actor="$actor" -f "$root/apply2.sql" >/dev/null 2>"$root/err2"; then echo "FEJL: forældet ark godtaget"; exit 1; fi
grep -q SPOUSE_SHEET_ROWS_STALE "$root/err2"
[ "$(q -At -c "SELECT count(*) FROM private.source_persona_identity_event")" = "$before" ]
echo SHEET_E2E_OK
