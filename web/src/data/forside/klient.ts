// Browseren henter forsidens færdigpakkede fil (spec 2026-11-24-forside-data-cache-design.md). `null` betyder »brug den
// direkte hentning«: for langsom (kold cache efter deploy), fejl, ikke-JSON (fx index.html, hvis /api/ blev omskrevet),
// forkert version, manglende dele eller ældre end 48 timer (fx efter en pause i free tier).
import { FORSIDE_DATA_VERSION, type ForsideData } from './format';

export const MAKS_ALDER_MS = 48 * 3600_000;
const DELE = ['bios', 'haendelser', 'livsdato', 'historier', 'naevnt'] as const;

function erDel(v: unknown): boolean {
  return typeof v === 'object' && v !== null && typeof (v as Record<string, unknown>).komplet === 'boolean'
    && 'data' in (v as Record<string, unknown>);
}

function erForsideData(v: unknown, nu: number): v is ForsideData {
  if (typeof v !== 'object' || v === null) return false;
  const fd = v as Record<string, unknown>;
  if (fd.version !== FORSIDE_DATA_VERSION || typeof fd.genereret !== 'string' || !Array.isArray(fd.personIder)) return false;
  const tid = Date.parse(fd.genereret);
  if (!Number.isFinite(tid) || nu - tid > MAKS_ALDER_MS) return false;
  return DELE.every((d) => erDel(fd[d]));
}

export async function hentForsideData(opts: {
  url?: string; fristMs?: number; nu?: () => number; fetchFn?: typeof fetch;
} = {}): Promise<ForsideData | null> {
  const { url = '/api/forside-data', fristMs = 2000, nu = Date.now, fetchFn = (u, i) => fetch(u, i) } = opts;
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), fristMs);
  try {
    const res = await fetchFn(url, { signal: ctrl.signal });
    if (!res.ok || !(res.headers.get('content-type') ?? '').includes('application/json')) return null;
    const v: unknown = await res.json();
    return erForsideData(v, nu()) ? v : null;
  } catch (e) {
    console.warn('[forside-data] bruger direkte hentning:', e);
    return null;
  } finally {
    clearTimeout(timer);
  }
}
