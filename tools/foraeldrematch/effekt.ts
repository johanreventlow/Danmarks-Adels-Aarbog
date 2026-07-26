// Måler effekten af udledKilderForAegtefaeller mod prod-data: hvor mange forældre
// bliver matchbare, hvor mange forældrepar kan gennemføres, og holder disjunktheden?
import { readFileSync } from 'node:fs';
import { buildFamilyGraph } from '../../packages/core/src/buildFamilyGraph';
import { collapseSameAs } from '../../packages/core/src/collapseSameAs';
import { udledKilderForAegtefaeller } from '../../packages/core/src/matchUdgaver';
import type { AppPerson, Db, SameAsEdge } from '../../packages/core/src/types';

const raw = JSON.parse(readFileSync('tmp/collapse-input.json', 'utf8'));
const persons: AppPerson[] = raw.persons.map((p: any) => ({
  id: p.id, name: p.name ?? '', born: p.born ?? null, died: p.died ?? null,
  years: '', title: '', bio: '', privat: false, koen: p.koen ?? null,
}));
const { unions, parentChild } = buildFamilyGraph(raw.members);
const db: Db = { persons, unions, parentChild };
const edges: SameAsEdge[] = raw.sammesom.map((r: any) => ({ alias: r.fra, canonical: r.til }));
const res = collapseSameAs(db, edges, new Map());

const kilde = new Map<string, number>();
for (const k of raw.kilde) kilde.set(k.person_id, k.source_id);

const foer = raw.persons.map((p: any) => ({
  id: p.id as string,
  sourceIds: kilde.has(p.id) ? [kilde.get(p.id)!] : [],
}));
const efter = udledKilderForAegtefaeller(foer, unions);
const kildeEfter = new Map(efter.map((p) => [p.id, p.sourceIds]));

const fik = efter.filter((p, i) => !foer[i].sourceIds.length && p.sourceIds.length).length;
const flertydige = efter.filter((p) => p.sourceIds.length > 1).length;
console.log(`personer uden bog-nummer der fik en udgave:    ${fik}`);
console.log(`personer tildelt FLERE udgaver (skal være 0):  ${flertydige}`);

// Hvordan fordeler de nye sig, og bliver A/B-siderne disjunkte?
const fordeling = new Map<number, number>();
for (const p of efter) {
  if (kilde.has(p.id) || !p.sourceIds.length) continue;
  fordeling.set(p.sourceIds[0], (fordeling.get(p.sourceIds[0]) ?? 0) + 1);
}
console.log(`  heraf til 1939:    ${fordeling.get(3) ?? 0}`);
console.log(`  heraf til 2018-20: ${fordeling.get(1) ?? 0}`);

// Kan forældreparrene nu gennemføres?
const foraeldreAf = (id: string) => [...new Set(parentChild.filter((pc) => pc.child === id).map((pc) => pc.parent))];
const klumper = new Map<string, { f: string[]; boern: number }>();
for (const q of res.quarantined) {
  const a = q.members.find((m) => kilde.get(m) === 3);
  const b = q.members.find((m) => kilde.get(m) === 1);
  if (!a || !b) continue;
  const f = [...foraeldreAf(a), ...foraeldreAf(b)];
  if (!f.length) continue;
  const key = f.slice().sort().join(',');
  const k = klumper.get(key) ?? { f, boern: 0 };
  k.boern++; klumper.set(key, k);
}
const mangler = (id: string) => !Object.prototype.hasOwnProperty.call(res.canonicalIdById, id);
let foerOK = 0, efterOK = 0, boernFoer = 0, boernEfter = 0;
for (const k of klumper.values()) {
  const m = k.f.filter(mangler);
  if (!m.length) continue;
  if (m.every((id) => kilde.has(id))) { foerOK++; boernFoer += k.boern; }
  if (m.every((id) => (kildeEfter.get(id) ?? []).length === 1)) { efterOK++; boernEfter += k.boern; }
}
console.log(`\nforældrepar der kan gennemføres i redaktørfladen:`);
console.log(`  før:   ${foerOK} par → ${boernFoer} børn`);
console.log(`  efter: ${efterOK} par → ${boernEfter} børn`);
