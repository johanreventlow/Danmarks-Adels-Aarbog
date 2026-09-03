// Privat redaktionsflade for kildens personaer. Den er bevidst ikke en del af
// den kanoniske personmodel: en source_persona er en forekomst i én kilde.
import { supabase } from '../supabase';

export type SourcePersonaAction = 'same' | 'different' | 'unresolved';

export type SourcePersonaQueueRow = {
  sourcePersonaId: string;
  sourceId: number;
  personaKey: string;
  decisionStatus: string | null;
  version: number;
  canonicalPersonId: number | null;
  mentionCount: number;
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
};

export function buildSourcePersonaDecisionCall(
  sourcePersonaId: string,
  expectedVersion: number,
  action: SourcePersonaAction,
  canonicalPersonId: number | null,
  note: string,
) {
  if (!sourcePersonaId || !Number.isInteger(expectedVersion) || expectedVersion < 0 || !note.trim()) return null;
  if (action === 'same' && (canonicalPersonId == null || !Number.isSafeInteger(canonicalPersonId) || canonicalPersonId <= 0)) return null;
  if (action !== 'same' && canonicalPersonId !== null) return null;
  return {
    fn: 'red_afgoer_source_persona' as const,
    args: {
      p_source_persona_id: sourcePersonaId,
      p_expected_version: expectedVersion,
      p_action: action,
      p_canonical_person_id: canonicalPersonId,
      p_note: note.trim(),
    },
  };
}

export async function fetchSourcePersonaQueue(status: string | null = null, sourceId: number | null = null, cursor: string | null = null): Promise<SourcePersonaQueueRow[]> {
  const { data, error } = await supabase.rpc('red_source_persona_queue', {
    p_status: status, p_source_id: sourceId, p_cursor: cursor, p_page_size: 50,
  });
  if (error) throw new Error(error.message);
  return (data ?? []).map((row: Record<string, unknown>) => ({
    sourcePersonaId: String(row.source_persona_id), sourceId: Number(row.source_id),
    personaKey: String(row.persona_key), decisionStatus: row.decision_status == null ? null : String(row.decision_status),
    version: Number(row.version), canonicalPersonId: row.canonical_person_id == null ? null : Number(row.canonical_person_id),
    mentionCount: Number(row.mention_count),
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
  };
}

export async function decideSourcePersona(
  sourcePersonaId: string, expectedVersion: number, action: SourcePersonaAction,
  canonicalPersonId: number | null, note: string,
): Promise<number> {
  const call = buildSourcePersonaDecisionCall(sourcePersonaId, expectedVersion, action, canonicalPersonId, note);
  if (!call) throw new Error('Ugyldig identitetsafgørelse.');
  const { data, error } = await supabase.rpc(call.fn, call.args);
  if (error) throw new Error(error.message);
  return Number(data);
}
