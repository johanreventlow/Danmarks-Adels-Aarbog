import { describe, expect, it } from 'vitest';
import type { ForsideData } from '../format';
import { udpakForsideData } from '../udpak';

const bioRow = (id: number) => ({ person_id: id, source_id: 1, source_year: 2018, record_order: 1, source_record_ref: 'r' + id, source_label: 'DAA', record_label: 'Post', narrative_text: 'Tekst ' + id, citation_label: '', provenance_kind: 'source_record' });
const fil = (o: Partial<ForsideData> = {}): ForsideData => ({
  version: 1, genereret: '2026-11-24T10:00:00.000Z', personIder: ['1', '2'],
  bios: { komplet: true, data: { kontrakt: 2, rows: [bioRow(1)], fejlede: [] } },
  haendelser: { komplet: true, data: { rows: [], narrativer: [], sources: [] } },
  livsdato: { komplet: true, data: { facts: [], conclusions: [], assertions: [] } },
  historier: { komplet: true, data: { rows: [], kilder: [], sources: [] } },
  naevnt: { komplet: true, data: [[{ subjekt_id: 2 }], [], []] },
  ...o,
});
const model = (persons: { id: string; levende?: boolean }[]) => ({ canonicalIdById: {}, persons });

describe('udpakForsideData', () => {
  it('komplet og dækkende fil giver nævnt-grundlag og biografier', () => {
    const u = udpakForsideData(fil(), model([{ id: '1' }, { id: '2' }]));
    expect(u.bios).toEqual({ bioBy: { '1': 'Tekst 1' }, komplet: true });
    expect(u.naevntGrundlag).not.toBe('fejlet');
    expect(u.naevntGrundlag !== 'fejlet' && [...u.naevntGrundlag.personerMedMereEndNavn]).toEqual(['2']);
  });

  it('ikke-levende person uden for personIder (tilføjet efter generering): nævnt fejlet', () => {
    expect(udpakForsideData(fil(), model([{ id: '1' }, { id: '2' }, { id: '3' }])).naevntGrundlag).toBe('fejlet');
  });

  it('levende person uden for personIder påvirker ikke dækningen', () => {
    expect(udpakForsideData(fil(), model([{ id: '1' }, { id: '2' }, { id: '9', levende: true }])).naevntGrundlag).not.toBe('fejlet');
  });

  it('delvise biografier: nævnt fejlet, biografierne med', () => {
    const u = udpakForsideData(fil({ bios: { komplet: false, data: { kontrakt: 2, rows: [bioRow(1)], fejlede: [2] } } }), model([{ id: '1' }, { id: '2' }]));
    expect(u.bios).toEqual({ bioBy: { '1': 'Tekst 1' }, komplet: false });
    expect(u.naevntGrundlag).toBe('fejlet');
  });

  it('fejlede biografier: bios null; en manglende del giver tomt opslag', () => {
    const u = udpakForsideData(fil({ bios: { komplet: false, data: null }, haendelser: { komplet: false, data: null } }), model([{ id: '1' }]));
    expect(u.bios).toBeNull();
    expect(u.haendelserBy).toEqual({});
    expect(u.naevntGrundlag).toBe('fejlet');
  });
});
