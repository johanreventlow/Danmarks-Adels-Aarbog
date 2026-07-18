import AsyncStorage from '@react-native-async-storage/async-storage';
import { createSeenStore, SEEN_KEY, toSeenWeights } from '../seenCards';

beforeEach(async () => {
  await AsyncStorage.clear();
  jest.useFakeTimers();
});
afterEach(() => {
  jest.useRealTimers();
});

describe('toSeenWeights', () => {
  it('decay-tærskler: <3 dage → 0.25, <7 → 0.5, <14 → 0.75, ældre udelades', () => {
    const seen = { a: 100, b: 98, c: 94, d: 90, e: 50 }; // today=100 → alder 0,2,6,10,50
    const weights = toSeenWeights(seen, 100);
    expect(weights.a).toBe(0.25); // alder 0
    expect(weights.b).toBe(0.25); // alder 2
    expect(weights.c).toBe(0.5); // alder 6
    expect(weights.d).toBe(0.75); // alder 10
    expect(weights.e).toBeUndefined(); // alder 50 → udeladt (standardvægt 1.0 andetsteds)
  });
  it('tomt input → tomt objekt', () => {
    expect(toSeenWeights({}, 100)).toEqual({});
  });
});

describe('createSeenStore — load', () => {
  it('tomt lager → {}', async () => {
    const store = createSeenStore();
    expect(await store.load()).toEqual({});
  });
  it('korrupt lagerindhold → {} uden crash', async () => {
    await AsyncStorage.setItem(SEEN_KEY, 'ikke-json{');
    const store = createSeenStore();
    expect(await store.load()).toEqual({});
  });
  it('ikke-objekt-JSON (fx array) → {}', async () => {
    await AsyncStorage.setItem(SEEN_KEY, '[1,2,3]');
    const store = createSeenStore();
    expect(await store.load()).toEqual({});
  });
});

describe('createSeenStore — markSeen (debounced batch-skriv)', () => {
  it('batcher flere markSeen-kald inden for debounce-vinduet til én skrivning', async () => {
    const store = createSeenStore();
    store.markSeen(['a', 'b'], 10);
    store.markSeen(['c'], 10);
    // Endnu ikke skrevet — debounce-timeren er ikke udløbet.
    expect(await AsyncStorage.getItem(SEEN_KEY)).toBeNull();

    await jest.runAllTimersAsync();

    const stored = JSON.parse((await AsyncStorage.getItem(SEEN_KEY)) ?? '{}');
    expect(stored).toEqual({ a: 10, b: 10, c: 10 });
  });

  it('flettes med eksisterende indhold i stedet for at overskrive', async () => {
    await AsyncStorage.setItem(SEEN_KEY, JSON.stringify({ old: 1 }));
    const store = createSeenStore();
    store.markSeen(['new'], 5);
    await jest.runAllTimersAsync();
    const stored = JSON.parse((await AsyncStorage.getItem(SEEN_KEY)) ?? '{}');
    expect(stored).toEqual({ old: 1, new: 5 });
  });

  it('tom id-liste er en no-op (ingen timer, ingen skrivning)', async () => {
    const store = createSeenStore();
    store.markSeen([], 10);
    await jest.runAllTimersAsync();
    expect(await AsyncStorage.getItem(SEEN_KEY)).toBeNull();
  });

  it('LRU-cap: beskærer til 300 nyeste poster, ældste epoch-dage ryger først', async () => {
    const old: Record<string, number> = {};
    for (let i = 0; i < 300; i++) old['old' + i] = 1; // alle epoch-dag 1 (ældst)
    await AsyncStorage.setItem(SEEN_KEY, JSON.stringify(old));

    const store = createSeenStore();
    store.markSeen(['new1', 'new2'], 50); // nyere end alle de 300 gamle
    await jest.runAllTimersAsync();

    const stored = JSON.parse((await AsyncStorage.getItem(SEEN_KEY)) ?? '{}');
    expect(Object.keys(stored)).toHaveLength(300);
    expect(stored.new1).toBe(50);
    expect(stored.new2).toBe(50);
    // De to nyeste fortrænger to af de ældste (epoch-dag 1) — mindst to 'old*'-nøgler er væk.
    const remainingOld = Object.keys(stored).filter((k) => k.startsWith('old'));
    expect(remainingOld).toHaveLength(298);
  });

  it('AsyncStorage-skrivefejl sluges — ingen kastet fejl', async () => {
    const spy = jest.spyOn(AsyncStorage, 'setItem').mockRejectedValueOnce(new Error('disk fuld'));
    const store = createSeenStore();
    store.markSeen(['a'], 10);
    // Ingen ukendte afvisninger nåede test-runneren (ville have fejlet testen selv).
    await jest.runAllTimersAsync();
    spy.mockRestore();
  });
});
