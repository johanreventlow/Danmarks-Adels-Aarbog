// Personsidens udgavevisning (6e, batch 5) for den foldede person 446 (2018-20 V-148) = 1337 (1939 IV-3).
import { buildModel, type BioSourceVersionV2, type RawLineageContext } from '@daa/core';
import { byggPersonUdgave, chipNoegle } from '../personUdgave';
import { byggUdgaveLag } from '../udgaveLag';
import type { Model, RawExtId, RawSource } from '../types';

const sources: RawSource[] = [
  { id: 1, slags: 'DAA-udgave', titel: 'Danmarks Adels Aarbog 1939', udgave: 'DAA 1939', aar: 1939, ekstern: null },
  { id: 2, slags: 'DAA-udgave', titel: 'Danmarks Adels Aarbog 2018-20', udgave: 'DAA 2018-20', aar: 2018, ekstern: null },
];
const lineageRows: RawLineageContext[] = [
  { id: 50, source_id: 2, kode: 'V', navn: 'Den grevelige Linje af 1673', slaegt_id: 1 },
];
const schemeRows = {
  schemes: [{ id: 10, slaegt_id: 1, source_id: 1, kind: 'stamtavle' }, { id: 20, slaegt_id: 1, source_id: 2, kind: 'stamtavle' }],
  entries: [
    { id: 101, scheme_id: 10, code: 'IV', label: 'IV. Den grevelige Linje af 1673' },
    { id: 201, scheme_id: 20, code: 'V', label: 'V. Den grevelige Linje af 1673' },
  ],
  mappings: [
    { entry_id: 101, lineage_id: 50, relation_kind: 'canonical' },
    { entry_id: 201, lineage_id: 50, relation_kind: 'canonical' },
  ],
};
const extIds: RawExtId[] = [
  { person_id: 446, source_id: 2, linje: 'V', nr: 148, provenance: 'placement', trykt_side: '512' },
  { person_id: 1337, source_id: 1, linje: 'IV', nr: 3, provenance: 'placement', trykt_side: '410' },
];
const db = {
  persons: [{ id: '446', name: 'A', born: 1900, died: null, years: '1900', title: '', bio: 'standard', privat: false }],
  unions: [], parentChild: [],
};
const model: Model = { ...buildModel(db), ...byggUdgaveLag({ extIds, sources, lineageRows, schemeRows }, { '1337': '446' }) };

const post = (sourceId: number, aar: number, tekst: string): BioSourceVersionV2 => ({
  recordRef: `r${sourceId}`, sourceLabel: `DAA ${aar}`, recordLabel: 'post', narrativeText: tekst, citationLabel: '',
  provenanceKind: 'source_record', sourceId, sourceYear: aar,
} as BioSourceVersionV2);
const basis = { bioVersions: null, valgtNoegle: null, fallbackBio: 'standard', fallbackKilder: [] };

test('standard: nyeste udgave — ét linjemærke og B6-noten om 1939', () => {
  const v = byggPersonUdgave(model, '446', { ...basis, bioVersions: [post(1, 1939, 'gammel'), post(2, 2018, 'ny')] });
  expect(v.vaelger.chips.map((c) => c.label)).toEqual(['DAA 2018-20', 'DAA 1939']);
  expect(v.valgtUdgave).toBe('2');
  expect(v.hovedLinjer).toEqual(['V. Den grevelige Linje af 1673']);
  expect(v.linjeNoter).toEqual(['✓ også i DAA 1939 (IV. Den grevelige Linje af 1673)']);
  expect(v.bioText).toBe('ny');
  expect(v.tidligereUdgave).toBe(false);
});

test('skift til 1939: mærket, noten og biografien følger udgaven', () => {
  const bioVersions = [post(1, 1939, 'gammel'), post(2, 2018, 'ny')];
  const foerst = byggPersonUdgave(model, '446', { ...basis, bioVersions });
  const v = byggPersonUdgave(model, '446', { ...basis, bioVersions, valgtNoegle: chipNoegle(foerst.vaelger.chips[1]) });
  expect(v.valgtUdgave).toBe('1');
  expect(v.hovedLinjer).toEqual(['IV. Den grevelige Linje af 1673']);
  expect(v.linjeNoter).toEqual(['✓ også i DAA 2018-20 (V. Den grevelige Linje af 1673)']);
  expect(v.bioText).toBe('gammel');
  expect(v.tidligereUdgave).toBe(true);
});

test('før biografierne er hentet: vælgeren bygges af bogposterne, og hovedet viser stadig én linje', () => {
  const v = byggPersonUdgave(model, '446', basis);
  expect(v.vaelger.chips.map((c) => c.label)).toEqual(['DAA 2018-20', 'DAA 1939']);
  expect(v.hovedLinjer).toEqual(['V. Den grevelige Linje af 1673']);
  expect(v.bioText).toBe('standard');
  expect(v.bioManglerIUdgave).toBe(false);
});

test('udgave uden biografi siger det, når en anden udgave har én', () => {
  const v0 = byggPersonUdgave(model, '446', { ...basis, bioVersions: [post(2, 2018, 'ny')] });
  const idx1939 = v0.vaelger.chips.findIndex((c) => c.sourceId === '1');
  const v = byggPersonUdgave(model, '446', { ...basis, bioVersions: [post(2, 2018, 'ny')], valgtNoegle: chipNoegle(v0.vaelger.chips[idx1939]) });
  expect(v.bioText).toBe('');
  expect(v.bioManglerIUdgave).toBe(true);
});

test('Kilde i Aarbogen: linjens navn + trykt side, nyeste udgave først; ellers citations-faldback', () => {
  const v = byggPersonUdgave(model, '446', basis);
  expect(v.sources.map((s) => s.ref)).toEqual([
    'V. Den grevelige Linje af 1673, s. 512, nr. 148',
    'IV. Den grevelige Linje af 1673, s. 410, nr. 3',
  ]);
  const aegtefaelle = byggPersonUdgave(model, '999', { ...basis, fallbackKilder: [{ work: 'DAA 1939', ref: 's. 578' }] });
  expect(aegtefaelle.sources).toEqual([{ work: 'DAA 1939', ref: 's. 578' }]);
  expect(aegtefaelle.vaelger.form).toBe('ingen');
  expect(aegtefaelle.hovedLinjer).toEqual([]);
});

test('uden skemaer (offline-seed o.l.): linjenavnene fra lineage, ingen noter', () => {
  const seedModel: Model = { ...buildModel(db), lineage: { byPerson: { '446': ['I'] }, list: [], navn: { I: 'Den holstenske linje' } } };
  const v = byggPersonUdgave(seedModel, '446', basis);
  expect(v.hovedLinjer).toEqual(['Den holstenske linje']);
  expect(v.linjeNoter).toEqual([]);
});
