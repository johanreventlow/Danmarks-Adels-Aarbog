import { describe, expect, it } from 'vitest';
import { byggForsideData, forsideDataSvar } from '../byg';

type Svar = { data: unknown; error: unknown };
const NU = new Date('2026-11-24T10:00:00.000Z');
const bioRow = (id: number) => ({ person_id: id, source_id: 1, source_year: 2018, record_order: 1, source_record_ref: 'r' + id, source_label: 'DAA', record_label: 'Post', narrative_text: 'Tekst ' + id, citation_label: '', provenance_kind: 'source_record' });

// Mock-klient: tabeller svarer fast; RPC'er kan fejle pr. navn.
const klient = (o: { haendelseFejl?: boolean; bioFejlFor?: number; medieFejl?: boolean } = {}) => ({
  from(table: string) {
    const data: Record<string, unknown[]> = {
      person: [{ id: 1 }, { id: 2 }],
      fact: [], relation: [{ subjekt_id: 1 }], story: [],
    };
    const b: Record<string, unknown> = {};
    for (const m of ['select', 'eq', 'in', 'order']) b[m] = () => b;
    b.range = async (): Promise<Svar> => ({ data: data[table] ?? [], error: null });
    b.then = (resolve: (v: Svar) => void) => resolve(table === 'media' && o.medieFejl ? { data: null, error: { code: '57014' } } : { data: data[table] ?? [], error: null });
    return b;
  },
  async rpc(navn: string, args: Record<string, unknown>): Promise<Svar> {
    if (navn === 'narrative_record_contract_version') return { data: 2, error: null };
    if (navn === 'public_person_bio_source_versions_v2') {
      const ids = args.p_person_ids as number[];
      if (o.bioFejlFor != null && ids.includes(o.bioFejlFor)) return { data: null, error: { code: '57014' } };
      return { data: ids.map(bioRow), error: null };
    }
    if (navn === 'public_haendelse_feed') {
      return o.haendelseFejl ? { data: null, error: { code: '57014' } } : { data: { rows: [], narrativer: [], sources: [], naeste: null }, error: null };
    }
    return { data: null, error: { message: 'ukendt ' + navn } };
  },
});

describe('forside/byg', () => {
  it('personIder og genereret står i filen', async () => {
    const fd = await byggForsideData(klient() as never, NU);
    expect(fd.version).toBe(2);
    expect(fd.billeder).toEqual({ komplet: true, data: [] });
    expect(fd.genereret).toBe(NU.toISOString());
    expect(fd.personIder).toEqual(['1', '2']);
    expect(fd.bios).toMatchObject({ komplet: true });
  });

  it('alle dele hentet giver 200 og en times cache', async () => {
    const svar = await forsideDataSvar(klient() as never, NU);
    expect(svar.status).toBe(200);
    expect(svar.headers['cache-control']).toBe('public, s-maxage=3600, stale-while-revalidate=86400');
    expect(svar.headers['content-type']).toBe('application/json; charset=utf-8');
    expect(JSON.parse(svar.body).version).toBe(2);
  });

  it('en fejlet hændelsesbladring: nævnt ufuldstændig, 200 med kun fem minutters cache (ikke 503 ved hvert besøg)', async () => {
    const fd = await byggForsideData(klient({ haendelseFejl: true }) as never, NU);
    expect(fd.haendelser).toEqual({ komplet: false, data: null });
    expect(fd.naevnt).toEqual({ komplet: false, data: null });
    const svar = await forsideDataSvar(klient({ haendelseFejl: true }) as never, NU);
    expect(svar.status).toBe(200);
    expect(svar.headers['cache-control']).toBe('public, s-maxage=300, stale-while-revalidate=300');
  });

  it('fejlet billed-del: ufuldstændig, kun fem minutters cache', async () => {
    const fd = await byggForsideData(klient({ medieFejl: true }) as never, NU);
    expect(fd.billeder).toEqual({ komplet: false, data: null });
    const svar = await forsideDataSvar(klient({ medieFejl: true }) as never, NU);
    expect(svar.headers['cache-control']).toBe('public, s-maxage=300, stale-while-revalidate=300');
  });

  it('kan personlisten ikke hentes, er hele filen 503 uden cache', async () => {
    const sb = klient();
    const from = sb.from.bind(sb);
    sb.from = (t: string) => {
      const b = from(t) as Record<string, unknown>;
      if (t === 'person') b.range = async () => ({ data: null, error: { code: '57014' } });
      return b;
    };
    const svar = await forsideDataSvar(sb as never, NU);
    expect(svar.status).toBe(503);
    expect(svar.headers['cache-control']).toBe('no-store');
  });

  it('nævnt-grundlaget gemmer kun subjekt-id for hændelserne (filen må ikke have hændelserne to gange)', async () => {
    const sb = klient();
    const rpc = sb.rpc.bind(sb);
    sb.rpc = async (navn: string, args: Record<string, unknown>) => navn === 'public_haendelse_feed'
      ? { data: { rows: [{ id: 9, subjekt_id: 2, klausul: 'En lang klausul.', narrative_id: 1 }], narrativer: [], sources: [], naeste: null }, error: null }
      : rpc(navn, args);
    const fd = await byggForsideData(sb as never, NU);
    expect(fd.naevnt.data?.[1]).toEqual([{ subjekt_id: 2 }]);
  });

  it('delvise biografier giver 200 og fem minutters cache', async () => {
    const fd = await byggForsideData(klient({ bioFejlFor: 2 }) as never, NU);
    expect(fd.bios.komplet).toBe(false);
    expect(fd.bios.data?.fejlede).toEqual([2]);
    const svar = await forsideDataSvar(klient({ bioFejlFor: 2 }) as never, NU);
    expect(svar.status).toBe(200);
    expect(svar.headers['cache-control']).toBe('public, s-maxage=300, stale-while-revalidate=300');
  });
});
