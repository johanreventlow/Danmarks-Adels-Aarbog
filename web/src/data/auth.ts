// Redaktør-auth til web-arbejdsbordet. Supabase Auth (e-mail/adgangskode) via den eksisterende
// anon-klient; efter login bruger samme klient brugerens JWT automatisk til RPC-skrivning.
// Rollen slås op i `profiles` (redaktion → skriver direkte; øvrige → forslag til staging).
import { supabase } from '../supabase';

export type Rolle = 'redaktion' | 'medlem' | string;
export type RedSession = { email: string; role: Rolle; userId: string };

async function rolleFor(userId: string): Promise<Rolle> {
  try {
    const { data } = await supabase.from('profiles').select('rolle').eq('id', userId).maybeSingle();
    return (data?.rolle as Rolle) ?? 'medlem';
  } catch {
    return 'medlem';
  }
}

export async function signIn(email: string, password: string): Promise<RedSession> {
  const { data, error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
  if (error) throw new Error(error.message);
  const userId = data.user?.id ?? '';
  return { email: data.user?.email ?? email.trim(), role: await rolleFor(userId), userId };
}

export async function signOut(): Promise<void> {
  await supabase.auth.signOut();
}

// Genskab en eksisterende session ved sideindlæsning (Supabase persisterer JWT i localStorage).
export async function currentSession(): Promise<RedSession | null> {
  const { data } = await supabase.auth.getSession();
  const u = data.session?.user;
  if (!u) return null;
  return { email: u.email ?? '', role: await rolleFor(u.id), userId: u.id };
}
