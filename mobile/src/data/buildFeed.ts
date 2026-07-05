// Ren feed-generator (spec §3, dual-review 20). Udleder et redaktionelt FeedCard[] af den
// eksisterende Model/Aux. Ingen backend, ingen Math.random/Date.now — today injiceres.
// Kilder empirisk verificeret i types.ts/load.ts/relationship.ts (dual-review DS1–DS4).
import { computeRelationship } from './relationship';
import { interleave, stableHash } from './feedHash';
import type { Aux, Model } from './types';

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
      sub: string; kicker: string }
  | { kind: 'vaaben'; id: string; armsId: string; blazon: string; foot: string; kicker: string }
  | { kind: 'samle'; id: string; count: number; tail: string; kicker: string };

export type FeedOverride = { pin?: string[]; hide?: string[] };
export interface FeedOptions {
  meId: string | null;
  focusId: string | null;
  today: number;
  overrides?: FeedOverride[];
}

export const FEED_CAPS: Record<FeedCard['kind'], number> = {
  portrait: 12, citat: 4, gods: Infinity, forbundet: 6,
  embede: 6, jubilaeum: 6, vaaben: Infinity, slaegt: 1, samle: 1,
};

const initialsOf = (name: string): string => (name.trim()[0] ?? '?').toUpperCase();

// Stabil id-komparator — genbrugt af alle gruppe-sorteringer (determinisme).
const byIdStr = (a: { id: string }, b: { id: string }): number => a.id.localeCompare(b.id);

// Bogmærkbarhed bor i data-laget: kort med et personId gemmer den kanoniske person.
// UI (feed + top-bar) importerer denne frem for at gentage `'personId' in card`-tjek.
export function bookmarkPersonId(card: FeedCard): string | null {
  return 'personId' in card ? card.personId : null;
}

// Første sætning på 40–180 tegn (undgå fragmenter/løb). null hvis intet passer.
export function firstQuotableSentence(bio: string): string | null {
  const parts = bio.split(/(?<=[.!?])\s+/);
  for (const raw of parts) {
    const s = raw.trim();
    if (s.length >= 40 && s.length <= 180) return s;
  }
  return null;
}

// Portrait/citat trækker fra samme bio-population, men en person optræder ALDRIG som begge
// (spec §3.3a): deterministisk hash-partition. Citat-slot uden brugbar sætning falder helt ud.
export function buildPortraitAndCitat(model: Model): { portraits: FeedCard[]; citater: FeedCard[] } {
  const bioPersons = model.persons
    .filter((p) => p.bio.trim() !== '')
    .sort(byIdStr);
  const portraits: FeedCard[] = [];
  const citater: FeedCard[] = [];
  for (const p of bioPersons) {
    const isCitatSlot = stableHash(p.id) % 4 === 0;
    if (isCitatSlot) {
      const quote = firstQuotableSentence(p.bio);
      if (quote == null) continue; // ingen portræt-fallback → partitionerne forbliver disjunkte
      citater.push({
        kind: 'citat', id: 'citat:' + p.id, personId: p.id, quote,
        source: p.years ? `${p.name}, ${p.years}` : p.name, kicker: 'Fra Aarbogen',
      });
    } else {
      portraits.push({
        kind: 'portrait', id: 'portrait:' + p.id, personId: p.id, name: p.name,
        years: p.years, initials: initialsOf(p.name), title: p.title !== '' ? p.title : null,
        bio: p.bio, kicker: 'Portræt',
      });
    }
  }
  return { portraits, citater };
}

// Runde jubilæer: num delelig med 50 og ≥100 (spec: 100/150/200…). Både fødsel og død.
function buildJubilaeer(model: Model, today: number): FeedCard[] {
  const out: FeedCard[] = [];
  for (const p of model.persons) {
    for (const [year, hvad] of [[p.born, 'født'], [p.died, 'død']] as const) {
      if (year == null) continue;
      const num = today - year;
      if (num >= 100 && num % 50 === 0) {
        out.push({
          kind: 'jubilaeum', id: `jubilaeum:${p.id}:${hvad}:${num}`, personId: p.id, num,
          name: p.name, sub: `${num} år siden ${p.name} blev ${hvad}`, kicker: 'Jubilæum',
        });
      }
    }
  }
  return out.sort(byIdStr);
}

function buildGods(aux: Aux): FeedCard[] {
  return aux.godsListe
    .map((g): FeedCard => ({
      kind: 'gods', id: 'gods:' + g.id, estateId: String(g.id), navn: g.navn,
      meta: g.ownerCount > 0 ? `${g.slags || 'Gods'} · ${g.ownerCount} ejere` : (g.slags || 'Gods'),
      ownerDots: Math.min(g.ownerCount, 7), kicker: 'Gods',
    }))
    .sort(byIdStr);
}

// forbundet: kun unions m. p2!==null OG begge personer i byId. Navne fra byId (IKKE p2_name/year
// — begge er null fra loaderen, dual-review NEW1). marBottom neutral fallback.
function buildForbundet(model: Model): FeedCard[] {
  const out: FeedCard[] = [];
  for (const u of Object.values(model.indexes.unionById)) {
    if (u.p2 == null) continue;
    const a = model.byId[u.p1];
    const b = model.byId[u.p2];
    if (!a || !b) continue;
    out.push({
      kind: 'forbundet', id: 'forbundet:' + u.id, aName: a.name, bName: b.name,
      aInit: initialsOf(a.name), bInit: initialsOf(b.name),
      marBottom: u.year ? `gift ${u.year}` : 'gift', kicker: 'Forbundet',
    });
  }
  return out.sort(byIdStr);
}

function buildEmbeder(model: Model, aux: Aux): FeedCard[] {
  const out: FeedCard[] = [];
  for (const [pid, offices] of Object.entries(aux.officesBy)) {
    const p = model.byId[pid];
    if (!p) continue;
    for (const o of offices) {
      out.push({
        kind: 'embede', id: `embede:${pid}:${o.label}:${o._y}`, personId: pid,
        label: o.label, name: p.name, period: o.period, init: initialsOf(p.name), kicker: 'Embede',
      });
    }
  }
  return out.sort(byIdStr);
}

function buildVaaben(aux: Aux): FeedCard[] {
  return aux.vaabenListe
    .map((v): FeedCard => ({
      kind: 'vaaben', id: 'vaaben:' + v.id, armsId: String(v.id),
      blazon: v.blasonering && v.blasonering.trim() !== '' ? v.blasonering
        : 'Blasoneringen indlæses fra Aarbogen, når våbenet knyttes.',
      foot: 'Se slægtens våben ›', kicker: 'Våben',
    }))
    .sort(byIdStr);
}

// slaegt: kun når meId+focusId begge sat og distinkte; skip hvis found:false (dual-review DS4/NEW2).
function buildSlaegt(model: Model, meId: string | null, focusId: string | null): FeedCard[] {
  if (!meId || !focusId || meId === focusId) return [];
  const a = model.byId[meId];
  const b = model.byId[focusId];
  if (!a || !b) return [];
  const rel = computeRelationship(model, meId, focusId);
  if (!rel.found) return [];
  return [{
    kind: 'slaegt', id: `slaegt:${meId}:${focusId}`, aId: meId, bId: focusId,
    aName: a.name, bName: b.name, rel: rel.label, foot: 'Se slægtskabet ›', kicker: 'Er I i familie?',
  }];
}

function cap(cards: FeedCard[], kind: FeedCard['kind']): FeedCard[] {
  const n = FEED_CAPS[kind];
  return n === Infinity ? cards : cards.slice(0, n);
}

export function buildFeed(model: Model, aux: Aux, opts: FeedOptions): FeedCard[] {
  if (model.persons.length === 0) return [];
  const { portraits, citater } = buildPortraitAndCitat(model);
  const portraitCards = cap(portraits, 'portrait');
  const citatCards = cap(citater, 'citat');
  const groups: FeedCard[][] = [
    portraitCards,
    cap(buildGods(aux), 'gods'),
    cap(buildForbundet(model), 'forbundet'),
    citatCards,
    cap(buildEmbeder(model, aux), 'embede'),
    cap(buildJubilaeer(model, opts.today), 'jubilaeum'),
    cap(buildVaaben(aux), 'vaaben'),
    cap(buildSlaegt(model, opts.meId, opts.focusId), 'slaegt'),
  ];
  const cards = interleave(groups);
  // 'samle'-kort til sidst (terminal): personer der ikke blev vist som eget person-kort.
  const shownPersons = portraitCards.length + citatCards.length;
  const remaining = model.persons.length - shownPersons;
  if (remaining > 0) {
    cards.push({
      kind: 'samle', id: 'samle:personer', count: remaining,
      tail: 'personer i registeret', kicker: 'Registeret',
    });
  }
  // opts.overrides er en no-op nu (hybrid-beslutning: editorial-krog til senere).
  return cards;
}
