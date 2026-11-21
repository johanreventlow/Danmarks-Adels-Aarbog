// Stamtræets fokusvisning (webredesign fase 5c, tegningerne »Stamtræ · fokus (web/mobil)«) som rækker:
// forældre · søskende · gift · børn. Ren funktion over modellen, så reglerne kan testes uden DOM.
//
// Regler (overdragelsen §Stamtræet, invariant 5–7):
// - Hele søskendeflokken: børn af alle viste forældre, ikke kun den primære.
// - Halvsøskende nævnes KUN, når begge fødselsfamilier har en kendt anden forælder, og de to er forskellige.
//   Familie-id'et alene siger intet: efter samme_som-sammenfoldningen kan samme forældrepar have én familie
//   pr. udgave, og en manglende kant er ingen oplysning om halvsøskende.
// - Samme ægtefælle i flere familier (fx én pr. udgave) er ét ægteskab.
// - »Mor/Far ikke angivet i bogen« kun med præcis én forælder af kendt køn.
// - Usikre slægtskaber (formodet/omstridt) bærer ordet; komponenten tegner kanten stiplet.
// - Børn grupperes pr. ægteskab, når data knytter dem til ét af personens ægteskaber; ellers samlet med note.
// - Børn står i Aarbogens rækkefølge (sorterBoernEfterBogen); søskende i dagens rækkefølge.
import type { Model, ModelPerson } from './types';
import { childrenOf, parentsOf } from './model';
import { konfTekst } from './format';
import { sorterBoernEfterBogen } from '@daa/core';

export type FokusRelation = { person: ModelPerson; konf: string };
export type FokusForaelder = FokusRelation & { rolle: 'Far' | 'Mor' | 'Forælder' };
export type FokusSoeskende = FokusRelation & { halv: boolean; iFokus: boolean };
export type FokusAegteskab = { unionId: string | null; aegtefaelleId: string | null; navn: string };
export type FokusBoerneGruppe = { aegteskab: FokusAegteskab | null; boern: FokusRelation[] };
export type FokusRaekker = {
  foraeldre: FokusForaelder[];
  manglendeForaelder: string | null;
  soeskende: FokusSoeskende[];
  aegteskaber: FokusAegteskab[];
  boerneGrupper: FokusBoerneGruppe[];
  boerneNote: string | null;
  antalBoern: number;
  harUsikre: boolean;
};

export const BOERN_UDEN_AEGTESKAB = 'Bogen angiver ikke, hvilket ægteskab børnene stammer fra.';

const INGEN_UNION = '__none';

export function byggFokusRaekker(model: Model, focusId: string): FokusRaekker | null {
  const f = model.byId[focusId];
  if (!f) return null;
  const canon = (id: string) => model.canonicalIdById?.[id] ?? id;
  const konf = (barn: string, foraelder: string) => konfTekst(model.indexes.konfByEdge?.[`${barn}|${foraelder}`]);

  // Forældre.
  const foraeldreP = parentsOf(model, focusId);
  const foraeldre: FokusForaelder[] = foraeldreP.map((p) => ({
    person: p, konf: konf(focusId, p.id),
    rolle: p.koen === 'mand' ? 'Far' : p.koen === 'kvinde' ? 'Mor' : 'Forælder',
  }));
  let manglendeForaelder: string | null = null;
  if (foraeldre.length === 1) {
    const r = foraeldre[0].rolle;
    manglendeForaelder = r === 'Far' ? 'Mor ikke angivet i bogen' : r === 'Mor' ? 'Far ikke angivet i bogen' : 'Den anden forælder er ikke angivet i bogen';
  } else if (foraeldre.length === 0) {
    manglendeForaelder = model.parentsUnknownByPerson?.[focusId] ? 'Forældrene kendes ikke ifølge bogen' : 'Forældre ikke angivet i bogen';
  }

  // Den anden forælder i barnets fødselsfamilie under `foraelder` (kanonisk), eller null hvis ukendt.
  const andenForaelder = (barn: string, foraelder: string): string | null => {
    for (const [k, boern] of Object.entries(model.indexes.childrenByUnion[foraelder] ?? {})) {
      if (k === INGEN_UNION || !boern.some((b) => canon(b) === barn)) continue;
      const u = model.indexes.unionById?.[k];
      if (!u) continue;
      const raa = canon(u.p1) === foraelder ? u.p2 : u.p1;
      if (raa) return canon(raa);
    }
    return null;
  };

  // Søskende: hele flokken under alle viste forældre, i forældrenes rækkefølge.
  const set = new Map<string, ModelPerson>();
  if (foraeldreP.length === 0) set.set(f.id, f);
  for (const p of foraeldreP) for (const b of childrenOf(model, p.id)) if (!set.has(b.id)) set.set(b.id, b);
  if (!set.has(f.id)) set.set(f.id, f);
  const soeskende: FokusSoeskende[] = [...set.values()].map((s) => {
    const faelles = foraeldreP.filter((p) => model.indexes.childIdx[p.id]?.has(s.id));
    let halv = false;
    if (s.id !== f.id && faelles.length > 0) {
      const p = faelles[0];
      const egen = andenForaelder(f.id, p.id);
      const deres = andenForaelder(s.id, p.id);
      halv = egen != null && deres != null && egen !== deres;
    }
    const usikker = faelles.map((p) => konf(s.id, p.id)).find(Boolean) ?? '';
    return { person: s, konf: usikker, halv, iFokus: s.id === f.id };
  });

  // Ægteskaber: fra unionerne (med id), ellers spousesBy; samme ægtefælle er ét ægteskab.
  const aegteskaber: FokusAegteskab[] = [];
  const findAegteskab = (aegtefaelleId: string | null, navn: string) =>
    aegteskaber.find((a) => (aegtefaelleId ? a.aegtefaelleId === aegtefaelleId : !a.aegtefaelleId && a.navn === navn));
  const unioner = Object.values(model.indexes.unionById ?? {}).filter((u) => canon(u.p1) === focusId || (u.p2 != null && canon(u.p2) === focusId));
  for (const u of unioner) {
    const andenRaa = canon(u.p1) === focusId ? u.p2 : u.p1;
    const anden = andenRaa ? canon(andenRaa) : null;
    // En familie med kun én partner og intet navn er ikke et ægteskab, men børn med ukendt anden forælder.
    if (!anden && !u.p2_name) continue;
    const navn = (anden && model.byId[anden]?.name) || u.p2_name || 'Ægtefælle uden navn';
    const id = anden && model.byId[anden] ? anden : null;
    if (!findAegteskab(id, navn)) aegteskaber.push({ unionId: u.id, aegtefaelleId: id, navn });
  }
  if (aegteskaber.length === 0) {
    for (const s of model.indexes.spousesBy[focusId] ?? []) {
      if (!s.name && !s.id) continue;
      if (!findAegteskab(s.id, s.name)) aegteskaber.push({ unionId: null, aegtefaelleId: s.id, navn: s.name || 'Ægtefælle uden navn' });
    }
  }

  // Børn: grupperet pr. ægteskab, når der er flere ægteskaber og data knytter børnene til ét af dem.
  // I Aarbogens rækkefølge (stamtavlenummeret); grupperne nedenfor filtrerer boernP og arver den.
  const boernP = sorterBoernEfterBogen(childrenOf(model, focusId), focusId, model.bogNrBy, model.udgaver);
  const boernRel = (b: ModelPerson): FokusRelation => ({ person: b, konf: konf(b.id, focusId) });
  let boerneGrupper: FokusBoerneGruppe[] = [];
  let boerneNote: string | null = null;
  if (aegteskaber.length >= 2 && boernP.length > 0) {
    const cbu = model.indexes.childrenByUnion[focusId] ?? {};
    const tildelt = new Set<string>();
    for (const a of aegteskaber) {
      // Samme ægtefælle i flere unioner: børnene fra alle dem samles under ægteskabet.
      const keys = unioner.filter((u) => {
        const andenRaa = canon(u.p1) === focusId ? u.p2 : u.p1;
        const anden = andenRaa ? canon(andenRaa) : null;
        return a.aegtefaelleId ? anden === a.aegtefaelleId : u.id === a.unionId;
      }).map((u) => u.id);
      const ider = new Set(keys.flatMap((k) => (cbu[k] ?? []).map(canon)));
      const boern = boernP.filter((b) => ider.has(b.id) && !tildelt.has(b.id));
      boern.forEach((b) => tildelt.add(b.id));
      if (boern.length) boerneGrupper.push({ aegteskab: a, boern: boern.map(boernRel) });
    }
    const rest = boernP.filter((b) => !tildelt.has(b.id));
    if (rest.length) {
      boerneGrupper.push({ aegteskab: null, boern: rest.map(boernRel) });
      boerneNote = BOERN_UDEN_AEGTESKAB;
    }
  } else if (boernP.length > 0) {
    boerneGrupper = [{ aegteskab: null, boern: boernP.map(boernRel) }];
  }

  const harUsikre = foraeldre.some((x) => x.konf) || soeskende.some((x) => x.konf) || boerneGrupper.some((g) => g.boern.some((x) => x.konf));
  return { foraeldre, manglendeForaelder, soeskende, aegteskaber, boerneGrupper, boerneNote, antalBoern: boernP.length, harUsikre };
}
