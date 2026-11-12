// Holder de typede værdier i index.ts lig designsystemets tokens.json.
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { color, fontFamily, radius, shadow, space, textStyle } from '../index';

type Tok = { name: string; value: string };
const json = JSON.parse(readFileSync(new URL('../tokens.json', import.meta.url), 'utf8'));
const camel = (s: string) => s.replace(/-([a-z0-9])/g, (_, c: string) => c.toUpperCase());
const px = (v: string) => Number(v.replace(/px$/, ''));

describe('tokens.json ↔ index.ts', () => {
  it('farver: samme navne og værdier, henvisninger som {bordeaux} slået op', () => {
    const toks: Tok[] = json.color.tokens;
    const byName = Object.fromEntries(toks.map((t) => [t.name, t.value]));
    const resolve = (v: string): string => (/^\{(.+)\}$/.test(v) ? resolve(byName[v.slice(1, -1)]) : v);
    const forventet = Object.fromEntries(toks.map((t) => [camel(t.name), resolve(t.value).toLowerCase()]));
    const faktisk = Object.fromEntries(Object.entries(color).map(([k, v]) => [k, v.toLowerCase()]));
    expect(faktisk).toEqual(forventet);
  });

  it('skriftfamilier', () => {
    expect(fontFamily).toEqual(json.type.families);
  });

  it('tekststile', () => {
    const forventet: Record<string, object> = {};
    for (const g of json.type.groups) {
      for (const s of g.styles) {
        forventet[camel(s.name)] = {
          family: g.family, fontSize: px(s.fontSize), lineHeight: px(s.lineHeight), fontWeight: s.fontWeight,
          ...(s.fontStyle ? { fontStyle: s.fontStyle } : {}),
          ...(s.letterSpacing ? { letterSpacing: s.letterSpacing } : {}),
        };
      }
    }
    expect(textStyle).toEqual(forventet);
  });

  it('afstande, radier og skygger', () => {
    expect(space).toEqual(Object.fromEntries(json.spacing.tokens.map((t: Tok) => [t.name.replace('space-', ''), px(t.value)])));
    expect(radius).toEqual(Object.fromEntries(json.radius.tokens.map((t: Tok) => [camel(t.name.replace('radius-', '')), px(t.value)])));
    expect(shadow).toEqual(Object.fromEntries(json.shadow.tokens.map((t: Tok) => [camel(t.name.replace('shadow-', '')), t.value])));
  });

  it('ingen tekst under 11 px', () => {
    for (const s of Object.values(textStyle)) expect(s.fontSize).toBeGreaterThanOrEqual(11);
  });
});
