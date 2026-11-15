import { describe, expect, it } from 'vitest';
import { sidetitel, VAERK } from '../sidetitel';
import { labelOfMode, type Mode } from '../nav';

describe('sidetitel', () => {
  it('hovedsiden hedder værket', () => {
    expect(VAERK).toBe('Danmarks Adels Aarbog');
    expect(sidetitel({ mode: 'home' })).toBe('Danmarks Adels Aarbog');
  });

  it('personsiden bærer personens navn; ukendt person kun værket', () => {
    expect(sidetitel({ mode: 'person', personNavn: 'Conrad Reventlow' })).toBe('Conrad Reventlow · Danmarks Adels Aarbog');
    expect(sidetitel({ mode: 'person', personNavn: null })).toBe('Danmarks Adels Aarbog');
  });

  it('slægtskab med begge personer nævner dem; ellers kun siden', () => {
    expect(sidetitel({ mode: 'relate', aNavn: 'A', bNavn: 'B' })).toBe('A og B · Er vi i familie? · Danmarks Adels Aarbog');
    expect(sidetitel({ mode: 'relate', aNavn: 'A', bNavn: null })).toBe('Er vi i familie? · Danmarks Adels Aarbog');
  });

  it('søgning med og uden søgeord', () => {
    expect(sidetitel({ mode: 'soeg', q: 'Conrad' })).toBe('Søg: Conrad · Danmarks Adels Aarbog');
    expect(sidetitel({ mode: 'soeg', q: '  ' })).toBe('Personer · Danmarks Adels Aarbog');
    expect(sidetitel({ mode: 'soeg' })).toBe('Personer · Danmarks Adels Aarbog');
  });

  it('slægtens forside og slægtens sider', () => {
    expect(sidetitel({ mode: 'about', slaegtNavn: 'Reventlow' })).toBe('Reventlow · Danmarks Adels Aarbog');
    for (const m of ['tree', 'estates', 'kort', 'arms', 'praesens'] as Mode[]) {
      expect(sidetitel({ mode: m, slaegtNavn: 'Reventlow' })).toBe(`${labelOfMode(m)} · Reventlow · Danmarks Adels Aarbog`);
    }
  });

  it('besiddelsens egen side vinder over slægtens liste', () => {
    expect(sidetitel({ mode: 'estates', slaegtNavn: null, besiddelseNavn: 'Clausholm' })).toBe('Clausholm · Danmarks Adels Aarbog');
  });

  it('bogmærker og ukendt slægt', () => {
    expect(sidetitel({ mode: 'bookmarks' })).toBe('Bogmærker · Danmarks Adels Aarbog');
    expect(sidetitel({ mode: 'ukendtSlaegt' })).toBe('Slægt ikke fundet · Danmarks Adels Aarbog');
  });
});
