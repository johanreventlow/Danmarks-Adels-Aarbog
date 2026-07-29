# Identitetsregister

Ét blivende id pr. trykt bogpost, så redaktionelt arbejde overlever at bogen
læses igen.

**Reglen: identitet udstedes, den udledes ikke.** Alle tidligere forsøg brød på
samme måde — de brugte noget *beregnet* (et løbenummer, en optælling, en
position i vores egen segmentering), og alt beregnet kan falde anderledes ud
næste gang beregningen kører. Se `docs/decisions.md` →
"1939-posternes permanente løbenummer".

## Filerne

| Fil | Indhold |
|---|---|
| `1939.json` | DAA 1939 — 515 aktive + 24 tombstones |

## Lokatoren

Posten genfindes på `(udgave, side, lokal_id)`:

- `side` — den trykte sides nummer, fra citationen
- `lokal_id` — bogens egen strukturelle sti (linje/slægtled/gruppe), fx `A.V.1`

Begge er læst **af bogen**. Målt på DAA 1939: `lokal_id` alene giver 425
distinkte værdier for 515 poster — ikke nok. Sammen med `side` er alle 515
entydige.

Lokatoren behøver ikke være perfekt stabil. Den skal være god nok til at
**foreslå** et match; tvetydighed er et lovligt udfald der kræver en menneskelig
afgørelse. Det er forskellen på en nøgle og et gæt.

## Tombstones

En fjernet post beholder sit id med `status: "tombstone"` og en begrundelse.
Id'et genbruges **aldrig**, og posten kan ikke genopstå ved en genindlæsning.

Registeret rydder aldrig selv op: forsvinder en post fra udtrækket, meldes den
som *bortfalden* — men tombstones ikke automatisk. Bortfald kan lige så vel
betyde en segmenteringsfejl som en rigtig sletning.

## PII

Filen indeholder **kun** id, udgave, side, strukturel sti og status — ingen
navne eller datoer. Derfor kan den versionsstyres, i modsætning til
artefakterne.

⚠ `lokal_id` kan i sjældne tilfælde indeholde et fornavn (72 af 539 poster i
1939 har et navne-lignende ord, fx `Uplac.6`, og ét bærer `Bertram`). Verificeret
2026-07-29: **ingen af de 7 levende 1939-personers `lokal_id` indeholder et
navn.** Kontrollen skal **gentages** før en ny slægt tilføjes — den er ikke
strukturelt garanteret.

## Brug

```python
from identitetsregister import Register, mint, reconcile

reg = Register.from_json(json.load(open("data/identitet/1939.json")))
res = reconcile(reg, nye_poster, udgave="1939")
# res.entydige   → genbrug id
# res.tvetydige  → STOP, kræver menneskelig afgørelse
# res.nye        → mint nyt id
# res.bortfaldne → meldes, tombstones IKKE automatisk
```
