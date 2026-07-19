# Koncept — Robust mediehåndtering: mediebibliotek, livscyklus & rettigheds-workflow

**Implementeringsstatus 2026-07-19:** Fase 1-filsiden, metadataredigering, rettighedspanel og genopretning er implementeret. Biblioteksoversigt, arbejdskøer, filudskiftning, dedup og udrensning er fortsat senere faser.

**Status:** koncept / idéudvikling (2026-07-19). Ingen kode endnu — dokumentet skal
styre den kommende udvikling (specs + planer pr. fase, jf. §9).
**Gælder:** redaktør-fladerne i `web/` og `mobile/` + DB-laget (`schema.sql`, `db-rls.sql`).
**Bygger på:** den samlede medieplan (`docs/superpowers/plans/2026-07-04-mediehaandtering.md`,
Slice 0–5), datamodellens invarianter (`claude.md` §3, `datamodel-oversigt.md`),
versioneringen (`docs/superpowers/specs/2026-06-30-versionering-og-hyperlinks-design.md`).
**Inspiration:** Wikimedia Commons' mediemodel (filside, filhistorik, anvendelses-
sporing, licens-workflow, vedligeholdelseskøer) — oversat til projektets skala og
invarianter, ikke kopieret.
**Afgrænsning (låst med brugeren):** *ingen egentlig billedredigering* (beskæring,
rotation, farver …) — kun robust *forvaltning* af medier.

---

## 1. Nuværende stand (empirisk, ikke antaget)

Fundamentet fra Slice 0/0g/0h + billedstørrelses-slices er reelt og stærkt:

- **DB-laget er modent.** `media` med byte-metadata + to ortogonale gating-dimensioner
  (GDPR-afbildet + rettigheder, begge fail-closed), `media_variant` (thumb/medium),
  privat bucket + signed URLs, RLS spejlet 1:1 mellem tabel og `storage.objects`,
  versionering via `trg_log_media`. RPC'er: `red_opret_media`, `red_bekraeft_media_upload`,
  `red_upload_media`, `red_set_media_rettigheder`, `red_fjern_media`,
  `red_registrer_media_variant` (`schema.sql:1663-1810`).
- **Upload virker på begge platforme** (person + gods/våben/linje), med klient-genererede
  størrelsestrin og to-fase bekræft. Fjern (afkobl relation) og Slet (blødt,
  `upload_status='fjernet'`) findes i UI.
- **Mentions i narrativ** (`[[media:id|…]]`) kan indsættes og renderes indlejret.

Men redaktør-*forvaltningen* stopper dér. Hvad redaktøren **ikke** kan i dag
(verificeret i koden, jf. subagent-kortlægning 2026-07-19):

| # | Mangel | Detalje |
|---|---|---|
| M1 | **Redigere metadata efter upload** | `titel`/`slags`/`kunstner`/`datering` sættes kun ved upload — og `kunstner`/`datering` kan slet ikke indtastes i upload-UI'et. Ingen `red_opdater_media`-RPC findes. |
| M2 | **Ændre rettigheder efter upload** | `red_set_media_rettigheder` findes i DB men har **intet UI**. `rettigheder_status` sendes hardkodet `'ukendt'` fra klienten (`redaktionWrite.ts:243`). Et billede der uploades upubliceret kan reelt aldrig frigives fra appen. |
| M3 | **Genoprette et slettet medie** | `'fjernet'` filtreres permanent væk i galleriet (`redaktionRead.ts:643`); fortryd kræver at man finder det rigtige change_set i historikken. Ingen papirkurv. |
| M4 | **Erstatte selve filen** | Ingen "ny version af filen"-vej. Bedre scanning af samme portræt = slet + genupload = nyt id, tabte relationer/mentions. |
| M5 | **Genbruge et eksisterende medie** | Ingen "tilknyt eksisterende billede"-picker; kun upload opretter `afbildet`-relationer. Et gruppebillede kan ikke kobles til flere personer. |
| M6 | **Se hvor et medie bruges** | Ingen "bruges på"-visning før fjern/slet — hverken relationer eller narrativ-mentions. Slet efterlader døde `[[media:id]]`-tokens (renderes som grå inaktiv tekst). |
| M7 | **Samlet mediebibliotek** | Medier ses kun pr. person/objekt. Ingen tværgående oversigt, søgning eller arbejdskøer. Kendt udestående ("løse billeder"-admin, changelog 2026-07-05). |
| M8 | **Dedup i praksis** | DB'ens sha256-guard er korrekt — men klienten beregner aldrig sha256; stier er `redaktor/${Date.now()}-…`. Dedup-mekanismen er reelt **inaktiv**, dubletter opstår frit. |
| M9 | **Oprydning efter delvist gennemført upload** | Fejler bekræft/variant-upload efter fase 1, efterlades `'kladde'`-rækker og/eller forældreløse Storage-objekter. Ingen samler dem op (de er fail-closed usynlige, men fylder). |
| M10 | **Vælge portræt eksplicit** | Hovedbillede vælges heuristisk (`pickPortrait`), ikke redaktionelt. Kendt udskudt punkt (plan §Slice 3 / "åbent punkt"). |
| M11 | **Rigtig sletning (udrensning)** | Blødt fjern rører aldrig Storage-bytes. Ved reel rettigheds-tilbagekaldelse eller GDPR-krav skal bytes faktisk væk — den vej findes ikke. |

Konklusionen matcher brugerens oplevelse: *upload findes, forvaltning mangler*.
Den oprindelige plan forudså det meste (Slice 1 = rettigheds-UI, Slice 2 = bulk-import,
"løse billeder"-oversigt) — dette koncept samler de manglende dele i én sammenhængende
redaktør-oplevelse i stedet for spredte enkelt-features.

---

## 2. Wikimedia som inspirationsramme

Wikimedia Commons' styrke er ikke billedredigering — det er at **hver fil er en
førsteklasses ting med sin egen side, sin egen historik og sit eget ansvar**
(licens, kilde, anvendelse). Oversat punkt for punkt:

| Commons-begreb | DAA-ækvivalent | Status i dag |
|---|---|---|
| **Filside** (`File:…` med beskrivelse, kilde, ophav, dato, licens) | Medie-detaljeside i redaktionen (§4.1) | Mangler |
| **Structured data: "depicts"** | `afbildet`-relation (polymorf, GDPR-gatet) | ✅ Findes — men kan kun oprettes ved upload |
| **Licens obligatorisk; ulicenserede filer i sletning-kø** | `rettigheder_status` + fail-closed `maa_publiceres` | ✅ Model findes; workflow/UI mangler (M2) |
| **VRT-tilladelser (permission-tickets)** | `gengivelsestilladelse`-fact + `citation` via `red_set_media_rettigheder` | ✅ RPC findes; UI mangler |
| **Filhistorik + "upload a new version"** | Erstat-fil med stabil medie-identitet (§4.5) | Mangler (M4) |
| **"File usage" / global usage** | "Bruges på"-visning: `relation` + `text_mention` (`ix_text_mention_maal` findes allerede) | Mangler (M6) |
| **Sletning er admin-reversibel; udrensning er sjælden og bevidst** | Blødt fjern (✅) + genopret + gated udrensning (§4.3) | Delvist (M3, M11) |
| **SHA1-dedup ved upload** | sha256-guard i `red_opret_media` | Inaktiv — klienten hasher ikke (M8) |
| **Vedligeholdelseskøer** (ukategoriseret, manglende licens, forældreløs) | Arbejdskøer i mediebiblioteket (§4.2) | Mangler (M7, M9) |
| **Kategorier/gallerier** | `slags` + albums (plan-Slice 4, udskudt) | Uændret udskudt |

Det, der bevidst **ikke** overtages: wiki-selvforvaltning (diskussionssider,
sletningsafstemninger, crowd-upload). Redaktionen er lille og betroet; moderations-
apparatet er overkill. Crowdsource forbliver plan-Slice 5, ude af scope.

---

## 3. Målbillede — tre løfter til redaktøren

1. **"Ethvert billede har ét hjem."** Fra ethvert galleri kan redaktøren åbne
   mediets egen side og dér se og rette *alt*: metadata, rettigheder, tilknytninger,
   anvendelse, historik, status. Ingen blindgyder hvor noget kun kunne sættes ved upload.
2. **"Intet forsvinder ved et uheld — og alt kan findes igen."** Slet er blødt og
   synligt fortrydbart (papirkurv), sletning advarer om anvendelser, og den
   sjældne *rigtige* udrensning er en bevidst, gated handling med sit eget spor.
3. **"Rettigheder er et arbejdsflow, ikke en kolonne."** Nye billeder fødes
   upublicerede (fail-closed, som i dag); biblioteket viser køen af uafklarede;
   frigivelse sker med status, dokumentation og én knap — og kan trækkes tilbage.

**Bærende princip:** dette er ren *forvaltning* oven på den eksisterende model.
Ingen nye entitetstabeller, ingen ændring af evidenslaget, ingen ny gating-logik —
konceptet udfylder de RPC- og UI-huller, den oprindelige plan allerede havde udpeget,
og strammer livscyklussen op.

---

## 4. Konceptets dele

### 4.1 Medie-detaljesiden ("filsiden")

Én skærm (web: sektion i Redaktion; mobile: skærm under redaktions-stakken) pr. medie:

- **Preview** (medium-variant, tap → Lightbox med large).
- **Metadata-panel:** `titel`, `slags` (vocab), `kunstner`, `datering` — *redigerbare*
  (ny RPC `red_opdater_media`, §5). Plus læse-felter: original-filnavn, mime,
  dimensioner, byte-størrelse, upload-status, sha256 (når den findes, jf. §4.6).
- **Rettigheds-panel** (§4.4): status-badge, publicerings-toggle, dokumentationsfelter.
- **Tilknytninger:** listen af `afbildet`-relationer (person/gods/våben/linje) med
  mulighed for at *fjerne* (eksisterende `red_slet_relation`) og *tilføje*
  (eksisterende `red_relation` — UI'et mangler blot; GDPR-retningen person→media
  håndhæves allerede server-side). Dermed løses M5 (genbrug/gruppebilleder) uden
  én linje ny SQL.
- **"Bruges på":** samlet anvendelses-liste — (a) `afbildet`-relationer, (b) narrativ-
  mentions via `text_mention` (`maal_type='media'`, indekset findes), (c) om mediet
  er nogens aktuelle portræt. Denne liste genbruges som advarsel i fjern/slet-flowet.
- **Historik:** mediets `change_set`-rækker (upload, metadata-rettelser, rettigheds-
  skift, fjern/genopret) — findes allerede via versioneringen, skal blot filtreres
  på entitet=media+id. Fortryd pr. sæt genbruger `red_fortryd_change_set`.

### 4.2 Mediebiblioteket (tværgående oversigt + arbejdskøer)

Redaktionens "Medier"-fane (web har allerede navigationspunktet) bliver et rigtigt
bibliotek i stedet for et pr.-subjekt-galleri:

- **Gitter/liste over alle medier** (redaktion ser alt via `redaktion_read`-politikken,
  inkl. `kladde`/`fjernet`/upublicerede) med thumb, titel, slags, status-badges,
  antal anvendelser. Søgning på titel/kunstner/filnavn; filtrering på slags/status.
- **Arbejdskøer** (Commons' vedligeholdelseskategorier, oversat):
  1. **Uafklarede rettigheder** — `rettigheder_status='ukendt'` eller `maa_publiceres=false`
     med status der tillader frigivelse. *Dette er den vigtigste kø:* i dag strander
     alt her uden UI.
  2. **Løse billeder** — `klar` uden nogen `afbildet`-relation og uden mentions
     (det kendte "løse billeder"-udestående).
  3. **Strandede uploads** — `kladde`/`fejlet` ældre end fx 24 timer (M9-symptomet,
     synligt i stedet for usynligt).
  4. **Papirkurv** — `fjernet`, med genopret-knap (§4.3) og udrensnings-indgang.
  5. **Dubletter** *(først når §4.6 er landet)* — samme sha256 / flere medier med
     identiske bytes fra før dedup blev aktiv.
- Køerne er rene forespørgsler på eksisterende kolonner + `text_mention` — ingen
  ny datamodel. Mobile kan nøjes med kø-tællere + simpel liste; web er primærflade
  for det tunge bibliotesarbejde (samme asymmetri-princip som entitets-editoren).

### 4.3 Livscyklus som eksplicit tilstandsmaskine

I dag: `kladde → klar → fjernet` — med envejsdør til sidst. Konceptet gør cyklussen
komplet og navngiver hver overgang:

```
kladde ──bekræft──▶ klar ──fjern──▶ fjernet ──genopret──▶ klar
  │                                    │
  └──(strandet >24t: kø 3)             └──udrens──▶ [række + bytes borte]
```

- **Genopret** (`red_genopret_media`): `fjernet → klar`. Symmetrisk modstykke til
  `red_fjern_media`, samme ene UPDATE, versioneret, gratis. Guard: kun fra `'fjernet'`.
- **Udrens** (`red_udrens_media` + klient-sidet Storage-sletning): den *rigtige*
  sletning — fjerner media-række, variant-rækker **og** Storage-objekter (bytes).
  Nødvendig for M11 (rettigheds-tilbagekaldelse/GDPR: bytes skal reelt væk — blødt
  fjern efterlader dem i bucket'en). Bevidst tung:
  - kun tilladt fra `'fjernet'` (to-trins: først blødt fjern, så udrens),
  - blokeret hvis mediet stadig har anvendelser (relationer/mentions) — de skal
    ryddes eksplicit først (Commons-princippet "fil i brug slettes ikke"),
  - bekræftelses-dialog med anvendelses-listen, à la `red_slet_person_preview`-mønsteret,
  - Storage-sletning sker klient-side efter DB-kaldet (RLS-politikken
    `media_obj_delete` for redaktion findes allerede); et fejlet Storage-kald
    efterlader et forældreløst objekt, som er fail-closed usynligt og fanges af
    oprydningen (§4.6).
  - **Åben spænding:** udrensning sletter rækken og kolliderer dermed med
    "påstande overskrives aldrig"-ånden. Begrundelsen er at media-bytes ikke er
    evidens men *materiale* — og at jura (copyright/GDPR) trumfer arkivering.
    Fortryd-historikken for rækken bevares i `change_set`/`change_row` (snapshot),
    men bytes er borte. Skal bekræftes som beslutning ved spec-arbejdet (§10).
- **Døde mentions:** fjern/udrens advarer via "bruges på", men sletter ikke tokens i
  prosa (narrativet er redaktørens tekst). `red_doede_links`-viewet udvides til også
  at dække `maal_type='media'` (+ evt. `fjernet`-status som "halvdødt" link), så
  efterladte tokens er synlige i stedet for tavse.

### 4.4 Rettigheds-workflow (Slice 1's UI, endelig)

`red_set_media_rettigheder` er komplet i DB (status + gate + licens/kildehenvisning/
gengivelsestilladelse som facts). Konceptet giver den sit UI:

- **Rettigheds-panel** på filsiden: vælger for `rettigheder_status` (vocab-værdierne
  `ukendt`/`public_domain`/`licenseret`/`tilladelse_givet`/`begraenset`/`spaerret`),
  toggle for `maa_publiceres`, felter for licens/kildehenvisning/tilladelse
  (lander som facts på mediet, dokumentation følger med).
- **Frigivelses-flow fra køen** (§4.2 kø 1): vurdér → sæt status → publicér. Én
  handling, ét change_set, fortrydbart.
- **Konsistens-nudge, ikke -tvang:** `spaerret`/`begraenset` + `maa_publiceres=true`
  advarer i UI (evt. blød server-guard). Gaten *forbliver* den simple boolean —
  ingen ny logik i RLS.
- Upload-arket udvides let: `kunstner`/`datering` og evt. rettigheds-status kan
  angives allerede ved upload (i dag hardkodes `'ukendt'`), men *skal* ikke —
  køen fanger resten. Fail-closed-defaulten (`maa_publiceres=false`) er urørt.

### 4.5 "Ny version af filen" — erstat bytes, behold identiteten

Commons' vigtigste forvaltnings-idé: filens *identitet* (id, relationer, mentions,
rettigheds-dokumentation) er adskilt fra dens *bytes*. Erstat-flowet:

1. Redaktøren vælger ny fil på filsiden → klienten bygger varianter som ved upload
   og lægger bytes på **nye** stier (sha-baserede, §4.6 — aldrig overskrivning af
   gamle objekter).
2. `red_erstat_media_fil(p_media_id, …)` opdaterer rækkens `storage_path`/`mime`/
   `byte_size`/`bredde`/`hoejde`/`sha256` (+ varianter re-registreres via eksisterende
   upsert i `red_registrer_media_variant`). Ét change_set.
3. **Filhistorik gratis:** `trg_log_media` snapshotter de gamle sti-/metadata-værdier —
   fortryd-historikken *er* filhistorikken. De gamle bytes bliver liggende i bucket'en
   (forældreløse = fail-closed usynlige for alle undtagen redaktion), så et fortryd af
   change_set'et faktisk virker: den gamle sti peger stadig på eksisterende bytes.
   Oprydning af *aldrig-mere-refererede* gamle objekter er en janitor-opgave (§4.6),
   med tilbageholdelses-frist (fx behold så længe et change_set refererer stien).

Dermed løses M4 uden ny tabel: ingen `media_version`-tabel, versioneringen bærer det.

### 4.6 Upload-hygiejne: dedup, deterministiske stier, janitor

- **Aktivér dedup:** klienten beregner sha256 af `large`-bytes før upload
  (Web Crypto `crypto.subtle.digest` / expo-crypto) og sender den med. DB-guarden
  findes allerede. UI-oversættelse af guard-fejlen: *"Billedet findes allerede"* →
  vis det eksisterende medie + tilbyd "tilknyt til denne person i stedet" (via §4.1's
  tilknytnings-flow). Dedup bliver en hjælp, ikke en fejlbesked.
- **Deterministiske stier:** skift fra `redaktor/${Date.now()}-…` til sha-baserede
  stier (planens oprindelige idé, fx `redaktor/<xx>/<sha>-large.jpg`) — samme bytes
  giver samme sti, upload bliver idempotent, og afbrudte forsøg kan genoptages uden
  at strø objekter.
- **Janitor (R-script, kør-ved-behov eller cron):** rapportér+ryd (a) `kladde`/`fejlet`
  ældre end frist, (b) Storage-objekter uden media-/variant-række (forældreløse),
  (c) variant-huller (media `klar` uden thumb/medium). Read-only rapport først,
  sletning som eksplicit flag — samme forsigtighed som TNG-QA-pipelinen.
- **HEIC på web** forbliver kendt begrænsning (fejler eksplicit med henvisning til
  mobilappen). Evt. senere: WASM-dekoder — ikke en del af dette koncept.

### 4.7 Eksplicit portræt-valg (lille, men længe ønsket)

"Sæt som portræt" på filsiden/galleriet. Modellen følger planens Slice 3-spor:
én kvalifikator på den eksisterende `afbildet`-relation (fx `relation.kvalifikator
jsonb` med `{"primaer": true}`), sat via lille RPC der nulstiller søskende-flag.
`pickPortrait`-heuristikken bliver fallback i stedet for eneste dommer. (Fuld
region-tagging forbliver udskudt — kvalifikator-kolonnen er blot dens forløber og
deles med den.)

---

## 5. Datamodel-konsekvenser (bevidst små)

**Ingen nye tabeller.** Nye/ændrede RPC'er (alle efter etableret konvention:
`SECURITY DEFINER`, rolle-gate, `begin_change_set`, versioneret):

| RPC | Gør | Note |
|---|---|---|
| `red_opdater_media` | titel/slags/kunstner/datering | M1. Spejler `red_edit_oplysning`-mønsteret. |
| `red_genopret_media` | `fjernet → klar` | M3. Guard: kun fra `'fjernet'`. |
| `red_erstat_media_fil` | ny sti/metadata/sha, re-registrér varianter | M4. To-fase som upload (bytes først). |
| `red_udrens_media` | hård sletning af række+varianter | M11. Kun fra `'fjernet'`; blokeret ved anvendelser; preview-RPC à la `red_slet_person_preview`. |
| (`red_saet_portraet`) | primær-flag på afbildet-relation | M10/§4.7. Kræver `relation.kvalifikator jsonb` (planens Slice 3-kolonne). |

Genbrug uden ændring: `red_relation`/`red_slet_relation` (tilknytninger),
`red_set_media_rettigheder` (rettigheder), `red_fortryd_change_set` (historik),
`red_registrer_media_variant` (varianter). Småting: `red_doede_links` udvides med
media-grenen; `db-verify-media.sql` udvides med genopret/udrens/erstat-gating-asserts;
`docs/database-current-state.md`'s media-linje er i øvrigt forældet (siger deny-all/tom
— Slice 0 gik i prod 2026-07-05) og bør rettes ved samme lejlighed.

**Invariant-check (`claude.md` §3):**
- *Tynd entitet:* ingen nye media-kolonner ud over planens allerede-besluttede
  (kvalifikatoren sidder på `relation` og var allerede planlagt). ✅
- *Semantik som relation, dokumentation som fact:* uændret — konceptet tilføjer UI
  og livscyklus, ikke nye attribut-hjem. ✅
- *Påstande overskrives aldrig:* metadata-rettelser versioneres; eneste spænding er
  udrensning (§4.3), som er flagget eksplicit og juridisk begrundet. ⚠ beslutning
- *Fail-closed gating:* urørt; alle nye tilstande (`fjernet`, forældreløs, `kladde`)
  er allerede usynlige for anon/auth. ✅
- *Cache er envejs:* varianter forbliver uversioneret afledt cache (B8-mønsteret). ✅

---

## 6. Hvad konceptet bevidst IKKE gør

- **Ingen billedredigering** (beskæring/rotation/justering) — eksplicit fravalgt.
- **Ingen crowdsource/medlemsupload** — forbliver plan-Slice 5.
- **Ingen albums/region-tagging nu** — forbliver Slice 3/4; konceptet er foreneligt
  med dem (kvalifikator-kolonnen deles, biblioteket kan senere filtrere på samling).
- **Ingen bulk-import-ændring** — Slice 2 (R-import) er stadig ikke bygget; §4.6's
  sha-stier og janitor er designet så bulk-importen kan genbruge dem 1:1.
- **Ingen ny moderations-/godkendelsesmodel** — redaktionen er betroet; det
  eksisterende change_set-spor er revisionen.

---

## 7. Web/mobile-arbejdsdeling

Samme princip som øvrig redaktion: **web er primærflade for biblioteks-/kø-arbejde**
(skærmplads, filtrering, batch-overblik), **mobile har fuld pr.-medie-funktionalitet**
(filside, metadata, rettigheder, genopret) men kan nøjes med forenklede kø-lister.
`redaktionWrite`/`mediaUpload` er fortsat duplikeret pr. platform ("hold i sync"-
kontrakten); de nye Change-arter tilføjes begge steder — delt-pakke-ekstraktion er
fortsat en separat follow-up og må ikke blokere dette.

---

## 8. Prioritering — hvad gør mest ondt først

Vurderet efter redaktørens daglige smerte (brugerens udgangspunkt: "slette, opdatere
mv."), ikke efter teknisk sværhedsgrad:

1. **Højest:** M2 (rettigheds-UI — uden den kan intet frigives), M1 (metadata-
   redigering), M3 (genopret/papirkurv). Alle tre er små: én RPC + panel-UI hver.
2. **Høj:** M7+M6 (bibliotek med køer + "bruges på") — forvandler medier fra
   pr.-person-vedhæng til forvaltet samling.
3. **Mellem:** M8+M9 (dedup + stier + janitor), M5 (tilknyt eksisterende).
4. **Lavere:** M4 (erstat fil), M11 (udrensning), M10 (portræt-valg).

---

## 9. Faseinddeling (hver fase = egen spec + plan, shippes selvstændigt)

| Fase | Indhold | Løser | Kerne-leverancer |
|---|---|---|---|
| **1 — Filsiden & fuld CRUD** | Medie-detaljeside (web+mobile) med metadata-redigering, rettigheds-panel, genopret | M1, M2, M3 | `red_opdater_media`, `red_genopret_media`, UI-panel, upload-ark udvidet med kunstner/datering. **Spec skrevet:** [`../superpowers/specs/2026-07-19-mediehaandtering-fase1-filside-design.md`](../superpowers/specs/2026-07-19-mediehaandtering-fase1-filside-design.md) |
| **2 — Biblioteket** | "Medier"-fanen som rigtigt bibliotek: søgning, køer 1–4, "bruges på", advarsel ved fjern/slet | M6, M7, M9 (synlighed) | kø-queries, `red_doede_links`+media, tilknyt-eksisterende-picker (M5). **Spec skrevet:** [`../superpowers/specs/2026-07-19-mediehaandtering-fase2-bibliotek-design.md`](../superpowers/specs/2026-07-19-mediehaandtering-fase2-bibliotek-design.md) |
| **3 — Hygiejne** | sha256 ved upload, sha-stier, dedup-UX, janitor-script | M8, M9 (oprydning) | klient-hash, `import/janitor`-R-script, verify-asserts |
| **4 — Identitet & endeligt farvel** | Erstat fil, udrensning m. preview, portræt-flag | M4, M11, M10 | `red_erstat_media_fil`, `red_udrens_media`(+preview), `red_saet_portraet`, `relation.kvalifikator` |

Fase 1+2 giver ~80 % af den oplevede forbedring og kræver nul nye arkitektur-
beslutninger. Fase 4 rummer de to beslutningstunge punkter (§10) og tages sidst.

---

## 10. Åbne spørgsmål (afklares ved spec-arbejdet, ikke her)

1. **Udrensning vs. arkiverings-ånden** (§4.3): bekræft at hård sletning af bytes
   + række er acceptabel når jura kræver det, og hvad der præcis skal overleve
   (change_row-snapshot gør det i dag — er det nok, eller for meget ift. GDPR?).
2. **Tilbageholdelses-frist for gamle bytes efter erstat-fil** (§4.5): hvor længe
   skal en erstattet version kunne fortrydes, før janitoren må rydde den?
3. **Dubletter fra før dedup** (§4.2 kø 5): skal eksisterende dubletter flettes
   (om-peg relationer → udrens kopien), eller blot flages?
4. **Vocab-håndhævelse for `slags`:** medie-`slags` er fritekst i dag (som al vocab)
   — skal filside-editoren begrænse til vocab-listen (nudge) nu, eller vente på den
   generelle vocab-FK-beslutning?
5. **Mobile-omfang for biblioteket:** kø-tællere + liste, eller fuld paritet med web?
