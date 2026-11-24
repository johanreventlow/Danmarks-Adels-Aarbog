// Tidslige kort (spec §4.4, §6). Rene funktioner — al netværkshentning bor i app-lagene
// (mobile/src/data/livsdato.ts, web/src/data/feedAux.ts); denne fil joiner/udleder kun.
import { byIdStr, harBrugbarBio, initialsOf } from './pool';
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
  // Review 37 M13: en foldet person har datoer fra flere poster. Rækkefølgen følger collapseSameAs (kanonisk post først,
  // så alias'erne sorteret på id som streng); inden for én post den laveste fact-id. Før vandt den sidste række, så en
  // 1939-posts årstal kunne erstatte den kanoniske posts dag-præcise dato. Jubilæumskortene bruger kun en dato, når den
  // foldede persons born/died er sat, og de kommer fra én posts samlede udsagn (decisions 2026-11-24).
  const rang = new Map<string, [number, string, number]>();
  const foerst = (x: [number, string, number], y: [number, string, number]) =>
    x[0] - y[0] || (x[1] < y[1] ? -1 : x[1] > y[1] ? 1 : 0) || x[2] - y[2];
  for (const f of facts) {
    if (f.faktatype !== 'fødsel' && f.faktatype !== 'død') continue;
    const concl = conclusionByFactId.get(String(f.id));
    if (!concl || concl.valgt_assertion_id == null) continue;
    const a = assertionById.get(String(concl.valgt_assertion_id));
    if (!a) continue;
    // Ingen dato at give (fx 1939-poster, hvis datoer ikke er indlæst, #409): tæller som fraværende, så en
    // anden post kan give datoen — som coalesce springer null over.
    if (a.date_min == null && a.date_max == null) continue;
    const sid = String(f.subjekt_id);
    const pid = canonicalIdById[sid] ?? sid;
    const r: [number, string, number] = [sid === pid ? 0 : 1, sid, Number(f.id)];
    const noegle = `${pid}|${f.faktatype}`;
    const tidligere = rang.get(noegle);
    if (tidligere && foerst(tidligere, r) <= 0) continue;
    rang.set(noegle, r);
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
            aarstal, dato: dato.min, hvad, praecision: 'dag', kicker: 'På denne dag',
          });
        } else if (mm(dato.min) === todayMM) {
          monthMatches.push({
            kind: 'paadennedag', id, personId: p.id, name: p.name, years: p.years,
            aarstal, dato: dato.min, hvad, praecision: 'maaned', kicker: 'I denne måned',
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
        dato: dato.min,
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
  const bioPersons = model.persons.filter((p) => harBrugbarBio(p.bio)).sort(byIdStr);
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
