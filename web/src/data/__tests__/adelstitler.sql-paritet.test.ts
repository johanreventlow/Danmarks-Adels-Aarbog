// Issue #396: regen_person_visning vælger adelstitlen som visning_titel ud fra en lukket liste i SQL.
// Listen skal være den samme som web's ADELS_TITLER, ellers viser cachen og præsenslisten forskellige titler.
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { ADELS_TITLER } from '../presens';

const rod = resolve(__dirname, '../../../..');
const MOENSTER = /lower\(trim\(a\.vaerdi_tekst\)\) IN \(([^)]*)\)/g;

function sqlLister(fil: string): string[][] {
  const sql = readFileSync(resolve(rod, fil), 'utf8');
  return [...sql.matchAll(MOENSTER)].map((m) =>
    m[1].split(',').map((s) => s.trim().replace(/^'|'$/g, '')),
  );
}

test('schema.sql: regen_person_visning har præcis én adelstitel-liste, og den er lig ADELS_TITLER', () => {
  const lister = sqlLister('schema.sql');
  expect(lister).toHaveLength(1);
  expect(new Set(lister[0])).toEqual(ADELS_TITLER);
  expect(lister[0]).toHaveLength(ADELS_TITLER.size);
});

test('db-migrations.sql: den sidste adelstitel-liste (den gældende definition) er lig ADELS_TITLER', () => {
  const lister = sqlLister('db-migrations.sql');
  expect(lister.length).toBeGreaterThan(0);
  expect(new Set(lister[lister.length - 1])).toEqual(ADELS_TITLER);
});
