# Færdigbevis: trin 6e-1 i prod — læserfladen viser valgt udgave forrest, den anden som note (2026-11-12)

Spec: `docs/superpowers/specs/2026-11-12-trin6e-laeserflade-design.md` (§8, 6e-1-delen). Plan:
`docs/superpowers/plans/2026-11-12-trin6e1-laeserflade-klient.md` Task 8. Måling: `laeserflade-6e1-maaling.md`.
Kun udfald, antal og id'er; Conrad (392) er spec'ens offentlige eksempel.

## Forløb

| Trin | Resultat |
|---|---|
| PR | #318 (draft → merget af projektejeren 2026-11-12, merge `c0ec6bda`, head `72a80dbc`) |
| Deploy | Vercel: ny bundle i prod ~60 s efter merge (`index-DYLVQgYN.js`; indeholder »Ingen biografi fra denne udgave«) |
| Data | Ingen DDL og ingen dataskrivning fra koden. Projektejeren rettede i Redaktion (prod): 392's navnekonklusion tilbage til redaktørens »Conrad« (navnet øverst = »Conrad Reventlow«), 255's konklusion til importens »Conrad de Reventlow«, og 255's nu overflødige redaktørpåstand 4699 (»Conrad«) slettet |
| Lokalt node-job (head) | core 526 · feed 129 · web 998 · web-build ok · mobil tsc ok · mobil jest 452 · e2e person-facts 4 |

## Browsertjek som anon mod `danmarks-adels-aarbog.vercel.app` (headless Chromium)

| Side | Udfald |
|---|---|
| Conrad `/person/392` (2018-20) | Navnet øverst »Conrad Reventlow«, uden markering. Fakta: **én** navnelinje »Conrad de Reventlow« med kilderne DAA 2018-20 (import, III-58) og »DAA 2018-20, s. 201-202 · V-1« og noten »DAA 1939 skriver: Conrad Reventlow«; ingen »Andre udsagn«. Født, titel (greve, III-58 + V-1 lagt sammen) og død med »✓ også i DAA 1939«. Ingen ledende `*`/`†`. |
| Conrad, klik »DAA 1939« | 1939's fakta med »DAA 1939, s. 541«; »✓ også i DAA 2018-20« ved født/titel/død; »DAA 2018-20 skriver: Conrad de Reventlow«; »Kun i DAA 2018-20« (titler, adling, begravet); »Tidligere udgave« vist |
| Ægtefælle `/person/745` (ingen biografi i nogen udgave) | Udgaveskift »DAA 2018-20 / DAA 1939« uden biografitekst og uden »Ingen biografi«; »DAA 1939 skriver: …« og »✓ også i DAA 1939« |
| Kun 1939 `/person/927` | Ingen vælger; 1939's fakta med »DAA 1939, s. N« |
| Uenighed `/person/304` | 2 × »DAA 1939 skriver: …« (bl.a. fødslen), 2 × »✓« |
| Placeret, sammenfoldet `/person/149` | Chips »DAA 2018-20 · II-20« og »DAA 1939«; »DAA 1939 skriver: …« på navn, født, død, begravet (bøgerne afviger på sted/form); »Kun i DAA 1939« med 1939's titler |
| Alle seks sider (før og efter klik) | **0** forekomster af `record-<uuid>` og `legacy-source:` i DOM'en |

## Spec §8 (6e-1-delen)

- Conrad åbner på V-1 med 2018-20's fakta; navn, født, titel og død én gang hver; »✓ også i DAA 1939« ved
  født/titel/død; 1939-visningen viser »DAA 1939, s. 541« og 2018-20 som note. **Opfyldt** (efter projektejerens
  dataretning på 255/392).
- En 1939-person uden 2018-20-modpart: ingen vælger. **Opfyldt** (927).
- En reel uenighed viser »… skriver: …«. **Opfyldt** (304, 149).
- Ingen `record-`/`legacy-source:` i DOM'en. **Opfyldt** (seks sider).
- Stikprøven uden falske par: projektejeren dømte 46 + 14 par korrekte → `SLUKKET_ENIGHED` tom.

## Ikke gjort / til 6e-2

- Personsidens kald er ikke tidsmålt (headless-tiderne inkl. `networkidle` og model-indlæsning siger intet). Det
  eneste nye kald er ét anon-opslag i `citation`, kun når en valgt påstand mangler kilde, og parallelt med resten;
  biografikaldet måles i 6e-2 (spec §8).
- Hovedets linjer følger ikke vælgeren; »Optræder i Aarbogen som … linje 1939 (1939-275)« og »ukendt linje« for
  ægtefæller er legacy — 6e-2 (§5.7).
- `status.md`'s 1939-kolonne hæves først efter 6e-2 (spec §8).
- Redaktørens kildeløse fakta vises stadig som »Kilde ikke registreret« (spec §9 pkt. 4, ikke afgjort).
- Relative datoer: 273 opløses, 91 vises som bogens tekst (forsigtig regel, spec §5.4a) — et kontrolark over de 40,
  der blev forsigtige i slutrunden, kan laves efter ønske.
