import { evaluateFamily, type FamilyContext } from './family';
import { buildScored, defaultCfg, scorePair, scorePairEvidens, type MatchCfg, type MatchFrame, type ScoredPair } from '@daa/core';
import type { PersonaOrigin } from './frames';

export type Tier = 'auto' | 'review' | 'none';
export type Candidate = {
  source_persona_id: string; candidate_person_id: number; rank: number; score: number; tier: Tier;
  basis: { signals: string[]; name_origin: string; birth_origin: string | null; death_origin: string | null;
           family_partner?: boolean; ordinal_match?: boolean; corroboration_eligible?: boolean;
           eligibility_reason?: string; cluster_members?: number[] };
};
export type RankOptions = { topK: number; origins: Map<string, PersonaOrigin>; evidensNormaliseret?: boolean;
  families?: Map<string, FamilyContext>; clusters?: Map<number, number>; familyNameMin?: number };

export function rankConfig(opts: Pick<RankOptions, 'evidensNormaliseret'>): MatchCfg {
  // topK i buildScored sættes højt, så VI vælger top-K efter endelig score pr. persona.
  // Ingen forudvalg i buildScored (det sorterer efter standardscore og ville skæve den normaliserede rangering).
  return { ...defaultCfg(), topK: Number.MAX_SAFE_INTEGER, evidensNormaliseret: Boolean(opts.evidensNormaliseret) };
}

const round4 = (x: number) => Math.round(x * 10000) / 10000;

// Pr. persona, IKKE injektiv: flere personas kan være samme person (spec §5).
export function rankCandidates(personas: MatchFrame[], persons: MatchFrame[], opts: RankOptions): Candidate[] {
  const cfg = rankConfig(opts);
  const score = (p: ScoredPair) => (cfg.evidensNormaliseret ? scorePairEvidens(p, cfg)
    : scorePair(p.nameSim, p.birthOverlap, p.deathOverlap, p.sexEq, cfg));
  const byPersona = new Map<string, Array<ScoredPair & { s: number }>>();
  for (const p of buildScored(personas, persons, cfg)) {
    const arr = byPersona.get(String(p.aId)) ?? [];
    arr.push({ ...p, s: score(p) });
    byPersona.set(String(p.aId), arr);
  }
  const out: Candidate[] = [];
  for (const persona of personas) {
    const pid = String(persona.id);
    const sorted = (byPersona.get(pid) ?? []).sort((a, b) => b.s - a.s || Number(a.bId) - Number(b.bId));
    const ctx = opts.families?.get(pid);
    const fam = ctx ? evaluateFamily(ctx) : null;
    let ordered = sorted;
    if (fam) {
      const inFam = new Set(fam.partners);
      ordered = [...sorted.filter((p) => inFam.has(Number(p.bId))), ...sorted.filter((p) => !inFam.has(Number(p.bId)))];
    }
    const members = new Map<number, number[]>();
    if (opts.clusters) {
      const seen = new Map<number, number>();
      ordered = ordered.filter((p) => {
        const id = Number(p.bId); const rep = opts.clusters!.get(id) ?? id;
        if (seen.has(rep)) { members.get(seen.get(rep)!)!.push(id); return false; }
        seen.set(rep, id); members.set(id, [id]); return true;
      });
      // Spec §6.1: repræsentanten er familiens partner, ellers laveste id — ikke den bedst scorede.
      // Pladsen (score, rang) bevares; kun id'et skiftes (Codex plan-r1 fund 6).
      const partnerSet = new Set(fam?.partners ?? []);
      ordered = ordered.map((p) => {
        const id = Number(p.bId); const ms = members.get(id)!;
        const repId = ms.find((m) => partnerSet.has(m)) ?? Math.min(...ms);
        if (repId === id) return p;
        members.delete(id); members.set(repId, ms);
        return { ...p, bId: repId };
      });
    }
    // Margin fra hele listen FØR afskæring: ellers giver --top-k 1 altid margin ∞ (Codex 2026-10-05).
    const margin = ordered.length < 2 ? Infinity : ordered[0].s - ordered[1].s;
    const list = ordered.slice(0, opts.topK);
    const origin = opts.origins.get(pid) ?? { name: null, birth: null, death: null };
    list.forEach((p, i) => {
      const kunNavn = !p.birthKendt && !p.deathKendt;
      const tier: Tier = i === 0 && !kunNavn && p.s >= cfg.autoCutoff && margin >= cfg.ambiguityMargin ? 'auto'
        : p.s >= cfg.reviewCutoff ? 'review' : 'none';
      const signals = ['name', ...(p.birthOverlap ? ['birth'] : []), ...(p.deathOverlap ? ['death'] : []), ...(p.sexEq ? ['sex'] : [])];
      const isPartner = fam ? fam.partners.includes(Number(p.bId)) : false;
      const eligible = Boolean(fam?.structureOk && i === 0 && fam.target === Number(p.bId) && p.nameSim >= (opts.familyNameMin ?? 0.9));
      const famTier: Tier = eligible ? 'auto' : tier === 'auto' ? 'review' : tier;
      const cl = (members.get(Number(p.bId)) ?? []).sort((a, b) => a - b);
      out.push({
        source_persona_id: pid, candidate_person_id: Number(p.bId), rank: i + 1, score: round4(Math.min(1, Math.max(0, p.s))),
        tier: fam ? famTier : tier,
        basis: { signals: [...signals, ...(isPartner ? ['family_partner'] : []), ...(fam?.ordinalMatch.has(Number(p.bId)) ? ['ordinal_match'] : [])],
                 name_origin: origin.name ?? 'unknown', birth_origin: origin.birth, death_origin: origin.death,
                 ...(fam ? { family_partner: isPartner, ordinal_match: fam.ordinalMatch.has(Number(p.bId)),
                             corroboration_eligible: eligible, eligibility_reason: eligible ? 'ok' : (fam.structureOk ? 'name_or_rank' : fam.reason) } : {}),
                 ...(cl.length > 1 ? { cluster_members: cl } : {}) },
      });
    });
  }
  return out;
}
