// Hvor mange 1939-hovedposter mangler forældre i DATA-laget vs. i LÆSER-laget?
// Bruger den RIGTIGE collapseSameAs — ingen genimplementering. Read-only.
//
// To definitioner rapporteres, fordi tidligere rapporter bruger hver sin:
//   "0 forældre"  = ingen forælderkant overhovedet
//   "<2 forældre" = mangelfuld (0 eller kun én kendt forælder) — det er dette
//                   tal docs/reviews/kryds-udgave-udfyldning-... kalder 253/539.
// Begge lag bruger SAMME prædikat; forskellen er alene om id'er kanoniseres.
import { readFileSync, writeFileSync } from 'node:fs';
import { buildFamilyGraph } from '../../packages/core/src/buildFamilyGraph';
import { collapseSameAs } from '../../packages/core/src/collapseSameAs';
import type { AppPerson, Db, SameAsEdge } from '../../packages/core/src/types';

const raw = JSON.parse(readFileSync('tmp/collapse-input.json', 'utf8'));

const persons: AppPerson[] = raw.persons.map((p: any) => ({
  id: p.id, name: p.name ?? '', born: p.born ?? null, died: p.died ?? null,
  years: '', title: '', bio: '', privat: !!p.privat, koen: p.koen ?? null,
}));
const { unions, parentChild } = buildFamilyGraph(raw.members);
const db: Db = { persons, unions, parentChild };
const edges: SameAsEdge[] = raw.sammesom.map((r: any) => ({ alias: r.fra, canonical: r.til }));

const hoved1939: string[] = raw.kilde
  .filter((k: any) => k.source_id === 3).map((k: any) => String(k.person_id));

const res = collapseSameAs(db, edges, new Map());
// Kanoniserede grupper indeholder KUN accepterede; karantænerede falder tilbage
// til deres eget id og arver derfor intet — det er den konservative retning.
const kanon = (id: string) => res.canonicalIdById[id] ?? id;

/** distinkte forældre pr. barn, med valgfri kanonisering af BEGGE sider. */
function foraeldreAntal(kanoniser: boolean): Map<string, Set<string>> {
  const k = (x: string) => (kanoniser ? kanon(x) : x);
  const m = new Map<string, Set<string>>();
  for (const e of parentChild as any[]) {
    const barn = k(String(e.child));
    if (!m.has(barn)) m.set(barn, new Set());
    m.get(barn)!.add(k(String(e.parent)));
  }
  return m;
}

const iKarantaene = new Set<string>();
for (const q of res.quarantined) for (const m of q.members) iKarantaene.add(String(m));

const rapport: Record<string, string[]> = {};
for (const [lag, kanoniser] of [['data', false], ['laeser', true]] as const) {
  const antal = foraeldreAntal(kanoniser);
  const n = (id: string) => antal.get(kanoniser ? kanon(id) : id)?.size ?? 0;
  const nul = hoved1939.filter((id) => n(id) === 0);
  const mangelfuld = hoved1939.filter((id) => n(id) < 2);
  console.log(`${lag}-lag: 0 forældre = ${nul.length}  ·  <2 forældre = ${mangelfuld.length}`);
  rapport[`${lag}_nul`] = nul;
  rapport[`${lag}_mangelfuld`] = mangelfuld;
}

console.log(`\n1939-hovedposter:                  ${hoved1939.length}`);
console.log(`karantænerede grupper i alt:       ${res.quarantined.length}`);
console.log(`læser-lag u. forældre i karantæne: ${rapport['laeser_nul'].filter((id) => iKarantaene.has(id)).length}`);

const nrAf = new Map<string, number>();
for (const k of raw.kilde) if (k.source_id === 3) nrAf.set(String(k.person_id), k.nr);
const tilNr = (ids: string[]) => ids.map((id) => nrAf.get(id)).filter(Boolean);
writeFileSync('tmp/laeser-uden-foraeldre.json', JSON.stringify({
  data_nul: tilNr(rapport['data_nul']),
  data_mangelfuld: tilNr(rapport['data_mangelfuld']),
  laeser_nul: tilNr(rapport['laeser_nul']),
  laeser_mangelfuld: tilNr(rapport['laeser_mangelfuld']),
  karantaene: tilNr(rapport['laeser_nul'].filter((id) => iKarantaene.has(id))),
}, null, 1));
