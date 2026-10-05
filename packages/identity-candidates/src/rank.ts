import { buildScored, defaultCfg, scorePair, scorePairEvidens, type MatchCfg, type MatchFrame, type ScoredPair } from '@daa/core';
import type { PersonaOrigin } from './frames';

export type Tier = 'auto' | 'review' | 'none';
export type Candidate = {
  source_persona_id: string; candidate_person_id: number; rank: number; score: number; tier: Tier;
  basis: { signals: string[]; name_origin: string; birth_origin: string | null; death_origin: string | null };
};
export type RankOptions = { topK: number; origins: Map<string, PersonaOrigin>; evidensNormaliseret?: boolean };

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
    // Margin fra hele listen FØR afskæring: ellers giver --top-k 1 altid margin ∞ (Codex 2026-10-05).
    const margin = sorted.length < 2 ? Infinity : sorted[0].s - sorted[1].s;
    const list = sorted.slice(0, opts.topK);
    const origin = opts.origins.get(pid) ?? { name: null, birth: null, death: null };
    list.forEach((p, i) => {
      const kunNavn = !p.birthKendt && !p.deathKendt;
      const tier: Tier = i === 0 && !kunNavn && p.s >= cfg.autoCutoff && margin >= cfg.ambiguityMargin ? 'auto'
        : p.s >= cfg.reviewCutoff ? 'review' : 'none';
      const signals = ['name', ...(p.birthOverlap ? ['birth'] : []), ...(p.deathOverlap ? ['death'] : []), ...(p.sexEq ? ['sex'] : [])];
      out.push({
        source_persona_id: pid, candidate_person_id: Number(p.bId), rank: i + 1, score: round4(Math.min(1, Math.max(0, p.s))), tier,
        basis: { signals, name_origin: origin.name ?? 'unknown', birth_origin: origin.birth, death_origin: origin.death },
      });
    });
  }
  return out;
}
