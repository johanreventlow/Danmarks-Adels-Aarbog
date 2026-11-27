// Hof-/rangtitel til personens statuslinje (spec 2026-11-27, »Titelalgoritmen«). Rene funktioner.
// Målt mod 109 koblede forældreoverskrifter i 2018-20; aldrig en titel personen ikke havde (fail-closed).
import { erAdelsTitel } from './adelsTitler';

const PRAEFIKSER = [
  'karakteriseret', 'karakt.', 'titulær', 'virkelig', 'preussisk', 'tysk', 'dansk', 'kgl.', 'kongelig',
];
// Stedled skæres ved første af disse ord (»amtmand over Sorø Amt« → »amtmand«; »over« jf. specens eksempel).
const STEDLED = /\s+(?:i|hos|af|à|ved|for|under|til|in|over)\s+/;

const ORDENER = new Set(['hvid ridder', 'blå ridder', 'storkors', 'kommandør af dannebrog']);

// Stiger, laveste trin først. Kaptajn og ritmester er samme trin (nested array).
const STIGER: (string | string[])[][] = [
  ['kammerjunker', 'kammerherre', 'overkammerherre'],
  ['jagtjunker', 'hofjægermester', 'overhofjægermester'],
  ['justitsråd', 'etatsråd', 'konferensråd', 'gehejmeråd', 'gehejmekonferensråd', 'gehejmestatsminister'],
  ['sekondløjtnant', 'løjtnant', 'premierløjtnant', ['kaptajn', 'ritmester'], 'major', 'oberstløjtnant',
    'oberst', 'generalmajor', 'generalløjtnant', 'general'],
];

// Rangfølgen, højest først — også den tilladte liste.
const RANG = [
  'storkansler', 'kansler', 'gehejmestatsminister', 'statholder', 'højesteretspræsident', 'regeringspræsident',
  'overkammerherre', 'gehejmekonferensråd', 'geheimekonferensråd', 'general', 'gehejmeråd', 'generalløjtnant',
  'generalmajor', 'gesandt', 'rigshofråd', 'konferensråd', 'stiftamtmand', 'kammerherre', 'hofjægermester',
  'oberst', 'oberstløjtnant', 'verbitter', 'landdagsmarskal', 'amtmand', 'etatsråd', 'professor', 'landråd',
  'major', 'kaptajn', 'ritmester', 'høvedsmand', 'ridder', 'premierløjtnant', 'løjtnant', 'kammerjunker', 'foged',
];

// Trin pr. ord: stige-indeks og højde.
const TRIN = new Map<string, { stige: number; hoejde: number }>();
STIGER.forEach((stige, s) => stige.forEach((trin, h) => {
  for (const ord of Array.isArray(trin) ? trin : [trin]) TRIN.set(ord, { stige: s, hoejde: h });
}));

const TILLADT = new Set<string>([...RANG, ...TRIN.keys()]);

export function normTitel(v: string): string {
  let t = v.trim().toLowerCase();
  t = t.replace(/\(.*?\)/g, '');
  t = t.split(',')[0].trim();
  for (let aendret = true; aendret;) {
    aendret = false;
    for (const p of PRAEFIKSER) {
      if (t.startsWith(`${p} `)) { t = t.slice(p.length).trim(); aendret = true; }
    }
  }
  t = t.split(STEDLED)[0];
  t = t.replace(/^[ .]+|[ .]+$/g, '').replace(/aa/g, 'å');
  return t;
}

export function hofTitel(vaerdier: readonly string[]): string | null {
  const ord = [...new Set(vaerdier.map(normTitel))].filter(
    (t) => t && !erAdelsTitel(t) && t !== 'rigsfriherre' && !ORDENER.has(t) && TILLADT.has(t),
  );
  // Kun det højeste trin pr. stige tæller.
  const hoejest = new Map<number, number>();
  for (const t of ord) {
    const tr = TRIN.get(t);
    if (tr) hoejest.set(tr.stige, Math.max(hoejest.get(tr.stige) ?? -1, tr.hoejde));
  }
  const kandidater = ord.filter((t) => {
    const tr = TRIN.get(t);
    return !tr || hoejest.get(tr.stige) === tr.hoejde;
  });
  // Rang = position i rangfølgen; ord uden for den (stigetrin) rangerer efter alle opførte, i input-orden.
  const rang = (t: string) => { const i = RANG.indexOf(t); return i < 0 ? RANG.length : i; };
  kandidater.sort((a, b) => rang(a) - rang(b)); // stabil sortering bevarer input-orden
  return kandidater[0] ?? null;
}
