// 6e på mobilen (paritetsplanens batch 4): linjer, udgaver og bogens kilder bygges som på web
// (web/src/data/model.ts), med de samme delte byggere fra @daa/core. Hver trykt DAA-udgave er sin egen kilde og
// nummererer linjerne forskelligt (1939 »IV« og 2018-20 »V« kan være den samme kanoniske linje); derfor nøgles
// linjerne aldrig på den trykte kode alene. Ren funktion: rå rækker + samme_som-afbildningen ind, modellens felter ud.
import {
  buildLineage, buildSources, byggBogNr, byggErStamtavle, byggLinjeRaekker, byggUdgaveModel, stamtavleSkemaOpslag,
  type LineageSchemeRows, type Model, type RawLineageContext,
} from '@daa/core';
import type { RawExtId, RawSource } from './types';

export type UdgaveLag = Required<Pick<Model, 'lineage' | 'sourcesBy' | 'linjeRaekkerBy' | 'udgaver' | 'udgaveForPersonRaekke' | 'bogNrBy'>>;

export const TOMT_SKEMA: LineageSchemeRows = { schemes: [], entries: [], mappings: [] };

export function byggUdgaveLag(
  input: {
    extIds: RawExtId[];
    sources: RawSource[];
    lineageRows: RawLineageContext[];
    // Tomme lister, når skematabellerne ikke kunne hentes: så falder linjerne tilbage til de trykte koder (som web).
    schemeRows: LineageSchemeRows;
  },
  canonicalIdById: Record<string, string> = {},
): UdgaveLag {
  const { extIds, sources, lineageRows, schemeRows } = input;
  return {
    lineage: buildLineage(extIds, lineageRows, canonicalIdById, schemeRows, sources),
    // Kun bogens egne opslag (koordinaterne): bogensNummer må aldrig se citations-proveniensen. Ægtefællernes
    // faldback (citationer) bor i aux.sourcesBy.
    sourcesBy: buildSources(extIds, sources, canonicalIdById, stamtavleSkemaOpslag(schemeRows)),
    linjeRaekkerBy: byggLinjeRaekker(extIds, sources, canonicalIdById, schemeRows),
    ...byggUdgaveModel(sources, extIds),
    bogNrBy: byggBogNr(extIds, canonicalIdById, byggErStamtavle(lineageRows, schemeRows.schemes)),
  };
}
