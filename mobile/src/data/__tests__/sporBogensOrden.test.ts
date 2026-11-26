// Stamtræets Spor-variant (C) står i Aarbogens rækkefølge (rest fra paritetsplanens batch 6). Rækkerne, førstefødt-
// halen, vej-til-mig og storens søskendeskift skal bruge SAMME rækkefølge; ellers lander et stryg på et andet barn end
// det, ruten regnede med. Fixturen gør indlæsnings-, fødselsårs- og bogens rækkefølge forskellige, så en kaldsted, der
// glemmer bogen, giver et andet resultat.
jest.mock('../load', () => ({ loadFromSupabase: jest.fn() }));
jest.mock('../../lib/auth', () => ({ signOut: jest.fn(), signIn: jest.fn(), fetchProfile: jest.fn() }));
jest.mock('../../lib/supabase', () => ({ supabase: {
  auth: {
    getSession: () => Promise.resolve({ data: { session: null } }),
    onAuthStateChange: () => ({ data: { subscription: { unsubscribe: () => undefined } } }),
  },
} }));

import { buildModel, type Db, type RawLineageContext } from '@daa/core';
import { useStore } from '../../store/useStore';
import { boernIBogensOrden, buildSnapPath, childrenOf, routeToMe, sporLinje, wayToMe } from '../selectors';
import type { AppPerson, Model, RawExtId, RawSource } from '../types';
import { byggUdgaveLag } from '../udgaveLag';

const mk = (id: string, name: string, born: number): AppPerson =>
  ({ id, name, born, died: null, years: `* ${born}`, title: '', bio: '', privat: false });

// Far (10) har tre børn. Indlæsning: Xa, Yb, Zc. Fødselsår: Yb (1690), Xa (1700), Zc (1710). Bogen: Zc nr. 2,
// Xa nr. 3, Yb nr. 4. Zc og Xa har hver ét barn (Zc → 30, Xa → 31).
const db: Db = {
  persons: [mk('10', 'Far', 1660), mk('20', 'Xa', 1700), mk('21', 'Yb', 1690), mk('22', 'Zc', 1710), mk('30', 'Zc-barn', 1740), mk('31', 'Xa-barn', 1730)],
  unions: [{ id: 'f1', p1: '10', p2: null, p2_name: null, year: null }, { id: 'f2', p1: '22', p2: null, p2_name: null, year: null }, { id: 'f3', p1: '20', p2: null, p2_name: null, year: null }],
  parentChild: [
    { child: '20', parent: '10', union: 'f1' }, { child: '21', parent: '10', union: 'f1' }, { child: '22', parent: '10', union: 'f1' },
    { child: '30', parent: '22', union: 'f2' }, { child: '31', parent: '20', union: 'f3' },
  ],
};
const sources: RawSource[] = [{ id: 2, slags: 'DAA-udgave', titel: 'Danmarks Adels Aarbog 2018-20', udgave: 'DAA 2018-20', aar: 2018, ekstern: null }];
const lineageRows: RawLineageContext[] = [{ id: 50, source_id: 2, kode: 'V', navn: 'Den grevelige Linje', slaegt_id: 1, slaegtsnavn: 'Reventlow' }];
const schemeRows = { schemes: [{ id: 20, slaegt_id: 1, source_id: 2, kind: 'stamtavle' }], entries: [], mappings: [] };
const ext = (person_id: number, nr: number): RawExtId => ({ person_id, source_id: 2, linje: 'V', nr, slaegtled_lokal: 1, provenance: 'placement' });
const extIds: RawExtId[] = [ext(10, 1), ext(22, 2), ext(20, 3), ext(21, 4), ext(30, 5), ext(31, 6)];
const model: Model = { ...buildModel(db), ...byggUdgaveLag({ extIds, sources, lineageRows, schemeRows }, {}), canonicalIdById: {}, parentsUnknownByPerson: {} };

describe('Spor (variant C) i Aarbogens rækkefølge', () => {
  test('fixturen skelner: indlæsning ≠ bogen', () => {
    expect(childrenOf(model, '10').map((p) => p.name)).toEqual(['Xa', 'Yb', 'Zc']);
    expect(boernIBogensOrden(model, '10').map((p) => p.name)).toEqual(['Zc', 'Xa', 'Yb']);
  });

  test('førstefødt-halen følger det første barn i bogen', () => {
    expect(buildSnapPath(model, '10', '10')).toEqual({ path: ['10', '22', '30'], depth: 0 });
  });

  test('vej til mig tæller søskendeskift i bogens rækkefølge', () => {
    const p = buildSnapPath(model, '22', '10'); // ['10','22','30'], depth 1 på Zc
    expect(routeToMe(model, p.path, p.depth, '21')).toEqual(['right', 'right']); // Zc → Xa → Yb
    expect(wayToMe(model, p.path, p.depth, '31')).toEqual({ step: 'right', remaining: 2 }); // Xa, så ned til Xa-barn
  });

  test('søskendeskift i storen går til næste barn i bogen og genopbygger halen', () => {
    useStore.setState({ model, snapPath: ['10', '22', '30'], snapDepth: 1, focusId: '22' });
    useStore.getState().moveSnapSib(1);
    expect(useStore.getState().snapPath).toEqual(['10', '20', '31']);
    expect(useStore.getState().focusId).toBe('20');
    useStore.getState().moveSnapSib(1);
    expect(useStore.getState().snapPath).toEqual(['10', '21']);
  });
});

describe('Spors linjenavn (sporLinje)', () => {
  test('den valgte linje vinder, når personen står i den', () => {
    expect(sporLinje(['IV', 'V'], 'V')).toBe('V');
  });
  test('personen står ikke i den valgte linje: personens egen første linje', () => {
    expect(sporLinje(['IV'], 'V')).toBe('IV');
  });
  test('ingen linjer på personen: den valgte (eller ingen)', () => {
    expect(sporLinje(undefined, 'V')).toBe('V');
    expect(sporLinje([], null)).toBeNull();
  });
});
