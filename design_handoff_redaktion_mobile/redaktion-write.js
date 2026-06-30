// redaktion-write.js
// Skrive- og login-lag for redaktør-arbejdsbordet.
//  • signIn()  — Supabase Auth (e-mail/adgangskode) → access_token
//  • getRole() — slår brugerens rolle op i profiles
//  • buildPlan(change, role) — oversætter en redigering til en RÆKKE REST-kald
//      role 'redaktion' → direkte til evidens-/data-tabeller
//      ellers           → ét forslag i staging-tabellen 'suggestion'
//  • submit(plan, opts) — dry-run (returnerer planen) eller live (udfører)
//
// Kobles på fra editorens logik via:  const W = await import('./redaktion-write.js');
// Intet kører af sig selv; editoren styrer dryRun-flaget.

const REST = (url) => url.replace(/\/+$/, '') + '/rest/v1/';
const AUTH = (url) => url.replace(/\/+$/, '') + '/auth/v1/';

// --- Auth ---------------------------------------------------------------
export async function signIn(url, anonKey, email, password) {
  const r = await fetch(AUTH(url) + 'token?grant_type=password', {
    method: 'POST',
    headers: { 'apikey': anonKey, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password })
  });
  const data = await r.json();
  if (!r.ok) throw new Error(data.error_description || data.msg || data.error || 'Login mislykkedes');
  return { token: data.access_token, refresh: data.refresh_token, user: data.user };
}

export async function getRole(url, anonKey, token, userId) {
  const r = await fetch(REST(url) + 'profiles?select=rolle,reventlow_person_id&id=eq.' + encodeURIComponent(userId), {
    headers: { 'apikey': anonKey, 'Authorization': 'Bearer ' + token }
  });
  const rows = await r.json();
  return (Array.isArray(rows) && rows[0]) ? rows[0] : { rolle: 'medlem' };
}

export async function signOut(url, anonKey, token) {
  try {
    await fetch(AUTH(url) + 'logout', { method: 'POST', headers: { 'apikey': anonKey, 'Authorization': 'Bearer ' + token } });
  } catch (_) {}
}

// --- Plan-byggere -------------------------------------------------------
// En "change" er normaliseret af editoren:
//   { art, subjektType, subjektId, felt, vaerdi, kildeSourceId, kildeFritekst, payload, note }
// art ∈ fakta | narrativ | relation | gods | hverv | vaaben | medie | ny_person

export function buildPlan(change, role) {
  const c = change || {};
  const note = c.note || '';
  // Ikke-redaktion: alt går til staging som ét forslag.
  if (role !== 'redaktion') {
    return [{
      label: 'Forslag → staging (afventer godkendelse)',
      method: 'POST', table: 'suggestion',
      body: {
        art: c.art, subjekt_type: c.subjektType || 'person', subjekt_id: c.subjektId ?? null,
        felt: c.felt ?? null, vaerdi: c.vaerdi ?? null,
        kilde_source_id: c.kildeSourceId ?? null, kilde_fritekst: c.kildeFritekst ?? null,
        payload: c.payload || {}, note
      }
    }];
  }

  // Redaktion: direkte skrivning, afhængigt af art.
  switch (c.art) {
    case 'fakta':
      return [
        { label: 'Ny påstand (assertion)', method: 'POST', table: 'assertion', capture: 'assertionId',
          body: { subjekt_type: c.subjektType || 'person', subjekt_id: c.subjektId, felt: c.felt, vaerdi: c.vaerdi } },
        { label: 'Citat på påstanden', method: 'POST', table: 'citation',
          body: { assertion_id: { __ref: 'assertionId' }, source_id: c.kildeSourceId ?? null, lokation: c.kildeFritekst ?? null, note } },
        { label: 'Blåstempl: opdater konklusion', method: 'PATCH', table: 'conclusion',
          query: `subjekt_type=eq.${c.subjektType || 'person'}&subjekt_id=eq.${c.subjektId}&felt=eq.${c.felt}`,
          body: { vaerdi: c.vaerdi, valgt_assertion_id: { __ref: 'assertionId' } } }
      ];
    case 'narrativ':
      return [{ label: 'Narrativ (opret/erstat)', method: 'POST', table: 'narrative',
        prefer: 'resolution=merge-duplicates',
        body: { subjekt_type: c.subjektType || 'person', subjekt_id: c.subjektId, tekst: c.vaerdi, privat: (c.payload && c.payload.privat) || false } }];
    case 'relation':
    case 'gods':
    case 'hverv':
      return [{ label: 'Relation', method: 'POST', table: 'relation',
        body: Object.assign({ subjekt_type: c.subjektType || 'person', subjekt_id: c.subjektId }, c.payload || {}) }];
    case 'ny_person':
      return [{ label: 'Ny person', method: 'POST', table: 'person', capture: 'personId',
        body: Object.assign({ visning_navn: c.vaerdi }, c.payload || {}) }];
    default:
      // ukendt art → læg den i staging fremfor at gætte
      return [{ label: 'Forslag → staging (ukendt art)', method: 'POST', table: 'suggestion',
        body: { art: c.art || 'fakta', subjekt_type: c.subjektType || 'person', subjekt_id: c.subjektId ?? null, felt: c.felt ?? null, vaerdi: c.vaerdi ?? null, payload: c.payload || {}, note } }];
  }
}

// Saml en plan for flere ændringer på én gang.
export function buildBatchPlan(changes, role) {
  const plan = [];
  (changes || []).forEach(ch => buildPlan(ch, role).forEach(op => plan.push(op)));
  return plan;
}

// Menneskelæselig forhåndsvisning af et kald (til dry-run-panelet).
export function describeOp(url, op) {
  const path = REST(url) + op.table + (op.query ? ('?' + op.query) : '');
  return `${op.method} ${path}\n${JSON.stringify(op.body, null, 2)}`;
}

// --- Udførelse ----------------------------------------------------------
// opts = { url, anonKey, token, dryRun }
export async function submit(plan, opts) {
  const { url, anonKey, token, dryRun } = opts || {};
  if (dryRun) {
    return { dryRun: true, ok: true, plan, preview: plan.map(op => describeOp(url, op)) };
  }
  if (!token) throw new Error('Ingen redaktør-session — log ind først.');
  const refs = {};
  const results = [];
  for (const op of plan) {
    const body = resolveRefs(op.body, refs);
    const path = REST(url) + op.table + (op.query ? ('?' + op.query) : '');
    const headers = {
      'apikey': anonKey, 'Authorization': 'Bearer ' + token,
      'Content-Type': 'application/json',
      'Prefer': op.prefer ? op.prefer : (op.capture ? 'return=representation' : 'return=minimal')
    };
    const r = await fetch(path, { method: op.method, headers, body: JSON.stringify(body) });
    const text = await r.text();
    let data = null; try { data = text ? JSON.parse(text) : null; } catch (_) { data = text; }
    if (!r.ok) throw new Error(`${op.label}: ${r.status} ${typeof data === 'string' ? data : JSON.stringify(data)}`);
    if (op.capture && Array.isArray(data) && data[0] && data[0].id != null) refs[op.capture] = data[0].id;
    results.push({ label: op.label, status: r.status, data });
  }
  return { dryRun: false, ok: true, results };
}

function resolveRefs(body, refs) {
  if (body == null || typeof body !== 'object') return body;
  if (body.__ref) return refs[body.__ref];
  const out = Array.isArray(body) ? [] : {};
  for (const k in body) out[k] = resolveRefs(body[k], refs);
  return out;
}
