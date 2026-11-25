// samme_som-kanterne til opstartens collapse (spec 2026-07-02): relation (subjekt=alias, objekt=kanonisk) + afklaret
// konklusion. Polymorf kobling (conclusion.target_type/target_id), ingen FK → hentes separat og matches i JS.
// Spejl af web/src/data/sammeSomKanter.ts (review 37 Y2, ce920139 + 14d1bfd3).
//
// Før hentede mobilen ALLE afklarede relationskonklusioner (~2.300 rækker, 3 offset-sider à 630-815 ms som gæst) og
// slugte enhver fejl til »ingen collapse«: så viste appen 1.725 personer i stedet for 919, uden banner. Nu hentes kun
// konklusionerne for samme_som-relationernes id'er i bidder à 200, og enhver fejl — også i én bid — afviser det hele:
// en halv sammenfoldning er værre end ingen, og storen viser så fejlen i stedet for tavse dubletpersoner.
import { getAll } from '@daa/core';
import type { supabase } from '../lib/supabase';
import { chunks, mapLimited, orThrow } from './bidder';

export type SammeSomKant = { alias: string; canonical: string };

type Sb = NonNullable<typeof supabase>;
type RelationRaekke = { id: number | string; subjekt_id: number | string; objekt_id: number | string };

const IN_BID = 200;
const SAMTIDIGE_BIDDER = 4;

// Ét genforsøg PR. KALD (relationerne, hver bid) — fx efter at free-tier-basen har været sat på pause, eller en
// enkelt 500 under belastning. Fejler et kald to gange, afvises det hele.
async function medGenforsoeg<T>(hvad: string, ventMs: number, kald: () => Promise<T>): Promise<T> {
  try {
    return await kald();
  } catch (e) {
    console.warn(`[loadFromSupabase] ${hvad} fejlede — prøver igen:`, e);
    if (ventMs > 0) await new Promise((r) => setTimeout(r, ventMs));
    return kald();
  }
}

export async function hentSammeSomKanter(sb: Sb, ventMs = 500): Promise<SammeSomKant[]> {
  const relationer = await medGenforsoeg('samme_som-relationer', ventMs, () => getAll<RelationRaekke>(() =>
    sb.from('relation').select('id,subjekt_id,objekt_id')
      .eq('rolle', 'samme_som').eq('subjekt_type', 'person').eq('objekt_type', 'person').order('id'),
  ));
  if (!relationer.length) return [];
  // Id'er som strenge: bigint > 2^53 må ikke gå gennem Number().
  const ids = relationer.map((r) => String(r.id));
  const bidder = await mapLimited(chunks(ids, IN_BID), SAMTIDIGE_BIDDER, (bid) =>
    medGenforsoeg('samme_som-konklusioner', ventMs, async () => orThrow(
      await sb.from('conclusion').select('target_id')
        .eq('target_type', 'relation').eq('status', 'afklaret').in('target_id', bid),
      'samme_som-konklusioner',
    ) ?? []),
  );
  const afklaret = new Set(bidder.flat().map((c: { target_id: number | string }) => String(c.target_id)));
  return relationer
    .filter((r) => afklaret.has(String(r.id)))
    .map((r) => ({ alias: String(r.subjekt_id), canonical: String(r.objekt_id) }));
}
