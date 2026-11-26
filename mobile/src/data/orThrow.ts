// Delt fejl-tjek for supabase-js-svar. supabase-js kaster ikke selv: en RLS-/grant-/netfejl
// kommer som `{ data: null, error }`, og et blot `data ?? []` gør den til "ingen data" (tavst tom
// tilstand). orThrow kaster fejlen frem, så kalderen kan skelne fejl fra tomt. Samme kontrakt som
// orThrow i public.ts (kopieret bevidst, så redaktionens læselag ikke afhænger af public.ts).
export function orThrow<T>(res: { data: T; error?: unknown }, label: string): T {
  if (res.error) {
    throw Object.assign(
      new Error(`${label}: ${(res.error as { message?: string })?.message ?? 'ukendt fejl'}`),
      { cause: res.error },
    );
  }
  return res.data;
}
