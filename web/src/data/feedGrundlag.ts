// Grundlaget for feedets »Nævnt i Aarbogen«-kort: hvilke personer har MERE end et navn
// (embede, gods, hændelse, historie)? Et kort om en person må aldrig vises, fordi en hentning
// fejlede og så tom ud — derfor kaster denne funktion ved enhver fejl i stedet for at falde
// tilbage til en tom mængde (ingen safe()), og kalderen sender så intet naevntGrundlag.
// Kun person-id'er hentes; teksterne hentes af feedets egne loadere.
import type { NaevntGrundlag } from '@daa/feed';
import { supabase } from '../supabase';
import { fetchHaendelseFeed } from './haendelseFeed';
import { hentNaevntSubjekter, type SubjektRow } from './forside/kilder';

export function buildNaevntGrundlag(
  rowGroups: SubjektRow[][],
  canonicalIdById: Record<string, string>,
): NaevntGrundlag {
  const personer = new Set<string>();
  for (const rows of rowGroups) {
    for (const row of rows) {
      const id = String(row.subjekt_id);
      personer.add(canonicalIdById[id] ?? id);
    }
  }
  return { personerMedMereEndNavn: personer };
}

export async function fetchNaevntGrundlag(
  canonicalIdById: Record<string, string>,
): Promise<NaevntGrundlag> {
  // Hændelser via feed-RPC'en i bidder (review 37 Y3), med samme regel pr. rolle som tabellens RLS. Bladreren
  // kaster ved enhver sidefejl, også efter en vellykket side, så et delvist resultat aldrig gør en person med
  // hændelser til »kun nævnt«. Den deles med hændelseskortene (fetchHaendelseFeed).
  return buildNaevntGrundlag(await hentNaevntSubjekter(supabase, fetchHaendelseFeed()), canonicalIdById);
}
