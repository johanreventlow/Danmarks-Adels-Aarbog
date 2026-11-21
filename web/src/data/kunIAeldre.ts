import { kunIAeldreUdgave } from '@daa/core';
import type { Model } from './types';

export type KunIAeldreTekst = { maerke: string; forklaring: string; linje: string };

// En nulevende står også i den nyere udgave (projektejeren 2026-11-21): aldrig »kun i« for en levende.
export function kunIAeldreTekst(model: Model, personId: string): KunIAeldreTekst | null {
  if (model.byId[personId]?.levende) return null;
  const resultat = kunIAeldreUdgave(personId, model.indexes.parentsByChild[personId] ?? [], model.bogNrBy, model.udgaver);
  if (!resultat) return null;
  const labels = new Map((model.udgaver ?? []).map((u) => [u.sourceId, u.label]));
  const kun = resultat.kunI.map((sid) => labels.get(sid)).filter((label): label is string => label != null).join(' og ');
  const ikke = labels.get(resultat.ikkeI);
  if (!kun || ikke == null) return null;
  return {
    maerke: `Kun i ${kun}`,
    forklaring: `Står i ${kun}, men ikke i ${ikke}.`,
    linje: `Nævnes kun i ${kun} og er ikke med i ${ikke}.`,
  };
}
