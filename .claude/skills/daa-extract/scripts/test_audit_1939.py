import json

from audit_1939 import main


def test_audit_cli_outputs_only_summary(tmp_path, capsys):
    source = tmp_path / "calamari.txt"
    source.write_text("### PAGE 496 ###\n   1. Ceder † 1900.\n", encoding="utf-8")

    assert main(["--input", str(source)]) == 0

    summary = json.loads(capsys.readouterr().out)
    assert summary["posts"] == 1
    assert summary["with_lokal_id"] == 0
    assert "raw_text" not in summary
