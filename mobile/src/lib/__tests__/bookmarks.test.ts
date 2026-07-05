import AsyncStorage from '@react-native-async-storage/async-storage';
import { BOOKMARKS_KEY, canonicalize, createLocalBookmarkStore } from '../bookmarks';

beforeEach(async () => {
  await AsyncStorage.clear();
});

describe('createLocalBookmarkStore', () => {
  it('toggle tilføjer nyeste-først og fjerner igen (async)', async () => {
    const s = createLocalBookmarkStore();
    expect(await s.toggle('a')).toEqual(['a']);
    expect(await s.toggle('b')).toEqual(['b', 'a']);
    expect(await s.toggle('a')).toEqual(['b']);
  });

  it('persisterer på tværs af store-instanser (async read efter write)', async () => {
    await createLocalBookmarkStore().toggle('x');
    expect(await createLocalBookmarkStore().list()).toEqual(['x']);
  });

  it('tom / ugyldig payload → tom liste', async () => {
    expect(await createLocalBookmarkStore().list()).toEqual([]);
    await AsyncStorage.setItem(BOOKMARKS_KEY, 'ikke-json');
    expect(await createLocalBookmarkStore().list()).toEqual([]);
    await AsyncStorage.setItem(BOOKMARKS_KEY, JSON.stringify([1, 'ok', null]));
    expect(await createLocalBookmarkStore().list()).toEqual(['ok']);
  });

  it('sekventielle toggles bevarer korrekt state (seneste-vinder)', async () => {
    const s = createLocalBookmarkStore();
    await s.toggle('a');
    await s.toggle('b');
    await s.toggle('c');
    expect(await s.list()).toEqual(['c', 'b', 'a']);
  });
});

describe('canonicalize', () => {
  const canon = (id: string): string => ({ alias1: 'canon1', alias2: 'canon1' } as Record<string, string>)[id] ?? id;

  it('mapper alias → kanonisk og dedup (nyeste-først, første vinder)', () => {
    expect(canonicalize(['alias1', 'canon1', 'alias2'], canon)).toEqual(['canon1']);
  });

  it('bevarer rækkefølge for distinkte kanoniske id\'er', () => {
    expect(canonicalize(['b', 'a', 'b', 'c'], (x) => x)).toEqual(['b', 'a', 'c']);
  });

  it('tom liste → tom', () => {
    expect(canonicalize([], (x) => x)).toEqual([]);
  });
});
