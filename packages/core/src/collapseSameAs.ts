// Frontend identitets-projektion: folder flere person-rækker der er samme fysiske person
// (linket via afklarede samme_som-relationer) til ÉN kanonisk post FØR buildModel, så
// slægtskabs-motoren forbliver urørt. Reversibel (returnerer alias-map + proveniens) og
// valideret (konflikter karantæneres, foldes ikke). Se spec 2026-07-02-samme-som-collapse-design.md.
import { fmtYears } from './fields';
import { KONFIDENS_RANK } from './types';
import type {
  SameAsEdge,
  QuarantineNote,
  Db,
  AppPerson,
  CollapseResult,
  Provenance,
  ParentChild,
  Konfidens,
} from './types';

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

// Maks. spredning på kendte fødselsår inden for én gruppe før collapse blokeres (spec §6.5).
// Ligger langt over enhver legitim kilde-til-kilde-usikkerhed på et fødselsår, så kun åbenlyst
// forskellige personer (fx et fejl-blåstemplet link) rammes — defense-in-depth, ikke primær-gate.
const MAX_BIRTH_SPREAD_YEARS = 80;

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
//
// FIXED-POINT (Codex D1): at karantænere én gruppe ændrer kanoniseringen for de øvrige — en
// af-mergedes P/Q afslører konkurrerende forældre der før så ens ud, og bryder cykler. Derfor
// genkøres ALLE checks på den aktuelt-accepterede canon-map indtil en runde ikke rejekterer mere.
export function validateGroups(
  groups: Map<string, string[]>,
  rawDb: Db,
): { accepted: Map<string, string[]>; quarantined: QuarantineNote[] } {
  const personById = new Map(rawDb.persons.map((p) => [p.id, p]));
  // Bøttet pr. barn ÉN gang: forældre-opslaget ligger i et per-gruppe-per-medlem-loop inde i
  // fixed-point-runden — et lineært filter dér koster O(medlemmer × kanter) pr. runde, og
  // previewSammeSom kalder hertil én gang pr. kandidatpar (tusindvis i SammenlignUdgaver).
  const pcByChild = new Map<string, ParentChild[]>();
  for (const pc of rawDb.parentChild) {
    let arr = pcByChild.get(pc.child);
    if (!arr) pcByChild.set(pc.child, (arr = []));
    arr.push(pc);
  }
  const quarantined: QuarantineNote[] = [];
  const rejected = new Set<string>();
  const rej = (canon: string, reason: string) => {
    if (rejected.has(canon)) return; // idempotent: ingen dobbelt-note pr. gruppe
    rejected.add(canon);
    quarantined.push({ members: groups.get(canon)!, reason });
  };

  let changed = true;
  while (changed) {
    const before = rejected.size;
    // Kun endnu-accepterede grupper indgår i denne rundes kanonisering.
    const active = new Map([...groups].filter(([c]) => !rejected.has(c)));
    const cm = canonMap(active);

    // Per-gruppe vital/køn-konflikt (defense-in-depth, spec §6.5) + konkurrerende forældre.
    for (const [canon, ids] of active) {
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
      // Fødsler for langt fra hinanden til at kunne være samme person (spec §6.5) — fanger tilfælde
      // hvor kun fødselsår kendes (levetids-tjekket ovenfor kræver også et dødsår).
      if (born.length > 1 && Math.max(...born) - Math.min(...born) > MAX_BIRTH_SPREAD_YEARS) {
        rej(canon, 'fødsler for langt fra hinanden (vital-konflikt)');
        continue;
      }
      // Konkurrerende ikke-tomme forældre-sæt: forældre pr. medlem, kanoniseret med accepted-only cm.
      const parentSets = ids.map(
        (id) => new Set((pcByChild.get(id) ?? []).map((pc) => cid(cm, pc.parent))),
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

    // Kombineret projiceret forældre-graf → selv-forælder + global cyklus.
    const childToParents = new Map<string, Set<string>>();
    for (const pc of rawDb.parentChild) {
      const c = cid(cm, pc.child);
      const p = cid(cm, pc.parent);
      if (c === p) {
        const canon = cm.get(pc.child) ?? cm.get(pc.parent);
        if (canon && active.has(canon)) rej(canon, 'selv-forælder efter merge');
        continue;
      }
      addTo(childToParents, c, p);
    }
    // Selv-ægtefælle efter merge (spec §6.1): en union hvis to partnere kanoniserer til samme id.
    // buildModel.addSpouse har ingen selv-guard, så det ville ellers gøre personen til sin egen ægtefælle.
    for (const u of rawDb.unions) {
      if (u.p1 == null || u.p2 == null) continue;
      if (cid(cm, u.p1) === cid(cm, u.p2)) {
        const canon = cm.get(u.p1) ?? cm.get(u.p2);
        if (canon && active.has(canon)) rej(canon, 'selv-ægtefælle efter merge');
      }
    }
    // Global cyklus-detektion (DFS opad). Marker gruppen der lukker cyklen.
    const GRAY = 1;
    const color = new Map<string, number>();
    const stack: string[] = [];
    const dfs = (n: string): string | null => {
      color.set(n, GRAY);
      stack.push(n);
      for (const p of childToParents.get(n) ?? []) {
        const c = color.get(p);
        if (c === GRAY) return p; // cyklus
        if (c == null) {
          const hit = dfs(p);
          if (hit) return hit;
        }
      }
      color.set(n, 2); // BLACK
      stack.pop();
      return null;
    };
    for (const n of childToParents.keys()) {
      if (color.get(n) == null) {
        const hit = dfs(n);
        if (hit) {
          // Karantænér ALLE accepterede grupper i selve cyklus-udsnittet (stack fra `hit` og ned),
          // ikke hele DFS-stien: en accepteret gruppe FØR cyklus-indgangen er uskyldig og må ikke
          // over-karantæneres. At tage hele udsnittet (ej blot første) garanterer at hver merge-
          // induceret kant i cyklussen fjernes, så den projicerede graf altid bliver acyklisk.
          const cycle = stack.slice(stack.indexOf(hit));
          for (const x of cycle) {
            const c = cm.get(x);
            if (c && active.has(c)) rej(c, 'cyklus i forældre-graf efter merge');
          }
          color.clear();
          stack.length = 0; // genstart konservativt
        }
      }
    }

    changed = rejected.size > before;
  }

  const accepted = new Map([...groups].filter(([c]) => !rejected.has(c)));
  return { accepted, quarantined };
}

// Regenerér display-år fra de coalescede tal via samme formatter som loaderen (fields.ts),
// så et flettet person-år er format-konsistent med resten af appen (sti-visningen bruger
// `years` separat — inkonsistens ville ellers lydløst afvige fra fmtYears).
const regenYears = (born: number | null, died: number | null): string =>
  fmtYears(born == null ? null : String(born), died == null ? null : String(died));

// Gruppér (Task 1) → validér/karantænér (Task 2) UDEN projektion. Egen indgang fordi
// previewSammeSom kun behøver karantænen — den fulde projektion (person-flet + kant-omskrivning)
// er O(hele grafen) og ville være spildt arbejde pr. kandidatpar (tusindvis i SammenlignUdgaver).
export function resolveSameAs(
  rawDb: Db,
  edges: SameAsEdge[],
): { accepted: Map<string, string[]>; quarantined: QuarantineNote[] } {
  const known = new Set(rawDb.persons.map((p) => p.id));
  const { groups, quarantined: q1 } = groupSameAs(edges, known);
  const { accepted, quarantined: q2 } = validateGroups(groups, rawDb);
  return { accepted, quarantined: [...q1, ...q2] };
}

// Fuld projektion: gruppér (Task 1) → validér/karantænér (Task 2) → flet accepterede grupper til
// deres kanoniske post og omskriv alle graf-kanter til kanoniske id'er. Reversibel: returnerer
// alias-map + mergedFrom (proveniens) + karantæne. Motoren (buildModel/relationship) forbliver urørt.
export function collapseSameAs(
  rawDb: Db,
  edges: SameAsEdge[],
  ext: Map<string, { linje: string | null; nr: number | null }>,
): CollapseResult {
  const { accepted, quarantined } = resolveSameAs(rawDb, edges);

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
    // Deterministisk coalesce-rækkefølge (spec §7): kanonisk først, derefter alias'er sorteret på id
    // — så et 3+-medlems-flet giver samme resultat på tværs af loads uanset traversérings-rækkefølge.
    const others = ids.filter((id) => id !== canonId).sort().map((id) => personById.get(id)!).filter(Boolean);
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
      // Narrativ = UNION (spec §8), kanonisk (fuld) bio først, dedup eksakte. No-op på web (bio='';
      // web unionerer narrativer i public.ts) — men fikser mobile hvor bio bæres på personen.
      bio: [...new Set([primary.bio, ...others.map((o) => o.bio)].filter(Boolean))].join('\n\n'),
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
  // Ved kollision beholdes den STÆRKESTE konfidens (matcher buildModel.konfByEdge; first-wins ville
  // ellers kunne nedgradere en sikker påstand til en formodet — Codex D2).
  const konfRank = (k: Konfidens | undefined) => (k == null ? -1 : KONFIDENS_RANK[k]);
  const pcByKey = new Map<string, ParentChild>();
  for (const pc of rawDb.parentChild) {
    const rw = { ...pc, child: canon(pc.child), parent: canon(pc.parent) };
    const key = `${rw.parent}|${rw.child}|${rw.union}`;
    const prev = pcByKey.get(key);
    if (!prev || konfRank(rw.konfidens) > konfRank(prev.konfidens)) pcByKey.set(key, rw);
  }
  const parentChild = [...pcByKey.values()];

  return { db: { persons, unions, parentChild }, canonicalIdById, mergedFrom, quarantined };
}
