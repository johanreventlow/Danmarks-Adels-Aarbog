// »Er vi i familie?« (webredesign fase 6a) som rene funktioner: forslag i personvælgeren og vejen trin for trin.
// Selve beregningen bor i @daa/core (computeRelationship); her formes den til visning.
import { compareDanish, foldToken, type Konfidens, type RelationLine } from '@daa/core';
import { erTekniskLinje } from './lineage';
import type { Model } from './types';

export type PersonForslag = { id: string; name: string; years: string; linje: string | null };

// Linjens navn til at skelne personer med samme navn. Tekniske nøgler vises aldrig.
export function linjeNavnFor(model: Model, id: string): string | null {
  return (model.lineage?.byPerson[id] ?? []).filter((k) => !erTekniskLinje(k)).map((k) => model.lineage?.navn[k]).find(Boolean) ?? null;
}

const ord = (s: string) => s.toLowerCase().split(/[\s,.()-]+/).filter(Boolean);

// Forslag til personvælgeren. Et navn rammes, når det indeholder søgeordet, eller når hvert søgeord
// (stavemåde-foldet, så Detlev finder Detlef) er begyndelsen på et ord i navnet. Rangering: navnet
// begynder med søgeordet, et ord begynder med det, ellers indeholder det det; så dansk alfabetisk.
export function personForslag(model: Model, query: string, n = 8): PersonForslag[] {
  const q = query.trim().toLowerCase();
  if (!q) return [];
  const qFold = ord(q).map(foldToken);
  const ramte: { p: Model['persons'][number]; rang: number }[] = [];
  for (const p of model.persons) {
    const navn = p.name.toLowerCase();
    let rang = -1;
    if (navn.startsWith(q)) rang = 0;
    else if (ord(navn).some((w) => w.startsWith(q))) rang = 1;
    else if (navn.includes(q)) rang = 2;
    else {
      const navnFold = ord(navn).map(foldToken);
      if (qFold.length && qFold.every((t) => navnFold.some((w) => w.startsWith(t)))) rang = 3;
    }
    if (rang >= 0) ramte.push({ p, rang });
  }
  ramte.sort((a, b) => a.rang - b.rang || compareDanish(a.p.name, b.p.name));
  return ramte.slice(0, n).map(({ p }) => ({ id: p.id, name: p.name, years: p.years, linje: linjeNavnFor(model, p.id) }));
}

export type VejTrin = {
  id: string; name: string; years: string;
  foerste: boolean; anden: boolean; faellesAne: boolean;
  // Leddet op til dette trin fra det forrige, når bogen kalder det formodet eller omstridt.
  usikkertLed: 'formodet' | 'omstridt' | null;
};

const usikker = (k: Konfidens | undefined): VejTrin['usikkertLed'] => (k === 'formodet' || k === 'omstridt' ? k : null);

export function vejTrin(line: RelationLine): VejTrin[] {
  const sidste = line.steps.length - 1;
  return line.steps.map((s, i) => ({
    id: s.id, name: s.name, years: s.years,
    foerste: i === 0, anden: i === sidste, faellesAne: s.isLca,
    usikkertLed: i > 0 ? usikker(s.edgeKonfidens) : null,
  }));
}

const TAL = ['nul', 'ét', 'to', 'tre', 'fire', 'fem', 'seks', 'syv', 'otte', 'ni', 'ti', 'elleve', 'tolv'];

// Antal slægtled mellem de to = trin op til den fælles ane plus trin ned.
export function slaegtledTekst(line: RelationLine): string {
  const n = line.d1 + line.d2;
  const tal = TAL[n] ?? String(n);
  return `${tal.charAt(0).toUpperCase()}${tal.slice(1)} slægtled`;
}

// Fælles ane eller anepar; ved dobbelt slægtskab alle anerne.
export function faellesAneTekst(line: RelationLine): string {
  const flere = line.aner.length > 1;
  return `${flere ? 'Fælles aner' : 'Fælles ane'}: ${line.aner.join(' · ')}`;
}
