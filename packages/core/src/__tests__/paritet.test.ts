// Paritetstest mellem web og mobil (paritetsplanens "hvordan stopper vi drift", punkt 3).
// Læser kildefilerne som tekst (ingen database, intet netværk) og sikrer to ting:
//  (a) at hvert tabel-/RPC-kald i web/src og mobile/src er kendt her — et nyt ensidigt kald kræver en skrevet grund;
//  (b) at de argumentnøgler, redaktionWrite.ts bygger til red_*-RPC'erne, er parametre i schema.sql.
import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { describe, expect, it } from 'vitest';

const ROD = fileURLToPath(new URL('../../../../', import.meta.url));
type App = 'web' | 'mobil';
type Side = 'begge' | App;
type Post = { side: 'begge' } | { side: App; grund: string };

const B: Post = { side: 'begge' };
const web = (grund: string): Post => ({ side: 'web', grund });
const mobil = (grund: string): Post => ({ side: 'mobil', grund });

const IKKE_RECORDFANER = 'bevidst udeladt på mobil: ingen narrativ-recordfaner (#152, paritetsrapport 2.6)';
const IKKE_SLET_HELT = 'bevidst udeladt på mobil: ingen »Slet helt« (decisions.md:304, paritetsrapport 2.6)';
const IKKE_OCR = 'ikke planlagt på mobil: OCR-ark er skrivebordsarbejde (paritetsrapport 2.6)';
const IKKE_PERSONA = 'ikke planlagt på mobil: source-persona-køen er kun til webkøen (paritetsrapport 2.6)';

// Tabeller og views (.from('…')).
const TABELLER: Record<string, Post> = {
  assertion: B, bookmark: B, citation: B, coat_of_arms: B, conclusion: B, estate: B, fact: B, family: B,
  family_member: B, feed_pin: B, haendelse: B, lineage: B, lineage_scheme: B, lineage_scheme_entry: B,
  lineage_scheme_entry_lineage: B, media: B, media_variant: B, narrative: B,
  organisation: B, person: B, person_external_id: B, place: B, profiles: B, red_foraeldre_konflikt: B,
  relation: B, source: B, story: B, story_kilde: B,
  note: web('ikke planlagt på mobil: medie-fletning (mediaMerge) findes kun på web; mobilen har kun dublet-tjek (paritetsrapport 2.6)'),
  red_doede_links: mobil('mobil-only: død-link-visning i redaktørfladen; web bruger den ikke (paritetsrapport 2.6)'),
  red_konflikt: mobil('mobil-only: konfliktvisning i redaktørfladen; web har den ikke (paritetsrapport 2.6)'),
  text_mention: mobil('mobilen læser omtale-tabellen direkte; web henter omtaler via RPC\'en red_overview_mentions'),
};

// RPC-funktioner (.rpc('…')).
const RPCER: Record<string, Post> = {
  hist_for_subjekt: B, narrative_record_contract_version: B, public_haendelse_feed: B,
  public_person_bio_source_versions: B, public_person_bio_source_versions_v2: B,
  red_bekraeft_media_upload: B, red_match_personer: B, red_person_narrative_records: B,
  red_registrer_media_variant: B, red_slet_person_preview: B, red_udrens_media_preview: B,
  public_person_facts: B,
  hist_for_subjekter: web('mobilen viser kun historik for ét subjekt ad gangen; samlet historik er ikke planlagt (paritetsrapport 2.6)'),
  red_media_efter_sha: web('midlertidigt: mobilen flyttes til RPC\'en i næste commit (#397 R37S8-1)'),
  red_media_interne_felter: web('midlertidigt: mobilen flyttes til RPC\'en i næste commit (#397 R37S8-1)'),
  red_ocr_historik: web(IKKE_OCR),
  red_person_grid_udsnit: web(IKKE_OCR),
  red_ret_ocr_felt: web(IKKE_OCR),
  red_overview_mentions: web('mobilen læser text_mention direkte i stedet for oversigts-RPC\'en'),
  red_person_narrative_publication_history: web(IKKE_RECORDFANER),
  red_person_purge_udbakke: web(IKKE_SLET_HELT),
  red_slet_person_helt_preview: web(IKKE_SLET_HELT),
  red_slettede_personer: web(IKKE_SLET_HELT),
  red_source_persona_detail: web(IKKE_PERSONA),
  red_source_persona_history: web(IKKE_PERSONA),
  red_source_persona_queue: web(IKKE_PERSONA),
};

// ---------- Kildelæsning ----------

function filer(mappe: string): string[] {
  return readdirSync(mappe, { withFileTypes: true }).flatMap((e) => {
    if (e.isDirectory()) return e.name === '__tests__' || e.name === 'node_modules' ? [] : filer(path.join(mappe, e.name));
    return /\.tsx?$/.test(e.name) && !/\.test\./.test(e.name) ? [path.join(mappe, e.name)] : [];
  });
}
const rel = (f: string) => path.relative(ROD, f);
const kilde: Record<App, { fil: string; tekst: string }[]> = {
  web: filer(path.join(ROD, 'web/src')).map((fil) => ({ fil, tekst: readFileSync(fil, 'utf-8') })),
  mobil: filer(path.join(ROD, 'mobile/src')).map((fil) => ({ fil, tekst: readFileSync(fil, 'utf-8') })),
};

/** Første argument (op til første komma/lukkeparentes på øverste niveau) — så `b ? 'x' : 'y'` giver begge navne. */
function foersteArgument(tekst: string, start: number): string {
  let dybde = 0;
  let i = start;
  for (; i < tekst.length; i++) {
    const c = tekst[i];
    if (c === "'" || c === '"' || c === '`') {
      for (i++; i < tekst.length && tekst[i] !== c; i++) if (tekst[i] === '\\') i++;
    } else if (c === '(' || c === '[' || c === '{') dybde++;
    else if (c === ')' || c === ']' || c === '}') { if (dybde === 0) break; dybde--; }
    else if (c === ',' && dybde === 0) break;
  }
  return tekst.slice(start, i);
}

type Kald = { navn: string; fil: string };
function findKald(app: App): { tabeller: Kald[]; rpcer: Kald[] } {
  const tabeller: Kald[] = [];
  const rpcer: Kald[] = [];
  for (const { fil, tekst } of kilde[app]) {
    for (const m of tekst.matchAll(/\.(rpc|from)!?\(/g)) {
      const foer = tekst.slice(Math.max(0, m.index! - 12), m.index!);
      if (/storage\s*$/.test(foer)) continue; // supabase.storage.from('bucket') er ingen tabel
      const arg = foersteArgument(tekst, m.index! + m[0].length);
      // Kun literaler uden interpolation: '…', "…" og `…`.
      for (const l of arg.matchAll(/'([A-Za-z0-9_.]+)'|"([A-Za-z0-9_.]+)"|`([A-Za-z0-9_.]+)`/g)) {
        (m[1] === 'rpc' ? rpcer : tabeller).push({ navn: l[1] ?? l[2] ?? l[3], fil: rel(fil) });
      }
    }
  }
  return { tabeller, rpcer };
}

function tjekListe(art: string, liste: Record<string, Post>, fundne: Record<App, Kald[]>): string[] {
  const fejl: string[] = [];
  const navne = new Set([...fundne.web, ...fundne.mobil].map((k) => k.navn));
  const filer = (app: App, navn: string) => [...new Set(fundne[app].filter((k) => k.navn === navn).map((k) => k.fil))];
  for (const navn of [...navne].sort()) {
    const iWeb = filer('web', navn);
    const iMobil = filer('mobil', navn);
    const faktisk: Side = iWeb.length && iMobil.length ? 'begge' : iWeb.length ? 'web' : 'mobil';
    const post = liste[navn];
    if (!post) {
      fejl.push(`Nyt ${art}-kald »${navn}« (kun ${faktisk}) i ${[...iWeb, ...iMobil].join(', ')} står ikke på paritetslisten. ` +
        `Tilføj det i paritetstesten — og for et ensidigt kald: skriv en grund (planlagt batch eller bevidst fravalg).`);
      continue;
    }
    if (post.side !== faktisk) {
      fejl.push(`${art} »${navn}« er listet som »${post.side}«, men bruges nu ${faktisk === 'begge' ? 'af begge' : `kun af ${faktisk}`} ` +
        `(${[...iWeb, ...iMobil].join(', ')}). Ret listen${faktisk === 'begge' ? ' — paritet er opnået' : ''}.`);
    }
    if (post.side !== 'begge' && !post.grund.trim()) fejl.push(`${art} »${navn}« er ensidigt men mangler en grund.`);
  }
  for (const navn of Object.keys(liste).sort()) {
    if (!navne.has(navn)) fejl.push(`${art} »${navn}« står på paritetslisten, men bruges ikke længere i web/src eller mobile/src. Fjern det fra listen.`);
  }
  return fejl;
}

describe('paritet: databasekald i web og mobil', () => {
  const web = findKald('web');
  const mobil = findKald('mobil');

  it('finder kald i begge apps (parseren virker)', () => {
    expect(web.tabeller.length).toBeGreaterThan(50);
    expect(mobil.tabeller.length).toBeGreaterThan(50);
    expect(web.rpcer.length).toBeGreaterThan(10);
    expect(mobil.rpcer.length).toBeGreaterThan(5);
  });

  it('hver .from(…) er på paritetslisten med rigtig side', () => {
    const fejl = tjekListe('tabel', TABELLER, { web: web.tabeller, mobil: mobil.tabeller });
    expect(fejl, '\n' + fejl.join('\n')).toEqual([]);
  });

  it('hver .rpc(…) er på paritetslisten med rigtig side', () => {
    const fejl = tjekListe('RPC', RPCER, { web: web.rpcer, mobil: mobil.rpcer });
    expect(fejl, '\n' + fejl.join('\n')).toEqual([]);
  });

  it('alle ensidige poster har en grund', () => {
    for (const [navn, p] of Object.entries({ ...TABELLER, ...RPCER })) {
      if (p.side !== 'begge') expect(p.grund.trim(), `${navn} mangler grund`).not.toBe('');
    }
  });
});

// ---------- (b) redaktionWrite: argumentnøgler mod schema.sql ----------

/** Fjerner kommentarer, men bevarer strenge (og længden af resten), så positioner forbliver gyldige. */
function udenKommentarer(t: string): string {
  let ud = '';
  for (let i = 0; i < t.length; i++) {
    const c = t[i];
    if (c === "'" || c === '"' || c === '`') {
      const start = i;
      for (i++; i < t.length && t[i] !== c; i++) if (t[i] === '\\') i++;
      ud += t.slice(start, i + 1);
    } else if (c === '/' && t[i + 1] === '/') { while (i < t.length && t[i] !== '\n') { ud += ' '; i++; } ud += '\n'; }
    else if (c === '/' && t[i + 1] === '*') { while (i < t.length && !(t[i] === '*' && t[i + 1] === '/')) { ud += t[i] === '\n' ? '\n' : ' '; i++; } ud += '  '; i++; }
    else ud += c;
  }
  return ud;
}

/** Indholdet mellem den åbnende tegn ved `start` og dets match (balanceret, streng-bevidst). */
function balanceret(t: string, start: number): string | null {
  const aaben = t[start];
  const luk = aaben === '{' ? '}' : aaben === '(' ? ')' : ']';
  let dybde = 0;
  for (let i = start; i < t.length; i++) {
    const c = t[i];
    if (c === "'" || c === '"' || c === '`') { for (i++; i < t.length && t[i] !== c; i++) if (t[i] === '\\') i++; continue; }
    if (c === aaben) dybde++;
    else if (c === luk && --dybde === 0) return t.slice(start + 1, i);
  }
  return null;
}

function delPaaKomma(t: string): string[] {
  const dele: string[] = [];
  let dybde = 0;
  let fra = 0;
  for (let i = 0; i < t.length; i++) {
    const c = t[i];
    if (c === "'" || c === '"' || c === '`') { for (i++; i < t.length && t[i] !== c; i++) if (t[i] === '\\') i++; continue; }
    if ('({['.includes(c)) dybde++;
    else if (')}]'.includes(c)) dybde--;
    else if (c === ',' && dybde === 0) { dele.push(t.slice(fra, i)); fra = i + 1; }
  }
  dele.push(t.slice(fra));
  return dele.map((d) => d.trim()).filter(Boolean);
}

type ObjektNoegler = { noegler: string[]; usikre: number };
function noeglerIObjekt(indhold: string): ObjektNoegler {
  const noegler: string[] = [];
  let usikre = 0;
  for (const del of delPaaKomma(indhold)) {
    if (del.startsWith('...')) {
      usikre++;
      for (const m of del.matchAll(/\b(p_[A-Za-z0-9_]+)\s*:/g)) noegler.push(m[1]); // litteral inde i spread
      continue;
    }
    const m = /^(?:'([^']+)'|"([^"]+)"|([A-Za-z_$][\w$]*))\s*(?::|$)/.exec(del);
    if (m) noegler.push(m[1] ?? m[2] ?? m[3]);
    else usikre++;
  }
  return { noegler, usikre };
}

type ArgKald = { fn: string; noegler: string[]; usikkert: boolean; sted: string };
function udtraekArgKald(app: 'web' | 'mobil'): ArgKald[] {
  const fil = path.join(ROD, app === 'web' ? 'web/src/data/redaktionWrite.ts' : 'mobile/src/data/redaktionWrite.ts');
  const t = udenKommentarer(readFileSync(fil, 'utf-8'));
  const ud: ArgKald[] = [];
  for (const m of t.matchAll(/\bfn:\s*'(red_[a-z0-9_]+)'\s*,\s*args\b\s*(:\s*)?/g)) {
    const sted = `${rel(fil)}:${t.slice(0, m.index).split('\n').length}`;
    const efter = m.index! + m[0].length;
    let noegler: string[] = [];
    let usikkert = false;
    if (m[2] && t[efter] === '{') {
      const ind = balanceret(t, efter);
      if (ind == null) { ud.push({ fn: m[1], noegler, usikkert: true, sted }); continue; }
      const r = noeglerIObjekt(ind);
      noegler = r.noegler;
      usikkert = r.usikre > 0;
    } else {
      // args-variabel (`args` eller `args: ident`): find nærmeste deklaration før og tilføjelser `ident.p_x = …`.
      const ident = m[2] ? /^[A-Za-z_$][\w$]*/.exec(t.slice(efter))?.[0] : 'args';
      if (!ident) { ud.push({ fn: m[1], noegler, usikkert: true, sted }); continue; }
      const foer = t.slice(0, m.index);
      const dekl = [...foer.matchAll(new RegExp(`\\b(?:const|let)\\s+${ident}\\b[^=\\n]*=\\s*`, 'g'))].pop();
      if (!dekl) { ud.push({ fn: m[1], noegler, usikkert: true, sted }); continue; }
      const start = dekl.index! + dekl[0].length;
      if (t[start] === '{') {
        const ind = balanceret(t, start);
        if (ind != null) { const r = noeglerIObjekt(ind); noegler.push(...r.noegler); usikkert = r.usikre > 0; } else usikkert = true;
      } else usikkert = true; // fx `const b = famLinkBase(c)` — kan ikke udtrækkes statisk
      for (const a of t.slice(start, m.index).matchAll(new RegExp(`\\b${ident}\\.(p_[A-Za-z0-9_]+)\\s*=`, 'g'))) noegler.push(a[1]);
      for (const a of t.slice(start, m.index).matchAll(new RegExp(`\\b${ident}\\[\\s*'(p_[A-Za-z0-9_]+)'\\s*\\]\\s*=`, 'g'))) noegler.push(a[1]);
    }
    ud.push({ fn: m[1], noegler: [...new Set(noegler)], usikkert, sted });
  }
  return ud;
}

/** red_*-funktioner i schema.sql → mængden af parameternavne (union over overloads). */
function schemaParametre(): Map<string, Set<string>> {
  const sql = readFileSync(path.join(ROD, 'schema.sql'), 'utf-8');
  const kort = new Map<string, Set<string>>();
  for (const m of sql.matchAll(/CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:public\.)?(red_[a-z0-9_]+)\s*\(/gi)) {
    const ind = balanceret(sql, m.index! + m[0].length - 1);
    if (ind == null) continue;
    const params = kort.get(m[1].toLowerCase()) ?? new Set<string>();
    for (const del of delPaaKomma(ind)) {
      const navn = del.replace(/^(?:IN|OUT|INOUT|VARIADIC)\s+/i, '').split(/\s+/)[0];
      if (navn) params.add(navn.replace(/"/g, ''));
    }
    kort.set(m[1].toLowerCase(), params);
  }
  return kort;
}

describe('paritet: redaktionWrite sender kun parametre, schema.sql kender', () => {
  const schema = schemaParametre();

  it('schema-parseren finder red_*-funktioner med parametre', () => {
    expect(schema.size).toBeGreaterThan(50);
    expect([...(schema.get('red_set_koen') ?? [])].sort()).toEqual(['p_koen', 'p_person_id']);
  });

  for (const app of ['web', 'mobil'] as const) {
    it(`${app}: hver fn: 'red_…' bruger kun argumentnøgler der er parametre i schema.sql`, () => {
      const kald = udtraekArgKald(app);
      expect(kald.length, 'fandt ingen fn-kald — parseren er gået i stykker').toBeGreaterThan(20);
      const fejl: string[] = [];
      let sprunget = 0;
      for (const k of kald) {
        const params = schema.get(k.fn);
        if (!params) { fejl.push(`${k.sted}: RPC'en ${k.fn} findes ikke i schema.sql.`); continue; }
        const ukendte = k.noegler.filter((n) => !params.has(n));
        if (ukendte.length) {
          fejl.push(`${k.sted}: ${k.fn} får argumenterne [${ukendte.join(', ')}], som ikke er parametre i schema.sql ` +
            `(kendte: ${[...params].join(', ') || 'ingen'}).`);
        }
        if (k.usikkert) sprunget++;
      }
      // Kald hvor ikke alle nøgler kunne udtrækkes statisk (spread, funktionskald) — de synlige nøgler er stadig tjekket.
      if (sprunget) console.info(`paritet(${app}): ${sprunget} af ${kald.length} kald kunne kun delvist udtrækkes statisk.`);
      expect(fejl, '\n' + fejl.join('\n')).toEqual([]);
    });
  }
});
