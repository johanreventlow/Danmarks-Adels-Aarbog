// Minimal PostgREST/Supabase-emulator til Playwright page.route — svarer fra fixture.json,
// rører aldrig en rigtig database. Dækker select (inkl. embeds og ::text), eq/neq/in/is/not,
// order, limit/offset/Range og single-objekt. RPC'er uden stub svarer [] (tom liste).
import fs from 'node:fs';
const FIX = JSON.parse(fs.readFileSync(process.env.FIXTURE, 'utf8'));
const DB = { ...FIX, profiles: [], bookmark: [], slaegt: [{ id: 1, navn: 'Reventlow' }], vocab: [], media: [], media_variant: [],
  haendelse: [], story: [], story_kilde: [], feed_pin: [], note: [], person_external_id: [], lineage_scheme: [], lineage_scheme_entry: [],
  lineage_scheme_entry_lineage: [], red_foraeldre_konflikt: [], historical_event: [], repository: [], suggestion: [] };
export const state = { role: null, fail: false, userId: '00000000-0000-4000-8000-000000000001', email: 'test@example.test' };

function splitTop(s) { const out = []; let d = 0, cur = ''; for (const c of s) { if (c === '(') d++; if (c === ')') d--; if (c === ',' && !d) { out.push(cur); cur = ''; } else cur += c; } if (cur) out.push(cur); return out.map((x) => x.trim()).filter(Boolean); }
function parseSelect(s) {
  return splitTop(s || '*').map((it) => {
    const m = it.match(/^(?:([\w]+):)?([\w!]+)(?:\((.*)\))?$/s) || it.match(/^([\w]+)::\w+$/);
    if (it.includes('::') && !it.includes('(')) { const [c] = it.split('::'); return { col: c, as: c, cast: true }; }
    if (!m) return { col: it, as: it };
    const [, alias, name, sub] = m;
    if (sub !== undefined) return { embed: name.split('!')[0], as: alias || name.split('!')[0], sub: parseSelect(sub) };
    return { col: name, as: alias || name };
  });
}
function project(table, row, sel) {
  if (sel.length === 1 && sel[0].col === '*') return { ...row };
  const o = {};
  for (const f of sel) {
    if (f.col === '*') Object.assign(o, row);
    else if (f.embed) {
      const name = f.embed;
      if (name.endsWith('_id') || row[name + '_id'] !== undefined) {
        const fk = name.endsWith('_id') ? name : name + '_id';
        const tt = name.endsWith('_id') ? name.slice(0, -3) : name;
        const target = (DB[tt] || []).find((r) => String(r.id) === String(row[fk]));
        o[f.as] = target ? project(tt, target, f.sub) : null;
      } else {
        o[f.as] = (DB[name] || []).filter((r) => String(r[table + '_id']) === String(row.id)).map((r) => project(name, r, f.sub));
      }
    } else o[f.as] = f.cast ? (row[f.col] == null ? null : String(row[f.col])) : (row[f.col] ?? null);
  }
  return o;
}
function parseList(v) { return v.replace(/^\(|\)$/g, '').split(',').map((x) => x.replace(/^"|"$/g, '')); }
function test(row, col, expr) {
  let neg = false; if (expr.startsWith('not.')) { neg = true; expr = expr.slice(4); }
  const i = expr.indexOf('.'); const op = expr.slice(0, i); const v = expr.slice(i + 1); const x = row[col];
  let r;
  switch (op) {
    case 'eq': r = String(x) === v; break; case 'neq': r = String(x) !== v; break;
    case 'in': r = parseList(v).includes(String(x)); break;
    case 'is': r = v === 'null' ? x == null : v === 'true' ? x === true : v === 'false' ? x === false : false; break;
    case 'gt': r = x > Number(v); break; case 'gte': r = x >= Number(v); break; case 'lt': r = x < Number(v); break; case 'lte': r = x <= Number(v); break;
    case 'ilike': case 'like': r = new RegExp('^' + v.replace(/[%*]/g, '.*') + '$', 'i').test(String(x ?? '')); break;
    default: r = true;
  }
  return neg ? !r : r;
}
// Biografi og fakta til personsiden (fase 3) for én person, så touren kan vise de udfyldte sektioner.
// Teksten er tydeligt testdata, ikke Aarbogens ord.
const TOUR_PERSON = 240;
const kunTourPerson = (args, rows) => ((args.p_person_ids ?? []).map(Number).includes(TOUR_PERSON) ? rows : []);
const faktaRaekke = (id, faktatype, o) => ({ person_id: TOUR_PERSON, fact_id: id, faktatype, conclusion_status: 'afklaret', assertion_id: id, chosen: true,
  vaerdi_tekst: null, date_raw: null, date_min: null, date_max: null, date_qualifier: null, date_certainty: null,
  source_id: 1, source_label: 'DAA 1939', side: '540', record_ref: null, record_label: null, citation_label: 'DAA 1939, s. 540', ...o });
const RPC = {
  public_person_bio_source_versions_v2: (args) => kunTourPerson(args, [{
    person_id: TOUR_PERSON, source_id: 1, source_year: 1939, record_order: 1, source_record_ref: 'tour-rec-1',
    source_label: 'DAA 1939', record_label: 'Testpost', citation_label: 'DAA 1939, s. 540', provenance_kind: 'source_record',
    narrative_text: 'Testbiografi til designtouren: her står personens biografi ordret, som Aarbogen skriver den, med kilde under. Teksten er pladsholder og ikke Aarbogens ord.',
  }, {
    // Anden udgave, så udgavevælgeren kan ses.
    person_id: TOUR_PERSON, source_id: 2, source_year: 2018, record_order: 1, source_record_ref: 'tour-rec-2',
    source_label: 'DAA 2018-20', record_label: 'Testpost 2', citation_label: 'DAA 2018-20, s. 201', provenance_kind: 'source_record',
    narrative_text: 'Testbiografi fra en anden udgave (pladsholder): vælgeren skifter mellem udgavernes tekster.',
  }]),
  public_person_facts: (args) => kunTourPerson(args, [
    faktaRaekke(900001, 'fødsel', { date_raw: '[testdato] 1700' }),
    faktaRaekke(900002, 'død', { date_raw: '[testdato] 1760' }),
    faktaRaekke(900003, 'titel', { vaerdi_tekst: 'Lensgreve' }),
  ]),
  public_person_source_coordinates: () => DB.coords,
  public_family_sources: () => [],
  narrative_record_contract_version: () => 2,
  hist_for_subjekt: () => [], hist_for_subjekter: () => [],
};
function json(route, status, body, headers = {}) { return route.fulfill({ status, contentType: 'application/json', headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-expose-headers': 'Content-Range', ...headers }, body: JSON.stringify(body) }); }
function b64(o) { return Buffer.from(JSON.stringify(o)).toString('base64url'); }
function session() {
  const exp = Math.floor(Date.now() / 1000) + 36000;
  const user = { id: state.userId, aud: 'authenticated', role: 'authenticated', email: state.email, app_metadata: {}, user_metadata: {}, created_at: '2026-01-01T00:00:00Z' };
  return { access_token: b64({ alg: 'none' }) + '.' + b64({ sub: state.userId, exp, role: 'authenticated', email: state.email }) + '.x', token_type: 'bearer', expires_in: 36000, expires_at: exp, refresh_token: 'r', user };
}
export const log = [];
export async function handle(route) {
  const req = route.request(); const u = new URL(req.url()); const p = u.pathname;
  if (req.method() === 'OPTIONS') return json(route, 200, {});
  if (p.startsWith('/auth/v1/token')) return json(route, 200, session());
  if (p.startsWith('/auth/v1/user')) return json(route, 200, session().user);
  if (p.startsWith('/auth/v1/logout')) return route.fulfill({ status: 204, body: '' });
  if (p.startsWith('/storage/')) return route.fulfill({ status: 404, body: '' });
  if (p.startsWith('/rest/v1/rpc/')) {
    const name = p.split('/').pop();
    const fn = RPC[name]; if (!fn) log.push('rpc uden stub: ' + name); return json(route, 200, fn ? fn(req.postDataJSON?.() || {}) : []);
  }
  if (!p.startsWith('/rest/v1/')) return route.fulfill({ status: 404, body: '' });
  if (state.fail) return json(route, 500, { message: 'upstream connect error (designtour: simuleret dvale)' });
  const table = p.slice('/rest/v1/'.length);
  if (req.method() !== 'GET' && req.method() !== 'HEAD') { log.push('WRITE ' + req.method() + ' ' + table); return json(route, 201, []); }
  if (table === 'profiles') DB.profiles = state.role ? [{ id: state.userId, rolle: state.role, reventlow_person_id: null }] : [];
  let rows = (DB[table] || []).slice(); if (!DB[table]) log.push('ukendt tabel ' + table);
  let sel = '*', order = null, limit = null, offset = 0;
  for (const [k, v] of u.searchParams) {
    if (k === 'select') sel = v; else if (k === 'order') order = v; else if (k === 'limit') limit = Number(v); else if (k === 'offset') offset = Number(v);
    else if (k === 'or' || k === 'and') {} else rows = rows.filter((r) => test(r, k, v));
  }
  if (order) { const [c, dir] = order.split(',')[0].split('.'); rows.sort((a, b) => ((a[c] ?? '') > (b[c] ?? '') ? 1 : (a[c] ?? '') < (b[c] ?? '') ? -1 : 0) * (dir === 'desc' ? -1 : 1)); }
  const rh = req.headers()['range']; if (rh) { const [a, b] = rh.split('-').map(Number); offset = a; limit = b - a + 1; }
  const total = rows.length; rows = rows.slice(offset, limit != null ? offset + limit : undefined);
  const parsed = parseSelect(sel); const out = rows.map((r) => project(table, r, parsed));
  const single = (req.headers()['accept'] || '').includes('vnd.pgrst.object');
  if (single) return out.length ? json(route, 200, out[0]) : json(route, 406, { code: 'PGRST116', message: 'no rows' });
  return json(route, 200, out, { 'content-range': `${offset}-${offset + out.length - 1}/${total}` });
}
