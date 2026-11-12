// Design tokens. Farverne kommer fra den fælles @daa/theme (designsystemets tokens.json,
// webredesign fase 1); fonte, radier, skygger og animationer står herunder.
import { color, radius } from '@daa/theme';

// De gamle navne (paperBg, paperCard, beige*, textSecondary*, textMuted*, liveRoed, konklusion*,
// konfliktFlade, bordeauxFillLight) er fjernet; se @daa/theme for reglerne (fx gold kun som pynt,
// goldInk til etiketter). Uden token endnu, bevaret uændret: bordeauxFillLight2, goldLight som
// flade, sandbox.
export const Colors = {
  ...color,
  bordeauxFillLight2: '#f4e2e6',
  goldLight: '#e7c98f',
  // Sandkasse-bg (uden for telefon)
  sandbox: '#e7e3da',
} as const;

// Ramme/separator-farver — rgba(34,31,26,.08–.14)
export const Border = {
  faint: 'rgba(34,31,26,0.08)',
  light: color.line,
  medium: 'rgba(34,31,26,0.14)',
} as const;

// Fonte — bundles via @expo-google-fonts. Nøgler matcher useFonts-mapping (se theme/fonts.ts).
export const Fonts = {
  // Cormorant Garamond — serif, overskrifter/navne
  serif: 'CormorantGaramond_500Medium',
  serifSemi: 'CormorantGaramond_600SemiBold',
  serifItalic: 'CormorantGaramond_500Medium_Italic',
  serifSemiItalic: 'CormorantGaramond_600SemiBold_Italic',
  // Hanken Grotesk — sans, brødtekst/UI
  sans: 'HankenGrotesk_400Regular',
  sansMedium: 'HankenGrotesk_500Medium',
  sansSemi: 'HankenGrotesk_600SemiBold',
  sansBold: 'HankenGrotesk_700Bold',
  // JetBrains Mono — kicker/labels/årstal
  mono: 'JetBrainsMono_400Regular',
  monoMedium: 'JetBrainsMono_500Medium',
} as const;

// Radier — README §6
// Radier fra @daa/theme (samme værdier som før): field 11, card 14, badge 8, chip 18, sheet 22, round 9999.
export const Radius = radius;

// Skygger — README §6
export const Shadow = {
  card: {
    shadowColor: '#221f1a',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.04,
    shadowRadius: 2,
    elevation: 1,
  },
  cardSelected: {
    shadowColor: '#881A33',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.14,
    shadowRadius: 14,
    elevation: 4,
  },
} as const;

// Animationer — README §6
export const Motion = {
  // daaScreen — skærm-skift: translateY(9px)→0, .44s
  screenDuration: 440,
  screenTranslate: 9,
  // daaRise — forside-elementer rejser sig: translateY(13px)→0, .62s, delays .04/.10/.16/.22/.28
  riseDuration: 620,
  riseTranslate: 13,
  riseDelays: [40, 100, 160, 220, 280],
  // Variant C snap (senere)
  snapDuration: 420,
  haptic: 6,
} as const;

// Mono letter-spacing (§6: .1–.22em). RN bruger absolutte px — ~0.1em ≈ fontSize*0.1.
export const monoSpacing = (fontSize: number, em = 0.16) => fontSize * em;

// Typografisk løft (2026-07-31): prototypernes px-værdier lå 20–30 % under OS-normal
// læsestørrelse. Monoton mapping — alt ≤16 løftes ét trin, store overskrifter urørte —
// så hierarkiet mellem mono/sans/serif bevares. Ét sted at skrue: brugt af Typography-
// primitiverne, så call-sites stadig angiver prototypens størrelser.
export const scaleType = (s: number) => (s <= 16 ? s + 1 : s);
