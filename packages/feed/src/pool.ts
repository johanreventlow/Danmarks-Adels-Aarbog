// Kandidat-pool (spec §3.3). Porteret fra mobile/src/data/buildFeed.ts — builders er
// UÆNDREDE i logik, men UDEN caps (FEED_CAPS/cap() udgår; poolen er alle kandidater).
// Model importeres fra @daa/core; builders er derfor kun afhængige af Model-felter,
// ikke af nogen app-specifik type.
import { computeRelationship } from '@daa/core';
import { stableHash } from './prng';
import type { FeedAux, FeedCard, Model } from './types';

const initialsOf = (name: string): string => (name.trim()[0] ?? '?').toUpperCase();

// Stabil id-komparator — genbrugt af alle gruppe-sorteringer (determinisme).
export const byIdStr = (a: { id: string }, b: { id: string }): number => a.id.localeCompare(b.id);

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
// (spec §3.3a, v3-spec §3.3a): deterministisk hash-partition. Citat-slot uden brugbar
// sætning falder helt ud. `excludeId` (spec §3, task 3) udelader dagens person — den
// vises som sit eget 'dagensperson'-kort i stedet (disjunkthed).
export function buildPortraitAndCitat(
  model: Model,
  excludeId: string | null = null,
): { portraits: FeedCard[]; citater: FeedCard[] } {
  const bioPersons = model.persons
    .filter((p) => p.bio.trim() !== '' && p.id !== excludeId)
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

// Runde jubilæer: num delelig med 50 og ≥100 (100/150/200…). Både fødsel og død.
// (Udvides i task 3 med dag-præcis 'på dagen'-markering — se temporal.ts.)
export function buildJubilaeer(model: Model, today: number): FeedCard[] {
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

export function buildGods(aux: FeedAux): FeedCard[] {
  return aux.godsListe
    .map((g): FeedCard => ({
      kind: 'gods', id: 'gods:' + g.id, estateId: String(g.id), navn: g.navn,
      meta: g.ownerCount > 0 ? `${g.slags || 'Gods'} · ${g.ownerCount} ejere` : (g.slags || 'Gods'),
      ownerDots: Math.min(g.ownerCount, 7), kicker: 'Gods',
    }))
    .sort(byIdStr);
}

// forbundet: kun unions m. p2!==null OG begge personer i byId. Navne fra byId.
export function buildForbundet(model: Model): FeedCard[] {
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

export function buildEmbeder(model: Model, aux: FeedAux): FeedCard[] {
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

export function buildVaaben(aux: FeedAux): FeedCard[] {
  return aux.vaabenListe
    .map((v): FeedCard => ({
      kind: 'vaaben', id: 'vaaben:' + v.id, armsId: String(v.id),
      blazon: v.blasonering && v.blasonering.trim() !== '' ? v.blasonering
        : 'Blasoneringen indlæses fra Aarbogen, når våbenet knyttes.',
      foot: 'Se slægtens våben ›', kicker: 'Våben',
    }))
    .sort(byIdStr);
}

// slaegt: kun når meId+focusId begge sat og distinkte; skip hvis found:false.
export function buildSlaegt(model: Model, meId: string | null, focusId: string | null): FeedCard[] {
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
