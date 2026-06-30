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

## Interaktionsmodel: dobbelt aktiv handling (NameDrop-stil)

**Bærende princip:** opdagelse sker KUN når *begge* brugere samtidig har sat app'en i
"mød en slægtning"-tilstand og holder telefonerne tæt sammen — svarende til iPhones
NameDrop (kontakt-udveksling kræver to telefoner tæt på hinanden + begges aktive valg).
Aldrig passiv baggrunds-søgning.

Konkret rendezvous-flow:
1. Begge åbner "Mød en slægtning" → app'en lytter/annoncerer i et kort, tidsafgrænset
   vindue (fx 30 sek), tydeligt signaleret i UI ("søger i nærheden …").
2. Kun enheder der *samtidig* er i dette vindue OG fysisk tæt på (nær-felt: NFC-tap,
   QR, eller kort-rækkevidde-BLE/RSSI-tærskel) matcher — ikke alt der scanner i rummet.
3. Match → begge ser en bekræftelses-prompt med modpartens *navn* (ikke fuld profil) →
   først ved gensidigt "ja" beregnes og vises slægtskabet.
4. Vinduet lukker af sig selv; intet annonceres bagefter.

Dette eliminerer stort set den passive-udsendelse-bekymring: der er intet at opsnappe
udenfor de få sekunder hvor begge bevidst har valgt at mødes.

## Privatliv / GDPR er det styrende krav

Projektet er *"GDPR indbygget"* og handler om **nulevende**. Passiv udsendelse af "jeg er
person X i Reventlow-træet" til alle der scanner i nærheden, strider mod privatlivs-
invarianten. Design SKAL være samtykke-først:

1. **Dobbelt aktiv handling:** kun match når begge er i mød-vinduet samtidig og fysisk
   tæt på (se interaktionsmodellen ovenfor); identitet afsløres først ved gensidigt "ja".
   Ingen passiv baggrunds-udsendelse af hvem man er.
2. **Efemere id'er:** roterende tokens i æteren, aldrig fast person-id i klartekst.
3. **Privatlivs-bevarende handshake (ønsket):** udveksl kun *hashede ane-fingeraftryk*
   (fx Bloom-filter over ane-id'er). Begge kan da udlede "vi deler en ane i 3. led" UDEN
   at afsløre hele stamtræet eller den levendes fulde identitet. De afdøde aner er fælles
   kendt viden i app'en; det følsomme er den levendes selv-udpegning — den behøver ikke
   sendes for at beregne slægtskabet.

## Faser

1. **Fase 1 — QR/mødekode-MVP.** Telefon A viser QR (eller 6-cifret kode), telefon B
   scanner → gensidigt samtykke → `computeRelationship` → resultat-kort. Er i sig selv
   den reneste "dobbelt aktiv handling" (begge skal gøre noget). Cross-platform trivielt,
   ingen entitlements, virker offline. Genbruger finderen 1:1.
2. **Fase 2 — BLE nær-felt** i et kort mød-vindue (RSSI-tærskel ⇒ kun helt tæt på),
   roterende efemere id'er + gensidig opt-in (kræver dev-build). Automatiserer trin 1's
   håndtryk uden QR, men beholder dobbelt-aktiv-princippet.
3. **Fase 3 — UWB-retning** ("din slægtning står derovre") som stævne-feature.

## Afhængigheder

- Slægtskabsfinderen færdig (bilineal, multi-linje) — under arbejde.
- `daa_me_id` selv-udpegning findes (issue #4).
- Fase 2+ kræver Expo dev-build (jf. `mobile/AGENTS.md`: verificér mod Expo 56-docs).
