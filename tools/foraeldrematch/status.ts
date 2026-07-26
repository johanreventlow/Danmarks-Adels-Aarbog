// Kører den RIGTIGE collapseSameAs mod et prod-dump — ingen genimplementering
// af reglerne. Formål: tælle hvor mange samme_som-grupper der karantæneres i dag,
// og hvorfor. Read-only; rører hverken base eller app.
import { readFileSync } from 'node:fs';
import { buildFamilyGraph } from '../../packages/core/src/buildFamilyGraph';
import { collapseSameAs } from '../../packages/core/src/collapseSameAs';
import type { AppPerson, Db, SameAsEdge } from '../../packages/core/src/types';

const raw = JSON.parse(readFileSync('tmp/collapse-input.json', 'utf8'));

const persons: AppPerson[] = raw.persons.map((p: any) => ({
  id: p.id,
  name: p.name ?? '',
  born: p.born ?? null,
  died: p.died ?? null,
  years: '',
  title: '',
  bio: '',
  privat: !!p.privat,
  koen: p.koen ?? null,
}));

const { unions, parentChild } = buildFamilyGraph(raw.members);
const db: Db = { persons, unions, parentChild };

// samme_som er lagret retningsbestemt (subjekt=alias, objekt=kanonisk)
const edges: SameAsEdge[] = raw.sammesom.map((r: any) => ({ alias: r.fra, canonical: r.til }));

const ext = new Map<string, { linje: string | null; nr: number | null }>();
const kildeAf = new Map<string, number>();
for (const k of raw.kilde) kildeAf.set(k.person_id, k.source_id);

const res = collapseSameAs(db, edges, ext);

const grupper = new Set(Object.values(res.canonicalIdById)).size;
console.log(`samme_som-kanter:            ${edges.length}`);
console.log(`personer i en gruppe:        ${Object.keys(res.canonicalIdById).length}`);
console.log(`accepterede grupper:         ${grupper}`);
console.log(`KARANTÆNEREDE grupper:       ${res.quarantined.length}`);

const perAarsag = new Map<string, number>();
for (const q of res.quarantined) {
  const key = q.reason.replace(/\(.*\)/, '(…)').trim();
  perAarsag.set(key, (perAarsag.get(key) ?? 0) + 1);
}
console.log('\nÅrsager:');
for (const [k, v] of [...perAarsag].sort((a, b) => b[1] - a[1])) console.log(`  ${v.toString().padStart(3)}  ${k}`);

const navnAf = new Map(persons.map((p) => [p.id, p.name]));
const kryds = res.quarantined.filter((q) =>
  q.members.some((m) => kildeAf.get(m) === 1) && q.members.some((m) => kildeAf.get(m) === 3));
console.log(`\nheraf på tværs af 1939 og 2018-20: ${kryds.length}`);
console.log('\nEksempler (maks 8):');
for (const q of res.quarantined.slice(0, 8)) {
  const navne = q.members.map((m) => `${navnAf.get(m) ?? '?'} [kilde ${kildeAf.get(m) ?? '-'}]`).join(' ↔ ');
  console.log(`  ${q.reason}\n      ${navne}`);
}

// --- Diagnose: er de 287 ægte uenigheder, eller en kaskade?
// Karantænetjekket kanoniserer forældre med ACCEPTED-only-kortet. Er en forælders
// egen gruppe også karantæneret, kanoniserer de to sider til hver sit id — og barnet
// karantæneres, selv om bøgerne er enige. Her kanoniseres med ALLE grupper i stedet.
const alleGrupper = new Map<string, string>();
{
  const parent = new Map<string, string>();
  const find = (x: string): string => { let r = x; while (parent.get(r) && parent.get(r) !== r) r = parent.get(r)!; return r; };
  const uni = (a: string, b: string) => { const ra = find(a), rb = find(b); if (ra !== rb) parent.set(ra, rb); };
  for (const e of edges) { if (!parent.has(e.alias)) parent.set(e.alias, e.alias); if (!parent.has(e.canonical)) parent.set(e.canonical, e.canonical); uni(e.alias, e.canonical); }
  for (const id of parent.keys()) alleGrupper.set(id, find(id));
}
const rep = (id: string) => alleGrupper.get(id) ?? id;
const foraeldreAf = new Map<string, Set<string>>();
for (const pc of parentChild) {
  const s = foraeldreAf.get(pc.child) ?? new Set<string>();
  s.add(rep(pc.parent)); foraeldreAf.set(pc.child, s);
}
let ægte = 0, kaskade = 0;
for (const q of res.quarantined) {
  const sæt = q.members.map((m) => [...(foraeldreAf.get(m) ?? new Set())].sort().join(','));
  const ikkeTomme = sæt.filter((s) => s.length > 0);
  const uenige = new Set(ikkeTomme).size > 1;
  if (uenige) ægte++; else kaskade++;
}
console.log(`\n--- Diagnose, kanoniseret med ALLE samme_som-grupper:`);
console.log(`  stadig uenige (ægte konflikt): ${ægte}`);
console.log(`  enige — karantænen er kaskade: ${kaskade}`);

console.log('\n--- Hvem er de uenige om? (5 tilfælde, med forældrenavne)');
let vist = 0;
for (const q of res.quarantined) {
  if (vist >= 5) break;
  const rader = q.members.map((m) => {
    const fs = [...(foraeldreAf.get(m) ?? new Set())];
    const navne = [...new Set(parentChild.filter((pc) => pc.child === m).map((pc) => navnAf.get(pc.parent) ?? '?'))];
    return { m, kilde: kildeAf.get(m), navn: navnAf.get(m), reps: fs.sort().join(','), navne: navne.join(' + ') };
  });
  if (rader.some((r) => !r.reps)) continue;
  vist++;
  console.log(`\n  ${rader.map((r) => `${r.navn} [kilde ${r.kilde}]`).join(' ↔ ')}`);
  for (const r of rader) console.log(`      kilde ${r.kilde}: forældre = ${r.navne}`);
}

console.log('\n--- Hvor få forældre-matches ville frigive de karantænerede?');
const parKey = (m: string) => [...new Set(parentChild.filter((pc) => pc.child === m).map((pc) => rep(pc.parent)))].sort().join(',');
const umatchedeForaeldre = new Set<string>();
const forældrepar = new Set<string>();
for (const q of res.quarantined) {
  for (const m of q.members) {
    const k = parKey(m);
    if (k) forældrepar.add(`${kildeAf.get(m)}:${k}`);
    for (const pc of parentChild.filter((p) => p.child === m)) {
      if (!alleGrupper.has(pc.parent)) umatchedeForaeldre.add(pc.parent);
    }
  }
}
console.log(`  karantænerede grupper:                 ${res.quarantined.length}`);
console.log(`  distinkte forældrepar involveret:      ${forældrepar.size}`);
console.log(`  forældre der IKKE er matchet i dag:    ${umatchedeForaeldre.size}`);
const top = new Map<string, number>();
for (const q of res.quarantined) {
  const navne = q.members.map((m) => [...new Set(parentChild.filter((pc) => pc.child === m).map((pc) => navnAf.get(pc.parent) ?? '?'))].join(' + ')).join('  |  ');
  top.set(navne, (top.get(navne) ?? 0) + 1);
}
console.log('\n  Største klumper (forældrepar → antal børn i karantæne):');
for (const [k, v] of [...top].sort((a, b) => b[1] - a[1]).slice(0, 8)) console.log(`    ${v.toString().padStart(3)}  ${k}`);

// Holder påstanden om "114 gratis udfyldninger" efter den rigtige validering?
const accepteret = new Set(Object.keys(res.canonicalIdById));
const harForaeldre = new Set(parentChild.map((pc) => pc.child));
let gratis = 0, spildt = 0;
for (const e of edges) {
  for (const [a, b] of [[e.alias, e.canonical], [e.canonical, e.alias]] as const) {
    if (kildeAf.get(a) === 3 && kildeAf.get(b) === 1 && !harForaeldre.has(a) && harForaeldre.has(b)) {
      if (accepteret.has(a)) gratis++; else spildt++;
    }
  }
}
console.log(`\n--- 1939-poster uden forældre, hvis 2018-20-modpart har dem:`);
console.log(`  arver forældre (gruppe accepteret): ${gratis}`);
console.log(`  arver IKKE (gruppe karantæneret):   ${spildt}`);
