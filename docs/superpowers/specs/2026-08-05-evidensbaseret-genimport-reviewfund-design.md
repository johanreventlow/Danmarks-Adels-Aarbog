# Rettelse af logiske reviewfund i evidensbaseret genimport

**Dato:** 2026-08-05

**Status:** Godkendt design; endnu ikke implementeret.

**Scope:** De syv verificerede logiske fund i den editionsuafhængige
evidenskontrakt, placements, identitetsafgørelser, promotionregler,
lineage-mapping, 1939-beslutningsroundtrip og offentlig visning af
kildeversioner. Rettelserne gælder infrastrukturen for både 1939 og 2018-20.

**Ikke scope:** Automatisk oprettelse eller ændring af kanonisk genealogi,
konkret re-import, produktionsdeployment, sikkerhedsreview, GDPR-review eller
ændring af den gamle `load_daa.R`-vej.

## 1. Beslutning

Løsningen bruger en hybridmodel:

- Kilde-, observation-, persona- og placement-forslagsrækker forbliver
  immutable.
- Placements får særskilte append-only beslutningsevents og autoritative views
  for den aktuelle tilstand.
- Promotionregler forbliver immutable versionsrækker; den nyeste version i en
  regellinje er gældende, og en ny `retired`-version pensionerer reglen.
- Identitetsafgørelser har én invariant, som håndhæves i den inderste
  databasefunktion og derfor ikke kan omgås gennem en alternativ RPC.
- Evidens kan kun bruges, når hele kæden fra den frosne rendition til den
  konkrete persona og fortolkning er positivt dokumenteret.

En ren status-UPDATE-model fravælges, fordi den svækker den eksisterende
append-only-audit. En fuld omskrivning af alle evidenstabeller til ét generisk
eventsystem fravælges, fordi den er større end de konkrete fejl kræver.

## 2. Evidensens autoritative kæde

En promotionsklar fortolkning skal kunne valideres gennem denne ubrudte kæde:

```text
frossen source rendition
  -> absolut source-record-span
  -> occurrence i samme record
  -> observation indeholdt i occurrence
  -> mention baseret på observationen
  -> source-persona knyttet til mention
  -> interpretation for samme persona
  -> claim, der citerer samme observation og record
```

Validatoren skal afvise bundlet, hvis et led mangler, peger på en ukendt ID,
tilhører en anden source/edition/record eller ikke er tekstligt indeholdt i
det foregående led. Ukendte eller strukturelt ugyldige nested objekter må ikke
ignoreres.

Alle spans bruger halvåbne absolutte tegnpositioner `[char_from, char_to)` i
den frosne rendition. For hvert span skal
`rendition_text[char_from:char_to] == verbatim_text`. Et record-lokalt
`0..len(verbatim_text)`-span er ikke et kildeanker. Hvis extraction-input kun
indeholder et løsrevet tekstudsnit uden absolut anker, kan det gemmes som
privat kladde, men det kan ikke passere den promotionsklare kontrakt.

Et `person.*`-claim skal citere en observation, der ligger bag en mention for
netop claimets `source_persona_id`. Det er ikke tilstrækkeligt, at personaen har
en vilkårlig mention et andet sted i bundlet. Ikke-personbundne claims må
fortsat eksistere uden kunstige personaer, men skal have den samme eksakte
kilde- og observationsbinding.

## 3. Placement-livscyklus

### 3.1 Immutable forslag og beslutningsevents

`private.source_record_placement` og `private.source_persona_placement`
repræsenterer immutable forslag og deres kildegrundlag. Deres nuværende
statuskolonner bruges kun som input til backfill. Når alle consumers er skiftet
til eventmodellen, omdøbes de til `initial_status`; navnet `status` må ikke
fortsat ligne en autoritativ aktuel tilstand.

Der tilføjes to append-only eventtabeller:

- `private.source_record_placement_decision`
- `private.source_persona_placement_decision`

Hvert event har stabilt ID, mål-ID, monoton version, beslutningsstatus,
evidensgrundlag, aktør og tidspunkt. Der er højst én række pr. kombination af
mål og version, og ingen eventrække kan opdateres eller slettes.

De autoritative current-views vælger den højeste eventversion pr. placement.
Alle consumers, promotiongates og redaktørvisninger skal læse disse views i
stedet for basekolonnens status.

### 3.2 Overgange

En databasefunktion foretager hver placementafgørelse atomisk med
optimistisk versionskontrol. Tilladte overgange er eksplicitte:

- record placement: `proposed -> accepted|rejected` og
  `accepted -> superseded`;
- persona placement: `proposed -> accepted|rejected` og
  `accepted -> superseded`.

Terminale tilstande kan ikke genåbnes in-place. En ny vurdering er et nyt
placementforslag med eget evidensgrundlag. Ved erstatning låser funktionen den
gamle og nye placement i stabil ID-orden, markerer den gamle som superseded og
accepterer den nye i samme transaktion. Den må aldrig efterlade to aktuelle,
accepterede placements, hvor den eksisterende unikhedsregel forbyder det.

Nye placementforslag oprettes gennem en databasefunktion, der indsætter
forslaget og version 1-beslutningen `proposed` i samme transaktion. En placement
uden mindst ét beslutningsevent er ugyldig. Den nuværende partielle
statusbaserede unikhedsregel erstattes af en kontrol over de aktuelle views i
beslutningsfunktionen; legacy-status må ikke fortsat styre uniqueness.

`source_persona_placement` får et stabilt surrogate ID, så flere immutable
beslutningsevents kan referere til samme forslag. Den nuværende kompositte
forretningsnøgle bevares som uniqueness-regel, ikke som eventets identitet.

### 3.3 Migration

Hver eksisterende placement får præcis ét initialt beslutningsevent med samme
effektive status som før migrationen. Migrationen skal:

1. afvise ukendte eller selvmodsigende legacy-statusser;
2. backfille stabile ID'er og initiale events deterministisk;
3. verificere samme antal placements og samme sæt aktuelt accepterede
   placements før og efter;
4. skifte consumers til current-views;
5. først derefter gøre legacy-statuskolonnen ikke-autoritativ.

Ingen migration må gætte en acceptance, afvisning eller erstatningsrelation.

## 4. Identitetsafgørelser

Den inderste `red_decide_source_persona_identity` skal håndhæve den fulde
forretningskontrakt, uanset hvilken wrapper der kalder den:

- `accepted` kræver præcis ét ikke-NULL `canonical_person_id`;
- `rejected`, `unresolved` og `superseded` kræver
  `canonical_person_id IS NULL`;
- personaen skal have mindst én gyldig, synlig source-persona-mention;
- beslutningsgrundlaget skal være et ikke-tomt, struktureret JSON-objekt;
- expected-version skal matche den aktuelle identitetsversion.

Wrapperen må forbedre ergonomi og oversætte handlinger, men ikke tilføje
invarianter, som kernefunktionen mangler. Databaseconstraint og begge RPC-tests
skal beskrive samme tilstandsmaskine.

Migrationen stopper fail-closed, hvis der allerede findes en ikke-accepteret
identitetsrække med canonical target eller en accepteret identitet uden positiv
mention. Sådanne rækker skal gennem menneskelig afklaring; migrationen må ikke
ændre deres betydning automatisk.

## 5. Versionerede promotionregler

`private.interpretation_promotion_rule` forbliver append-only. Den partielle
unikhedsregel, der forhindrer en ny aktiv version, fjernes.

En regellinje identificeres af `rule_key`. Alle versioner i samme linje skal
have samme predicate, og `rule_version` skal stige monotont. Det autoritative
current-view vælger den højeste version pr. `rule_key` og sikrer, at højst én
gældende regellinje findes pr. predicate.

- Er den nyeste version `active`, kan den bruges til promotion.
- Er den nyeste version `retired`, findes der ingen aktiv regel i linjen.
- En ældre aktiv version må aldrig genopstå, når en nyere version er retired.

Promotion-preview og endelig promotion skal låse og genvalidere den samme
aktuelle regelversion. Et preview bliver stale, hvis en nyere regelversion er
indsat mellem preview og commit.

Eksisterende regler kræver ingen datamutation: deres nuværende højeste version
bliver fortsat gældende. Migrationen afviser predicate-kollisioner mellem to
forskellige aktuelle regellinjer i stedet for at vælge én.

## 6. Lineage-integritet

En mapping mellem `lineage_scheme_entry` og `lineage` er kun gyldig, når
scheme-entryens scheme og lineage-rækken har samme `slaegt_id`.

Invarianten gøres deklarativ: `slaegt_id` backfilles til scheme-entry og
mapping, og sammensatte fremmednøgler binder scheme-entry til
`lineage_scheme(id, slaegt_id)` samt mapping til både
`lineage_scheme_entry(id, slaegt_id)` og `lineage(id, slaegt_id)`. De
sammensatte mål får de nødvendige uniqueness-constraints. Dermed kan hverken
en ny mapping eller en senere ændring af en parent-rækkes slægt skabe et
cross-clan-link uden en databasefejl.

Migrationen foretager først en read-only preflight og stopper med de konkrete
konflikt-ID'er, hvis eksisterende cross-clan mappings findes. Kontrollen må
ikke kun leve i en loader eller klient.

## 7. 1939-beslutningsroundtrip

`review_to_decisions` skal bevare mindst:

- schema-version;
- edition;
- `baseline_sha256`;
- de eksplicitte reviewbeslutninger.

Materialisering genberegner baseline-hashen fra den angivne baselinefil og
sammenligner den med beslutningsartefaktet, før kandidater bygges eller output
åbnes. Samme record keys med ændrede baseline-bytes er stale og afvises.

Et legacy beslutningsartefakt uden hash må ikke grandfatheres. Det skal
regenereres deterministisk fra det hashbundne review-/choice-artefakt. Den
igangværende 1939-undtagelseskø integreres ved at bevare dens stærkere
kildehashes; rettelsen må ikke tilbagerulle dens provenance- eller
choice-validering.

## 8. Offentlige kildeversioner på aliaspersoner

Web og mobil skal bruge samme definition af de fysiske person-ID'er bag en
kanonisk `same_som`-person:

1. canonical person ID;
2. alle `mergedFrom[].personId`;
3. deduplikeret i stabil rækkefølge.

En lille ren core-hjælper producerer ID-listen, så web og mobil ikke kan drive
fra hinanden. `fetchPublicBioVersions` modtager hele listen. En kildeversion,
der fysisk er knyttet til et alias, skal derfor vises identisk på web og mobil.

Hjælperen ændrer ikke collapse-, identitets- eller publiceringssemantik; den
standardiserer kun læseprojektionen.

## 9. Fejlhåndtering og transaktioner

Alle mismatch i kilde, tekst, span, record, persona, baseline-hash, regelversion
eller slægt afvises fail-closed. Ingen fejlvej må falde tilbage til navn-, side-,
nummer- eller tekstlig lighed.

Databaseafgørelser bruger expected-version og stabile låseordener. En stale
klient får en eksplicit konflikt og skal hente aktuel tilstand igen. Et batch
med én ugyldig overgang rulles helt tilbage.

Schema og migrationsfil holdes semantisk identiske. Migrationer er
idempotente, men preflight-konflikter er bevidst blokerende og må ikke skjules
med automatisk datakorrektion.

## 10. Implementeringsrækkefølge og samtidighed

Arbejdet udføres i en separat worktree baseret på den senest committed
re-import-revision. Den anden sessions dirty eller ignorerede arbejdsfiler
røres aldrig.

Leverancerne er:

1. evidensbinding og 1939-baselineintegritet;
2. placement-, identitets-, promotion- og lineage-modeller;
3. delt alias-ID-projektion og mobil/web-paritet.

1939-filer, der overlapper den samtidige undtagelseskø, ændres sidst i første
leverance. Før hvert delresultat og før aflevering sammenlignes målbranchens
nyeste HEAD og berørte filnavne. Ny upstream-kode integreres i den isolerede
branch; den anden worktree overskrives aldrig.

## 11. Test- og acceptkriterier

### Evidens og 1939

- Et observationstekstudsnit uden for occurrence eller rendition afvises.
- Et persona-A-claim baseret på persona-B's mention/observation afvises.
- Ukendte eller ugyldige nested objekter afvises.
- Absolutte spans og ordret tekst valideres mod den frosne rendition.
- Et beslutningsartefakt med forkert eller manglende baseline-hash afvises ved
  både konvertering og materialisering.
- Den samtidige 1939-reviewkøs eksisterende hash-, candidate- og
  dubletinvarianter forbliver grønne.

### Database

- Hver tilladt placementovergang består; hver ugyldig eller stale overgang
  afvises.
- Erstatning af placement er atomisk og efterlader præcis én tilladt aktuel
  acceptance.
- Wrapper og kerneidentitets-RPC afviser de samme ugyldige tilstande.
- En aktiv promotionregel kan erstattes af en ny aktiv version og pensioneres
  af en nyere retired version; ældre regler genopstår ikke.
- Et stale promotion-preview afvises efter regelændring.
- Cross-clan lineage-mapping afvises.
- Frisk `schema.sql` efterfulgt af migrations to gange består, og initiale
  eventbackfills bevarer alle eksisterende effektive placements.
- Relevante to-sessionstests beviser versionskonflikt og atomisk replacement;
  sekventielle tests alene er ikke tilstrækkelige.

### Core, web og mobil

- Den delte hjælper returnerer canonical ID og alle fysiske alias-ID'er uden
  dubletter.
- Web og mobil henter en publiceret kildeversion, der kun ligger på et alias.
- En person uden aliaser bevarer nuværende request og resultat.

### Samlede gates

- Regressionstesten skrives og observeres rød før hver produktionsrettelse.
- Fokuserede Python-, SQL-, core-, web- og mobiltests køres efter deres
  respektive del.
- Derefter køres hele scriptsuiten, R-suiten og de relevante fulde Node-suiter
  separat med ærlig rapportering af skips og baselinefejl.
- Ingen konkret re-import, produktionsdatabaseændring, deployment eller push
  udføres som del af denne rettelsesleverance.

## 12. GO/NO-GO efter rettelserne

Grønne rettelser giver GO til at bruge den private evidens-, review- og
promotioninfrastruktur videre. De giver ikke i sig selv GO til automatisk
re-import, kanonisk writer eller cutover. Disse kræver fortsat gennemførte
2018-20- og 1939-piloter, konkret databundet projektion og en særskilt
go/no-go-gennemgang.
