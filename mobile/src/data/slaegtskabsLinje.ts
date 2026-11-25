// Slægtskab som kontekst over navnet på personskærmen (paritetsplanens batch 7): »Din tipoldefar«, »Gift med
// Christian Reventlow, din onkel«. Konteksten beregnes af @daa/core's slaegtskabsKontekst (samme som web); her
// formes den til tekststykker efter web's SlaegtskabsLinje (web/src/components/SlaegtskabsLinje.tsx), så skærmen kun
// skal tegne dem. Usikkerhed siges altid med ord (invariant 7) og sidder på blodsforbindelsen, ikke på ægteskabet.
import type { Forbindelse, SlaegtskabsKontekst } from '@daa/core';

export type LinjeDel =
  | { art: 'tekst'; tekst: string }
  | { art: 'tvivl'; tekst: string } // usikkerhedsordet i faresignalets farve
  | { art: 'person'; tekst: string; personId: string } // ægtefællen som link
  | { art: 'vej'; tekst: string; fra: string; til: string }; // »Se vejen« → »Er vi i familie?«

export type SlaegtskabsLinjeVisning = { dele: LinjeDel[]; daempet: boolean };

const stort = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

function ordMedSikkerhed(f: Forbindelse, foerst: boolean): LinjeDel[] {
  if (f.sikkerhed === 'sikker') return [{ art: 'tekst', tekst: foerst ? stort(f.ord) : f.ord }];
  const tvivl = f.sikkerhed === 'sandsynligvis' ? 'sandsynligvis' : 'omstridt:';
  return [{ art: 'tvivl', tekst: foerst ? stort(tvivl) : tvivl }, { art: 'tekst', tekst: ` ${f.ord}` }];
}

const vej = (f: Forbindelse, fra: string, til: string): LinjeDel[] => [
  { art: 'tekst', tekst: ' · ' },
  { art: 'vej', tekst: f.veje > 1 ? `Se alle ${f.veje} veje` : 'Se vejen', fra, til },
];

export function slaegtskabsLinje(k: SlaegtskabsKontekst, meId: string | null, focusId: string): SlaegtskabsLinjeVisning | null {
  if (k.art === 'skjult' || !meId) return null;
  if (k.art === 'ingen') return { dele: [{ art: 'tekst', tekst: 'Aarbogen viser ingen fælles ane med dig' }], daempet: true };
  if (k.art === 'dig') return { dele: [{ art: 'tekst', tekst: 'Det er dig' }], daempet: false };
  if (k.art === 'min-aegtefaelle') return { dele: [{ art: 'tekst', tekst: 'Din ægtefælle' }], daempet: false };
  const bekraeftet: LinjeDel[] = k.bekraeftetAndenVej ? [{ art: 'tekst', tekst: ' · bekræftet ad en anden linje' }] : [];
  if (k.art === 'blod') return { dele: [...ordMedSikkerhed(k, true), ...bekraeftet, ...vej(k, meId, focusId)], daempet: false };
  return {
    dele: [
      { art: 'tekst', tekst: 'Gift med ' },
      { art: 'person', tekst: k.aegtefaelleNavn, personId: k.aegtefaelleId },
      { art: 'tekst', tekst: ', ' },
      ...ordMedSikkerhed(k, false), ...bekraeftet, ...vej(k, meId, k.aegtefaelleId),
    ],
    daempet: false,
  };
}

// Den samlede tekst (til skærmlæser og test).
export const linjeTekst = (v: SlaegtskabsLinjeVisning): string => v.dele.map((d) => d.tekst).join('');
