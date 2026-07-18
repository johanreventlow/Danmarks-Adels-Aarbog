// Feed-motorens typer. Model importeres fra @daa/core — motoren er netværks- og app-fri.
import type { Model } from '@daa/core';

export type { Model };

export interface FeedAux {
  godsListe: { id: string; navn: string; slags: string; ownerCount: number }[];
  vaabenListe: { id: string; blasonering: string; note: string }[];
  officesBy: Record<string, { label: string; period: string; _y: number }[]>;
}

export type FuzzyDato = { min: string | null; max: string | null; qualifier: string | null };
export type LivsdatoBy = Record<string, { foedt?: FuzzyDato; doed?: FuzzyDato }>;

export interface HaendelseItem {
  id: string;
  klausul: string;
  kategori: string | null;
  dato: FuzzyDato;
  dateRaw: string | null;
  interessant: boolean;
  rygrad: boolean;
  kilde: string | null;
}
export type HaendelserBy = Record<string, HaendelseItem[]>;

export type FeedCard =
  | { kind: 'portrait'; id: string; personId: string; name: string; years: string;
      initials: string; title: string | null; bio: string; kicker: string }
  | { kind: 'citat'; id: string; personId: string; quote: string; source: string; kicker: string }
  | { kind: 'arkiv'; id: string; personId: string; name: string; klausul: string;
      aarLabel: string | null; kategori: string | null; kilde: string | null;
      interessant?: boolean; kicker: string }
  | { kind: 'gods'; id: string; estateId: string; navn: string; meta: string;
      ownerDots: number; kicker: string }
  | { kind: 'forbundet'; id: string; aName: string; bName: string; aInit: string;
      bInit: string; marBottom: string; kicker: string }
  | { kind: 'slaegt'; id: string; aId: string; bId: string; aName: string; bName: string;
      rel: string; foot: string; kicker: string }
  | { kind: 'embede'; id: string; personId: string; label: string; name: string;
      period: string; init: string; kicker: string }
  | { kind: 'jubilaeum'; id: string; personId: string; num: number; name: string;
      sub: string; kicker: string; paaDagen?: boolean }
  | { kind: 'vaaben'; id: string; armsId: string; blazon: string; foot: string; kicker: string }
  | { kind: 'samle'; id: string; count: number; tail: string; kicker: string }
  | { kind: 'paadennedag'; id: string; personId: string; name: string; years: string;
      aarstal: number; hvad: 'født' | 'død' | 'hændelse'; klausul?: string;
      praecision: 'dag' | 'maaned'; kicker: string }
  | { kind: 'dagensperson'; id: string; personId: string; name: string; years: string;
      initials: string; title: string | null; bio: string; kicker: string };

export type FeedOverride = { pin?: string[]; hide?: string[] };

export interface FeedInputs {
  seed: number;
  todayISO: string;
  meId: string | null;
  focusId: string | null;
  bookmarkedIds?: string[];
  seenWeights?: Record<string, number>;
  livsdatoBy?: LivsdatoBy;
  haendelserBy?: HaendelserBy;
  overrides?: FeedOverride[];
}

export function bookmarkPersonId(card: FeedCard): string | null {
  return 'personId' in card ? card.personId : null;
}
