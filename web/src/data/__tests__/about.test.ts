import { describe, expect, it, vi } from 'vitest';

vi.mock('../../supabase', () => ({ supabase: { auth: { onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }) } } }));

import { byggAboutSections, type RawAboutRow } from '../public';

const daa = (aar: number, udgave: string | null, titel = 'Danmarks Adels Aarbog') => ({ slags: 'DAA-udgave', titel, aar, udgave });

describe('byggAboutSections', () => {
  it('bærer kilde og år fra den valgte udgave, efter udgavevælgerens regel (udgave før titel)', () => {
    const rows: RawAboutRow[] = [
      { id: 1, subjekt_type: 'slaegt', subjekt_id: 1, source_id: 10, tekst: 'Gammel indledning', source: daa(1939, 'Reventlow, stamtavle') },
      { id: 2, subjekt_type: 'slaegt', subjekt_id: 1, source_id: 20, tekst: 'Ny indledning', source: daa(2020, 'DAA 2018-20') },
    ];
    expect(byggAboutSections(rows, [])).toEqual([
      { lineageId: null, lineageNavn: null, lineageKode: null, tekst: 'Ny indledning', kilde: 'DAA 2018-20', aar: 2020 },
    ]);
  });

  it('falder tilbage på titlen, når udgaven mangler', () => {
    const rows: RawAboutRow[] = [
      { id: 1, subjekt_type: 'slaegt', subjekt_id: 1, source_id: 10, tekst: 'Tekst', source: daa(1939, null) },
    ];
    expect(byggAboutSections(rows, [])[0]).toMatchObject({ kilde: 'Danmarks Adels Aarbog', aar: 1939 });
  });

  it('giver linjeafsnit deres lineage-id som nøgle og bogens kode, i linjernes rækkefølge', () => {
    const rows: RawAboutRow[] = [
      { id: 3, subjekt_type: 'lineage', subjekt_id: 2, source_id: 10, tekst: 'Om II', source: daa(1939, 'Reventlow, stamtavle') },
      { id: 4, subjekt_type: 'lineage', subjekt_id: 1, source_id: 10, tekst: 'Om I', source: daa(1939, 'Reventlow, stamtavle') },
    ];
    const lin = [{ id: 1, navn: 'I. linje', kode: 'I' }, { id: 2, navn: null, kode: 'II' }];
    expect(byggAboutSections(rows, lin).map((s) => [s.lineageId, s.lineageKode, s.lineageNavn, s.tekst])).toEqual([
      ['1', 'I', 'I. linje', 'Om I'],
      ['2', 'II', 'Linje II', 'Om II'],
    ]);
  });

  it('springer tekst fra andre kilder end DAA-udgaver over (samme gate som biografien)', () => {
    const rows: RawAboutRow[] = [
      { id: 1, subjekt_type: 'slaegt', subjekt_id: 1, source_id: 30, tekst: 'Stub', source: { slags: 'TNG', aar: null, udgave: null } },
    ];
    expect(byggAboutSections(rows, [])).toEqual([]);
  });
});
