// Præsensliste-kernen: bottom-up-beskæring + anker-klatring (spec 2026-07-22 §5).
// Rene funktioner på den COLLAPSEDE model (kanoniske id'er — kald kanoniserPresensGrundlag først).
import { KONFIDENS_RANK } from './types';
import type { Konfidens, Model } from './types';

export type LevendeById = Record<string, boolean>;
export type PresensPartner = { id: string; levende: boolean };
export type PresensNode = {
  id: string;
  levende: boolean;
  forbindelsesled: boolean; // afdød, kun medtaget fordi noget levende hænger under (bogens s.15-regel)
  partnere: PresensPartner[];
  boern: PresensNode[];
  usikker: boolean; // formodet/omstridt konfidens på kanten OP til denne node (invariant 7)
  // Personen er allerede vist FULDT ud et andet sted i SAMME gren (fx et dobbelt-fætterskab,
  // ikke ualmindeligt i tætsammengift adel) — denne forekomst er en tom stub uden undertræ.
  // Krydsning MELLEM grene dækkes separat af dobbelt_naaet-advarslen og påvirkes ikke af dette.
  krydsReference: boolean;
};

const svag = (k: Konfidens): boolean => k != null && KONFIDENS_RANK[k] <= KONFIDENS_RANK.formodet;

function edgeKonf(model: Model, child: string, parent: string): Konfidens {
  return model.indexes.konfByEdge[`${child}|${parent}`] ?? null;
}

function partnereAf(model: Model, levendeById: LevendeById, id: string): PresensPartner[] {
  return (model.indexes.spousesBy[id] ?? [])
    .map((s) => s.id)
    .filter((sid): sid is string => sid != null)
    .map((sid) => ({ id: sid, levende: levendeById[sid] === true }));
}

function sortNodes(model: Model, ns: PresensNode[]): void {
  ns.sort((a, b) => (model.byId[a.id]?.born ?? 9999) - (model.byId[b.id]?.born ?? 9999) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
}

// DAA er patrilineær: linje/gren nedarves gennem faderen (jf. compareParentOrder i
// web/src/data/model.ts, "DAA er patrilineær, linje/nr følger mandslinjen"). Et barn med TO
// registrerede forældre hører derfor KUN til under faderens efterkommer-liste — aldrig moderens,
// selv når begge er blod-Reventlow (fx to grene der gifter sig sammen, brugerfund 2026-07-23).
// Har barnet kun ÉN registreret forælder, er der intet at vælge imellem (aldrig datatab). Er
// faderen ikke selv nået nogen steder i denne præsensliste, dukker barnet ikke stille op under
// moderen i stedet — det fanges af den eksisterende levende_uden_gren-advarsel (§7), som er den
// rette kanal for redaktionel opmærksomhed, ikke en stille fejlplacering.
function patrilinealForaelder(model: Model, childId: string): string | null {
  const par = model.indexes.parentsByChild[childId] ?? [];
  if (par.length <= 1) return par[0] ?? null;
  const faedre = par.filter((p) => model.byId[p]?.koen === 'mand');
  if (faedre.length === 1) return faedre[0];
  return [...par].sort()[0]; // ingen (eller >1, datafejl) far registreret — deterministisk fallback
}

// Beskæring bottom-up: levende medtages; afdøde kun med levende under sig eller efterlevende
// ægtefælle. GDPR-bemærkning: `levende` kommer fra person.levende — RLS afgør hvad klienten
// overhovedet kan se; denne funktion tilføjer ingen eksponering.
//
// To adskilte spor forhindrer uendelig rekursion/gentagelse:
// - `paaVej` — id'er PÅ DEN AKTUELLE rekursions-sti. Genfund her er en ÆGTE cyklus i data
//   (skal ikke forekomme i gyldige slægtsdata) → beskæres defensivt til null, som hidtil.
// - `alleredeVist` — id'er der ALLEREDE er fuldt bygget og BEHOLDT et andet sted i SAMME
//   kald til `buildGren` (delt på tværs af søskende-sidegrene, ikke kun inden for én undertræ-
//   sti). Genfund her er et gyldigt konvergent slægtskab (fx dobbelt-fætterskab), ikke en fejl
//   → returnerer en krydshenvisnings-stub i stedet for at duplikere undertræet eller stille
//   droppe grenen. Tilføjes KUN når noden faktisk beholdes (ikke ved beskæring til null),
//   så en tidligere forgæves gren aldrig blokerer en senere gyldig forekomst af samme id.
export function pruneUndertrae(
  model: Model,
  levendeById: LevendeById,
  id: string,
  edgeKonfidens: Konfidens = null,
  paaVej: Set<string> = new Set(),
  alleredeVist: Set<string> = new Set(),
): PresensNode | null {
  if (paaVej.has(id)) return null;
  if (alleredeVist.has(id)) {
    return { id, levende: levendeById[id] === true, forbindelsesled: levendeById[id] !== true, partnere: [], boern: [], usikker: false, krydsReference: true };
  }
  paaVej.add(id);
  const levende = levendeById[id] === true;
  const boern = [...(model.indexes.childIdx[id] ?? new Set<string>())]
    .filter((cid) => patrilinealForaelder(model, cid) === id)
    .map((cid) => pruneUndertrae(model, levendeById, cid, edgeKonf(model, cid, id), paaVej, alleredeVist))
    .filter((n): n is PresensNode => n != null);
  sortNodes(model, boern);
  paaVej.delete(id);
  const partnere = partnereAf(model, levendeById, id);
  const efterlevendePartner = !levende && partnere.some((p) => p.levende);
  if (!levende && boern.length === 0 && !efterlevendePartner) return null;
  alleredeVist.add(id);
  return { id, levende, forbindelsesled: !levende, partnere, boern, usikker: svag(edgeKonfidens), krydsReference: false };
}

import { sortAnkre, stiOverskrift } from './presensLabels';
import type { PresensAnker, SoeskendeSammensaetning } from './presensLabels';
import type { Koen } from './types';

export type PresensGruppe = {
  overskrift: string;
  niveau: number; // generationsafstand: 1 = søskende/mor-plan, 2 = fars niveau …
  art: 'soeskende' | 'foraelder' | 'enke';
  roedder: PresensNode[];
  usikker: boolean;
};
export type PresensGren = { anker: PresensAnker; ankerBlok: PresensNode; grupper: PresensGruppe[] };
export type PresensAdvarsel = {
  art: 'levende_uden_gren' | 'dobbelt_naaet' | 'anker_konflikt';
  personId: string | null;
  besked: string;
};
export type PresensListe = { grene: PresensGren[]; advarsler: PresensAdvarsel[] };

// Søskende af p: børn af p's forældre, minus p selv.
function soeskendeAf(model: Model, p: string): string[] {
  const ud = new Set<string>();
  for (const par of model.indexes.parentsByChild[p] ?? [])
    for (const c of model.indexes.childIdx[par] ?? new Set<string>()) if (c !== p) ud.add(c);
  return [...ud];
}

// Blod- vs gift-ind-forælder (spec §3): gift-ind-personer står typisk uden op-kobling i
// grafen (deres forældre er kun parentes-noter) — blodforælderen er den med egen op-kobling.
// Tie-break: mand først (DAA er patrilineær i PoC-data), dernæst laveste id. HEURISTIK,
// dokumenteret i spec §5 — fejlklassifikation giver en forkert-benævnt gruppe, aldrig datatab.
function blodOgGiftInd(model: Model, cur: string): { blod: string | null; giftInd: string | null } {
  const par = model.indexes.parentsByChild[cur] ?? [];
  if (par.length === 0) return { blod: null, giftInd: null };
  if (par.length === 1) return { blod: par[0], giftInd: null };
  // Patrilineær FØRST (konsistent med patrilinealForaelder, §"patrilineær efterkommer-tilhør"):
  // en registreret far er ALTID blod-forælderen ved klatring, uanset hvor righoldig hver sides
  // dokumenterede herkomst er. Brugerfund 2026-07-23 (task-review): den tidligere rigdoms-først-
  // heuristik kunne vælge MODEREN som "blod", når faderen manglede egen registreret herkomst men
  // moderen havde sin — og det patrilineære søskende-filter ekskluderede da fejlagtigt hendes
  // øvrige børn (inkl. ankerets EGNE fulde søskende) fra grenen. Uden en kendt far (begge/ingen
  // "mand") falder vi tilbage til den oprindelige rigdoms-heuristik som ren tie-break.
  const faedre = par.filter((p) => model.byId[p]?.koen === 'mand');
  if (faedre.length === 1) {
    const blod = faedre[0];
    return { blod, giftInd: par.find((p) => p !== blod) ?? null };
  }
  const score = (p: string): number =>
    ((model.indexes.parentsByChild[p] ?? []).length > 0 || soeskendeAf(model, p).length > 0 ? 2 : 0) +
    (model.byId[p]?.koen === 'mand' ? 1 : 0);
  const sorted = [...par].sort((a, b) => score(b) - score(a) || (a < b ? -1 : a > b ? 1 : 0));
  return { blod: sorted[0], giftInd: sorted[1] ?? null };
}

// Er et af de andre ankre i rootId's undertræ (inkl. rootId selv)? → sidegrenen har sin egen
// gren-sektion og springes over (spec §5 trin 6: grenene partitionerer sig selv).
function indeholderAnker(model: Model, rootId: string, andreAnkre: Set<string>): boolean {
  const queue = [rootId];
  const seen = new Set<string>(queue);
  let head = 0;
  while (head < queue.length) {
    const cur = queue[head++];
    if (andreAnkre.has(cur)) return true;
    for (const c of model.indexes.childIdx[cur] ?? new Set<string>())
      if (!seen.has(c)) { seen.add(c); queue.push(c); }
  }
  return false;
}

function koenSammensaetning(model: Model, ids: string[]): SoeskendeSammensaetning {
  const s: SoeskendeSammensaetning = { maend: 0, kvinder: 0, ukendt: 0 };
  for (const id of ids) {
    const k = model.byId[id]?.koen;
    if (k === 'mand') s.maend++; else if (k === 'kvinde') s.kvinder++; else s.ukendt++;
  }
  return s;
}

// Enkelt-person-node uden undertræ (gift-ind-forælder, enke, nød-anker).
function blad(model: Model, levendeById: LevendeById, id: string): PresensNode {
  const levende = levendeById[id] === true;
  return { id, levende, forbindelsesled: !levende, partnere: partnereAf(model, levendeById, id), boern: [], usikker: false, krydsReference: false };
}

const ART_ORDEN: Record<PresensGruppe['art'], number> = { soeskende: 0, foraelder: 1, enke: 2 };

function buildGren(model: Model, levendeById: LevendeById, anker: PresensAnker, andreAnkre: Set<string>): PresensGren {
  // Delt på tværs af HELE grenens opbygning (ankerblok + alle sidegrene på alle niveauer), så en
  // person nået ad to veje inden for samme gren vises fuldt ud én gang og som krydshenvisning
  // resten af stederne (spec 2026-07-22, bruger-beslutning 2026-07-22 om dobbelt-fætterskaber).
  const alleredeVist = new Set<string>();
  // Ankeret medtages ALTID — også hvis beskæringen ellers ville fjerne det.
  const ankerBlok = pruneUndertrae(model, levendeById, anker.personId, null, new Set(), alleredeVist) ?? blad(model, levendeById, anker.personId);
  alleredeVist.add(anker.personId); // også ved blad()-fallback, så senere fund af samme id korrekt krydshenviser
  const grupper: PresensGruppe[] = [];
  const kaede: Koen[] = [];
  let cur = anker.personId;
  const beskyt = new Set<string>([anker.personId]); // mod umulige forfader-cyklusser
  for (let guard = 0; guard < 50; guard++) {
    const { blod, giftInd } = blodOgGiftInd(model, cur);
    const niveau = kaede.length + 1;
    // 1) Søskende-sidegrene: blodforfaderens øvrige børn.
    if (blod != null) {
      const roedder = [...(model.indexes.childIdx[blod] ?? new Set<string>())]
        .filter((c) => c !== cur && !indeholderAnker(model, c, andreAnkre) && patrilinealForaelder(model, c) === blod)
        .map((c) => pruneUndertrae(model, levendeById, c, edgeKonf(model, c, blod), new Set(), alleredeVist))
        .filter((n): n is PresensNode => n != null);
      sortNodes(model, roedder);
      if (roedder.length > 0) {
        grupper.push({
          art: 'soeskende', niveau,
          overskrift: stiOverskrift(kaede, { slags: 'soeskende', sammensaetning: koenSammensaetning(model, roedder.map((r) => r.id)) }),
          roedder,
          usikker: svag(edgeKonf(model, cur, blod)) || roedder.some((r) => r.usikker),
        });
      }
    }
    // 2) Levende gift-ind-forælder: MOR / FAR / FARMOR …
    if (giftInd != null && levendeById[giftInd] === true) {
      grupper.push({
        art: 'foraelder', niveau,
        overskrift: stiOverskrift(kaede, { slags: 'foraelder', koen: model.byId[giftInd]?.koen ?? null }),
        roedder: [blad(model, levendeById, giftInd)],
        usikker: svag(edgeKonf(model, cur, giftInd)),
      });
    }
    // 3) Enke efter afdød blodforfader (som ikke er gift-ind-forælderen — hun har egen gruppe).
    if (blod != null && levendeById[blod] !== true) {
      const enker = partnereAf(model, levendeById, blod).filter((p) => p.levende && p.id !== giftInd);
      if (enker.length > 0) {
        grupper.push({
          art: 'enke', niveau,
          overskrift: stiOverskrift([...kaede, model.byId[blod]?.koen ?? null], { slags: 'enke' }),
          roedder: enker.map((p) => blad(model, levendeById, p.id)),
          usikker: false,
        });
      }
    }
    if (blod == null || beskyt.has(blod)) break;
    beskyt.add(blod);
    kaede.push(model.byId[blod]?.koen ?? null);
    cur = blod;
  }
  grupper.sort((a, b) => a.niveau - b.niveau || ART_ORDEN[a.art] - ART_ORDEN[b.art] || (a.overskrift < b.overskrift ? -1 : a.overskrift > b.overskrift ? 1 : 0));
  return { anker, ankerBlok, grupper };
}

function samlIds(n: PresensNode, ud: Set<string>): void {
  ud.add(n.id);
  for (const p of n.partnere) ud.add(p.id);
  for (const b of n.boern) samlIds(b, ud);
}

export function buildPresensListe(model: Model, ankre: PresensAnker[], levendeById: LevendeById): PresensListe {
  const advarsler: PresensAdvarsel[] = [];
  const sorteret = sortAnkre(ankre);
  const set = new Map<string, PresensAnker>();
  for (const a of sorteret) {
    const key = `${a.linje}|${a.gren ?? ''}`;
    const anden = set.get(key);
    if (anden) advarsler.push({ art: 'anker_konflikt', personId: a.personId, besked: `To overhoveder udpeget for "${a.raaVaerdi}" (person ${anden.personId} og ${a.personId})` });
    else set.set(key, a);
  }
  const ankerIds = new Set(sorteret.map((a) => a.personId));
  const grene = sorteret.map((a) =>
    buildGren(model, levendeById, a, new Set([...ankerIds].filter((id) => id !== a.personId))),
  );
  // Dæknings-advarsler (spec §7): rapportering, aldrig skrivning.
  const naaet = new Map<string, number>();
  for (const g of grene) {
    const ids = new Set<string>();
    samlIds(g.ankerBlok, ids);
    for (const gr of g.grupper) for (const r of gr.roedder) samlIds(r, ids);
    for (const id of ids) naaet.set(id, (naaet.get(id) ?? 0) + 1);
  }
  for (const [id, n] of naaet)
    if (n > 1) advarsler.push({ art: 'dobbelt_naaet', personId: id, besked: `${model.byId[id]?.name ?? id} optræder i ${n} grene — muligt identitets-dublet eller overlappende ankre` });
  for (const p of model.persons)
    if (levendeById[p.id] === true && !naaet.has(p.id))
      advarsler.push({ art: 'levende_uden_gren', personId: p.id, besked: `${p.name} er levende, men indgår i ingen gren — hul i ankersættet eller manglende slægtskabskant` });
  advarsler.sort((a, b) => a.art.localeCompare(b.art) || String(a.personId).localeCompare(String(b.personId)));
  return { grene, advarsler };
}

// Fold rå id'er til kanoniske (samme_som-collapse). Levende = OR over komponentens medlemmer.
export function kanoniserPresensGrundlag(
  model: Model,
  ankre: PresensAnker[],
  levendeById: LevendeById,
): { ankre: PresensAnker[]; levendeById: LevendeById } {
  const canon = model.canonicalIdById ?? {};
  const levende: LevendeById = {};
  for (const [id, lv] of Object.entries(levendeById)) {
    const cid = canon[id] ?? id;
    levende[cid] = levende[cid] === true || lv === true;
  }
  const ud = new Map<string, PresensAnker>();
  for (const a of ankre) {
    const cid = canon[a.personId] ?? a.personId;
    if (!ud.has(cid)) ud.set(cid, { ...a, personId: cid });
  }
  return { ankre: [...ud.values()], levendeById: levende };
}
