// Webbens farver og skrifter, læst fra den fælles @daa/theme (designsystemets tokens.json).
// De gamle navne (pageBg, paper, panel, beige, muted/muted2/muted3, cream, goldLight) er
// fjernet: de dækkede flere roller, og designsystemet skelner fx mellem dæmpet tekst
// (inkMuted) og guld som pynt (gold) eller etiket (goldInk). Se @daa/theme for reglerne.
import { color, fontFamily } from '@daa/theme';

export const T = {
  ...color,
  serif: fontFamily.serif, sans: fontFamily.sans, mono: fontFamily.mono,
};
