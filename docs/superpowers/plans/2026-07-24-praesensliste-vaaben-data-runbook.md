# Præsensliste — våben + intro-tekst dataindsættelse (runbook)

Kør EFTER migrationerne (`vocab` rolle='vaaben' + `lineage.presens_kode`) er anvendt
mod prod. Kør altid mod en lokal kopi/branch-base først (jf. global regel om
DB-ændringer).

**Verificeret mod prod (2026-07-24):** `lineage`-rækkerne er

| id | kode | navn |
|----|------|------|
| 1 | I | Den holstenske linje (uddød — indgår IKKE i præsenslisten) |
| 2 | II | Linjen Gallentin (uddød — indgår IKKE i præsenslisten) |
| 3 | III | Den mecklenburgske linje (uddød — indgår IKKE i præsenslisten) |
| 4 | IV | Den lensgrevelige linje af 1767 — **bliver "I linje" i præsenslisten** |
| 5 | V | Den grevelige linje af 1673 — **bliver "II linje" i præsenslisten** |

## 1. Sæt presens_kode

```sql
UPDATE lineage SET presens_kode = 'I'  WHERE id = 4;  -- Den lensgrevelige linje af 1767
UPDATE lineage SET presens_kode = 'II' WHERE id = 5;  -- Den grevelige linje af 1673
```

Verificér bagefter: `SELECT id, kode, presens_kode, navn FROM lineage ORDER BY kode;`
— kun rækkerne med et udfyldt `presens_kode` vises i præsenslisten. Skal en tredje
linje senere have levende medlemmer, gentages dette trin med `presens_kode = 'III'`
osv. — det er en løbende redaktionel beslutning, ikke noget der afledes automatisk.

## 2. Opret coat_of_arms-rækker (kun via SQL — ingen UI til dette endnu)

Find næste ledige id: `SELECT max(id) + 1 FROM coat_of_arms;` (indsæt herunder i
stedet for `[nyt_id]`).

```sql
-- Den lensgrevelige linjes våben (bliver "I linje" i præsenslisten)
INSERT INTO coat_of_arms (id, blasonering, note)
VALUES ([nyt_id_A], NULL, NULL); -- blasonering eftersuppleres redaktionelt

-- Den grevelige linjes våben (bliver "II linje" i præsenslisten)
INSERT INTO coat_of_arms (id, blasonering, note)
VALUES ([nyt_id_B], NULL, NULL);

-- Linjerne har hvert deres våben (rolle='vaaben', Task 3's vocab-kode)
INSERT INTO relation (subjekt_type, subjekt_id, objekt_type, objekt_id, rolle)
VALUES ('lineage', 4, 'coat_of_arms', [nyt_id_A], 'vaaben');
INSERT INTO relation (subjekt_type, subjekt_id, objekt_type, objekt_id, rolle)
VALUES ('lineage', 5, 'coat_of_arms', [nyt_id_B], 'vaaben');
```

## 3. Upload billederne via den EKSISTERENDE redaktions-UI (ikke rå SQL)

Redaktions-appen har allerede en generisk medie-upload + -tilknytnings-flade
(`web/src/Redaktion.tsx`, "Våben"-målet i medie-tilknytningspickeren,
`red_upload_media`/`red_relation`-RPC'erne) — den dækker præcis dette, ingen ny kode
nødvendig:

1. Log ind i redaktionen, upload de to våben-billeder (de findes i
   Claude Design-projektet som `reventlow-linje-I.png`/`reventlow-linje-II.png`,
   eller i de filer du selv har liggende) som almindelige medier.
2. Brug "tilknyt"-funktionen på hvert billede, vælg mål-type **Våben**, og vælg det
   `coat_of_arms`-id du oprettede i trin 2 ovenfor (id A for linje IV/"I", id B for
   linje V/"II").

**Rækkefølge er vigtig:** trin 2 (opret coat_of_arms-rækkerne) SKAL køres først —
tilknytningspickeren i UI'et viser kun allerede-eksisterende `coat_of_arms`-rækker,
den opretter ikke nye.

## 4. Præsens-intro narrativ

```sql
-- 1) dedikeret kilde
INSERT INTO source (id, slags, titel) VALUES ([nyt_id], 'præsens-intro', 'Præsensliste — indledning');

-- 2) narrativet selv (subjekt_id=1 er samme sentinel som "Om slægten"s subjekt_type='slaegt')
INSERT INTO narrative (id, subjekt_type, subjekt_id, source_id, tekst, privat)
VALUES ([nyt_id], 'slaegt', 1, [source_id fra trin 1], '[intro-tekst — redaktionelt indhold, to afsnit adskilt af \n\n]', false);
```

## 5. Verificér

Genindlæs `/praesens` (redaktør-login) og bekræft at "I linje" viser Den lensgrevelige
linje af 1767's våben/titel/navn, og "II linje" viser Den grevelige linje af 1673's —
IKKE de uddøde Holstenske/Gallentin-linjers data. Linjer uden data falder tilbage til
blank (ingen fejl, jf. Task 4/5's `undefined`-håndtering).
