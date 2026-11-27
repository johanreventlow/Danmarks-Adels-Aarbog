// Review 37 C3: sikkerhedsheaderne i web/vercel.json. CSP'en håndhæves (ikke kun Report-Only),
// og de direktiver, der bærer beskyttelsen, må ikke forsvinde stille ved en senere redigering.
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

type Header = { key: string; value: string };
const cfg = JSON.parse(readFileSync(new URL('../../vercel.json', import.meta.url), 'utf8')) as {
  headers: { source: string; headers: Header[] }[];
};
const alle = cfg.headers.find((h) => h.source === '/(.*)')?.headers ?? [];
const csp = alle.filter((h) => h.key.toLowerCase().startsWith('content-security-policy'));

function direktiver(v: string): Map<string, string[]> {
  return new Map(
    v.split(';').map((d) => d.trim()).filter(Boolean).map((d) => {
      const [navn, ...kilder] = d.split(/\s+/);
      return [navn, kilder] as [string, string[]];
    }),
  );
}

describe('vercel.json: CSP', () => {
  it('har præcis én CSP-header, og den håndhæves', () => {
    expect(csp.map((h) => h.key)).toEqual(['Content-Security-Policy']);
  });

  it('script-src er kun self (ingen unsafe-inline/unsafe-eval)', () => {
    const d = direktiver(csp[0].value);
    expect(d.get('default-src')).toEqual(["'self'"]);
    expect(d.get('script-src')).toEqual(["'self'"]);
  });

  it('bevarer ramme-, base- og objektværnet', () => {
    const d = direktiver(csp[0].value);
    expect(d.get('frame-ancestors')).toEqual(["'none'"]);
    expect(d.get('base-uri')).toEqual(["'self'"]);
    expect(d.get('object-src')).toEqual(["'none'"]);
    expect(d.get('form-action')).toEqual(["'self'"]);
  });

  it('tillader Supabase til data og billeder (ellers er siden tom)', () => {
    const d = direktiver(csp[0].value);
    expect(d.get('connect-src')).toEqual(expect.arrayContaining(['https://*.supabase.co']));
    expect(d.get('img-src')).toEqual(expect.arrayContaining(['https://*.supabase.co', 'blob:', 'data:']));
  });
});
