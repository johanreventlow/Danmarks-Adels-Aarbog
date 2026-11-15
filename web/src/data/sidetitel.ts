// Sidens titel (fanen, bogmærker og delte links). Navne kommer kun fra modellen, som RLS har filtreret — samme regel som
// sidens overskrift; viser siden en fejl, sætter Følgesvend kun værkets navn.
import { labelOfMode, type Mode } from './nav';

export const VAERK = 'Danmarks Adels Aarbog';

export function sidetitel(s: {
  mode: Mode; slaegtNavn?: string | null; personNavn?: string | null; aNavn?: string | null; bNavn?: string | null;
  q?: string | null; besiddelseNavn?: string | null;
}): string {
  const med = (...dele: string[]) => [...dele, VAERK].join(' · ');
  switch (s.mode) {
    case 'home': return VAERK;
    case 'person': return s.personNavn ? med(s.personNavn) : VAERK;
    case 'relate': return s.aNavn && s.bNavn ? med(`${s.aNavn} og ${s.bNavn}`, 'Er vi i familie?') : med('Er vi i familie?');
    case 'soeg': return s.q?.trim() ? med(`Søg: ${s.q.trim()}`) : med('Personer');
    case 'bookmarks': return med('Bogmærker');
    case 'ukendtSlaegt': return med('Slægt ikke fundet');
    case 'about': return s.slaegtNavn ? med(s.slaegtNavn) : VAERK;
    default:
      if (s.mode === 'estates' && s.besiddelseNavn) return med(s.besiddelseNavn);
      return s.slaegtNavn ? med(labelOfMode(s.mode), s.slaegtNavn) : med(labelOfMode(s.mode));
  }
}
