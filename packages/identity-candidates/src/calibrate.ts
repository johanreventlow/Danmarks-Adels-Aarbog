import type { Candidate, Tier } from './rank';

export type Tal = {
  med_facit: number; uden_kandidat: number; top1: number; top3: number;
  tier: Record<Tier, { n: number; rigtige: number }>;
};
export type Calibration = Tal & { personas: number; uden_navn: number; uden_aarstal: Tal };

type Facit = Array<{ source_persona_id: string; canonical_person_id: number }>;

// Kun tal: ingen navne forlader funktionen.
export function calibrate(
  candidates: Candidate[], truth: Facit, personaCount: number, udenNavn: number,
  udenAar: ReadonlySet<string> = new Set(),
): Calibration {
  const byPersona = new Map<string, Candidate[]>();
  for (const k of candidates) byPersona.set(k.source_persona_id, [...(byPersona.get(k.source_persona_id) ?? []), k]);
  return { personas: personaCount, uden_navn: udenNavn, ...tal(byPersona, truth),
           uden_aarstal: tal(byPersona, truth.filter((t) => udenAar.has(t.source_persona_id))) };
}

function tal(byPersona: Map<string, Candidate[]>, truth: Facit): Tal {
  const out: Tal = { med_facit: truth.length, uden_kandidat: 0, top1: 0, top3: 0,
    tier: { auto: { n: 0, rigtige: 0 }, review: { n: 0, rigtige: 0 }, none: { n: 0, rigtige: 0 } } };
  for (const t of truth) {
    const list = (byPersona.get(t.source_persona_id) ?? []).sort((a, b) => a.rank - b.rank);
    if (!list.length) { out.uden_kandidat++; continue; }
    const hit = (k: Candidate) => k.candidate_person_id === t.canonical_person_id;
    if (hit(list[0])) out.top1++;
    if (list.slice(0, 3).some(hit)) out.top3++;
    out.tier[list[0].tier].n++;
    if (hit(list[0])) out.tier[list[0].tier].rigtige++;
  }
  return out;
}
