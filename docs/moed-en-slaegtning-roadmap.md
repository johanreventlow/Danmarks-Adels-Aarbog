# Roadmap: "Mød en slægtning" — telefon-til-telefon slægtskab ved fysisk møde

> Status: **idé / roadmap** (2026-06-30). Ingen kode endnu. Beslutning: hold som
> follow-up; gør slægtskabsfinderen (`mobile/src/data/relationship.ts`) færdig først.

## Idé

To medlemmer mødes fysisk (slægtsstævne, reception). Hver har app'en og har angivet
sin plads i stamtræet (`daa_me_id`, jf. issue #4). Telefonerne udveksler identitet og
beregner med det samme: *"I er 3. grads fætre — fælles ane Conrad Reventlow."*

## Nøgleindsigt: genealogien er allerede løst

Beregningen er **præcis** `computeRelationship(model, A, B)` — samme bilineale multi-linje-
finder vi bygger nu. Træet er cachet på enheden, så det kan køre **offline** (vigtigt ved
et stævne med dårligt signal). Funktionen kræver **ingen** ny slægtskabs-logik — kun et
transport- + samtykke-lag ovenpå. Den ene telefon skal bare lære den andens person-id.

## Den svære del er nærheds-transport (ikke genealogi)

| Metode | Cross-platform iOS↔Android | Baggrund | Expo | Rolle |
|---|---|---|---|---|
| QR / mødekode / NFC-tap | Trivielt | aktiv handling | Let (expo-camera) | **MVP** |
| BLE (GATT) | Ja, men fiklet | iOS begrænser baggrunds-annoncering hårdt | Dev-build + config-plugin (ikke Expo Go) | Fase 2 |
| Apple Nearby Interaction / Google Nearby | Nej (platform-siloer) | Bedre | Native modul | Niche |
| UWB (U1-chip: afstand + retning) | Mest iPhone | God | Native | "Wow"-gimmick |

Ægte *passiv* baggrunds-genkendelse ("telefonerne ser hinanden af sig selv") er dyrest —
især iOS-baggrunds-BLE af et custom-id. BLE GATT er laveste cross-platform fællesnævner.

## Privatliv / GDPR er det styrende krav

Projektet er *"GDPR indbygget"* og handler om **nulevende**. Passiv udsendelse af "jeg er
person X i Reventlow-træet" til alle der scanner i nærheden, strider mod privatlivs-
invarianten. Design SKAL være samtykke-først:

1. **Gensidig opt-in:** identitet afsløres først når *begge* aktivt trykker "forbind".
   Ingen passiv baggrunds-udsendelse af hvem man er.
2. **Efemere id'er:** roterende tokens i æteren, aldrig fast person-id i klartekst.
3. **Privatlivs-bevarende handshake (ønsket):** udveksl kun *hashede ane-fingeraftryk*
   (fx Bloom-filter over ane-id'er). Begge kan da udlede "vi deler en ane i 3. led" UDEN
   at afsløre hele stamtræet eller den levendes fulde identitet. De afdøde aner er fælles
   kendt viden i app'en; det følsomme er den levendes selv-udpegning — den behøver ikke
   sendes for at beregne slægtskabet.

## Faser

1. **Fase 1 — QR/mødekode-MVP.** Telefon A viser QR (eller 6-cifret kode), telefon B
   scanner → gensidigt samtykke → `computeRelationship` → resultat-kort. Cross-platform
   trivielt, ingen entitlements, virker offline. Genbruger finderen 1:1.
2. **Fase 2 — BLE-nærhed** med roterende efemere id'er + gensidig opt-in (kræver dev-build).
3. **Fase 3 — UWB-retning** ("din slægtning står derovre") som stævne-feature.

## Afhængigheder

- Slægtskabsfinderen færdig (bilineal, multi-linje) — under arbejde.
- `daa_me_id` selv-udpegning findes (issue #4).
- Fase 2+ kræver Expo dev-build (jf. `mobile/AGENTS.md`: verificér mod Expo 56-docs).
