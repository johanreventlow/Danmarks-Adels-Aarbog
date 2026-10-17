// Privat redaktionsflade for kildens personaer. Den er bevidst ikke en del af
// den kanoniske personmodel: en source_persona er en forekomst i én kilde.
import { supabase } from '../supabase';

export type SourcePersonaAction = 'same' | 'different' | 'unresolved' | 'new_person_needed';

export type SourcePersonaCandidate = {
  candidateId: string; runId: string; rank: number; score: number; tier: string;
  personId: number; personName: string; born: string | null; died: string | null; signals: string[];
  // Trin 5b: kandidatvisning (titler, egen post, familie med hovedpersonen).
  titles: string[]; ownPostKey: string | null; familyId: number | null; ordinal: number | null;
};
// Trin 5b 2b-i: hvorfor en ægtefælle står i køen (udledt i databasen) og hovedpersonens faktiske partnere.
export type ReviewReason = 'context_unavailable' | 'principal_no_family' | 'partner_is_candidate' | 'partner_not_candidate';
export type PrincipalPartner = {
  personId: number; familyId: number; name: string; born: string | null; died: string | null; ordinal: number | null; konfidens: string[];
};
const REVIEW_REASONS: ReviewReason[] = ['context_unavailable', 'principal_no_family', 'partner_is_candidate', 'partner_not_candidate'];

export type SourcePersonaHistoryRow = {
  version: number; decisionStatus: string; canonicalPersonId: number | null;
  basis: string | null; candidateId: string | null; reason: string | null; decidedByName: string | null; decidedAt: string | null;
};

export type SourcePersonaQueueRow = {
  sourcePersonaId: string;
  sourceId: number;
  personaKey: string;
  decisionStatus: string | null;
  version: number;
  canonicalPersonId: number | null;
  mentionCount: number;
  bestTier: string | null;
  reason: string | null;
  mentionRole: string | null;
};

export type SourcePersonaDetail = {
  persona: SourcePersonaQueueRow;
  mentions: Array<{
    mentionKind: string; mentionRole: string; verbatimText: string;
    observationKind: string; pageFrom: number; pageTo: number;
    textVersions: Array<{ version: number; verbatimText: string; preferred: boolean }>;
  }>;
  placements: Array<{ placementRole: string; printedNumber: string | null; generationLabelRaw: string | null }>;
  interpretations: Array<{ predicate: string; value: unknown; status: string; confidence: number; derivation_kind: string }>;
  candidates: SourcePersonaCandidate[];
  collisions: Array<{ personId: number; personaKey: string }>;
  // Trin 5b: kun for ægtefælle-personas med entydig familiekontekst.
  familyContext: { principalRecordKey: string; marriageOrdinal: number } | null;
  principalPartners: PrincipalPartner[];
  reviewReason: ReviewReason | null;
};

export async function fetchSourcePersonaQueue(status: string | null = null, sourceId: number | null = null,
  cursor: string | null = null, mentionRole: string | null = null): Promise<SourcePersonaQueueRow[]> {
  const { data, error } = await supabase.rpc('red_source_persona_queue', {
    p_status: status, p_source_id: sourceId, p_cursor: cursor, p_page_size: 50, p_mention_role: mentionRole,
  });
  if (error) throw new Error(error.message);
  return (data ?? []).map((row: Record<string, unknown>) => ({
    sourcePersonaId: String(row.source_persona_id), sourceId: Number(row.source_id),
    personaKey: String(row.persona_key), decisionStatus: row.decision_status == null ? null : String(row.decision_status),
    version: Number(row.version), canonicalPersonId: row.canonical_person_id == null ? null : Number(row.canonical_person_id),
    mentionCount: Number(row.mention_count),
    bestTier: row.best_tier == null ? null : String(row.best_tier),
    reason: row.reason == null ? null : String(row.reason),
    mentionRole: row.mention_role == null ? null : String(row.mention_role),
  }));
}

export async function fetchSourcePersonaDetail(sourcePersonaId: string): Promise<SourcePersonaDetail> {
  const { data, error } = await supabase.rpc('red_source_persona_detail', { p_source_persona_id: sourcePersonaId });
  if (error) throw new Error(error.message);
  const raw = data as Record<string, unknown>;
  const persona = raw.persona as Record<string, unknown>;
  return {
    persona: {
      sourcePersonaId: String(persona.source_persona_id), sourceId: Number(persona.source_id),
      personaKey: String(persona.persona_key), decisionStatus: persona.decision_status == null ? null : String(persona.decision_status),
      version: Number(persona.version), canonicalPersonId: persona.canonical_person_id == null ? null : Number(persona.canonical_person_id),
      mentionCount: Array.isArray(raw.mentions) ? raw.mentions.length : 0,
      bestTier: null, reason: null, mentionRole: null,
    },
    mentions: Array.isArray(raw.mentions) ? raw.mentions.map((mention) => {
      const value = mention as Record<string, unknown>;
      return {
        mentionKind: String(value.mention_kind), mentionRole: String(value.mention_role),
        verbatimText: String(value.verbatim_text), observationKind: String(value.observation_kind),
        pageFrom: Number(value.page_from), pageTo: Number(value.page_to),
        textVersions: Array.isArray(value.text_versions) ? value.text_versions.map((textVersion) => {
          const text = textVersion as Record<string, unknown>;
          return { version: Number(text.version), verbatimText: String(text.verbatim_text), preferred: Boolean(text.preferred) };
        }) : [],
      };
    }) : [],
    placements: Array.isArray(raw.placements) ? raw.placements.map((placement) => {
      const value = placement as Record<string, unknown>;
      return { placementRole: String(value.placement_role), printedNumber: value.printed_number == null ? null : String(value.printed_number), generationLabelRaw: value.generation_label_raw == null ? null : String(value.generation_label_raw) };
    }) : [],
    interpretations: (raw.interpretations ?? []) as SourcePersonaDetail['interpretations'],
      candidates: Array.isArray(raw.candidates) ? raw.candidates.map((c) => {
        const v = c as Record<string, unknown>;
        return { candidateId: String(v.candidate_id), runId: String(v.run_id), rank: Number(v.rank), score: Number(v.score),
          tier: String(v.tier), personId: Number(v.person_id), personName: String(v.person_name ?? ''),
          born: v.born == null ? null : String(v.born), died: v.died == null ? null : String(v.died),
          signals: Array.isArray((v.basis as Record<string, unknown> | undefined)?.signals) ? ((v.basis as Record<string, unknown>).signals as unknown[]).map(String) : [],
          titles: Array.isArray(v.titles) ? (v.titles as unknown[]).map(String) : [],
          ownPostKey: v.own_post_key == null ? null : String(v.own_post_key),
          familyId: v.family_id == null ? null : Number(v.family_id),
          ordinal: v.ordinal == null ? null : Number(v.ordinal) };
      }) : [],
      collisions: Array.isArray(raw.collisions) ? raw.collisions.map((c) => {
        const v = c as Record<string, unknown>;
        return { personId: Number(v.person_id), personaKey: String(v.persona_key) };
      }) : [],
      familyContext: raw.family_context ? (() => {
        const fc = raw.family_context as Record<string, unknown>;
        return { principalRecordKey: String(fc.principal_record_key), marriageOrdinal: Number(fc.marriage_ordinal) };
      })() : null,
      principalPartners: Array.isArray(raw.principal_partners) ? raw.principal_partners.map((p) => {
        const v = p as Record<string, unknown>;
        return { personId: Number(v.person_id), familyId: Number(v.family_id), name: String(v.name ?? ''),
          born: v.born == null ? null : String(v.born), died: v.died == null ? null : String(v.died),
          ordinal: v.ordinal == null ? null : Number(v.ordinal),
          konfidens: Array.isArray(v.konfidens) ? (v.konfidens as unknown[]).map(String) : [] };
      }) : [],
      reviewReason: REVIEW_REASONS.includes(raw.review_reason as ReviewReason) ? raw.review_reason as ReviewReason : null,
  };
}

export function buildSourcePersonaDecisionCall(
  sourcePersonaId: string, expectedVersion: number, action: SourcePersonaAction,
  canonicalPersonId: number | null, note: string, candidate: { candidateId: string; runId: string } | null = null,
) {
  if (!sourcePersonaId || !Number.isInteger(expectedVersion) || expectedVersion < 0 || !note.trim()) return null;
  if (action === 'same' && (canonicalPersonId == null || !Number.isSafeInteger(canonicalPersonId) || canonicalPersonId <= 0)) return null;
  if (action !== 'same' && (canonicalPersonId !== null || candidate !== null)) return null;
  return {
    fn: 'red_afgoer_source_persona' as const,
    args: {
      p_source_persona_id: sourcePersonaId, p_expected_version: expectedVersion, p_action: action,
      p_canonical_person_id: canonicalPersonId, p_note: note.trim(),
      p_context: candidate ? { basis: 'web_detail', candidate_id: candidate.candidateId, run_id: candidate.runId } : { basis: 'web_detail' },
    },
  };
}

export async function decideSourcePersona(
  sourcePersonaId: string, expectedVersion: number, action: SourcePersonaAction,
  canonicalPersonId: number | null, note: string, candidate: { candidateId: string; runId: string } | null = null,
): Promise<number> {
  const call = buildSourcePersonaDecisionCall(sourcePersonaId, expectedVersion, action, canonicalPersonId, note, candidate);
  if (!call) throw new Error('Ugyldig identitetsafgørelse.');
  const { data, error } = await supabase.rpc(call.fn, call.args);
  if (error) throw new Error(error.message);
  return Number(data);
}

export async function fetchSourcePersonaHistory(sourcePersonaId: string): Promise<SourcePersonaHistoryRow[]> {
  const { data, error } = await supabase.rpc('red_source_persona_history', { p_source_persona_id: sourcePersonaId });
  if (error) throw new Error(error.message);
  return (data ?? []).map((r: Record<string, unknown>) => {
    const ev = (r.evidence ?? {}) as Record<string, unknown>;
    return {
      version: Number(r.version), decisionStatus: String(r.decision_status),
      canonicalPersonId: r.canonical_person_id == null ? null : Number(r.canonical_person_id),
      basis: ev.basis == null ? null : String(ev.basis), candidateId: ev.candidate_id == null ? null : String(ev.candidate_id),
      reason: ev.reason == null ? null : String(ev.reason),
      decidedByName: r.decided_by_name == null ? null : String(r.decided_by_name),
      decidedAt: r.decided_at == null ? null : String(r.decided_at),
    };
  });
}
