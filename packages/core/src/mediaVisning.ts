// Delt visning af medier (web + mobil): hvilke slags er portrætter, og billedtekstens formel.

// Billedtypen (`media.slags`) beskriver MOTIVET — hvad billedet viser; teknikken er medie-faktummet `teknik`
// (projektejeren 2026-11-25, spec 2026-11-25-media-slags-ordliste-design.md). Samme seks koder som `vocab`
// (scheme `media_slags`), som databasens trigger håndhæver; db-verify.sql låser rækkerne til denne liste.
// Et nyt motiv = en vocab-række + en linje her.
export const MEDIA_SLAGS: ReadonlyArray<{ code: string; label: string }> = [
  { code: 'portræt', label: 'Portræt' },
  { code: 'våben', label: 'Våben' },
  { code: 'segl', label: 'Segl' },
  { code: 'medalje', label: 'Medalje' },
  { code: 'gods', label: 'Gods' },
  { code: 'dokument', label: 'Dokument' },
];
export const MEDIA_SLAGS_STANDARD = 'portræt';

// Label til visning; en ukendt kode vises som den er.
export function mediaSlagsLabel(slags: string | null | undefined): string {
  return MEDIA_SLAGS.find((s) => s.code === slags)?.label ?? (slags ?? '');
}

// Portræt-egnede slags (hovedbillede på personkort). Sammenlign altid normaliseret (lowercase+trim). Efter
// dataflytningen og databasens trigger (2026-11-25) findes kun motivet 'portræt'; gamle værdier oversættes i databasen.
export const PORTRAIT_SLAGS: ReadonlySet<string> = new Set(['portræt']);

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
