import { describe, expect, it, vi } from 'vitest';
import { executeUdrens } from '../mediaUdrens';

describe('executeUdrens (fase 4 — dryRun-threading-regressionstest, PR #72-læringen)', () => {
  it('dry-run: submitChange kaldes med dryRun=true og storage røres ALDRIG', async () => {
    const submit = vi.fn().mockResolvedValue({ dryRun: true });
    const removeObjects = vi.fn();
    const res = await executeUdrens({ mediaId: '9', dryRun: true, role: 'redaktion' }, { submit, removeObjects });
    expect(submit).toHaveBeenCalledWith(expect.objectContaining({ art: 'udrensMedia' }),
      expect.objectContaining({ dryRun: true }));
    expect(removeObjects).not.toHaveBeenCalled();
    expect(res.kind).toBe('dry-run');
  });

  it('live: sletter de RETURNEREDE stier grupperet pr. bucket', async () => {
    const submit = vi.fn().mockResolvedValue({ dryRun: false,
      result: { stier: [{ bucket: 'media', sti: 'a.jpg' }, { bucket: 'media', sti: 'b.jpg' }] } });
    const removeObjects = vi.fn().mockResolvedValue({ error: null });
    const res = await executeUdrens({ mediaId: '9', dryRun: false, role: 'redaktion' }, { submit, removeObjects });
    expect(removeObjects).toHaveBeenCalledWith('media', ['a.jpg', 'b.jpg']);
    expect(res).toEqual({ kind: 'completed' });
  });

  it('fejlet storage-kald bliver en ADVARSEL, ikke en fejlet udrensning (DB er sandheden)', async () => {
    const submit = vi.fn().mockResolvedValue({ dryRun: false, result: { stier: [{ bucket: 'media', sti: 'a.jpg' }] } });
    const removeObjects = vi.fn().mockResolvedValue({ error: { message: 'nede' } });
    const res = await executeUdrens({ mediaId: '9', dryRun: false, role: 'redaktion' }, { submit, removeObjects });
    expect(res.kind).toBe('completed');
    expect(res.storageAdvarsel).toMatch(/janitor/i);
  });

  it('AFVIST (throw) storage-kald bliver også en ADVARSEL, ikke en propaget exception (Codex-fund)', async () => {
    const submit = vi.fn().mockResolvedValue({ dryRun: false, result: { stier: [{ bucket: 'media', sti: 'a.jpg' }] } });
    const removeObjects = vi.fn().mockRejectedValue(new Error('netværksfejl'));
    const res = await executeUdrens({ mediaId: '9', dryRun: false, role: 'redaktion' }, { submit, removeObjects });
    expect(res.kind).toBe('completed');
    expect(res.storageAdvarsel).toMatch(/janitor/i);
  });

  it('bucket EFTER en afvist ombringes stadig — én kastende bucket stopper ikke resten', async () => {
    const submit = vi.fn().mockResolvedValue({ dryRun: false, result: {
      stier: [{ bucket: 'a', sti: '1.jpg' }, { bucket: 'b', sti: '2.jpg' }] } });
    const removeObjects = vi.fn()
      .mockRejectedValueOnce(new Error('netværksfejl'))
      .mockResolvedValueOnce({ error: null });
    const res = await executeUdrens({ mediaId: '9', dryRun: false, role: 'redaktion' }, { submit, removeObjects });
    expect(removeObjects).toHaveBeenCalledTimes(2);
    expect(res.kind).toBe('completed');
    expect(res.storageAdvarsel).toMatch(/janitor/i);
  });
});
