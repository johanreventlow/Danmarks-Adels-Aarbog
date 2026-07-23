# Præsensliste — våben + intro-tekst dataindsættelse (runbook)

Kør EFTER Task 3's migration (`vocab` rolle='vaaben') er anvendt mod prod. Kør altid
mod en lokal kopi/branch-base først (jf. global regel om DB-ændringer).

## 1. Upload våben-billeder til Storage

Upload de eksisterende PNG'er fra Claude Design-projektet (`assets/heraldik/linje-I.png`,
`linje-II.png` — kun disse to findes pt. som pr.-linje-specifikke filer; øvrige linjer
mangler stadig dedikerede billeder) til Supabase Storage-bucketten `media`, under en sti
efter eksisterende konvention, fx `heraldik/linje-i.png`.

## 2. Indsæt media + coat_of_arms + relation pr. linje

For hver linje der har et billede, kør (udfyld de firkantede parenteser med reelle
værdier — `lineage_id` findes via `SELECT id, kode, navn FROM lineage;`):

```sql
-- 1) media-række for billedfilen
INSERT INTO media (id, slags, bucket, storage_path, upload_status, maa_publiceres)
VALUES ([nyt_id], 'scanning', 'media', 'heraldik/linje-i.png', 'klar', true);

-- 2) coat_of_arms-række (blasonering kan eftersuppleres)
INSERT INTO coat_of_arms (id, blasonering, note)
VALUES ([nyt_id], '[blasonering — redaktionelt indhold]', NULL);

-- 3) media viser våbnet (eksisterende konvention, samme retning som fetchObjectMedia)
INSERT INTO relation (subjekt_type, subjekt_id, objekt_type, objekt_id, rolle)
VALUES ('media', [media_id], 'coat_of_arms', [coat_of_arms_id], 'afbildet');

-- 4) linjen har dette våben (ny relationstype, Task 3's vocab-kode)
INSERT INTO relation (subjekt_type, subjekt_id, objekt_type, objekt_id, rolle)
VALUES ('lineage', [lineage_id], 'coat_of_arms', [coat_of_arms_id], 'vaaben');
```

## 3. Præsens-intro narrativ

```sql
-- 1) dedikeret kilde
INSERT INTO source (id, slags, titel) VALUES ([nyt_id], 'præsens-intro', 'Præsensliste — indledning');

-- 2) narrativet selv (subjekt_id=1 er samme sentinel som "Om slægten"s subjekt_type='slaegt')
INSERT INTO narrative (id, subjekt_type, subjekt_id, source_id, tekst, privat)
VALUES ([nyt_id], 'slaegt', 1, [source_id fra trin 1], '[intro-tekst — redaktionelt indhold, to afsnit adskilt af \n\n]', false);
```

## 4. Verificér

Genindlæs `/praesens` (redaktør-login) og bekræft at våben/titel/navn/intro nu vises for
de linjer der har fået data — linjer uden data falder tilbage til blank (ingen fejl,
jf. Task 4/5's `undefined`-håndtering).
