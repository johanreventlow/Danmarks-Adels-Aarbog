import { cleanupUdrensStorage } from '../mediaUdrens';

describe('cleanupUdrensStorage', () => {
  it('grupperer de returnerede stier pr. bucket', async () => {
    const removeObjects = jest.fn().mockResolvedValue({ error: null });

    const warning = await cleanupUdrensStorage({
      stier: [
        { bucket: 'media', sti: 'a.jpg' },
        { bucket: 'media', sti: 'b.jpg' },
        { bucket: 'arkiv', sti: 'c.jpg' },
      ],
    }, removeObjects);

    expect(removeObjects).toHaveBeenCalledTimes(2);
    expect(removeObjects).toHaveBeenCalledWith('media', ['a.jpg', 'b.jpg']);
    expect(removeObjects).toHaveBeenCalledWith('arkiv', ['c.jpg']);
    expect(warning).toBeNull();
  });

  it('gør et resolved Storage-error til en advarsel efter DB-sletningen', async () => {
    const removeObjects = jest.fn().mockResolvedValue({ error: { message: 'storage nede' } });

    const warning = await cleanupUdrensStorage({
      stier: [{ bucket: 'media', sti: 'a.jpg' }],
    }, removeObjects);

    expect(warning).toMatch(/Rækken er slettet/);
    expect(warning).toMatch(/storage nede/);
    expect(warning).toMatch(/janitoren/);
  });

  it('gør en kastet Storage-rejection til en advarsel og fortsætter næste bucket', async () => {
    const removeObjects = jest.fn()
      .mockRejectedValueOnce(new Error('netværksfejl'))
      .mockResolvedValueOnce({ error: null });

    const warning = await cleanupUdrensStorage({
      stier: [
        { bucket: 'a', sti: '1.jpg' },
        { bucket: 'b', sti: '2.jpg' },
      ],
    }, removeObjects);

    expect(removeObjects).toHaveBeenCalledTimes(2);
    expect(warning).toMatch(/Rækken er slettet/);
    expect(warning).toMatch(/netværksfejl/);
    expect(warning).toMatch(/janitoren/);
  });
});
