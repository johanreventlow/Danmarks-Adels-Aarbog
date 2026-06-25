// Port af buildModel() fra design/design/Reventlow-folgesvend-v2.dc.html (linje 765-796).
// Udleder den flade visningsmodel: parentId + spouse pr. person, plus side-indekserne
// (childIdx, parentsByChild, childrenByUnion, spousesBy, unionById).
//
// VIGTIGT (advisor 2026-06-23): loadFromSupabase giver kun {persons, unions, parentChild}
// hvor persons IKKE har parentId/spouse. buildModel er et separat 2. stadie der afleder dem.
// I React var indekserne implicitte instans-felter; her returneres de eksplicit så Zustand-
// storen kan gemme dem (uden dem: træ uden forældre, tomme børn-grupper).
import type { Db, Model, ModelIndexes, ModelPerson } from './types';

export function buildModel(db: Db): Model {
  const persons = db.persons ?? [];
  const unions = db.unions ?? [];

  // Sanity-guard mod kendte udtræks-fejl (era-tie-break / kryds-gren-børn, CLAUDE.md §5):
  // fjern forælder→barn-kanter hvor barnet er født FØR forælderen (begge år kendt). Stopgap i
  // app-laget indtil data rettes mod den korrekte GEDCOM-base. Rører ikke basen.
  const bornOf: Record<string, number | null> = {};
  persons.forEach((p) => { bornOf[p.id] = p.born ?? null; });
  const parentChild = (db.parentChild ?? []).filter((pc) => {
    const cb = bornOf[pc.child];
    const pb = bornOf[pc.parent];
    return !(cb != null && pb != null && cb < pb); // drop hvis barn ældre end forælder
  });

  const nameOf = (id: string): string => persons.find((p) => p.id === id)?.name ?? '';

  // Ægtefæller pr. person — begge retninger, deduplikeret.
  const sp: Record<string, string> = {};
  const spousesBy: ModelIndexes['spousesBy'] = {};
  const addSpouse = (pid: string | null, oid: string | null, oname: string) => {
    if (!pid || !oname) return;
    const arr = (spousesBy[pid] = spousesBy[pid] || []);
    if (!arr.some((x) => x.id === (oid || null) && x.name === oname)) {
      arr.push({ id: oid || null, name: oname });
    }
    if (!(pid in sp)) sp[pid] = oname;
  };
  unions.forEach((u) => {
    const n2 = u.p2_name || (u.p2 ? nameOf(u.p2) : '');
    const n1 = u.p1 ? nameOf(u.p1) : '';
    addSpouse(u.p1, u.p2 || null, n2);
    addSpouse(u.p2, u.p1 || null, n1);
  });

  // Forældre pr. barn — KUN fra primær fødselsfamilie (første union), så et barn der
  // fejlagtigt optræder som 'barn' i flere familier ikke får flettet flere forældre sammen.
  const firstParent: Record<string, string> = {};
  const childIdx: Record<string, Set<string>> = {};
  const parentsByChild: Record<string, string[]> = {};
  const firstUnionKey: Record<string, string> = {};

  parentChild.forEach((pc) => {
    (childIdx[pc.parent] = childIdx[pc.parent] || new Set<string>()).add(pc.child);
  });
  parentChild.forEach((pc) => {
    const key = pc.union || '__none';
    if (!(pc.child in firstUnionKey)) firstUnionKey[pc.child] = key;
    if (key !== firstUnionKey[pc.child]) return;
    if (!(pc.child in firstParent)) firstParent[pc.child] = pc.parent;
    const arr = (parentsByChild[pc.child] = parentsByChild[pc.child] || []);
    if (!arr.includes(pc.parent)) arr.push(pc.parent); // dedup (flere påstande pr. link)
  });

  // Børn grupperet pr. ægteskab (union) — så børn fra flere ægteskaber vises hver for sig.
  // Dedup: evidens-modellen tillader flere parentChild-rækker for samme link (flere påstande),
  // så samme barn kan optræde to gange. Uden dedup giver childrenOf duplikat-ids → dublerede
  // React-keys i træ-varianterne + desync i moveSnapSib (indexOf rammer forkert).
  const childrenByUnion: Record<string, Record<string, string[]>> = {};
  parentChild.forEach((pc) => {
    const k = pc.union || '__none';
    childrenByUnion[pc.parent] = childrenByUnion[pc.parent] || {};
    const arr = (childrenByUnion[pc.parent][k] = childrenByUnion[pc.parent][k] || []);
    if (!arr.includes(pc.child)) arr.push(pc.child);
  });

  const unionById: Record<string, import('./types').Union> = {};
  unions.forEach((u) => {
    unionById[u.id] = u;
  });

  const modelPersons: ModelPerson[] = persons.map((p) => ({
    ...p,
    parentId: firstParent[p.id] || null,
    spouse: sp[p.id] || '',
  }));

  const byId: Record<string, ModelPerson> = {};
  modelPersons.forEach((p) => {
    byId[p.id] = p;
  });

  const indexes: ModelIndexes = {
    spousesBy,
    childIdx,
    parentsByChild,
    childrenByUnion,
    unionById,
  };

  return { persons: modelPersons, byId, indexes };
}
