// Personens visning, delt af stamtræets panel (DetailPanel) og personsiden (PersonSide): udgavevælger
// (6e-1), familie med kilder (trin 5b), godser i den valgte udgave, kilder og medier. Udtrukket fra
// DetailPanel (webredesign fase 3), uden ændret adfærd.
import { useEffect, useState, type CSSProperties } from 'react';
import { T } from '../theme';
import { childrenOf, parentsOf } from '../data/model';
import { pickPortrait, withUrl } from '../data/media';
import type { PersonDetailData } from '../data/public';
import type { Model } from '../data/types';
import { erTekniskLinje } from '../data/lineage';
import {
  aegteskabsKilder as aegteskabsKilderFor, boerneKilder as boerneKilderFor, byggUdgaveFakta, byggUdgaveVaelger,
  familieIderForPerson, foraelderKilder as foraelderKilderFor, kildeLinje, udgaveForRaekker,
  udgaverMedFakta, type BioSourceVersionV2, type FamilieKilde, type UdgaveChip,
  optraederSom, sorterKilder, unikkeKildelinjer, linjerForUdgave, b6Noter,
} from '@daa/core';
import { fetchFamilySources } from '../data/familySources';

export function usePersonVisning(model: Model, focusId: string, detail: PersonDetailData | null) {
  // Udgavevælger (6e-1, spec §5.5): ÉN chip-liste styrer både biografien og fakta-udgaven. Læserens valg er
  // bundet til personen og chippens identitet (art, udgave, post) — ikke til detalje-objektet, så en genhentning for
  // samme person (fx når geo ankommer) bevarer valget. Findes chippen ikke i de aktuelle data, gælder standarden,
  // uden at valget glemmes; en ny person giver altid standarden. Afledt, ikke nulstillet i en effekt.
  const [valg, setValg] = useState<{ focusId: string; noegle: string } | null>(null);
  // Nyt focusId nulstiller valget (også ved A → B → A); justeret under render, ikke i en effekt.
  const [valgFokus, setValgFokus] = useState(focusId);
  if (valgFokus !== focusId) {
    setValgFokus(focusId);
    setValg(null);
  }
  const faktaInput = detail?.faktaInput ?? null;
  const udgaver = model.udgaver ?? [];
  const vaelger = byggUdgaveVaelger(detail?.bioVersions ?? [], udgaver, faktaInput ? udgaverMedFakta(faktaInput) : []);
  const valgtFundet = valg && valg.focusId === focusId ? vaelger.chips.findIndex((c) => chipNoegle(c) === valg.noegle) : -1;
  const valgtIdx = valgtFundet >= 0 ? valgtFundet : vaelger.standard;
  const vaelgChip = (idx: number) => {
    const c = vaelger.chips[idx];
    if (c) setValg({ focusId, noegle: chipNoegle(c) });
  };
  const aktivChip: UdgaveChip | null = vaelger.chips[valgtIdx] ?? null;
  // En chip fra en ukendt udgave (fx »label:…« uden udgaveoplysninger) filtrerer intet: alt vises som i dag.
  const valgtUdgave = aktivChip && udgaver.some((u) => u.sourceId === aktivChip.sourceId) ? aktivChip.sourceId : null;
  const faktaVisning = faktaInput ? byggUdgaveFakta(faktaInput, valgtUdgave) : null;
  // Trin 5b 2a (spec §5.2): kilder på ægteskab og forældrelinje. Hentes pr. person; et svar for en
  // tidligere person ignoreres. Fejl giver [] i datalaget, så panelet aldrig brydes. Afhænger af
  // model.indexes, ikke model: et nyt modelobjekt (fx når geo ankommer) skal ikke hente kilderne igen.
  const [familieKilder, setFamilieKilder] = useState<FamilieKilde[]>([]);
  useEffect(() => {
    let aktiv = true;
    setFamilieKilder([]);
    const { aegteskaber, foraeldreFamilier } = familieIderForPerson(model.indexes, focusId);
    const ids = [...aegteskaber.map((a) => a.familyId), ...foraeldreFamilier];
    void fetchFamilySources(ids).then((k) => { if (aktiv) setFamilieKilder(k); });
    return () => { aktiv = false; };
  }, [focusId, model.indexes]);
  const p = model.byId[focusId] ?? null;
  const familieIder = familieIderForPerson(model.indexes, focusId);
  // Kildefiltrene bor i core (6d-3 spor L): modparten slås op kanonisk, så en kilde fra en sammenfoldet
  // udgaves post (fx 1939's alias-række) vises hos den kanoniske person.
  const canon = model.canonicalIdById ?? {};
  const aegteskabsKilder = (spouseId: string | null) => aegteskabsKilderFor(familieKilder, familieIder, spouseId, focusId, canon);
  const foraelderKilder = (parentId: string) => foraelderKilderFor(familieKilder, familieIder, parentId, canon);
  const boerneKilder = boerneKilderFor(familieKilder, familieIder, focusId, canon);
  // Samme ægteskab kan være bundet fra flere udgaver/poster; nøglen skal derfor også bære kilden.
  const kildeNøgle = (k: FamilieKilde) => [k.familyId, k.slags, k.counterpartPersonId, k.sourceLabel, k.sourceRecordRef ?? k.recordLabel].join('|');
  const parents = p ? parentsOf(model, focusId) : [];
  const spouses = p ? (model.indexes.spousesBy[focusId] ?? []) : [];
  const children = p ? childrenOf(model, focusId) : [];
  // Tekniske linjenøgler (legacy-source:…, lineage.ts) vises aldrig (spec §5.7) — ellers faldt hovedet tilbage
  // til »Linje <nøgle>«.
  const linjer = (model.lineage?.byPerson[focusId] ?? []).filter((lk) => !erTekniskLinje(lk));
  // 6e-2 (spec §12.4): hovedet viser linjetitler for den valgte udgave (uden vælger: personens eneste udgave) og
  // B6-noter om de andre udgavers placering. Uden linjerækker (kilde uden skema) gælder dagens linjenavne.
  const linjeRaekker = model.linjeRaekkerBy?.[focusId] ?? [];
  const raekkeKilder = [...new Set(linjeRaekker.map((r) => r.sourceId))];
  const hovedKilde = valgtUdgave ?? (raekkeKilder.length === 1 ? raekkeKilder[0] : null);
  const hovedLinjer = linjeRaekker.length === 0
    ? linjer.map((lk) => model.lineage?.navn[lk] ?? `Linje ${lk}`)
    : [...new Set((hovedKilde ? [hovedKilde] : raekkeKilder).flatMap((sid) => linjerForUdgave(linjeRaekker, sid)))];
  const linjeNoter = hovedKilde ? b6Noter(linjeRaekker, hovedKilde) : [];
  // Bog-nummeret ("Linje II, nr. 4") vinder; citation-proveniensen udfylder kun for personer bogen
  // ikke gav et opslag — typisk ægtefæller, der ellers stod helt uden kilde.
  // Eksakte dubletter (samme værk + ref, fx to 1939-legacy-poster for én foldet person) vises én gang (M-6).
  const sources = unikkeKildelinjer(model.sourcesBy?.[focusId]?.length ? sorterKilder(model.sourcesBy[focusId]) : (detail?.sources ?? []));
  // Portræt = hovedbilledet; galleri = de øvrige medier (materiale). RLS-gatet i data-laget.
  const media = detail?.media ?? [];
  const portrait = pickPortrait(media);
  const gallery = media.filter((m) => m.url && m.id !== portrait?.id);
  const lightboxItems = withUrl([portrait, ...gallery]);
  // Proveniens: er personen foldet af flere DAA-poster (samme_som), vis hvilke linjer/numre.
  const mergedFrom = p?.mergedFrom ?? [];
  // Godser (spec §5.8): kun dem, hvis personrække hører til den valgte udgave, eller hvis udgave ikke kendes.
  // Rækkens udgave som for fakta (§5.1): fakta-rækkernes udgave, ellers personrækkens eksterne nøgle.
  const raekkeUdgave = faktaInput ? udgaveForRaekker(faktaInput) : {};
  const godsUdgave = (personId: string): string | null => {
    if (!faktaInput) return null;
    const r = raekkeUdgave[personId];
    if (r !== undefined) return r;
    const ext = faktaInput.udgaveForPersonRaekke[personId];
    return ext != null && udgaver.some((u) => u.sourceId === ext) ? ext : null;
  };
  const godser = (detail?.estates ?? [])
    .filter((e) => { const u = godsUdgave(e.personId); return valgtUdgave == null || u == null || u === valgtUdgave; })
    .filter((e, i, alle) => alle.findIndex((x) => x.id === e.id) === i);
  // »Tidligere udgave« kun når den aktive chips udgave er ældre end standardens (årstal); ukendt år → ingen etiket.
  const standardChip = vaelger.chips[vaelger.standard] ?? null;
  const chipAar = (c: UdgaveChip): number | null => udgaver.find((u) => u.sourceId === c.sourceId)?.aar
    ?? (c.art === 'post' ? (c.version as Partial<BioSourceVersionV2>).sourceYear ?? null : null);
  const aktivAar = aktivChip ? chipAar(aktivChip) : null;
  const standardAar = standardChip ? chipAar(standardChip) : null;
  const tidligereUdgave = aktivAar != null && standardAar != null && aktivAar < standardAar;
  // »Optræder i Aarbogen som …« (spec §5.7): foldet person → de bogreferencer, posterne giver, i bogensNummers orden.
  const proveniens = mergedFrom.length > 1 ? optraederSom(model.sourcesBy?.[focusId] ?? []) || null : null;
  // Biografien for den aktive chip (eller den gamle bio-tekst, når der ingen vælger er).
  const bioText = aktivChip
    ? (aktivChip.art === 'post' ? aktivChip.version.narrativeText : '')
    : (detail?.bio ?? '');
  return {
    p, vaelger, valgtIdx, vaelgChip, aktivChip, valgtUdgave, faktaVisning, bioText, tidligereUdgave,
    parents, spouses, children, linjer, hovedLinjer, linjeNoter, sources, portrait, gallery, lightboxItems, proveniens, godser,
    aegteskabsKilder, foraelderKilder, boerneKilder, kildeNøgle,
  };
}

// En chips identitet på tværs af genhentninger: art, udgave og post (postens ref, ellers etiketten).
export function chipNoegle(c: UdgaveChip): string {
  return c.art === 'post' ? `post:${c.sourceId}:${c.version.recordRef ?? c.label}` : `udgave:${c.sourceId}`;
}

// Udgavevælgerens knapper. Etiketten er chippens (core har allerede fjernet tekniske postnøgler).
export function UdgaveKnapper({ chips, valgt, onVaelg, style }: {
  chips: UdgaveChip[]; valgt: number; onVaelg: (idx: number) => void; style?: CSSProperties;
}) {
  return (
    <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, ...style }}>
      {chips.map((c, i) => (
        <button key={`${c.art}:${c.sourceId}:${i}`} type="button" aria-pressed={i === valgt} onClick={() => onVaelg(i)} style={{
          fontFamily: T.mono, fontSize: 10.5, fontWeight: 600, cursor: 'pointer',
          color: i === valgt ? T.inkOnInverse : T.inkMuted,
          background: i === valgt ? T.bordeaux : T.surfaceSunken,
          border: '1px solid rgba(34,31,26,.12)', padding: '4px 9px', borderRadius: 6,
        }}>
          {c.label}
        </button>
      ))}
    </div>
  );
}

// Kildelinjen »Kilde: ‹udgave› · ‹post›«. Er posten en af personens egne biografiposter, vælger et klik udgavens chip
// (chips er pr. udgave, 2026-11-19: III-58 → »DAA 2018-20«); ellers (fx forælderens post) er linjen ren tekst.
export function KildeLinjeVisning({ kilde, chips, onVaelg, fontSize = 11.5 }: {
  kilde: FamilieKilde; chips: UdgaveChip[]; onVaelg: (idx: number) => void; fontSize?: number;
}) {
  const ref = kilde.sourceRecordRef;
  const idx = ref ? chips.findIndex((c) => c.art === 'post' && (c.version.recordRef === ref || c.poster.includes(ref))) : -1;
  const stil = { display: 'block', fontFamily: T.sans, fontSize, fontStyle: 'normal' as const, color: T.inkMuted };
  return idx >= 0
    ? <button type="button" onClick={() => onVaelg(idx)} style={{ ...stil, background: 'none', border: 0, padding: 0, cursor: 'pointer', textAlign: 'left' }}>{kildeLinje(kilde)}</button>
    : <span style={stil}>{kildeLinje(kilde)}</span>;
}
