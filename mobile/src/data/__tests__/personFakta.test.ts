// Paritetsplanens batch 7: fakta med kilde pr. udgave på personskærmen. Eksemplet er den foldede person 446
// (DAA 2018-20) = 1337 (DAA 1939): rækkerne skal være præcis dem, web's byggUdgaveFakta giver for samme input.
import {
  buildModel, byggUdgaveFakta, SLUKKET_ENIGHED, type PublicPersonFactRow, type RawLineageContext,
} from '@daa/core';
import { byggFaktaInput, FAKTA_BID, hentFaktaRaekker, hentFritekstKilde, hentPersonFakta } from '../personFakta';
import { byggPersonUdgave } from '../personUdgave';
import type { Model, RawExtId, RawSource } from '../types';
import { byggUdgaveLag } from '../udgaveLag';

const sources: RawSource[] = [
  { id: 1, slags: 'DAA-udgave', titel: 'Danmarks Adels Aarbog 1939', udgave: 'DAA 1939', aar: 1939, ekstern: null },
  { id: 2, slags: 'DAA-udgave', titel: 'Danmarks Adels Aarbog 2018-20', udgave: 'DAA 2018-20', aar: 2018, ekstern: null },
];
const lineageRows: RawLineageContext[] = [{ id: 50, source_id: 2, kode: 'V', navn: 'Den grevelige Linje af 1673', slaegt_id: 1 }];
const schemeRows = { schemes: [], entries: [], mappings: [] };
const extIds: RawExtId[] = [
  { person_id: 446, source_id: 2, linje: 'V', nr: 148, provenance: 'placement' },
  { person_id: 1337, source_id: 1, linje: 'IV', nr: 3, provenance: 'placement' },
];
const db = { persons: [{ id: '446', name: 'A', born: 1900, died: null, years: '1900', title: '', bio: '', privat: false }], unions: [], parentChild: [] };
const model: Model = { ...buildModel(db), ...byggUdgaveLag({ extIds, sources, lineageRows, schemeRows }, { '1337': '446' }) };
const mergedFrom = [{ personId: '1337' }] as never;

let next = 1;
const row = (o: Partial<PublicPersonFactRow>): PublicPersonFactRow => {
  const id = next++;
  return {
    person_id: 446, fact_id: id, faktatype: 'død', conclusion_status: 'afklaret', assertion_id: id, chosen: true,
    vaerdi_tekst: null, date_raw: '1850', date_min: null, date_max: null, date_qualifier: null, date_certainty: null,
    source_id: 2, source_label: 'DAA 2018-20', side: null, record_ref: null, record_label: null, citation_label: null,
    ...o,
  };
};
const ROWS: PublicPersonFactRow[] = [
  row({ faktatype: 'fødsel', date_raw: '12.3.1780' }),
  row({ faktatype: 'død', date_raw: '1850' }),
  row({ person_id: 1337, faktatype: 'fødsel', date_raw: '12.3.1781', source_id: 1, source_label: 'DAA 1939' }),
  row({ person_id: 1337, faktatype: 'dåb', date_raw: '20.3.1781', source_id: 1, source_label: 'DAA 1939' }),
  // Redaktørens faktum uden bogkilde: fritekstkilden hentes fra citation.
  row({ faktatype: 'titel', vaerdi_tekst: 'Kammerherre', date_raw: null, source_id: null, source_label: null }),
];

type Kald = { rpc: number[][]; citation: number[][] };
function fakeSb(o: { rpc?: 'fejl' | 'kast' | PublicPersonFactRow[]; citation?: 'fejl' | unknown[] } = {}) {
  const kald: Kald = { rpc: [], citation: [] };
  const sb = {
    rpc: async (navn: string, args: { p_person_ids: number[] }) => {
      expect(navn).toBe('public_person_facts');
      kald.rpc.push(args.p_person_ids);
      if (o.rpc === 'kast') throw new Error('netfejl');
      if (o.rpc === 'fejl') return { data: null, error: { code: '57014', message: 'statement timeout' } };
      const ids = new Set(args.p_person_ids.map(String));
      return { data: (o.rpc ?? ROWS).filter((r) => ids.has(String(r.person_id))), error: null };
    },
    from: (tabel: string) => {
      expect(tabel).toBe('citation');
      const b: Record<string, unknown> = {
        select: () => b,
        is: () => b,
        in: async (_k: string, ids: number[]) => {
          kald.citation.push(ids);
          if (o.citation === 'fejl') return { data: null, error: { message: 'nej' } };
          return { data: o.citation ?? ids.map((id) => ({ assertion_id: id, citat_tekst: 'Rigsarkivet, kammerherreudnævnelse' })), error: null };
        },
      };
      return b;
    },
  };
  return { sb: sb as never, kald };
}

describe('hentPersonFakta', () => {
  test('alle medlems-id\'er i ét kald (få id\'er), fritekstkilden for redaktørens faktum', async () => {
    const { sb, kald } = fakeSb();
    const r = await hentPersonFakta(sb, '446', mergedFrom, model);
    expect(r.fejl).toBe(false);
    expect(kald.rpc).toEqual([[446, 1337]]);
    expect(r.input!.rows).toHaveLength(ROWS.length);
    expect(r.input!.fritekstKilde).toEqual({ [String(ROWS[4].assertion_id)]: ['Rigsarkivet, kammerherreudnævnelse'] });
  });

  test('rækkerne er de samme som byggUdgaveFakta giver på web for samme person og udgave', async () => {
    const { sb } = fakeSb();
    const r = await hentPersonFakta(sb, '446', mergedFrom, model);
    const web = (valgt: string | null) => byggUdgaveFakta({
      rows: ROWS, udgaver: model.udgaver ?? [], udgaveForPersonRaekke: model.udgaveForPersonRaekke ?? {},
      fritekstKilde: { [String(ROWS[4].assertion_id)]: ['Rigsarkivet, kammerherreudnævnelse'] }, slukketEnighed: SLUKKET_ENIGHED,
    }, valgt);
    const basis = { bioVersions: [], fallbackBio: '', fallbackKilder: [], faktaInput: r.input };
    const ny = byggPersonUdgave(model, '446', { ...basis, valgtUdgaveId: null });
    expect(ny.valgtUdgave).toBe('2');
    expect(ny.faktaVisning).toEqual(web('2'));
    expect(ny.faktaVisning!.linjer.length).toBeGreaterThan(0);
    const gammel = byggPersonUdgave(model, '446', { ...basis, valgtUdgaveId: '1' });
    expect(gammel.faktaVisning).toEqual(web('1'));
  });

  test('få id\'er pr. kald: højst FAKTA_BID', async () => {
    const { sb, kald } = fakeSb({ rpc: [] });
    const ids = Array.from({ length: 45 }, (_, i) => String(i + 1));
    expect(await hentFaktaRaekker(sb, ids)).toEqual([]);
    expect(kald.rpc.map((b) => b.length)).toEqual([FAKTA_BID, FAKTA_BID, 5]);
    expect(FAKTA_BID).toBeLessThanOrEqual(20);
  });

  test.each(['fejl', 'kast'] as const)('RPC\'en fejler (%s) → fejl, ingen fakta', async (art) => {
    const { sb } = fakeSb({ rpc: art });
    expect(await hentPersonFakta(sb, '446', mergedFrom, model)).toEqual({ input: null, fejl: true });
  });

  test('ingen klient (offline) → fejl', async () => {
    expect(await hentPersonFakta(null, '446', mergedFrom, model)).toEqual({ input: null, fejl: true });
  });

  test('fritekstkilden er tolerant: en fejl giver {} og fakta står stadig', async () => {
    const { sb } = fakeSb({ citation: 'fejl' });
    expect(await hentFritekstKilde(sb, ROWS)).toEqual({});
    const r = await hentPersonFakta(sb, '446', mergedFrom, model);
    expect(r.fejl).toBe(false);
    expect(r.input!.fritekstKilde).toEqual({});
  });

  test('byggFaktaInput har samme felter som på web', () => {
    expect(byggFaktaInput(ROWS, model, {})).toEqual({
      rows: ROWS, udgaver: model.udgaver, udgaveForPersonRaekke: model.udgaveForPersonRaekke, fritekstKilde: {}, slukketEnighed: SLUKKET_ENIGHED,
    });
  });
});

describe('udgavevælgeren (batch 7)', () => {
  const basis = { bioVersions: [], valgtUdgaveId: null, fallbackBio: '', fallbackKilder: [] };
  test('med fakta: udgaverne med fakta (som web)', () => {
    const kun2018 = byggFaktaInput(ROWS.filter((r) => r.person_id === 446), model, {});
    expect(byggPersonUdgave(model, '446', { ...basis, faktaInput: kun2018 }).vaelger.chips.map((c) => c.label)).toEqual(['DAA 2018-20']);
    expect(byggPersonUdgave(model, '446', { ...basis, faktaInput: byggFaktaInput(ROWS, model, {}) }).vaelger.chips.map((c) => c.label))
      .toEqual(['DAA 2018-20', 'DAA 1939']);
  });
  test('før fakta er hentet (eller ved fejl): udgaverne med en bogpost', () => {
    const v = byggPersonUdgave(model, '446', { ...basis, faktaInput: null });
    expect(v.vaelger.chips.map((c) => c.label)).toEqual(['DAA 2018-20', 'DAA 1939']);
    expect(v.faktaVisning).toBeNull();
  });
});
