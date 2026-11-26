// Personskærmens »Besiddelser« i den valgte udgave (mobil-paritet, rest fra batch 6). Udgave-reglen er @daa/core's
// godserIUdgave — samme som web's personside. Web viser ét navn pr. gods; mobilen viser også perioden, så samme gods i
// flere rækker (to ejerperioder, eller én række pr. udgave efter samme_som-foldningen) samles til én tag med alle
// perioder i stedet for at stå to gange eller miste en periode.
import { godserIUdgave, type UdgaveFaktaInput } from '@daa/core';
import type { EstateRef } from './types';

export type GodsVisning = { id: string; navn: string; perioder: string };

export function godserTilVisning(
  estates: readonly EstateRef[],
  faktaInput: UdgaveFaktaInput | null,
  udgaver: readonly { sourceId: string }[],
  valgtUdgave: string | null,
): GodsVisning[] {
  const ud = new Map<string, { navn: string; perioder: string[] }>();
  for (const e of godserIUdgave(estates, faktaInput, udgaver, valgtUdgave)) {
    const g = ud.get(e.id) ?? { navn: e.navn, perioder: [] };
    if (e.period && !g.perioder.includes(e.period)) g.perioder.push(e.period);
    ud.set(e.id, g);
  }
  return [...ud].map(([id, g]) => ({ id, navn: g.navn, perioder: g.perioder.join(', ') }));
}
