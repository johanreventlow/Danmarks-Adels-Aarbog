// Identitets-linkets etiket i redaktørens "Samme person"-liste. Egen fil (ingen DOM, ingen
// Supabase-import) så den kan enheds-testes uden miljøvariabler — data/redaktionRead.ts importerer
// supabase.ts, som kaster ved modul-load uden VITE_SUPABASE_*.
//
// SammeSomLink.retning er klassificeret set fra den REDIGEREDE person (mapSammeSomLinks i
// redaktionRead.ts); rækken viser MODPARTENS navn — derfor er rollen spejlvendt.
//
// Forklaringen beskriver relationen, ikke resultatet: et link medfører ikke altid en foldning.
// Bekræftelsesdialogen kan sige "⚠ Foldes ikke endnu — … Linket oprettes, men personerne vises
// separat til konflikten er løst", og listen må ikke love mere end den.
export function sammeSomEtiket(retning: 'alias' | 'kanonisk'): { rolle: 'KANONISK' | 'ALIAS'; forklaring: string } {
  return retning === 'alias'
    ? { rolle: 'KANONISK', forklaring: 'den post du redigerer er markeret som alias for denne' }
    : { rolle: 'ALIAS', forklaring: 'markeret som alias for den post du redigerer' };
}
