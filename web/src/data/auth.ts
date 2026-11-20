// Redaktør-auth til web-arbejdsbordet. Supabase Auth (e-mail/adgangskode) via den eksisterende
// anon-klient; efter login bruger samme klient brugerens JWT automatisk til RPC-skrivning.
// Rollen slås op i `profiles` (redaktion → skriver direkte; øvrige → forslag til staging).
import { supabase } from '../supabase';

export type Rolle = 'redaktion' | 'medlem' | string;
export type RedSession = { email: string; role: Rolle; userId: string };

export const ROLLE_UDFALD = 'ROLLE_UDFALD';

// Review 37 W6: et opslags-udfald må ALDRIG stille degradere en redaktør til »medlem« (så
// rettelser blev til forslag resten af sessionen). Kun en rigtig, tom profil giver 'medlem';
// en fejl kastes, så kalderen kan vise den og prøve igen.
async function rolleFor(userId: string): Promise<Rolle> {
  let svar;
  try {
    svar = await supabase.from('profiles').select('rolle').eq('id', userId).maybeSingle();
  } catch (e) {
    console.warn('[auth] rolleopslag fejlede:', e);
    throw new Error(ROLLE_UDFALD);
  }
  if (svar.error) {
    console.warn('[auth] rolleopslag fejlede:', svar.error);
    throw new Error(ROLLE_UDFALD);
  }
  return (svar.data?.rolle as Rolle) ?? 'medlem';
}

export async function signIn(email: string, password: string): Promise<RedSession> {
  const { data, error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
  if (error) throw new Error(error.message);
  const userId = data.user?.id ?? '';
  let role: Rolle;
  try {
    role = await rolleFor(userId);
  } catch (e) {
    // Uden kendt rolle er brugeren hverken redaktør eller medlem: log ud igen, så »Log ind« kan prøves på ny.
    await supabase.auth.signOut().catch(() => undefined);
    throw e;
  }
  return { email: data.user?.email ?? email.trim(), role, userId };
}

// Login-fejl i ord, læseren kan bruge. Supabase svarer på engelsk ("Invalid login credentials");
// den rå tekst logges, men vises ikke.
export function loginFejlTekst(e: unknown): string {
  const m = e instanceof Error ? e.message : String(e);
  if (/invalid login credentials/i.test(m)) return 'E-mail eller adgangskode er forkert.';
  if (/email not confirmed/i.test(m)) return 'E-mailadressen er ikke bekræftet endnu.';
  if (m === ROLLE_UDFALD) return 'Din rolle kunne ikke hentes. Prøv igen om lidt.';
  console.warn('[login] fejlede:', m);
  return 'Login lykkedes ikke. Prøv igen om lidt.';
}

// Abonnér på sessionsskift fra Supabase (udløb, logout i en anden fane, brugerskift). Callbacken må
// ikke selv kalde Supabase synkront (deadlock i supabase-js): udskyd opslag med setTimeout.
export function onAuthChange(cb: (event: string, userId: string | null) => void): () => void {
  const { data } = supabase.auth.onAuthStateChange((event, session) => cb(event, session?.user?.id ?? null));
  return () => data.subscription.unsubscribe();
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
