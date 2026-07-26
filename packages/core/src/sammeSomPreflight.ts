// Rådgivende pre-flight for redaktionel samme_som-linking (spec 2026-07-02 §6). Kører collapse med
// den hypotetiske kant på REDAKTIONS-datasættet og rapporterer om kantens komponent ville blive
// karantæneret (køn/levetid/konkurrerende forældre). IKKE autoritativt — offentlig visning kan afvige
// pga. RLS/completeness; DB-triggeren håndhæver graf-invarianterne. Kun et UI-hint.
//
// PERF: SammenlignUdgaver kalder hertil én gang PR. KANDIDATPAR (tusindvis pr. memo-pass) med
// IDENTISK rawDb + existingEdges — kun den hypotetiske kant skifter. En fuld resolveSameAs pr. kald
// koster O(hele grafen) hver gang; i stedet caches baseline-afledte strukturer (1 slot, nøglet på
// argumenterne) og det almindelige tilfælde — et par der er graf-inert ift. de bekræftede grupper —
// afgøres på parrets eget nabolag. Alt der ikke BEVISELIGT er inert falder tilbage til den fulde
// beregning, så svaret forbliver byte-identisk med den naive sti (låst af equivalence-testen).
import { groupSameAs, resolveSameAs, validateGroups } from './collapseSameAs';
import type { AppPerson, Db, ParentChild, QuarantineNote, SameAsEdge, Union } from './types';

type PreflightCtx = {
  personById: Map<string, AppPerson>;
  known: Set<string>;
  endpoints: Set<string>; // alle endpoints i eksisterende (ikke-self) kanter
  memberSet: Set<string>; // medlemmer af alle baseline-grupper (også dem validering senere afviser)
  parentsOfMembers: Set<string>; // rå forældre-id'er til gruppemedlemmer
  // Baseline-ACCEPTEREDE grupper er aktive i samtlige fixed-point-runder, så deres kanonisering
  // er konstant — parrets forældre må derfor gerne ligge i dem, blot udsnittet omskriver forældre-
  // id'et til gruppens canon. Kun VALIDERINGS-AFVISTE gruppers medlemmer kanoniserer runde-
  // varierende (mappet i tidlige runder, rå efter afvisning) og tvinger fallback.
  acceptedCm: Map<string, string>;
  rejectedMembers: Set<string>;
  pcByChild: Map<string, ParentChild[]>;
  unionsByPerson: Map<string, Union[]>;
  // Projiceret forældre-graf under runde-1-kanonisering (ALLE grupper merget). Runde-1 er den
  // maksimale sammensmeltning, og kanonisering kan kun TILFØJE forbindelser — så uopnåelighed her
  // medfører uopnåelighed i alle senere (mindre mergede) runder.
  childToParentsAll: Map<string, Set<string>>;
  baselineQuarantined: QuarantineNote[]; // fuld baseline-kørsel (bruges når hyp. kant er self-loop)
};

// Kun til test-observabilitet (equivalence-testen skal kunne bevise at BEGGE stier rammes).
export const _previewSammeSomStats = { fast: 0, fallback: 0, baseline: 0 };

let cacheDb: Db | null = null;
let cacheEdges: SameAsEdge[] | null = null;
let cacheCtx: PreflightCtx | null = null;

// Indholds-sammenligning frem for ren reference: koster O(kanter) men redder cachen hvis en
// kalder genskaber kant-arrayet med samme indhold pr. kald.
const sameEdges = (a: SameAsEdge[], b: SameAsEdge[]): boolean =>
  a === b || (a.length === b.length && a.every((e, i) => e.alias === b[i].alias && e.canonical === b[i].canonical));

function getCtx(rawDb: Db, existingEdges: SameAsEdge[]): PreflightCtx {
  if (cacheCtx && cacheDb === rawDb && cacheEdges && sameEdges(cacheEdges, existingEdges)) return cacheCtx;

  const personById = new Map(rawDb.persons.map((p) => [p.id, p]));
  const known = new Set(personById.keys());
  const endpoints = new Set<string>();
  for (const e of existingEdges) {
    if (e.alias === e.canonical) continue; // groupSameAs dropper self-loops — samme normalisering her
    endpoints.add(e.alias);
    endpoints.add(e.canonical);
  }
  const pcByChild = new Map<string, ParentChild[]>();
  for (const pc of rawDb.parentChild) {
    const arr = pcByChild.get(pc.child);
    if (arr) arr.push(pc);
    else pcByChild.set(pc.child, [pc]);
  }
  const unionsByPerson = new Map<string, Union[]>();
  for (const u of rawDb.unions) {
    for (const p of u.p1 === u.p2 ? [u.p1] : [u.p1, u.p2]) {
      if (p == null) continue;
      const arr = unionsByPerson.get(p);
      if (arr) arr.push(u);
      else unionsByPerson.set(p, [u]);
    }
  }
  const { groups } = groupSameAs(existingEdges, known);
  const memberSet = new Set<string>();
  const cmAll = new Map<string, string>();
  for (const [canon, ids] of groups)
    for (const id of ids) {
      memberSet.add(id);
      cmAll.set(id, canon);
    }
  const parentsOfMembers = new Set<string>();
  for (const id of memberSet) for (const pc of pcByChild.get(id) ?? []) parentsOfMembers.add(pc.parent);
  const childToParentsAll = new Map<string, Set<string>>();
  for (const pc of rawDb.parentChild) {
    const c = cmAll.get(pc.child) ?? pc.child;
    const p = cmAll.get(pc.parent) ?? pc.parent;
    if (c === p) continue;
    let s = childToParentsAll.get(c);
    if (!s) childToParentsAll.set(c, (s = new Set()));
    s.add(p);
  }
  const baseline = resolveSameAs(rawDb, existingEdges);
  const acceptedCm = new Map<string, string>();
  for (const [canon, ids] of baseline.accepted) for (const id of ids) acceptedCm.set(id, canon);
  const rejectedMembers = new Set([...memberSet].filter((id) => !acceptedCm.has(id)));
  const ctx: PreflightCtx = {
    personById,
    known,
    endpoints,
    memberSet,
    parentsOfMembers,
    pcByChild,
    unionsByPerson,
    childToParentsAll,
    acceptedCm,
    rejectedMembers,
    baselineQuarantined: baseline.quarantined,
  };
  cacheDb = rawDb;
  cacheEdges = existingEdges;
  cacheCtx = ctx;
  return ctx;
}

// Opad-søgning i den projicerede graf: nås t1 eller t2 fra `start`s forældre? Bruges både til
// "er den ene ane til den anden" (merge ville skabe ny cyklus) og "ligger start selv på en
// cyklus" (en eksisterende cyklus gennem parret ville efter merget attribueres til den nye gruppe).
function reachesUp(adj: Map<string, Set<string>>, start: string, t1: string, t2: string): boolean {
  const seen = new Set<string>();
  const stack = [...(adj.get(start) ?? [])];
  while (stack.length) {
    const n = stack.pop()!;
    if (n === t1 || n === t2) return true;
    if (seen.has(n)) continue;
    seen.add(n);
    for (const p of adj.get(n) ?? []) stack.push(p);
  }
  return false;
}

// Parret er inert når intet af validateGroups' arbejde for de ØVRIGE grupper kan påvirkes af
// alias→canonical-omskrivningen, og parrets egen skæbne ikke afhænger af runde-varierende
// kanonisering: (1) frisk 2-komponent (ingen delte endpoints med eksisterende kanter),
// (2) alias er ikke forælder til et gruppemedlem (ellers skifter dén gruppes forældre-sæt),
// (3) parrets egne forældre er ikke medlemmer af VALIDERINGS-AFVISTE grupper (accepterede
// gruppers kanonisering er runde-konstant og omskrives i udsnittet), (4) ingen af parret er ane
// til den anden eller ligger på en cyklus (ellers kan merget skabe/arve en cyklus i den
// projicerede graf).
const isInert = (ctx: PreflightCtx, alias: string, canonical: string): boolean =>
  ctx.known.has(alias) &&
  ctx.known.has(canonical) &&
  !ctx.endpoints.has(alias) &&
  !ctx.endpoints.has(canonical) &&
  !ctx.parentsOfMembers.has(alias) &&
  !(ctx.pcByChild.get(alias) ?? []).some((pc) => ctx.rejectedMembers.has(pc.parent)) &&
  !(ctx.pcByChild.get(canonical) ?? []).some((pc) => ctx.rejectedMembers.has(pc.parent)) &&
  !reachesUp(ctx.childToParentsAll, alias, alias, canonical) &&
  !reachesUp(ctx.childToParentsAll, canonical, alias, canonical);

export function previewSammeSom(
  rawDb: Db,
  existingEdges: SameAsEdge[],
  hypotetisk: SameAsEdge,
): { folder: boolean; grund: string | null } {
  const { alias, canonical } = hypotetisk;
  const ctx = getCtx(rawDb, existingEdges);

  let quarantined: QuarantineNote[];
  if (alias === canonical) {
    // Self-loop normaliseres væk i groupSameAs → resultatet er præcis baseline-kørslen.
    _previewSammeSomStats.baseline++;
    quarantined = ctx.baselineQuarantined;
  } else if (isInert(ctx, alias, canonical)) {
    _previewSammeSomStats.fast++;
    // Kør de ÆGTE checks — samme kode, samme reason-strenge, samme rækkefølge — på parrets eget
    // udsnit (egne personer, egne forældre-rækker, berørte unioner). Inertheds-garantien ovenfor
    // betyder at intet uden for udsnittet kan ændre udfaldet, og at ingen baseline-gruppes
    // karantæne-note kan nævne parret — så kun den nye gruppes egen note er relevant.
    // Forældre i accepterede grupper omskrives til deres canon — det er hvad den fulde kørsels
    // kanonisering ville gøre i hver runde, og det afgør om to forældre-sæt "er ens".
    const mapPc = (pc: ParentChild): ParentChild => {
      const canon = ctx.acceptedCm.get(pc.parent);
      return canon == null ? pc : { ...pc, parent: canon };
    };
    const mini: Db = {
      persons: [ctx.personById.get(alias)!, ctx.personById.get(canonical)!],
      unions: [...new Set([...(ctx.unionsByPerson.get(alias) ?? []), ...(ctx.unionsByPerson.get(canonical) ?? [])])],
      parentChild: [...(ctx.pcByChild.get(alias) ?? []), ...(ctx.pcByChild.get(canonical) ?? [])].map(mapPc),
    };
    quarantined = validateGroups(new Map([[canonical, [alias, canonical]]]), mini).quarantined;
  } else {
    // Sammenfiltret med eksisterende grupper/graf — kør den fulde, autoritative beregning.
    _previewSammeSomStats.fallback++;
    quarantined = resolveSameAs(rawDb, [...existingEdges, hypotetisk]).quarantined;
  }

  const karantæne = quarantined.find(
    (q) => q.members.includes(hypotetisk.alias) || q.members.includes(hypotetisk.canonical),
  );
  return karantæne ? { folder: false, grund: karantæne.reason } : { folder: true, grund: null };
}
