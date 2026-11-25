// Review 37 W7: signerede URL'er fornyes, når de er udløbet (spejler web/media.fornyelse.test.ts).
const mockCreateSignedUrls = jest.fn();
jest.mock('../supabase', () => ({
  supabase: {
    auth: { onAuthStateChange: () => ({ data: { subscription: { unsubscribe: () => undefined } } }) },
    storage: { from: () => ({ createSignedUrls: (...a: unknown[]) => mockCreateSignedUrls(...a) }) },
  },
}));

import { fornyUrl, signPaths } from '../media';

let taeller = 0;
beforeEach(() => {
  mockCreateSignedUrls.mockReset();
  mockCreateSignedUrls.mockImplementation(async (paths: string[]) => ({
    data: paths.map((p) => ({ path: p, signedUrl: `https://sb/${p}?t=${++taeller}` })), error: null,
  }));
});

describe('fornyUrl', () => {
  it('signerer stien bag en kendt URL forfra, uden om cachen', async () => {
    const gammel = (await signPaths(['a/1.jpg'])).get('a/1.jpg')!;
    expect((await signPaths(['a/1.jpg'])).get('a/1.jpg')).toBe(gammel); // cache-hit
    mockCreateSignedUrls.mockClear();
    const ny = await fornyUrl(gammel);
    expect(ny).toBeTruthy();
    expect(ny).not.toBe(gammel);
    expect(mockCreateSignedUrls).toHaveBeenCalledWith(['a/1.jpg'], 600);
  });

  it('en ukendt URL giver null uden kald', async () => {
    expect(await fornyUrl('https://andet/billede.jpg')).toBeNull();
    expect(mockCreateSignedUrls).not.toHaveBeenCalled();
  });

  it('er stien allerede fornyet, genbruges den nye URL uden ny signering', async () => {
    const gammel = (await signPaths(['d.jpg'])).get('d.jpg')!;
    const ny = await fornyUrl(gammel);
    mockCreateSignedUrls.mockClear();
    expect(await fornyUrl(gammel)).toBe(ny);
    expect(mockCreateSignedUrls).not.toHaveBeenCalled();
  });

  it('samtidige fornyelser af samme URL deles i ét signeringskald', async () => {
    const gammel = (await signPaths(['e.jpg'])).get('e.jpg')!;
    mockCreateSignedUrls.mockClear();
    const [x, y] = await Promise.all([fornyUrl(gammel), fornyUrl(gammel)]);
    expect(x).toBe(y);
    expect(mockCreateSignedUrls).toHaveBeenCalledTimes(1);
  });

  it('fejler signeringen, giver fornyelsen null', async () => {
    const gammel = (await signPaths(['f.jpg'])).get('f.jpg')!;
    mockCreateSignedUrls.mockResolvedValue({ data: null, error: { message: 'x' } });
    jest.spyOn(console, 'warn').mockImplementation(() => undefined);
    expect(await fornyUrl(gammel)).toBeNull();
  });

  it('cachen udleverer ikke en URL med under halvdelen af levetiden tilbage', async () => {
    const nu = Date.now();
    const spy = jest.spyOn(Date, 'now').mockReturnValue(nu);
    const foerste = (await signPaths(['g.jpg'])).get('g.jpg')!;
    spy.mockReturnValue(nu + 301_000); // > 300 s
    const anden = (await signPaths(['g.jpg'])).get('g.jpg')!;
    spy.mockRestore();
    expect(anden).not.toBe(foerste);
  });
});
