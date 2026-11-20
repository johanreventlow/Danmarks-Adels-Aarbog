import { describe, expect, it } from 'vitest';
import { slutterPaaSlaegtsnavn, udenSlaegtsnavnTilSidst } from '../slaegtsnavn';

describe('slutterPaaSlaegtsnavn / udenSlaegtsnavnTilSidst (#401)', () => {
  it('helt ord til sidst, uden hensyn til store bogstaver og bindestregs-tegn', () => {
    expect(slutterPaaSlaegtsnavn('Beke Ahlefeldt‑Laurvig', 'ahlefeldt-laurvig')).toBe(true);
    expect(slutterPaaSlaegtsnavn('Anna Hansensdatter', 'Hansen')).toBe(false);
    expect(slutterPaaSlaegtsnavn('Hansen', 'Hansen')).toBe(false);
    expect(slutterPaaSlaegtsnavn('Anna Hansen', '  ')).toBe(false);
  });
  it('fjerner slægtsnavnet, men aldrig hele navnet', () => {
    expect(udenSlaegtsnavnTilSidst('Anna Hansen', 'Hansen')).toBe('Anna');
    expect(udenSlaegtsnavnTilSidst('Hansen', 'Hansen')).toBe('Hansen');
    expect(udenSlaegtsnavnTilSidst('Anna Christensen', 'Hansen')).toBe('Anna Christensen');
  });
});
