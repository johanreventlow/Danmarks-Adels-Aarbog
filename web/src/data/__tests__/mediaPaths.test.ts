import { beforeEach, describe, expect, it, vi } from 'vitest';

const storage = vi.hoisted(() => ({
  calls: [] as { path: string; file: Blob; options: { contentType: string; upsert: boolean } }[],
  error: null as unknown,
}));

vi.mock('../../supabase', () => ({
  supabase: {
    storage: {
      from: (bucket: string) => {
        if (bucket !== 'media') throw new Error(`Uventet bucket: ${bucket}`);
        return {
          upload: async (
            path: string,
            file: Blob,
            options: { contentType: string; upsert: boolean },
          ) => {
            storage.calls.push({ path, file, options });
            return { error: storage.error };
          },
        };
      },
    },
  },
}));

import { buildShaStoragePaths, hexEncode } from '../mediaPaths';
import { performUpload, sha256Hex } from '../mediaUpload';

beforeEach(() => {
  storage.calls = [];
  storage.error = null;
});

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

describe('sha256Hex', () => {
  it('matcher NIST-vektoren for tom input', async () => {
    await expect(sha256Hex(new Blob([])))
      .resolves.toBe('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
  });

  it('matcher NIST-vektoren for "abc"', async () => {
    await expect(sha256Hex(new Blob(['abc'])))
      .resolves.toBe('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });
});

describe('performUpload', () => {
  it.each([
    { statusCode: 'Duplicate', message: 'Conflict' },
    { error: 'Duplicate', message: 'Conflict' },
    { statusCode: '409', message: 'The resource already exists' },
  ])('behandler en genkendt Storage-dublet som succes: %o', async (error) => {
    storage.error = error;

    await expect(performUpload(new Blob(['x'], { type: 'image/jpeg' }), 'redaktor/aa/x.jpg'))
      .resolves.toBeUndefined();
  });

  it('bevarer write-once med upsert false', async () => {
    const file = new Blob(['x'], { type: 'image/jpeg' });

    await performUpload(file, 'redaktor/aa/x.jpg');

    expect(storage.calls).toEqual([{
      path: 'redaktor/aa/x.jpg',
      file,
      options: { contentType: 'image/jpeg', upsert: false },
    }]);
  });

  it.each([
    { statusCode: '409', message: 'En anden konflikt' },
    { error: 'Unauthorized', message: 'Adgang nægtet' },
  ])('genkaster en ikke-genkendt Storage-fejl: %o', async (error) => {
    storage.error = error;

    await expect(performUpload(new Blob(['x']), 'redaktor/aa/x.jpg'))
      .rejects.toThrow(error.message);
  });
});
