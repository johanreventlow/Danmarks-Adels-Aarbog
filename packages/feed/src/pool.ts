// Kandidat-pool (spec §3.3). Porteret fra mobile/src/data/buildFeed.ts — builders er
// UÆNDREDE i logik, men UDEN caps (FEED_CAPS/cap() udgår; poolen er alle kandidater).
// Model importeres fra @daa/core; builders er derfor kun afhængige af Model-felter,
// ikke af nogen app-specifik type.
import { computeRelationship } from '@daa/core';
import { stableHash } from './prng';
import type { FeedAux, FeedCard, HaendelserBy, LivsdatoBy, Model } from './types';

export const initialsOf = (name: string): string => (name.trim()[0] ?? '?').toUpperCase();

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
  haendelserBy: HaendelserBy = {},
): { portraits: FeedCard[]; citater: FeedCard[]; usedCitatHaendelseIds: Set<string> } {
  const bioPersons = model.persons
    .filter((p) => p.bio.trim() !== '' && p.id !== excludeId)
    .sort(byIdStr);
  const portraits: FeedCard[] = [];
  const citater: FeedCard[] = [];
  const usedCitatHaendelseIds = new Set<string>();
  for (const p of bioPersons) {
    const isCitatSlot = stableHash(p.id) % 4 === 0;
    if (isCitatSlot) {
      const kandidater = (haendelserBy[p.id] ?? []).filter(
        (item) => !item.rygrad && item.klausul.length >= 40 && item.klausul.length <= 180,
      );
      const valgt = kandidater.length > 0
        ? kandidater[stableHash(p.id) % kandidater.length]
        : null;
      const quote = valgt?.klausul ?? firstQuotableSentence(p.bio);
      if (quote == null) continue; // ingen portræt-fallback → partitionerne forbliver disjunkte
      if (valgt) usedCitatHaendelseIds.add(valgt.id);
      citater.push({
        kind: 'citat', id: 'citat:' + p.id, personId: p.id, quote,
        source: valgt?.kilde ?? (p.years ? `${p.name}, ${p.years}` : p.name),
        kicker: 'Fra Aarbogen',
      });
    } else {
      portraits.push({
        kind: 'portrait', id: 'portrait:' + p.id, personId: p.id, name: p.name,
        years: p.years, initials: initialsOf(p.name), title: p.title !== '' ? p.title : null,
        bio: p.bio, kicker: 'Portræt',
      });
    }
  }
  return { portraits, citater, usedCitatHaendelseIds };
}

// Hændelser uden rygrads-kobling er feed-kandidater. En klausul, der allerede er valgt
// som citat, udelades for at samme kildeuddrag ikke optræder i to kort-flavours.
export function buildArkivKort(
  model: Model,
  haendelserBy: HaendelserBy,
  usedCitatHaendelseIds: ReadonlySet<string>,
): FeedCard[] {
  const out: FeedCard[] = [];
  for (const [personId, items] of Object.entries(haendelserBy)) {
    const p = model.byId[personId];
    if (!p) continue;
    for (const item of items) {
      if (item.rygrad || usedCitatHaendelseIds.has(item.id)) continue;
      const aarLabel = item.dateRaw != null && item.dateRaw !== ''
        ? item.dateRaw
        : item.dato.min?.slice(0, 4) ?? null;
      out.push({
        kind: 'arkiv', id: 'arkiv:' + item.id, personId, name: p.name,
        klausul: item.klausul, aarLabel, kategori: item.kategori, kilde: item.kilde,
        ...(item.interessant ? { interessant: true as const } : {}),
        kicker: 'Årbogen skriver',
      });
    }
  }
  return out.sort(byIdStr);
}

// Runde jubilæer: num delelig med 50 og ≥100 (100/150/200…). Både fødsel og død.
// Dag-præcis opgradering (spec §6.3): når livsdatoBy har en eksakt dato for personen der
// matcher dagens MM-DD (todayISO), opgraderes teksten ("… — på dagen") og paaDagen sættes —
// scoringen (task 4) bruger paaDagen til et timeliness-boost. livsdatoBy/todayISO er valgfrie
// (bagudkompatibelt: uden dem er adfærden identisk med den oprindelige års-regel).
export function buildJubilaeer(
  model: Model,
  today: number,
  livsdatoBy: LivsdatoBy = {},
  todayISO?: string,
): FeedCard[] {
  const todayMMDD = todayISO ? todayISO.slice(5, 10) : null;
  const out: FeedCard[] = [];
  for (const p of model.persons) {
    for (const [year, hvad] of [[p.born, 'født'], [p.died, 'død']] as const) {
      if (year == null) continue;
      const num = today - year;
      if (num >= 100 && num % 50 === 0) {
        const dato = hvad === 'født' ? livsdatoBy[p.id]?.foedt : livsdatoBy[p.id]?.doed;
        const paaDagen = Boolean(
          todayMMDD && dato?.qualifier === 'exact' && dato.min && dato.min.slice(5, 10) === todayMMDD,
        );
        out.push({
          kind: 'jubilaeum', id: `jubilaeum:${p.id}:${hvad}:${num}`, personId: p.id, num,
          name: p.name,
          sub: paaDagen
            ? `${num} år siden ${p.name} blev ${hvad} — på dagen`
            : `${num} år siden ${p.name} blev ${hvad}`,
          kicker: 'Jubilæum',
          ...(paaDagen ? { paaDagen: true as const } : {}),
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
