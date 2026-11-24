// Delt visning af medier (web + mobil): hvilke slags er portrætter, og billedtekstens formel.

// Portræt-egnede slags (hovedbillede på personkort). Sammenlign altid normaliseret (lowercase+trim),
// så 'Maleri'/'Portræt ' også genkendes.
export const PORTRAIT_SLAGS: ReadonlySet<string> = new Set(['foto', 'maleri', 'portræt', 'portraet']);

// Er mediet et portræt? Portrætrammerne (beskåret) passer kun til portrætter; vælges et segl, en
// medalje eller et våben som hovedbillede, skal det vises helt i stedet.
export function erPortraetSlags(slags: string | null | undefined): boolean {
  return PORTRAIT_SLAGS.has((slags ?? '').trim().toLowerCase());
}

const normTekst = (s: string) => s.replace(/\s+/g, ' ').trim().toLowerCase();

// Billedtekst: titel · kunstner · datering (kun de udfyldte). `dateringFakt` (den strukturerede fakt)
// vinder ALTID over den rå `datering`-kolonne (medie-metadata, Global Constraint). Bogens billedtekster
// (DAA 2018-20) bærer dateringen i titlen; står den der allerede, gentages den ikke.
export function mediaCaption(m: { titel?: string | null; kunstner?: string | null; datering?: string | null; dateringFakt?: string | null }): string {
  const datering = m.dateringFakt ?? m.datering;
  const gentaget = !!datering && !!m.titel && !!normTekst(datering) && normTekst(m.titel).includes(normTekst(datering));
  return [m.titel, m.kunstner, gentaget ? null : datering].filter(Boolean).join(' · ');
}
