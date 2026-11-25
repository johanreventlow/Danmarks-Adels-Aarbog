import { kunIAeldreUdgave } from './kunIAeldreUdgave';
import type { Model } from './types';

// kunISourceIds: de udgaver (source-id), barnet står i — personsiden gør navnet til et link, når en af dem er valgt.
export type KunIAeldreTekst = { maerke: string; forklaring: string; linje: string; kunISourceIds: string[] };

// En nulevende står også i den nyere udgave (projektejeren 2026-11-21): aldrig »kun i« for en levende.
export function kunIAeldreTekst(model: Model, personId: string): KunIAeldreTekst | null {
  if (model.byId[personId]?.levende) return null;
  const resultat = kunIAeldreUdgave(personId, model.indexes.parentsByChild[personId] ?? [], model.bogNrBy, model.udgaver);
  if (!resultat) return null;
  const labels = new Map((model.udgaver ?? []).map((u) => [u.sourceId, u.label]));
  const kendte = resultat.kunI.filter((sid) => labels.has(sid));
  const kun = kendte.map((sid) => labels.get(sid)!).join(' og ');
  const ikke = labels.get(resultat.ikkeI);
  if (!kun || ikke == null) return null;
  return {
    maerke: `Kun i ${kun}`,
    forklaring: `Står i ${kun}, men ikke i ${ikke}.`,
    linje: `Nævnes kun i ${kun} og er ikke med i ${ikke}.`,
    kunISourceIds: kendte,
  };
}
