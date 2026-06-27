// Design tokens — direkte fra design/README.md §6 (hi-fi, endelige værdier).
// Genskab præcist: farver, fonte, radier, skygger, animationer.

export const Colors = {
  // Bordeaux (primær) — accenter, aktive states, knapper, navne-links
  bordeaux: '#881A33',
  bordeauxFillLight: '#f8ecef',
  bordeauxFillLight2: '#f4e2e6',
  // Blæk (tekst) — overskrifter, primær tekst; også mørke kort
  ink: '#221f1a',
  // Tekst sekundær
  textSecondary: '#3d382f',
  textSecondary2: '#6f675b',
  // Tekst dæmpet — mono-labels, årstal
  textMuted: '#9a8f78',
  textMuted2: '#a99f8c',
  textMuted3: '#b0a691',
  // Guld — kickers, "fælles ane", dekorativ
  gold: '#b9a06a',
  goldLight: '#e7c98f',
  // Papir
  paperBg: '#f4efe6',
  paperCard: '#fbf8f1',
  // Beige — sekundære kort, badges, segment-spor
  beige: '#efe7d7',
  beige2: '#ece4d6',
  beige3: '#e6ddcc',
  // Sandkasse-bg (uden for telefon)
  sandbox: '#e7e3da',
  // Fejl/slet — bordeaux-rød (handoff §Design tokens)
  danger: '#8a2b2b',
} as const;

// Ramme/separator-farver — rgba(34,31,26,.08–.14)
export const Border = {
  faint: 'rgba(34,31,26,0.08)',
  light: 'rgba(34,31,26,0.10)',
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
export const Radius = {
  field: 11, // felter/knapper 9–14
  card: 14, // kort 11–16
  badge: 8, // badges 7–9
  chip: 18, // chips/piller 16–20
  sheet: 22, // bottom sheet top-hjørner
  round: 9999, // runde avatarer 50%
} as const;

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
