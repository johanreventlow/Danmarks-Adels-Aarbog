// samme_som-kanterne til opstartens collapse (spec 2026-07-02): relation (subjekt=alias, objekt=kanonisk) + afklaret
// konklusion. Polymorf kobling (conclusion.target_type/target_id), ingen FK → hentes separat og matches i JS.
//
// Review 37 Y2: før hentede opstarten ALLE afklarede relationskonklusioner (prod 24/11 som gæst: ~2.300 rækker i 3
// offset-sider à ~630 ms, fordi RLS-kaskaden evaluerer alle relationer pr. side) og brugte kun samme_som-delen.
// Nu hentes kun konklusionerne for samme_som-relationernes id'er, i bidder à 200 (~64 ms pr. bid, målt som anon).
// En fejl blev før slugt til »ingen collapse«, så dubletpersoner dukkede op uden fejlbesked. Nu er enhver fejl —
// også i én bid — en fejl for det hele: en halv sammenfoldning er værre end ingen.
import { getAll } from '@daa/core';
import { chunks, mapLimited, type Sb } from './forside/kilder';
import { orThrow } from './orThrow';

export type SammeSomKant = { alias: string; canonical: string };

type RelationRaekke = { id: number | string; subjekt_id: number | string; objekt_id: number | string };

const IN_BID = 200;
const SAMTIDIGE_BIDDER = 4;

export async function hentSammeSomKanter(sb: Sb): Promise<SammeSomKant[]> {
  const relationer = await getAll<RelationRaekke>(() =>
    sb.from('relation').select('id,subjekt_id,objekt_id')
      .eq('rolle', 'samme_som').eq('subjekt_type', 'person').eq('objekt_type', 'person').order('id'),
  );
  if (!relationer.length) return [];
  // Id'er som strenge: bigint > 2^53 må ikke gå gennem Number() (dual-review 21 N2).
  const ids = relationer.map((r) => String(r.id));
  const bidder = await mapLimited(chunks(ids, IN_BID), SAMTIDIGE_BIDDER, async (bid) =>
    orThrow(
      await sb.from('conclusion').select('target_id')
        .eq('target_type', 'relation').eq('status', 'afklaret').in('target_id', bid),
      'samme_som-konklusioner',
    ) ?? [],
  );
  const afklaret = new Set(bidder.flat().map((c: { target_id: number | string }) => String(c.target_id)));
  return relationer
    .filter((r) => afklaret.has(String(r.id)))
    .map((r) => ({ alias: String(r.subjekt_id), canonical: String(r.objekt_id) }));
}

// Ét genforsøg (fx efter at free-tier-basen har været sat på pause), derefter afvises — loadModel fejler så,
// og læseren får fejlskærmen med »Prøv igen« i stedet for en model med tavse dubletpersoner.
export async function hentSammeSomKanterMedGenforsoeg(sb: Sb, ventMs = 500): Promise<SammeSomKant[]> {
  try {
    return await hentSammeSomKanter(sb);
  } catch (e) {
    console.warn('[loadModel] samme_som-hentning fejlede — prøver igen:', e);
    if (ventMs > 0) await new Promise((r) => setTimeout(r, ventMs));
    return hentSammeSomKanter(sb);
  }
}
