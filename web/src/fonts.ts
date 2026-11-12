// Skrifterne serveres fra vores egen server, ikke Google Fonts (webredesign fase 1). Vite lægger
// woff2-filerne i dist. Samme snit som før: Cormorant Garamond 500/600 i ret og kursiv,
// Hanken Grotesk 400–700, JetBrains Mono 400/500 — mangler et snit, tegner browseren falsk
// fed eller kursiv. Hver fil dækker alle tegnsæt med unicode-range, så browseren kun henter dem,
// siden bruger (latin-ext er med, så navne med fx ł eller č ikke skifter skrift midt i ordet).
import '@fontsource/cormorant-garamond/500.css';
import '@fontsource/cormorant-garamond/600.css';
import '@fontsource/cormorant-garamond/500-italic.css';
import '@fontsource/cormorant-garamond/600-italic.css';
import '@fontsource/hanken-grotesk/400.css';
import '@fontsource/hanken-grotesk/500.css';
import '@fontsource/hanken-grotesk/600.css';
import '@fontsource/hanken-grotesk/700.css';
import '@fontsource/jetbrains-mono/400.css';
import '@fontsource/jetbrains-mono/500.css';
