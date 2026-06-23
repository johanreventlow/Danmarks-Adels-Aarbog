import { buildModel } from '../buildModel';
import { computeRelationship, relationshipLabel } from '../relationship';
import type { Db } from '../types';

const mk = (id: string, name: string) => ({ id, name, born: null, died: null, years: '', title: '', bio: '' });

// Træ:  G ─┬─ P1 ─┬─ A
//          │      └─ A2
//          └─ P2 ──── B
const db: Db = {
  persons: ['G', 'P1', 'P2', 'A', 'A2', 'B'].map((id) => mk(id, id)),
  unions: [
    { id: 'fG', p1: 'G', p2: null, p2_name: null, year: null },
    { id: 'fP1', p1: 'P1', p2: null, p2_name: null, year: null },
    { id: 'fP2', p1: 'P2', p2: null, p2_name: null, year: null },
  ],
  parentChild: [
    { child: 'P1', parent: 'G', union: 'fG' },
    { child: 'P2', parent: 'G', union: 'fG' },
    { child: 'A', parent: 'P1', union: 'fP1' },
    { child: 'A2', parent: 'P1', union: 'fP1' },
    { child: 'B', parent: 'P2', union: 'fP2' },
  ],
};
const model = buildModel(db);

describe('relationshipLabel — danske etiketter', () => {
  test('samme person / forælder-barn / bedsteforælder', () => {
    expect(relationshipLabel(0, 0)).toBe('Samme person');
    expect(relationshipLabel(0, 1)).toBe('Forælder & barn');
    expect(relationshipLabel(2, 0)).toBe('Bedsteforælder & barnebarn');
  });
  test('søskende / onkel / fætter-grader', () => {
    expect(relationshipLabel(1, 1)).toBe('Søskende');
    expect(relationshipLabel(2, 1)).toBe('Onkel/tante & niece/nevø');
    expect(relationshipLabel(2, 2)).toBe('1. grads fætter/kusine');
    expect(relationshipLabel(3, 3)).toBe('2. grads fætter/kusine');
  });
  test('forskudt fætterskab', () => {
    expect(relationshipLabel(3, 2)).toBe('1. grads fætter/kusine · 1 gang forskudt');
    expect(relationshipLabel(4, 2)).toBe('1. grads fætter/kusine · 2 gange forskudt');
  });
});

describe('computeRelationship — over et konkret træ', () => {
  test('A og B = 1. grads fætter/kusine, fælles ane G', () => {
    const r = computeRelationship(model, 'A', 'B');
    expect(r.found).toBe(true);
    expect(r.label).toBe('1. grads fætter/kusine');
    expect(r.lcaId).toBe('G');
    expect(r.lcaName).toBe('G');
  });
  test('trin-for-trin: A → P1 → G(LCA) → P2 → B', () => {
    const r = computeRelationship(model, 'A', 'B');
    expect(r.steps.map((s) => s.id)).toEqual(['A', 'P1', 'G', 'P2', 'B']);
    expect(r.steps.find((s) => s.isLca)?.id).toBe('G');
  });
  test('søskende A & A2', () => {
    expect(computeRelationship(model, 'A', 'A2').label).toBe('Søskende');
  });
  test('onkel: A & P2', () => {
    expect(computeRelationship(model, 'A', 'P2').label).toBe('Onkel/tante & niece/nevø');
  });
  test('samme person', () => {
    expect(computeRelationship(model, 'A', 'A').label).toBe('Samme person');
  });
});
