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
