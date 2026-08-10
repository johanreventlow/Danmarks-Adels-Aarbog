# Overdragelse: 1939-grænsefladen — prompt til Codex

Kopiér alt under stregen ind i Codex. Den er selvstændig: den forudsætter ikke
kendskab til samtalen, hvor fladen blev bygget.

---

Du overtager arbejdet med **1939-grænsefladen** i repoet
`danmarksadelsaarbog`, worktree `.claude/worktrees/evidensbaseret-genimport`,
branch `feat/evidensbaseret-genimport`. Læs først kontrakten:
`docs/superpowers/plans/2026-08-09-graenseflade-spec.md` — den er brugergodkendt,
og §3 (brugerens beslutninger), §4 (markør-grammatik), §5 (byte-gaten), §7
(eksportformat) og §9b (sidevisning) må ikke omstødes uden at spørge.

## Hvad fladen er

Én HTML-fil, `file://`-lokal, uden netværk. Den viser hele Calamari-OCR-teksten
fra DAA 1939 (186.655 tegn, 3.939 linjer, 86 bogsider) i en `<textarea>`, én
bogside ad gangen. Skæringer mellem kildeposter står som markørlinjer i teksten;
mennesket sletter forkerte, sætter manglende, og markerer tekst der ikke hører til
nogen post. Resultatet eksporteres som `1939-graenseflade.json`.

**Formålet er dækning, ikke pynt.** Fase 1 viste at 25 % af bogteksten ikke ejes af
nogen post, og at et hul er usynligt i en flade der kun viser skæringer mellem spænd
der allerede findes.

## Ufravigelige invarianter

1. **Kildeteksten er uforanderlig.** 445 accepterede spænd peger på eksakte
   tegnintervaller i netop denne fil, og påstande overskrives aldrig. Byte-gaten
   stripper fladens egne markører og sammenligner resten byte for byte med kilden.
   Eksport er **umulig** — ikke frarådet — mens gaten er brudt.
2. **`===` er fladens, `###` er bogens.** Kildeteksten indeholder allerede 86
   `### PAGE nnnn ###`-linjer. Strip-mønstrene er eksakte og navngivne; aldrig et
   generisk `^===`-catch-all og under ingen omstændigheder `^###`. Sletter mennesket
   en kilde-`### PAGE`-linje, skal gaten fange det.
3. **Tavshed er godkendelse** for den enkelte skæring (brugerens valg). Eksporten
   registrerer derfor *ændringen* mod de 446 forudsatte, ikke en dom pr. grænse.
4. **Positioner i eksporten er tegnkoordinater i kildeteksten**, ikke i den
   markerede visning. Omregningen er implementeringens ansvar og skal testes begge
   veje.
5. **Sideidentitet er kildesiden (1-86), ikke det trykte PDF-sidetal.** To sider
   bærer begge tallet 598. Nøgles fremskridt på det trykte tal, kan to sider dele én
   plads — og kvittering for den ene får den anden til at fremstå gennemgået.
6. **Resultatet er review-/fil-GO.** Ingen materialisering, ingen database, ingen
   loader. Afløsning af accepteret evidens kræver en selvstændig, autoriseret
   operation — se `docs/decisions.md` 2026-08-08.
7. **`work/` og `work_1939_stamtavle/` indeholder PII.** Læs dem ikke ind i din
   kontekst, print ikke deres tekstindhold, commit dem aldrig. Rapportér tal.

## Byg og verificér

```bash
W=/Users/johanreventlow/TypeScript/danmarksadelsaarbog/work_1939_stamtavle
P=work/task19-1939-pilot

python3 .claude/skills/daa-extract/scripts/make_boundary_text_1939.py \
  --baseline $W/clean_1939_v2.json \
  --queue-manifest $P/review-queue-manifest-v2-run-e.json \
  --source-manifest $P/review-queue-manifest-v2-run-e.json \
  --calamari $W/full_ocr_calamari_r6_clean.txt \
  --raw $W/raw.txt \
  --anchored $P/human-anchored-candidates-v4-faerdig.json \
  [--markeringer <tidligere eksport>] \
  --out $P/<ny fil>.html
```

Skal skrive: `446 grænser · 97 huller · 61 forslag · 86 PDF-sider`.

**Tests:** `python -m pytest .claude/skills/daa-extract/scripts/test_make_boundary_text_1939.py -q`
(38 grønne). Hele skill-suiten: 1.117 grønne.

**Ægte browser (obligatorisk — jsdom fanger intet af det der gik galt):**

```bash
node .claude/skills/daa-extract/scripts/verify_boundary_text_browser.mjs \
  $P/<fil>.html $W/full_ocr_calamari_r6_clean.txt
```

28 kontroller. Playwright ligger i `web/node_modules`.

**Kontrol af et menneskes gennemgang:**

```bash
python3 .claude/skills/daa-extract/scripts/check_graenseflade_export.py \
  <eksport.json> --calamari $W/full_ocr_calamari_r6_clean.txt \
  --boundaries $P/menneskeark-graenser-v8.html --forrige <tidligere.json>
```

## Hvor arbejdet står

Mennesket har gennemgået hele bogen: **651 skæringer** (fra 446 forudsatte — 414
beholdt, 32 forkastet, 237 nye), **132 udeladelser**, 85 af 86 sider kvitteret.
Alle 68 trykte postnumre i ejerløs tekst er skåret eller udeladt. Arbejdet fortsætter
med finpudsning side for side.

Commits `7b9a27a..7c7239d` på branchen; **intet er pushet**.

## Udestående opgaver, vigtigst først

### 1. Slutmarkør på ejerløse huller

Fladen markerer kun hvor et hul **begynder** (`=== EJERLØS TEKST · N tegn ===`),
aldrig hvor det holder op. Mennesket skulle tælle 647 tegn frem i hovedet for at se
hvad det arbejdede på, og sagde direkte at det var utydeligt. Tilføj en
slutmarkør, så stykket er indrammet. Den skal indgå i strip-mønstrene (invariant 2)
og må ikke ændre nogen koordinat i eksporten.

### 2. Levende regnskab for godkendte forslag

Et forslag godkendes ved at fjerne ordet `FORSLAG?` fra markørlinjen. Den kørende
flade bogfører det som "slettet forslag + ny skæring": eksporten sagde
`forslag_godkendt: 0`, mens den *samme* fil efter gen-indlæsning siger 36. Data er
identiske; kun etiketten er forkert i den kørende flade. Ret opgørelsen, så en
in-place-godkendelse tælles som godkendt.

### 3. Vagt mod det efterladte tegn

En udeladelse der begynder ét tegn efter et linjeskift efterlader overskriftens
første bogstav som ejet tekst. Det skete **76 gange** i én gennemgang uden at nogen
opdagede det, fordi en tekstboks ikke viser omfang. Advar i fladen når en udeladelse
efterlader ét enkelt ikke-blankt tegn mellem linjestart og markeringens begyndelse.
Rettelsen af de eksisterende 76 er allerede kørt maskinelt.

### 4. Uafklaret: rapporteret forskydning ved genindlæsning

Mennesket rapporterede at en markering rykkede sig ét tegn ved genindlæsning af
HTML-filen. Det er **ikke** genskabt: tre genindlæsninger, begge tag-skrivemåder og
gen-indlæsning via `--markeringer` gav alle nul afvigelse. Enten sad fejlen i en
tidligere udgave, eller den kræver en tilstand der ikke er ramt. Betragt det som
åbent, ikke lukket.

### 5. Runde 2: ejerskab

Fladen producerer et **skæringssæt**, ikke ejerskab. Markøren siger kun "her
klippes"; hvilken post der ejer hvilket stykke, er en senere, separat flade som ikke
er designet. 101 baseline-poster ejede intet tekstspænd ved fase 1's afslutning.

## Fejlmønstre fra dette arbejde — de gentog sig

**Fravær af bevis læst som bevis på fravær.** Et signal bygget til en kendt fejl,
der aldrig fyrer, er et resultat om koden, ikke om dataene. Konkret her: to
ejerløse huller med rigtig tekst (868 og 6.330 tegn) var usynlige, fordi et hul
krævede en nabo på *begge* sider — dokumentets kanter har ingen nabo.

**En optælling er kun så god som det, den tæller.** Tre gange kaldte en kontrol
korrekt arbejde for fejl: den ledte efter en skæring *inde i* et hul (den rigtige
placering er kanten), den viste linjen *før* en skæring ved et linjeslut, og den
krævede at udeladelser flugtede med linjer (delvise markeringer er tilladt).
Verificér mod noget kilden selv siger — bogens trykte postnumre — ikke mod din egen
definition af færdig.

**Test i en rigtig browser.** Fase 1 kostede fire fejl som udelukkende en browser
fandt: uparsebar scriptblok (blank side), tom kasse læst som frikendelse, manglende
fremdrift, kontekst ud over spændets kant. Alle bestod jsdom.

**Piletaster i en `<textarea>` flytter sig efter ombrudte linjer, ikke rigtige.**
En browsertest der navigerer med `ArrowDown` måler sin egen navigation. Brug
`setSelectionRange` på en beregnet tegnposition.

**En identitet skal være entydig, ikke bare trykt.** Sidetallet 598 optræder to
gange; lokal_id blev af samme grund valgt som bogens firleddede trykte adresse frem
for et beregnet løbenummer (`docs/decisions.md` 2026-07-30).
