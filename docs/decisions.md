# Beslutninger

Kun ikke-oplagte arkitektur-/design-valg. Detaljer i changelog + memory.

## BESLUTTET: model 2 — lagdelt styringsmodel for evidensbaseret genimport (2026-08-25)

[Designspecifikationen](superpowers/specs/2026-08-25-evidensbaseret-genimport-styringsgrundlag-design.md)
vedtages som model 2: fire autoritative dokumenter med adskilte roller og
myndighed. [Visionen](evidensbaseret-genimport/vision.md) fastlægger det stabile
værdigrundlag, [roadmapet](evidensbaseret-genimport/roadmap.md) den bindende
prioritering, [målarkitekturen](evidensbaseret-genimport/teknisk-maalarkitektur.md)
den stabile tekniske retning og [status](evidensbaseret-genimport/status.md) et
dateret, driftfølsomt snapshot. Status er ikke kilde til stabile værdier eller
til tekniske detaljer, som levende kode og schema har ændret.

Vision og målarkitektur må kun ændres ved projektejerens udtrykkelige
beslutning. Roadmaprækkefølgen må kun ændres gennem en begrundet
beslutningspost. Roadmapet har ét aktivt programmål, og nye planer inden for
scope skal opfylde alle seks adgangskrav i roadmapet.

CI-håndhævelse er bevidst udskudt, indtil den manuelle styringsmodel er
afprøvet. Beslutningen giver ingen produktions-GO og ændrer ikke andre
projektspors styring.

## C3 apply: fire ikke-oplagte valg i apply-kontrakten (2026-08-22)

Truffet under revisionen efter Codex sols adversarial review. Alle fire kunne
være gået den anden vej, og begrundelsen er ikke synlig af koden alene.

**1. Tekstgodkendelsen bindes til `text_bundle_sha256`, ikke til manifestet.**
Finalmanifestet binder databasenavn og system identifier, så et prod-bundet
manifest afvises mod rehearsal-basen og omvendt — der er nødvendigvis **to**
databasebundne artefaktforløb. Havde godkendelsen været bundet til manifestet,
skulle mennesket godkende de samme fem tekstdiffs to gange. *Afvist alternativ:*
lade det ske. Begrundelse for at afvise: den anden godkendelse ville blive en
formalitet, man klikker igennem, og en godkendelse man ikke reelt læser er
værre end ingen. Teksten afhænger af record-verbatim og normaliseringsprofil,
ikke af databasen, så bindingen til en teksthash er den ærlige afgrænsning.
Manifestet binder fortsat bundle-hashen, så tekstændringer stadig invaliderer
alt.

**2. Source-record-eksklusivitet håndhæves deklarativt, ikke kun med låse.**
`narrative_record_publication` har unikhed på `narrative_id` og `record_ref`,
men **ikke** på `source_record_id`. En binding, der ikke findes, kan ikke
`FOR UPDATE`-låses, så to writere kan hver oprette en binding for samme record
og begge committe. *Valgt:* partielt unikt indeks
(`WHERE status IN ('draft','published')`) **plus** delt lås på
`private.source_record`. *Afvist alternativ:* kun låsedisciplin — den beskytter
ikke mod en fremtidig writer, der glemmer låsen, og det er præcis den slags
regression, ingen opdager før den rammer produktion.

**3. `phase` og `operation` holdes ortogonale.** Spec'en foreslog
operationskoder `c3_apply|c3_reversal`. Valgt i stedet: `phase='c3'` +
`operation='apply'|'reversal'` som separate felter. Begrundelse: fasen er et
kontrolleret vokabular, senere faser udvider det med en migration, og
sammensatte koder ville betyde, at hver ny fase fordobler antallet af
operationsværdier. `payload_schema_version` tilføjet, så en senere fase ikke kan
flytte C3-eventets betydning.

**4. `haendelse`-kravet nedskaleret fra regenerering til »kræv sættet tomt«.**
`red_upsert_narrativ` opdaterer kun `narrative`; `haendelse` er en
tekstafhængig envejsprojektion uden regenereringstrigger, så en tekstændring
kan efterlade forældede spans. Måling: `haendelse` har **0 rækker** i hele
prod. Derfor bygges ingen regenerering — previewet måler ID-sættet og kræver
det tomt. Kravet skal genbesøges, hvis hændelsesudtrækket køres (#130). Dette
er anvendelsen af princippet om, at målingen afgør *hvor meget der skal bygges*
— ikke om problemet er reelt.

**Metodisk sidegevinst:** tre af rettelserne lå oprindeligt kun i planens
filkort og noter uden et step, der udførte dem — samme fejltype som
reviewfundet H6. En udførende agent følger tasken, ikke indledningen. Enhver
rettelse skal derfor være et step med sin egen test, ikke en note.

## BESLUTTET: evidensbaseret genimport — retning efter afvigelsesvurderingen (2026-08-22)

Fem uafhængige audits + læse-kun prod-måling + Codex-krydskontrol viste, at
programmet pivoterede ~2026-08-06 uden skriftlig beslutning: det byggede er et
provenance-lag for 1939 (592 records, 559 bindinger) oven på juli-loaderens
data — ikke spec'ens evidensbaserede genimport (fortolkningslag 0 rækker,
2018-20 0 records, placement/membership 0 rækker). Fuld opgørelse:
`docs/superpowers/reviews/2026-08-22-evidensbaseret-genimport-afvigelsesvurdering.md`.

**Tre beslutninger (brugeren, 2026-08-22):**

1. **Fortolkningslaget SKAL fyldes.** Provenance-laget er ikke det færdige
   produkt. Extractor-runner + `proposed`-ingest + vokabular-mapping til
   promotion bygges (#147), med klausulgranularitet som forudsætning (#148).
   Spec §20 er fortsat målet.
2. **2018-20 SKAL have fase A-ækvivalent** (rendition, records, ankre,
   bindinger) uafhængigt af udtræk (#149) — kildeversionerne i UI skal være
   symmetriske. Forudsætter at writeren generaliseres først (#153).
3. **Fase-pakke-modellen er den gældende prod-gate** i stedet for planens
   parallelle DB + samlet cutover: backup (0600+SHA) → restore-rehearsal m.
   byte-identiske baselines → hash-låst manifest → brugergodkendelse → ét
   apply. Kendt svaghed: ingen uafhængig gammel↔ny-sammenligning; kompenseres
   af en »prod = sum af manifester«-afstemning (#156).

**Anti-creep-regler, der følger af beslutningerne:**

- Ingen ny v50-fase (C3-apply, `[NY]`, C1, C2) før narrativ-nøglen (#152) er
  afgjort — C3 må ikke bygges på en model, der skal skiftes.

  **Præcisering 2026-08-22 (efter måling):** reglen blev skrevet på påstanden
  om, at #152 »blokerer« C3. Den påstand var ikke udledt, og målingen viste
  desuden, at der ikke findes nogen unique-constraint på
  `(subjekt, source_id)` — én-pr-udgave bor i `red_upsert_narrativ` og
  læserne, ikke i skemaet. Reglen gælder derfor kun, indtil ét spørgsmål er
  besvaret: **er C3's apply-operationer bindinger eller tekstkirurgi?**
  Bindinger (»pensionér person X, ombind record R til person Y«) er
  fremadkompatible med en senere nøgleændring, og så kan C3 køre først.
  Tekstkirurgi (»føj fragment til 1017's `tekst`, slet 1021's narrativ«)
  skal rulles tilbage af en nøgleændring, og så går #152 først. Afgøres af
  gennemgangen af `2026-08-22-1939-v50-c3-atomisk-apply.md` — ikke af skøn.
  Merge-patologien er til gengæld nu empirisk bekræftet (1017 rummer hele
  record A + starten af record B; 1021 rummer B's hale), så #152's
  berettigelse står, uanset hvordan sekvensen falder ud. Se
  afvigelsesvurderingens §7.6b-c.

  **AFGJORT samme dag — gaten ophæves.** Gennemgangen af
  `specs/2026-08-22-1939-v50-fase-c3-apply-design.md` viser, at C3's fem
  sager er **bindinger, ikke tekstkirurgi**, og dermed fremadkompatible:

  - `TIL`-semantikken kræver, at target-narrativet under lås har
    bindingstilstand `absent` (eller en eksakt draft til samme record), og at
    **ingen anden binding findes for samme source-record** (§Record- og
    publiceringsinvarianter). Hver sag etablerer altså præcis ét
    record ↔ ét narrativ ↔ én person — nøjagtig den invariant, record-nøgling
    ville håndhæve.
  - »Implicit rebind eller withdrawal af eksisterende publiceringer« og »de
    øvrige lowercase-start- eller `[NY]`-sager« er eksplicit **uden for
    scope**. Merge-sagerne (1017/1021, 929/930, 1013/1014, 1791) er parkeret
    og røres ikke; 1017 og 1021 nævnes slet ikke i C3's apply-dokumenter.
  - Teksten skrives ganske vist om, men konvergerer mod netop den tilstand,
    en senere `narrative.source_record_id` ville udtrykke. Backfill efter
    #152 bliver triviel og tabsfri:
    `UPDATE narrative SET source_record_id = pub.source_record_id FROM
    narrative_record_publication pub WHERE pub.narrative_id = narrative.id`.

  **Ny rækkefølge: C3-apply først, #152 derefter.** C3 leverer redaktionel
  værdi nu uden at male os op i et hjørne, og #152 tager bagefter præcis de
  sager, C3 måtte parkere — de bliver først *udtrykkelige* med en
  record-nøglet model i stedet for at kræve tekstkirurgi. Rækkefølgen for
  resten er uændret: #153 (generalisér writer) før #149 (2018-20 fase A).

  Forbehold: verifikationen hviler på designets invarianter og dets
  menneskelige før/efter-tekstgodkendelse, ikke på en optælling af de fem
  konkrete personer — beslutnings-JSON'en ligger i gitignoreret `work/`.
- Ingen ny plan uden henvisning til et §7-punkt i afvigelsesvurderingen eller
  et af issues #147-#158.
- Ingen prod-skrivning uden committet GO-pakke.
- Spor H (heraldik) og M (mobil redaktør) er parkeret, ikke glemt; de får
  ingen issues, før kernen (#147-#150) står.

Øvrige issues fra vurderingen: #151 (én identitetsvej), #154 (global REVOKE
EXECUTE), #155 (DB-hærdning), #157 (dokumentationsdrift), #158 (1939 v50
lukning).

## ÅBENT: hvor langt er bio-udtrækket nået? (2026-08-20)

Målt mod prod, så spørgsmålet »har vi udtrukket de ekstra bio-oplysninger?«
kan besvares med tal frem for indtryk.

**Rygraden er bredt dækket.** 7.197 fakta på 15 typer:

| Mål | Antal | Af 1.811 |
|---|---:|---:|
| Har mindst ét faktum ud over navn | 1.473 | 81 % |
| Har fødsels- eller dødsdato | 1.335 | 74 % |
| Har narrativ | 1.167 | 64 % |
| Har gods (`relation`→`estate`) | 308 | 17 % |
| Har embede (`relation`→`organisation`) | **150** | **8 %** |
| Har kun navn og intet andet | 263 | 15 % |

Typefordeling: navn 1.815 · død 1.137 · fødsel 1.104 · forældrefamilie 922 ·
titel 806 · begravelse 325 · dåb 293 · dekoration 131 · floruit 105 ·
dødsårsag 21 · klosterindgang 8 · tilnavn 5 · forældre_ukendt 4 · overhoved 4 ·
adling 4.

**Det rige lag er derimod aldrig kørt.** `haendelse`-tabellen indeholder
**0 rækker**. Hændelsesudtrækket (`/daa-haendelser`) blev parkeret som issue
#130 til efter genimporten — og genimporten er nu nået til fase D2/C0. Det er
her de daterede begivenheder fra prosaen skulle blive struktur: udnævnelser,
slag, rejser, godskøb, studier.

**Størrelsesordenen af det uudnyttede:** 1939-narrativerne alene er 166.518
tegn prosa fordelt på 576 biografier. Til sammenligning er kun 150 personer
knyttet til et embede, selv om embedsroller optræder tæt i teksten
(amtmand 34, kaptajn 14, gehejmeråd 11, landråd 12 …). Rygraden er udtrukket;
karriereforløbene ligger stadig i prosaen.

**Ikke besluttet:** om hændelsesudtrækket skal køres nu, hvor genimporten har
stabiliseret teksten. Det er forudsætningen for både det levende feed og for
at persondetaljen kan vise mere end leveår — jf. »strukturerede fakta er
usynlige i fladen« nedenfor. De to hænger sammen: der er ingen grund til at
udtrække mere, før der er et sted at vise det, og ingen grund til at bygge
visningen, hvis den kun kan vise fødsel og død.

## UDFØRT: C0-efterkørslen kørt i prod 2026-08-21 — 1017 flyttet til C3 (2026-08-20)

Afgjort ved måling, ikke ræsonnement. Fuld dokumentation i
`docs/superpowers/reviews/1939-v50-fase-c0-efterkoersel-afklaringer.md`.

**Person 1017 hører ikke til C0.** Koblingen ville fjerne afsnit B) (149 tegn),
og fragmentet findes ikke ordret nogen steder i korpus. Længste delvise match
er 57 tegn — og det match *er* person **1021's samlede narrativ**, som begynder
midt i det orddelte »Revent- low«. 1021 er altså ikke en post, men halen af
1017's afsnit B). C0's antagelse om at B)-delen »følger med i C3« holder kun
for de sidste 57 tegn; de første ~92 ville forsvinde. **Den rigtige rettelse er
en C3-sammenlægning af 1021 ind i 1017's afsnit B).** Den, der scoper C3, skal
kende dette.

**Person 1297 bliver i batchen.** Det fjernede er »Børn: Ottende Slægtled IIl.«
— en trykt krydshenvisning, samme klasse som de 73 sidemarkører og 499
søskende-ordenstal, fase B allerede fjernede.

**963/967's synligheds-spørgsmål er ikke reelt.** `private` er ikke eksponeret
gennem API'et, `anon` har nul grants på `narrative_record_publication` og får
»permission denied for schema private«, og ser 0 af de 7 staged personer og 0
af deres narrativer. Rækkefølgen mellem »bind record« og »publicér person« er
derfor ligegyldig for synligheden.

**Status 2026-08-21: UDFØRT.** De ni koblinger er skrevet til prod (`change_set 965`, bindinger 550 → 559). Se changelog. 1017/1021 er stadig åben og hører til C3. Det oprindelige forbehold nedenfor er indfriet ved at bygge en dedikeret writer med en gate-kæde stærkere end D2's:
`narrative_record_publication` står ikke i `version_pk_registry`, så en forkert
kobling kan ikke fortrydes — dumpen er eneste udvej. Gate-kæden skal være
stærkere end D2's, og fasen erstatter narrativtekst frem for at sætte et flag.
Det kræver egen spec.

## ÅBENT: 1021 er ikke enestående — 12 narrativer begynder midt i en sætning (2026-08-20)

Scannet over alle 576 1939-narrativer for 1021's signatur (teksten begynder med
lille bogstav = fortsættelse af noget afskåret):

```
 929 (302 tegn)   930 (302 tegn)   956 (433)   977 (79)   1013 (127)
1014 (127)       1021 (57)        1308 (110)  1413 (191) 1771 (58)
1772 (66)        1791 (1439)
```

To iøjnefaldende mønstre: **929/930 og 1013/1014 er par med byte-identisk
tekst** — altså både afskårne *og* duplikerede. Og fem af de tolv (929, 930,
977, 1013, 1014) står på C0's uafklarede-liste, mens 1014 desuden er en af de
7 staged.

Ingen narrativer *ender* på en bindestreg, så modstykkerne er enten allerede
afkortet eller ligger i en anden post, som 1021's gør hos 1017.

**Dette er ikke fikset — kun talt.** Tallet er relevant, fordi det antyder
C3's reelle størrelse: grænsefejlene er en klasse på mindst 12, ikke et
enkelttilfælde.

## ÅBENT: strukturerede fakta er usynlige i fladen (2026-08-20)

**Fundet under D2's web-verifikation.** Persondetaljen viser aldrig en
fakta-liste. `fetchPersonDetail` (`web/src/data/public.ts:171`) henter
narrativ, embeder, godser, medier og evt. kilder — den forespørger **ikke**
`fact`. De eneste fakta, der når skærmen, er:

- `p.years` — leveårene som lille monospace under navnet (`DetailPanel.tsx:88`),
  bygget af cache-kolonnerne `visning_foedt`/`visning_doed`
- `p.title` — titel som badge (`DetailPanel.tsx:96`)

Fødsel, dåb, død, navneformer og alt andet står i basen med afklarede
konklusioner, men har ingen vej til brugeren. Verificeret hele kæden ned for
person 1651 og 1268: fakta findes, konklusioner er `afklaret`, cachen er
udfyldt, `anon` får dem udleveret, og `getAll` paginerer korrekt. Der er
**ingen fejl** — visningen findes bare ikke.

**Hvorfor det først falder i øjnene nu:** fase D2 publicerede 21 gift-ind-
stubbe uden narrativ. Deres sider består af navn + leveår og intet andet, så
det tomrum, der hidtil var skjult bag lange biografier, blev synligt.

Det er en spænding mod invariant 6: prosaen bevares ordret *og* rygraden
udtrækkes selektivt — men kun prosaen vises. For en person uden prosa er der
derfor intet at se, selv om rygraden er der.

**Ikke besluttet:** om persondetaljen skal have en fakta-sektion, og i så fald
om den skal vise konklusionen alene eller også påstand/kilde (evidenskæden).
Redaktionsfladen viser allerede fakta; læserfladen gør ikke.

## ÅBENT: 16 tomme unioner i prod (2026-08-20)

Målt under D2's efterkontrol: 16 af 682 familier har **præcis én partner og
nul børn** — altså et registreret ægteskab uden nogen at være gift med.

```
familie 396→977 · 715→931 · 717→995 · 718→996 · 719→998 · 720→1025
        721→1040 · 723→1112 · 724→1136 · 725→1148 · 726→1198 · 727→1220
        728→1291 · 729→1356 · 730→1367 · 731→1403
```

To ting gør dem mistænkelige frem for blot ufuldstændige:

1. **Familie-id 715–731 er en næsten sammenhængende blok.** Det peger på én
   loader-kørsel, ikke på spredte redaktionelle fejl. Det passer med den
   udestående loader-guard (`navn ≠ ref`), som ellers genskaber
   spøgelses-unioner ved reload — samme klasse som oprydningen i change_sets 3-7.
2. **977, 1220 og 1291 står på C0's uafklarede-liste**, så der er overlap med
   et spor, der allerede er åbent.

**Ingen af fase D2's 21 sidder i en tom union**, og alle 16 fandtes før D2.
Fasen har hverken skabt eller forværret dem. Men de vises formentlig som
"ægteskab" i fladen, og person 996 er en af dem — netop den person, D2's
nye ægtefælle 1487 blev koblet til.

**Ikke besluttet:** om de skal ryddes, eller om loader-guarden skal komme
først, så oprydningen ikke bliver gjort om ved næste reload.

## RETTET OG DEPLOYET: `red_slet_person` var brudt for alle 551 narrativ-bundne personer (2026-08-20)

**Symptom:** `red_slet_person(p_person_id)` fejler med

```
update or delete on table "narrative" violates foreign key constraint
"narrative_record_publication_narrative_id_fkey"
```

for enhver person, hvis 1939-narrativ har en binding i
`private.narrative_record_publication`. Det er **alle 551**, fase B bandt —
altså hovedparten af 1939-bestanden. Redaktørfladens slet-knap vil fejle på
dem alle.

**Årsag:** funktionen er ældre end bindingstabellen (som kom med v50-arbejdet
i august) og kender den ikke. Dens sletteorden går
citation → assertion → fact/relation → narrative → person, og FK'en fra
`narrative_record_publication.narrative_id` blokerer narrativ-sletningen.
`red_slet_person_preview` er tilsvarende ufuldstændig: den rapporterer fakta
og relationer, men hverken narrativer eller bindinger.

**Opdaget** da person 975 skulle pensioneres (2026-08-20). Dér blev det løst
ved at slette bindingen først i samme transaktion — en engangsomgåelse, ikke
en rettelse.

**Rettelse (skrevet 2026-08-20, IKKE kørt mod nogen base):** begge funktioner
er genudgivet som en ny blok i bunden af `db-migrations.sql` og opdateret i
`schema.sql`. De tidligere blokke (linje 451 og 1714) står urørt som historik —
det er husets konvention i en replayet migrationsfil, og den sidste definition
vinder. `red_slet_person` fjerner nu bindingerne før narrativerne.

Gennemgangen fandt **to blokerende fremmednøgler mere**, som noten ovenfor ikke
kendte: `person_slaegt_membership` og `person_lineage_membership` har begge
`person_id NOT NULL` uden `ON DELETE CASCADE`. De ryddes nu i samme omgang.

`red_slet_person_preview` returnerer nu også `antal_narrativer`,
`antal_bindinger` og `antal_medlemskaber`, og begge slet-flader (web
`Redaktion.tsx`, mobil `SletBekraeftSheet.tsx`) viser tallene — ellers var
udvidelsen usynlig for redaktøren.

**Fælde værd at huske:** begge funktioner er `SECURITY DEFINER` med
`SET search_path=public`, så `private.`-tabeller **skal** skema-kvalificeres.
Uden præfikset fejler funktionen ved *deploy* med »relation does not exist«,
ikke ved kørsel.

**Status:** deployet til prod 2026-08-20 efter backup. Alle tre nye
db-verify-blokke bestod, og sletningen er verificeret på ægte data (person 924
med kildebinding, i en rullet-tilbage transaktion). Eneste udestående er
`get_advisors(security)`, som kræver dashboard-adgang — en SQL-lint for
`search_path` på SECURITY DEFINER-funktioner gav 0 fund.

**Bemærk om semantikken:** bindingen siger »dette narrativ stammer fra denne
kilderecord«. Når narrativet slettes, er udsagnet meningsløst, så bindingen
skal med. `private.source_record` skal derimod **aldrig** røres af en
person-sletning — registreringen af, at teksten står på siden, er stadig sand.

---

## ÅBEN: hvad skal en person-sletning gøre ved `source_persona_identity`? (2026-08-20)

**Spørgsmålet dukkede op** under rettelsen af `red_slet_person` ovenfor.
`private.source_persona_identity` og `private.source_persona_identity_event`
har begge `canonical_person_id` med fremmednøgle mod `person(id)` og **uden**
`ON DELETE`. De blokerer altså en sletning på præcis samme måde som
bindingstabellen gjorde — men de er bevidst **ikke** rørt af rettelsen.

**Hvorfor ikke:** en source persona er bogens beskrivelse af en person — en
påstand fra kilden, ikke et faktum om vores kanoniske person. At slette den,
fordi vi sletter personen, er samme kategorifejl som at slette
`private.source_record` (invariant 1: påstande overskrives aldrig).
`_event`-tabellen er desuden et append-only beslutningsspor.

Nulstilling er heller ikke en udvej: `source_persona_identity_target_check`
kræver at `canonical_person_id IS NOT NULL` præcis når
`decision_status='accepted'`. Man kan altså ikke nulstille feltet uden samtidig
at flytte beslutningen til fx `superseded` — og *det* er en redaktionel
afgørelse (»denne identifikation gælder ikke længere«), ikke en teknisk
oprydning der hører hjemme i en slette-rutine.

**Konsekvens indtil videre:** sletning af en person, som har en *accepteret*
persona-identifikation, vil stadig fejle på fremmednøglen. Det rammer ikke de
551 (de blokerede på bindingen), men skal afklares før persona-materialiseringen
bruges bredt.

**Rettelse efter review (Codex sol, 2026-08-20):** forslag (a) — »supersede og
tillad så sletning« — **virker ikke**. `source_persona_identity_event` er
append-only (kun en `BEFORE INSERT`-trigger, ingen UPDATE/DELETE-sti), og hver
historisk event bærer sin egen `canonical_person_id` med fremmednøgle mod
`person`. En ny `superseded`-event fjerner altså ikke den gamle accepterede
events reference. Konsekvensen er skarpere end først noteret: **har en person
én gang været mål for en accepteret identitetsbeslutning, kan den aldrig
hard-slettes** — uanset hvad `red_slet_person` gør. Det er en egenskab ved
v50'ens auditdesign, ikke en fejl i slette-rutinen.

**Valgmuligheder, revideret:** (b) lade `red_slet_person` afvise tidligt med en
forståelig domænefejl (»personen har en accepteret kilde-identifikation — træk
den tilbage først«) i stedet for en rå FK-fejl. Det er ærligt og billigt, men
løser ikke det underliggende. (c) soft-delete/tombstone af kanoniske personer,
så identitetshistorikken kan pege på et bevaret id. (d) et auditdesign hvor
historiske person-id'er bevares uden blokerende fremmednøgle.

**Dette er et arkitekturvalg, ikke en oprydning** — (c) og (d) ændrer hvad
»slet en person« overhovedet betyder i modellen, og bør besluttes bevidst.

**Status:** (b) er implementeret — `red_slet_person` afviser nu tidligt med
`PERSON_HAR_KILDEIDENTITET` i stedet for at lade en rå FK-violation slippe ud
midt i en halvt udført sletning. Det er en ærlig fejlbesked, ikke en løsning.

Gaten fyrer **præcis** når fremmednøglen alligevel ville blokere, så den gør
ingen sletning umulig, der før var mulig. Men den rejser et spørgsmål, som ikke
kan besvares uden et opslag i basen: **hvor stor en del af de 551 narrativ-bundne
er også persona-bundne?** De er i så fald fortsat ikke-slettelige — ikke på grund
af bindingen, som nu er rettet, men på grund af det uforanderlige beslutningsspor.
V50-materialiseringen skrev `identity_status: "accepted"`, og cutover-kontrollen
omfattede personae, så overlappet er sandsynligt, men ikke målt.

Kør dette mod prod for at afgøre, hvor meget rettelsen faktisk frigør:

```sql
SELECT
  count(*)                                              AS narrativ_bundne_personer,
  count(*) FILTER (WHERE EXISTS (
    SELECT 1 FROM private.source_persona_identity_event e
     WHERE e.canonical_person_id = nb.person_id))       AS blokeret_af_kildeidentitet
FROM (
  SELECT DISTINCT n.subjekt_id AS person_id
    FROM public.narrative n
    JOIN private.narrative_record_publication p ON p.narrative_id = n.id
   WHERE n.subjekt_type = 'person'
) nb;
```

**MÅLT mod prod 2026-08-20 (read-only):**

| | |
|---|---:|
| narrativ-bundne personer | **550** |
| heraf blokeret af kilde-identitet | **8** |

550 og ikke 551, fordi person 975 blev slettet samme morgen — tallet stemmer med
den kendte historik. **Rettelsen frigør altså 542 af 550.** De 8 er dem fra
v50-cutoveren, hvis integritetskontrol netop omfattede personae.

**Konsekvens for tombstone-valget:** det haster ikke. Det angår 8 personer, ikke
hovedparten af bestanden, og hard delete med dokumenteret forbehold er derfor et
holdbart valg indtil videre. Bemærk dog at tallet vokser, efterhånden som flere
identitetsbeslutninger accepteres — det er ikke et engangstal, og det bør måles
igen før den næste udgave lægges ind.

**Anbefaling fra arkitekturvurdering (fable, 2026-08-20): vælg (c), i varianten
tombstone + udtømning.** `red_slet_person` ville da tømme alt det, den allerede
sletter (fakta, evidenskæde, narrativer, bindinger, medlemskaber, external ids,
`visning_*`), men bevare den nøgne person-række med et eksplicit slettet-state,
så `canonical_person_id`-fremmednøglerne forbliver gyldige. Begrundelsen ligger
i modellens egne invarianter: personen er reelt en *konklusion*
(`datamodel-oversigt.md`), og rettelse sker ved ny tilstand ovenpå — aldrig ved
destruktion (invariant 1). Hard delete er anomalien i denne model, ikke normen.
Huset praktiserer i forvejen tombstones: 1939-reversal sletter ikke personer,
den sætter `staged=true, status='reimport_1939_reversed'`.

GDPR (invariant 8) taler ikke imod: en udtømt tombstone er et nøgent surrogat-id
uden persondata. Den reelle eksponering ved en sletteanmodning ligger i
`private.source_persona`/`source_record` — bogens egen tekst — og den består
uanset om person-rækken slettes hårdt. Hard delete ville altså ikke have løst
det GDPR-problem, tombstonen får skylden for.

**Vigtigste indvending mod (c):** tombstones skal ekskluderes konsistent i
*alle* læseflader — RLS, anon-RPC'er, finderen, `samme_som`-collapse, tællinger.
Én overset gate genopliver en »slettet« person offentligt. `staged` kan ikke
genbruges (det betyder kuratering, ikke sletning), så det kræver et nyt,
distinkt state plus en audit af samtlige læsestier og lockstep-opdatering af
web og mobil. **Beslutningen er ikke truffet — den afventer brugeren.**

---

## Hændelses-ankre: subjekt/objekt-asymmetrien (2026-08-20)

`red_slet_person` samler relationer hvor personen er **subjekt eller objekt**,
mens hændelses-loaderen (`load_haendelser.R`) forankrer hændelser efter
**subjekt alene**. En relation Q→P kan derfor bære en hændelse under *Q's*
narrativ, som ikke cascade-slettes når P's narrativer forsvinder — og
`haendelse.relation_id` har fremmednøgle uden `ON DELETE`. Sletningen af P ville
strande på Q's hændelse.

**Løsning:** ankeret løsnes (`SET NULL`) i stedet for at slette en anden persons
hændelse. Hændelseslaget er per design regenererbart, og begge kolonner er
allerede `skip_cols` i versioneringen, så en nulstilling er konsistent med
husets eget valg om ikke at versionere dem.

`haendelse.fact_id` tages med for symmetri, men den sti er **ikke** påvist:
loaderen filtrerer fakta til narrativets egen person, så et krydsanker kan i dag
ikke opstå. Det er billig forsikring mod en fremtidig writer, ikke en rettelse
af en kendt fejl.

---

## Narrativ-bindingens tab ved fortryd er publicerings-tilstand, ikke evidens (2026-08-20)

`private.narrative_record_publication` kan ikke registreres i
`version_pk_registry`: registret er nøglet på skemaløst `tabel TEXT`,
trigger-loopet bruger `%I` uden skema, og `_version_pk_where` slår kolonner op
med `table_schema='public'` hårdkodet. Sletning af en binding giver derfor ingen
`change_event` og kan ikke fortrydes.

**Vurdering:** koblingen narrativ→kilderecord er *funktionelt* rekonstruerbar for
1939-flowets rækker — labels dannes efter en deterministisk konvention, og
`record_key` er unik pr. kilde. Reelt tabt er derimod `record_ref` (en
`gen_random_uuid()`, UNIQUE og uforanderlig — en genopbygget binding ville mønte
en **ny** offentlig identitet), `published_at`, og de frit kalder-leverede labels
på den manuelle publiceringssti.

**Det er ikke tabt evidens** i invariant 1's forstand: evidensen er
`private.source_record`, som aldrig røres. Det er tabt *publicerings-tilstand*.
Alvoren i dag er lav — `record_ref` eksponeres for `anon` via
`public_person_bio_source_versions`, men ingen konsument fastholder den (kun
listenøgle og sorterings-tiebreak i web/mobil). Alvoren bliver reel, hvis
`record_ref` nogensinde bruges som citérbar reference udadtil — hvilket er
præcis, hvad den er designet til. **Bør genbesøges før den bruges eksternt.**

---

---

## Fase C1 udskudt: værdien udløses først af den anden udgave (2026-08-19)

**Beslutning:** C1 (promovering af 1.078 literal fakta + 212 ægteskaber til
det private fortolkningslag) bygges ikke nu. Fase D tages i stedet.

**Hvad målingen viste.** Programplanen kaldte C1 »mekanisk: manifest + writer
efter fase A-mønstret«. Tre tal modsiger det:

- `private.interpretation` og `private.interpretation_promotion` er **tomme**
  (0 rækker). Der er intet at promovere; fortolkningerne skal først skabes.
- Promotion-reglerne dækker **979 af 1.078** fakta (fødsel/titel/død). Dåb (50)
  og begravelse (49) mangler regler; alle **212 ægteskaber** mangler en
  regelklasse, fordi de fem eksisterende regler er `person.*`-prædikater mod
  `assertion`, mens et ægteskab er en relation.
- Fakta er **allerede kildebundne**: 3.211 citations mod DAA 1939, alle med
  `assertion_id`, fordelt på 87 sider. De 1.233 uden `citat_tekst` er
  hovedsagelig `forældrefamilie` (356, en relation uden naturligt citat) og
  `navn` (337, hvor citatet ville gentage værdien). Indholdsfakta — fødsel,
  død, titel, vielse — har citat i 366-369 tilfælde og mangler kun i 80-93.

**Hvad der reelt mangler** er koblingen fra faktum til den granulære
`source_record` (posten på siden), som narrativerne fik i fase A og B. Én side
rummer flere personer, så »DAA 1939, s. 574« er grovere end »posten om
Ferdinand, s. 574-575«. Det betyder lidt for én udgave og meget når 2018-20
skal stilles op mod 1939.

**Hvorfor udskydelsen ikke koster noget.** Fase A's 592 source records ligger
allerede uforanderligt i prod. Fakta kan bindes til dem når som helst —
rækkefølgen er fri. Det omvendte gælder ikke: bygger vi regelklassen for
ægteskaber nu, låser vi et design **før** vi har set 2018-20's ægteskabsdata.
Døren lukker sig af at gå i gang, ikke af at vente.

**Hvis C1 alligevel skal give noget nu:** det billigste med reel effekt er at
udfylde de 80-93 manglende citater på fødsel og død — de tal folk læser efter
— uden at røre fortolkningslaget og uden DDL.

---

## Grænsekontrollen som redigerbar tekst: tre valg der bærer resten (2026-08-09/10)

**Annoteringssyntaksen må ikke dele tegn med det, den annoterer.** Kildeteksten
indeholder allerede 86 `### PAGE nnnn ###`-linjer, så fladens egne markører fik `===`.
Havde begge brugt `###`, ville integritetskontrollens strip fjerne bogens egne linjer
sammen med vores — og en sletning i kilden kunne passere ubemærket. Reglen er derfor
skarp: `===` er fladens, `###` er bogens, og strip matcher eksakte navngivne mønstre,
aldrig et catch-all.

**Tavshed er godkendelse for den enkelte skæring — men ikke for en side.**
Brugervalgt: en urørt markør er en accepteret skæring (446 klik ville flytte den
gamle arbejdsbyrde ind i en ny flade). Eksporten registrerer derfor *ændringen* mod
det forudsatte sæt, ikke en dom pr. grænse. Men "antal manglende sider" kan kun være
ærligt, hvis noget markerer en side som set, så sidevisningen fik en kvittering pr.
side: 86 klik, ikke 446 domme. Kvitteringen er deaktiveret mens siden har en fejl.
*Fravalgt:* auto-besøgt (et hurtigt gennemblad ville tælle som en gennemgang).

**Identitet skal være entydig, ikke bare trykt.** Sidefremskridtet blev først nøglet
på det trykte PDF-sidetal — men bogens to sidste sider bærer begge tallet 598, så to
sider delte én plads: 86/86 var uopnåeligt, og kvittering for den ene fik den anden
til at fremstå gennemgået. Nøglen er nu kildesiden (1-86). Samme mønster som
lokal_id-valget 2026-07-30: alt beregnet eller genbrugt taber, kun entydige etiketter
står fast. Gamle eksporter oversættes fail-closed — et tvetydigt tal markerer ingen
side, fordi et gæt ville påstå at en uset side var gennemgået.

**Fladen giver review-/fil-GO, ikke materialisering.** Grænsen fra 2026-08-08 står:
afløsning af accepteret evidens kræver en selvstændig, autoriseret operation. Runde 2
— hvem der ejer hvilket stykke — er bevidst adskilt fra runde 1, så "hvor brydes
teksten" (afgøres af teksten selv) ikke blandes med "hvem er det" (kræver bogens numre).

## Menneskevalg: approval er identitetsankeret; råbroen er valgfri (2026-08-06)

**Besluttet:** Et valideret menneskevalg bindes til det eksakte, hash-fastlåste
Calamari-span med `approval.kind = human_approved_span_v1`. En invariant
Calamari↔rå-OCR-occurrence-bro registreres, når den findes entydigt, men er ikke
et krav for et menneskegodkendt valg: mennesket har allerede truffet
identitetsafgørelsen, og råbroen tilføjer redundant proveniens. Automatiske
afgørelser beholder kravet om dual-rendition-evidens. Globale krav om entydigt
ejerskab, kandidat-id-injektivitet og ikke-overlappende spans er uændrede.

**Evidence- og GO-grænse:** Adapteren kræver et komplet source-bundet
base-evidence-bundle og erstatter kun samme evidensfrie baseline-key med en
valideret human-entry. Task-5-filen `{decisions, audit_results}` og dette composed
bundle joines i `prepare_review_queue_1939.py`. Der findes ingen approval-capable
privat coverage-materializer; workflowet stopper ved review-/fil-GO. En senere
materialisering kræver selvstændigt design, godkendelse og replay.

**Udskudt backlog:** Slutarkets store occurrence på side 597–598 resegmenteres
ikke nu. Approval-stien gør den manglende invariante råbro ikke-blokerende, mens en
resegmentering ville ændre occurrence-identiteter og alignment på tværs af de
fastlåste artefakter uden at tilføje identitetssikkerhed til de allerede
menneskegodkendte valg. Arbejdet genåbnes kun, hvis senere automatisk behandling
kræver finere occurrence-grænser.

## Hvad der bevidst IKKE blev et link (2026-08-01)

**Besluttet ved link-konverteringen af web-fladen.** Reglen er "ingen fabrikerede
links": et element får kun `href` hvis målet faktisk er adresserbart i
URL-grammatikken. Tre fravalg — ret dem ikke uden at læse hvorfor:

- **`RelateView`s stitrin** (`components/RelateView.tsx`) bruger `focusOnly`:
  venstreklik skifter fokus **uden** at navigere, fordi Slægtskabs-fanen bevarer
  sit mode. Et `href` ville stå i browserens statuslinje og love en side klikket
  ikke går til. Rigtige næste skridt er ikke et anker, men en beslutning om
  hvorvidt `/relate/<aId>/<bId>` skal være adresserbar (delbare slægtskabs-links).
- **Kort-punkter** (`components/OverviewMapView.tsx`) navigerer via kort-rendererens
  `onPointPress`-callback; rendereren kan ikke levere ankre. Teknisk undtagelse.
- **Feed-kort af typen `slaegt`, `forbundet`, `samle`** får `null` fra
  `hrefForCard`: deres mål (A/B-parret, browse-tilstanden) ligger uden for
  URL-grammatikken.

**Åben opfølgning:** fire håndbyggede `/redaktion/person/${id}`-strenge
(`Redaktion.tsx`, `OcrKildepanel.tsx`, `PersonKvalitetsark.tsx` ×2) strider mod
den regel `data/nav.ts` opstiller for sig selv. Rettelsen kræver at
`redaktionPath`/`parseRedaktionPath` flyttes ud af `Redaktion.tsx` — at
eksportere dem derfra ville give en import-cyklus, fordi `Redaktion.tsx`
importerer begge komponenter. Bevidst udskudt, ikke overset.

## Kanonisk låseorden + id-gulv over versioneringshistorik (2026-07-31)

**Besluttet (af sol-review-cyklussen):** (1) Alle scripts/migrationer der LOCKer flere
model-tabeller bruger ÉN kanonisk rækkefølge — forældre-først, relation FØR assertion
(RPC'ernes naturlige skriveorden; definitionen bor ved `id_tables` i load_daa.R).
Inversion mellem samtidige LOCK-statements = deadlock. (2) Id-allokering bruger aldrig
rå `max(id)` som gulv men `GREATEST(levende max, versioneringshistorikkens max pr. tabel)`
— rækker slettet via red_slet-* efterlader change_events med højere id'er end levende max,
og id-genbrug dér "genopliver" historik på nye, forkerte rækker (fundet empirisk af
--replace-dry-runens invariantvagt). Gælder alle fire loadere + sekvens-setval i migrationer.

## Replay-laget: source-scoped replace, ikke generaliseret journal (2026-07-30)

**Besluttet (bruger-valg efter helhedsreview, issue #123):** re-load af en udgave bevarer
person-id'er via record_key-match mod identitetsregisteret; kun source-ejede rækker (uden
change_event-spor) erstattes, redaktionelt arbejde består automatisk. **Fravalgt:**
generaliseret journal-mønster (reload-invariante ankre i alle ~60 red_*-RPC'er + migration
af eksisterende samme_som-change_sets) — (b)'s forudsætninger var netop færdigbygget
(register 514/514, book_post_id = record_key, perturbationstestet reconcile), mens (a)'s
hovedomkostning netop var migrationen. Fuldt design inkl. forudsætninger (record_key-
backfill i prod, IDENTITY-migration, dry-run-match-rapport først) og åbne spørgsmål:
`docs/replay-source-scoped-design.md`. Ledsagende gates landet samme dag: #124 (reset
tømmer versioneringshistorik), #125 (navn≠ref-guard), #126 (gate-manifest).

## 1939-lokal_id: bogens trykte firleddede adresse — der tælles ikke, der læses (2026-07-30)

**Besluttet (bruger-anvist):** en 1939-posts identitetsadresse er `{linje}.{slægtled}.{afsnit}.{nr}`
(fx `IV.Ottende.II.6`) — alle fire led læst af bogens egne overskrifter og numre.

**Forkastede alternativer, begge på måling — ikke på smag:**
- *Position på siden:* en indskudt post forskyder alle efterfølgende; reconcile accepterer
  eksakte hit, så post N+1 arver tavst post N's id (perturbationstesten beviste det).
- *Beregnet gruppeindeks* (`G7.3`): 127 nabogruppe-par deler trykt nr + side, så ét forskudt
  indeks fejl-tildeler i stor stil. Samme sygdom, gruppeniveau.

Mønstret efter tre faldne kandidater: alt BEREGNET (løbenummer, position, indeks) taber
forskydningstesten, fordi én opdaget fejl omnummererer resten. Kun trykte etiketter står fast.
Enhver fremtidig lokator-kandidat skal bestå perturbationstesten (nul FORKERTE, ikke nul
tvetydige) FØR entydighed overhovedet måles.

## Register-broer valideres mod facit man allerede ejer (2026-07-30)

Om-nøglingen af identitetsregisteret (LLM-æra-lokatorer → trykt skema) brugte tre
evidenskilder, hver med indbygget kontrol: (1) tekst-anker — gammel og ny post kommer fra
samme kildetekst, så normaliserede vinduer skal stå ordret (l↔1-OCR kollapses); (2) bogens
trykte nummer som uafhængigt krydstjek — BLOKERENDE ved én uenighed (målt 445/445 enige);
(3) afkodning af de gamle LLM-id'ers indlejrede sti — men først efter kalibrering mod de
437 allerede-sikre match (0 hårde fejl på 281 afkodelige). Princip: et signal uden målt
fejlrate er et gæt; injektivitet håndhæves (to gamle om samme nye adresse → begge til
menneske). Alternativ forkastet: score-baseret matching uden margin/injektivitet (Codex-
reviewets hovedindvending mod første udkast).

## Delmængde-forældre: konflikt eller blot mindre detalje? ÅBEN (2026-07-29)

`collapseSameAs` sætter to udgavers version af samme person i karantæne når deres forældresæt er
"forskellige ikke-tomme sæt". Spørgsmålet: skal `{far}` mod `{far, mor}` tælle som **konflikt**
(som i dag) eller som **forenelig, blot mindre detaljeret** — sådan som vi allerede har besluttet
for datointervaller?

**Målt 2026-07-29** på de 142 resterende karantæner (efter dubletoprydning og ~119 forældre-match):

| Type | Antal | Betydning |
|---|---|---|
| **Delmængde** — den ene udgave siger mindre | **38** (27 %) | 1939 nævner kun faren; 2018-20 har begge. Den fælles forælder er allerede matchet |
| **Delvist** — én fælles, hver side har én ekstra | 79 (56 %) | Blandet; nogle bliver delmængder når den ekstra forælder matches |
| **Disjunkt** — ingen fælles forælder | 25 (18 %) | Overvejende stavevarianter (`Iven`/`Iwan`, `Hartvig`/`Hartwich`) der endnu ikke er matchet |

To ting følger af tallene:

- **De 38 kan aldrig løses ved matchning.** Der findes ingen 1939-person at koble moderen til —
  bogen nævner hende ikke. De bliver stående uanset hvor meget matcharbejde der lægges i.
- **De 25 disjunkte kan.** Der er præcis 25 umatchede forældre tilbage; tallene passer på hinanden.
  Matches de, bliver parrene til delmængder — altså flytter de bare over i den første kategori.

### Argumentet for at kalde det forenelighed

Det er samme mønster som datoerne, hvor vi målte at bøgerne næsten aldrig er uenige — de er
forskelligt præcise — og hvor reglen blev: *indeholdelse = enige, vis den fineste*. `{far}` ⊂
`{far, mor}` er den samme relation. Konsekvens hvis kriteriet ændres: **38 grupper folder sammen
med det samme**, og matcharbejdet får en langt lavere bund.

### Argumentet imod

Datointervaller er entydige; forældresæt er det ikke. To forskellige mænd ved navn Siwert med hver
deres børn ville også folde sammen, hvis 1939 kun nævnte faren. Karantænen er i dag den
konservative default — den gætter ikke, den parkerer — og den har vist sig at ramme rigtigt hidtil.

### Hvad der skal afgøre det

Ikke om delmængde *kan* betyde enighed, men om der findes en **diskriminator** der skiller de to
tilfælde. Kandidater, ingen af dem undersøgt:

- kræv at den fælles forælder er matchet **og** at barneparret i forvejen er enigt om navn og
  datoer (så forældresættet ikke er eneste bevis)
- begræns til det konkrete mønster: præcis 1 forælder på den ene side, præcis 2 på den anden, hvor
  den ene er fælles — altså "moderen er ikke nævnt", ikke vilkårlige delmængder
- lad det være et redaktionelt valg pr. tilfælde frem for en global regel: vis dem som en egen
  kø ("den ene udgave nævner kun én forælder — er det samme person?")

**Konsekvens for læseren så længe det står åbent:** de 38 vises som to personer i stedet for én.
Det er synligt, men ikke forkert — og at folde dem forkert sammen ville være værre.

Beslægtet: dato-reglen i
`docs/superpowers/specs/2026-07-28-redaktoer-udgavefaner-design.md` §"Hvornår er to udgaver uenige
om en dato?".

## Model-tier til GPT: terra som default, sol til eskalering (2026-07-29)

Brugervalg efter kalibrering, jf. `tools/kalibrering/` og
`docs/reviews/re-ekstraktion-forberedelse-2026-07-29.md`. Erstatter ikke
juni-beslutningen om Claude-tierne; den gælder GPT-sporet til
1939-re-ekstraktionen, valgt for at holde tokenforbruget ude af Claude-konteksten.

**Kalibreringen:** 30 poster, stratificeret hvor det gik galt sidst — 10 gravsatte
omtaler (facit kendt uden bogopslag), 10 med flere ægteskaber, 10 tætte biografier.
Samme frosne prompt til begge modeller.

| | `gpt-5.6-terra` | `gpt-5.6-luna` |
|---|---|---|
| Ugyldig JSON | 0 | 0 |
| `er_omtale` på stratum A | **10/10** | **10/10** |
| `kilde_span` ordret (blokerende, R7) | 96/96 | 82/82 |
| Ægteskaber m. partnerdata | 26/26 | 26/26 |
| `koen_kilde` sat | 24/30 | 18/30 |
| **Embeder fundet** | **59** | **35** |
| Godser fundet | 67 | 67 |

- **Besluttet: `terra` på max effort som default, `sol` til poster valideringen flagger.**
  Eskaleringsmønsteret findes allerede (`escalate_merge.py`).
- **Begge modeller løser rygraden.** Ingen ugyldig JSON, ingen opfundne `kilde_span`,
  alle ægtefæller dekomponeret, og begge fandt samtlige ti omtaler. Kontrakt-ændringen
  bar mere end modelvalget gjorde.
- **Forskellen er udtræksdybde:** terra finder 69 % flere embeder og mærker køn-kilden
  oftere. Det er samme dimension juni-beslutningen målte for Haiku — klassifikations-
  nuancer, ikke grundlæggende korrekthed.

⚠ **Forbehold der ikke er lukket:** embede-forskellen (59 vs 35) er et *antal*, ikke en
korrekthed. Om terras 24 ekstra er rigtige fund eller falske positiver kræver et
menneskeligt facit på C-strata. Brugeren valgte bevidst at gå videre uden — beslutningen
hviler derfor på at terra ikke er *dårligere* på nogen målt dimension, ikke på at de
ekstra embeder er verificeret. `work/kalibrering/uenigheder.md` har de 24 uenige poster,
hvis det senere skal afgøres.

**Addendum 2026-07-29 (uenigheds-gennemgang, bruger-godkendt: terra + to betingelser):**

- **er_omtale UDEN FOR stratum A afgjort mod kendt facit** (B/C-poster ER rigtige
  personer): terra kasserede 4 (alle med afhugget tekststart), luna 1. Ingen af dem
  satte `tekst_afhugget` en eneste gang. Det var kalibreringens alvorligste fund —
  den dyreste fejltype i omvendt retning (rigtige mennesker gravsat).
- **Prompt-hærdningen virker, empirisk:** afhugget-sektionen i `extract-prompt.md`
  (skrevet fra netop disse fund) blev kontrolkørt med terra på de 5 fejlposter —
  **5/5 nu korrekte** (`er_omtale=false` + `tekst_afhugget=true`), se
  `work/kalibrering/terra-kontrol/`.
- **Embede-forbeholdet delvist lukket ved stikprøve:** terras 5 ekstra embeder på
  B:275 (Hofjkr., Hof- og Kancelliraad, Amtmand, Landraad, Oberst) er alle ordrette
  citater fra prosaen — luna fandt 0 af dem. Merudtrækket er ægte fund, ikke støj.
  (Stikprøve, ikke fuldt facit — resten af forbeholdet står.)
- **Betingelse 2 implementeret som R10-gate** (`validate.tjek_omtale`):
  `er_omtale=true` på en post segmenteringen har forankret til sit EGET trykte nummer
  er en selvmodsigelse (omtaler har intet eget nummer) → blokeres til menneskelig
  afgørelse, aldrig auto-gravsat. Fail-soft uden anker-signal.
- Bifund: `er_omtale`/`tekst_afhugget`/`koen_kilde` manglede i validates `ALLOWED_TOP`,
  så R5 ville have flagget ethvert kontrakt-konformt udtræk. Rettet.
- C:3 og C:29 viste sig at have IDENTISK gruppetekst — det kendte delt-narrativ-problem
  ramte selve kalibreringsbatchen (2 af 10 C-poster). Re-segmenteringen fjerner den
  fejlkilde ved roden.

**Kalibreringens største udbytte var ikke modelvalget.** Den afslørede en fejl i
kontrakten: `er_omtale`-kriteriet sammenblandede "dette er en omtale" med "denne tekst
er klippet forkert", så terra loyalt markerede fire rigtige personer som omtaler. Ved
fuld kørsel var de forsvundet tavst ud af korpus. Rettet med et selvstændigt felt
`tekst_afhugget` (prompt-version 2026-07-29b); kontrolkørsel bekræftede at alle fem
omstridte poster nu klassificeres rigtigt uden tab af data. **60 kald fandt en fejl der
ellers ville være ramt 515 poster.**

## 1939-posternes permanente løbenummer: ÅBEN, og bevidst ikke sat endnu (2026-07-28)

Brugerspørgsmål: er der en plan for at 1939-posterne får et permanent løbenummer
(`person_external_id.record_key`)? **Nej — det er noteret tre gange samme dag af to
uafhængige arbejdsspor, men aldrig planlagt.** Denne sektion findes for at det ikke skal
genopdages en fjerde gang.

**Hvorfor DAA 2018-20 kunne backfilles, og 1939 ikke kan.** 2018-20's `record_key` blev
udledt af at filnavnene i `data/extracted-2026-06-18/*.json` selv *er* nøglen — identiteten
fandtes i forvejen, den var bare ikke skrevet ind i basen. 1939 har ikke det: løbenumrene
1–539 tildeles af `convert_1939_stamtavle.py` som en gennemløbende tæller hen over hele
bogen. Konverterens egen header fastslår at nummer-ankeret derfor er "reelt dødt".

- **Beslutning: ingen nøgle før korpuset ligger fast.** En permanent nøgle skal overleve at
  bogen segmenteres om. Re-segmenteringen 2026-07-26 flyttede postgrænser i 216 narrativer;
  havde numrene været brugt som nøgle, ville redaktionelle rettelser bagefter have hængt på
  de forkerte personer. Fraværet af `record_key` er derfor **det rigtige valg indtil videre**,
  ikke en forglemmelse.
- **Konsekvens i dag:** 1939 kan læses og bruges som kilde — `red_set_konklusion` tager kun
  et assertion-id og har intet ankerkrav, så en 1939-oplysning kan udmærket vælges som den
  gældende. Kun `red_ret_ocr_felt` (transskriptionsrettelse) er spærret, fordi den forankrer
  på `(import_key, record_key)`.
- **Rækkefølge, når det tages op:** (1) dubletgennemgangen fra
  `docs/reviews/dubletter-1939-2026-07-27.md` — ~30 par betyder at nogle poster skal væk, og
  man giver ikke nøgler til poster der forsvinder; (2) nøglen på et korpus der ligger fast;
  (3) redigerbarhed af 1939.
- **Kandidater, ikke undersøgt:** artefaktet bevarer postens egen nummerering inde i sin
  gruppe (`lokal_id`) og en intern post-id (`_id`) — begge fra kilden frem for opfundet af
  konverteren. Om nogen af dem er stabil på tværs af re-segmentering er præcis det
  spørgsmål en plan skal besvare.
- - **⚠ Artefaktet og prod er drevet fra hinanden (opdaget 2026-07-29).** `linked_clean.json` og
  `clean_1939.json` indeholder begge **539** poster; prod har **515** efter at 23 dubletter blev
  slettet. Sletningerne findes **kun i basen**. `person_external_id` står på loaderens reset-liste
  (`load_helpers.R`), så en genindlæsning fra artefaktet ville **genskabe alle 23 dubletter** og
  efterlade enhver nøgle mintet i mellemtiden pegende på poster der ikke længere skulle findes.
  Enhver nøgle-mintning skal derfor ske **efter** at artefaktet er afstemt med prod — ikke før.

**Fremadrettet krav (K4 i `docs/reviews/flerslaegt-parathed-2026-07-28.md`):** for nye
  slægter sættes `record_key` **ved udtræk**, ikke ved backfill bagefter. Så opstår problemet
  ikke igen.

Beslægtet, men egen sag: de **627 gift-ind-ægtefæller** uden bogpost er ikke-redigerbare af
samme grund (intet anker). Nøglen dér ville være forælderens `record_key` + indeks i
`aegteskaber`, og `linje` SKAL være NULL, da `regen_person_visning()` ellers påhæfter
slægtsnavnet til indgifte ægtefæller.

## Feedets GDPR-nødbremse: dødsevidens-gate + narrativ-minimum, kun i feed-laget (2026-07-25)

**Implementeret på feature-branch, ikke deployet.** Ønske: aldrig vis en levende eller
muligvis-levende person i feedet (web-forside + mobil), og aldrig et portræt-/dagensperson-kort
uden et brugbart narrativ.

**`person.levende` er en ren manuel redaktør-markering** (`schema.sql`) der aldrig genberegnes
ud fra fødsels-/dødsdato — RLS' `person_offentlig` (`db-rls.sql`) stoler blindt på den. En
fejlmarkering (glemt/forkert flag) ville derfor kunne lække en levende person gennem hele
site'et. Bevidst valgt at IKKE ændre RLS/`person_offentlig` denne omgang — det ville ramme
person-sider, søgning og stamtræ, langt bredere end det efterspurgte "feed", og er en
prod-RLS-migration med større blast radius. I stedet: en uafhængig gate udelukkende i
`packages/feed` (`levende.ts`, `kunSikkertDoede`/`erSikkertDoed`), anvendt ét sted
(`buildFeedOrder`'s choke-point) + separat i `web/src/data/home.ts` (`curatedFounders`/
`forsideStartpersoner`, som viser navne UDEN OM `buildFeedOrder` og ellers ville omgå gaten).
Kræver positiv dødsevidens: registreret dødsår, ELLER fødsel for over **120 år** siden uden
dødsår (ingen kendt person i slægten er dokumenteret ældre). Mangler begge → udelades
(fail-closed), selvom `person.levende=false` allerede skulle have tilladt personen.

Målt mod prod (`xjnvdhajfyrcytatnzos`, 2026-07-25, 889 RLS-synlige personer): 720 har positiv
dødsevidens (81 %); 3 er født inden for aldersgrænsen uden dødsår (den reelle risikogruppe
gaten er lavet til); 166 har hverken fødsels- eller dødsår og kan derfor ikke klassificeres.
Feedets person-kort-pulje krymper med disse ~169 (19 %) — de forbliver synlige på egne
person-sider/søgning/stamtræ, kun feedets kuraterede overflader er strammet.

**Narrativ-minimum:** portræt-/citat-/dagensperson-kort krævede før kun ikke-tom bio
(`p.bio.trim() !== ''`); et enkelt fragment ("Nævnt 1650.") kunne bære et helt kort. Ny grænse
`MIN_BIO_LAENGDE = 120` tegn (`pool.ts`), afledt af den eksisterende `firstQuotableSentence`-
gates 40-tegns minimum for ÉN sætning × ca. 2-3 sætninger. Målt mod prod med samme
udgave-prioritering som `pickPreferredBio` (nyeste udgave vinder): **399 af 889** synlige
personer består BÅDE dødsevidens- og narrativ-gaten (45 %) — det er feedets reelle
portræt/citat-pulje, ikke det rå 890-tal. 312 har slet intet foretrukket narrativ, 112 har ét
under 120 tegn.

**Åben backlog:** skal `person_offentlig`/RLS også hærdes med samme 120-års-regel (site-bredt,
ikke kun feed)? Brugerens beslutning — ikke taget denne omgang.

## Redaktions-datahentning var strukturelt tung, ikke midlertidigt langsom (2026-07-24)

**Delvist løst samme dag.** Fund fra manuel test af "Sammenlign udgaver": "Indlæser
redaktions-datasæt…" tager mærkbart lang tid. Verificeret empirisk mod prod
(`xjnvdhajfyrcytatnzos`, status `ACTIVE_HEALTHY` — ikke en midlertidig serverdegradering):

1. **RLS-filtrering på `fact`/`conclusion`/`assertion`/`family_member` m.fl. er ikke
   indeksérbar.** Synligheden går gennem `entitet_offentlig()` (`db-rls.sql`), som Postgres ikke
   kan bruge et indeks til — planlæggeren falder til en **sekventiel scan** + funktionskald pr.
   række. Målt via `EXPLAIN ANALYZE` (som `authenticated`): 571 ms for ét ufiltreret opslag på
   `assertion` (~7.000 rækker, `Seq Scan on fact` inderst med `Rows Removed by Filter: 2687`).
2. **Denne dyre filtrering genberegnes fra bunden pr. side.** `getAll()` (`packages/core/src/getAll.ts`)
   paginerer i sider af 1000 (PostgREST-grænsen); intet caches mellem separate requests, så det
   samme sekventielle scan kører forfra for hver side — op til 7 sider pr. tabel ved nuværende
   volumen.
3. **Supabases egen performance-advisor bekræfter uafhængigt et kendt anti-mønster:** `fact`,
   `conclusion`, `person`, `family_member`, `person_external_id` har hver TO permissive RLS-
   policies (`auth_read` + `redaktion_read`) for samme rolle/handling — tvinger Postgres til at
   OR'e begge sammen pr. række i stedet for én samlet policy (`multiple_permissive_policies`,
   WARN).
4. **`fetchMatchPersoner()` (`web/src/data/redaktionRead.ts`) var allerede kode-kommenteret som en
   bevidst bred, ufiltreret hentning** ("PoC-volumen er håndterbar") — en rimelig afvejning ved
   ~900 personer, men målingen ovenfor er efter 1939-loadet (1758 personer). Blev kun værre med
   mere data, rettede sig ikke af sig selv.

**Genmåling som ægte redaktion-JWT (samme dag) nuancerede fundet:** `redaktion_read`-policyen
bruger `(select current_rolle())='redaktion'` som InitPlan og kortslutter OR'et korrekt — de dyre
`entitet_offentlig`-subplans viste `never executed`. For redaktøren selv var flaskehalsen derfor
IKKE punkt 1 (RLS-sargability), men punkt 2: summen af net-roundtrips på tværs af 5 parallelle,
pagineret-i-1000 `getAll()`-kald.

**Løst (punkt 2+4):** `red_match_personer()` — batchet, redaktion-gated RPC i samme mønster som
`hist_for_subjekter` (`db-migrations.sql` 2026-07-24), returnerer de samme rå rækkesæt i ét
kald. `fetchMatchPersoner()` er nu et tyndt `.rpc()`-kald; `buildMatchPersoner`/`RedMatchPerson`
uændret. PR #88, anvendt+verificeret mod prod samme dag (~135ms server-side for hele
aggregatet). Policy-konsolidering (punkt 3) er droppet som følge af genmålingen — ingen målt
gevinst, unødig risiko på GDPR-fladen.

**Ikke løst:** punkt 1 (entitet_offentlig-sargability) gælder fortsat for anon/almindelig
authenticated-læsning (ikke redaktion) — relevant hvis/når den offentlige API-flade vokser til
samme skala. Ingen akut driver pt.

## Præsensliste: patrilineær efterkommer-tilhør — barn hører kun til under faderen (2026-07-23)

**Brugerfund mod rigtig prod-data:** Friedrich (Fritz) Carl Heinrich Reventlow (person 455,
†2008) er søn af to blod-Reventlow-forældre (Einar og Adelheid, fra hver sin gren der giftede
sig sammen) og blev vist under BEGGE forældres efterkommer-liste i "I linje, 1. gren" — men DAA
er patrilineær ("linje/nr følger mandslinjen", jf. `compareParentOrder` i `web/src/data/model.ts`),
så et barn med to kendte forældre hører KUN til under faderen, aldrig moderen, selv når moderen
selv er en fuldt dokumenteret blod-slægtning.

- **Ny hjælper `patrilinealForaelder`** (`packages/core/src/presensListe.ts`): barn med 2+
  registrerede forældre → foretræk den med `koen='mand'`; barn med 0-1 forælder → den forælder
  uændret (aldrig datatab). Anvendt i `pruneUndertrae`s egen boern-beregning og `buildGren`s
  søskende-sidegren-beregning.
- **Superseder `krydsReference`-mekanismen for "barn af to kendte forældre".** Den ambiguitet
  (fx to grene der gifter sig sammen) løses nu FØR `alleredeVist`-laget nås overhovedet — ingen
  krydshenvisning nødvendig, da moderen aldrig får tilbudt barnet i første omgang.
  `krydsReference` forbliver som forsvarsmekanisme for ægte konvergent slægtskab dybere i
  træet (dobbelt-fætterskab uden en direkte fælles forælder) — dækket af en parentesløs
  lavniveau-test, ikke længere reelt eksponeret via `buildGren` for den almindelige sag.
- **To reviewrunder fandt en reel regression før dette landede:** den første version filtrerede
  kun `pruneUndertrae`/`buildGren`s efterkommer-retning, men lod `blodOgGiftInd` (klatrings-
  retningen) beholde sin gamle rigdoms-først-heuristik. Når faderen INGEN egen registreret
  herkomst har, men moderen HAR sin, valgte `blodOgGiftInd` fejlagtigt moderen som "blod" —
  og det nye søskende-filter ekskluderede da hendes øvrige børn, INKL. ankerets egne fulde
  søskende, med kun en misvisende `levende_uden_gren`-advarsel som spor. Rettet ved at lade
  `blodOgGiftInd` delegere HELE afgørelsen til `patrilinealForaelder` (ét kald, ingen separat
  heuristik tilbage at uenes med) — klatring stopper nu naturligt ved en far uden videre
  herkomst, i stedet for fejlagtigt at klatre videre via morens linje.
- **Ingen prod-datarettelse nødvendig** — Fritz' egne data (to korrekt registrerede forældre)
  var altid rigtige; fejlen lå udelukkende i visnings-algoritmen.

## Præsensliste-visning v1: beregnet frem for lagret + overhoved-fakta-konvention (2026-07-22)

Implementeret via subagent-driven-development med Codex (`gpt-5.6-sol`) som udførende
implementer pr. task og Claude-subagenter som uafhængige task-reviewere (spec + kvalitet).
Spec: `docs/superpowers/specs/2026-07-22-praesensliste-visning-design.md`. Plan:
`docs/superpowers/plans/2026-07-22-praesensliste-visning.md`. Alle 10 tasks grønne
(`packages/core` 291/291, web 426/426, mobil 348/348, alle `tsc --noEmit` rene).

- **Beregnet, ikke lagret (bekræftet ved implementering).** Relationsgrupper og
  overskrifter (FARBROR, SØSTRE, FARFARS FARBROR …) beregnes af `buildPresensListe`
  (`packages/core/src/presensListe.ts`) fra slægtsgrafen + et sæt redaktionelt udpegede
  overhoved-fakta — ingen bogstruktur er lagret. Facitliste-testen (Task 5) reproducerer
  DAA 2012-14 II linje 1. grens gruppestruktur (SØSTRE + FARFARS FARBROR) fra en syntetisk
  graf-fixture, som bekræftelse af algoritmen mod den trykte bog.
- **Overhoved-udpegning:** ny vokabular-række `('faktatype','overhoved', …)` (INGEN
  skemaændring) + eksisterende `red_upsert_fakta`/`red_opret_fakta`-flow. Værdi-format
  `"<ROMERTAL> linje[, <N>. gren]"`, parset fail-closed af `parseOverhovedVaerdi`
  (uparsebar værdi giver aldrig et gættet anker). **Prod-apply udført 2026-07-22 (bruger-
  godkendt):** `INSERT INTO vocab (scheme, code, label) VALUES ('faktatype','overhoved', …)
  ON CONFLICT DO NOTHING` kørt transaktionelt mod prod (xjnvdhajfyrcytatnzos) via psql
  (session pooler, `sslmode=require`). Verificeret: rækken findes med korrekt label,
  `vocab`-antal 152→153 (præcis +1, ingen sideeffekter), idempotens bekræftet (gentaget
  INSERT gav 0 rækker), `vocab.relrowsecurity` uændret (RLS-lint/get_advisors ikke kørt —
  ingen Supabase MCP tilgængelig i denne session — men irrelevant her: ingen ny tabel,
  funktion eller RLS-politik, kun én dataræke i en allerede-sikret referencetabel).
- **RETTET (2026-07-22, bruger-beslutning "vis én gang + krydshenvisning"):** den tidligere
  kendte struktur-begrænsning er lukket. `pruneUndertrae`s vagt er splittet i to: `paaVej`
  (ID'er på den aktuelle rekursions-stak — en ægte data-cyklus beskæres fortsat defensivt til
  null, som hidtil) og `alleredeVist` (ID'er allerede fuldt bygget og BEHOLDT, delt på tværs
  af HELE `buildGren`-kaldet — ikke kun ét undertræ). Første forekomst af en levende person
  inden for én gren vises fuldt ud; enhver senere forekomst inden for SAMME gren bliver en tom
  krydshenvisnings-stub (`PresensNode.krydsReference`), vist i UI som en kort note ("vist
  andetsteds i denne gren") i stedet for stille at blive droppet (det oprindelige fund) eller
  duplikeret fuldt ud (kernens spejlbillede, fanget af slut-reviewet — to FORSKELLIGE
  sidegrene der begge fører til samme levende person, fx et fætter-fætter-ægteskab). ÉN
  mekanisme løser begge varianter, da `alleredeVist` trådes gennem både ankerBlokkens egen
  rekursion og hver søskende-sidegrens kald. `alleredeVist` tilføjes KUN på succes-stien
  (aldrig ved beskæring til null), så et tidligere forgæves forsøg aldrig blokerer en senere
  gyldig forekomst. Krydsning MELLEM grene (`dobbelt_naaet`-advarslen) er uændret og upåvirket
  — scopet er bevidst kun inden-for-gren. Facitliste-tests dækker begge varianter direkte.
- **Trust-erfaring fra eksekveringen:** Codex' selv-rapporterede tekst (rapportfiler,
  afsluttende chat-resumeer) viste sig ved ét tilfælde (Task 4) at være fuldstændig
  opdigtet — beskrev funktioner/tests der ikke fandtes i den faktisk leverede (og korrekte)
  kode. Al implementering blev derfor verificeret uafhængigt gennem hele kørslen: kontrolløren
  genkørte selv test-suiter/`tsc` efter hvert task, og task-revieweren læste diffen — aldrig
  rapporten — som eneste kilde til sandhed. Selve koden var i alle 10 tasks korrekt.
- **To reelle implementeringsfejl fanget af task-reviewere og rettet under kørslen** (ikke
  Codex-fejl — begge var mangler i selve planen, forfattet af controlleren):
  1. Task 5's facitliste-test importerede hjælpefunktioner (`mk`/`union`/`pc`) fra en
     sibling `*.test.ts`-fil, hvilket fik Vitest til at genregistrere den importerede fils
     `describe`/`test`-blokke under den importerende fils suite (302 tests i stedet for de
     forventede 291). Rettet ved at udtrække hjælperne til en ikke-testfil
     (`packages/core/src/__tests__/presensFixtures.ts`).
  2. Task 9's mobil-skærm udelod stille partner-visning (design-spec §"Ægtefæller vises
     sammen med deres familie") og genskabte `Node`/`Gren` som indlejrede komponenter ved
     hvert render. Rettet: partnere vises nu identisk med webbens logik, komponenterne er
     løftet til modul-scope.
- **Bevidst v1-scope-reduktion (ikke fejl):** mobil-skærmen viser advarsler som et
  antal-tal, ikke som webbens udvidelige per-advarsel-liste (`<details>`). Acceptabel
  forenkling for en lille skærm; kan udvides senere hvis redaktøren efterspørger det.
  Tilsvarende mangler mobil webbens "Vis i præsensliste"-genvej fra person-siden samt
  fokus-scroll til en bestemt person (kun drawer-indgangen findes på mobil) — funktionen
  er stadig nåbar, blot ét klik længere væk; kan tilføjes senere uden arkitektur-ændring.
- **Rettet efter slut-review: `canonicalIdById` manglede på mobil-modellen.** Web's
  `loadModel` stamper `canonicalIdById` direkte på `Model`-objektet, men mobil-storen
  (`useStore.ts`) holder det som et separat felt ved siden af `model` — så
  `kanoniserPresensGrundlag(model, …)` i `praesens.tsx` læste `model.canonicalIdById ?? {}`
  og fik altid et tomt map, dvs. funktionen var reelt en no-op på mobil (ankre/levende-flag
  fra et `samme_som`-alias ville aldrig linjes op med den allerede kollapsede graf). Lavt
  risiko i dagens data (aliasser er afdøde grundlæggerdubletter/kryds-slægt-broer, ikke
  levende linjehoveder), men brød planens egen invariant. Rettet lokalt i `praesens.tsx`
  ved at flette store'ns `canonicalIdById`-felt ind på modellen før kanonisering — en
  bredere rettelse (stample det direkte på `model` i selve storen, til gavn for alle
  fremtidige forbrugere) er en mulig senere oprydning, ikke nødvendig for v1.
- **Codex-sandbox-begrænsning (proces, ikke kode):** i denne git-worktree-opsætning
  (gitdir uden for worktree-træet, `.git/worktrees/<navn>/`) kunne Codex ofte ikke selv
  committe (`.git/worktrees/*/index.lock` skrivebeskyttet i dens sandbox) — undertiden
  lykkedes det dog. Controlleren staged/committede derfor konsekvent selv efter hver
  implementer-kørsel, uafhængigt verificeret først.

## RLS-synlighed: fail-closed `entitet_offentlig`-helper, ikke `type <> 'person'` (2026-07-17)

**Besluttet:** al polymorf RLS-gating (fact/relation/narrative/note/text_mention) afgør synlighed via
`entitet_offentlig(type, id)` (SECURITY DEFINER) med et eksplicit `CASE`: `person`→`person_offentlig`,
`family`→`family_offentlig`, det faste ikke-PII-entitetssæt→`true`, **ELSE `false`**. `family_offentlig(fid)`
er offentlig kun hvis intet medlem er ikke-offentligt.

**Hvorfor:** det tidligere mønster `subjekt_type <> 'person' OR person_offentlig(...)` var **fail-open** på to
måder (Codex-fundament-review): (1) `family` er en polymorf target-type der bærer person-PII gennem sine
medlemmer, men `<> 'person'` behandlede den som offentlig → levende families vielse-fakta/noter lækkede til
anon+authenticated; (2) type-kolonnerne er fritekst uden CHECK, så en fejlstavet discriminator (`'Person'`)
slap forbi. En fail-closed helper dræber hele klassen (media-gatingen var den første instans af samme fejl).

**Kritisk:** helperne SKAL være SECURITY DEFINER — ellers re-filtrerer `family_member`-RLS det levende medlem
væk fra helperens egen subquery, så den ser en "ren" familie → fail-OPEN. `fact`/`relation`-mål (kun
note/text_mention) gates IKKE af helperen men cascader gennem targetets EGEN RLS (EXISTS i policyen).

**Alternativer forkastet:** (a) tilføje `family` som endnu et special-case i hver policy — ville efterlade
ukendt-type-hullet og gentage mønstret ved næste entitet; (b) CHECK-constraints på type-kolonnerne alene —
løser fejlstavning men ikke family-target-lækken; (c) fail-open ELSE — ville genintroducere Finding 2.

## Authenticated-tier fail-closer til anon-niveau indtil samtykke-/slægts-scope findes (2026-07-17)

**Besluttet:** en logget-ind bruger uden redaktør-rolle (medlem-tier, fx bogmærke-brugere) ser nu **præcis det
samme som anon** — kun afdøde, ikke-private personer. Levende er skjult for alle uden redaktør-rolle.

**Hvorfor:** den tidligere `auth_read` lod enhver authenticated bruger se alle ikke-private levende personer
(en bevidst udskudt beslutning), i strid med invariant #8 (levende kræver samtykke) — en GDPR-fail-open.
Indtil en egentlig samtykke-/slægts-scope-model er bygget (Codex-fund F-05), er fail-close til anon-reglen den
sikre standard. Redaktion beholder fuld adgang via det additive `redaktion_read`-lag.

**Konsekvens:** logged-in bogmærke-brugere mister synlighed af levende personer — et bevidst produkt-tab, ikke
en regression, indtil samtykke-modellen findes. **Alternativ forkastet:** beholde levende-for-medlem med et
`samtykke_offentlig`-flag nu — udskudt, da flag-modellen kræver egen design (medlem vs. forsker-tier, §F-05).

## ETL-sprog: R til DB-load, TypeScript til delt/runtime-logik (2026-07-16)

**Datavejen forbliver polyglot med et bevidst snit: R til batch-DB-load, TS til alt klienten også bruger.**
Ved opstart af flere-DAA-udgaver-arbejdet blev det taget op om R er rette sprog. Beslutning: **behold R** til
de fungerende loaders (`load_daa.R`/`load_presens.R`/`post_load_fixup.R`) — omskrivning er høj risiko, lav
værdi, og R er vedligeholderens kernekompetence. **Delt/runtime-logik (navnefoldning, dato-parsing, matching)
hører i `packages/core` (TS)**, ikke R — jf. Problem 3 §3.1 (`matchUdgaver` er TS; R-TNG-QA er kalibrerings-
reference). Disciplin: delt normalisering har ÉT hjem (TS); R kalibrerer mod TS-output, ikke sin egen kopi.
Extraction forbliver Python (tekst/LLM). Ingen R→TS-omskrivning af DB-loadet.

**`source.aar`-konvention: SIDSTE dækkede år.** Tidsserie-aksen (Problem 1) bruger sidste år i udgave-spannet
(DAA 2012-2014→2014, 2018-20→2020, 1939→1939), fail-closed parse i loaderne (`parse_aar`). En tidligere
backfill satte 2018-20→2018 (første år); harmoniseret til 2020 for ensartet "forrige udgave"-derivation
(db-migrations.sql, idempotent korrektion — anvendes først ved prod-cutover).

**Bibliografiske source-identiteter (A3d, 2026-07-17 — afklar mod primærkilde før prod-import).** Hver DAA-udgave
er en selvstændig `source` (invariant §"Hver trykt DAA-udgave"); `source` har INGEN forfatter-kolonne → forfatter
bæres i `titel` (fx `"Dansk Adels Aarbog – DAA 1939 (Louis Bobé)"`). Kendt/antaget:
- **DAA 1939** — Reventlow-stamtavlen af **Louis Bobé**. `udgave="DAA 1939"`, `aar=1939`. *(loaderen opretter den
  korrekt — verificeret i A4-dry-run.)*
- **DAA 2018-20** — Reventlow-artiklen af **Poul Holstein** (IKKE Christian Hau — han er en *citeret forsker*).
  `udgave="DAA 2018-20"`, `aar=2020` (sidste dækkede år). **NB:** dato-analysen kaldte den "2024" — det er
  sandsynligvis **trykke-/udgivelsesåret**, ikke dæknings-benævnelsen; ikke en modstrid (bind udgives typisk år
  efter dækningsperioden). Bekræft det trykte binds titelblad før import.
- **DAA 1893** — antaget **Anders Thiset**-tavle (jf. divergens-rapport); planen nævnte også "Ludwig zu Reventlow".
  **Uafklaret** — verificér forfatter mod primærkilde før 1893 evt. importeres.
- **Holstein må IKKE automatisk "vinde"** ved udgave-konflikt — rettelser går begge veje (det lokale treudgave-
  eksempel viser frem-og-tilbage-korrektioner). Kanonisk valg er redaktionelt (conclusion), ikke udgave-rang.

## `packages/core`: npm-workspace + source-only, snæver type-grænse (2026-07-14)

**Delt web↔mobil-logik samles i ét npm-workspace (`@daa/core`), ikke via paritetstest-spejling.**
Review 27 tilbød to niveauer: (A) fuld workspace-pakke, eller (B) minimalt "værn" (en test der asserter
at spejlede filer er byte-identiske). Oprindelig hældning var C (B nu + udskyd A), fordi A ville røre en
antaget prod-mobilbuild. **Da mobil viste sig kun at køre dev (ikke prod), faldt A's tungeste con væk**,
og Expo SDK 56's stærke monorepo-støtte gør Metro-friktionen lav → A valgt. Eksekveret **spike-first**:
ét modul + 5 tooling-checkpoints (Metro, jest-transform, Vite, cross-workspace-typer, Vercel deep-link)
BEVIST før fuld flytning, med fallback til B hvis et checkpoint fejlede. Alle grønne.

**Source-only pakke (rå `.ts`, ingen build-step).** Begge bundlere transpilerer kilden direkte — undgår
en dist-watch-loop og en separat build-pipeline for en intern pakke. Vercel krævede `installCommand: npm
install --prefix ..` så workspace-symlinket oprettes fra repo-roden (Root Directory=web installerer ellers
kun web's egne deps).

**Snæver type-grænse, ikke hele `types.ts`.** Kun de typer de delte moduler faktisk importerer flytter til
core (`Model` som additivt superset m.m.); app-specifikke typer bliver lokale. **`linjeByPerson`-konflikten
(web `Record<string,string>` vs mobil `Record<string,string[]>`) sidesteppes** ved at holde dens ejer-type
`Aux` app-specifik — ingen delt modul bruger `Aux`, så konflikten krydser aldrig ind i core (Codex-dual-
review-fund forfinet til en enklere, sikrere løsning end at forsone den). Grænsen mellem delt og app-
specifikt følger konsekvent: *flyt kun det forbrugerne kræver; divergens uden for det delte snit løses ikke.*

## "Forældre ukendt"-markering: rå-scope vs. samme_som-kanonisk — accepteret PoC-grænse (2026-07-11)

**Fjern-operationen forbliver rå-`personId`-scoped, selvom den offentlige projektion er kanonisk
(samme_som-collapset).** Codex-fund i review 27 (`docs/reviews/27-*.md` HIGH a): markér/fjern skriver
til det rå person-id, mens `buildParentsUnknown` folder facts fra flere rå personer til én kanonisk
(og vælger "første vinder"). Er to samme_som-linkede medlemmer BEGGE markeret, fjerner Fjern kun den
ene; den anden projicerer stadig. **Bevidst valgt backlog frem for kaskade/konflikt-visning:** (a) det
er en pre-eksisterende egenskab ved hele featuren (markér/gammel-fjern/ny-fjern er alle rå-scoped —
review-26 ændrede kun *hvordan* der fjernes), ikke en regression; (b) det kræver to samme_som-linkede
personer der *begge* er hånd-markeret forældre_ukendt — meget sjældent i en hånd-kurateret base; (c)
redaktøren collapser bevidst IKKE (evidens redigeres på rå poster). Determinisme-fixet (`.order('target_id')`
i `fetchForaeldreUkendtMarkering`) gør adfærden konsistent. Kaskadér-Fjern (RPC/editor loader collapse-
mappen + itererer flere facts) eller konflikt-visning genbesøges hvis et reelt tilfælde dukker op.

## Konto-bogmærker: login-eksklusivt (ikke hybrid), direkte tabel-adgang (ikke RPC) (2026-07-06)

**Login-eksklusivt frem for hybrid lokal/konto.** Bogmærker blev netop shippet som lokal PoC uden
reelle brugerdata — i stedet for at bygge merge-logik (lokalt→konto ved login) blev de gjort
**cloud-only**: udlogget = tomt + login-prompt, logget-ind = Supabase. Forkastet: hybrid
(lokal-når-udlogget, synk-når-logget-ind, flet ved login) — mest UX, men markant mere logik
(offline-cache, merge-strategi) for et gode brugeren selv bad om som "added benefit", ikke en
kerneflow. Ingen migration nødvendig (ingen live brugerdata i den lokale version endnu).

**Direkte tabel-adgang (RLS+grants) frem for RPC.** `bookmark`-tabellen er ren bruger-ejet data
(ingen evidens-lag, ingen redaktionel logik) → RLS-policies + eksplicitte grants er tilstrækkeligt
og Supabase-idiomatisk. `red_*`-RPC'er forbeholdes evidens-modellens skrivninger (versionering,
change-sets). Kræver dog **eksplicit** `GRANT`/`REVOKE` — Supabase auto-grant'er default-
privilegier til anon/authenticated ved tabel-oprettelse, så RLS alene lækker (dual-review 21 N1,
jf. [[supabase-revoke-from-public-insufficient]]).

**Web fik minimal login-flade; mobil kun wiring.** Mobils Konto-fane understøttede allerede
medlem-login; web's offentlige Folgesvend-læser havde ingen session (kun localStorage-"mig").
Web-skiven tilføjede derfor en lille login-modal (genbrug af `data/auth.ts`) — bevidst IKKE en
fuld kontoflade, og bevidst UDEN at ændre den eksisterende "mig"-lagring (forbliver separat,
udskudt migration).

## Følgesvend v3-feed: hybrid auto-generering + person-kun bogmærker (2026-07-05)

**Feed auto-genereret nu, editorial-krog senere (ikke DB-kurateret).** `buildFeed` er en ren
selector der udleder kort af eksisterende `Model`/`Aux` — ingen ny feed-tabel. Et tomt
`overrides`-argument reserverer den redaktionelle indgang uden at bygge den. Forkastet:
DB-kurateret feed (skema + RPC'er + redaktør-UI = stor merudvidelse uden PoC-værdi nu).

**Portrait og citat i disjunkte hash-partitioner.** Begge trækker fra personer-med-bio; uden en
regel ville samme person kunne optræde to gange. Valgt: `stableHash(id) % 4` allokerer ~25% til
citat-slot; citat-slot uden brugbar sætning falder HELT ud (bliver ikke portræt) så partitionerne
forbliver disjunkte. Forkastet: tillad dublet (redaktionelt rodet); rendrer-tids-dedup (skjuler
ikke-determinisme).

**Bogmærker: person-kun, spejler web.** Selv om v3-feedet viser gem-ikon på flere korttyper,
lagres kun kanoniske person-id'er (AsyncStorage), 1:1 med web's kontrakt. Gem-ikon vises derfor
kun på kort med `personId` (portrait/citat/embede/jubilaeum) — de gemmer personen. Forkastet:
polymorf `{type,id}` (afveg fra web; afledte kort som jubilæum/citat har ingen stabil egen-id).

**Async-lager + synkron hook-state (ikke bare `await`).** Web's bookmark-kontrakt var synkron
(`useState`-init, sync `has()`/`toggle()`). AsyncStorage-porten holder `ids` i `useState` som
render-sandhed (sync `has()`), hydrerer i effect, og toggler optimistisk + persisterer async
(seneste-vinder). Hook'en afhænger af `canonicalIdById`-**mappet**, ikke funktionsreferencen —
den stabile Zustand-`canonicalId` ville aldrig signalere recollapse (dual-review BM1/BM2).

## Flere narrativer pr. person: kilde-nøgling + per-subjekt selector (2026-07-03)

**Kilde-nøgling frem for id-liste eller konkatenering.** En persons narrativer nøgles på
`(subjekt, source_id)` — én biografi pr. DAA-udgave. Forkastede alternativer: en generisk
id-adresseret liste (over-engineering ift. udgave-driveren; kilde mister sin organiserende rolle)
og konkatenering til én narrativ (bryder invariant §6 "prosa ordret" + §7 "udgave = source", og
gør privat-flag pr. udgave umuligt). Modellen bar det allerede — kun UI/read/write kollapsede N→1.

**`source.aar` frem for `max(source_id)` eller leksikalsk `udgave`.** "Nyeste udgave" kræver et
struktureret sorterbart felt: `source.id` er ren PK (en senere oprettet TNG-kilde ville vinde
forkert), og `source.udgave` er ukontrolleret fritekst ('DAA særudgave' bryder leksikalsk sort).
Codex-fund i dual-review; additiv `aar`-kolonne + `red_opret_kilde(p_aar)` er svaret.

**Selectoren er per-subjekt, IKKE per foldet gruppe.** Spec'ens første formulering sagde "vælg på
tværs af hele identitetsgruppen", men web's cross-medlem-concat (`public.ts` founder-bio + alias-
stub) er *tilsigtet* og må ikke regressere. I stedet gøres per-medlem-valget deterministisk pr.
udgave (`pickPreferredBio`), og hver apps eksisterende cross-medlem-komposition er urørt.
Determinisme opnås via fuld orden i selectoren, ikke via gruppe-niveau-valg.

**DAA-only fallback (ingen vilkårlig stub).** Når ingen DAA-udgave findes, viser læseren *ingen*
bio frem for en vilkårlig ikke-DAA-narrativ — ellers kunne en TNG-stub blive autoritativ biografi.
Fremadrettet (TNG-enrichment) udvides `BIO_SLAGS` bevidst, ikke ved at åbne for "enhver offentlig".

**RPC-DROP er cross-client breaking → mobil i scope + prod-cutover udskudt.** Antagelsen "app er
eneste klient/lockstep" var forkert: web OG mobil deler RPC-kontrakt. At droppe en RPC-signatur
knækker den anden klients deployede bundle indtil den redeployes. Derfor: (a) mobil-redaktøren fik
en minimal source-korrekt skrivevej i samme omgang, og (b) DB-migrationer testes mod en lokal
prod-kopi og anvendes først mod prod ved koordineret merge + web-deploy (nul breakage-vindue).

## Redaktør-navigation + edit/slet bryder IKKE evidensmodellen (2026-07-03)

Spørgsmål der opstod: strider det mod evidensmodellen at lade redaktøren navigere til partnere/børn
og redigere/slette dem? **Svar: nej** — og det er værd at fastholde hvorfor, da det er let at fejllæse
invariant §1 ("påstande er uforanderlige") som et generelt redigeringsforbud.

**Hvorfor det er sikkert:** Invariant §1 gælder kun *påstande* (`assertion`) — konklusioner, relationer
og familie-links er per design det *foranderlige* fortolkningslag ovenpå. Redigering sker append-baseret
(`red_edit_oplysning`: void→jsonb, ny påstand + ny konklusion, aldrig overskrivning), og sletning kører
gennem `change_set`/`change_event` (fortrydbar). Navigation er ren læsning. Alle tre respekterer altså
evidenslaget.

**Den eneste reelle kant:** hard-delete af en *hel person* (`red_slet_person`) trækker en FK-ordnet
cascade der også fjerner de underliggende påstande — dvs. man sletter kildens udsagn, ikke bare sin
fortolkning. Derfor bevidst bevaret bag `red_slet_person_preview` + eksplicit bekræftelse. Sletning af
*links* (familie-relation, konklusion) er uproblematisk.

**Årstal på børn/partnere:** hentet fra `model.byId[pid].years` (afledt cache), ikke en ny query —
konsistent med invariant §4 (cache er envejs-projektion, læses aldrig som autoritet, men fint til visning).

## Bidirektionelle stamtræs-kolonner: fast anker + frontier-reset (2026-07-03)

Stamtræets Kolonner-visning (variant B) blev udvidet til begge retninger (aner venstre / efterkommere
højre) fra en fast **anker**-person. To ikke-oplagte valg:

**1. Fast anker, ikke re-centrering.** Ankeret flytter sig ikke ved drill; kun fokus (detalje-panel)
følger valget. **Hvorfor:** matcher den eksisterende descendant-drills semantik og holder tilstanden
enkel; visningen viser én ane-linje opad + efterkommere nedad fra ankeret — *ikke* kollaterale
slægtninge. **Fravalgt:** re-centrering på hvert valg (mere eksplorativt, men kolonnerne "hopper", og
det ville kræve at afkoble `focusId` fra `selectedId`, som web-appen bevidst konflaterer).

**2. Reset via frontier-tjek, IKKE fuldt medlemskab.** Når `focusId` skifter afgøres om drill-stien
bevares eller nulstilles. **Valgt:** bevar kun hvis `focusId` er den YDERSTE valgte ane/efterkommer
(eller ankeret). **Hvorfor (Codex-BLOCKER):** et fuldt medlemskabs-tjek (`focusId ∈ up/down`) kan
ikke skelne intern drill fra ekstern navigation til en person der tilfældigvis allerede er valgt —
drill A→B→C, klik så B i sidebaren → B∈down → ville forkert bevare stien i strid med "ekstern nav
nulstiller". Frontier-formen spejler den beviste baseline (hale-tjek). **Platform-divergens (bevidst):**
web bruger en `useState`+effekt med frontier-tjek; mobile (zustand) opnår det samme via **eksplicit
mutator-reset** — navigations-mutatorer (setFocus/setVariant/pickLinje/…) rydder `up`/`down`, drill-
mutatorer bevarer ankeret. Samme kontrakt, forskellig mekanisme pga. de to apps' state-mønstre.
Fuld spec: `docs/superpowers/specs/2026-07-03-kolonner-aner-efterkommere-design.md`.

## TNG er sammenlignings-reference, ikke facit; uenigheder loades som konkurrerende påstande (2026-07-03)

TNG-QA-rapporten flaggede 5 dato-uenigheder. **Valgt:** adjudikér hver mod DAA-kilden (narrativen bevarer
bogens prosa ordret); hvor vores `date_raw` matcher bogen (alle 5 gjorde), er TNG forkert — så vi ændrer
IKKE vores data, men loader TNG's værdi som en **konkurrerende `assertion`** på samme fakta med vores
konklusion uændret. **Hvorfor:** invariant §1 (alle kilders udsagn bevares, vores vurdering ovenpå) +
rapportens egen header. **Fravalgt:** at behandle TNG som facit og "rette" vores data (ville have
introduceret 5 fejl, da TNG var forkert i alle 5). Memory-premissen "fejl-attribueret date_raw" holdt ikke
ved kilde-tjek. Læring: en QA-uenighed er en anledning til adjudikation, ikke et signal om egen fejl.

## Spøgelses-unioner: barn "gift" med ane via mis-opløst "se nr."-ref; diskriminator = navn≠ref (2026-07-03)

Loaderen skabte 26 barnløse unioner hvor et barn var "gift" med sin egen far/ane. Rod: en `aegteskab`
hvor `partner_navn` (barnets mor, fra grupperings-headingen) og `partner_ekstern_ref` ("se nr. Y" → en ane)
er UENIGE; `load_daa.R` linkede ref'en og ignorerede navnet. **Detektions-diskriminator (efter flere
forsøg):** *ikke* "barnløs+ingen vielse" (fam 11 var ægte MEN barnløs uden vielse-fakta), *ikke* rekursiv
ane-tjek (tidlige generationers ane-kæder er selv ufuldstændige → missede de fleste). Den pålidelige er
**navn≠ref**: den opløste interne partners navn matcher ikke `partner_navn`. **Konsekvens:** loader-guarden
skal afvise intern-ref-link ved navne-mismatch (ikke ved fravær af vielse). **Læring:** en kandidat blev
manuelt bekræftet ægte af bruger (fam 11) FØR sletning — konservativ scope (kun høj-sikre) + menneske-review
på tvivl forhindrede at et ægte kryds-linje-ægteskab blev slettet. Se også [[boern-multi-union-datafix]]
(samme "se nr."/mor-heading-rod).

## Barn→union-matching: partnernavn primær, ordenstal kryds-tjek; parkér frem for at gætte (2026-07-03)

Ved fix af flergifte-forældres børn-tilknytning skulle hvert barns fritekst-`aegteskab_kontekst`
("af andet ægteskab med Sophia Amalia Hahn") mappes til rette union. **Valgt:** partnernavn som
PRIMÆR anker (positions-uafhængigt) + ordenstals-ord som KRYDS-TJEK, med NA ved uenighed eller
ukendt partner. **Hvorfor ikke bare ordenstal→position:** partnernavn kan være tvetydigt (Iwan I-60
giftede sig med samme "Margaretha von Rantzau" i både 3. OG 4. ægteskab — kun ordenstallet afgør),
OG ordinal-feltet kan være NA; de to signaler afdækker hinandens huller, og uenighed afslører
ekstraktionsfejl gratis. **Parkering frem for gæt:** børn hvis kontekst navngiver en ikke-registreret
forbindelse (III-85 Detlef, hvor feltet beskriver hans EGET ægteskab, ikke moderens) tilknyttes en
partnerløs union — aldrig et forkert ægteskab. En partnerløs union gør INGEN påstand om moderen;
den nuværende false-Brockdorff-tilknytning var en positiv falsk påstand. **Fravalgt:** LLM-baseret
matching (deterministisk fritekst-matching gav 110/111 på rigtige data).

## Prod-datafix via kirurgisk change_set (DELETE+INSERT), ikke reset-reload eller PK-UPDATE (2026-07-03)

Den allerede-loadede base bar fejlen. **Valgt:** kirurgisk versioneret korrektion (ét `change_set`,
64 flytninger som DELETE gammel + INSERT ny family_member-række) frem for (a) reset-reload fra fixet
loader eller (b) `UPDATE family_member SET family_id`. **Hvorfor ikke reset-reload:** `--force-reset`s
TRUNCATE CASCADE rammer profiles/lineage/suggestion + redaktionel historik (jf. [[base-identitet-og-reload]]);
kirurgisk fix er reversibelt og har lille blast-radius. **Hvorfor DELETE+INSERT ikke UPDATE:** `family_id`
er del af PK (family_id,person_id,rolle); en PK-muterende UPDATE er præcis den slags kant der skjulte
den tidligere GENERATED-kolonne-fortryd-bug — DELETE+INSERT giver to rene, entydigt reversible change_events.
**Delt matcher** mellem loader og korrektion, så de umuligt kan divergere. **Læring:** re-run-verifikation
er tautologisk (samme matcher); uafhængig evidens var event-tællingen (no-op INSERT trigger-logger ikke →
tab ville få 132-tallet til at komme til kort) + eksternt genealogisk holdepunkt (Anna Sophie var Hahns datter).

## Redaktør person-browse driver af `persons` (RedPerson), ikke `model.persons` (2026-07-03)

Da Følgesvends browse-UX (a-z/fødsel-sort/linje-filter) blev porteret til redaktør-fladen, kunne listen
have været drevet af den samme `model.persons` (ModelPerson) som Følgesvend bruger. Valgt i stedet: driv af
redaktørens egen `persons` (RedPerson) + kun linje-metadata fra `model.lineage`. **Hvorfor:** redaktør-listen
er *skrive-autoritativ* — `curPerson`/`recordId` skal altid resolve mod den redigerbare mængde. Hvis
`model.persons` (collapse:false) var et subset/superset af RedPerson-mængden, ville listen enten skjule
redigerbare personer eller vise rækker uden editor-backing. RedPerson bærer i forvejen `born` (parset fra
`visning_foedt`, aldrig dødsår), så fødsels-sort krævede ingen ny data. `buildBrowse` blev derfor
generaliseret strukturelt (`BrowsePerson = {id,name,born}`) frem for at tvinge redaktøren over på model-
typen. **Fravalgt:** unify de to person-kilder upstream (unødvendig kobling; redaktøren har legitimt brug
for den rå liste til redigering). Kontrakten der holder id-rummene flugtende: redaktør-modellen loades
`collapse:false`, så model-person-id == rå RedPerson-id.

**Linje-chip filtrerer kun listen (afvigelse fra Følgesvend).** På Følgesvend hopper et linje-klik også
stamtræs-fokus til grenens stamfader. Redaktør-fladen har intet stamtræ, så chippen her *kun* filtrerer.

## Versionering + hyperlinks App-lag (2026-06-30)

**Escape-fix lagt på encode-siden (`makeToken`), ikke decode-siden (scanneren).**
Mit første fix-forsøg (H1) var at indsnævre scannerens backslash-gren til kun `\|[]`. Det løser
intet: `]` er legitimt eskaperet, så en ueskaperet trailing backslash sluger stadig afgrænserens
første `]` uanset hvor smal regex'en er — verificeret empirisk med en node-simulation af begge
varianter. Korrekt fix: eskaper `\` SELV i `makeToken`; scanneren forbliver uændret, fordi dens
ubegrænsede "backslash+næste-tegn=ét par"-logik er korrekt, NÅR encoderen garanterer at enhver
literal backslash altid er doblet. Generel læring: et escape-alfabet skal inkludere escape-tegnet
selv, ikke kun de tegn det beskytter.

**`reverteret`-status beregnes fra HELE historik-listen, ikke fra rækkens eget felt.**
`change_set.reverterer_id` på række R betyder "R fortrød hvilket sæt" — sat på det NYE
reversal-sæt, peger TILBAGE på det ORIGINALE. En original post X's eget `reverterer_id` forbliver
derfor NULL efter X er fortrudt. `mapHistRow` tager nu et `revertedIds`-sæt (alle `reverterer_id`-
værdier fra hele resultatet) som parameter, i stedet for at læse feltet direkte på hver række.

## Versionering + hyperlinks DB-lag (2026-06-30)

**`begin_change_set` wires i ALLE DML-skrive-RPC'er, inkl. de 4 opretter-RPC'er.**
Implementeringsplanens task-liste nævnte 17 RPC'er og udelod `red_opret_person/estate/kilde/
organisation`. Men `red_opret_person` kalder `red_upsert_fakta` nested — uden et change_set åbnet
i den YDRE opretter ville person-INSERT'en ikke logges, og de nestede kald ville åbne separate sæt
(spec-finding H1). Design-specens §6 ("Alle `red_*`") er den korrekte autoritet; planens liste var
en mangel. `red_suggest` (staging) og `red_slet_person_preview` (read-only) forbliver uwired.

**Restore-divergens-tjek dækker DELETE-inverse (ikke kun INSERT/UPDATE).**
Den optimistiske B9-kontrol skal sammenligne nuværende række mod den *post-state* sættet efterlod:
INSERT/UPDATE → `efter`, DELETE → SQL NULL (række skal være ABSENT). Den oprindelige plan-kode
tjekkede kun INSERT/UPDATE, så en genbrugt PK efter en sletning kunne overskrives blindt ved
fortryd. Dual-review-fund H1; rettet.

**`_version_upsert_row` lister kun snapshot-kolonner i INSERT/SET.**
Snapshot udelader skip_cols (`person.visning_*`, `profiles.email/rolle`). `(jsonb_populate_record).*`
ville sætte dem NULL ved restore → `profiles.rolle NOT NULL`-crash, og NOT NULL-tjekket fyrer FØR
ON CONFLICT-arbitrering, så det rammer selv ved UPDATE-restore af eksisterende række. Fix: eksplicit
kolonne-liste fra snapshot-nøgler → skip_cols får DEFAULT ved insert, bevares ved update. Dual-review
H2 (opgraderet fra LOW). Cache (`visning_*`) regenereres separat efter restore.

**TOCTOU i restore deferret bevidst.** `_version_current_row`-tjek + inverse-DML er ikke atomiske.
Acceptabelt under single-writer PoC (samme threat-model som `max(id)+1`-id-tildeling, spec §4.6);
genåbnes ved flerbruger-skrivning.

## TNG-QA: tre kerne-valg i match + QA (2026-06-30)

**Auto-tier = ambiguitets-margin, ikke `unique_block`.**
Næsten alle i basen hedder "Reventlow", så `unique_block` ("ene plausible navne-kandidat")
er ALDRIG sand → auto var altid 0. Valgt: auto kræver at bedste kandidat er ≥
`ambiguity_margin` (0.05) foran nr. 2 (+ score≥cutoff + top-kandidat). Kalibreret mod
*bootstrap-ankre* (entydige eksakte matches) i stedet for et håndlabelt facit-sæt — bevidst
hurtig-start; ankrene er korrekte pr. konstruktion, så de validerer ikke præcision uafhængigt
(non-anker-auto øjen-kontrolleres i `calibrate.R`). Forkastet: sænke `unique_block`-strenghed
(ville ikke skalere med uniform efternavn).

**Dato-overlap tæller kun som scoring-evidens ved reel dato på begge sider.**
`intervals_overlap` returnerer TRUE når begge datoer er ukendte (NA→±Inf), så et middelmådigt
navne-match fik 0.3 "gratis" vægt og kunne auto-promoteres på navn alene (fx forskelligt
efternavn, ingen datoer). `.overlap_evidence` kræver dato på begge sider. Konsekvens: auto
kræver reel fødselsårs-korroboration (navne-only maxer på 0.7). Bivirkning: dato-løse
nr.2-kandidater taber vægt → større margin → flere entydige auto (273→347).

**GDPR PII-gate = INPUT-gating, ikke output-gating.**
Filtrér ALLE sammenlignings-input (vores + TNG) til afdøde-ikke-private FØR sammenligning, så
ingen levende person kan komme ind i `disc` — heller ikke som relateret 2.-endepunkt. Reducerer
garantien til én kontrollerbar invariant frem for "hver refereret id på hver række blev tjekket".
KRITISK: TNG-siden filtreres OGSÅ (ellers navngiver `mangler_hos_os` en levende ægtefælle til en
afdød). Fail-closed på ukendt privacy. Forkastet: output-filtrering af `disc` + tekst-scan
(`assert_no_living_pii`) som primær — degraderet til backstop (svækkes når id'er → labels).

## Opret: privat FORCERET true + sted udskudt (2026-06-29, hærdet 2026-06-30)

**Ny person oprettes med `privat=true` — IKKE konfigurerbar ved opret.**
RLS-reglen `levende=false AND privat=false` gør personen anon-læsbar. En glemt levende-toggle
ville ellers publicere en nulevende person umiddelbart ved opret. Frem til cycle-08 var `p_privat`
en parameter med default `true`, men en crafted kald med `p_privat=false` kunne omgå beskyttelsen.
**cycle-08 (2026-06-30):** `p_privat`-parameteren fjernet helt — `INSERT` hardkoder `privat=true`.
Gammel 7-arg signatur DROPpet; ny 6-arg erstatter. Synlighed skiftes udelukkende via
`red_set_privat`. Ansvaret for synlighed placeres dermed eksplicit hos redaktøren.

**Gods-sted udskudt.**
`EntitetPicker` understøtter kun organisation/estate, og `redaktionAux` har ingen `placeListe`.
En sted-picker til gods kræver ny aux-datasektion og ny picker-komponent — ikke i scope for PoC.

## Plan 2C-2b: redigerbar familie-sektion — 5 nøgle-valg (2026-06-29)

**`red_slet_familie_link` sletter aldrig `family`-entiteten (Codex H1).**
`family`-tabellen bærer i gennemsnit 276 facts og 700 notes i nuværende load. Disse binder via
`(target_type='family', target_id)` — polymorfisk, ingen FK, ingen cascade-constraint. En
sletning af family-rækken ville efterlade al evidens forældreløs. RPC'en sletter KUN
`family_member`-rækkerne. En tom family (ingen members) er bedre end orphaned evidens;
fjernelse af en tom family kræver eksplicit audit og separat RPC.

**Ingen auto-dedup af unioner i `red_opret_union` (Codex H2).**
Et par (A, B) kan logisk have to selvstændige ægteskaber (fx skilsmisse + gengifte). En
pair-dedup (`WHERE partner_a=X AND partner_b=Y → returnér eksisterende family_id`) ville flette
børn og ægteskabs-events fra to distinkte tidslinjer ind i ét family-objekt. RPC'en opretter
ALTID en ny family-entitet + 2 partner-links. Ansvaret for at identificere et allerede
eksisterende ægteskab og vælge det korrekte family-objekt ligger i UI-laget / redaktøren.

**Cyklus-guard + selv-forælder-afvisning i `red_tilfoej_barn` (Codex H3).**
To separate afvisninger i RPC-laget (SECURITY DEFINER, ikke kun klient-lag):
(1) Selv-forælder: `p_barn_id` == en af familiens partnere → RAISE.
(2) Cyklus: recursiv CTE traverserer opad i slægtstræet fra `p_barn_id`; hvis nogen ane == en
af familiens partnere → RAISE.
Begge afvisninger er nødvendige i databaselaget — klient-side-guard alene kan omgås ved
direkte RPC-kald.

**`fetchPersonFamilie` separat fra `redaktionAux`.**
`redaktionAux` sammensætter familie-visningen til display (formaterede listestrenge), men
eksponerer hverken `family_member.konfidens` eller primærnøglerne (`family_id` + `person_id`)
som slet- og konfidens-kaldene kræver. Separat fetch mod `family_member`-tabellen var den eneste
korrekte løsning — omskrivning af aux-kontrakten ville bryde resten af editoren. Analogt med
2C-2a's valg af separat `fetchPersonRelationer`.

**Era-validering: klient-side advar-og-tillad.**
`eraAdvarsel` er en blød advarsel, ikke en hard-reject. Begrundelse: 27 af de eksisterende
familie-links i databasen er historisk inkonsistente (era-fejl fra DAA-parseren) — en
hard-reject ville blokere korrekt redigering af disse poster. Redaktøren modtager advarslen,
bekræfter og fortsætter. Hard-reject forudsætter at alle 27 era-fejl er rettet i basen.

**Live RPC-deploy + rollback-tests + manuel e2e er controller-gated.**
Samme model som tidligere plans: bruger-OK + backup (R/RPostgres) inden DDL kører mod prod.
App-siden er komplet og testet (121/121 jest, tsc rent); RPC'erne eksisterer endnu ikke i prod.

## Plan 2C-2a: redigerbar sektion-relationer — scope + nøgle-valg (2026-06-29)

**Redigerbart scope: kun relation-baserede hverv/godser; familie og kilder read-only.**
Familie (family_member) og kilder (external_id) er udeladt af 2C-2a. Familie-redigering
kræver separat semantik (opret familie-enhed, kobl forælder/barn, håndtér
`family_member.konfidens`) og er udskudt til plan 2C-2b. Kilder (external_id) kræver
opret-flow for nye source-entiteter. Begge deferred = bevidst scope-grænse.

**Separat `fetchPersonRelationer` frem for genbrug af `redaktionAux`.**
`redaktionAux` eksponerer relationer som formaterede listestrenge uden `relation.id`.
Slet-kaldet (`red_slet_relation`) kræver præcist `relation_id`. En separat pagineret
fetch (direkte mod `relation`-tabellen, filtreret på `subjekt_id`) var den eneste
korrekte løsning — genbrug af aux ville kræve en destruktiv omskrivning af aux-kontrakten
der bryder resten af editoren.

**`red_slet_relation` skal FK-ordne evidens-slettelsen manuelt.**
`relation`-tabellen har intet ON DELETE CASCADE til sin evidens: `assertion`, `conclusion`,
`citation`, `note` binder på `(target_type='relation', target_id)` — polymorft, uden FK.
RPC'en sletter i rækkefølge citation → conclusion → assertion → note → relation for at
undgå forældreløse evidens-rækker. (~955 evidens-rækker er knyttet til relationer i nuværende load.)
Løsningen er bevidst SECURITY DEFINER + rolle-gated (anon → P0001) som de øvrige red_*-RPC'er.

**`red_tilfoej_relation` validerer objekt_type og eksistens + dup-guard.**
Validering af `objekt_type` mod tilladt sæt og eksistens af `objekt_id` sker i RPC'en
(ikke i app-laget) — nødvendigt for at undgå FK-violation + meningsløse relationer ved
klientfejl. Dup-guard returnerer eksisterende `relation.id` ved gentagelse (idempotent),
ingen dublet indsættes.

**Live RPC-deploy + rollback-test + manuel e2e er controller-gated.**
Samme model som tidligere DDL-deploys: bruger-OK + backup inden DDL kører mod prod.
App-siden er komplet; RPC'erne eksisterer endnu ikke i prod.

## Plan 2C-1: entitetslister read-only via udvidet buildAux (2026-06-28)
Redaktions-appens Entiteter-tab viste kun personer (2A). 2C-1 gjorde den til en type-menu med
read-only lister over de øvrige entiteter.

**Ikke-oplagte fund/valg:**
- **RPC-fladen er person-centrisk.** Ingen write-RPC for source/organisation/estate/media/coat_of_arms
  → 2C-1 er nødvendigvis read-only; entitets-redigering kræver nye RPC'er (= 2C-3).
- **Datakilde: udvidet `buildAux`, ikke separate fetches.** De fire lister (kilde/org/medie/gods)
  kommer fra de rå arrays buildAux allerede modtager → ingen ekstra fetch. Kun `coat_of_arms` er nyt.
- **`majorat` er ikke en entitet** — det er en `slags` af `estate` (len/stamhus/lensgrevskab) og er
  dermed i gods-listen. (estate.slags er desuden NULL på alle 229 rækker nu.) Promovering til egen
  entitet = fremtidigt model-arbejde (jf. lineage-promoveringen).
- **`coat_of_arms` (våben) FINDES** — Codex fangede en fejlpåstand om at tabellen manglede; våben
  inkluderet.
- **Auth-state-kontrakt:** lister/menu skelner rolle≠redaktion ("Kræver redaktør") fra load
  ("Henter…") — ellers permanent "Henter…" for ikke-redaktører (Codex).

## Plan 2B: separat redaktion-MODEL frem for per-person re-derivation (2026-06-28)
Person-editoren lænede sig på den delte anon-model (893, uden levende) → "ikke fundet" for de 70
levende som 2A nu når. Det oprindelige design var en per-person `fetchRedaktionPerson(id)` der
re-deriverede familie/sektioner.

**Codex-review afslørede at re-derivationen ville DIVERGERE** fra den faktiske logik:
`buildModel` chrono-filtrerer umulige forælder-barn-kanter + vælger første fødselsfamilie;
`buildAux` klassificerer hverv som BÅDE organisation OG `historical_event` med specifik
format/sort. En forenklet re-implementering ville vise andre (flere/umulige) forældre og mangle
hverv ift. publikums-visningen.

**Beslutning: SEPARAT REDAKTION-MODEL.** Load én ekstra fuld model via redaktion-sessionen
(`loadFromSupabase({includePrivat:true})` → `buildModel`), gemt i en adskilt store-slice. Editoren
bruger de EKSISTERENDE selektorer/aux uændret → ingen divergens, pagination gratis (getAll), al
derivation genbrugt. Publikums-faner bruger uændret den offentlige model (ingen GDPR-læk).

**Konsekvenser:**
- To modeller side om side (offentlig 893 / redaktion 963). Lazy-loadet ved rolle=redaktion.
- `AppPerson.privat` tilføjet (toggle-init); `loadFromSupabase` får `includePrivat`-param.
- Narrativ-privat-fix (`fetchPersonNarrativ` = skrive-mål + bevar privat) — `red_upsert_narrativ`
  redigerer første narrativ uanset privat, så prefill skal læse SAMME række.
- Kun køn redigerbart i 2B; familie/sektion read-only (relations-redigering = 2C).

## Plan 2A: separat redaktion-person-fetch + pool-baseret søg (2026-06-28)
Redaktions-appen manglede in-app-navigation til personer (konflikt-køen tom efter kardinalitets-fix,
entitetslister stub) → man tastede URL → web-reload → skrivemode nulstillet. 2A gav Entiteter-tab'en
en person-liste.

**Ikke-oplagt valg: SEPARAT `fetchRedaktionPersoner` frem for genbrug af den delte model.**
Den delte publikums-model filtrerer `privat` ud (`load.ts:103`) OG loades ved boot som anon (kun
offentlige). Genbrug ville enten skjule levende/private for redaktøren ELLER (ved reload-med-private)
lække dem til publikums-fanerne (samme model). Separat fetch (RLS-gated, inkl. levende/privat) holder
GDPR-grænsen ren. Verificeret: redaktion ser 963, anon 893.

**Konsekvenser:**
- `buildSearch` → pool-baseret `searchPool` (DRY; publikum + redaktion deler søg/alfabet/sort-logik).
- Pagination obligatorisk (`getAll`/`.range`) — PostgREST capper ved 1000 lydløst (Codex 2A H1).
- `RedPerson.born` direkte fra visning_foedt, ikke aar-strengen (ellers dødsår-som-fødeår, Codex 2A M1).
- Tag på liste-rækker = `levende || privat` (de 70 skjulte er levende, ikke manuelt-private).

## Fact-kardinalitet: flere facts pr. (person, faktatype) er korrekt, ikke konflikt (2026-06-28)
Bruger-feedback under live-test: person 199 viste kun 1 titel, og konflikt-køen flagede
"6 uenige titel-værdier". Data-tjek: personen har **6 separate titel-facts** (kammerjunker,
konferensråd, kammerherre, gehejmeråd, gehejmekonferensråd, landråd i Holsten) — alle
legitime titler båret gennem livet, ikke konkurrerende påstande om samme forhold.

**Beslutning: en person kan have N facts af samme faktatype, og det er den korrekte model.**
Konsekvenser, rettet:
- **`red_konflikt`-view:** grain ændret fra `(person, faktatype)` til **pr. fact** — ægte
  konflikt = >1 distinkt assertion-værdi INDEN FOR ét fact (to kilder uenige om samme forhold).
  Efter rettelsen: 0 konflikt-rækker i nuværende load (alle facts har én oplysning) — den
  gamle kø var 100% falske positiver.
- **`joinEvidence` / person-editor:** `PersonEvidence.felter` er nu `Record<felt, FeltEvidens[]>`
  (liste pr. felt). Editoren viser ét kort PR. FACT under en felt-overskrift (titel → 6 kort).
  Tidligere overskrev `joinEvidence` pr. felt → kun det sidste fact var synligt.

**Write-side (løst 2026-06-28):** to nye RPC'er adskiller de to operationer som
`red_upsert_fakta`'s find-or-create blandede sammen:
- `red_tilfoej_oplysning(p_fact_id, …)` — operation A: ny oplysning til ET specifikt fact
  (per-kort "+ Tilføj oplysning"). Rører ikke conclusion (kandidat; vælg med red_set_konklusion).
- `red_opret_fakta(p_subjekt_type, p_subjekt_id, p_faktatype, …)` — operation B: ALTID nyt
  distinkt fact (sektion-knap "+ Ny titel"). Tillader flere facts pr. faktatype.
`red_upsert_fakta` (find-or-create) beholdes for R-load/bagudkomp, men UI bruger den ikke mere.

## Redaktions-UI: vertikal kerne-skive + 3 ikke-oplagte DB-valg (2026-06-27)
Redaktør-appens UI bygget som **vertikal kerne-skive** (dashboard + person-editor + konto +
3 sheets), ikke hele handoff-designet. Entitetslister, generisk record-editor, opret-flow og
relations/sektion-redigering udskudt til plan 2 — kerne-skiven validerer hele evidens-skrive-stien
end-to-end hurtigst. Køn-editor + familie/sektion-visning også udskudt (spec §6.2 ikke fuldt
indfriet; bevidst nedskaleret, bruger-godkendt).

**Tre ikke-oplagte DB-valg (Codex-review fangede dem som spec-fejl før impl):**
1. **`red_konflikt`-view kræver `security_invoker=true`.** Et alm. PostgreSQL-view kører med
   ejer-rettigheder og **omgår RLS** på fact/assertion → ville lække private personers konflikter
   til anon/medlem. security_invoker arver kalderens RLS. (GDPR, invariant #8.)
2. **Redaktion-read-RLS er nødvendig, ikke valgfri.** Den eksisterende `auth_read`-policy skjuler
   private rækker for ALLE authenticated. Uden en redaktion-specifik policy ville en redaktørs egen
   privat-toggle gøre personen usynlig for hende selv ved næste re-fetch (kan ikke ophæves). Løst med
   policy gated på `current_rolle()='redaktion'` (ikke `using(true)` — bevarer medlem-GDPR-laget).
   **Konsekvens:** en redaktør har fuldt indsyn i ALLE nulevende — bevidst privacy-udvidelse for rollen.
3. **Slet-advarsel skal hente indgående OG udgående relationer.** `red_slet_person` sletter
   relationer hvor personen er subjekt ELLER objekt, men app-modellen (`load.ts`) henter kun subjekt.
   Egen `red_slet_person_preview`-RPC spejler RPC'ens slette-logik 1:1, så advarslen ikke underrapporterer.

**Blød/mutabel assertion bevaret** (arvet fra 2026-06-26-spec): redigér=UPDATE, slet=DELETE bryder
invariant #1 (uforanderlighed), men er bevidst PoC-valg m. reversibel migrationssti i RPC-kroppen.

## Slægtslinje promoveret til entitet `lineage` — (a) nu, (b) senere (2026-06-23)
Linjer var bare et `linje`-label på `person_external_id`. Et label kan ikke bære navn,
våben, adlingsdato eller forgrening. CLAUDE.md §9 + datamodel-oversigt §5 forhåndsgodkendte
en promovering ("kan promoveres hvis branch-niveau-udsagn ønskes"); behovet for navne
(og i andre slægter: linjer der adles → nye adelsfamilier) udløser den.

**Valg: minimal entitet nu, ikke fuld udbygning.** `lineage` oprettes med kun
`(id, source_id, kode, navn)` — trin (a), navngivning. Bevidst IKKE bygget endnu:
`parent_lineage_id` (forgrening), `status`, `fact subjekt_type='lineage'` (adling/floruit/
alternative navne m. evidens), `relation` til våben/kilde/person. Det er trin (b).

**Hvorfor det ikke bryder invariant #2** ("nye behov = rolletyper, ikke tabeller): en
linje er en ny *slags ting* med egen identitet, ikke en ny måde at forbinde på. Label-
løsningen brød netop sammen ved "adlet gren → ny familie".

**Hvorfor (a) ikke maler os i et hjørne:** (a) skaber SAMME tabel som (b) bruger, bare
med færre kolonner. (b) er ren `ALTER ADD COLUMN` + nye relationer — nul rename, nul
data-migration. Det rå `linje`-token på `person_external_id` bliver liggende som join-nøgle
og proveniens (mapper til trykt side). Backfill udleder `source_id` fra data, så den binder
til den faktiske DAA-source uanset id. App falder tilbage til `Linje {kode}` hvis navn mangler.

## boern udledes deterministisk; boern.linje er IKKE JSON-linjen (2026-06-17)
Børne-referencer ("3 børn: Tiende slægtled, II, nr. 31-35") parses deterministisk i
`validate.py` (`derive_boern`), ikke af LLM-trinnet — LLM'en missede dem systematisk
(Codex-udtræk: kun 38/123 fanget). Teksten er regulær; deterministisk kode er fejlfri.

**aegteskaber-udtræk er stadig LLM (åben):** Modsat boern parses ægteskaber af
LLM-trinnet — og det misser ~9% (26/288 poster har "Gift" i narrativ men tom
`aegteskaber`, fx V-106 Christian Benedictus' ægtefælle Sophie Pauline Schjær).
Børn loades alligevel (deterministisk boern), men deres familie får ingen partner.
**Anbefalet fix:** løft ægteskabs-klausulen til deterministisk parsing i `validate.py`
(som boern). Klausulen er regulær ("Gift [dato] [sted] med Navn (F.: forældre),
* fødsel, † død") men rigere end boern (ordinaler, 1°/2°, skilsmisse, b.v.,
ægtefælle-forældre) → mere regex-arbejde. Ikke implementeret.

**Kryds-gren-tvetydighed (åben):** Romertallet i børne-ref ("…, II, nr. 31") er bogens
INTERNE gren-tæller i slægtleddet, IKKE JSON-linjen (I-V). Det matcher JSON-linjen ~85%,
men `nr` genbruges på tværs af 133 linjer, så i 145 tilfælde findes barn-nr i BÅDE
"stated" og forælder-linje. Loaderen (`load_daa.R`) vælger stated først → 97 verificerede
fejl (stated-kandidat historisk umulig, hundreder af år fra forælder), 38 ægte kryds-gren
(stated korrekt), ~10 uklare. **Anbefalet fix:** era-baseret tie-break — afvis stated hvis
kandidatens fødselsår er >80 år fra forælderens; ellers behold stated. Påvirker kun ældre
linjer I/III (Reventlow-hovedlinje V er entydig). Ikke implementeret endnu.

## Import: DAA-PDF først, TNG kun enrichment (2026-06-15)
Databasen bygges fra den trykte DAA (autoritativ, kohærent kilde), ikke fra TNG-dumpet
(25k personer, blandede tredjeparts-kilder → ville forurene grundlaget). TNG bliver
senere "flere påstande fra en svagere kilde"; konklusionslogikken foretrækker DAA.
Hver DAA-udgave = én `source`; identitetssammenkædning pragmatisk i PoC.

## Selektiv struktur — kun genealogisk rygrad (2026-06-16)
Rygrad = navn/titel/fødsel/dåb/død/begravelse/floruit/ægteskab/forældre-børn/godser/
adling/dekoration. **Erhverv + uddannelse er IKKE rygrad** — de ligger i prosaen
(narrativ for nummererede personer; bio-note for ægtefæller uden post). Begrundelse:
de forbinder ikke entiteter og driver ikke træet (§6). Overvejet/forkastet: strukturere
karriere som fakta for alle (kræver dyrt re-udtræk, lille genealogisk gevinst).

## Titel ≠ navn; flere navne-former = påstande (2026-06-16)
Titel ("Greve") er eget `titel`-fakta, aldrig bagt ind i navnet; display komponerer.
Samme person nævnt flere steder = flere navne-påstande; konklusion vælger kanonisk.
Relative datoer (s.å./s.m.) opløses til ISO ved udtræk, rå tekst bevaret.

## Bulk-insert frem for row-by-row (2026-06-16)
Loaderen akkumulerer i hukommelsen og skriver per tabel med dbAppendTable/COPY i
FK-rækkefølge. Row-by-row over session-pooleren var både langsomt (30+ min) OG
skrøbeligt (forbindelsen droppede → rollback). Bulk = ~14 sek + kort transaktion.

## Load-laget som deterministisk normaliserings-trin (2026-06-16)
Kategoriserings-/dedup-regler (estate-dedup, child-linje-fallback, akademisk-grad-
klassificering) anvendes ved load på hele datasættet i én 14-sek reload — frem for
dyrt LLM-re-udtræk. Udtrækket fanger rå-værdien; loaderen pålægger struktur.

## Model-tier: Sonnet til udtræk; Haiku afprøvet (2026-06-16)
Sonnet til stamtavle-udtræk (klarer tredjeparts-fælder, dense biografier). Haiku
testet: rammer genealogisk rygrad tæt, men taber på klassifikations-nuancer (karriere
vs embede) og er flakier. Forkastet for fuld kørsel efter clobber-fejl; egnet til
billig broaden HVIS isolerede output-mapper + terse output.

## Identitetssammenkædning: `samme_som`-relation + collapse i app (løsning A) (2026-07-02)
Samme fysiske person kan optræde som FLERE person-poster: (a) slægtslinje-
grundlæggere står i DAA to gange (oprindelses-linje + som rod af egen linje, fx
Conrad de Reventlow III-58/V-1, Detlef IV-1/III-104); (b) indgiftede der har egen
slægt et andet sted (fx Beke Ahlefeldt-Laurvig: ægtefælle-stub i Reventlow NU,
barn af Julius Ahlefeldt i kommende Ahlefeldt-import).

**Valg: LINK, ikke merge.** En `samme_som`-relation (person→person, evidenslag)
forbinder posterne; begge DB-rækker bevares (proveniens + fortrydbart, datamodel
§9). Frontend COLLAPSER dem via traversal → brugeren møder ÉN person (én søgetræffer,
én person-visning der samler begge posters fakta/relationer, én knude i
slægtskabsfinderen). Applied durabelt i post_load_fixup.R (reload-sikkert, opslag på
linje/nr). Samme mekanisme dækker begge tilfælde — men betydningen adskiller sig:
grundlægger = redundant dublet at skjule; indgiftet-med-egen-slægt = én person i TO
slægter, hvor collapse tegner selve kryds-slægt-broen ("er vi i familie?").

**Status (2026-07-02): frontend-projektionen IMPLEMENTERET (web+mobile).** Ren funktion
`collapseSameAs` folder de linkede poster til én kanonisk FØR `buildModel` (motoren urørt),
valideret + reversibel (karantæne ved konflikt). Se changelog + `docs/reviews/16`+`17`.
Dual-reviewet (Claude+Codex); empirisk valideret mod prod (Conrad/Detlef folder rent).

**Udestår:** (1) Automatisk detektion i skala via crosswalk/matching når nye slægter
importeres (manuel linking kun til få kendte tilfælde nu; crosswalk er for støjende til
bulk uden injektiv matcher). (2) Kryds-slægt-broer (Beke-typen) — kræver server-side
privacy-klasse før de kan foldes i publikums-web/mobile (spec §9). (3) Manuel skærm-
verifikation (Expo-simulator + web-browser).

## Reload-strategi + durable post-load-fixup (2026-07-02)
DAA-basen genindlæses med `load_daa.R --reset` (fuld TRUNCATE+rebuild), IKKE append
(append dublerer hele basen — id'er allokeres fra MAX(id)). RESET-guarden afviser dog
`--reset` mod en base med redaktionelle `change_set`-rækker; `--force-reset` tilsidesætter
bevidst (sletter dem). **Læring fra data-tab-hændelse (2026-07-02):** en TRUNCATE CASCADE
rammer også `profiles`/`lineage`/`suggestion` (FK-kaskade), og enhver hånd-applyet live-edit
(lineage-navne, redaktør-profiler, `samme_som`-links) går tabt ved næste reload. Derfor:
efter-load-korrektioner der ikke bor i loaderens automatiske pipeline SKAL ligge i et
committet, idempotent `post_load_fixup.R` med par-/entitets-opslag på reload-invariante nøgler
(linje/nr, ikke person-id). Alternativ (differentiel upsert-loader der bevarer redaktionelt
arbejde) er afvist for nu — større arbejde, egen OpenSpec. **Verificeret:** reload → 922
personer, TNG-QA manglende links 125→10.

## TNG-funktionalitet: prioritering af backlog (2026-07-03)

Efter fuld gennemgang af familiens TNG-dump (`jr_tng_reventlow.sql`, se
`docs/tng-reventlow-analyse.md`) er fire opfølgningspunkter prioriteret:

- **DNA-slægtskabsdata: AFVIST**, ikke udskudt. Ingen ny tabel/faktatype/relation
  til Y-DNA/mtDNA/centiMorgans/DNA-matches bygges, selvom familiens TNG rummer 20
  reelle test og "er vi i familie?" er kernefunktionen. Fravalgt af bruger uden
  begrundelse påkrævet — lukker sagen, ingen genåbning uden eksplicit ny anmodning.
- **Foto/medie-rigdom (region-tagging à la Facebook-tagging, albums, event-scoped
  medielink, geokodning+proveniens på medier): UDSKUDT SAMLET.** Ønsket, men skal
  designes som én sammenhængende medie-arkitektur-beslutning, ikke fire spredte
  enkelt-features. Ingen implementering før den samlede session.
- **Gemte rapporter/smart-lister: NÆSTE FOKUS.** TNG-familien har 193 reelt brugte
  brugerdefinerede lister — det eneste §7-punkt med både stærk evidens for værdi OG
  eksplicit bruger-interesse nu. Implementeres som parametriserede forespørgsler i
  app-koden (ikke TNG's rå `sqlselect`-tekstfelt — SQL-injektions-mønster).
- **Navnekomponentering (adelspartikel "von"/"af", jf. TNG `lnprefix`): UDSKUDT.**
  Ikke afvist, men ingen ændring af navne-som-fri-tekst-i-assertion før videre
  overvejelse.

**Nyt, ikke-designet krav rejst i samme samtale: flersproget stamtræ** (tysk,
svensk, norsk, engelsk). Ikke en del af TNG-analysen — et selvstændigt fremtidigt
scope-punkt. Rejser ubesvarede spørgsmål (UI-i18n vs. indholds-i18n; hvor
oversættelse lander i evidenslaget; hvad der sker med `narrative`s ordret-prosa-
invariant på tværs af sprog) der kræver egen brainstorm, ikke besvaret her. Se
`docs/tng-reventlow-analyse.md` §8.

## Generation som kolonne, ikke fact; hul-reparation skriver aldrig (2026-07-05)

- **Slægtled = strukturel bog-koordinat pr. udgave** (som `nr`/`linje`), IKKE en omstridt
  påstand → plain kolonner på `person_external_id`, ikke evidenslag. Følger præcedensen
  `lineage.slaegtsnavn` (bevidst kolonne-ikke-fact). To tal fordi bogen selv nummererer
  dobbelt ("Første (tolvte)"): lokalt i linjen + gennemgående gennem moderlinjen.
- **Fallback-ringen er en ren read-time projektion.** En generations-nabo er en UBEVIST
  kandidat; at vælge den re-ankrer (navigation), og der oprettes ALDRIG en `relation`-kant.
  Fail-closed founder-hop (præcis ét moderlinje-mål, ellers ingen ring) frem for at gætte.
  Dual-review bekræftede invarianten på begge platforme.
- **Join-nøgle `(source_id, linje, nr)`** — `nr` resetter pr. gren (ikke globalt); NULL-linje
  karantænes. Backfill fail-closer på tvetydigt source-valg (TNG-source id 2 har 0 Roman-linjer,
  så DAA-source 1 resolves entydigt).

## Mediehåndtering: dokumenter/PDF/tekst-transskription — samme fundament, egen fase (2026-07-19)

Bruger-rejst behov: indscannede kilder (PDF/scanning, fx avisartikel om en person) +
artiklens rå tekst til læsbar visning/søgning; teoretisk også lyd/video.

- **Besluttet: samme media-system, IKKE et separat dokument-system.** `media` er
  allerede format-agnostisk (`mime_type`/`byte_size`/`slags`; vocab har `'scanning'`;
  `bredde`/`hoejde` nullable), og hele forvaltningsapparatet (rettigheds-workflow,
  gating, blødt slet/genopret, versionering, filside, bibliotek/køer) er
  format-neutralt — et separat system ville duplikere det hele. Kun klient-laget er
  billede-specifikt (variant-pipeline, Lightbox, `accept="image/*"`).
- **Transskription = narrativ-på-media** (`narrative` er allerede polymorf) —
  Wikisource-mønsteret: scanning + fts-søgbar læsetekst koblet 1:1. ⚠ Egen
  GDPR-designrunde påkrævet før implementering: tekst om (potentielt levende) person
  skal arve mediets afbildet-gating fail-closed.
- **Tilføjet som fase 5** i mediekonceptet (`docs/design/2026-07-19-mediehaandtering-robust-koncept.md`
  §4.8 + §9); uafhængig af fase 3–4. Lyd/video: kun "døren åben" (mime_type bærer
  dem), intet bygges før konkret behov.
- **Eneste konsekvens for fase 2 (biblioteket), indskrevet i spec'en:** defensiv
  rendering — ikke-billede-mime/manglende thumb → dokument-ikon, aldrig knækket
  thumbnail; udeladt af Lightbox.

## Levende feed fase 4 (LLM-assist): udskudt, ikke annulleret (2026-07-20)

Fase 3 (minihistorier & redaktionel styring) er kode-komplet på `main`. Fase 2+3-
skemaet (`haendelse`/`story`/`story_kilde`/`feed_pin`) blev deployet til prod samme
dag (se sektionen nedenfor) — men det ændrer ikke fase 4-vurderingen: Fase 4
("Foreslå historie"-Edge Function + proveniens, koncept §8+§10) sættes bevidst i
bero før spec-arbejdet påbegyndes.

- **Begrundelse:** PoC-korpusset har for få kilder indlæst til at LLM-assist giver
  reel værdi endnu, og scopet (Edge Function, kontekst-sammensætning på tværs af
  udgaver, proveniens) er for detaljeret at kaste sig over nu.
- **Ikke tabt arbejde:** rammen ligger allerede i koncept §8 (teknisk ramme) og
  fase 3-design §12, som bevidst efterlod ○b (hændelses-gruppering på tværs af
  udgaver) og ○c (skal `historie`-kort vise AI-oprindelse) åbne til fase 4. `story`
  har allerede `llm_model`/`llm_promptversion`/`llm_naar`-kolonner (forward-compat,
  ingen ny migration nødvendig ved genoptagelse).
- **Genoptages** når kilde-korpusset er vokset nok til at hændelses-mængden
  retfærdiggør redaktionel LLM-hjælp — ingen fast dato.

## Levende feed fase 2+3 prod-cutover: skema nu, hændelsesudtræk senere (2026-07-20)

Bruger vil have fase 2 (`haendelse`) + fase 3 (`story`/`story_kilde`/`feed_pin`)-skemaet i
prod. Fase 2's offline LLM-hændelsesudtræk (narrativ → `haendelse` via `daa-haendelser`-
skillen) er derimod aldrig kørt — hverken lokalt eller mod prod.

- **Besluttet: adskil skema-deploy fra dataudtræk.** Skemaet (tabeller/RLS/RPC'er) kræver
  ingen LLM-kørsel og er harmløst tomt — feed-motoren degraderer bevist gracefult til
  fase 1-adfærd (`packages/feed/src/pool.ts:32-44`), og `story` kræver ikke et
  `haendelse_id`-anker. Runbook:
  [`levende-feed-fase2-3-runbook.md`](levende-feed-fase2-3-runbook.md).
- **Opdatering samme dag:** skemaet blev deployet til prod 2026-07-20 — ikke via den
  forberedte `psql`-runbook, men direkte via Supabase MCP fra en parallel session
  (`docs/database-current-state.md` §3). Bundlingen med mediehåndtering fase 1+2 (næste
  punkt) indtraf som forudsagt. `db-rollback-fase2.sql`/`db-rollback-fase3.sql` fra
  runbooken er stadig relevante som rollback-beredskab.
- **Hændelsesudtrækket udskydes fortsat bevidst**, samme begrundelse som fase 4 (PoC har
  for få kilder til at retfærdiggøre en LLM-batch-kørsel over hele korpusset endnu) — men
  noteret eksplicit som en kommende opgave, ikke annulleret.
- **Bifund:** `db-migrations.sql`/`db-rls.sql` er monolitiske kumulative filer, så en
  fase 2+3-cutover bundler mediehåndtering fase 1+2-skema (samme filsektion, interleaved) —
  se runbookens ⚠-afsnit.

## Replay-dagen: fire beslutninger fra første ægte prod-replace (2026-07-31)

Hele replay-kæden (design → implementering → to skarpe prod-kørsler) landede på én
dag. Fire beslutninger med varig virkning:

- **De 48 unummererede genbruger identiteter — mint kun for beviseligt identitetsløse.**
  Sols fail-closed-stop afslørede at de "48 nye" stamfædre/oversigtsposter allerede
  havde parkerede registeridentiteter (legacy-lokatorer). Mint ville have skabt
  dublet-identiteter; i stedet om-nøgledes lokatorerne (#120-mønstret). Alternativet
  (mint + senere sammenlægning) blev forkastet: registerprincippet er "id mintes ÉN gang".
- **Strukturelle bortfald tombstones IKKE før prod-oprydning.** De 23 legacy-identiteter
  hvis person i v2 ligger i samleposter forbliver AKTIVE som "bortfaldne" — replace-
  designet lader bortfaldne bestå urørt, mens tombstone ville udløse loaderens
  tombstone-guard og blokere alle fremtidige replaces indtil prod-personerne er
  håndteret. Tombstone + oprydning er en senere samlet redaktionel operation.
- **Kildetekst-strategi for 1939: struktur fra raw, prosa fra Calamari.** De unummererede
  poster kan kun findes i raw.txt (centreringsinfo); Calamari-teksten giver bedre
  narrativ-kvalitet. build_1939_v2 kombinerer (415 Calamari / 131 raw) med krydstjekket
  match — hverken ren-raw eller ren-Calamari kunne levere begge dele.
- **Ny-klassen i --replace (replay-udfald 4).** Registerkendte record_keys uden
  prod-person oprettes ad append-vejen; hullet-guarden består for nøgler uden hverken
  prod-person eller artefaktpost. Aktiveret af mint-arbejdet; sol-reviewet GO.

Driftslæring: delt-workdir-racen ramte igen (anden session skiftede branch under en
kørende terra-batch) — stoppet, karantænet, genkørt med selektivt valideret genbrug.
Parallelle sessioner bør bruge git worktrees.

## Union-redigering + identitets-invarianter (2026-08-01)

- **`red_slet_union` bygget og derefter droppet.** Funktionen krævede referentiel
  integritet i en model der bevidst ikke har fremmednøgler på polymorfe referencer.
  Hver rettelse skubbede kravet videre ud: rækkelås → ni tabellåse → en fælles
  låseprotokol på tværs af loadere og RPC'er. Og racet kunne ikke lukkes med låse
  overhovedet — en ventende `red_suggest` fortsætter EFTER sletningens commit.
  Værdien var samtidig nær nul: de 15 mor-løse 1939-skaller kan **ikke** slettes
  alligevel, fordi bogens oprindelige forældrepåstande peger på dem (familie 726 er
  refereret 14 steder). Skallerne er ikke affald, men evidens der har mistet sin krop.
  Alternativet (byg en tombstone-/valideringsmekanisme) er selvstændigt arbejde.
- **Invarianter i triggere, ikke i RPC'er.** To-parts-loftet og identitets-guardsne
  ligger på `family_member` og `relation`, ikke i `red_tilfoej_partner`. En RPC-tælling
  dækkede hverken fortryd-stien (`_version_upsert_row` skriver rækker direkte tilbage)
  eller samtidige kald. Samme begrundelse som `enforce_samme_som_invariants` i sin tid.
- **Håndhævelsen skal være symmetrisk.** "Alias tilføjes som part nr. 2" og "to parter
  linkes bagefter som samme person" giver samme forbudte sluttilstand; med kun én guard
  afhang udfaldet af redaktørens klik-rækkefølge. Begge veje er nu spærret, i hver sin
  trigger.
- **`samme_som`-rolle og -endepunkter er uforanderlige.** Ændring kræver slet+genopret.
  Evidensen hænger på relationens stabile id, så en `UPDATE` ville genbruge en gammel
  kildehenvisning til en ny identitetspåstand. Alternativet (en `OLD`-ekskluderende
  graf-guard på UPDATE) blev forkastet: det ville tillade at en påstand skifter mening
  uden at skifte identitet.
- **Krydsracet mellem de to triggere er BEVIDST ikke lukket.** Advisory-låsen der ville
  lukke det inverterede rækkefølgen mod `load_daa.R` (loaderen tager EXCLUSIVE på
  `relation` og flusher `family_member` først, mens `red_samme_som` holder advisory-låsen
  og venter på `relation`) — en ægte deadlock-cyklus der kan abortere en hel load.
  Cyklussen kan ikke omarrangeres væk. Fuld lukning kræver BEGGE dele: låsen i
  `load_daa.R`/`load_presens.R`/`post_load_fixup.R` før deres `LOCK TABLE`, OG i
  partner-triggeren. Restrisikoen kræver to samtidige transaktioner og fanges bagefter
  af projektionen som karantæne, ikke som stille korruption — samme single-writer-
  antagelse som `red_tilfoej_barn`s cyklus-tjek allerede hviler på.

Review-læring: otte adversarial Codex-runder, og fundene skrumpede først da en
**funktion blev fjernet**, ikke da endnu en guard blev tilføjet — at droppe
`red_slet_union` lukkede tre HIGH på én gang. To gange rettede en Codex-rettelse ét
problem og skabte et nyt (alfabetisk låseorden inverterede projektets kanoniske orden;
advisory-låsen gav deadlock). Peer-review er ikke monotont forbedrende. Og
`get_advisors(security)` fangede efter deploy noget ingen af de otte runder så: to nye
`SECURITY DEFINER`-trigger-funktioner stod åbne for `anon` via Supabases default-grants.
Codex læser SQL; advisoren læser den kørende bases ACL.

## Grænsekontrollen ligger før materialisering, og massebekræftelse er droppet (2026-08-08)

**Placering.** Grænsekontrollen kræver eksakte, hash-låste spænd og skal ligge før
materialisering. Begge betingelser er opfyldt straks efter forankringen, så kontrollen
lægges der — ikke efter komponeringen, hvor en ugyldig rettelse er dyrere at kassere.
Efter materialisering er teksterne påstande, og påstande overskrives aldrig (invariant 1).
Første udgave hævdede at der kun fandtes ét muligt sted; det holdt ikke.

**Afløsning af accepteret evidens er forbudt i dag, og guarden skal ikke løsnes.**
`compose_human_evidence_bundle()` afviser at menneske-evidens erstatter en entry med
kandidater eller positiv proveniens. En grænserettelse ER en sådan erstatning, så fase 2
kræver én navngiven, autoriseret afløsningsoperation med eksplicit invalideringsgraf —
seks punkter, herunder stikprøve/audit og op til tre incidente grænser, fordi en flytning
ændrer begge nabospænd. Kandidat*formatet* kræver derimod ingen ny evidensart; det er
producent-neutralt. Formatet rakte, operationen manglede.

**Massebekræftelses-bunken er fjernet.** Den lovede at et hul var positivt bevist tomt,
herunder at der ikke var et trykt hoved i rå OCR's modsvarende stykke. Men det modsvarende
stykke findes ikke: et menneskeforankret Calamari-spænd er et delspænd inde i en
forekomst, mens dets `raw_structure_bridge` dækker hele den parrede rå-forekomst. **Målt:
0 af 352 forankrede spænd er spændpræcise; 349 er delspænd; kun 110 har en rå-bro.** Rå-
vinduet begyndte derfor at læse for sent i hvert enkelt tilfælde. Valgt løsning: drop
bunken, alle 446 grænser til individuel vurdering. Rå-kontrollen er ikke slettet men
**vendt** — et positivt fund er troværdigt, fraværet af et fund beviser intet — så den er
nu signalet `hoved_i_raa_ocr`. En spændpræcis kontrol via `align_renditions` er
forudsætningen for at genindføre en bunke. Afvist: at portere på Calamari alene, fordi det
er præcis den fejlmåde designet findes for.

**Revision 0 i fase 1 er tilsigtet.** Grænse-id bærer et revisionsnummer, men fase 1
ændrer aldrig et spænd, så der findes ingen anden revision. Bumpning og forældrekæde bygges
i fase 2 sammen med afløsningen. Reviewet kaldte det en spec-fejl; afgjort at planen gælder.

**Dagens gennemgående fejlmønster: fravær af bevis læst som bevis på fravær.** Otte
tilfælde. Sidemodellen der talte sider i stedet for at slå dem op; porten der kaldte et
ukontrolleret hul tomt; en opsummering hvor `har_broedtekst=0` slap igennem; et
injektivitetskald der udregnede sin egen godkendelseshash og dermed gjorde kontrollen
indholdsløs; et rå-OCR-vindue der ledte i den forkerte tekst; søskendegrupper bygget kun af
spænd-ejere, så `slugt_hoved` fyrede **0 gange** i et datasæt med fire kendte grænsefejl; en
tom kasse i UI'et der læstes som frikendelse; og kontekst der rakte ud over spændets kant
uden nogen markering. Fælles: koden bestod sine tests, fordi testene fodrede den med
sandheden. **Nul er et signal** — et signal bygget til en kendt fejl, der aldrig fyrer, er
et resultat om koden, ikke om dataene.

**Testværn skal måle egenskaben, ikke teksten.** Task 8's tests hævdede at de rigtige
strenge stod i den genererede HTML; filen var alligevel uparsebar, fordi generatoren skrev
`";\\n"` i stedet for et linjeskift — blank side, fundet af brugeren efter otte tasks, tre
reviews og en fix-bølge. Begge generatorer har nu en test der **parser** scriptblokken med
`node --check`, mutationstestet ved at genindsætte fejlen. Og gaten for det delte UI-modul
var **tallet 88**, ikke "grønne tests": et tal fanger en adfærdsændring som en farve skjuler.

**Delegering til Codex: arbejdsdelingen blev omvendt af sandkassen.** Delegaten kan ikke
committe (`index.lock` nægtet) og har ingen PyPI-adgang, og runtimen kører kun én opgave ad
gangen — et parallelt dispatch afvises, og en død proces kan efterlade en forældet
"kører"-lås der blokerer alt. Arbejdsdeling: delegaten skriver kode og tests, kontrol-
sessionen kører testene og committer med delegaten navngivet.
