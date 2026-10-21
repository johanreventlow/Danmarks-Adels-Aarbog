"""Enhedstests for transfer_ddl.py (5a+5b-overførslen, plan A Task 2)."""
import os
import subprocess
import sys

import pytest

sys.path.insert(0, os.path.dirname(__file__))
import transfer_ddl as t  # noqa: E402

E = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"


def cat(*rows):
    return [f"P|{r}" if r.count("|") == 3 else r for r in rows]


def write(tmp_path, name, text):
    p = tmp_path / name
    p.write_text(text, encoding="utf-8")
    return p


# ---- prefix -------------------------------------------------------------------------------------

def test_prefix_cuts_at_unique_commit(tmp_path):
    m = write(tmp_path, "m.sql", "x;\nBEGIN;\ny;\nCOMMIT;\nz;\n")
    out = tmp_path / "o.sql"
    n, _ = t.prefix(m, "after-153-commit", out)
    assert n == 4 and out.read_text() == "x;\nBEGIN;\ny;\nCOMMIT;\n"


def test_prefix_marker_must_be_unique(tmp_path):
    m = write(tmp_path, "m.sql", "BEGIN;\nCOMMIT;\nBEGIN;\nCOMMIT;\n")
    with pytest.raises(SystemExit, match="PREFIX_MARKER"):
        t.prefix(m, "after-153-commit", tmp_path / "o.sql")


def test_prefix_in_5a_cutover(tmp_path):
    m = write(tmp_path, "m.sql", "a;\n-- BEGIN 5a-cutover\nb;\n-- END 5a-cutover\nc;\n")
    n, _ = t.prefix(m, "in-5a-cutover", tmp_path / "o.sql")
    assert n == 4


def test_prefix_function_window_is_line_before_revoke(tmp_path):
    rev = "REVOKE ALL ON FUNCTION red_identity_candidate_input(bigint,jsonb) FROM PUBLIC,anon,authenticated;"
    m = write(tmp_path, "m.sql", f"a;\nCREATE FUNCTION x() ...\nEND $$;\n{rev}\nGRANT x;\n")
    out = tmp_path / "o.sql"
    n, _ = t.prefix(m, "in-function-window", out)
    assert n == 3 and out.read_text().endswith("END $$;\n")


def test_prefix_before_rls_is_whole_file(tmp_path):
    m = write(tmp_path, "m.sql", "a;\nb;\n")
    n, _ = t.prefix(m, "before-rls", tmp_path / "o.sql")
    assert n == 2


# ---- removal-sql --------------------------------------------------------------------------------

def test_removal_new_table_drops_once_with_cascade():
    before = cat("r|private.old|m|0")
    after = cat("r|private.old|m|0", "r|private.ny|m|0", "c|private.ny.a|m|0", "k|private.ny.fk|m|0",
                "i|private.ny.ny_pkey|m|0")
    sql, st = t.removal_sql(before, after)
    assert sql.count("DROP") == 1 and "DROP TABLE IF EXISTS private.ny CASCADE;" in sql
    assert st["skipped_existing"] == 0


def test_removal_replaced_function_is_kept():
    sql, st = t.removal_sql(cat("f|private.g(integer)|a|0"), cat("f|private.g(integer)|b|0"))
    assert "DROP" not in sql and st["drop"] == 0


def test_removal_new_overload_dropped():
    sql, _ = t.removal_sql(cat("f|public.h(uuid)|a|0"), cat("f|public.h(uuid)|a|0", "f|public.h(uuid,text)|b|0"))
    assert "DROP ROUTINE IF EXISTS public.h(uuid,text) CASCADE;" in sql and "public.h(uuid) " not in sql


def test_removal_column_on_existing_table_counted_not_dropped():
    sql, st = t.removal_sql(cat("r|public.person|m|0"), cat("r|public.person|m|0", "c|public.person.ny_kol|m|0"))
    assert "DROP" not in sql and st["skipped_existing"] == 1


def test_removal_trigger_on_existing_table_with_new_function():
    before = cat("r|public.person|m|0")
    after = cat("r|public.person|m|0", "f|private.trg_fn()|m|0", "t|public.person.trg|m|0")
    sql, st = t.removal_sql(before, after)
    assert "DROP ROUTINE IF EXISTS private.trg_fn() CASCADE;" in sql and st["skipped_existing"] == 1


def test_removal_policy_name_with_spaces_on_existing_table():
    sql, st = t.removal_sql(cat("r|public.person|m|0"), cat("r|public.person|m|0", "p|public.person.Læs alle.x|m|0"))
    assert "DROP" not in sql and st["skipped_existing"] == 1


def test_removal_counts_removed_by_ddl():
    _, st = t.removal_sql(cat("f|public.gammel(uuid)|a|0", "k|private.x.c|a|0"), cat())
    assert st["removed_by_ddl"] == 2


def test_removal_ignores_local_part():
    sql, st = t.removal_sql([], ["L|n|auth|m|0", "L|p|storage.objects.x|m|0"])
    assert "DROP" not in sql and st == {"drop": 0, "skipped_existing": 0, "removed_by_ddl": 0}


def test_removal_skips_owned_sequence():
    sql, st = t.removal_sql(cat("r|public.family|m|0"), cat("r|public.family|m|0", "s|public.family_id_seq|m|1"))
    assert "DROP" not in sql and st["skipped_existing"] == 1


def test_removal_order_views_functions_tables():
    after = cat("y|private.t_enum|m|0", "s|private.ny_seq|m|0", "r|private.ny|m|0", "f|private.f()|m|0",
                "v|private.ny_v|m|0", "m|private.ny_mv|m|0", "o|private.ny_dom|m|0")
    sql, _ = t.removal_sql([], after)
    kinds = [l.split(" IF EXISTS")[0] for l in sql.splitlines() if l.startswith("DROP")]
    assert kinds == ["DROP VIEW", "DROP MATERIALIZED VIEW", "DROP ROUTINE", "DROP TABLE", "DROP SEQUENCE",
                     "DROP TYPE", "DROP DOMAIN"]


def test_removal_accepts_real_regprocedures():
    sig = 'public.x(timestamp with time zone,text[],"char",character varying,extensions.citext)'
    sql, _ = t.removal_sql([], cat(f"f|{sig}|m|0"))
    assert f"DROP ROUTINE IF EXISTS {sig} CASCADE;" in sql


def test_removal_rejects_odd_identity():
    for bad in ("r|private.x; DROP|m|0", "f|public.g(int); DROP x)|m|0", "r|Private.X|m|0"):
        with pytest.raises(SystemExit, match="REMOVAL_IDENTITY"):
            t.removal_sql([], cat(bad))


def test_removal_wrapped_in_one_transaction():
    sql, _ = t.removal_sql([], cat("r|private.ny|m|0"))
    lines = sql.strip().splitlines()
    assert lines[0] == "BEGIN;" and lines[-1] == "COMMIT;"


# ---- data-delta ---------------------------------------------------------------------------------

def test_data_delta_allowed_change_ok():
    st = t.data_delta(["private.r=a", "public.p=b"], ["private.r=c", "public.p=b"], {"private.r"})
    assert st == {"changed": 1, "new": 0}


def test_data_delta_unlisted_change_fails():
    with pytest.raises(SystemExit, match="DATA_DELTA_UNEXPECTED"):
        t.data_delta(["public.p=b"], ["public.p=c"], set())


def test_data_delta_new_nonempty_table_fails():
    assert t.data_delta([], [f"private.ny={E}"], set()) == {"changed": 0, "new": 1}
    with pytest.raises(SystemExit, match="DATA_DELTA_UNEXPECTED"):
        t.data_delta([], ["private.ny=abc"], set())


def test_data_delta_dropped_table_must_be_allowed():
    with pytest.raises(SystemExit, match="DATA_DELTA_UNEXPECTED"):
        t.data_delta(["private.gammel=a"], [], set())
    assert t.data_delta(["private.gammel=a"], [], {"private.gammel"})["changed"] == 1


def test_cli_removal_prints_marker(tmp_path):
    b = write(tmp_path, "b.txt", "")
    a = write(tmp_path, "a.txt", "P|r|private.ny|m|0\n")
    out = tmp_path / "drop.sql"
    r = subprocess.run([sys.executable, "-I", os.path.join(os.path.dirname(__file__), "transfer_ddl.py"), "removal-sql",
                        "--before", str(b), "--after", str(a), "--out", str(out)], capture_output=True, text=True)
    assert r.returncode == 0 and r.stdout.startswith("REMOVAL_OK drop=1 skipped_existing=0 removed_by_ddl=0 sha256=")
