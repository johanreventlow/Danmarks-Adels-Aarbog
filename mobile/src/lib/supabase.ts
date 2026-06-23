// Supabase-klient. url-polyfill SKAL importeres før supabase-js i RN, ellers brækker
// fetch/URL (advisor 2026-06-23). AsyncStorage som auth-storage så session (og senere
// profiles.reventlow_person_id) overlever app-genstart.
import 'react-native-url-polyfill/auto';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { createClient } from '@supabase/supabase-js';

// Anon/publishable-nøgle er offentlig by design (RLS gater læseadgang) — men holdes i env,
// ikke hardcoded. Sæt i mobile/.env via EXPO_PUBLIC_-prefix (eksponeres i klient-bundlen).
const url = process.env.EXPO_PUBLIC_SUPABASE_URL;
const anonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY;

if (!url || !anonKey) {
  // Kaster ikke — loaderen falder tilbage til offline-seed hvis klienten mangler.
  console.warn(
    '[supabase] EXPO_PUBLIC_SUPABASE_URL / _ANON_KEY mangler — kører på offline-seed.',
  );
}

export const supabaseEnabled = Boolean(url && anonKey);

export const supabase = supabaseEnabled
  ? createClient(url as string, anonKey as string, {
      auth: {
        storage: AsyncStorage,
        autoRefreshToken: true,
        persistSession: true,
        detectSessionInUrl: false,
      },
    })
  : null;
