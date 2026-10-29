// node --test web/scripts/verify-public-rpcs.test.mjs — hermetisk: den rigtige supabase-js med en falsk fetch, så
// pagineringen afprøves præcis som klienten sender den (offset/limit på RPC-POST, Range på tabel-GET).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';
import { BID, hentAlle, maalGate, sammenlign } from './verify-public-rpcs.mjs';

const NOEGLE = 'hemmelig-test-noegle-123';

// Svarer med sider ud fra den anmodede offset/limit (RPC) eller Range-header (tabel).
function falskFetch({ total, fejlPaaSide } = {}) {
  const kald = [];
  const fetch = async (input, init = {}) => {
    const url = new URL(typeof input === 'string' ? input : input.url);
    const headers = new Headers(init.headers);
    let from = 0; let to = 0;
    if (url.searchParams.has('offset')) {
      from = Number(url.searchParams.get('offset')); to = from + Number(url.searchParams.get('limit')) - 1;
    } else if (headers.get('range')) {
      [from, to] = headers.get('range').split('-').map(Number);
    }
    const side = Math.floor(from / 1000) + 1;
    kald.push({ sti: url.pathname, from, to, side });
    if (fejlPaaSide === side) return new Response(JSON.stringify({ message: 'boom' }), { status: 500, headers: { 'content-type': 'application/json' } });
    const n = Math.max(0, Math.min(to, total - 1) - from + 1);
    const rows = Array.from({ length: n }, (_, i) => ({ id: from + i, provenance_kind: 'placement' }));
    return new Response(JSON.stringify(rows), { status: 200, headers: { 'content-type': 'application/json' } });
  };
  return { fetch, kald };
}

test('tre sider (1000, 1000, 17) giver 2017 rækker gennem RPC-paginering', async () => {
  const f = falskFetch({ total: 2017 });
  const sb = createClient('http://localhost:1', NOEGLE, { global: { fetch: f.fetch } });
  const rows = await hentAlle(() => sb.rpc('public_person_source_coordinates'));
  assert.equal(rows.length, 2017);
  assert.deepEqual(f.kald.map((k) => k.side), [1, 2, 3]);
});

test('en 500-fejl på side 2 kaster', async () => {
  const f = falskFetch({ total: 2017, fejlPaaSide: 2 });
  const sb = createClient('http://localhost:1', NOEGLE, { global: { fetch: f.fetch } });
  await assert.rejects(() => hentAlle(() => sb.rpc('public_person_source_coordinates')));
});

test('linjen sammenlignes med forventningen og indeholder ikke nøglen', async () => {
  const forventet = 'C2B11_MAAL funktioner=3 definer=2 anon=true auth=true koord=3 placement=2 legacy=1 fakta=4 bundet=1 import=2 ingen_kilde=1 uden_narrativ=1 udfald_i_alt=0 udfald_publicering=0';
  const ok = sammenlign({ koord: 3, placement: 2, legacy: 1, fakta: 4, bundet: 1, import: 2, ingen: 1 }, forventet);
  assert.match(ok.linje, /resultat=OK$/);
  assert.ok(!ok.linje.includes(NOEGLE));
  const afv = sammenlign({ koord: 3, placement: 2, legacy: 1, fakta: 5, bundet: 1, import: 3, ingen: 1 }, forventet);
  assert.match(afv.linje, /resultat=AFVIGER$/);
});

test('maalGate tæller over alle offentlige personer i bidder af BID', async () => {
  const personer = Array.from({ length: 1203 }, (_, i) => ({ id: i + 1 }));
  const bidder = [];
  const sb = {
    from: () => ({ select: () => ({ order: () => ({ range: async (a, b) => ({ data: personer.slice(a, b + 1), error: null }) }) }) }),
    rpc: (navn, args) => ({
      range: async (a, b) => {
        if (navn === 'public_person_source_coordinates') {
          const rows = [{ provenance_kind: 'placement' }, { provenance_kind: 'legacy_external_id' }];
          return { data: rows.slice(a, b + 1), error: null };
        }
        if (a === 0) bidder.push(args.p_person_ids.length);
        const rows = a === 0 ? [{ record_ref: 'r', source_id: 1 }, { record_ref: null, source_id: 1 }, { record_ref: null, source_id: null }] : [];
        return { data: rows, error: null };
      },
    }),
  };
  const t = await maalGate(sb);
  const fulde = Math.floor(1203 / BID);
  assert.deepEqual(bidder, [...Array(fulde).fill(BID), ...(1203 % BID ? [1203 % BID] : [])]);
  const n = bidder.length;
  assert.deepEqual(t, { koord: 2, placement: 1, legacy: 1, fakta: 3 * n, bundet: n, import: n, ingen: n });
});
