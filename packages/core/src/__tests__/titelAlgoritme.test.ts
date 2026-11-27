import { describe, it, expect } from 'vitest';
import { normTitel, hofTitel } from '../titelAlgoritme';

describe('titelAlgoritme', () => {
  it('normTitel skræller præfiks, parentes, komma og stedled', () => {
    expect(normTitel('Karakt. Etatsraad')).toBe('etatsråd'); // 1939-stavning »aa« → »å«
    expect(normTitel('Amtmand over Sorø Amt')).toBe('amtmand');
    expect(normTitel('kammerherre (1801)')).toBe('kammerherre');
    expect(normTitel('Hofjægermester, Ritmester')).toBe('hofjægermester');
    expect(normTitel('Kongelig Kammerherre til Hoffet')).toBe('kammerherre');
  });
  it('hofTitel: højeste trin pr. stige, så rangfølgen', () => {
    expect(hofTitel(['kammerjunker', 'kammerherre', 'major'])).toBe('kammerherre');
    expect(hofTitel(['oberst', 'generalmajor'])).toBe('generalmajor');
    expect(hofTitel(['etatsråd', 'amtmand'])).toBe('amtmand');
  });
  it('hofTitel: kaptajn og ritmester er samme trin', () => {
    expect(hofTitel(['kaptajn', 'ritmester', 'løjtnant'])).toBe('kaptajn');
    expect(hofTitel(['ritmester', 'major'])).toBe('major');
  });
  it('hofTitel: ord uden for rangfølgen (stigetrin) rangerer efter de opførte', () => {
    expect(hofTitel(['sekondløjtnant'])).toBe('sekondløjtnant');
    expect(hofTitel(['justitsråd', 'foged'])).toBe('foged');
  });
  it('hofTitel: adelstitler, ordener og ukendte ord giver null', () => {
    expect(hofTitel(['greve', 'hvid ridder', 'godsejer'])).toBeNull();
    expect(hofTitel(['rigsfriherre'])).toBeNull();
    expect(hofTitel([])).toBeNull();
  });
  it('hofTitel: en embedsetiket »rolle · org« er ikke input — kun rollen', () => {
    expect(hofTitel(['Kammerherre · Hoffet'])).toBeNull(); // kalderen giver rollen
    expect(hofTitel(['Kammerherre'])).toBe('kammerherre');
  });
});
