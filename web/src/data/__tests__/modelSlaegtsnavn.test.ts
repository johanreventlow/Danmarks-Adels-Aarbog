// loadModel lægger slægtsrodens navn på modellen (som mobilen), så statuslinjens gift-del virker for en hustru, hvis mand
// har en linje, men hvis linje ingen adelsnavn-regel har: »Gift grevinde Reventlow«.
import { describe, expect, it, vi } from 'vitest';
import { byggStatuslinje } from '@daa/core';

const TABELLER: Record<string, unknown[]> = {
  person: [
    { id: 1, visning_navn: 'Carl Reventlow', visning_fuldt_navn: 'Carl Reventlow', visning_foedt: null, visning_doed: null, visning_titel: 'Greve', koen: 'mand', privat: false },
    { id: 2, visning_navn: 'Anna Hansen', visning_fuldt_navn: 'Anna Hansen', visning_foedt: null, visning_doed: null, visning_titel: null, koen: 'kvinde', privat: false },
  ],
  family_member: [
    { family_id: 10, person_id: 1, rolle: 'partner', ordinal: null, konfidens: null },
    { family_id: 10, person_id: 2, rolle: 'partner', ordinal: null, konfidens: null },
  ],
  lineage: [
    { id: 1, source_id: 1, kode: 'I', navn: 'Den grevelige Linje', canonical_label: null, slaegt_id: 1, slaegtsnavn: 'Reventlow', parent_lineage_id: null },
  ],
  source: [{ id: 1, slags: 'DAA-udgave', titel: 'DAA', udgave: '2018-20', aar: 2018, ekstern: false }],
};
const KOORD = {
  person_id: 1, source_id: 1, legacy_line_code: 'I', printed_number: 15, printed_number_label: '15',
  generation_local: 3, generation_global: 7, kuld_label: null, provenance_kind: 'placement', printed_page: null,
};

function kaede(rows: unknown[]) {
  const q: Record<string, unknown> = {};
  for (const m of ['select', 'eq', 'in', 'or', 'order', 'not', 'is']) q[m] = () => q;
  q.range = async (a: number, b: number) => ({ data: rows.slice(a, b + 1), error: null });
  q.then = (res: (v: unknown) => unknown, rej?: (e: unknown) => unknown) => Promise.resolve({ data: rows, error: null }).then(res, rej);
  return q;
}

vi.mock('../../supabase', () => ({
  supabase: {
    from: (t: string) => kaede(TABELLER[t] ?? []),
    rpc: (fn: string) => fn === 'public_person_source_coordinates_samlet'
      ? { then: (res: (v: unknown) => unknown, rej?: (e: unknown) => unknown) => Promise.resolve({ data: [KOORD], error: null }).then(res, rej) }
      : kaede([]),
  },
}));

const { loadModel } = await import('../model');

describe('loadModel: slægtsrodens navn', () => {
  it('sætter model.slaegtsnavn, så hustruen får »gift grevinde Reventlow« uden adelsnavn-regel', async () => {
    const model = await loadModel({ collapse: false });
    expect(model.slaegtsnavn).toBe('Reventlow');
    expect(model.adelsnavne).toEqual({});
    expect(model.skilsmisser).toEqual({});
    expect(byggStatuslinje(model, '2', null)).toBe('Gift grevinde Reventlow');
  });
});
