// Ét sted for feed-sessionens ikke-rene inputs (fase1-design.md §5.2, §8.1). Motoren i
// @daa/feed forbliver ren — al tilfældighed/tid samles her, ved UI-randen.
import { stableHash } from '@daa/feed';

const DAY_MS = 86_400_000;

export function todayISO(d: Date = new Date()): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

// Dage siden epoch — bruges af set-hukommelsens tidsstempler (seenCards.ts), IKKE af
// feed-motoren selv (den tager todayISO). Bygget fra lokal kalenderdato (ikke ms-aritmetik
// på UTC-tid), så den er stabil på tværs af sommertids-skift og matcher todayISO ovenfor.
export function epochDay(d: Date = new Date()): number {
  const localMidnight = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  return Math.floor(localMidnight.getTime() / DAY_MS);
}

// Ny sessions-seed pr. mount/reseed: dagsdato (delt tidsligt indhold, §4.3) + en tilfældig
// nonce (variation pr. besøg). DET ENESTE sted Math.random() må optræde i feed-koden —
// motoren i @daa/feed selv er 100% ren og tager seedet som injiceret tal.
export function newSeed(today: string): number {
  const nonce = Math.random().toString(36).slice(2);
  return stableHash(`${today}:${nonce}`);
}
