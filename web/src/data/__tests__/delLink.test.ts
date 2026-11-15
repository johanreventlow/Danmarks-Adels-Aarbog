// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from 'vitest';
import { delLink } from '../delLink';

const URL_ = 'https://eksempel.dk/person/1';

function saet(share: ((d: ShareData) => Promise<void>) | undefined, writeText: ((t: string) => Promise<void>) | undefined) {
  Object.defineProperty(navigator, 'share', { value: share, configurable: true, writable: true });
  Object.defineProperty(navigator, 'clipboard', { value: writeText ? { writeText } : undefined, configurable: true, writable: true });
}

afterEach(() => { saet(undefined, undefined); });

describe('delLink', () => {
  it('deler med telefonens delemenu, når deling er ønsket og findes — kopierer ikke', async () => {
    const share = vi.fn().mockResolvedValue(undefined); const writeText = vi.fn().mockResolvedValue(undefined);
    saet(share, writeText);
    expect(await delLink(URL_, 'Titel', true)).toBe('delt');
    expect(share).toHaveBeenCalledWith({ title: 'Titel', url: URL_ });
    expect(writeText).not.toHaveBeenCalled();
  });

  it('afbryder læseren delemenuen, sker intet andet', async () => {
    const share = vi.fn().mockRejectedValue(new DOMException('afbrudt', 'AbortError')); const writeText = vi.fn().mockResolvedValue(undefined);
    saet(share, writeText);
    expect(await delLink(URL_, 'Titel', true)).toBe('afbrudt');
    expect(writeText).not.toHaveBeenCalled();
  });

  it('fejler delingen af anden grund, kopieres linket i stedet', async () => {
    const share = vi.fn().mockRejectedValue(new DOMException('nej', 'NotAllowedError')); const writeText = vi.fn().mockResolvedValue(undefined);
    saet(share, writeText);
    expect(await delLink(URL_, 'Titel', true)).toBe('kopieret');
    expect(writeText).toHaveBeenCalledWith(URL_);
  });

  it('fejler både deling og kopiering, er udfaldet fejl', async () => {
    saet(vi.fn().mockRejectedValue(new DOMException('nej', 'NotAllowedError')), vi.fn().mockRejectedValue(new Error('nægtet')));
    expect(await delLink(URL_, 'Titel', true)).toBe('fejl');
  });

  it('uden ønske om deling kopieres der kun', async () => {
    const share = vi.fn().mockResolvedValue(undefined); const writeText = vi.fn().mockResolvedValue(undefined);
    saet(share, writeText);
    expect(await delLink(URL_, 'Titel', false)).toBe('kopieret');
    expect(share).not.toHaveBeenCalled();
  });

  it('afvist kopiering er fejl', async () => {
    saet(undefined, vi.fn().mockRejectedValue(new Error('nægtet')));
    expect(await delLink(URL_, 'Titel', false)).toBe('fejl');
  });

  it('findes deling ikke, kopieres der', async () => {
    const writeText = vi.fn().mockResolvedValue(undefined);
    saet(undefined, writeText);
    expect(await delLink(URL_, 'Titel', true)).toBe('kopieret');
  });

  it('findes udklipsholderen ikke, er udfaldet fejl', async () => {
    saet(undefined, undefined);
    expect(await delLink(URL_, 'Titel', true)).toBe('fejl');
  });
});
