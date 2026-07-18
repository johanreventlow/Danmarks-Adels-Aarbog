// Feed-motorens typer (spec §3.1-§3.2, §6.2-§6.3). Model importeres fra @daa/core —
// motoren er netværks- og app-fri; mobil/web leverer deres data gennem disse kontrakter.
import type { Model } from '@daa/core';

export type { Model };

// FeedAux: det UDSNIT af app-lagets Aux motoren rører (spec §3.1). Mobil opfylder den
// strukturelt (mobile/src/data/types.ts Aux); web bygger en adapter (fase 1 skive 5).
export interface FeedAux {
  godsListe: { id: string; navn: string; slags: string; ownerCount: number }[];
  vaabenListe: { id: string; blasonering: string; note: string }[];
  officesBy: Record<string, { label: string; period: string; _y: number }[]>;
}

export type FeedCard =
  | { kind: 'portrait'; id: string; personId: string; name: string; years: string;
      initials: string; title: string | null; bio: string; kicker: string }
  | { kind: 'citat'; id: string; personId: string; quote: string; source: string; kicker: string }
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
      aarstal: number; hvad: 'født' | 'død'; praecision: 'dag' | 'maaned'; kicker: string }
  | { kind: 'dagensperson'; id: string; personId: string; name: string; years: string;
      initials: string; title: string | null; bio: string; kicker: string };

// Fuzzy dato — samme mønster som assertion.date_min/max/qualifier (schema.sql).
export type FuzzyDato = { min: string | null; max: string | null; qualifier: string | null };
export type LivsdatoBy = Record<string, { foedt?: FuzzyDato; doed?: FuzzyDato }>;

export type FeedOverride = { pin?: string[]; hide?: string[] };

// Motorens eneste inputs (spec §3.2). ALDRIG Math.random/Date.now inde i motoren —
// seed og todayISO injiceres altid af app-laget (UI-randen må gerne bruge tilfældighed
// til at VÆLGE seedet).
export interface FeedInputs {
  seed: number;
  todayISO: string; // 'YYYY-MM-DD'
  meId: string | null;
  focusId: string | null;
  bookmarkedIds?: string[];
  seenWeights?: Record<string, number>;
  livsdatoBy?: LivsdatoBy;
  overrides?: FeedOverride[]; // no-op i fase 1 (realiseres fase 3)
}

// Bogmærkbarhed bor i data-laget: kort med et personId gemmer den kanoniske person.
export function bookmarkPersonId(card: FeedCard): string | null {
  return 'personId' in card ? card.personId : null;
}
