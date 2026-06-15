import { createClient } from "@supabase/supabase-js";

// Læses fra .env.local (Vite eksponerer kun VITE_-prefiksede vars til klienten).
const url = import.meta.env.VITE_SUPABASE_URL;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

if (!url || !anonKey) {
  throw new Error(
    "Mangler VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY. " +
      "Kopiér .env.local.example til .env.local og udfyld den.",
  );
}

// Kun den offentlige anon-nøgle. RLS styrer hvad denne rolle må læse.
export const supabase = createClient(url, anonKey);
