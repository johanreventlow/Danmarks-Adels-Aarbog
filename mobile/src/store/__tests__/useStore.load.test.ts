// load(): ét genforsøg, før appen falder tilbage til offline-seed (prod 25/11: en enkelt 57014 efterlod læseren på
// 5 eksempelpersoner, til appen blev genstartet). Biografierne stemples ind bagefter (loadBios).
const mockLoad = jest.fn();
jest.mock('../../data/load', () => ({ loadFromSupabase: (...a: unknown[]) => mockLoad(...a) }));
jest.mock('../../lib/supabase', () => ({ supabase: null, supabaseEnabled: false }));

import { useStore } from '../useStore';

const svar = (bios: Promise<{ bioBy: Record<string, string>; komplet: boolean }> = Promise.resolve({ bioBy: {}, komplet: true })) => ({
  db: { persons: [{ id: '1', name: 'Live', born: null, died: null, years: '', title: '', bio: '', privat: false }],
        unions: [], parentChild: [] },
  aux: {},
  rootId: '1', focusId: '1', relAId: '1', relBId: '1',
  canonicalIdById: {}, mergedFrom: {},
  geo: { points: [] }, loadGeo: async () => ({ points: [] }),
  loadBios: () => bios,
  genCoordsByPerson: {}, parentsUnknownByPerson: {}, livsdatoBy: {}, haendelserBy: {}, storieBy: {}, feedPins: [],
});
const flush = () => new Promise((r) => setTimeout(r, 0));

beforeEach(() => {
  mockLoad.mockReset();
  useStore.setState({ status: 'idle', source: null, error: null, model: null, biosStatus: 'idle' });
  jest.spyOn(console, 'warn').mockImplementation(() => undefined);
});
afterEach(() => jest.restoreAllMocks());

test('én fejl → prøver igen og lander live', async () => {
  mockLoad.mockRejectedValueOnce({ code: '57014', message: 'canceling statement due to statement timeout' });
  mockLoad.mockResolvedValueOnce(svar());
  await useStore.getState().load();
  expect(mockLoad).toHaveBeenCalledTimes(2);
  expect(useStore.getState().source).toBe('live');
  expect(useStore.getState().model?.persons[0].name).toBe('Live');
});

test('to fejl → offline-seed med læsbar fejltekst (ikke [object Object])', async () => {
  mockLoad.mockRejectedValue({ code: '57014', message: 'canceling statement due to statement timeout' });
  await useStore.getState().load();
  expect(mockLoad).toHaveBeenCalledTimes(2);
  expect(useStore.getState().source).toBe('seed');
  expect(useStore.getState().error).toBe('57014 canceling statement due to statement timeout');
});

test('biografierne stemples ind bagefter; biosStatus følger komplet', async () => {
  let loes!: (v: { bioBy: Record<string, string>; komplet: boolean }) => void;
  const bios = new Promise<{ bioBy: Record<string, string>; komplet: boolean }>((r) => { loes = r; });
  mockLoad.mockResolvedValueOnce(svar(bios));
  await useStore.getState().load();
  expect(useStore.getState().biosStatus).toBe('loading');
  expect(useStore.getState().model?.byId['1'].bio).toBe('');
  loes({ bioBy: { '1': 'En tekst' }, komplet: false });
  await flush();
  expect(useStore.getState().biosStatus).toBe('delvis');
  expect(useStore.getState().model?.byId['1'].bio).toBe('En tekst');
});

test('bio-fejl → biosStatus fejl, modellen bliver live', async () => {
  mockLoad.mockResolvedValueOnce(svar(Promise.reject(new Error('PUBLIC_BIO_SOURCE_VERSIONS_UNAVAILABLE'))));
  await useStore.getState().load();
  await flush();
  expect(useStore.getState().source).toBe('live');
  expect(useStore.getState().biosStatus).toBe('fejl');
});
