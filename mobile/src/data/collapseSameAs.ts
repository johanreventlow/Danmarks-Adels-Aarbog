// Frontend identitets-projektion: folder flere person-rækker der er samme fysiske person
// (linket via afklarede samme_som-relationer) til ÉN kanonisk post FØR buildModel, så
// slægtskabs-motoren forbliver urørt. Reversibel (returnerer alias-map + proveniens) og
// valideret (konflikter karantæneres, foldes ikke). Se spec 2026-07-02-samme-som-collapse-design.md.
import { fmtYears } from './fields';
import type { SameAsEdge, QuarantineNote, Db, AppPerson, CollapseResult, Provenance } from './types';

// Tilføj til et Set under nøglen `k` (opret sættet ved første brug).
const addTo = <K>(m: Map<K, Set<string>>, k: K, v: string): void => {
  let s = m.get(k);
  if (!s) m.set(k, (s = new Set()));
  s.add(v);
};

// Behold første forekomst pr. nøgle (rækkefølge-bevarende dedup).
const dedupeByKey = <T>(arr: T[], key: (t: T) => string): T[] => {
  const seen = new Set<string>();
  return arr.filter((t) => {
    const k = key(t);
    if (seen.has(k)) return false;
    seen.add(k);
    return true;
  });
};

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

  // Komponent-medlemmer + alias-mængde (noder der optræder som alias, dvs. har outdegree > 0).
  const members = new Map<string, Set<string>>();
  for (const id of parent.keys()) addTo(members, find(id), id);
  const aliasSet = new Set(edgeList.map((e) => e.alias));

  const groups = new Map<string, string[]>();
  const quarantined: QuarantineNote[] = [];
  for (const [, mem] of members) {
    const ids = [...mem];
    const missing = ids.filter((id) => !knownIds.has(id));
    if (missing.length) {
      quarantined.push({ members: ids, reason: `ufuldstændig komponent (mangler ${missing.join(',')})` });
      continue;
    }
    const sinks = ids.filter((id) => !aliasSet.has(id)); // aldrig alias = sink-kandidat
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
    const koen = [...new Set(ps.map((p) => p.koen).filter(Boolean))];
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
    addTo(childToParents, c, p);
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

// Regenerér display-år fra de coalescede tal via samme formatter som loaderen (fields.ts),
// så et flettet person-år er format-konsistent med resten af appen (sti-visningen bruger
// `years` separat — inkonsistens ville ellers lydløst afvige fra fmtYears).
const regenYears = (born: number | null, died: number | null): string =>
  fmtYears(born == null ? null : String(born), died == null ? null : String(died));

// Fuld projektion: gruppér (Task 1) → validér/karantænér (Task 2) → flet accepterede grupper til
// deres kanoniske post og omskriv alle graf-kanter til kanoniske id'er. Reversibel: returnerer
// alias-map + mergedFrom (proveniens) + karantæne. Motoren (buildModel/relationship) forbliver urørt.
export function collapseSameAs(
  rawDb: Db,
  edges: SameAsEdge[],
  ext: Map<string, { linje: string | null; nr: number | null }>,
): CollapseResult {
  const known = new Set(rawDb.persons.map((p) => p.id));
  const { groups, quarantined: q1 } = groupSameAs(edges, known);
  const { accepted, quarantined: q2 } = validateGroups(groups, rawDb);
  const quarantined = [...q1, ...q2];

  const cm = canonMap(accepted);
  const canonicalIdById: Record<string, string> = Object.fromEntries(cm);
  const canon = (id: string) => cm.get(id) ?? id;

  // Flet personer til den kanoniske post (coalesce: kanonisk først, derefter alias'er).
  const personById = new Map(rawDb.persons.map((p) => [p.id, p]));
  const mergedFrom: Record<string, Provenance[]> = {};
  const mergedPersons: AppPerson[] = [];
  const droppedAlias = new Set<string>();
  for (const [canonId, ids] of accepted) {
    const primary = personById.get(canonId)!;
    const others = ids.filter((id) => id !== canonId).map((id) => personById.get(id)!).filter(Boolean);
    const coalesce = <K extends keyof AppPerson>(k: K): AppPerson[K] =>
      (primary[k] ?? others.find((o) => o[k] != null)?.[k]) as AppPerson[K];
    const born = coalesce('born');
    const died = coalesce('died');
    mergedPersons.push({
      ...primary,
      born,
      died,
      years: regenYears(born as number | null, died as number | null),
      title: primary.title || others.find((o) => o.title)?.title || '',
      koen: primary.koen ?? others.find((o) => o.koen)?.koen,
      privat: ids.some((id) => Boolean(personById.get(id)?.privat)), // OR
    });
    mergedFrom[canonId] = ids.map((id) => ({
      personId: id,
      linje: ext.get(id)?.linje ?? null,
      nr: ext.get(id)?.nr ?? null,
    }));
    for (const id of ids) if (id !== canonId) droppedAlias.add(id);
  }
  const persons = rawDb.persons
    .filter((p) => !accepted.has(p.id) && !droppedAlias.has(p.id))
    .concat(mergedPersons);

  // Omskriv unions til kanoniske id'er (dedup familie-bevidst: unik på familie-id).
  const unions = dedupeByKey(
    rawDb.unions.map((u) => ({ ...u, p1: u.p1 == null ? u.p1 : canon(u.p1), p2: u.p2 == null ? u.p2 : canon(u.p2) })),
    (u) => u.id,
  );

  // Omskriv parentChild til kanoniske id'er (dedup på kanonisk-forælder|kanonisk-barn|familie —
  // ikke kun endpoints, ellers aggregerer buildModel's konfidens-logik kanter på tværs af familier).
  const parentChild = dedupeByKey(
    rawDb.parentChild.map((pc) => ({ ...pc, child: canon(pc.child), parent: canon(pc.parent) })),
    (pc) => `${pc.parent}|${pc.child}|${pc.union}`,
  );

  return { db: { persons, unions, parentChild }, canonicalIdById, mergedFrom, quarantined };
}
