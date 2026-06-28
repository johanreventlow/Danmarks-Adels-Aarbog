// Minimal indlejret Reventlow-seed — offline-fallback hvis Supabase-hentning fejler.
// Lille men struktur-gyldig (samme shapes som live-data), så UI'et kan rendere uden net.
// Ikke autoritativt: live-data er kilden (README §8). Udvides ikke — det er kun en sikkerheds-net.
import type { Aux, Db } from './types';

const db: Db = {
  persons: [
    { id: 's1', name: 'Conrad Reventlow', born: 1644, died: 1708, years: '1644–1708', title: 'Storkansler', bio: 'Dansk statsmand og storkansler. (Offline-seed — fuld biografi i live-basen.)', privat: false },
    { id: 's2', name: 'Christian Ditlev Reventlow', born: 1671, died: 1738, years: '1671–1738', title: 'Greve', bio: 'Søn af Conrad. (Offline-seed.)', privat: false },
    { id: 's3', name: 'Anna Sophie Reventlow', born: 1693, died: 1743, years: '1693–1743', title: 'Dronning', bio: 'Datter af Conrad; senere dronning. (Offline-seed.)', privat: false },
    { id: 's4', name: 'Conrad Detlev Reventlow', born: 1704, died: 1750, years: '1704–1750', title: 'Greve', bio: 'Søn af Christian Ditlev. (Offline-seed.)', privat: false },
    { id: 's5', name: 'Christian Ditlev Reventlow', born: 1748, died: 1827, years: '1748–1827', title: 'Statsminister', bio: 'Reformator og statsminister. (Offline-seed.)', privat: false },
  ],
  unions: [
    { id: 'f1', p1: 's1', p2: null, p2_name: 'Anna Margrethe Gabel', year: null },
    { id: 'f2', p1: 's2', p2: null, p2_name: 'Benedicte Margrethe von Brockdorff', year: null },
    { id: 'f3', p1: 's4', p2: null, p2_name: 'Wilhelmine Augusta von Lente', year: null },
  ],
  parentChild: [
    { child: 's2', parent: 's1', union: 'f1' },
    { child: 's3', parent: 's1', union: 'f1' },
    { child: 's4', parent: 's2', union: 'f2' },
    { child: 's5', parent: 's4', union: 'f3' },
  ],
};

const aux: Aux = {
  sourcesBy: {
    s1: [{ ref: 'Linje I, nr. 1', work: 'Danmarks Adels Aarbog' }],
  },
  estatesBy: {},
  officesBy: {},
  mediaBy: {},
  ownersByEstate: {},
  estateList: [],
  estateById: {},
  linjeByPerson: { s1: 'I', s2: 'I', s3: 'I', s4: 'I', s5: 'I' },
  linjeList: [{ linje: 'I', count: 5, headId: 's1', navn: 'Den holstenske linje' }],
  linjeNavn: { I: 'Den holstenske linje' },
  kildeListe: [],
  orgListe: [],
  medieListe: [],
  godsListe: [],
  vaabenListe: [],
};

export const SEED = {
  db,
  aux,
  rootId: 's1',
  focusId: 's2',
  relAId: 's3',
  relBId: 's5',
};
