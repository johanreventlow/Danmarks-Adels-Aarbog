// Review 37 W7: signerede medie-URL'er (600 s) blev aldrig fornyet. Et billede, der først indlæses efter udløb
// (fx Lightbox efter 10 min), gav et brudt billede. fornyUrl signerer stien bag en udløbet URL forfra, og cachen
// udleverer kun URL'er med mindst halvdelen af levetiden tilbage.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

let n = 0;
const createSignedUrls = vi.fn(async (paths: string[]) => ({
  data: paths.map((path) => ({ path, signedUrl: `https://x/sign/${path}?token=${++n}` })),
  error: null,
}));
let authLytter: (() => void) | null = null;

vi.mock('../../supabase', () => ({
  supabase: {
    storage: { from: () => ({ createSignedUrls }) },
    auth: { onAuthStateChange: (cb: () => void) => { authLytter = cb; } },
    from: vi.fn(),
  },
}));

const { signPaths, fornyUrl } = await import('../media');

beforeEach(() => { vi.useFakeTimers(); createSignedUrls.mockClear(); authLytter?.(); });
afterEach(() => { vi.useRealTimers(); });

describe('signerede URL\'er fornyes (review 37 W7)', () => {
  it('fornyUrl signerer stien bag en kendt URL forfra og omgår cachen', async () => {
    const gammel = (await signPaths(['a/1.jpg'])).get('a/1.jpg')!;
    const ny = await fornyUrl(gammel);
    expect(ny).not.toBeNull();
    expect(ny).not.toBe(gammel);
    expect(createSignedUrls).toHaveBeenCalledTimes(2);
    expect(createSignedUrls).toHaveBeenLastCalledWith(['a/1.jpg'], 600);
  });

  it('fornyUrl på en ukendt URL giver null uden kald', async () => {
    expect(await fornyUrl('https://andet/billede.jpg')).toBeNull();
    expect(createSignedUrls).not.toHaveBeenCalled();
  });

  it('cachen genbruger kun en URL med mindst halvdelen af levetiden tilbage', async () => {
    const foerste = (await signPaths(['b.jpg'])).get('b.jpg');
    vi.advanceTimersByTime(299_000);
    expect((await signPaths(['b.jpg'])).get('b.jpg')).toBe(foerste);
    vi.advanceTimersByTime(2_000); // 301 s: under halvdelen af de 600 s tilbage
    expect((await signPaths(['b.jpg'])).get('b.jpg')).not.toBe(foerste);
  });

  it('et login-/logout-skift glemmer også URL→sti-koblingen', async () => {
    const url = (await signPaths(['c.jpg'])).get('c.jpg')!;
    authLytter?.();
    expect(await fornyUrl(url)).toBeNull();
  });
});
