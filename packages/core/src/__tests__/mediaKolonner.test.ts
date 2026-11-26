// Kolonne-kontrakten for public.media (review 37 S8 + R37S8-1, #397). Læser kildefilerne som tekst (ingen database,
// intet netværk) og beviser, at hver direkte media-forespørgsel i web/src og mobile/src kun vælger og filtrerer på
// kolonner, som anon og authenticated har SELECT på (db-rls.sql-blokken $review37_s8_anon_kolonner$). En kolonne uden
// for listen giver »permission denied« i prod — også for redaktøren, da medlemmer og redaktion deler rollen
// authenticated. original_filnavn og sha256 læses kun gennem red_media_interne_felter/red_media_efter_sha.
import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { describe, expect, it } from 'vitest';

const ROD = fileURLToPath(new URL('../../../../', import.meta.url));
const INTERNE = ['original_filnavn', 'sha256'];

type App = 'web' | 'mobil';
const APPS: Record<App, { src: string; kontrakt: string; minFund: number }> = {
  web: { src: 'web/src', kontrakt: 'web/src/data/mediaKontrakt.ts', minFund: 7 },
  mobil: { src: 'mobile/src', kontrakt: 'mobile/src/data/mediaKontrakt.ts', minFund: 4 },
};

function filer(mappe: string): string[] {
  return readdirSync(mappe, { withFileTypes: true }).flatMap((e) => {
    if (e.isDirectory()) return e.name === '__tests__' || e.name === 'node_modules' ? [] : filer(path.join(mappe, e.name));
    return /\.tsx?$/.test(e.name) && !/\.test\./.test(e.name) ? [path.join(mappe, e.name)] : [];
  });
}

/** Fjerner //- og /* *\/-kommentarer, men bevarer strenge. */
function udenKommentarer(t: string): string {
  let ud = '';
  for (let i = 0; i < t.length; i++) {
    const c = t[i];
    if (c === "'" || c === '"' || c === '`') {
      const start = i;
      for (i++; i < t.length && t[i] !== c; i++) if (t[i] === '\\') i++;
      ud += t.slice(start, i + 1);
    } else if (c === '/' && t[i + 1] === '/') { while (i < t.length && t[i] !== '\n') i++; ud += '\n'; }
    else if (c === '/' && t[i + 1] === '*') { while (i < t.length && !(t[i] === '*' && t[i + 1] === '/')) i++; i++; }
    else ud += c;
  }
  return ud;
}

/** Indholdet mellem parentesen ved `start` og dens match (streng-bevidst); slutindeks efter ')'. */
function argumenter(t: string, start: number): { indhold: string; slut: number } | null {
  let dybde = 0;
  for (let i = start; i < t.length; i++) {
    const c = t[i];
    if (c === "'" || c === '"' || c === '`') { for (i++; i < t.length && t[i] !== c; i++) if (t[i] === '\\') i++; continue; }
    if (c === '(' || c === '[' || c === '{') dybde++;
    else if ((c === ')' || c === ']' || c === '}') && --dybde === 0) return { indhold: t.slice(start + 1, i), slut: i + 1 };
  }
  return null;
}

const literal = (arg: string): string | null => {
  const m = /^\s*(['"`])([^'"`$]*)\1\s*(?:,|$)/.exec(arg);
  return m ? m[2] : null;
};

/** Kolonnerne i en PostgREST-select: alias:kolonne og kolonne::type → kolonne. Embeds og '*' er fejl. */
export function selectKolonner(select: string): { kolonner: string[]; fejl: string[] } {
  const kolonner: string[] = [];
  const fejl: string[] = [];
  for (const del of select.split(',').map((d) => d.trim()).filter(Boolean)) {
    if (del.includes('(') || del.includes('*')) { fejl.push(`ikke-tilladt select-del »${del}«`); continue; }
    const uden = del.replace(/^[A-Za-z_][A-Za-z0-9_]*:(?!:)/, '').replace(/::[A-Za-z_][A-Za-z0-9_ ]*$/, '').trim();
    if (!/^[a-z_][a-z0-9_]*$/.test(uden)) { fejl.push(`ukendt select-del »${del}«`); continue; }
    kolonner.push(uden);
  }
  return { kolonner, fejl };
}

const FILTRE = new Set(['eq', 'neq', 'in', 'is', 'gt', 'gte', 'lt', 'lte', 'like', 'ilike', 'order', 'contains', 'containedBy']);
const NEUTRALE = new Set(['range', 'limit', 'maybeSingle', 'single', 'returns', 'abortSignal', 'throwOnError']);

type Fund = { sted: string; kolonner: string[]; fejl: string[] };

/** Alle media-forespørgsler i en tekst: .from('media')-kæder og spec-objekter { table: 'media', select: '…' }. */
export function mediaForespoergsler(tekst: string, sted: string): Fund[] {
  const t = udenKommentarer(tekst);
  const fund: Fund[] = [];
  for (const m of t.matchAll(/\.from\(\s*(['"`])media\1\s*\)/g)) {
    if (/storage\s*$/.test(t.slice(Math.max(0, m.index! - 12), m.index!))) continue; // storage-bucket, ikke tabellen
    const f: Fund = { sted: `${sted}@${t.slice(0, m.index!).split('\n').length}`, kolonner: [], fejl: [] };
    let i = m.index! + m[0].length;
    for (;;) {
      const k = /^\s*\.\s*([A-Za-z]+)\s*\(/.exec(t.slice(i));
      if (!k) break;
      const args = argumenter(t, i + k[0].length - 1);
      if (!args) { f.fejl.push('ubalanceret kæde'); break; }
      const metode = k[1];
      const lit = literal(args.indhold);
      if (metode === 'select') {
        if (lit == null) f.fejl.push(`select uden streng-literal: ${args.indhold.trim()}`);
        else { const s = selectKolonner(lit); f.kolonner.push(...s.kolonner); f.fejl.push(...s.fejl); }
      } else if (FILTRE.has(metode)) {
        if (lit == null) f.fejl.push(`.${metode} uden kolonne-literal`);
        else f.kolonner.push(lit.split('.')[0]);
      } else if (!NEUTRALE.has(metode)) {
        f.fejl.push(`ukendt kædemetode .${metode} (tilføj den til testen, hvis den ikke rører kolonner)`);
      }
      i = args.slut;
    }
    if (!f.kolonner.length && !f.fejl.length) f.fejl.push('ingen select fundet');
    fund.push(f);
  }
  for (const m of t.matchAll(/table:\s*(['"`])media\1\s*,\s*select:\s*(['"`])([^'"`]*)\2/g)) {
    const s = selectKolonner(m[3]);
    fund.push({ sted: `${sted}@${t.slice(0, m.index!).split('\n').length} (spec)`, kolonner: s.kolonner, fejl: s.fejl });
  }
  return fund;
}

function rlsListe(): { kolonner: string[]; modtagere: string } {
  const rls = readFileSync(path.join(ROD, 'db-rls.sql'), 'utf-8');
  const m = [...rls.matchAll(/GRANT SELECT \(([^)]*)\)\s+ON TABLE public\.media TO ([a-z, ]+);/g)];
  expect(m, 'præcis én kolonne-grant på public.media i db-rls.sql').toHaveLength(1);
  return { kolonner: m[0][1].split(',').map((c) => c.trim()), modtagere: m[0][2].trim() };
}

function appListe(app: App): string[] {
  const t = udenKommentarer(readFileSync(path.join(ROD, APPS[app].kontrakt), 'utf-8'));
  const m = /export const MEDIA_KLIENT_KOLONNER = \[([^\]]*)\]/.exec(t);
  expect(m, `${APPS[app].kontrakt} eksporterer MEDIA_KLIENT_KOLONNER`).not.toBeNull();
  return [...m![1].matchAll(/'([a-z_0-9]+)'/g)].map((x) => x[1]);
}

describe('kolonne-kontrakt for public.media', () => {
  const rls = rlsListe();

  it('db-rls.sql giver anon listen, uden de interne felter', () => {
    expect(rls.modtagere).toBe('anon');
    expect(rls.kolonner.length).toBeGreaterThan(10);
    for (const k of INTERNE) expect(rls.kolonner).not.toContain(k);
  });

  for (const app of Object.keys(APPS) as App[]) {
    describe(app, () => {
      const liste = appListe(app);
      const fund = filer(path.join(ROD, APPS[app].src)).flatMap((fil) =>
        mediaForespoergsler(readFileSync(fil, 'utf-8'), path.relative(ROD, fil)));

      it('MEDIA_KLIENT_KOLONNER er præcis db-rls.sql-listen', () => {
        expect([...liste].sort()).toEqual([...rls.kolonner].sort());
      });

      it('parseren finder appens media-forespørgsler', () => {
        expect(fund.length).toBeGreaterThanOrEqual(APPS[app].minFund);
      });

      it('hver media-forespørgsel vælger og filtrerer kun på kontraktens kolonner', () => {
        const fejl = fund.flatMap((f) => [
          ...f.fejl.map((e) => `${f.sted}: ${e}`),
          ...f.kolonner.filter((k) => !liste.includes(k)).map((k) => `${f.sted}: kolonnen »${k}« er ikke læsbar for anon/authenticated`),
        ]);
        expect(fejl, '\n' + fejl.join('\n')).toEqual([]);
      });
    });
  }

  it('har tænder: en select eller et filter på sha256/original_filnavn, select(*) og embeds afvises', () => {
    const liste = rls.kolonner;
    const ulovlig = (kode: string) => mediaForespoergsler(kode, 'syntetisk').flatMap((f) => [
      ...f.fejl, ...f.kolonner.filter((k) => !liste.includes(k)),
    ]);
    expect(ulovlig("sb.from('media').select('id::text,sha256').order('id')")).toEqual(['sha256']);
    expect(ulovlig("supabase.from('media').select('id').eq('sha256', sha).maybeSingle()")).toEqual(['sha256']);
    expect(ulovlig("x.from('media').select('id,navn:original_filnavn')")).toEqual(['original_filnavn']);
    expect(ulovlig("const s = { table: 'media', select: 'id,original_filnavn' };")).toEqual(['original_filnavn']);
    expect(ulovlig("sb.from('media').select('*')")).toHaveLength(1);
    expect(ulovlig("sb.from('media').select('id,media_variant(storage_path)')")).toHaveLength(1);
    expect(ulovlig("sb.from('media').select(KOLONNER)")).toHaveLength(1);
    expect(ulovlig("sb.from('media').select('id').or('sha256.eq.x')")).toHaveLength(1);
    expect(ulovlig("supabase.storage.from('media').upload(sti, fil)")).toEqual([]);
    expect(ulovlig("sb.from('media').select('id,storage_path').in('id', ids).order('id')")).toEqual([]);
  });
});
