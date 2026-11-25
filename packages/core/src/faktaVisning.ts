// Personens fakta med kilde — de rene dele af web's PersonFakta-komponent (web/src/components/PersonFakta.tsx),
// flyttet til core (mobil-paritet, batch 7), så web og mobil bruger samme faktanavne, samme notetekst og samme
// gruppering af »Kun i …«. Selve visningen (byggUdgaveFakta) bor i editionFacts.ts.
import type { KunIUdgave, UdgaveNote } from './editionFacts';

const NAVN: Record<string, string> = {
  navn: 'Navn', tilnavn: 'Tilnavn', fødsel: 'Født', dåb: 'Døbt', titel: 'Titel', dekoration: 'Dekoration',
  adling: 'Adlet', floruit: 'Nævnt', klosterindgang: 'Klosterindgang', overhoved: 'Overhoved', død: 'Død',
  dødsårsag: 'Dødsårsag', begravelse: 'Begravet',
};
export const faktaTypeNavn = (t: string) => NAVN[t] ?? t.charAt(0).toUpperCase() + t.slice(1);

export function udgaveNoteTekst(note: UdgaveNote): string {
  return note.art === 'enig'
    ? `✓ også i ${note.udgave.label}`
    : `${note.udgave.label} skriver: ${note.vaerdier.join('; ')}`;
}

// »Kun i …« grupperet pr. udgave i core's rækkefølge (nyeste udgave først).
export function grupperKunI(rows: readonly KunIUdgave[]): { udgave: KunIUdgave['udgave']; raekker: KunIUdgave[] }[] {
  const kunI: { udgave: KunIUdgave['udgave']; raekker: KunIUdgave[] }[] = [];
  for (const k of rows) {
    const g = kunI.find((x) => x.udgave.sourceId === k.udgave.sourceId);
    if (g) g.raekker.push(k);
    else kunI.push({ udgave: k.udgave, raekker: [k] });
  }
  return kunI;
}
