# Prompt — heraldisk lag + logoovergang (mockup-fase)

> Til **Claude Design** (Anthropic). **Kør den på Fable** til denne mockup-fase: Fables
> forspring er størst netop på UI-design, den læser intention med mindre nudging og fanger
> design-huller. Gem Opus til den senere, mere mekaniske port til `web/`.
>
> **Inden du prompter:** lad Claude Design onboarde på dette projekt — peg den mod repoet,
> eller som minimum `web/src/theme.ts` (farve-/font-tokens) og `web/src/Folgesvend.tsx`
> (header, megamenu, slægt-chip), så den bygger design-systemet af mine *rigtige* værdier.
> Læg derefter dine våben-billeder ved (se "Assets" nederst) og kopiér prompten under linjen.

## Token-disciplin (Fable brænder ~2× — hold sessionen indhegnet)

Denne note er *ikke* en del af prompten — kopiér den ikke ind. Den er huskeliste før du åbner Fable.

- **Timing:** Fable er inkluderet uden ekstra betaling på egnede planer indtil **19. juli 2026**
  (op til ~50% af ugentlig grænse) — lav helst design-runden inden da. Tjek dit eget forbrug på
  konto-siden; plan-mekanik ændrer sig.
- **Fable kun til genereringen.** Prompten er allerede skrevet billigt (uden for Fable). Planlægning,
  porteringen til `web/` og al almindelig snak → Opus/Sonnet, ikke Fable.
- **Færre, bedre runder = den største besparelse.** Hver tur genbehandler hele den voksende kontekst
  til 2×. Den detaljerede én-shot-prompt er netop lavet for at ramme i 1–2 runder frem for 6–8.
- **Slidere/direkte redigering > re-prompt.** Juster artifact'en med Claude Designs slidere, direkte
  edits og kommentarer i stedet for "lav det hele om" — det undgår fuld regenerering.
- **Hold tråden kort og enkelt-formålet.** Pivotér du væk fra heraldik: start en frisk tråd frem for
  at slæbe en stor kontekst med.
- **Skift kun til Fable ved selve genereringen.** Lad onboarding (kodelæsning) og trivielle tweaks
  køre på den billigere default hvis Claude Design tillader model-valg pr. handling.

---

Du er UI-designer for **Danmarks Adels Aarbog — digital følgesvend**, en webapp der er et
levende, søgbart *supplement* til det trykte adelsårbog (ikke en konkurrent). Kernemissionen er
"er vi i familie?" — slægtskabssøgning. Denne PoC dækker familien **Reventlow** (~922 personer).
Tonen er et fornemt, varmt bogværk: roligt, tillidsvækkende, aldrig gimmicky eller "heraldik-kitsch".

Jeg vil have en **selvstændig, interaktiv HTML-mockup (Artifact)** — ikke produktionskode. Den skal
lade mig *se og sammenligne* et nyt heraldisk lag i slægtsvisningen samt en forbedret logoovergang.
Jeg porter selv det valgte design ind i den rigtige kodebase bagefter.

## Visuelt sprog (skal matche det du læste fra `theme.ts` under onboarding)

Disse tokens er som de står i koden — brug dem som facit; hvis din onboarding gav afvigende
værdier, så er det koden der gælder. Nye fonte eller fremmede accenter må ikke introduceres.

Farver: baggrund `#ece6da`, papir `#fbf8f1`, panel `#f4efe6`, blæk `#221f1a`,
bordeaux `#881A33` (accent/aktiv), guld `#b9a06a`, lys guld `#e7c98f`,
dæmpede `#6f675b`/`#9a8f78`/`#a99f8c`, creme `#cabfa9`.
Skrift: overskrifter serif `Cormorant Garamond`; brødtekst/UI sans `Hanken Grotesk`;
små versal-labels mono `JetBrains Mono` med bred letter-spacing. Blødt papir, tynde
`rgba(34,31,26,.1)`-streger, diskrete skygger. Theme-aware (lyst som udgangspunkt; hvis du laver
mørk variant skal begge se bevidste ud).

## Det heraldiske koncept (vigtigt — respektér lagdelingen)

- **DAF-logoet** (en heraldisk hjelm — jeg vedhæfter det) er *foreningens/husets* identitet.
  Det skal **bevares** og blive i navigationsbjælken og megamenuen. Rør det ikke som koncept.
- **Slægtsvåbnene** er et *andet, nyt* lag: hver slægt har et **grundvåben** (fx det reventlowske),
  og enkelte linjer har desuden et **grevelig våben** (grevelige linjer). De skal ind i selve
  slægtsvisningen — ikke erstatte hjelmelogoet.
- Appen skal *vise* usikkerhed og nuance, ikke skjule den — heraldikken må gerne føles autentisk og
  kildebunden, ikke som dekorative klistermærker.

## Undersøg også: våbnenes stiludtryk (vigtigt)

Jeg er ikke sikker på om **fuldfarve-heraldik** sidder rigtigt i det rolige, varme bogværk-udtryk.
Undersøg og vis mig side om side:

- **Fuldfarve** — våbnene som de er.
- **Monokrom / tonet i design-paletten** — fx en gråskala- eller ét-tone-behandling farvet i de
  varme grund-/beige-toner (`#cabfa9` creme, `#b9a06a` guld, `#221f1a` blæk, papir `#fbf8f1`), evt.
  som en diskret prægning/linjegravering der ligner et bogtrykt våben frem for et farvefoto.

Vurdér selv hvilken behandling der binder bedst sammen med logoet, typografien og paletten — og
**anbefal** én, med kort begrundelse. Det er helt legitimt at konkludere at fuldfarve kun bruges ét
sted (fx heroen) mens de mindre forekomster (chip, grevelig-markør) er tonede — foreslå gerne den
slags hybrid, hvis den fungerer bedst.

## Det mockup'en skal vise

Byg én sammenhængende Reventlow-slægtsside (header + et repræsentativt indhold nedenunder) med:

1. **Header-chip med grundvåben.** I dag er der en chip øverst til højre med et rundt "R"-monogram +
   teksten "Reventlow ▾". Erstat monogrammet med det faktiske **grundvåben** i en lille, elegant
   indfatning. Skal læse rent i lille størrelse.

2. **Slægts-hero / intro.** Når man lander på slægten: en dedikeret, større præsentation af
   grundvåbnet med slægtsnavn og en kort linje. Fornem, ikke pralende — tænk titelblad i en bog.

3. **Grevelig markør på personer.** I person-/kolonnevisningen: et lille **grevelig-våben-mærke** ud
   for personer eller grene der hører til en grevelig linje, så man visuelt kan se hvornår man
   bevæger sig ind i en grevelig gren. Diskret, men aflæseligt.

4. **Forbedret logoovergang i megamenuen.** I dag sidder hjelmelogoet lille (~40px) i den kollapsede
   bjælke og *crossfader* (opacity) over til en større kopi (~64px) der skalerer `.62 → 1`, når en
   megamenu folder ud på hover. Det føles som to kopier der blinker forbi hinanden. Lav det om til at
   føles som **ét logo der vokser kontinuerligt frem** fra bjælke-positionen til hero-positionen i
   det udfoldede panel — én sammenhængende bevægelse, ingen synlig crossfade/dobbelt-logo. Vis
   overgangen som noget jeg kan trigge (hover/klik) i mockup'en.

## Det åbne valg — vis TO varianter jeg kan sammenligne

Jeg har ikke besluttet hvordan grundvåben og grevelig våben skal spille sammen. Byg en **toggle**
(eller to synlige varianter side om side) så jeg kan sammenligne:

- **Variant A — Hus + linje:** grundvåbnet bliver i header-chippen som slægtens faste "hus"-identitet,
  OG det grevelige våben vises *også* når man er på en grevelig linje (fx i heroen + som markør), så
  lagdelingen er synlig på én gang.
- **Variant B — Grundvåben fast, grevelig kontekstuelt:** grundvåbnet er altid i header; det grevelige
  våben dukker *kun* op kontekstuelt dybere i visningen (hero/person) når man faktisk er på en grevelig
  linje — chippen skifter aldrig.

Gør forskellen mærkbar, ikke kosmetisk, så jeg kan træffe et reelt valg.

## Leverance & rammer

- Én selvstændig HTML-Artifact, al CSS/JS inline, ingen eksterne kald. Brug mine vedhæftede
  våben-billeder som `data:`-URI'er (eller pæne placeholder-våben hvis et mangler, tydeligt markeret).
- Responsiv; vandret indhold (person-kolonner) må scrolle i egen container, aldrig hele siden.
- Bliv inden for det etablerede typografiske/farve-system — ingen nye fonte eller fremmede accenter.
- **Undgå:** clutter, for mange våben på skærmen på én gang, wappen-som-emoji-følelse, animationer der
  gør det legetøjsagtigt. Fornem ro > effekt.
- Kommentér kort i koden hvor de fire elementer og de to varianter sidder, så jeg let kan pege på hvad
  jeg vil justere.

Start med at bygge mockup'en. Bagefter itererer vi på detaljer.

## Assets (vedhæftes til samtalen)

- `daf-logo.png` — det eksisterende DAF-hjelmelogo (bevares).
- Reventlow **grundvåben** (PNG) — [vedhæft].
- Et eller flere **grevelige våben** for grevelige linjer (PNG) — [vedhæft].

Alt vedhæftes som **PNG** (høj opløsning). Til den monokrome/tonede behandling ovenfor:
approksimér gerne udtrykket på PNG'en her i mockup'en (fx afmætning + tonet overlay), så jeg kan
*se* om retningen virker — det behøver ikke være pixel-perfekt. Jeg har våbnene i **EPS-vektor** og
laver den endelige, rene gen-farvning i produktionskoden bagefter; mockup'en skal kun afgøre om
udtrykket er rigtigt.
