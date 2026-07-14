// Delt geo-datalag (kort), i @daa/core. Samme mønster som buildAux: én ren funktion der
// bygger generiske kortpunkter, som de fire kort-flader (godskort, livskort, overblik,
// nærhed) blot filtrerer over.
//
// Datakilder:
//   * estate.sted_id → place    ⇒ gods-punkt (offentligt)
//   * fact.sted_id  (subjekt_type='person', faktatype∈{fødsel,dåb,død,begravelse,bisættelse})
//   * fact.sted_id  (subjekt_type='family', faktatype='vielse') ⇒ ægteskabs-punkt, indekseret på begge partnere
//
// RLS: koordinater er ikke følsomme, men PERSON-punkter må kun dannes for personer der
// er med i den collapsed + privat-filtrerede db (`persons`) — en privat/levende person er
// allerede sorteret fra dér, så deres fakta giver intet punkt.
//
// fact har ingen dato-kolonne (datoer bor i evidenslaget) → år udledes af personens born/died.
import type { AppPerson, Geo, GeoKind, GeoPoint, RawEstate, RawFact, RawPlace, Union } from './types';

// Person-faktatype → GeoKind. Nye "location-tags" tilføjes her (og i GeoKind).
const PERSON_FAKTA: Record<string, GeoKind> = {
  fødsel: 'fødsel',
  dåb: 'dåb',
  død: 'død',
  begravelse: 'begravelse',
  bisættelse: 'bisættelse',
};

type BuildGeoInput = {
  facts: RawFact[];
  estates: RawEstate[];
  places: RawPlace[];
  persons: AppPerson[]; // COLLAPSED + privat-filtreret db.persons (RLS-gate + fødsels-/døds-år)
  unions: Union[]; // family_id → partnere (til vielse-punkter); union.id = 'f' + family_id
};

export function buildGeo(
  { facts, estates, places, persons, unions }: BuildGeoInput,
  // samme_som-collapse: fakta-subjekter kanoniseres, så et punkt for et foldet alias
  // havner på den kanoniske person. Default {} for bagudkompat i tests.
  canonicalIdById: Record<string, string> = {},
): Geo {
  const cid = (id: string) => canonicalIdById[id] ?? id;

  // Steder MED koordinater; koordinatløse (endnu uberigede) filtreres fra.
  const placeById: Record<string, { navn: string; lat: number; lon: number }> = {};
  (places || []).forEach((p) => {
    if (p.lat == null || p.lon == null) return;
    placeById[String(p.id)] = { navn: p.navn ?? '', lat: p.lat, lon: p.lon };
  });

  // Synlige personer i ét opslag: RLS-membership (`has`) + fødsels-/døds-år (`get`).
  const personById = new Map((persons || []).map((p) => [p.id, p]));

  // family_id → union (union.id = 'f' + family_id). p1/p2 er allerede kanoniske efter collapse.
  const unionByFamilyId: Record<string, Union> = {};
  (unions || []).forEach((u) => {
    unionByFamilyId[String(u.id).replace(/^f/, '')] = u;
  });

  const points: GeoPoint[] = [];
  const byPerson: Record<string, GeoPoint[]> = {};
  const byEstate: Record<string, GeoPoint> = {};

  // Byg et GeoPoint med all-null-defaults; kun de relevante felter overskrives pr. kind.
  // Ét sted at redigere når GeoPoint får et nyt felt eller et nyt kind tilføjes.
  const mkPoint = (
    placeId: string,
    pl: { navn: string; lat: number; lon: number },
    over: Partial<GeoPoint> & { kind: GeoKind },
  ): GeoPoint => ({
    placeId,
    navn: pl.navn,
    lat: pl.lat,
    lon: pl.lon,
    personId: null,
    estateId: null,
    unionId: null,
    year: null,
    ...over,
  });

  // Gods-punkter (offentlige — ikke person-gated).
  (estates || []).forEach((e) => {
    if (e.sted_id == null) return;
    const pl = placeById[String(e.sted_id)];
    if (!pl) return;
    const pt = mkPoint(String(e.sted_id), pl, { kind: 'estate', estateId: String(e.id) });
    points.push(pt);
    byEstate[String(e.id)] = pt;
  });

  // Person- og familie-fakta-punkter.
  (facts || []).forEach((f) => {
    if (f.sted_id == null) return;
    const pl = placeById[String(f.sted_id)];
    if (!pl) return;
    const ft = (f.faktatype || '').toLowerCase();

    if (f.subjekt_type === 'person') {
      const kind = PERSON_FAKTA[ft];
      if (!kind) return;
      const pid = cid(String(f.subjekt_id));
      const person = personById.get(pid);
      if (!person) return; // RLS: privat/foldet-væk person → intet punkt
      const year = kind === 'fødsel' ? person.born : kind === 'død' ? person.died : null;
      const pt = mkPoint(String(f.sted_id), pl, { kind, personId: pid, year });
      points.push(pt);
      (byPerson[pid] = byPerson[pid] || []).push(pt);
    } else if (f.subjekt_type === 'family' && ft === 'vielse') {
      const fid = String(f.subjekt_id);
      const u = unionByFamilyId[fid];
      if (!u) return; // ukendt familie → intet punkt
      // RLS: emittér KUN hvis mindst én partner er synlig. Er begge private/filtreret fra,
      // droppes punktet helt — ellers ville et privat pars vielsessted lække på overbliks-/
      // nærhedskortet (personId er null dér, så byPerson-gaten alene beskytter ikke `points`).
      // Set() afduplikerer p1===p2, som kan opstå hvis samme_som-collapse folder begge til én.
      const visible = [...new Set([u.p1, u.p2].filter((pp): pp is string => !!pp && personById.has(pp)))];
      if (!visible.length) return;
      const pt = mkPoint(String(f.sted_id), pl, {
        kind: 'vielse',
        unionId: u.id, // app-konvention: 'f' + family_id (→ buildModel.unionById)
        year: u.year ?? null,
      });
      points.push(pt);
      // Livskort: ægteskabet hører til begge synlige partnere.
      visible.forEach((pp) => (byPerson[pp] = byPerson[pp] || []).push(pt));
    }
  });

  return { points, byPerson, byEstate };
}

// Tom geo — offline-seed-fallback + default før load.
export const EMPTY_GEO: Geo = { points: [], byPerson: {}, byEstate: {} };
