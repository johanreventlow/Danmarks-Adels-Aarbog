import type { Change } from './redaktionWrite';
import type { MediaAnvendelse, MediaBibliotekPost, MedieKoe } from './redaktionRead';
import { supabase } from '../supabase';
import { getAll } from '@daa/core';

type MergeTargetType = 'person' | 'estate' | 'coat_of_arms' | 'lineage';

export type MediaMergeStep = {
  kind: 'soft-delete-copy' | 'link-original' | 'delete-copy-relation';
  change: Change;
  description: string;
};

export type MediaMergePlan = {
  copyId: string;
  originalId: string;
  mentions: MediaAnvendelse['mentions'];
  steps: MediaMergeStep[];
};

export type MediaMergeState = {
  copyStatus: string;
  copyAnvendelse: MediaAnvendelse;
  originalAnvendelse: MediaAnvendelse;
};

/** Stabil snapshot-identitet for præcis det mention-varsel redaktøren har gennemgået. */
export function mediaMentionFingerprint(mentions: readonly MediaAnvendelse['mentions'][number][]): string {
  return JSON.stringify(mentions
    .map((mention) => [mention.kildeType, mention.kildeId, mention.subjektNavn] as const)
    .sort((a, b) => JSON.stringify(a).localeCompare(JSON.stringify(b))));
}

function validCreatedAt(value: string | null): number | null {
  if (!value) return null;
  const timestamp = Date.parse(value);
  return Number.isFinite(timestamp) ? timestamp : null;
}

/** Bevar bibliotekets normale rækkefølge; kun den strandede kø har aldersprioritet. */
export function sortMediaForQueue(
  rows: readonly MediaBibliotekPost[],
  queue: MedieKoe | 'alle',
): MediaBibliotekPost[] {
  if (queue !== 'strandede') return [...rows];
  return [...rows].sort((a, b) => {
    const aTime = validCreatedAt(a.createdAt);
    const bTime = validCreatedAt(b.createdAt);
    if (aTime == null && bTime == null) return 0;
    if (aTime == null) return 1;
    if (bTime == null) return -1;
    return aTime - bTime;
  });
}

/**
 * Flet-kandidater er kun andre, aktuelle `klar`-rækker med samme komplette fase-3-trilling.
 * Kopien må derimod godt allerede være `fjernet`, så et afbrudt flow kan genoptages fra
 * papirkurvens filside.
 */
export function findMediaMergeCandidates(
  copy: Pick<MediaBibliotekPost, 'id' | 'uploadStatus' | 'byteSize' | 'bredde' | 'hoejde'>,
  rows: readonly MediaBibliotekPost[],
): MediaBibliotekPost[] {
  if ((copy.uploadStatus !== 'klar' && copy.uploadStatus !== 'fjernet')
    || copy.byteSize == null || copy.bredde == null || copy.hoejde == null) return [];
  return rows.filter((candidate) => (
    candidate.id !== copy.id
    && candidate.uploadStatus === 'klar'
    && candidate.byteSize != null && candidate.bredde != null && candidate.hoejde != null
    && candidate.byteSize === copy.byteSize
    && candidate.bredde === copy.bredde
    && candidate.hoejde === copy.hoejde
  ));
}

function targetKey(target: Pick<MediaAnvendelse['afbildet'][number], 'type' | 'id'>): string {
  return `${target.type}:${target.id}`;
}

function isMergeTargetType(type: string): type is MergeTargetType {
  return type === 'person' || type === 'estate' || type === 'coat_of_arms' || type === 'lineage';
}

export function buildMediaMergePlan(args: {
  copyId: string;
  copyStatus: string;
  copyAnvendelse: MediaAnvendelse;
  originalId: string;
  originalAnvendelse: MediaAnvendelse;
}): MediaMergePlan {
  if (args.copyId === args.originalId) throw new Error('Kopien kan ikke flettes ind i sig selv.');
  const steps: MediaMergeStep[] = [];
  if (args.copyStatus !== 'fjernet') {
    steps.push({
      kind: 'soft-delete-copy',
      description: `Flyt kopi #${args.copyId} til papirkurven`,
      change: {
        art: 'fjernMedia', subjektType: 'media', subjektId: args.copyId, mediaId: args.copyId,
      },
    });
  }

  const originalTargets = new Set(args.originalAnvendelse.afbildet.map(targetKey));
  for (const relation of args.copyAnvendelse.afbildet) {
    if (!isMergeTargetType(relation.type)) {
      throw new Error(`Ukendt mediemåltype i relation ${relation.relationId}: ${relation.type}`);
    }
    if (!originalTargets.has(targetKey(relation))) {
      steps.push({
        kind: 'link-original',
        description: `Tilknyt original #${args.originalId} til ${relation.navn}`,
        change: {
          art: 'tilknytMedia', subjektType: 'media', subjektId: args.originalId,
          mediaId: args.originalId, payload: { maalType: relation.type, maalId: relation.id },
        },
      });
    }
    // Også når originalen allerede har målet: en afbrudt tidligere kørsel kan have nået linket,
    // men ikke afkoblingen. Rerun afslutter derfor præcis den resterende relation.
    steps.push({
      kind: 'delete-copy-relation',
      description: `Fjern kopiens tilknytning til ${relation.navn}`,
      change: {
        art: 'sletMediaRelationUdenEvidens', subjektType: 'media', subjektId: args.copyId,
        relationId: relation.relationId,
      },
    });
  }

  return {
    copyId: args.copyId,
    originalId: args.originalId,
    mentions: [...args.copyAnvendelse.mentions],
    steps,
  };
}

function isAlreadyLinkedRace(error: unknown): boolean {
  return /mediet er allerede tilknyttet dette subjekt/i.test(String((error as Error)?.message ?? error));
}

type RelationEvidenceRow = { target_id: string | number };

/**
 * Relationsevidens er polymorf og kan derfor ikke joines fra relation-tabellen. Citations
 * er dækket af assertion-opslaget, fordi citation.assertion_id peger på assertion-rækken.
 */
export async function fetchMediaMergeRelationEvidence(relationIds: readonly string[]): Promise<string[]> {
  const ids = [...new Set(relationIds)];
  if (!ids.length) return [];
  const [assertions, conclusions, notes] = await Promise.all([
    getAll<RelationEvidenceRow>(() => supabase.from('assertion').select('target_id::text')
      .eq('target_type', 'relation').in('target_id', ids)),
    getAll<RelationEvidenceRow>(() => supabase.from('conclusion').select('target_id::text')
      .eq('target_type', 'relation').in('target_id', ids)),
    getAll<RelationEvidenceRow>(() => supabase.from('note').select('target_id::text')
      .eq('target_type', 'relation').in('target_id', ids)),
  ]);
  return [...new Set([...assertions, ...conclusions, ...notes].map((row) => String(row.target_id)))].sort();
}

export async function executeMediaMerge(
  args: { copyId: string; originalId: string; dryRun: boolean; confirmedMentionFingerprint: string },
  deps: {
    loadState: () => Promise<MediaMergeState>;
    loadRelationEvidence: (relationIds: readonly string[]) => Promise<string[]>;
    execute: (change: Change) => Promise<void>;
  },
): Promise<
  | { kind: 'mentions-changed'; state: MediaMergeState; mentionFingerprint: string }
  | { kind: 'dry-run' | 'completed'; plan: MediaMergePlan }
> {
  // Tilstand og relationer hentes ved hvert forsøg. Det gør papirkurv-status og en delvist flyttet
  // relation autoritative ved rerun i stedet for at stole på den åbne dialogs gamle liste-state.
  const state = await deps.loadState();
  const currentMentionFingerprint = mediaMentionFingerprint(state.copyAnvendelse.mentions);
  if (currentMentionFingerprint !== args.confirmedMentionFingerprint) {
    // Vigtigt: ingen plan eksekveres, før redaktøren har set og eksplicit genbekræftet det nye
    // autoritative varsel. Gælder både tilføjede, fjernede og ændrede mention-detaljer.
    return { kind: 'mentions-changed', state, mentionFingerprint: currentMentionFingerprint };
  }
  const relationIds = state.copyAnvendelse.afbildet.map((relation) => relation.relationId);
  const evidencedRelationIds = await deps.loadRelationEvidence(relationIds);
  if (evidencedRelationIds.length) {
    throw new Error(`Blød flet er blokeret: kopiens relationer har evidens (${evidencedRelationIds.join(', ')}).`);
  }
  const plan = buildMediaMergePlan({ ...args, ...state });
  if (args.dryRun) return { kind: 'dry-run', plan };

  for (const step of plan.steps) {
    try {
      await deps.execute(step.change);
    } catch (error) {
      if (step.kind !== 'link-original' || !isAlreadyLinkedRace(error)) throw error;
      // En anden redaktør nåede samme link efter vores autoritative læsning. Unikhedsfejlen er
      // postconditionen; fortsæt til den efterfølgende afkobling af kopiens relation.
    }
  }
  return { kind: 'completed', plan };
}
