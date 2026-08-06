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
};

type RawHist = {
  id: number;
  actor_navn: string | null;
  created_at: string;
  operation: string | null;
  summary: string | null;
  reverterer_id: number | null;
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
  };
}

export async function fetchHistorik(personId: string): Promise<HistPost[]> {
  const { data, error } = await supabase.rpc('hist_for_subjekt', { p_type: 'person', p_id: Number(personId) });
  if (error) throw new Error(error.message);
  const rows: RawHist[] = data ?? [];
  const revertedIds = new Set(rows.map((r) => r.reverterer_id).filter((id): id is number => id != null));
  return rows.map((r) => mapHistRow(r, revertedIds));
}
