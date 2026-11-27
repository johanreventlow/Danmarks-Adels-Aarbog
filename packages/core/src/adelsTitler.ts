// Den lukkede liste over adelstitler (flyttet hertil fra web/mobil `data/presens.ts`, 2026-11-26, så præsenslisten og
// bogens formelle navneform deler den). Listen er identisk med SQL-sidens adelsforrang i visningscachen
// (`schema.sql`, »titel: adelstitlen«); `web/src/data/__tests__/adelstitler.sql-paritet.test.ts` låser de to sammen.
// En titel uden for listen (»Kammerherre«, »Premierløjtnant i vesttyske Pionier Bataillons reserve«, »Grevinde (?)«)
// er ingen adelstitel.
export const ADELS_TITLER = new Set([
  'greve', 'grevinde', 'komtesse', 'comtesse', 'lensgreve', 'lensgrevinde',
  'baron', 'baronesse', 'friherre', 'friherreinde', 'rigsgreve', 'rigsgrevinde',
]);

export const erAdelsTitel = (s: string): boolean => ADELS_TITLER.has(s.trim().toLowerCase());

// Køns-bøjning af adelstitler — kun mands-formerne er nøgler: »komtesse« (ugift datter) er aldrig noget en kvinde
// »gifter sig til« via ægtefællen. Flyttet hertil fra web/mobil `data/presens.ts` (2026-11-27).
const FEMININ_TITEL: Record<string, string> = {
  greve: 'Grevinde', lensgreve: 'Lensgrevinde', baron: 'Baronesse',
  friherre: 'Friherreinde', rigsgreve: 'Rigsgrevinde',
};
export const feminiserTitel = (mandsTitel: string): string | null => FEMININ_TITEL[mandsTitel.trim().toLowerCase()] ?? null;

// Rangfølge (højere = højere rang): komtesse = comtesse < friherreinde = baronesse < grevinde < lensgrevinde <
// rigsgrevinde; friherre = baron < greve < lensgreve < rigsgreve. Spec 2026-11-27, »Rangfølge«.
export const ADELS_RANG: Record<string, number> = {
  komtesse: 0, comtesse: 0,
  friherreinde: 1, baronesse: 1, friherre: 1, baron: 1,
  grevinde: 2, greve: 2,
  lensgrevinde: 3, lensgreve: 3,
  rigsgrevinde: 4, rigsgreve: 4,
};
export const adelsRang = (titel: string): number => ADELS_RANG[titel.trim().toLowerCase()] ?? -1;
