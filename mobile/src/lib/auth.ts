// Auth-helpers: tynd wrapper om supabase.auth + profiles-opslag. Ren mapping-logik
// (mapProfileRow) er adskilt så den kan unit-testes uden netværk.
import { supabase } from './supabase';

export type Rolle = 'redaktion' | 'medlem';
export type Profile = { rolle: Rolle; reventlowPersonId: string | null };

export function mapProfileRow(row: { rolle?: string; reventlow_person_id?: number | null } | null): Profile {
  const rolle: Rolle = row?.rolle === 'redaktion' ? 'redaktion' : 'medlem';
  const rid = row?.reventlow_person_id;
  return { rolle, reventlowPersonId: rid != null ? String(rid) : null };
}

export const ROLLE_UDFALD = 'Rollen kunne ikke hentes — prøv igen';

// Review 37 W6: et opslags-udfald må ALDRIG stille degradere en redaktør til »medlem«. Kun en
// rigtig, tom profil (ingen række) giver 'medlem'; en fejl kastes, så kalderen kan vise den.
export async function fetchProfile(userId: string): Promise<Profile> {
  if (!supabase) return { rolle: 'medlem', reventlowPersonId: null };
  let svar;
  try {
    svar = await supabase
      .from('profiles').select('rolle,reventlow_person_id').eq('id', userId).maybeSingle();
  } catch (e) {
    console.warn('[auth] rolleopslag fejlede:', e);
    throw new Error(ROLLE_UDFALD);
  }
  if (svar.error) {
    console.warn('[auth] rolleopslag fejlede:', svar.error);
    throw new Error(ROLLE_UDFALD);
  }
  return mapProfileRow(svar.data);
}

export async function signIn(email: string, password: string): Promise<{ userId: string } & Profile> {
  if (!supabase) throw new Error('Supabase ikke konfigureret');
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw new Error(error.message);
  let prof: Profile;
  try {
    prof = await fetchProfile(data.user.id);
  } catch (e) {
    // Uden kendt rolle er brugeren hverken redaktør eller medlem: log ud igen, så »Log ind« kan prøves på ny.
    await supabase.auth.signOut().catch(() => undefined);
    throw e;
  }
  return { userId: data.user.id, ...prof };
}

export async function signOut(): Promise<void> {
  if (supabase) await supabase.auth.signOut();
}
