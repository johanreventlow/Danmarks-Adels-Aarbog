// Forsidens færdigpakkede data (spec 2026-11-24-forside-data-cache-design.md). Bygges som gæst med den offentlige
// anon-nøgle (RLS afgør, hvad der kommer med) og gemmes af Vercels CDN efter Cache-Control fra forsideDataSvar.
import { createClient } from '@supabase/supabase-js';
import { forsideDataSvar } from '../src/data/forside/byg';

export async function GET(): Promise<Response> {
  const url = process.env.VITE_SUPABASE_URL;
  const anonKey = process.env.VITE_SUPABASE_ANON_KEY;
  if (!url || !anonKey) {
    return new Response(JSON.stringify({ fejl: 'mangler konfiguration' }), {
      status: 500,
      headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
    });
  }
  const sb = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const svar = await forsideDataSvar(sb, new Date());
  return new Response(svar.body, { status: svar.status, headers: svar.headers });
}
