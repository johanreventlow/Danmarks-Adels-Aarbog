#!/usr/bin/env bash
# Trin 6d-3 Task 6 trin 4: forælderarkets rækkefil v2 (kontekst) ende til ende i en engangsbase — rækkefil → asserts på
# kontekstfelterne → ark + HTML. Opdigtede personer; printer kun koder.
set -euo pipefail
db=${1:?database}
root=$(mktemp -d); chmod 700 "$root"; trap 'rm -rf "$root"' EXIT
sd=.claude/skills/daa-extract/scripts
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$db" "$@"; }
q -f tests/sql/fixtures/relation-parent-e2e.sql >/dev/null
rows() { PGCLIENTENCODING=UTF8 env -u PGOPTIONS psql -X -Atq -v ON_ERROR_STOP=1 -v source=-26101 -d "$db" -f $sd/relation_parent_rows.sql; }
rows > "$root/rows.json"; rows > "$root/rows2.json"
# Deterministisk projektion: to kørsler er byte-ens; filen er ::text + præcis én LF.
cmp -s "$root/rows.json" "$root/rows2.json"
[ "$(tail -c1 "$root/rows.json" | xxd -p)" = "0a" ] && [ "$(wc -l < "$root/rows.json" | tr -d ' ')" = "1" ]
python3 - "$root/rows.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert d["contract"] == "relation-parent-sheet-input-v2" and d["source_id"] == -26101 and len(d["rows"]) == 2
a = next(r for r in d["rows"] if r["record_key"] == "V-2")
b = next(r for r in d["rows"] if r["record_key"] == "V-3")
assert a["post_text"] == "Ib Delta, f. 1830. Søn af Ole <Delta> & Eva Delta."
assert a["clauses"] == [{"text": "Søn af Ole <Delta> & Eva Delta.", "page_from": 10, "page_to": 10,
                         "post_char_from": 19, "post_char_to": 50}]
assert a["post_text"][19:50] == a["clauses"][0]["text"]
assert a["principal"] == {"person_id": -26112, "navn": "Ib Delta", "foedt": "1830", "doed": "1900", "levende": False}
assert len(a["candidates"]) == 1
c = a["candidates"][0]
assert sorted(p["navn"] for p in c["partners"]) == ["Eva Delta", "Ole Delta"]
assert [p["navn"] for p in c["children"]] == ["Ib Delta", "Ida Delta"]   # fødselsår stigende
assert {p["person_id"]: (p["foedt"], p["doed"]) for p in c["partners"]}[-26111] == ("1801", "1870")
assert c["counterpart_person_id"] == -26111 and isinstance(c["family_id"], int)
assert b["candidates"] == [] and b["post_text"] == "Kai Delta. Søn af en ukendt." and b["principal"]["navn"] == "Kai Delta"
PY
keys=$(python3 -c "import json,sys; print('\n'.join(r['interpretation_key'] for r in json.load(open('$root/rows.json'))['rows']))")
printf '%s\n' "$keys" > "$root/keys.txt"
[ "$(python3 $sd/relation_parent_sheet.py render --rows "$root/rows.json" --out "$root/ark.txt" --html "$root/ark.html" \
     --interpretation-keys "$root/keys.txt" --private-root "$root")" = "ARK_OK rows=2 entydig=1 uden_entydig=1" ]
grep -q '^#     barn: Ib Delta (1830–1900) · post V-2$' "$root/ark.txt"
grep -q 'rows_sha256: '"$(python3 -c "import hashlib,json,sys; sys.path.insert(0,'$sd'); import relation_parent_sheet as p; print(p.selected_rows_sha256(json.load(open('$root/rows.json'))))")" "$root/ark.txt"
grep -q '<mark>Søn af Ole &lt;Delta&gt; &amp; Eva Delta.</mark>' "$root/ark.html"
grep -q 'Ole Delta (1801–1870)' "$root/ark.html"
echo PARENT_ROWS_V2_OK
