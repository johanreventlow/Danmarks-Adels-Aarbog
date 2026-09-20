# Runbook: medie-indkapsling mod prod (2026-09-20)

Lukker de sidste to anon-kaldbare gate-funktioner, `media_afbilder_skjult` og
`media_id_for_object`. Fortsættelsen af anon-hærdningen fra 2026-09-19 (PR #202,
`77d83e7`), hvor netop disse to bevidst blev ladt åbne.

**Hvad der kan gå galt:** fejler ændringen, holder billeder op med at loade for
gæster. Det er ikke en teori — med brudt indkapsling fejler hele `media`-forespørgslen
som anon med `permission denied for function media_afbilder_skjult`. Derfor er både
anvendelse og fortrydelse transaktionelle, og `db-rls.sql` har en vagt, der stopper
deployet før revoket, hvis forudsætningen mangler.

## Ændringen

| Greb | Hvor |
|---|---|
| `media_synlig_anon` gjort `SECURITY DEFINER` (krop uændret) | `db-rls.sql` |
| Ny `media_object_synlig_anon(text)`, `SECURITY DEFINER` | `db-rls.sql` |
| `media_obj_anon` + `media_obj_auth` kalder kun wrapperen | `db-rls.sql` |
| De to funktioner tilføjet `$anon_gate_hardening$` + vagt | `db-rls.sql` |
| Nye påstande i Task 12; Task 12b porteret | `db-verify.sql`, `db-verify-media.sql` |
| Storage-shim så politikkerne overhovedet testes i CI | `tests/sql/evidence-promotion-bootstrap.sql` |

`media_rettigheder_ok` er bevidst urørt — men **ikke fordi den er harmløs**. Adversarial
Codex-review (`gpt-5.6-sol`) påviste, at den er et eksistens-orakel: den svarer `true`
for et rettighedsfrigivet medie, også når det er skjult af GDPR-grunde. Målt på
prod-kopien lækker den 0 i dag (0 af 13 medier er skjulte). Projektejeren har besluttet
at sende indkapslingen nu og give orakelet sin egen opgave, fordi det kræver en ændring
af `entitet_offentlig`s media-gren, som også styrer noter/narrativer/tekst-henvisninger.
Se `docs/decisions.md` (2026-09-20).

## Afprøvet før prod

Engangskopi lavet med `createdb -T` af 19/9-kopien — ægte prod-data med
storage-skema, 13 medier, 20 varianter, 36 storage-objekter og
`storage.protect_delete`-triggeren.

- Anons synlige mængder byte-identiske før/efter (`md5` på id/navn-listerne):
  media 13, media_variant 20, storage.objects 33 af 36. Samme for `authenticated`.
  Mængderne er ikke tomme, og tre objekter er fortsat skjulte — målingen skelner.
- Direkte kald som anon: begge `permission denied`. Den lovlige vej svarer uændret.
- Idempotent: anden kørsel giver identisk snapshot.
- Fire negative kontroller fyrer (gendannet grant, INVOKER-tilbagefald, omdøbt
  wrapper, omdøbt signatur).
- Fortryd-scriptet ramte udgangspunktet præcist (tom `diff` mod før-snapshottet).
- `psql -1 -f db-rls.sql` kører rent i **én** transaktion → alt eller intet.
- **Hele katalogets delta målt** på en kopi *uden* forudgående `db-rls.sql`-kørsel
  (`pg_policies` i alle skemaer + `proacl`/`prosecdef` + `relrowsecurity`/`relacl`):
  nøjagtig 11 linjer, og de er nøjagtig de tilsigtede. Ingen blindpassagerer.
  Bekræftet af historikken: kun `77d83e7` (allerede i prod) og denne gren har rørt
  `db-rls.sql` siden sidste fuld-fil-apply (`140a17b`).
- CI's egen sekvens lokalt: exit 0, 120 OK-linjer (mod 119 før — Task 12b kører nu
  i stedet for at springe over).
- **Adversarial Codex-review** (`gpt-5.6-sol`, read-only) kørt på diffen. Tre fund
  lukket: blank sti og bucket-korrelation i `media_id_for_object`, vagten beviser nu at
  politikkerne faktisk kalder wrapperen, og Task 12b har fået to fixtures der fælder de
  regressioner, den før sov igennem (GDPR-skjult storage-objekt, objekt i anden bucket).
  Alle tre er efterprøvet med negativ kontrol.

> **Status 2026-09-20:** trin 1-2 er udført. PR #204 merget som `2271d0b`, alle 10
> CI-jobs grønne. Det udestående er trin 3-5: tør kørsel, anvendelse og browser-tjek.

## Rækkefølge

CI **før** prod. Det var netop lærestykket 19/9: CI fangede en forbruger
(`db-verify.sql`), jeg havde overset. Anvender man først i prod, gentager man fejlen
med omvendt fortegn.

1. Push grenen + åbn `--draft` PR (push er gated — spørg først)
2. Alle CI-jobs grønne
3. Tør kørsel mod prod
4. Anvend
5. Browser-tjek + `get_advisors`
6. Først derefter: markér PR'en klar og merge

## Kørsel

Prod-skrivning går gennem din egen shell (`! zsh …`), ikke gennem modellen.

**Låsevindue:** hele `db-rls.sql` i én transaktion tager `drop policy`/`create policy`
på alle politik-bærende tabeller, og de låse holdes til transaktionen committer —
læsninger venter så længe. Målt lokalt: 0,13 s. Over session-pooleren bliver det
sekunder, ikke minutter. Kør alligevel i en stille periode, ikke midt i en demo.

```
# 1) Tør kørsel — måler FØR, ændrer intet
zsh ~/.private/medie-indkapsling/medie-indkapsling-apply.zsh

# 2) Anvend
zsh ~/.private/medie-indkapsling/medie-indkapsling-apply.zsh --jeg-mener-det
```

Scriptet kræver `--jeg-mener-det` og afviser ukendte argumenter. Det kræver desuden, at
repoet står rent på `main` (eller arbejdsgrenen), og at `db-rls.sql` **faktisk bærer**
indkapslingen — en navne-vagt alene ville lade en ældre udgave slippe igennem. FØR/EFTER
+ funktionsprøve skrives til en rapportfil.

**Acceptkriteriet i rapporten:** blokken "gæstens flade" skal være **uændret** fra FØR
til EFTER. Ændrer tallene sig, er noget galt — fortryd.

## Efter anvendelsen — i denne rækkefølge

1. **Hent et rigtigt billede i browseren.** Det er den eneste prøve databasen ikke kan
   give: bytes serveres af Storage-API'et, som rammer RLS ved `createSignedUrl`.
   - som **gæst** (privat vindue): et offentligt portræt skal vises
   - som **redaktion**: samme + et spærret billede
2. `get_advisors(security)` — 0028/0029 skal ikke længere nævne de to funktioner.
   **Forvent til gengæld to NYE træf:** `media_object_synlig_anon` og
   `media_synlig_anon` er nu `SECURITY DEFINER` *og* anon-kaldbare. Det er designet,
   ikke en fejl — de er indgangspunkter på linje med `entitet_offentlig`. Ingen af dem
   er et orakel: begge svarer `false` for både skjult og ikke-eksisterende, og anon
   kunne i forvejen læse præcis det samme gennem `media`/`storage.objects`.
3. Først derefter: PR og merge.

## Fortrydelse

```
psql -X -v ON_ERROR_STOP=1 -f ~/.private/medie-indkapsling/medie-indkapsling-fortryd.sql
```

Én transaktion, med fail-closed readback: virker gæstens vej ikke bagefter, rulles
fortrydelsen selv tilbage. Genskaber INVOKER-udgaven af `media_synlig_anon`, de to
grants, de gamle politik-kroppe, og fjerner wrapperen.

**Bemærk:** merges branchen, mens prod er fortrudt, vil næste `db-rls.sql`-kørsel
anvende indkapslingen igen. Fortryder du, så lad være med at merge, før årsagen er fundet.
