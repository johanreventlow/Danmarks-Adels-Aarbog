import { buildArbejdsliste, pairKey } from '../sammenlign';
import type { ScoredPair } from '@daa/core';

const sp = (aId: string, bId: string, tier: ScoredPair['tier'], score: number): ScoredPair =>
  ({ aId, bId, nameSim: score, birthOverlap: true, deathOverlap: false, sexEq: true, uniqueBlock: true, score, tier });

describe('sammenlign — arbejdsliste (§5.2)', () => {
  const pairs = [
    sp('A1', 'B1', 'auto', 0.95),
    sp('A1', 'B2', 'review', 0.72),
    sp('A2', 'B3', 'review', 0.75),
    sp('A3', 'BX', 'none', 0.3),
  ];
  const aIds = ['A1', 'A2', 'A3', 'A4'];

  it('pairKey retningsløs', () => {
    expect(pairKey('7', '3')).toBe(pairKey('3', '7'));
  });

  it('grupperer; tier none ekskluderet; A4 formodet_ny', () => {
    const { personer } = buildArbejdsliste(pairs, aIds, new Set(), new Set());
    const byId = Object.fromEntries(personer.map((p) => [p.aId, p]));
    expect(byId['A1'].kandidater.map((k) => k.bId)).toEqual(['B1', 'B2']);
    expect(byId['A3'].status).toBe('formodet_ny');
    expect(byId['A4'].status).toBe('formodet_ny');
  });

  it('linket → afklaret; afvist → afklaret; fremdrift', () => {
    const linkede = buildArbejdsliste(pairs, aIds, new Set(), new Set([pairKey('A1', 'B1')]));
    expect(linkede.personer.find((p) => p.aId === 'A1')!.status).toBe('afklaret');
    const afviste = buildArbejdsliste(pairs, aIds, new Set([pairKey('A2', 'B3')]), new Set());
    expect(afviste.personer.find((p) => p.aId === 'A2')!.status).toBe('afklaret');
    const { fremdrift } = buildArbejdsliste(pairs, aIds, new Set(), new Set());
    expect(fremdrift.staerke).toBe(1);
    expect(fremdrift.formodetNye).toBe(2);
  });
});
