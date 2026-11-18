import { beforeEach, describe, expect, it, vi } from 'vitest';
import { executePurgeOprydning, executeSletHelt, purgeStorage, type PurgeFil, type PurgeStorageDeps } from '../personPurge';
import { buildRpcCall, planCall, submitChange } from '../redaktionWrite';
import { supabase } from '../../supabase';

vi.mock('../../supabase', () => ({ supabase: { rpc: vi.fn(), storage: { from: vi.fn() }, auth: { onAuthStateChange: vi.fn() } } }));
const opts = { personId: '1791', previewSha256: 'a'.repeat(64), dryRun: false, role: 'redaktion' };
function deps(files: PurgeFil[] = [{ bucket: 'media', sti: 'a' }]) {
  return {
    submit: vi.fn<PurgeStorageDeps['submit']>().mockResolvedValue({ dryRun: false }),
    listOutbox: vi.fn<PurgeStorageDeps['listOutbox']>().mockResolvedValue(files),
    removeObjects: vi.fn<PurgeStorageDeps['removeObjects']>().mockImplementation(async (_bucket: string, paths: string[]) => ({ data: paths.map((name) => ({ name })), error: null })),
    objectAbsent: vi.fn<PurgeStorageDeps['objectAbsent']>().mockResolvedValue(false),
  };
}
beforeEach(() => vi.clearAllMocks());
describe('executeSletHelt — DB først og dryRun-threading (PR #72)', () => {
  it('tråder dryRun=true og role helt igennem; hverken udbakke, Storage eller kvittering berøres', async () => {
    const d = deps(); d.submit.mockResolvedValue({ dryRun: true });
    expect(await executeSletHelt({ ...opts, dryRun: true }, d)).toEqual({ kind: 'dry-run' });
    expect(d.submit).toHaveBeenCalledTimes(1);
    expect(d.submit).toHaveBeenCalledWith({ art: 'sletPersonHelt', subjektType: 'person', subjektId: '1791',
      payload: { previewSha256: opts.previewSha256 } }, { dryRun: true, role: 'redaktion' });
    expect(d.listOutbox).not.toHaveBeenCalled(); expect(d.removeObjects).not.toHaveBeenCalled();
  });
  it('den rigtige submitChange har også dry-run-gaten og sender preview-hashen', async () => {
    const d = deps();
    expect(buildRpcCall({ art: 'sletPersonHelt', subjektType: 'person', subjektId: opts.personId,
      payload: { previewSha256: opts.previewSha256 } })).toEqual({ fn: 'red_slet_person_helt',
      args: { p_person_id: 1791, p_preview_sha256: opts.previewSha256 } });
    await executeSletHelt({ ...opts, dryRun: true }, { ...d, submit: submitChange });
    expect(supabase.rpc).not.toHaveBeenCalled(); expect(d.removeObjects).not.toHaveBeenCalled();
  });
  it('bevarer store bigint-id præcist og afviser manglende hash uden staging', () => {
    expect(buildRpcCall({ art: 'sletPersonHelt', subjektType: 'person', subjektId: '9007199254740993',
      payload: { previewSha256: opts.previewSha256 } })?.args.p_person_id).toBe('9007199254740993');
    expect(() => planCall({ art: 'sletPersonHelt', subjektType: 'person', subjektId: '1' }, 'redaktion')).toThrow(/Ufuldstændig/);
    expect(() => planCall({ art: 'sletPersonHelt', subjektType: 'person', subjektId: '1',
      payload: { previewSha256: opts.previewSha256 } }, 'medlem')).toThrow(/rettigheder/);
    expect(() => planCall({ art: 'kvitterPersonPurgeFil', subjektType: 'storage', subjektId: '',
      payload: { bucket: 'media', sti: 'a' } }, 'medlem')).toThrow(/rettigheder/);
  });
  it('bevarer SQLSTATE gennem submitChange, også når beskeden ikke indeholder koden', async () => {
    vi.mocked(supabase.rpc).mockResolvedValueOnce({ data: null, error: { code: '40P01', message: 'deadlock detected' } } as never);
    await expect(executeSletHelt(opts, { ...deps(), submit: submitChange })).rejects.toMatchObject({ code: '40P01' });
  });
  it('DB-fejl stopper før Storage og listen', async () => {
    const d = deps(); d.submit.mockRejectedValueOnce(new Error('PURGE_PREVIEW_AENDRET'));
    await expect(executeSletHelt(opts, d)).rejects.toThrow('PURGE_PREVIEW_AENDRET');
    expect(d.listOutbox).not.toHaveBeenCalled(); expect(d.removeObjects).not.toHaveBeenCalled();
  });
  it('kører DB → udbakke → Storage pr. bucket → kvittering pr. bekræftet fil', async () => {
    const d = deps([{ bucket: 'media', sti: 'a' }, { bucket: 'media', sti: 'b' }, { bucket: 'anden', sti: 'c' }]);
    expect(await executeSletHelt(opts, d)).toEqual({ kind: 'completed' });
    expect(d.removeObjects.mock.calls).toEqual([['media', ['a', 'b']], ['anden', ['c']]]);
    expect(d.submit).toHaveBeenCalledTimes(4);
    expect(d.submit.mock.invocationCallOrder[0]).toBeLessThan(d.listOutbox.mock.invocationCallOrder[0]);
    expect(d.listOutbox.mock.invocationCallOrder[0]).toBeLessThan(d.removeObjects.mock.invocationCallOrder[0]);
    expect(d.removeObjects.mock.invocationCallOrder[0]).toBeLessThan(d.submit.mock.invocationCallOrder[1]);
    expect(d.submit.mock.calls.slice(1).map(([c]) => c.payload)).toEqual([
      { bucket: 'media', sti: 'a' }, { bucket: 'media', sti: 'b' }, { bucket: 'anden', sti: 'c' },
    ]);
  });
  it.each(['returneret', 'kastet'])('Storage-fejl (%s) bliver advarsel uden kvittering og stopper ikke næste bucket', async (kind) => {
    const d = deps([{ bucket: 'media', sti: 'a' }, { bucket: 'anden', sti: 'b' }]);
    if (kind === 'kastet') d.removeObjects.mockRejectedValueOnce(new Error('netværk'));
    else d.removeObjects.mockResolvedValueOnce({ data: null, error: { message: 'nede' } });
    const res = await executeSletHelt(opts, d);
    expect(res.kind).toBe('completed'); expect(res.storageAdvarsel).toMatch(/venter/);
    expect(d.submit.mock.calls.slice(1).map(([c]) => c.payload)).toEqual([{ bucket: 'anden', sti: 'b' }]);
  });
  it('kvitterer kun bekræftede stier fra den rigtige bucket; tomt/delvist svar er ikke succes', async () => {
    const d = deps([{ bucket: 'media', sti: 'a' }, { bucket: 'media', sti: 'b' }]);
    d.removeObjects.mockResolvedValueOnce({ data: [{ name: 'a' }, { name: 'fremmed' }], error: null });
    expect((await executeSletHelt(opts, d)).storageAdvarsel).toMatch(/ikke bekræftet/);
    expect(d.submit).toHaveBeenCalledTimes(2);
    expect(d.submit.mock.calls[1][0].payload).toEqual({ bucket: 'media', sti: 'a' });
  });
  it('en gentaget oprydning fjerner resten uden at gentage personsletningen', async () => {
    const pending: PurgeFil[] = [{ bucket: 'media', sti: 'a' }]; const d = deps(pending);
    d.submit.mockImplementation(async (c) => {
      if (c.art === 'kvitterPersonPurgeFil') pending.splice(0, 1);
      return { dryRun: false };
    });
    d.removeObjects.mockRejectedValueOnce(new Error('nede'));
    expect((await executeSletHelt(opts, d)).storageAdvarsel).toBeTruthy(); expect(pending).toHaveLength(1);
    expect(await executePurgeOprydning(opts, d)).toEqual({ kind: 'completed' }); expect(pending).toHaveLength(0);
    expect(d.submit.mock.calls.filter(([c]) => c.art === 'sletPersonHelt')).toHaveLength(1);
  });
  it('mistet kvittering kan genforsøges, også når filen allerede er væk', async () => {
    const d = deps();
    d.submit.mockResolvedValueOnce({ dryRun: false }).mockRejectedValueOnce(new Error('kvittering nede'));
    expect((await executeSletHelt(opts, d)).storageAdvarsel).toMatch(/kvittering nede/);
    d.removeObjects.mockResolvedValueOnce({ data: [], error: null }); d.objectAbsent.mockResolvedValueOnce(true);
    expect(await executePurgeOprydning(opts, d)).toEqual({ kind: 'completed' });
    expect(d.submit.mock.calls[2][0].art).toBe('kvitterPersonPurgeFil');
  });
  it('en fejlet kvittering efterlader den ene fil og stopper ikke næste fil i samme bucket', async () => {
    const d = deps([{ bucket: 'media', sti: 'a' }, { bucket: 'media', sti: 'b' }]);
    d.submit.mockResolvedValueOnce({ dryRun: false }).mockRejectedValueOnce(new Error('kvittering nede'));
    expect((await executeSletHelt(opts, d)).storageAdvarsel).toMatch(/kvittering nede/);
    expect(d.submit).toHaveBeenCalledTimes(3);
    expect(d.submit.mock.calls[2][0].payload).toEqual({ bucket: 'media', sti: 'b' });
    expect(d.submit.mock.calls[2][1]).toEqual({ dryRun: false, role: 'redaktion' });
  });
  it('en fejlet udbakkelæsning efter commit er en advarsel', async () => {
    const d = deps(); d.listOutbox.mockRejectedValueOnce(new Error('listen nede'));
    expect(await executeSletHelt(opts, d)).toMatchObject({ kind: 'completed', storageAdvarsel: expect.stringContaining('listen nede') });
  });
  it('genforsøg respekterer dry-run uden Storage, liste eller kvittering', async () => {
    const d = deps(); expect(await executePurgeOprydning({ ...opts, dryRun: true }, d)).toEqual({ kind: 'dry-run' });
    expect(d.listOutbox).not.toHaveBeenCalled(); expect(d.submit).not.toHaveBeenCalled();
  });
  it('kvitteringskald indeholder kun bucket og sti, intet person-id', () => {
    expect(buildRpcCall({ art: 'kvitterPersonPurgeFil', subjektType: 'storage', subjektId: '',
      payload: { bucket: 'media', sti: 'sha/file.jpg' } })).toEqual({ fn: 'red_person_purge_udbakke_kvitter',
      args: { p_bucket: 'media', p_sti: 'sha/file.jpg' } });
  });
  it('fravær kræver bekræftelse: 404 accepteres, 400/403 og eksisterende objekt gør ikke', async () => {
    const exists = vi.fn(); vi.mocked(supabase.storage.from).mockReturnValue({ exists } as never);
    expect(await purgeStorage.objectAbsent('anden', 'a')).toBe(false); expect(exists).not.toHaveBeenCalled();
    exists.mockResolvedValueOnce({ data: false, error: { status: 404 } });
    expect(await purgeStorage.objectAbsent('media', 'a')).toBe(true);
    for (const status of [400, 403]) {
      exists.mockResolvedValueOnce({ data: false, error: { status } });
      expect(await purgeStorage.objectAbsent('media', 'a')).toBe(false);
    }
    exists.mockResolvedValueOnce({ data: true, error: null });
    expect(await purgeStorage.objectAbsent('media', 'a')).toBe(false);
  });
});
