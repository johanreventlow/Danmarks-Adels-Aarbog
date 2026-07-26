import { describe, test, expect } from 'vitest';
import { buildArbejdsliste, pairKey } from '../sammenlign';
import type { ScoredPair } from '@daa/core';

const sp = (aId: string, bId: string, tier: ScoredPair['tier'], score: number): ScoredPair =>
  ({ aId, bId, nameSim: score, birthOverlap: true, deathOverlap: false, sexEq: true, uniqueBlock: true, score, tier });

describe('pairKey — retningsløs normalisering', () => {
  test('samme nøgle uanset rækkefølge', () => {
    expect(pairKey('7', '3')).toBe(pairKey('3', '7'));
    expect(pairKey('a', 'b')).toBe('a|b');
  });
});

describe('buildArbejdsliste (§5.2)', () => {
  const pairs = [
    sp('A1', 'B1', 'auto', 0.95),
    sp('A1', 'B2', 'review', 0.72),
    sp('A2', 'B3', 'review', 0.75),
    sp('A3', 'BX', 'none', 0.3), // tier none → ignoreres
  ];
  const aIds = ['A1', 'A2', 'A3', 'A4']; // A4 har ingen kandidater

  test('grupperer pr. A-person; tier none ekskluderet; A4 = formodet_ny', () => {
    const { personer } = buildArbejdsliste(pairs, aIds, new Set(), new Set());
    const byId = Object.fromEntries(personer.map((p) => [p.aId, p]));
    expect(byId['A1'].kandidater.map((k) => k.bId)).toEqual(['B1', 'B2']); // sorteret score desc
    expect(byId['A3'].kandidater).toHaveLength(0); // 'none' filtreret
    expect(byId['A3'].status).toBe('formodet_ny');
    expect(byId['A4'].status).toBe('formodet_ny');
  });

  test('linket par → afklaret; A2 uden link → aaben', () => {
    const linkede = new Set([pairKey('A1', 'B1')]);
    const { personer } = buildArbejdsliste(pairs, aIds, new Set(), linkede);
    const byId = Object.fromEntries(personer.map((p) => [p.aId, p]));
    expect(byId['A1'].status).toBe('afklaret');
    expect(byId['A1'].kandidater.find((k) => k.bId === 'B1')!.linket).toBe(true);
    expect(byId['A2'].status).toBe('aaben');
  });

  test('alle kandidater afvist → afklaret', () => {
    const afviste = new Set([pairKey('A2', 'B3')]);
    const { personer } = buildArbejdsliste(pairs, aIds, afviste, new Set());
    const a2 = personer.find((p) => p.aId === 'A2')!;
    expect(a2.kandidater[0].afvist).toBe(true);
    expect(a2.status).toBe('afklaret');
  });

  test('fremdrift tæller korrekt', () => {
    const { fremdrift } = buildArbejdsliste(pairs, aIds, new Set(), new Set());
    expect(fremdrift.total).toBe(4);
    expect(fremdrift.staerke).toBe(1);      // A1 har aktiv auto
    expect(fremdrift.gennemse).toBe(1);     // A2 kun review
    expect(fremdrift.formodetNye).toBe(2);  // A3, A4
    expect(fremdrift.afklaret).toBe(0);
  });

  test('sortering: åbne før afklarede før formodet-nye', () => {
    const linkede = new Set([pairKey('A1', 'B1')]); // A1 → afklaret
    const { personer } = buildArbejdsliste(pairs, aIds, new Set(), linkede);
    const statusRk = personer.map((p) => p.status);
    // første skal være 'aaben' (A2), formodet_ny sidst
    expect(statusRk[0]).toBe('aaben');
    expect(statusRk[statusRk.length - 1]).toBe('formodet_ny');
  });
});

describe('svage kandidater (tier=none) bevares til manuel gennemgang', () => {
  const par = (aId: string, bId: string, tier: 'auto' | 'review' | 'none', score: number) => ({
    aId, bId, tier, score, nameSim: score, birthOverlap: false, deathOverlap: false,
    sexEq: false, uniqueBlock: false,
  });

  it('lægger tier=none i svageKandidater, ikke i kandidater', () => {
    const l = buildArbejdsliste([par('1', 'b1', 'none', 0.62)], ['1'], new Set(), new Set());
    const p = l.personer[0];
    expect(p.kandidater).toHaveLength(0);
    expect(p.svageKandidater.map((k) => k.bId)).toEqual(['b1']);
  });

  it('holder status formodet_ny — svage kandidater ændrer ikke fremdriften', () => {
    const l = buildArbejdsliste([par('1', 'b1', 'none', 0.62)], ['1'], new Set(), new Set());
    expect(l.personer[0].status).toBe('formodet_ny');
    expect(l.fremdrift.formodetNye).toBe(1);
    expect(l.fremdrift.gennemse).toBe(0);
  });

  it('sorterer svage kandidater efter score, bedste først', () => {
    const l = buildArbejdsliste(
      [par('1', 'lav', 'none', 0.40), par('1', 'hoej', 'none', 0.65)],
      ['1'], new Set(), new Set(),
    );
    expect(l.personer[0].svageKandidater.map((k) => k.bId)).toEqual(['hoej', 'lav']);
  });

  it('markerer allerede afviste svage kandidater, så de kan skjules', () => {
    const l = buildArbejdsliste(
      [par('1', 'b1', 'none', 0.62)], ['1'],
      new Set([pairKey('1', 'b1')]), new Set(),
    );
    expect(l.personer[0].svageKandidater[0].afvist).toBe(true);
  });

  it('rører ikke personer der har rigtige kandidater', () => {
    const l = buildArbejdsliste(
      [par('1', 'god', 'review', 0.75), par('1', 'svag', 'none', 0.5)],
      ['1'], new Set(), new Set(),
    );
    expect(l.personer[0].status).toBe('aaben');
    expect(l.personer[0].kandidater.map((k) => k.bId)).toEqual(['god']);
    expect(l.personer[0].svageKandidater.map((k) => k.bId)).toEqual(['svag']);
  });
});
