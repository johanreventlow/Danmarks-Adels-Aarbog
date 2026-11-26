// Bogens formelle navneform (plan docs/superpowers/plans/2026-11-26-linjernes-adelsnavn.md). Partiklen og stavemåden
// følger linjen (IV »de Reventlou«, V »af Reventlow«: et kildebundet `adelsnavn`-faktum på lineage); titelordet følger
// personen (visningscachens adelstitel, allerede kønsbøjet). Ren visningsregel: der skrives intet i navn eller cache.
import { erAdelsTitel } from './adelsTitler';
import { udenSlaegtsnavnTilSidst } from './slaegtsnavn';
import type { Lineage } from './types';

/** lineage-id (streng) → linjens adelsnavn, fx `{ '5': 'af Reventlow' }`. */
export type LinjeAdelsnavne = Record<string, string>;

const tekst = (v: string | null | undefined): string => (v ?? '').trim();

/**
 * »Johan Martin greve af Reventlow«: fornavne + adelstitel med lille + linjens adelsnavn — samme form som
 * præsenslistens hovedrække (`formatAnkerNavn`). `null`, når en del mangler, eller titlen ikke er en adelstitel.
 */
export function formelNavneform(input: {
  fornavne: string | null | undefined;
  titel: string | null | undefined;
  adelsnavn: string | null | undefined;
  slaegtsnavn?: string | null;
}): string | null {
  const titel = tekst(input.titel);
  const adelsnavn = tekst(input.adelsnavn);
  const slaegtsnavn = tekst(input.slaegtsnavn);
  const fornavne = slaegtsnavn ? udenSlaegtsnavnTilSidst(tekst(input.fornavne), slaegtsnavn) : tekst(input.fornavne);
  if (!fornavne || !adelsnavn || !titel || !erAdelsTitel(titel)) return null;
  return `${fornavne} ${titel.toLowerCase()} ${adelsnavn}`;
}

/**
 * Personens adelsnavn ud fra linjerne: præcis én distinkt regel, ellers `null` (fail-closed, fx en samme_som-foldet
 * person i både IV og V). Er personen stifter af en linje med regel, `null`: stifterens navn kommer fra hans eget
 * patent (V: Conrad »de Reventlow« 1673; bevillingen 1692 på »af Reventlow« gælder sønner og descendenter).
 */
export function adelsnavnForLinjer(
  lineageIds: readonly string[],
  regler: LinjeAdelsnavne,
  stifterAf: readonly string[] = [],
): string | null {
  if (stifterAf.some((id) => tekst(regler[id]) !== '')) return null;
  const fundne = new Set(lineageIds.map((id) => tekst(regler[id])).filter((r) => r !== ''));
  return fundne.size === 1 ? [...fundne][0] : null;
}

/** Lineage-id fra en `lineageContextKey` (`slaegt:…:lineage:<id>:scheme:…`); `null` for rå koder og tekniske nøgler. */
export function lineageIdAfNoegle(key: string): string | null {
  const m = /(?:^|:)lineage:([^:]+)(?::|$)/.exec(key);
  return m && !key.startsWith('legacy-source:') ? m[1] : null;
}

/** Personens adelsnavn fra læserens linjemodel (web): personens linjenøgler + stifterskab i listen. */
export function personensAdelsnavn(personId: string, lineage: Lineage, regler: LinjeAdelsnavne): string | null {
  const ids = (lineage.byPerson[personId] ?? []).map(lineageIdAfNoegle).filter((id): id is string => id != null);
  const stifterAf = lineage.list
    .filter((l) => l.headId === personId)
    .map((l) => lineageIdAfNoegle(l.linje))
    .filter((id): id is string => id != null);
  return adelsnavnForLinjer(ids, regler, stifterAf);
}
