import { buildModel } from '@daa/core';
import { describe, expect, it } from 'vitest';
import { erSikkertDoed, kunSikkertDoede, LEVENDE_ALDERSGRAENSE } from '../levende';
import type { Model } from '../types';

function person(id: string, over: Partial<{ born: number | null; died: number | null }> = {}) {
  return {
    id, name: 'Person ' + id, born: null, died: null, years: '', title: '', bio: '',
    privat: false, ...over,
  };
}

function mkModel(persons: ReturnType<typeof person>[]): Model {
  return buildModel({ persons, unions: [], parentChild: [] }) as unknown as Model;
}

describe('erSikkertDoed', () => {
  it('registreret dødsår → sikkert død, uanset alder', () => {
    expect(erSikkertDoed({ born: null, died: 2020 }, 2026)).toBe(true);
  });
  it('født for over aldersgrænsen siden uden dødsår → regnes som død', () => {
    expect(erSikkertDoed({ born: 1900, died: null }, 2026)).toBe(true);
  });
  it(`født præcis ${LEVENDE_ALDERSGRAENSE} år siden uden dødsår → IKKE sikkert død (kan være i live)`, () => {
    expect(erSikkertDoed({ born: 2026 - LEVENDE_ALDERSGRAENSE, died: null }, 2026)).toBe(false);
  });
  it('født for nyligt uden dødsår → kan være i live, ikke sikkert død', () => {
    expect(erSikkertDoed({ born: 1980, died: null }, 2026)).toBe(false);
  });
  it('hverken fødsels- eller dødsår → ukendt, fail-closed (ikke sikkert død)', () => {
    expect(erSikkertDoed({ born: null, died: null }, 2026)).toBe(false);
  });
});

describe('kunSikkertDoede', () => {
  it('udelukker personer uden dødsevidens fra både persons og byId', () => {
    const model = mkModel([
      person('doed', { died: 1950 }),
      person('gammel', { born: 1880 }),
      person('ukendt'),
      person('muligvis-levende', { born: 1990 }),
    ]);
    const safe = kunSikkertDoede(model, 2026);
    expect(safe.persons.map((p) => p.id).sort()).toEqual(['doed', 'gammel']);
    expect(safe.byId.doed).toBeDefined();
    expect(safe.byId.gammel).toBeDefined();
    expect(safe.byId.ukendt).toBeUndefined();
    expect(safe.byId['muligvis-levende']).toBeUndefined();
  });

  it('rører ikke indexes — slægtsgrafen forbliver komplet for relationsberegning', () => {
    const model = buildModel({
      persons: [
        person('barn1', { died: 1950 }),
        person('barn2', { died: 1960 }),
        person('foraelder', { born: 1990 }), // ikke sikkert død — udelades fra byId
      ],
      unions: [{ id: 'u1', p1: 'foraelder', p2: null, p2_name: null, year: null }],
      parentChild: [
        { child: 'barn1', parent: 'foraelder', union: 'u1', konfidens: 'sikker' },
        { child: 'barn2', parent: 'foraelder', union: 'u1', konfidens: 'sikker' },
      ],
    }) as unknown as Model;
    const safe = kunSikkertDoede(model, 2026);
    expect(safe.indexes).toBe(model.indexes);
    expect(safe.indexes.parentsByChild.barn1).toContain('foraelder');
  });

  it('tom model → tom liste, ingen crash', () => {
    const safe = kunSikkertDoede(mkModel([]), 2026);
    expect(safe.persons).toEqual([]);
    expect(safe.byId).toEqual({});
  });
});
