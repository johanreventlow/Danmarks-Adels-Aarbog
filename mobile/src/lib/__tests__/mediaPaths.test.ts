import { buildShaStoragePaths, hexEncode } from '../mediaPaths';

describe('hexEncode', () => {
  it('koder faste bytevektorer som lowercase hex med foranstillede nuller', () => {
    expect(hexEncode(new Uint8Array())).toBe('');
    expect(hexEncode(new Uint8Array([0x00, 0x01, 0x0f, 0x10, 0x80, 0xff])))
      .toBe('00010f1080ff');
  });
});

describe('buildShaStoragePaths', () => {
  it('bruger shaens første to tegn som shard og bygger alle tre jpg-stier', () => {
    const sha = 'ab0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcd';

    expect(buildShaStoragePaths(sha)).toEqual({
      thumb: `redaktor/ab/${sha}-thumb.jpg`,
      medium: `redaktor/ab/${sha}-medium.jpg`,
      large: `redaktor/ab/${sha}-large.jpg`,
    });
  });
});
