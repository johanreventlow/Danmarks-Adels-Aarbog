// Merge-gate for PR 2 (5c-2 + B11; runbook docs/runbooks/5c2-b11-prod.md, plan Task 8): kalder de to offentlige
// RPC'er gennem PostgREST med den offentlige nøgle (anon), pagineret som klienten (supabase-js .range), og
// sammenligner antallene med 5c2_forventet_maal.txt. Udskriver kun antal; nøglen og URL'en printes aldrig.
// Brug (fra repo-roden): node web/scripts/verify-public-rpcs.mjs   → RPC_GATE … resultat=OK|AFVIGER (exit 0|1)
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const SIDE = 1000;
const BID = 500;

// Alle rækker fra en PostgREST-forespørgsel: sider på 1000 til en kort side; en fejl kaster.
export async function hentAlle(lavForespoergsel) {
  const alle = [];
  for (let from = 0; ; from += SIDE) {
    const { data, error } = await lavForespoergsel().range(from, from + SIDE - 1);
    if (error) throw new Error(`RPC_GATE_FEJL: ${error.message ?? 'ukendt'}`);
    const rows = data ?? [];
    alle.push(...rows);
    if (rows.length < SIDE) return alle;
  }
}

export async function maalGate(sb) {
  const koord = await hentAlle(() => sb.rpc('public_person_source_coordinates'));
  const personer = await hentAlle(() => sb.from('person').select('id').order('id'));
  const ids = personer.map((p) => p.id);
  const fakta = [];
  for (let i = 0; i < ids.length; i += BID) {
    const bid = ids.slice(i, i + BID);
    fakta.push(...await hentAlle(() => sb.rpc('public_person_facts', { p_person_ids: bid })));
  }
  return {
    koord: koord.length,
    placement: koord.filter((r) => r.provenance_kind === 'placement').length,
    legacy: koord.filter((r) => r.provenance_kind === 'legacy_external_id').length,
    fakta: fakta.length,
    bundet: fakta.filter((r) => r.record_ref != null).length,
    import: fakta.filter((r) => r.record_ref == null && r.source_id != null).length,
    ingen: fakta.filter((r) => r.record_ref == null && r.source_id == null).length,
  };
}

// Gaten bruger målingens felter; »ingen« hedder ingen_kilde i maal-linjen.
const FELT = { koord: 'koord', placement: 'placement', legacy: 'legacy', fakta: 'fakta', bundet: 'bundet', import: 'import', ingen: 'ingen_kilde' };

export function sammenlign(t, forventetLinje) {
  const forv = Object.fromEntries([...forventetLinje.matchAll(/(\w+)=(\S+)/g)].map((m) => [m[1], m[2]]));
  const ok = Object.entries(FELT).every(([k, f]) => String(t[k]) === forv[f]);
  const linje = 'RPC_GATE ' + Object.keys(FELT).map((k) => `${k}=${t[k]}`).join(' ') + ` resultat=${ok ? 'OK' : 'AFVIGER'}`;
  return { ok, linje };
}

function laesEnv(sti) {
  const env = {};
  for (const l of readFileSync(sti, 'utf8').split('\n')) {
    const m = l.match(/^\s*(VITE_SUPABASE_URL|VITE_SUPABASE_ANON_KEY)\s*=\s*(.+?)\s*$/);
    if (m) env[m[1]] = m[2].replace(/^['"]|['"]$/g, '');
  }
  return env;
}

async function main() {
  const her = dirname(fileURLToPath(import.meta.url));
  const rod = join(her, '..', '..');
  const env = laesEnv(join(rod, 'web', '.env.local'));
  if (!env.VITE_SUPABASE_URL || !env.VITE_SUPABASE_ANON_KEY) throw new Error('RPC_GATE_ENV (web/.env.local mangler URL eller nøgle)');
  const { createClient } = await import('@supabase/supabase-js');
  const sb = createClient(env.VITE_SUPABASE_URL, env.VITE_SUPABASE_ANON_KEY, { auth: { persistSession: false } });
  const forventet = readFileSync(join(rod, '.claude/skills/daa-extract/scripts/5c2_forventet_maal.txt'), 'utf8').trim();
  const { ok, linje } = sammenlign(await maalGate(sb), forventet);
  console.log(linje);
  process.exit(ok ? 0 : 1);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  main().catch((e) => { console.error(String(e.message ?? e)); process.exit(1); });
}
