// Forsøg (plan Task 1): bygger Vercel en Node-funktion, der importerer workspace-pakken @daa/core (TS-kilde)?
import { getAll } from '@daa/core';
import { FORSIDE_DATA_VERSION } from '../src/data/forside/format';

export function GET(): Response {
  return new Response(JSON.stringify({ ok: true, version: FORSIDE_DATA_VERSION, getAll: typeof getAll }), {
    status: 200,
    headers: { 'content-type': 'application/json', 'cache-control': 'no-store' },
  });
}
