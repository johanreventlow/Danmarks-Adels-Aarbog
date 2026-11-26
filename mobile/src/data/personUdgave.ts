// Personsidens udgavevisning (6e, paritetsplanens batch 5) — mobilens pendant til web's usePersonVisning
// (web/src/components/personVisning.tsx), som ren funktion: udgavevælger, linjemærker for den valgte udgave,
// B6-noter om de andre udgavers placering, biografien for den valgte chip og »Kilde i Aarbogen«.
//
// Batch 7: fakta med kilde pr. udgave (public_person_facts, data/personFakta.ts). Udgavevælgerens tredje argument er
// som på web de udgaver, personen har fakta i (udgaverMedFakta), og den valgte udgaves fakta bygges af
// byggUdgaveFakta. Forskel fra web: indtil fakta er hentet — eller hvis hentningen fejlede — bruges de udgaver,
// personen har en bogpost i (koordinatrækkerne i model.sourcesBy), hvor web bruger en tom liste. Uden det fik en
// foldet person uden biografi i hver udgave ingen vælger, mens fakta hentes (eller offline), og hovedet viste
// linjerne fra begge udgaver side om side.
import {
  b6Noter, byggUdgaveFakta, byggUdgaveVaelger, erTekniskLinje, linjerForUdgave, sorterKilder, udgaverMedFakta,
  unikkeKildelinjer,
  type BioSourceVersion, type BioSourceVersionV2, type SourceRef, type UdgaveChip, type UdgaveFaktaInput,
  type UdgaveFaktaVisning, type UdgaveVaelger,
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
  // Den valgte udgaves fakta (null: fakta er ikke hentet, eller hentningen fejlede).
  faktaVisning: UdgaveFaktaVisning | null;
};

export function byggPersonUdgave(
  model: Model,
  personId: string,
  input: {
    // null = biografierne er ikke hentet (endnu) eller kunne ikke hentes.
    bioVersions: BioSourceVersion[] | null;
    // Læserens valgte udgave (chippens sourceId); findes den ikke, gælder standarden (nyeste udgave med en post).
    // Nøglet på udgaven, ikke som web på chippens art + post: der er én chip pr. udgave, og før biografierne er hentet er chippen en
    // udgave-chip, bagefter en post-chip — valget skal overleve skiftet.
    valgtUdgaveId: string | null;
    // Personens biografi fra den samlede indlæsning (standardversionen) — bruges, til versionerne er hentet.
    fallbackBio: string;
    // Citations-proveniensen (aux.sourcesBy) for personer uden bogpost, typisk ægtefæller.
    fallbackKilder: SourceRef[];
    // Personens fakta (data/personFakta.ts); null/udeladt = ikke hentet (endnu) eller fejlet.
    faktaInput?: UdgaveFaktaInput | null;
  },
): PersonUdgaveVisning {
  const udgaver = model.udgaver ?? [];
  const kendt = new Set(udgaver.map((u) => u.sourceId));
  const bogKilder = model.sourcesBy?.[personId] ?? [];
  const udgaverMedPost = [...new Set(bogKilder.map((s) => s.sourceId).filter((id): id is string => id != null && kendt.has(id)))];
  const faktaInput = input.faktaInput ?? null;
  const vaelger = byggUdgaveVaelger(input.bioVersions ?? [], udgaver, faktaInput ? udgaverMedFakta(faktaInput) : udgaverMedPost);
  const fundet = input.valgtUdgaveId != null ? vaelger.chips.findIndex((c) => c.sourceId === input.valgtUdgaveId) : -1;
  const valgtIdx = fundet >= 0 ? fundet : vaelger.standard;
  const aktivChip = vaelger.chips[valgtIdx] ?? null;
  // En chip fra en ukendt udgave (fx »label:…«) filtrerer intet.
  const valgtUdgave = aktivChip && kendt.has(aktivChip.sourceId) ? aktivChip.sourceId : null;

  const faktaVisning = faktaInput ? byggUdgaveFakta(faktaInput, valgtUdgave) : null;

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

  // fallbackBio er standardudgavens tekst og må kun stå under standardchippen — ellers stod den nyeste udgaves
  // biografi under 1939-chippen, mens versionerne hentes (eller hvis hentningen fejlede).
  const harPost = vaelger.chips.some((c) => c.art === 'post');
  const bioText = input.bioVersions == null || !harPost
    ? (valgtIdx === vaelger.standard ? input.fallbackBio : '')
    : aktivChip?.art === 'post' ? aktivChip.version.narrativeText : '';

  // Bogens opslag vinder; citationen udfylder kun for personer uden opslag. Eksakte dubletter vises én gang (M-6).
  const sources = unikkeKildelinjer(bogKilder.length ? sorterKilder(bogKilder) : input.fallbackKilder);

  return {
    vaelger, valgtIdx, aktivChip, valgtUdgave, hovedLinjer, linjeNoter, tidligereUdgave,
    bioText, bioManglerIUdgave: harPost && bioText === '', sources, faktaVisning,
  };
}
