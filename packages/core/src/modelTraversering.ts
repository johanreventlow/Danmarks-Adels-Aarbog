// Flyttet fra web/src/data/model.ts (mobil-paritet, batch 6), så stamtræets fokusrækker (fokusTrae.ts) kan bo i
// core. Web re-eksporterer dem fra model.ts. Mobilens egne childrenOf/parentsOf i data/selectors.ts er ikke de samme
// (de læser childrenByUnion) og er bevidst urørte.
import type { Model, ModelPerson } from './types';

// Børn af en person som ModelPerson[] (childIdx er Sets). Delt af stamtræ-visningen.
export function childrenOf(model: Model, id: string): ModelPerson[] {
  return [...(model.indexes.childIdx[id] ?? new Set<string>())]
    .map((cid) => model.byId[cid])
    .filter(Boolean) as ModelPerson[];
}

// Forældre af en person som ModelPerson[] (fra primær fødselsfamilie, far før mor jf.
// compareParentOrder i loaderen). Symmetrisk med childrenOf; bruges af ane-drillen i variant B.
// Matcher mobilens selectors.parentsOf.
export function parentsOf(model: Model, id: string): ModelPerson[] {
  return (model.indexes.parentsByChild[id] ?? [])
    .map((pid) => model.byId[pid])
    .filter(Boolean) as ModelPerson[];
}
