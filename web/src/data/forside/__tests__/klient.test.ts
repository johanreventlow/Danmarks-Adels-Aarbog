import { afterEach, describe, expect, it, vi } from 'vitest';
import { hentForsideData } from '../klient';

const NU = Date.parse('2026-11-24T10:00:00.000Z');
const del = (data: unknown) => ({ komplet: true, data });
const gyldig = (o: Record<string, unknown> = {}) => ({
  version: 1, genereret: new Date(NU - 3600_000).toISOString(), personIder: ['1'],
  bios: del({ kontrakt: 2, rows: [], fejlede: [] }), haendelser: del({ rows: [], narrativer: [], sources: [] }),
  livsdato: del({ facts: [], conclusions: [], assertions: [] }), historier: del({ rows: [], kilder: [], sources: [] }),
  naevnt: del([[], [], []]), ...o,
});
const svar = (body: string, status = 200, type = 'application/json') =>
  vi.fn(async () => new Response(body, { status, headers: { 'content-type': type } })) as unknown as typeof fetch;

afterEach(() => { vi.useRealTimers(); });

describe('hentForsideData', () => {
  it('gyldig fil returneres', async () => {
    const fd = await hentForsideData({ fetchFn: svar(JSON.stringify(gyldig())), nu: () => NU });
    expect(fd?.version).toBe(1);
    expect(fd?.personIder).toEqual(['1']);
  });

  it('langsom server: null efter fristen', async () => {
    vi.useFakeTimers();
    const evig = vi.fn((_: unknown, init?: RequestInit) => new Promise<Response>((_res, rej) => {
      init?.signal?.addEventListener('abort', () => rej(new DOMException('afbrudt', 'AbortError')));
    })) as unknown as typeof fetch;
    const p = hentForsideData({ fetchFn: evig, fristMs: 2000, nu: () => NU });
    await vi.advanceTimersByTimeAsync(2001);
    expect(await p).toBeNull();
  });

  it('HTML-svar (rewrite til index.html) giver null', async () => {
    expect(await hentForsideData({ fetchFn: svar('<!doctype html><html></html>', 200, 'text/html'), nu: () => NU })).toBeNull();
  });

  it('forkert version giver null', async () => {
    expect(await hentForsideData({ fetchFn: svar(JSON.stringify(gyldig({ version: 2 }))), nu: () => NU })).toBeNull();
  });

  it('fil ældre end 48 timer giver null', async () => {
    const gammel = gyldig({ genereret: new Date(NU - 49 * 3600_000).toISOString() });
    expect(await hentForsideData({ fetchFn: svar(JSON.stringify(gammel)), nu: () => NU })).toBeNull();
  });

  it('503 giver null', async () => {
    expect(await hentForsideData({ fetchFn: svar(JSON.stringify(gyldig()), 503), nu: () => NU })).toBeNull();
  });

  it('manglende del giver null', async () => {
    const { haendelser: _udeladt, ...uden } = gyldig();
    expect(await hentForsideData({ fetchFn: svar(JSON.stringify(uden)), nu: () => NU })).toBeNull();
  });
});
