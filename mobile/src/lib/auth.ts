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

export async function fetchProfile(userId: string): Promise<Profile> {
  if (!supabase) return { rolle: 'medlem', reventlowPersonId: null };
  const { data } = await supabase
    .from('profiles').select('rolle,reventlow_person_id').eq('id', userId).maybeSingle();
  return mapProfileRow(data);
}

export async function signIn(email: string, password: string): Promise<{ userId: string } & Profile> {
  if (!supabase) throw new Error('Supabase ikke konfigureret');
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw new Error(error.message);
  const prof = await fetchProfile(data.user.id);
  return { userId: data.user.id, ...prof };
}

export async function signOut(): Promise<void> {
  if (supabase) await supabase.auth.signOut();
}
