// Ændringshistorik pr. person (issue #144) — læse-adapter over hist_for_subjekt.
// mapHistRow PORTERET fra mobile/src/data/redaktionRead.ts — hold i sync. Udvidet med
// erFortryd: et fortryd-sæt logger bevidst ingen child-events (red_fortryd_change_set
// nuller app.change_set_id under inverse-DML), så det kan ikke selv spilles baglæns —
// UI'et skjuler fortryd-knappen for dem i stedet for at tilbyde et tavst no-op.
// Redaktøren arbejder i det RÅ id-rum (loadModel({ collapse: false })), så historikken
// slås op på det rå person-id — ingen samme_som-kanonisering her (skrive-id-rummet).
import { supabase } from '../supabase';
import { formatTidspunkt } from './format';

export type HistPost = {
  id: string;
  hvem: string;
  hvornaar: string;
  resume: string;
  reverteret: boolean;
  erFortryd: boolean;
  undoKind?: 'change_set' | 'publication_event';
  canReverse?: boolean;
  blockingReason?: string | null;
  changeSetId?: string;
  sourceRecordRef?: string | null;
  legacyPublicationRef?: string | null;
};

type RawHist = {
  id: number;
  actor_navn: string | null;
  created_at: string;
  operation: string | null;
  summary: string | null;
  reverterer_id: number | null;
};

type RawNarrativePublicationHistory = {
  event_id: string;
  change_set_id: number | string;
  stream_version: number;
  event_type: string;
  source_record_ref: string | null;
  legacy_publication_ref: string | null;
  before_text: string | null;
  after_text: string | null;
  decided_by_name: string | null;
  created_at: string;
  can_reverse: boolean;
  blocking_reason: string | null;
};

// revertedIds: id'er på rækker der ER blevet fortrudt af en ANDEN række i samme liste
// (review10 H2). r.reverterer_id peger omvendt — fra fortrydelsen TIL den fortrudte —
// så status kan ikke afgøres af rækken selv; den kræver hele listens reverterer_id-mængde.
export function mapHistRow(r: RawHist, revertedIds: ReadonlySet<number> = new Set()): HistPost {
  return {
    id: String(r.id),
    hvem: r.actor_navn ?? 'ukendt',
    // formatTidspunkt (delt m. OCR-historikken) frem for mobilens toLocaleString — samme
    // visuelle format i webbens to historik-flader vejer tungere end 1:1-porten her.
    hvornaar: formatTidspunkt(r.created_at),
    resume: r.summary ?? '(uden beskrivelse)',
    reverteret: revertedIds.has(r.id),
    erFortryd: r.operation === 'fortryd',
    undoKind: 'change_set',
    canReverse: !revertedIds.has(r.id) && r.operation !== 'fortryd',
    blockingReason: null,
  };
}

export function mapNarrativePublicationHistoryRow(r: RawNarrativePublicationHistory): HistPost {
  const isReversal = r.event_type === 'reversal';
  const eventLabel = r.event_type.replace(/_/g, ' ');
  const text = r.after_text ?? r.before_text ?? '(ingen tekst)';
  return {
    id: r.event_id,
    hvem: r.decided_by_name ?? 'ukendt',
    hvornaar: formatTidspunkt(r.created_at),
    resume: `Narrativ-publicering: ${eventLabel} — ${text}`,
    reverteret: false,
    erFortryd: isReversal,
    undoKind: 'publication_event',
    canReverse: r.can_reverse,
    blockingReason: r.blocking_reason,
    changeSetId: String(r.change_set_id),
    sourceRecordRef: r.source_record_ref,
    legacyPublicationRef: r.legacy_publication_ref,
  };
}

export async function fetchHistorik(personId: string): Promise<HistPost[]> {
  const parsedPersonId = Number(personId);
  const [genericResult, narrativeResult] = await Promise.all([
    supabase.rpc('hist_for_subjekt', { p_type: 'person', p_id: parsedPersonId }),
    supabase.rpc('red_person_narrative_publication_history', { p_person_id: parsedPersonId }),
  ]);
  if (genericResult.error) throw new Error(genericResult.error.message);
  if (narrativeResult.error) throw new Error(narrativeResult.error.message);
  const rows: RawHist[] = genericResult.data ?? [];
  const publicationRows = (narrativeResult.data ?? []) as RawNarrativePublicationHistory[];
  const publicationChangeSetIds = new Set(publicationRows.map((row) => String(row.change_set_id)));
  const revertedIds = new Set(rows.map((r) => r.reverterer_id).filter((id): id is number => id != null));
  // A publication event and its generic change-set row describe one mutation.  Keep
  // only the typed event, otherwise a record mutation could reach generic undo.
  const generic = rows
    .filter((r) => !publicationChangeSetIds.has(String(r.id)))
    .map((r) => ({ post: mapHistRow(r, revertedIds), createdAt: r.created_at }));
  const narrative = publicationRows
    .map((r) => ({ post: mapNarrativePublicationHistoryRow(r), createdAt: r.created_at }));
  return [...generic, ...narrative]
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
    .map(({ post }) => post);
}
