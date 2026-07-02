// Frontend identitets-projektion: folder flere person-rækker der er samme fysiske person
// (linket via afklarede samme_som-relationer) til ÉN kanonisk post FØR buildModel, så
// slægtskabs-motoren forbliver urørt. Reversibel (returnerer alias-map + proveniens) og
// valideret (konflikter karantæneres, foldes ikke). Se spec 2026-07-02-samme-som-collapse-design.md.
import type { SameAsEdge, QuarantineNote, Db, AppPerson } from './types';

// Union-find over samme_som-kanter → grupper. Kanonisk = unik sink (alias-outdegree 0).
// Karantæne hvis: ingen unik sink, retnings-cyklus, eller endpoint ukendt (ufuldstændig
// komponent — RLS kan have skjult en tvilling). Reversibel: kalder får medlems-lister.
export function groupSameAs(
  edges: SameAsEdge[],
  knownIds: Set<string>,
): { groups: Map<string, string[]>; quarantined: QuarantineNote[] } {
  // Normalisér: fjern dubletter + self-loops.
  const norm = new Map<string, SameAsEdge>();
  for (const e of edges) {
    if (e.alias === e.canonical) continue;
    norm.set(`${e.alias}->${e.canonical}`, e);
  }
  const edgeList = [...norm.values()];

  // Union-find (uden retning) → komponenter.
  const parent = new Map<string, string>();
  const find = (x: string): string => {
    parent.set(x, parent.get(x) ?? x);
    let r = x;
    while (parent.get(r) !== r) r = parent.get(r)!;
    while (parent.get(x) !== r) {
      const n = parent.get(x)!;
      parent.set(x, r);
      x = n;
    }
    return r;
  };
  const union = (a: string, b: string) => {
    parent.set(find(a), find(b));
  };
  for (const e of edgeList) {
    find(e.alias);
    find(e.canonical);
    union(e.alias, e.canonical);
  }

  // Komponent-medlemmer + alias-flag (om noden nogensinde optræder som alias).
  const members = new Map<string, Set<string>>();
  const isAlias = new Map<string, boolean>();
  for (const id of parent.keys()) {
    const r = find(id);
    (members.get(r) ?? members.set(r, new Set()).get(r)!).add(id);
    if (!isAlias.has(id)) isAlias.set(id, false);
  }
  for (const e of edgeList) isAlias.set(e.alias, true);

  const groups = new Map<string, string[]>();
  const quarantined: QuarantineNote[] = [];
  for (const [, mem] of members) {
    const ids = [...mem];
    const missing = ids.filter((id) => !knownIds.has(id));
    if (missing.length) {
      quarantined.push({ members: ids, reason: `ufuldstændig komponent (mangler ${missing.join(',')})` });
      continue;
    }
    const sinks = ids.filter((id) => !isAlias.get(id)); // aldrig alias = sink-kandidat
    if (sinks.length !== 1) {
      quarantined.push({ members: ids, reason: `ingen unik sink (kandidater: ${sinks.join(',') || 'ingen'})` });
      continue;
    }
    groups.set(sinks[0], ids);
  }
  return { groups, quarantined };
}

// Kanonisk-id-map fra en gruppe-samling (ethvert medlem → kanonisk).
const canonMap = (groups: Map<string, string[]>): Map<string, string> => {
  const m = new Map<string, string>();
  for (const [canon, ids] of groups) for (const id of ids) m.set(id, canon);
  return m;
};
const cid = (m: Map<string, string>, id: string) => m.get(id) ?? id;

// Validér grupperne på den fuldt omskrevne, KOMBINEREDE forældre-graf FØR nogen kant droppes
// (spec §6): en tavs self-edge-drop ville ellers skjule netop den konflikt vi skal fange, og to
// grupper der er sikre hver for sig kan konflikte samlet. Fejlende grupper karantæneres (foldes
// ikke) — aldrig tavs oprydning.
export function validateGroups(
  groups: Map<string, string[]>,
  rawDb: Db,
): { accepted: Map<string, string[]>; quarantined: QuarantineNote[] } {
  const cm = canonMap(groups);
  const personById = new Map(rawDb.persons.map((p) => [p.id, p]));
  const quarantined: QuarantineNote[] = [];
  const rejected = new Set<string>();
  const rej = (canon: string, reason: string) => {
    rejected.add(canon);
    quarantined.push({ members: groups.get(canon)!, reason });
  };

  // Vital/køn-konflikt pr. gruppe (defense-in-depth, spec §6.5).
  for (const [canon, ids] of groups) {
    const ps = ids.map((id) => personById.get(id)).filter(Boolean) as AppPerson[];
    const koen = [...new Set(ps.map((p) => p.koen).filter((k) => k && k !== 'ukendt'))];
    if (koen.length > 1) {
      rej(canon, `kendt-forskelligt køn (${koen.join(',')})`);
      continue;
    }
    const born = ps.map((p) => p.born).filter((b): b is number => b != null);
    const died = ps.map((p) => p.died).filter((d): d is number => d != null);
    // Ikke-overlappende levetider: seneste fødsel efter tidligste død → et par er disjunkt
    // (nogen blev født efter en anden allerede var død) → kan ikke være samme person.
    if (born.length && died.length && Math.max(...born) > Math.min(...died) + 1) {
      rej(canon, 'ikke-overlappende levetider (vital-konflikt)');
      continue;
    }
    // Konkurrerende ikke-tomme forældre-sæt: forældre pr. medlem (rå), kanoniseret.
    const parentSets = ids.map(
      (id) => new Set(rawDb.parentChild.filter((pc) => pc.child === id).map((pc) => cid(cm, pc.parent))),
    );
    const nonEmpty = parentSets.filter((s) => s.size > 0);
    if (nonEmpty.length > 1) {
      const first = [...nonEmpty[0]].sort().join(',');
      if (nonEmpty.some((s) => [...s].sort().join(',') !== first)) {
        rej(canon, 'konkurrerende forældre (forskellige ikke-tomme sæt)');
        continue;
      }
    }
  }

  // Byg KOMBINERET projiceret forældre-graf (kun ikke-afviste grupper) → selv-forælder + global cyklus.
  const accepted0 = new Map([...groups].filter(([c]) => !rejected.has(c)));
  const cm2 = canonMap(accepted0);
  const childToParents = new Map<string, Set<string>>();
  for (const pc of rawDb.parentChild) {
    const c = cid(cm2, pc.child);
    const p = cid(cm2, pc.parent);
    if (c === p) {
      const canon = cm2.get(pc.child) ?? cm2.get(pc.parent);
      if (canon && accepted0.has(canon)) rej(canon, 'selv-forælder efter merge');
      continue;
    }
    (childToParents.get(c) ?? childToParents.set(c, new Set()).get(c)!).add(p);
  }
  // Global cyklus-detektion (DFS opad). Marker gruppen der lukker cyklen.
  const WHITE = 0,
    GRAY = 1,
    BLACK = 2;
  const color = new Map<string, number>();
  const stack: string[] = [];
  const dfs = (n: string): string | null => {
    color.set(n, GRAY);
    stack.push(n);
    for (const p of childToParents.get(n) ?? []) {
      const c = color.get(p) ?? WHITE;
      if (c === GRAY) return p; // cyklus
      if (c === WHITE) {
        const hit = dfs(p);
        if (hit) return hit;
      }
    }
    color.set(n, BLACK);
    stack.pop();
    return null;
  };
  for (const n of childToParents.keys()) {
    if ((color.get(n) ?? WHITE) === WHITE) {
      const hit = dfs(n);
      if (hit) {
        // find en accepteret gruppe involveret i cyklus-stakken
        const canon = [...stack, hit].map((x) => cm2.get(x)).find((c) => c && accepted0.has(c));
        if (canon && !rejected.has(canon)) rej(canon, 'cyklus i forældre-graf efter merge');
        color.clear();
        stack.length = 0; // genstart konservativt
      }
    }
  }
  const accepted = new Map([...groups].filter(([c]) => !rejected.has(c)));
  return { accepted, quarantined };
}
