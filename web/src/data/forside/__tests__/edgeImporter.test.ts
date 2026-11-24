import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

// Vercels Edge-bygger kan ikke slå workspace-pakkerne (@daa/*, kun TypeScript-kilde) op: deployet fejlede 24/11 med
// »The Edge Function "api/forside-data" is referencing unsupported modules: … kilder.js: @daa/core«. Funktionens
// importgraf må derfor kun have type-importer fra @daa/*.
const fil = (rel: string) => readFileSync(fileURLToPath(new URL(rel, import.meta.url)), 'utf-8');
const vaerdiImportFraDaa = /^import\s+(?!type\b)[^;]*from\s+'@daa\//m;

describe('forside-data-funktionens importgraf (Edge)', () => {
  it.each(['../../../../api/forside-data.ts', '../byg.ts', '../format.ts', '../kilder.ts'])('%s importerer ikke værdier fra @daa/*', (rel) => {
    expect(fil(rel)).not.toMatch(vaerdiImportFraDaa);
  });
});
