import { describe, it, expect } from 'vitest';
import { parseFolgesvendPath, pathForMode, labelOfMode, detailOpenFor, personPath, estatePath, slaegtPath, stamtraePath, soegPath, type Mode } from '../data/nav';

const tom = { personId: null, fokusId: null, estateId: null, slaegt: null, q: null, omdiriger: null };

describe('parseFolgesvendPath — ny grammatik', () => {
  it('/ (og tom sti) → hovedsiden', () => {
    expect(parseFolgesvendPath('/')).toEqual({ ...tom, mode: 'home' });
    expect(parseFolgesvendPath('')).toEqual({ ...tom, mode: 'home' });
  });
  it('slægtens sider', () => {
    expect(parseFolgesvendPath('/slaegt/reventlow')).toEqual({ ...tom, mode: 'about', slaegt: 'reventlow' });
    expect(parseFolgesvendPath('/slaegt/reventlow/stamtrae')).toEqual({ ...tom, mode: 'tree', slaegt: 'reventlow' });
    expect(parseFolgesvendPath('/slaegt/reventlow/praesens').mode).toBe('praesens');
    expect(parseFolgesvendPath('/slaegt/reventlow/godser').mode).toBe('estates');
    expect(parseFolgesvendPath('/slaegt/reventlow/godser', '?visning=kort').mode).toBe('kort');
    expect(parseFolgesvendPath('/slaegt/reventlow/vaaben').mode).toBe('arms');
  });
  it('stamtræet med fokus åbner personen', () => {
    expect(parseFolgesvendPath('/slaegt/reventlow/stamtrae', '?fokus=482')).toEqual({ ...tom, mode: 'tree', slaegt: 'reventlow', fokusId: '482' });
  });
  it('ukendt slægt eller side → ukendtSlaegt, ikke forsiden', () => {
    expect(parseFolgesvendPath('/slaegt/findes-ikke').mode).toBe('ukendtSlaegt');
    expect(parseFolgesvendPath('/slaegt/reventlow/findes-ikke').mode).toBe('ukendtSlaegt');
  });
  it('sider over slægterne', () => {
    expect(parseFolgesvendPath('/person/abc')).toEqual({ ...tom, mode: 'person', personId: 'abc' });
    expect(parseFolgesvendPath('/gods/e1')).toEqual({ ...tom, mode: 'estates', estateId: 'e1' });
    expect(parseFolgesvendPath('/slaegtskab').mode).toBe('relate');
    expect(parseFolgesvendPath('/soeg', '?q=Conrad')).toEqual({ ...tom, mode: 'soeg', q: 'Conrad' });
    expect(parseFolgesvendPath('/soeg').q).toBe('');
    expect(parseFolgesvendPath('/min-side/bogmaerker').mode).toBe('bookmarks');
  });
  it('ødelagt kodning i stien kaster ikke', () => {
    expect(parseFolgesvendPath('/slaegt/reventlow%').mode).toBe('ukendtSlaegt');
  });
  it('ukendt sti øverst → hovedsiden', () => {
    expect(parseFolgesvendPath('/findes-ikke').mode).toBe('home');
  });
});

describe('gamle stier omdirigeres', () => {
  const tilfaelde: [string, string, Mode][] = [
    ['/stamtrae', '/slaegt/reventlow/stamtrae', 'tree'],
    ['/about', '/slaegt/reventlow', 'about'],
    ['/estates', '/slaegt/reventlow/godser', 'estates'],
    ['/kort', '/slaegt/reventlow/godser?visning=kort', 'kort'],
    ['/arms', '/slaegt/reventlow/vaaben', 'arms'],
    ['/praesens', '/slaegt/reventlow/praesens', 'praesens'],
    ['/relate', '/slaegtskab', 'relate'],
    ['/bookmarks', '/min-side/bogmaerker', 'bookmarks'],
    ['/estate/7', '/gods/7', 'estates'],
  ];
  it.each(tilfaelde)('%s → %s', (gammel, ny, mode) => {
    const p = parseFolgesvendPath(gammel);
    expect(p.omdiriger).toBe(ny);
    expect(p.mode).toBe(mode); // første render er allerede rigtig
  });
  it('/person/<id> er uændret og omdirigeres ikke', () => {
    expect(parseFolgesvendPath('/person/1').omdiriger).toBeNull();
  });
});

describe('pathForMode + rundtur', () => {
  const modes: Mode[] = ['home', 'tree', 'estates', 'relate', 'arms', 'about', 'bookmarks', 'kort', 'praesens', 'soeg'];
  it('parse(pathForMode(m)).mode === m, uden omdirigering', () => {
    for (const m of modes) {
      const [sti, q = ''] = pathForMode(m).split('?');
      const p = parseFolgesvendPath(sti, q ? `?${q}` : '');
      expect(p.mode).toBe(m);
      expect(p.omdiriger).toBeNull();
    }
  });
});

describe('stier med id og query', () => {
  it('person, gods, slægt, stamtræ og søgning', () => {
    expect(personPath('482')).toBe('/person/482');
    expect(estatePath('7')).toBe('/gods/7');
    expect(slaegtPath()).toBe('/slaegt/reventlow');
    expect(stamtraePath()).toBe('/slaegt/reventlow/stamtrae');
    expect(stamtraePath('reventlow', '482')).toBe('/slaegt/reventlow/stamtrae?fokus=482');
    expect(soegPath('Conrad Reventlow')).toBe('/soeg?q=Conrad%20Reventlow');
    expect(soegPath('')).toBe('/soeg');
  });
  it('er den modsatte retning af parseFolgesvendPath', () => {
    expect(parseFolgesvendPath(personPath('482')).personId).toBe('482');
    expect(parseFolgesvendPath(estatePath('7')).estateId).toBe('7');
    const [sti, q] = stamtraePath('reventlow', '482').split('?');
    expect(parseFolgesvendPath(sti, `?${q}`).fokusId).toBe('482');
    expect(parseFolgesvendPath('/soeg', soegPath('Ida Benedicte').slice(5)).q).toBe('Ida Benedicte');
  });
});

describe('labelOfMode', () => {
  it('giver sidens navn', () => {
    expect(labelOfMode('tree')).toBe('Stamtræ');
    expect(labelOfMode('estates')).toBe('Godser');
  });
  it('tom for modes uden navn', () => {
    expect(labelOfMode('home')).toBe('');
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

