// Personens visning, delt af stamtræets panel (DetailPanel) og personsiden (PersonSide): udgavevælger
// (6e-1), familie (uden kildelinjer siden 2026-11-21), godser i den valgte udgave, kilder og medier. Udtrukket fra
// DetailPanel (webredesign fase 3), uden ændret adfærd.
import { useState, type CSSProperties } from 'react';
import { T } from '../theme';
import { childrenOf, parentsOf } from '../data/model';
import { pickPortrait, withUrl } from '../data/media';
import type { PersonDetailData } from '../data/public';
import type { Model } from '../data/types';
import { erTekniskLinje } from '../data/lineage';
import {
  byggUdgaveFakta, byggUdgaveVaelger, godserIUdgave,
  udgaverMedFakta, type BioSourceVersionV2, type UdgaveChip,
  sorterKilder, unikkeKildelinjer, linjerForUdgave, b6Noter,
} from '@daa/core';

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
  const p = model.byId[focusId] ?? null;
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
  // Godser (spec §5.8) i den valgte udgave — reglen bor i @daa/core (godserIUdgave), som mobilens personskærm også bruger.
  // Samme gods i flere rækker vises én gang.
  const godser = godserIUdgave(detail?.estates ?? [], faktaInput, udgaver, valgtUdgave)
    .filter((e, i, alle) => alle.findIndex((x) => x.id === e.id) === i);
  // »Tidligere udgave« kun når den aktive chips udgave er ældre end standardens (årstal); ukendt år → ingen etiket.
  const standardChip = vaelger.chips[vaelger.standard] ?? null;
  const chipAar = (c: UdgaveChip): number | null => udgaver.find((u) => u.sourceId === c.sourceId)?.aar
    ?? (c.art === 'post' ? (c.version as Partial<BioSourceVersionV2>).sourceYear ?? null : null);
  const aktivAar = aktivChip ? chipAar(aktivChip) : null;
  const standardAar = standardChip ? chipAar(standardChip) : null;
  const tidligereUdgave = aktivAar != null && standardAar != null && aktivAar < standardAar;
  // Biografien for den aktive chip (eller den gamle bio-tekst, når der ingen vælger er).
  const bioText = aktivChip
    ? (aktivChip.art === 'post' ? aktivChip.version.narrativeText : '')
    : (detail?.bio ?? '');
  return {
    p, vaelger, valgtIdx, vaelgChip, aktivChip, valgtUdgave, faktaVisning, bioText, tidligereUdgave,
    parents, spouses, children, linjer, hovedLinjer, linjeNoter, sources, portrait, gallery, lightboxItems, godser,
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
