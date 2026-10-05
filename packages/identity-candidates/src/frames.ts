import { buildMatchFrame, buildMatchPersoner, parseYear, type MatchFrame } from '@daa/core';
import type { MatchAssertRow, MatchConcRow, MatchExtIdRow, MatchFactRow, MatchPersonRow } from '@daa/core';

export type PersonaExportRow = {
  source_persona_id: string; name: string | null; name_origin: string | null;
  birth_raw: string | null; birth_origin: string | null; death_raw: string | null; death_origin: string | null;
};
export type PersonaOrigin = { name: string | null; birth: string | null; death: string | null };
export type MatchPayload = {
  persons: MatchPersonRow[]; facts: MatchFactRow[]; concs: MatchConcRow[];
  assertions: MatchAssertRow[]; extIds: MatchExtIdRow[];
};

// Personaen har intet køn i kilden på dette led; ukendt tæller ikke imod.
export function personaFrames(rows: PersonaExportRow[]): { frames: MatchFrame[]; origins: Map<string, PersonaOrigin> } {
  const origins = new Map<string, PersonaOrigin>();
  const frames = rows.map((r) => {
    origins.set(r.source_persona_id, { name: r.name_origin, birth: r.birth_origin, death: r.death_origin });
    const y = (s: string | null) => (s == null ? null : String(parseYear(s) ?? ''));
    return buildMatchFrame({
      id: r.source_persona_id, navn: r.name ?? '', koen: null,
      foedsel: r.birth_raw ? { date_min: y(r.birth_raw), date_max: y(r.birth_raw) } : null,
      doed: r.death_raw ? { date_min: y(r.death_raw), date_max: y(r.death_raw) } : null,
    });
  });
  return { frames, origins };
}

export function personFrames(payload: MatchPayload): MatchFrame[] {
  return buildMatchPersoner(payload.persons, payload.facts, payload.concs, payload.assertions, payload.extIds)
    .map((p) => buildMatchFrame({ id: Number(p.id), navn: p.navn, koen: p.koen, foedsel: p.foedsel, doed: p.doed }));
}

// Personas uden parsebart fødsels- eller dødsår (spec §8.1): afgøres af de byggede frames,
// ikke af råfelterne — en ikke-tom date_raw uden 3-4-cifret tal giver intet år for matcheren.
export function udenAarstal(frames: MatchFrame[]): string[] {
  return frames.filter((f) => f.birthMin == null && f.birthMax == null && f.deathMin == null && f.deathMax == null)
    .map((f) => String(f.id));
}
