// Præsensliste: anker-parse + sti→overskrift-generator (spec 2026-07-22 §4-§5).
// Rene funktioner. Genererer ALTID moderne former (FARBROR, FARS SØSTER) — bogens
// arkaiske varianter gengives ikke; original-proveniens er en senere påbygning.
import type { Koen } from './types';

export type PresensAnker = { personId: string; linje: string; gren: number | null; raaVaerdi: string };

const ROMER: Record<string, number> = { I: 1, II: 2, III: 3, IV: 4, V: 5, VI: 6, VII: 7, VIII: 8, IX: 9, X: 10 };

// 'II linje' / 'II linje, 1. gren' — tolerant for kasse og mellemrum; alt andet → null
// (fail-closed: en uparsebar udpegning bliver aldrig et gættet anker).
export function parseOverhovedVaerdi(personId: string, vaerdi: string): PresensAnker | null {
  const m = /^\s*([ivx]+)\s*\.?\s*linje\s*(?:,\s*(\d+)\s*\.?\s*gren)?\s*$/i.exec(vaerdi ?? '');
  if (!m) return null;
  const linje = m[1].toUpperCase();
  if (!(linje in ROMER)) return null;
  return { personId, linje, gren: m[2] != null ? Number(m[2]) : null, raaVaerdi: vaerdi.trim() };
}

export function sortAnkre(ankre: PresensAnker[]): PresensAnker[] {
  return [...ankre].sort(
    (a, b) => ROMER[a.linje] - ROMER[b.linje] || (a.gren ?? 0) - (b.gren ?? 0) || (a.personId < b.personId ? -1 : a.personId > b.personId ? 1 : 0),
  );
}

export type SoeskendeSammensaetning = { maend: number; kvinder: number; ukendt: number };
export type PresensTerminal =
  | { slags: 'soeskende'; sammensaetning: SoeskendeSammensaetning }
  | { slags: 'foraelder'; koen: Koen }
  | { slags: 'enke' };

const ET: Record<'mand' | 'kvinde', string> = { mand: 'far', kvinde: 'mor' };
const PAR: Record<string, string> = { 'mand|mand': 'farfar', 'mand|kvinde': 'farmor', 'kvinde|mand': 'morfar', 'kvinde|kvinde': 'mormor' };

// Kæden chunks parvis fra ankeret: [far,far,far] → ['farfar','far'] — så komposit-reglen
// nedenfor giver bogens 'farfars farbror' frem for 'fars fars fars bror'.
function kaedeOrd(kaede: Koen[]): string[] {
  const ord: string[] = [];
  let i = 0;
  while (i < kaede.length) {
    const a = kaede[i];
    const b = kaede[i + 1];
    if (a != null && b != null) { ord.push(PAR[`${a}|${b}`]); i += 2; }
    else if (a != null) { ord.push(ET[a]); i += 1; }
    else { ord.push('forælder'); i += 1; } // ukendt køn chunkes ikke
  }
  return ord;
}

// Genitiv-s på alle led undtagen det sidste: ['farfar','farbror'] → 'farfars farbror'.
const genitivJoin = (ord: string[]): string => ord.map((o, i) => (i < ord.length - 1 ? o + 's' : o)).join(' ');
const cap = (s: string): string => s.charAt(0).toUpperCase() + s.slice(1);

function soeskendeOrd(s: SoeskendeSammensaetning): { ord: string; art: 'bror' | 'soester' | 'soeskende' } {
  if (s.ukendt === 0 && s.kvinder === 0 && s.maend > 0) return { ord: s.maend > 1 ? 'brødre' : 'bror', art: 'bror' };
  if (s.ukendt === 0 && s.maend === 0 && s.kvinder > 0) return { ord: s.kvinder > 1 ? 'søstre' : 'søster', art: 'soester' };
  return { ord: 'søskende', art: 'soeskende' };
}

// kaede = køn for forfaderleddene fra ankeret og OP (uden terminalleddet).
// UI'et versaliserer selv (typografisk slægtskab med bogen); her returneres 'Farfars farbror'.
export function stiOverskrift(kaede: Koen[], terminal: PresensTerminal): string {
  if (terminal.slags === 'foraelder') return cap(genitivJoin(kaedeOrd([...kaede, terminal.koen])));
  if (terminal.slags === 'enke') return cap(genitivJoin([...kaedeOrd(kaede), 'enke']));
  const ord = kaedeOrd(kaede);
  const s = soeskendeOrd(terminal.sammensaetning);
  const sidste = ord[ord.length - 1];
  // Komposit KUN for brødre efter enkelt forælder-led (bogen: FARBROR, men FARS SØSTER).
  if (s.art === 'bror' && (sidste === 'far' || sidste === 'mor')) {
    const komposit = (sidste === 'far' ? 'farbr' : 'morbr') + (terminal.sammensaetning.maend > 1 ? 'ødre' : 'or');
    return cap(genitivJoin([...ord.slice(0, -1), komposit]));
  }
  return cap(genitivJoin([...ord, s.ord]));
}
