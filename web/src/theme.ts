// Delte farve-/font-tokens for publikums-følgesvenden (Folgesvend.tsx + dens komponentfiler).
// Udtrukket fra Folgesvend.tsx så nye komponenter (BookmarksView, SlaegtPicker) kan importere
// samme tokens uden cirkulær import (Folgesvend → komponent → Folgesvend).
export const T = {
  pageBg: '#ece6da', paper: '#fbf8f1', panel: '#f4efe6', beige: '#ece4d6',
  ink: '#221f1a', bordeaux: '#881A33', gold: '#b9a06a', goldLight: '#e7c98f',
  muted: '#6f675b', muted2: '#9a8f78', muted3: '#a99f8c', cream: '#cabfa9',
  serif: "'Cormorant Garamond',serif", sans: "'Hanken Grotesk',sans-serif", mono: "'JetBrains Mono',monospace",
};
