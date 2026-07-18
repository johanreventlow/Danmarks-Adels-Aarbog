// Tidslige kort (spec §4.4, §6). Rene funktioner — al netværkshentning bor i app-lagene
// (mobile/src/data/livsdato.ts, web/src/data/feedAux.ts); denne fil joiner/udleder kun.
import { byIdStr, initialsOf } from './pool';
import { stableHash } from './prng';
import { isExactDay } from './types';
import type { FeedCard, FuzzyDato, HaendelserBy, LivsdatoBy, Model } from './types';

// Rå rækker (PostgREST-form) til buildLivsdatoBy — date_min/max er DATE-kolonner
// (schema.sql), så PostgREST returnerer dem som 'YYYY-MM-DD'-strenge.
export interface LivsdatoFactRow {
  id: string | number;
  subjekt_id: string | number;
  faktatype: string;
}
export interface LivsdatoConclusionRow {
  target_id: string | number;
  valgt_assertion_id: string | number | null;
}
export interface LivsdatoAssertionRow {
  id: string | number;
  date_min: string | null;
  date_max: string | null;
  date_qualifier: string | null;
}

// Ren JS-join (spec §6.1) — polymorfe koblinger (fact→conclusion→assertion) kan ikke
// FK-joines i PostgREST, samme mønster som fetchParentsUnknownRows/fetchSammeSomRows.
// Kun faktatype 'fødsel'/'død' er relevante her; alt andet ignoreres. Id'er kanoniseres.
export function buildLivsdatoBy(
  facts: LivsdatoFactRow[],
  conclusions: LivsdatoConclusionRow[],
  assertions: LivsdatoAssertionRow[],
  canonicalIdById: Record<string, string> = {},
): LivsdatoBy {
  const assertionById = new Map(assertions.map((a) => [String(a.id), a]));
  const conclusionByFactId = new Map(conclusions.map((c) => [String(c.target_id), c]));
  const out: LivsdatoBy = {};
  for (const f of facts) {
    if (f.faktatype !== 'fødsel' && f.faktatype !== 'død') continue;
    const concl = conclusionByFactId.get(String(f.id));
    if (!concl || concl.valgt_assertion_id == null) continue;
    const a = assertionById.get(String(concl.valgt_assertion_id));
    if (!a) continue;
    const pid = canonicalIdById[String(f.subjekt_id)] ?? String(f.subjekt_id);
    const dato: FuzzyDato = { min: a.date_min, max: a.date_max, qualifier: a.date_qualifier };
    const entry = out[pid] ?? (out[pid] = {});
    if (f.faktatype === 'fødsel') entry.foedt = dato;
    else entry.doed = dato;
  }
  return out;
}

const mmdd = (dateStr: string): string => dateStr.slice(5, 10);
const mm = (dateStr: string): string => dateStr.slice(5, 7);

// 'På denne dag'-kort (spec §6.2). Kun punktintervaller med dag-præcision tæller
// (aldrig fabrikeret præcision). Global fallback: hvis INGEN person har et dag-træf, vises
// måneds-træf ('I denne måned') — så feed'en sjældent er helt uden tidsligt indhold,
// uden nogensinde at hævde en præcision datoen ikke bærer.
export function buildPaaDenneDag(
  model: Model,
  livsdatoBy: LivsdatoBy,
  todayISO: string,
  haendelserBy: HaendelserBy = {},
): FeedCard[] {
  const todayMMDD = mmdd(todayISO);
  const todayMM = mm(todayISO);
  const dayMatches: FeedCard[] = [];
  const monthMatches: FeedCard[] = [];
  for (const p of model.persons) {
    const ld = livsdatoBy[p.id];
    if (ld) {
      for (const [key, hvad] of [['foedt', 'født'], ['doed', 'død']] as const) {
        const dato = ld[key];
        if (!isExactDay(dato) || !dato?.min) continue;
        const aarstal = Number(dato.min.slice(0, 4));
        if (!Number.isFinite(aarstal)) continue;
        const id = `paadennedag:${p.id}:${hvad}:${aarstal}`;
        if (mmdd(dato.min) === todayMMDD) {
          dayMatches.push({
            kind: 'paadennedag', id, personId: p.id, name: p.name, years: p.years,
            aarstal, hvad, praecision: 'dag', kicker: 'På denne dag',
          });
        } else if (mm(dato.min) === todayMM) {
          monthMatches.push({
            kind: 'paadennedag', id, personId: p.id, name: p.name, years: p.years,
            aarstal, hvad, praecision: 'maaned', kicker: 'I denne måned',
          });
        }
      }
    }

    for (const item of haendelserBy[p.id] ?? []) {
      const dato = item.dato;
      if (item.rygrad || !isExactDay(dato) || !dato.min) continue;
      const aarstal = Number(dato.min.slice(0, 4));
      if (!Number.isFinite(aarstal)) continue;
      const card = {
        kind: 'paadennedag' as const,
        id: 'paadennedag:h:' + item.id,
        personId: p.id,
        name: p.name,
        years: p.years,
        aarstal,
        hvad: 'hændelse' as const,
        klausul: item.klausul,
      };
      if (mmdd(dato.min) === todayMMDD) {
        dayMatches.push({ ...card, praecision: 'dag', kicker: 'På denne dag' });
      } else if (mm(dato.min) === todayMM) {
        monthMatches.push({ ...card, praecision: 'maaned', kicker: 'I denne måned' });
      }
    }
  }
  return (dayMatches.length > 0 ? dayMatches : monthMatches).sort(byIdStr);
}

// Én person pr. dag, ens for alle brugere (spec §6.3): hash(todayISO) % N over den
// stabilt id-sorterede bio-population. null hvis ingen har en bio.
export function pickDagensPerson(model: Model, todayISO: string): string | null {
  const bioPersons = model.persons.filter((p) => p.bio.trim() !== '').sort(byIdStr);
  if (bioPersons.length === 0) return null;
  return bioPersons[stableHash(todayISO) % bioPersons.length].id;
}

export function buildDagensPersonCard(model: Model, personId: string): FeedCard | null {
  const p = model.byId[personId];
  if (!p) return null;
  return {
    kind: 'dagensperson', id: 'dagensperson:' + p.id, personId: p.id, name: p.name,
    years: p.years, initials: initialsOf(p.name), title: p.title !== '' ? p.title : null,
    bio: p.bio, kicker: 'Dagens person',
  };
}
