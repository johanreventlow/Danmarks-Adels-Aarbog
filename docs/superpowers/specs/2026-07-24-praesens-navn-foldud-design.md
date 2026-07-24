# Præsensliste: fold-ud narrativ ved navneklik — design

**Status:** Godkendt af bruger 2026-07-24, klar til plan.

## Baggrund

I Præsenslisten (`web/src/components/PresensView.tsx`) navigerer et klik på et
navn i dag direkte væk fra listen til personens fulde profil i stamtræet
(`onPick` → `onPickPerson` → `navigateTree`, sat op i `Folgesvend.tsx`). Ved
gennemgang af en lang linje ("Farfars farbror", 4-5 led dyb) var det brugerens
ønske i stedet at kunne folde en kort biografisk tekst ud under rækken uden at
forlade listen, med et separat link videre til den fulde profil.

## Interaktion

- Klik på et navn (personens eget **og** en ægtefælles navn, "· g. m. ...")
  veksler en fold-ud-boks under rækken — erstatter dagens direkte navigation
  for navneklik i Præsenslisten specifikt.
- Et lille chevron (▸ lukket / ▾ åben) ved siden af navnet signalerer at det
  er foldbart.
- Flere rækker kan være foldet ud samtidig og uafhængigt af hinanden — ingen
  accordion-lukning af andre rækker.
- Årstals-spannet (`aarAf`) er fortsat ikke selv et klik-mål — uændret.
- Cross-reference-noten ("↗ vist andetsteds i denne gren") og
  forbindelsesled-styling (kursiv/dæmpet) er uændrede; disse rækker får samme
  fold-ud-behandling som alle andre.

## Indhold i fold-ud-boksen

1. Personens bedste tilgængelige narrative tekst, hentet via den eksisterende
   `fetchPersonDetail(id, memberIds)` (`web/src/data/public.ts:143`) — samme
   udvælgelses- og samme_som-folde-logik som den fulde profil bruger
   (`PersonDetailData.bio`). `memberIds` udledes som i `Folgesvend.tsx:180`:
   `model.byId[id]?.mergedFrom?.map((m) => m.personId)`.
2. Teksten rendres med den eksisterende `NarrativRenderer`
   (`web/src/components/NarrativRenderer.tsx`) — samme typografi og samme
   klikbare person-links inde i selve bio-teksten som andre steder i appen
   (Om-siden, Godser, detaljepanelet). Klik på et navn *inde i* bio-teksten
   navigerer direkte til profilen via `onPickPerson` — uændret, etableret
   mekanik, ikke en del af dette fold-ud-lag.
3. Har personen ingen offentlig narrativ (`bio === ''`), vises i stedet en
   kort, dæmpet placeholder-tekst ("Ingen biografi registreret") — linket
   nedenfor vises stadig, så affordancen er ens for alle navne uanset om der
   findes en bio.
4. Nederst i boksen: et lille "→ Se fuld profil"-link. Dette link er
   Præsenslistens eneste vej videre til stamtræ-visningen nu (kalder
   `onPickPerson`, dvs. samme `navigateTree` som før).

## Data/loading

- Første klik på en rækkes navn udløser `fetchPersonDetail`; mens den er
  undervejs vises en kort "Henter…"-tekst i boksens sted.
- Resultatet (bio-teksten) caches i et lokalt state-map nøglet på person-id —
  gentagne luk/genåbn af samme række genhenter ikke.
- Fejl fra hentningen behandles som tomt resultat (samme mønster som
  `Folgesvend.tsx:181`'s `.catch(() => setDetail({...tom...}))`) — viser
  placeholder-teksten fra punkt 3, aldrig en fejlbesked i selve UI'en.

## State-placering og prop-threading

- To nye state-stykker liftes til `PresensView` (samme sted som `fokusId`
  allerede bor):
  - `aabne: Set<string>` — hvilke person-id'er er foldet ud.
  - `bioCache: Map<string, 'henter' | string>` — hentet/undervejs bio-tekst
    pr. id (`string` er den hentede tekst, evt. tom streng for "ingen bio").
- Disse trådes ned gennem `PresensLinjeSektion → PresensGrenSektion →
  renderNode` som to nye props (`erAaben: (id) => boolean` og
  `onToggle: (id) => void`), efter samme mønster som `onPick`/`navnAf`
  allerede bruges i disse tre komponenter.
- `renderNode`s eksisterende `onClick={() => onPick(n.id)}` på navne-spannet
  ændres til `onClick={() => onToggle(n.id)}`; selve navigationen flytter til
  det nye "Se fuld profil"-link inde i fold-ud-boksen, som fortsat kalder
  `onPick(n.id)` (dvs. `onPickPerson`/`navigateTree`, uændret kontrakt).
- Ægtefælle-spannet (linje ~64 i dagens `PresensView.tsx`) får samme
  `onToggle`/fold-ud-behandling som personens eget navn, med sit eget
  `erAaben`/bio-opslag nøglet på ægtefællens id.

## Visuelt

- Boksen ligger under rækken i samme venstre-indrykning som selve rækken
  (dvs. samme `marginLeft` som rækkens `<div>`, ikke yderligere indrykket).
- Tynd venstre-kant i samme guldtone som gren-linjernes border
  (`rgba(185,160,106,.45)`), lidt indvendig padding.
- Bio-teksten arver `NarrativRenderer`s egen typografi (samme serif/link-stil
  som andre steder); boksens egen ramme tilføjer ikke ny skriftart.
- "Se fuld profil"-linket sættes i `T.bordeaux` (samme farve som appens
  øvrige links), med en lille pil-indikator ("→").
- Ingen animation ud over instant vis/skjul — i tråd med appens øvrige
  stort set transition-fri stil.

## Fejlhåndtering

- Netværksfejl ved `fetchPersonDetail` → tom bio → placeholder-tekst (se
  Data/loading ovenfor). Ingen synlig fejlbesked, ingen retry-knap (matcher
  appens eksisterende `.catch(() => ...tomt...)`-mønster for al
  "ikke-kritisk pynt"-hentning i `PresensView.tsx`).

## Test

- `PresensView.test.tsx` udvides med:
  - Klik på et navn folder boksen ud (viser hentet/mocket bio-tekst); klik
    igen folder den sammen.
  - To forskellige rækker kan være foldet ud samtidig (uafhængige `Set`-
    medlemmer).
  - Ægtefælle-navnets klik folder ægtefællens egen boks ud, ikke personens.
  - Tom bio → placeholder-teksten vises, linket er der stadig.
  - "Se fuld profil"-linket kalder `onPick` med det korrekte id (ikke
    `onToggle`).
- Ingen ændring i `presens.ts`/`presensListe.ts`-testene — denne feature
  rører kun rendering/state i `PresensView.tsx`, ikke databerigningslaget.

## Ikke i scope

- `NarrativRenderer`s egen indlejrede person-links (inde i selve bio-teksten)
  ændres ikke — de navigerer fortsat direkte, uændret kontrakt.
- Ingen ændring af `DetailPanel`, `AboutView`, `EstatesView` eller andre
  steder `fetchPersonDetail`/`NarrativRenderer` allerede bruges.
- Ingen portræt/embede/gods-visning i fold-ud-boksen — kun narrativ + link
  (matcher brugerens eksplicitte ønske; `PersonDetailData`s øvrige felter
  hentes teknisk med i samme kald, men bruges ikke her).
