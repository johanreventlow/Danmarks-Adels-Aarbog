# Designtour

Skærmbilleder af webappen som anonym læser, indlogget medlem og redaktør, uden rigtig database og uden rigtige konti. Til at sammenligne den kørende app med designoplæggene, fx før og efter et redesign.

## Kør

```bash
python3 web/scripts/designtour/build-fixture.py   # → tmp/designtour/fixture.json
cd web && npm run dev                              # port 5173
node scripts/designtour/tour.mjs                   # alle trin
node scripts/designtour/tour.mjs red               # kun trin hvis navn indeholder "red"
```

Billederne lander i `tmp/designtour/shots/` (gitignoreret).

## Sådan virker det

- **Testdata:** `build-fixture.py` bygger tabellerne ud fra stamtavleudtrækket i `data/extracted-2026-06-18`. Kun personer født senest 1930 kommer med. Uden kendt fødsel er personen kun med, hvis den døde senest 1930, har et dateret faktum senest 1890 eller har en forælder født senest 1880. Ægtefæller filtreres efter samme princip. Der er ingen narrativer, medier, feed eller våben.
- **Database:** `mockdb.mjs` besvarer appens kald til `localhost:54321` (Supabase-URL'en i `.env.local`) fra fixture-filen via Playwrights `page.route`. Den dækker de PostgREST-funktioner, appen bruger. RPC'er uden stub svarer `[]` og logges som "rpc uden stub".
- **Login:** rollen sættes pr. trin (`role: 'medlem' | 'redaktion'`). Sessionen lægges direkte i localStorage, og `profiles` svarer med rollen. Skrivninger bliver ikke udført, kun logget.

Nye trin tilføjes i `STEPS` i `tour.mjs`.
