// Slægtskabs-algoritme — kernefunktionen "er vi i familie?" (README §5.4).
//
// BILINEAL (begge forældre): BFS opad over ALLE forældre (indexes.parentsByChild), så
// slægtskab via mor-linjen fanges lige så vel som via far-linjen — kritisk i en tæt
// sammengift adel, hvor grene forbindes ad flere linjer på én gang.
//
// MULTI-LINJE: returnerer ALLE distinkte forbindelses-linjer (ikke kun den nærmeste),
// nærmeste først. Anepar tæller som ÉN linje (helsøskende vises ikke som to). "Halv"
// markeres kun når den anden forælder faktisk er kendt og forskellig (ingen falske
// halvsøskende fra datahuller). Etiketter er kønsbestemte/moderne via person.koen, med
// kønsneutral fallback der matcher de oprindelige strenge.
//
// Rene funktioner (testbare).
import type { Koen, Konfidens, Model } from './types';

// Konfidens-rang: svag→stærk. null (uangivet) holdes uden for "svageste led"-beregningen,
// så en bunke uangivne links ikke får hver sti til at se usikker ud.
const KONF_RANK: Record<string, number> = { omstridt: 0, formodet: 1, sandsynlig: 2, sikker: 3 };

// Konfidens på forælder→barn-kanten mellem x og y (retnings-uafhængigt opslag).
function edgeKonf(model: Model, x: string, y: string): Konfidens {
  const k = model.indexes.konfByEdge;
  return k[`${x}|${y}`] ?? k[`${y}|${x}`] ?? null;
}

// ── Ane-traversal ────────────────────────────────────────────────────────────

// BFS opad → mindste generations-afstand til hver ane + forgænger-pointer (prev[ane] =
// barn-knuden ét trin tættere på start, til sti-rekonstruktion).
type Reach = { dist: Record<string, number>; prev: Record<string, string> };

function ancestorReach(model: Model, startId: string): Reach {
  const dist: Record<string, number> = { [startId]: 0 };
  const prev: Record<string, string> = {};
  const queue: string[] = [startId];
  let head = 0;
  let guard = 0;
  while (head < queue.length && guard < 100000) {
    guard++;
    const cur = queue[head++];
    const d = dist[cur];
    const parents = model.indexes.parentsByChild[cur] || [];
    for (const p of parents) {
      if (!(p in dist)) {
        // BFS over uvægtede forælder-kanter ⇒ første besøg = mindste afstand.
        // `in dist`-vagten lukker også cyklusser (skulle data have en umulig løkke).
        dist[p] = d + 1;
        prev[p] = cur;
        queue.push(p);
      }
    }
  }
  return { dist, prev };
}

// Er `anc` en (egentlig) ane til `node`? Bruges til at reducere fælles aner til de NÆRMESTE.
function isAncestorOf(model: Model, anc: string, node: string): boolean {
  if (anc === node) return false;
  const seen = new Set<string>([node]);
  const queue: string[] = [node];
  let head = 0;
  let guard = 0;
  while (head < queue.length && guard < 100000) {
    guard++;
    const cur = queue[head++];
    for (const p of model.indexes.parentsByChild[cur] || []) {
      if (p === anc) return true;
      if (!seen.has(p)) {
        seen.add(p);
        queue.push(p);
      }
    }
  }
  return false;
}

// Mest-nære fælles aner (MRCA-sættet): fælles aner som ikke selv er ane til en anden
// fælles ane. Hver svarer til en distinkt forbindelses-linje (anepar grupperes senere).
function mostRecentCommon(model: Model, ra: Reach, rb: Reach): string[] {
  const common = Object.keys(ra.dist).filter((id) => id in rb.dist);
  return common.filter((c) => !common.some((d) => d !== c && isAncestorOf(model, c, d)));
}

// Sti fra descendenten `from` op til (og med) anen `to`. prev[ane] = barn-knuden, så vi
// følger prev fra `to` NED mod `from` (langs den vej anen blev fundet) og vender om.
function pathUp(reach: Reach, from: string, to: string): string[] {
  if (from === to) return [from];
  if (!(to in reach.dist)) return [];
  const rev = [to];
  let cur = to;
  let guard = 0;
  while (cur !== from && guard < 100) {
    const child = reach.prev[cur];
    if (child == null) return [];
    rev.push(child);
    cur = child;
    guard++;
  }
  return rev.reverse();
}

// "Halv" KUN når begge sider har en anden, kendt forælder der adskiller sig. Mangler den
// anden forælder på en side, påstås intet (kunne være helsøskende med uregistreret par).
function isHalfThrough(model: Model, ra: Reach, rb: Reach, rep: string): boolean {
  const xa = ra.prev[rep];
  const xb = rb.prev[rep];
  if (xa == null || xb == null || xa === xb) return false;
  const pa = (model.indexes.parentsByChild[xa] || []).filter((p) => p !== rep);
  const pb = (model.indexes.parentsByChild[xb] || []).filter((p) => p !== rep);
  if (!pa.length || !pb.length) return false; // anden forælder ukendt på en side
  return !pa.some((p) => pb.includes(p)); // delt anden forælder ⇒ par (ikke halv)
}

// ── Etiketter ────────────────────────────────────────────────────────────────

function g(k: Koen | undefined, mand: string, kvinde: string, neutral: string): string {
  return k === 'mand' ? mand : k === 'kvinde' ? kvinde : neutral;
}

export type LabelOpts = { koenA?: Koen; koenB?: Koen; half?: boolean };

// Oversæt generations-afstande (d1 = A→LCA, d2 = B→LCA) til dansk etiket. Uden køn/half
// gengives de oprindelige kønsneutrale strenge uændret.
export function relationshipLabel(d1: number, d2: number, opts: LabelOpts = {}): string {
  const { koenA, koenB, half } = opts;
  if (d1 === 0 && d2 === 0) return 'Samme person';

  // Direkte linje — den ene er anen.
  if (d1 === 0 || d2 === 0) {
    const n = d1 + d2;
    const ancK = d1 === 0 ? koenA : koenB;
    const descK = d1 === 0 ? koenB : koenA;
    if (n === 1) return `${g(ancK, 'Far', 'Mor', 'Forælder')} & ${g(descK, 'søn', 'datter', 'barn')}`;
    if (n === 2) return `${g(ancK, 'Bedstefar', 'Bedstemor', 'Bedsteforælder')} & barnebarn`;
    if (n === 3) return `${g(ancK, 'Oldefar', 'Oldemor', 'Oldeforælder')} & oldebarn`;
    if (n === 4) return `${g(ancK, 'Tipoldefar', 'Tipoldemor', 'Tipoldeforælder')} & tipoldebarn`;
    return 'Tip-tipoldeforælder & efterkommer';
  }

  const minD = Math.min(d1, d2);
  const rem = Math.abs(d1 - d2);
  const deg = minD - 1;

  if (deg === 0) {
    // Søskende-plan.
    if (rem === 0) {
      const base =
        koenA === 'mand' && koenB === 'mand' ? 'Brødre'
        : koenA === 'kvinde' && koenB === 'kvinde' ? 'Søstre'
        : (koenA === 'mand' && koenB === 'kvinde') || (koenA === 'kvinde' && koenB === 'mand') ? 'Bror & søster'
        : 'Søskende';
      if (!half) return base;
      return base === 'Brødre' ? 'Halvbrødre'
        : base === 'Søstre' ? 'Halvsøstre'
        : base === 'Bror & søster' ? 'Halvbror & halvsøster'
        : 'Halvsøskende';
    }
    // Onkel/tante-plan: den ældre har mindst afstand til LCA.
    const elderK = d1 < d2 ? koenA : koenB;
    const youngerK = d1 < d2 ? koenB : koenA;
    const s =
      rem === 1
        ? `${g(elderK, 'Onkel', 'Tante', 'Onkel/tante')} & ${g(youngerK, 'nevø', 'niece', 'niece/nevø')}`
        : `${g(elderK, 'Grandonkel', 'Grandtante', 'Grandonkel/-tante')} & ${g(youngerK, 'grandnevø', 'grandniece', 'grandniece/-nevø')}`;
    return half ? s + ' (halv)' : s;
  }

  // Fætter/kusine-plan.
  const cousin =
    koenA === 'mand' && koenB === 'mand' ? 'fætre'
    : koenA === 'kvinde' && koenB === 'kvinde' ? 'kusiner'
    : (koenA === 'mand' && koenB === 'kvinde') || (koenA === 'kvinde' && koenB === 'mand') ? 'fætter & kusine'
    : 'fætter/kusine';
  let s = `${deg}. grads ${cousin}`;
  if (rem > 0) s += ' · ' + rem + ' gang' + (rem > 1 ? 'e' : '') + ' forskudt';
  return half ? s + ' (halv)' : s;
}

// ── Offentlig API ────────────────────────────────────────────────────────────

export type RelationStep = {
  id: string;
  name: string;
  years: string;
  isLca: boolean;
  // Konfidens på kanten der fører OP til dette trin fra det forrige (undefined for første trin).
  edgeKonfidens?: Konfidens;
};

// Én distinkt forbindelses-linje mellem A og B.
export type RelationLine = {
  label: string;
  lcaId: string;
  lcaName: string;
  coupleNames?: string; // sat når linjen går gennem et anepar ("Far & Mor")
  half: boolean;
  d1: number;
  d2: number;
  steps: RelationStep[];
  // Svageste STATEREDE konfidens på stien (null = alle led uangivet/ingen svaghed).
  weakestKonfidens: Konfidens;
  // True når stien hviler på et formodet/omstridt led — finderen skal vise usikkerhed.
  usikker: boolean;
};

export type RelationResult = {
  found: boolean;
  // Top-niveau spejler den nærmeste linje (lines[0]) — bagudkompatibelt for relate.tsx.
  label: string;
  lcaId: string | null;
  lcaName: string;
  steps: RelationStep[];
  lines: RelationLine[]; // alle distinkte linjer, nærmeste først
};

// Laveste fælles ane som id (bilineal, nærmeste). null hvis ingen påvist forbindelse.
export function lcaId(model: Model, a: string, b: string): string | null {
  if (a === b) return a;
  const mrcas = mostRecentCommon(model, ancestorReach(model, a), ancestorReach(model, b));
  if (!mrcas.length) return null;
  // Vælg den nærmeste (mindste samlede afstand) deterministisk.
  const ra = ancestorReach(model, a);
  const rb = ancestorReach(model, b);
  return mrcas.slice().sort((x, y) => ra.dist[x] + rb.dist[x] - (ra.dist[y] + rb.dist[y]) || (x < y ? -1 : 1))[0];
}

function buildSteps(model: Model, ra: Reach, rb: Reach, aId: string, bId: string, rep: string): RelationStep[] {
  const cA = pathUp(ra, aId, rep); // A … LCA
  const cB = pathUp(rb, bId, rep); // B … LCA
  const down = cB.slice(0, -1).reverse(); // LCA-eksklusiv, vendt nedad mod B
  const fullIds = cA.concat(down);
  const lcaIndex = cA.length - 1;
  return fullIds.map((pid, idx) => {
    const p = model.byId[pid];
    // Kanten op til dette trin = mellem forrige knude og denne (parent↔barn, retning ligegyldig).
    const edgeKonfidens = idx > 0 ? edgeKonf(model, fullIds[idx - 1], pid) : undefined;
    return { id: pid, name: p?.name ?? '', years: p?.years ?? '', isLca: idx === lcaIndex, edgeKonfidens };
  });
}

// Svageste staterede konfidens på en sti (null hvis alle led er uangivet).
function weakestOnPath(steps: RelationStep[]): Konfidens {
  let weakest: Konfidens = null;
  for (const s of steps) {
    const k = s.edgeKonfidens;
    if (k == null) continue;
    if (weakest == null || KONF_RANK[k] < KONF_RANK[weakest]) weakest = k;
  }
  return weakest;
}

// Beregn slægtskab mellem to personer: alle distinkte linjer (etiket + trin-for-trin-kæde).
export function computeRelationship(model: Model, aId: string, bId: string): RelationResult {
  const a = model.byId[aId];
  const b = model.byId[bId];
  const none: RelationResult = { found: false, label: '', lcaId: null, lcaName: '', steps: [], lines: [] };
  if (!a || !b) return none;
  if (a.id === b.id) {
    const line: RelationLine = { label: 'Samme person', lcaId: a.id, lcaName: a.name, half: false, d1: 0, d2: 0, steps: [], weakestKonfidens: null, usikker: false };
    return { found: true, label: line.label, lcaId: a.id, lcaName: a.name, steps: [], lines: [line] };
  }

  const ra = ancestorReach(model, a.id);
  const rb = ancestorReach(model, b.id);
  const mrcas = mostRecentCommon(model, ra, rb);
  if (!mrcas.length) {
    return { found: false, label: 'Ingen påvist forbindelse', lcaId: null, lcaName: '', steps: [], lines: [] };
  }

  const mrcaSet = new Set(mrcas);
  const used = new Set<string>();
  const lines: RelationLine[] = [];

  for (const c of mrcas) {
    if (used.has(c)) continue;
    // Anepar: en anden MRCA der er ægtefælle til c → samme linje (helsøskende ≠ to linjer).
    const spouseIds = (model.indexes.spousesBy[c] || []).map((s) => s.id).filter((id): id is string => !!id);
    const partner = spouseIds.find((id) => mrcaSet.has(id) && !used.has(id) && id !== c) ?? null;
    used.add(c);
    if (partner) used.add(partner);

    const couple = partner != null;
    const rep = couple ? (c < partner! ? c : partner!) : c;
    const d1 = ra.dist[rep];
    const d2 = rb.dist[rep];
    const half = !couple && isHalfThrough(model, ra, rb, rep);
    const label = relationshipLabel(d1, d2, { koenA: a.koen, koenB: b.koen, half });
    const steps = buildSteps(model, ra, rb, a.id, b.id, rep);
    const coupleNames = couple ? `${model.byId[rep]?.name ?? ''} & ${model.byId[rep === c ? partner! : c]?.name ?? ''}` : undefined;
    const weakestKonfidens = weakestOnPath(steps);
    const usikker = weakestKonfidens != null && KONF_RANK[weakestKonfidens] <= KONF_RANK.formodet;
    lines.push({ label, lcaId: rep, lcaName: model.byId[rep]?.name ?? '', coupleNames, half, d1, d2, steps, weakestKonfidens, usikker });
  }

  // Nærmeste først: mindste samlede afstand, så mest balancerede, så stærkeste led, så id.
  const weakRank = (k: Konfidens) => (k == null ? 99 : KONF_RANK[k]); // uangivet rangerer som "stærkt" (ikke straffet)
  lines.sort(
    (x, y) =>
      x.d1 + x.d2 - (y.d1 + y.d2) ||
      Math.max(x.d1, x.d2) - Math.max(y.d1, y.d2) ||
      weakRank(y.weakestKonfidens) - weakRank(x.weakestKonfidens) ||
      (x.lcaId < y.lcaId ? -1 : x.lcaId > y.lcaId ? 1 : 0),
  );

  const p = lines[0];
  return { found: true, label: p.label, lcaId: p.lcaId, lcaName: p.lcaName, steps: p.steps, lines };
}
