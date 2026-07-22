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

// Beskæring bottom-up: levende medtages; afdøde kun med levende under sig eller efterlevende
// ægtefælle. GDPR-bemærkning: `levende` kommer fra person.levende — RLS afgør hvad klienten
// overhovedet kan se; denne funktion tilføjer ingen eksponering.
export function pruneUndertrae(
  model: Model,
  levendeById: LevendeById,
  id: string,
  edgeKonfidens: Konfidens = null,
  seen: Set<string> = new Set(),
): PresensNode | null {
  if (seen.has(id)) return null; // cyklus-/dobbeltvej-vagt
  seen.add(id);
  const levende = levendeById[id] === true;
  const boern = [...(model.indexes.childIdx[id] ?? new Set<string>())]
    .map((cid) => pruneUndertrae(model, levendeById, cid, edgeKonf(model, cid, id), seen))
    .filter((n): n is PresensNode => n != null);
  sortNodes(model, boern);
  const partnere = partnereAf(model, levendeById, id);
  const efterlevendePartner = !levende && partnere.some((p) => p.levende);
  if (!levende && boern.length === 0 && !efterlevendePartner) return null;
  return { id, levende, forbindelsesled: !levende, partnere, boern, usikker: svag(edgeKonfidens) };
}
