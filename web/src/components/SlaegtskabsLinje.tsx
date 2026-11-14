// Slægtskab som kontekst over navnet (webredesign fase 8): »Din tipoldefar«, »Gift med Christian Reventlow, din
// onkel«. Ren visning af en SlaegtskabsKontekst (beregnet i data/slaegtskab.ts). Usikkerhed siges altid med ord
// (invariant 7) og sidder på blodsforbindelsen, ikke på ægteskabet. Personsiden nævner aldrig »dobbelt«
// slægtskab: ordet og sikkerheden kommer fra den nærmeste vej, og »Se alle N veje« fører til »Er vi i familie?«.
import type { CSSProperties, ReactNode } from 'react';
import { T } from '../theme';
import { Link } from '../Link';
import { personPath, slaegtskabPath } from '../data/nav';
import type { Forbindelse, SlaegtskabsKontekst } from '../data/slaegtskab';

const stil: CSSProperties = { margin: 0, fontFamily: T.serif, fontSize: 17, lineHeight: 1.35, fontStyle: 'italic', color: T.bordeaux };
const linkStil: CSSProperties = { color: T.bordeaux, textDecoration: 'underline', textUnderlineOffset: 3 };
const stort = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

// »Sandsynligvis din onkel« / »Omstridt: din onkel« — usikkerhedsordet i faresignalets farve.
function ordMedSikkerhed(f: Forbindelse, foerst: boolean): ReactNode {
  if (f.sikkerhed === 'sikker') return foerst ? stort(f.ord) : f.ord;
  const tvivl = f.sikkerhed === 'sandsynligvis' ? 'sandsynligvis' : 'omstridt:';
  return <><span style={{ color: T.danger }}>{foerst ? stort(tvivl) : tvivl}</span> {f.ord}</>;
}

function vejLink(f: Forbindelse, a: string, b: string): ReactNode {
  return <> · <Link href={slaegtskabPath(a, b)} style={linkStil}>{f.veje > 1 ? `Se alle ${f.veje} veje` : 'Se vejen'}</Link></>;
}

export function SlaegtskabsLinje({ kontekst, meId, focusId, onVisPerson }: {
  kontekst: SlaegtskabsKontekst; meId: string | null; focusId: string; onVisPerson: (id: string) => void;
}) {
  const k = kontekst;
  if (k.art === 'skjult' || !meId) return null;
  if (k.art === 'ingen') {
    return <p data-testid="slaegtskab-kontekst" style={{ ...stil, fontStyle: 'normal', color: T.inkMuted }}>Aarbogen viser ingen fælles ane med dig</p>;
  }
  if (k.art === 'dig') return <p data-testid="slaegtskab-kontekst" style={stil}>Det er dig</p>;
  if (k.art === 'min-aegtefaelle') return <p data-testid="slaegtskab-kontekst" style={stil}>Din ægtefælle</p>;
  const bekraeftet = k.bekraeftetAndenVej ? ' · bekræftet ad en anden linje' : '';
  if (k.art === 'blod') {
    return <p data-testid="slaegtskab-kontekst" style={stil}>{ordMedSikkerhed(k, true)}{bekraeftet}{vejLink(k, meId, focusId)}</p>;
  }
  return (
    <p data-testid="slaegtskab-kontekst" style={stil}>
      Gift med <Link href={personPath(k.aegtefaelleId)} onNavigate={() => onVisPerson(k.aegtefaelleId)} style={linkStil}>{k.aegtefaelleNavn}</Link>
      {', '}{ordMedSikkerhed(k, false)}{bekraeftet}{vejLink(k, meId, k.aegtefaelleId)}
    </p>
  );
}
