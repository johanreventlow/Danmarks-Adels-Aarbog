# Trin 6m: modelgennemgang af 1939 — fakta og kildetekst mod bogen — design

**Status:** UDKAST 2026-11-05 til projektejerens godkendelse. Projektejeren valgte at springe afklaringsrunden over;
specen bygger på samtalen 5/11 (§3). Valg, der ikke er projektejerens, er markeret *mit valg*.
**Gren:** `docs/trin6m-spec` fra `main` (`18f73dad`).
**Overordnet spec:** `docs/superpowers/specs/2026-10-29-trin6-1939-gennem-kaeden-design.md` (§5).
**Grundlag:** `docs/decisions.md` 2026-11-05 (1939-tekst må gå til en model som beslutningsstøtte; PR #298).
**Review-budget (B13):** 1 Codex-runde på spec+plan (`gpt-6.1-sol`, Opus dømmer), 1 på diffen før prod.

## 1. Roadmap-kobling

1. **Roadmapmål:** trin 6, færdigbevis (a) og (b): 1939's fakta og kildetekst, som læseren ser med kildehenvisning,
   skal være bogens. Delspecen indsættes mellem 6c-2 og 6c-3 (kræver en linje i `docs/decisions.md`, §8 pkt. 1).
2. **Værdikædeled:** kildetekst (source record → tekstversion) og forslag → afgørelse → rettelse, begge for 1939.
3. **Leverancetype:** et genbrugeligt gennemgangsværktøj (modelinput, svar, oversigt, ark) og ceremonier gennem de
   eksisterende skriveveje. Ingen editionsnavngiven permanent overflade; værktøjet tager kilde-id som parameter.
4. **Værdi:** fejl, der ellers kun findes ved at læse hele bogen (OCR-fejl, forkert udtrukne værdier, fejl i
   databasens ældre værdier), bliver fundet og rettet, før 6c-3 og 6d bygger klausuler, relationer og placements
   ovenpå.
5. **Færdigbevis:** §7.
6. **Erstatter:** at projektejeren selv skal læse bogen linje for linje for at finde fejl, og at 6c-2's kort kun
   dækker 150 af 1939's 2.774 forslag.

## 2. Målt udgangspunkt (stand-in `_slut2` = prod-kopi efter øvet 6c-2, læse-kun, kun antal, 2026-11-05)

| Mål | Antal |
|---|---|
| 1939's source records | 592 |
| 1939's narrativer (tegn i alt) | 576 (ca. 166.000 tegn) |
| 1939's aktuelle forslag | 2.774: 1.093 `accepted` (efter ceremoni 4), 1.554 `proposed`, 127 `unresolved` |
| heraf i 6c-2's kontrolunivers (navn, titel, fødsel, død) | 1.248 |
| heraf uden for (sted-omtaler, ægteskaber, embeder, godser, uddannelse, dåb, begravelse, rang m.fl.) | 1.526 |
| Personer bundet til 1939 | 559; ingen har `levende`; 28 født efter 1900 mangler dødsfaktum |

Bogens PDF ligger lokalt (gitignoreret) og kan give sidebilleder. `private.source_observation_text` har ingen rækker
for 1939 på `_slut2`; hvor 1939's posttekst bor (occurrences og deres tekststykker, som kortenes vindue syr sammen),
måler planen (§8 pkt. 4).

**Øvelsen 5/11:** Opus fik 112 af 6c-2's kortfelter (87 kort; filtreret input) og foreslog 10 B, 58 D og 44 V.
Projektejeren gennemgik listen: forslagene rammer godt, og modellen fandt OCR-fejl, der ellers er svære at se.

## 3. Hvad projektejeren har sagt (5/11)

1. Det er overvældende at gennemgå 121 poster i hånden; en model bør hjælpe.
2. Ingen af 1939-bogens personer lever (ældste nulevende Reventlow er født 1946; gælder også ægtefællerne).
3. Modelprøven ramte godt og fandt OCR-fejl; derfor skal en model gennemgå hele 1939-teksten for at sikre korrekt
   input.
4. Gennemgangen skal dække både (A) de udtrukne fakta og (B) selve kildeteksten.
5. Modellen foreslår; projektejeren afgør (decisions 2026-11-05).

## 4. Design

### 4.1 To spor

**A. Fakta.** Hvert aktuelt 1939-forslag (alle 2.774, uanset status) holdes op mod bogens post. For forslag i
kontrolfeltet (navn, titel, fødsel, død), der er bundet til en person, også mod databasens værdi, som på 6c-2's kort.
Modellen svarer pr. forslag:

| Svar | Betydning |
|---|---|
| `OK` | forslaget står i bogen og er udtrukket korrekt |
| `FORSLAG_FEJL` | forslaget er forkert udtrukket eller bærer en OCR-fejl; modellen angiver bogens læsning |
| `DB_FEJL` | bogen og forslaget er rigtige, databasens værdi er forkert (kun kontrolfeltet) |
| `BEGGE` | begge kan være rigtige (fx titler fra forskellige tidspunkter) |
| `TVIVL` | kan ikke afgøres |

Modellen ser postens sidebillede ved siden af OCR-teksten. `FORSLAG_FEJL` og `DB_FEJL` på navne, tal og stednavne
kræver, at billedet støtter læsningen; ellers er svaret `TVIVL`. Øvelsen 5/11 havde kun OCR-teksten, så dens
OCR-rettelser var kvalificerede gæt, ikke kontrol mod bogen. *Mit valg.*

Modellen må desuden notere *manglende fakta* (et meningsbærende udsagn i posten uden forslag) som antal og ref; de
skrives ikke i denne delspec (§5).

**B. Kildetekst.** Hver af de 592 posters tekst holdes op mod bogens sidebillede. Modellen svarer pr. post med en liste
af rettelser (tegnposition, nuværende tekst, bogens tekst, art: OCR-tegn, orddeling, manglende/overskydende tekst,
grænse til nabopost) eller `OK`. *Mit valg:* sidebilledet er facit, ikke modellens sprogfornemmelse; en rettelse uden
billedstøtte meldes som `TVIVL`.

**Rækkefølge:** B før A. En rettet kildetekst ændrer, hvad A skal holde forslagene op imod. *Mit valg.*

### 4.2 Input og fortrolighed

1. Et script bygger modelinputtet fra databasen og PDF'en: posttekst, sidebilleder for postens sider, forslag og
   (kun spor A's kontrolfelt) databasens værdi og personens familie. Filteret fra 6c-2-øvelsen gælder: en person med
   databaseværdier medtages kun, hvis databasen har en død for personen eller et fødselsår til og med 1939; ellers
   udelades personen, og et forslag om netop den person går til projektejeren uden modelforslag.
2. Modellen får ingen interne id'er, kun ref'er; nøglen bliver i `~/.private`.
3. Modellen læser kun inputfilerne og skriver kun svarfilerne (0600 i `~/.private`); dens svar til sessionen er kun
   antal. Modellen skriver aldrig i et ark eller i databasen.
4. *Mit valg:* Opus til begge spor. Fable bruges ikke i en workflow (global regel); en eventuel Fable-læsning af
   resultatet spørges der om først.

### 4.3 Projektejerens gennemgang

Kun det, modellen markerer (alt andet end `OK`), når projektejeren. Gennemgangen bygger på 6c-2's kortværktøj (HTML
med bogtekst og sidebillede, svar gemt lokalt, flettet til et tokenark) frem for et langt ark
(`ingen-flere-fulde-afgoerelsesark`):

1. **Grupper.** Rettelser af samme art (fx `FORSLAG_FEJL` med samme OCR-tegnpar, orddelinger) vises samlet; ét svar
   gælder gruppen, og hvert element kan tages ud af gruppen.
2. **Modellens forslag vises, men er ikke forudfyldt.** Projektejeren klikker selv sit svar; et ubesvaret felt er
   `V` (ingen handling). Det imødegår, at et forudfyldt ark skjuler fejl (#248).
3. **Mål for indsatsen:** projektejerens gennemgang skal kunne gøres på højst nogle timer. Overstiger antallet af
   markerede elementer efter gruppering 300, stopper planen og vender tilbage til projektejeren med tallene. *Mit
   valg (tærsklen).*

### 4.4 Skriveveje (kun eksisterende, hvor det er muligt)

| Afgørelse | Skrivevej |
|---|---|
| B-rettelse af kildetekst | `red_apply_reimport_source_text_revision` (6a): ny tekstversion, originalen bevares; klausulerne afledes igen, og RPC'en melder `binding_loss`/`parties_dropped` |
| Narrativ følger kildeteksten | `red_revider_publiceret_person_narrative_record` |
| `DB_FEJL` godkendt | `red_ret_paastand(…, 'bogen_har_ret', …)` som i 6c-2 |
| `FORSLAG_FEJL` godkendt, forslaget `proposed` | ny version af forslaget med bogens læsning (se nedenfor) |
| `FORSLAG_FEJL` godkendt, forslaget `accepted` | ny version + afgørelsen og bindingen flyttes (se nedenfor) |
| `BEGGE`, `TVIVL`, ubesvaret | ingen skrivning; forslaget står som før |

**Hul:** der findes ingen RPC, der laver en ny version af et forslag med en menneskeligt angivet værdi;
`red_normaliser_forslag` tager kun den faste regel `dato-markoer-v1`. Planen afgør, om den generaliseres (regel
`menneske-laesning-v1` med eksplicit værdi og evidens: ref til gennemgangen og modellens forslag) eller om en ny RPC er
renere. Det er ny DDL og kræver blok, ceremoni og øvelse som 6c-2's.

### 4.5 Ceremonier

Som 6c-2: runner i `~/.private`, stand-in-øvelse fra operatørens cwd, dump før hver skrivende ceremoni, GO-kode bundet
til commit, filer og ark, `--jeg-mener-det`, prod kun fra projektejerens shell, fortrydelse fra dumpet.

1. **B-ceremonien** (kildetekst) før A's kort laves. Tørkørsel på stand-in måler `binding_loss` og `parties_dropped`
   pr. post. *Mit valg:* en rettelse, der ville miste en binding, som 6c-2 lavede, skrives ikke i B-ceremonien; den
   meldes, og planen beskriver, hvordan bindingen genskabes (ny binding til den nye klausul i samme transaktion) eller
   hvorfor rettelsen udskydes.
2. **A-ceremonien** (fakta) efter projektejerens kort, i én transaktion: forslagsversioner, påstandsrettelser og
   afgørelser, med efterkontrol som 6c-2's ceremoni 4.

## 5. Mål, ikke-mål og anti-mål

**Mål:** alle 592 poster og alle 2.774 forslag er gennemgået af modellen; alt markeret er afgjort af projektejeren;
rettelserne er i prod med proveniens (modellens forslag, projektejerens afgørelse, sidebilledet).

**Ikke-mål:**
- Nye fakta fra *manglende fakta* (A) skrives ikke; de tælles og kan blive input til 6c-3/6d.
- Andre udgaver end 1939 (2018-20 har levende personer; præsenslisten 2012-14).
- Ny OCR af bogen. Renditionen er uforanderlig; rettelser er tekstversioner.
- Et fjerde kortsvar »begge rigtige« til 6c-2's kort (backlog til 6c-3, hvis `BEGGE` viser sig hyppigt).

**Anti-mål (gør specen til en fiasko, selv hvis den virker teknisk):**
- Modellen skriver noget, eller et modelforslag bliver til en afgørelse uden projektejerens klik.
- En binding fra 6c-2 forsvinder stille.
- Tekst om en person, der ikke opfylder filteret, sendes til en model.
- Projektejeren skal igennem et ark i størrelsesordenen af 4.5-arket (dage).

## 6. Begrænsninger

- Ingen prod-skrivning uden GO i projektejerens shell; ingen push/merge uden godkendelse; PR'er som kladde.
- Arbejdsmapper og `~/.private` committes aldrig; runner og scripts printer kun antal, nøgler og hashes.
- Prods `statement_timeout` er 2 min; stand-in-tid er ikke prod-tid (mål forholdet).
- Fryse: ingen redigering i prod fra hvert dump, til ceremonien er godkendt.

## 7. Færdigbevis

1. Modellens dækning: 592/592 poster og 2.774/2.774 forslag har et svar; valideret (hver ref præcis én gang, kun
   gyldige svar).
2. Prod efter ceremonierne: antal tekstversioner, forslagsversioner, påstandsrettelser og afgørelser = projektejerens
   ark; 0 tabte bindinger fra 6c-2 uden meldt og godkendt håndtering; lighedstjek og `vejb` grønne som i 6c-2.
3. Læseren: tre stikprøver valgt af projektejeren viser den rettede tekst og værdi med kildehenvisning.

## 8. Åbne punkter

1. **Roadmap-linjen** i `docs/decisions.md`: 6m mellem 6c-2 og 6c-3. Projektejeren godkender ved merge af denne spec.
2. **Forslagsversion med menneskelig læsning** (§4.4): generalisering af `red_normaliser_forslag` eller ny RPC.
   Planens valg, begrundet; DDL-blok.
3. **Bindinger fra 6c-2 ved tekstrettelse** (§4.5 pkt. 1): genskab i samme transaktion eller udskyd. Planen måler
   omfanget på stand-in først.
4. **Hvor 1939's posttekst bor** og hvordan en tekstrevision rammer den (occurrences, tekststykker, narrativ). Planen
   måler før design af B-ceremonien.
5. **Sidebilleder:** opløsning og beskæring pr. post (Calamari-sidekortet, `CALAMARI_R6_TO_PDF_V1`). Planens valg.
