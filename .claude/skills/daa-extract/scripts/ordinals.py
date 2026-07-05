"""Dansk ordinal (ord) -> heltal. Dækker slægtled-spændet i DAA + margin.

Bruges af segment.py til at parse 'Første (tolvte) slægtled'-headere. Deterministisk;
udvid tabellen hvis en ny udgave bruger højere slægtled end 'toogtyvende'.
"""
_ORDINALS = {
    "første": 1, "andet": 2, "tredje": 3, "fjerde": 4, "femte": 5, "sjette": 6,
    "syvende": 7, "ottende": 8, "niende": 9, "tiende": 10, "ellevte": 11, "tolvte": 12,
    "trettende": 13, "fjortende": 14, "femtende": 15, "sekstende": 16, "syttende": 17,
    "attende": 18, "nittende": 19, "tyvende": 20, "enogtyvende": 21, "toogtyvende": 22,
}

def ordinal_to_int(word):
    if not word:
        return None
    return _ORDINALS.get(word.strip().lower())
