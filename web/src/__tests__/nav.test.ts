import { describe, it, expect } from 'vitest';
import { parseFolgesvendPath, pathForMode, themeOfMode, labelOfMode, detailOpenFor, personPath, estatePath, type Mode } from '../data/nav';

describe('parseFolgesvendPath', () => {
  it('/ (og tom sti) → forsiden (home)', () => {
    expect(parseFolgesvendPath('/')).toEqual({ mode: 'home', personId: null, estateId: null });
    expect(parseFolgesvendPath('')).toEqual({ mode: 'home', personId: null, estateId: null });
  });
  it('/stamtrae → tree uden fokus', () => {
    expect(parseFolgesvendPath('/stamtrae')).toEqual({ mode: 'tree', personId: null, estateId: null });
  });
  it('/person/:id → tree med fokus', () => {
    expect(parseFolgesvendPath('/person/abc')).toEqual({ mode: 'tree', personId: 'abc', estateId: null });
  });
  it('/estate/:id → estates med estateId', () => {
    expect(parseFolgesvendPath('/estate/e1')).toEqual({ mode: 'estates', personId: null, estateId: 'e1' });
  });
  it('faste faner mapper korrekt', () => {
    expect(parseFolgesvendPath('/estates').mode).toBe('estates');
    expect(parseFolgesvendPath('/relate').mode).toBe('relate');
    expect(parseFolgesvendPath('/arms').mode).toBe('arms');
    expect(parseFolgesvendPath('/about').mode).toBe('about');
    expect(parseFolgesvendPath('/bookmarks').mode).toBe('bookmarks');
    expect(parseFolgesvendPath('/kort').mode).toBe('kort');
    expect(parseFolgesvendPath('/praesens').mode).toBe('praesens');
  });
  it('ukendt sti → home (ikke tree)', () => {
    expect(parseFolgesvendPath('/findes-ikke').mode).toBe('home');
  });
});

describe('pathForMode + rundtur', () => {
  const modes: Mode[] = ['home', 'tree', 'estates', 'relate', 'arms', 'about', 'bookmarks', 'kort'];
  it('home → /, tree → /stamtrae', () => {
    expect(pathForMode('home')).toBe('/');
    expect(pathForMode('tree')).toBe('/stamtrae');
    expect(pathForMode('praesens')).toBe('/praesens');
  });
  it('parse(pathForMode(m)).mode === m for alle id-løse modes', () => {
    for (const m of modes) expect(parseFolgesvendPath(pathForMode(m)).mode).toBe(m);
  });
});

describe('themeOfMode', () => {
  it('mapper live modes til deres tema', () => {
    expect(themeOfMode('tree')).toBe('slaegten');
    expect(themeOfMode('relate')).toBe('slaegten');
    expect(themeOfMode('arms')).toBe('slaegten');
    expect(themeOfMode('about')).toBe('slaegten');
    expect(themeOfMode('estates')).toBe('godser');
    expect(themeOfMode('kort')).toBe('godser');
  });
  it('home/bookmarks hører ikke under noget tema', () => {
    expect(themeOfMode('home')).toBeNull();
    expect(themeOfMode('bookmarks')).toBeNull();
  });
});

describe('labelOfMode', () => {
  it('giver menu-label for live modes', () => {
    expect(labelOfMode('tree')).toBe('Stamtræ');
    expect(labelOfMode('kort')).toBe('Kort');
  });
  it('tom for modes uden menupunkt (home/bookmarks)', () => {
    expect(labelOfMode('home')).toBe('');
    expect(labelOfMode('bookmarks')).toBe('');
  });
});

describe('detailOpenFor (§5 split)', () => {
  it('tree: detalje åben KUN når URL har en person', () => {
    expect(detailOpenFor('tree', 'p1', 'p1')).toBe(true);   // /person/:id
    expect(detailOpenFor('tree', null, 'p1')).toBe(false);  // /stamtrae (træet centreret, men lukket)
    expect(detailOpenFor('tree', null, null)).toBe(false);
  });
  it('relate: detalje åben når en person er i fokus (focusOnly), uafhængigt af URL', () => {
    expect(detailOpenFor('relate', null, 'p1')).toBe(true);
    expect(detailOpenFor('relate', null, null)).toBe(false);
  });
  it('øvrige modes har ingen detalje', () => {
    expect(detailOpenFor('home', 'p1', 'p1')).toBe(false);
    expect(detailOpenFor('bookmarks', null, 'p1')).toBe(false);
    expect(detailOpenFor('estates', null, 'p1')).toBe(false);
    expect(detailOpenFor('arms', null, 'p1')).toBe(false);
  });
});

describe('personPath / estatePath', () => {
  it('bygger den dybe-linkbare person-sti', () => {
    expect(personPath('482')).toBe('/person/482');
  });
  it('bygger den dybe-linkbare gods-sti', () => {
    expect(estatePath('7')).toBe('/estate/7');
  });
  it('er den modsatte retning af parseFolgesvendPath', () => {
    // Samme par-invariant som MODE_PATH/PATH_MODE: de to retninger må ikke komme ud af trit.
    expect(parseFolgesvendPath(personPath('482')).personId).toBe('482');
    expect(parseFolgesvendPath(estatePath('7')).estateId).toBe('7');
  });
});
