# Dagsværk 4.4 · Task 0 — målinger før noget bygges

**Kørt:** 2026-09-14, read-only mod 4.3b's restore (`daa43b_20260912192527`) og
dens svar-cache. Ingen modelkald.

Formålet er at fjerne antagelser, før koden skrives. **To af de fem tal var
forkerte i den tidligere planudgave.**

| # | Måling | Resultat |
| --- | --- | --- |
| 1 | Er nogen af de 10 records i et tekstkollisions-par? | **Nej** |
| 2 | IV-34's kontrakt-afviste antal | **Blev aldrig gemt** |
| 3 | `event.*`-claims uden `person.`-præfiks | **8** |
| 4 | Persona-vej-paritet over hele 2018-20 | **587/587 enige, 0 uenige** |
| 5 | Persona-løse records | **4** |

## 1. Tekstkollisionerne rammer ikke vores udvalg

Fem records deler helposttekst med en anden (`I-91`, `III-20`, `III-30`,
`III-52`, `III-74`). **Ingen af dem er blandt de ti**, 4.3b kørte.

Cache-nøglen bar ikke `record_key` før PR #188, så to poster med samme tekst ville
have delt cachepost. Det er altså **uden konsekvens for 4.4** — målt, ikke antaget.

## 2. IV-34's afviste antal findes ikke

`afviste`-feltet blev tilføjet til kørselsscriptet **efter** bundt 2 var kørt.
IV-34 står som `delvis` med 11 gyldige claims, men antallet af afviste er ikke
gemt.

Tallet er ikke tabt — det kan genskabes ved at re-validere cachens rå svar, hvilket
er præcis det, Task 4 Step 3 foreskriver. Men det er **ikke målt endnu**, og det er
første led i femtals-regnskabet.

## 3. Spec §7.2's hul er reelt

**Otte claims** er `event.appointment` (6), `event.dismissal` (1) og
`event.acquisition` (1). De er hverken `person.*` eller `mention`/`relation`.

§7.2 definerer kun `principal` (recordens persona) og `other` (`NULL`, form
`mention`/`relation`). Med en naiv »ikke-`person.*` → `other`«-regel ville de otte
få persona `NULL` og deres klausuler `afventer_identitet` — forkert, for de handler
om hovedpersonen.

**Task 5 Step 2 skal derfor udføres, ikke lukkes.** Problemet er ikke teoretisk.

Fordeling pr. `interpretation_kind` (talt pr. prædikattype pr. record):
`property` 38, `mention` 5, `relation` 4, `event` 3.

## 4. De to persona-veje er enige

Eksporten finder personaen via `persona_key = record_key`; spec §7.2 foreskriver
helpost → mention → `source_persona_mention` med rolle `primary`.

**Begge veje giver 587 records og samme persona for alle 587. Nul uenige.**

Det afkræfter empirisk anden læsers bekymring om, at builder og writer kunne slå
persona op ad forskellige veje og blive uenige om ingestibilitet. Writeren kan
bruge §7.2's vej, builderen den samme, uden risiko for divergens i denne udgave.

## 5. Fire persona-løse records — ikke tre

Spec §7.1 siger fire (`unresolved_text`). En tidligere planudgave skrev tre uden
måling; 4.3b's preflight rapporterede også tre, men den så kun på records, der ikke
allerede var udelukket af andre grunde.

**Målt: fire.** Negativtesten i Task 7 Step 5 skal vælge sin record fra det sæt.
