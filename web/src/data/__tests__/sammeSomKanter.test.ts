// Review 37 Y2: opstarten hentede ALLE afklarede relationskonklusioner (prod 24/11: ~2.300 rækker i 3 offset-sider,
// hver ~630 ms som gæst pga. RLS-kaskaden) for kun at bruge dem til samme_som. Nu hentes kun konklusionerne for
// samme_som-relationerne, i bidder. En fejl må ikke længere give tavse dubletpersoner.
import { describe, expect, it, vi } from 'vitest';
import { hentSammeSomKanter, hentSammeSomKanterMedGenforsoeg } from '../sammeSomKanter';
import type { Sb } from '../forside/kilder';

type Kald = { tabel: string; eq: [string, unknown][]; in?: [string, unknown[]] };

function fake(opts: {
  relationer: { id: number; subjekt_id: number; objekt_id: number }[];
  afklarede: number[];
  fejlPaaKonklusion?: number; // antal konklusionskald, der fejler, før de lykkes
  fejlPaaRelation?: number;
}) {
  const kald: Kald[] = [];
  let konklFejl = opts.fejlPaaKonklusion ?? 0;
  let relFejl = opts.fejlPaaRelation ?? 0;
  const sb = {
    from: (tabel: string) => {
      const k: Kald = { tabel, eq: [] };
      kald.push(k);
      const q: Record<string, unknown> = {};
      q.select = () => q;
      q.order = () => q;
      q.eq = (c: string, v: unknown) => { k.eq.push([c, v]); return q; };
      q.in = (c: string, v: unknown[]) => { k.in = [c, v]; return q; };
      const svar = () => {
        if (tabel === 'relation') {
          if (relFejl > 0) { relFejl--; return { data: null, error: { message: 'relation-fejl' } }; }
          return { data: opts.relationer, error: null };
        }
        if (konklFejl > 0) { konklFejl--; return { data: null, error: { message: 'konklusion-fejl' } }; }
        const ids = (k.in?.[1] ?? []).map(String);
        return { data: opts.afklarede.filter((id) => ids.includes(String(id))).map((id) => ({ target_id: id })), error: null };
      };
      q.range = async (a: number, b: number) => {
        const s = svar();
        return s.error ? s : { data: (s.data as unknown[]).slice(a, b + 1), error: null };
      };
      q.then = (res: (v: unknown) => unknown, rej?: (e: unknown) => unknown) => Promise.resolve(svar()).then(res, rej);
      return q;
    },
    rpc: () => { throw new Error('ingen rpc forventet'); },
  } as unknown as Sb;
  return { sb, kald };
}

const rel = (n: number) => Array.from({ length: n }, (_, i) => ({ id: 1000 + i, subjekt_id: 1 + i, objekt_id: 5000 + i }));

describe('hentSammeSomKanter (review 37 Y2)', () => {
  it('henter kun konklusioner for samme_som-relationerne, afgrænset til afklarede relationskonklusioner', async () => {
    const { sb, kald } = fake({ relationer: rel(3), afklarede: [1000, 1002] });
    const kanter = await hentSammeSomKanter(sb);
    expect(kanter).toEqual([
      { alias: '1', canonical: '5000' },
      { alias: '3', canonical: '5002' },
    ]);
    const konkl = kald.filter((k) => k.tabel === 'conclusion');
    expect(konkl).toHaveLength(1);
    expect(konkl[0].eq).toEqual(expect.arrayContaining([['target_type', 'relation'], ['status', 'afklaret']]));
    // id'er sendes som strenge (bigint > 2^53 må ikke gå gennem Number()).
    expect(konkl[0].in).toEqual(['target_id', ['1000', '1001', '1002']]);
  });

  it('deler id-listen i bidder à højst 200', async () => {
    const { sb, kald } = fake({ relationer: rel(450), afklarede: rel(450).map((r) => r.id) });
    const kanter = await hentSammeSomKanter(sb);
    expect(kanter).toHaveLength(450);
    const bidder = kald.filter((k) => k.tabel === 'conclusion').map((k) => k.in![1].length);
    expect(bidder.sort((a, b) => b - a)).toEqual([200, 200, 50]);
  });

  it('ingen samme_som-relationer → ingen konklusionskald', async () => {
    const { sb, kald } = fake({ relationer: [], afklarede: [] });
    expect(await hentSammeSomKanter(sb)).toEqual([]);
    expect(kald.filter((k) => k.tabel === 'conclusion')).toHaveLength(0);
  });

  it('én fejlet bid er en fejl for det hele (en halv sammenfoldning er værre end ingen)', async () => {
    const { sb } = fake({ relationer: rel(450), afklarede: rel(450).map((r) => r.id), fejlPaaKonklusion: 1 });
    await expect(hentSammeSomKanter(sb)).rejects.toThrow('konklusion-fejl');
  });
});

describe('hentSammeSomKanterMedGenforsoeg', () => {
  it('prøver én gang til efter en fejl', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const { sb } = fake({ relationer: rel(2), afklarede: [1000, 1001], fejlPaaRelation: 1 });
    expect(await hentSammeSomKanterMedGenforsoeg(sb, 0)).toHaveLength(2);
    expect(warn).toHaveBeenCalledTimes(1);
    warn.mockRestore();
  });

  it('fejler stadig efter genforsøget → afviser (ingen tavse dubletpersoner)', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const { sb } = fake({ relationer: rel(2), afklarede: [1000, 1001], fejlPaaKonklusion: 2 });
    await expect(hentSammeSomKanterMedGenforsoeg(sb, 0)).rejects.toThrow('konklusion-fejl');
    warn.mockRestore();
  });
});
