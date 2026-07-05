# test_ordinals.py
from ordinals import ordinal_to_int

def test_known_ordinals():
    assert ordinal_to_int("Første") == 1
    assert ordinal_to_int("andet") == 2
    assert ordinal_to_int("Tolvte") == 12
    assert ordinal_to_int("  Nittende ") == 19

def test_unknown_returns_none():
    assert ordinal_to_int("Tyvende-og-noget") is None
    assert ordinal_to_int("") is None
    assert ordinal_to_int("42") is None
