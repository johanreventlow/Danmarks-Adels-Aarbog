// Personsidens udgavevisning (6e, paritetsplanens batch 5) — mobilens pendant til web's usePersonVisning
// (web/src/components/personVisning.tsx), som ren funktion: udgavevælger, linjemærker for den valgte udgave,
// B6-noter om de andre udgavers placering, biografien for den valgte chip og »Kilde i Aarbogen«.
//
// Forskel fra web: mobilen henter ikke personens fakta (public_person_facts, paritetsplanens batch 7), så
// udgavevælgerens tredje argument (udgaver med fakta) erstattes af de udgaver, personen har en bogpost i
// (koordinatrækkerne i model.sourcesBy). Uden det fik en foldet person uden biografi i hver udgave ingen vælger,
// og hovedet viste linjerne fra begge udgaver side om side.
import {
  b6Noter, byggUdgaveVaelger, erTekniskLinje, linjerForUdgave, sorterKilder, unikkeKildelinjer,
  type BioSourceVersion, type BioSourceVersionV2, type SourceRef, type UdgaveChip, type UdgaveVaelger,
} from '@daa/core';
import type { Model } from './types';

export type PersonUdgaveVisning = {
  vaelger: UdgaveVaelger;
  valgtIdx: number;
  aktivChip: UdgaveChip | null;
  valgtUdgave: string | null;
  // Linjenavnene i hovedet: den valgte udgaves linjer (uden vælger: personens eneste udgave).
  hovedLinjer: string[];
  linjeNoter: string[];
  tidligereUdgave: boolean;
  bioText: string;
  // Biografien mangler i den valgte udgave, selv om en anden udgave har en (»Ingen biografi fra denne udgave.«).
  bioManglerIUdgave: boolean;
  sources: SourceRef[];
};

// En chips identitet på tværs af genhentninger: art, udgave og post (postens ref, ellers etiketten). Som web.
export function chipNoegle(c: UdgaveChip): string {
  return c.art === 'post' ? `post:${c.sourceId}:${c.version.recordRef ?? c.label}` : `udgave:${c.sourceId}`;
}

export function byggPersonUdgave(
  model: Model,
  personId: string,
  input: {
    // null = biografierne er ikke hentet (endnu) eller kunne ikke hentes.
    bioVersions: BioSourceVersion[] | null;
    // Læserens valg (chipNoegle); findes chippen ikke, gælder standarden (nyeste udgave med en post).
    valgtNoegle: string | null;
    // Personens biografi fra den samlede indlæsning (standardversionen) — bruges, til versionerne er hentet.
    fallbackBio: string;
    // Citations-proveniensen (aux.sourcesBy) for personer uden bogpost, typisk ægtefæller.
    fallbackKilder: SourceRef[];
  },
): PersonUdgaveVisning {
  const udgaver = model.udgaver ?? [];
  const kendt = new Set(udgaver.map((u) => u.sourceId));
  const bogKilder = model.sourcesBy?.[personId] ?? [];
  const udgaverMedPost = [...new Set(bogKilder.map((s) => s.sourceId).filter((id): id is string => id != null && kendt.has(id)))];
  const vaelger = byggUdgaveVaelger(input.bioVersions ?? [], udgaver, udgaverMedPost);
  const fundet = input.valgtNoegle ? vaelger.chips.findIndex((c) => chipNoegle(c) === input.valgtNoegle) : -1;
  const valgtIdx = fundet >= 0 ? fundet : vaelger.standard;
  const aktivChip = vaelger.chips[valgtIdx] ?? null;
  // En chip fra en ukendt udgave (fx »label:…«) filtrerer intet.
  const valgtUdgave = aktivChip && kendt.has(aktivChip.sourceId) ? aktivChip.sourceId : null;

  // Linjerne i hovedet (6e-2, spec §12.4) — samme regel som web.
  const linjer = (model.lineage?.byPerson[personId] ?? []).filter((lk) => !erTekniskLinje(lk));
  const linjeRaekker = model.linjeRaekkerBy?.[personId] ?? [];
  const raekkeKilder = [...new Set(linjeRaekker.map((r) => r.sourceId))];
  const hovedKilde = valgtUdgave ?? (raekkeKilder.length === 1 ? raekkeKilder[0] : null);
  const hovedLinjer = linjeRaekker.length === 0
    ? [...new Set(linjer.map((lk) => model.lineage?.navn[lk] ?? `Linje ${lk}`))]
    : [...new Set((hovedKilde ? [hovedKilde] : raekkeKilder).flatMap((sid) => linjerForUdgave(linjeRaekker, sid)))];
  const linjeNoter = hovedKilde ? b6Noter(linjeRaekker, hovedKilde) : [];

  // »Tidligere udgave« kun når den aktive chips udgave er ældre end standardens; ukendt år → ingen etiket.
  const chipAar = (c: UdgaveChip | null): number | null => (c == null ? null
    : udgaver.find((u) => u.sourceId === c.sourceId)?.aar
      ?? (c.art === 'post' ? (c.version as Partial<BioSourceVersionV2>).sourceYear ?? null : null));
  const aktivAar = chipAar(aktivChip);
  const standardAar = chipAar(vaelger.chips[vaelger.standard] ?? null);
  const tidligereUdgave = aktivAar != null && standardAar != null && aktivAar < standardAar;

  const harPost = vaelger.chips.some((c) => c.art === 'post');
  const bioText = input.bioVersions == null || !harPost
    ? input.fallbackBio
    : aktivChip?.art === 'post' ? aktivChip.version.narrativeText : '';

  // Bogens opslag vinder; citationen udfylder kun for personer uden opslag. Eksakte dubletter vises én gang (M-6).
  const sources = unikkeKildelinjer(bogKilder.length ? sorterKilder(bogKilder) : input.fallbackKilder);

  return {
    vaelger, valgtIdx, aktivChip, valgtUdgave, hovedLinjer, linjeNoter, tidligereUdgave,
    bioText, bioManglerIUdgave: harPost && bioText === '', sources,
  };
}
