// Fælles designværdier for web og mobil (webredesign fase 1). Kilden er designsystemet
// »Danmarks Adels Aarbog« (Claude Design): src/tokens.json er en uændret kopi af dets
// project/tokens.json. Værdierne herunder skrives ud, så navnene er typede; testen holder dem
// lig tokens.json, så de ikke kan glide fra hinanden. Ændres et token, ændres det i
// designsystemet først og kopieres hertil.
//
// Brugsregler (designsystemets README): `gold` er kun pynt, aldrig tekst (brug `goldInk`);
// tekst på `surfaceInverse` bruger `inkOnInverse`, `inkMutedOnInverse` og `goldOnInverse`;
// status vises altid også med et ord, ikke kun med farve.

export const color = {
  surfaceGround: '#f4efe6',
  surfaceRaised: '#fbf8f1',
  surfaceSunken: '#ece4d6',
  surfaceInverse: '#221f1a',
  ink: '#221f1a',
  inkSecondary: '#3d382f',
  inkMuted: '#655d4f',
  inkOnInverse: '#fbf8f1',
  inkMutedOnInverse: '#cabfa9',
  bordeaux: '#881a33',
  bordeauxStrong: '#6d1529',
  bordeauxTint: '#f8ecef',
  onBordeaux: '#fbf8f1',
  gold: '#b9a06a',
  goldInk: '#776338',
  goldOnInverse: '#e7c98f',
  line: 'rgba(34,31,26,0.10)',
  lineStrong: 'rgba(34,31,26,0.18)',
  focus: '#881a33',
  success: '#1f5b3a',
  successTint: '#eaf3ec',
  danger: '#8a2b2b',
  dangerTint: '#f2dede',
  live: '#a8331f',
} as const;

export const fontFamily = {
  serif: '"Cormorant Garamond", "EB Garamond", Georgia, serif',
  sans: '"Hanken Grotesk", "Helvetica Neue", Arial, sans-serif',
  mono: '"JetBrains Mono", ui-monospace, Menlo, monospace',
} as const;

// Tekststile. Størrelser i px; lineHeight i px.
export const textStyle = {
  displayXl: { family: 'serif', fontSize: 40, lineHeight: 44, fontWeight: 500 },
  displayLg: { family: 'serif', fontSize: 30, lineHeight: 34, fontWeight: 600 },
  title: { family: 'serif', fontSize: 22, lineHeight: 27, fontWeight: 600 },
  name: { family: 'serif', fontSize: 19, lineHeight: 23, fontWeight: 600 },
  lead: { family: 'serif', fontSize: 17.5, lineHeight: 28, fontWeight: 500, fontStyle: 'italic' },
  body: { family: 'sans', fontSize: 15, lineHeight: 24, fontWeight: 400 },
  bodySm: { family: 'sans', fontSize: 13.5, lineHeight: 20, fontWeight: 400 },
  ui: { family: 'sans', fontSize: 14, lineHeight: 20, fontWeight: 600 },
  label: { family: 'mono', fontSize: 11, lineHeight: 14, fontWeight: 500, letterSpacing: '0.16em' },
  data: { family: 'mono', fontSize: 12, lineHeight: 16, fontWeight: 400 },
} as const;

// Afstande i px: space[1] … space[8].
export const space = { 1: 4, 2: 8, 3: 12, 4: 16, 5: 24, 6: 32, 7: 48, 8: 64 } as const;

// Radier i px.
export const radius = { badge: 8, field: 11, card: 14, chip: 18, sheet: 22, round: 9999 } as const;

// Skygger som CSS-værdier (web). Mobil oversætter dem til React Natives shadow-felter.
export const shadow = {
  card: '0 1px 2px rgba(34,31,26,0.04)',
  selected: '0 4px 14px rgba(136,26,51,0.14)',
  popover: '0 26px 46px rgba(20,17,13,0.14)',
} as const;

export type ColorToken = keyof typeof color;
