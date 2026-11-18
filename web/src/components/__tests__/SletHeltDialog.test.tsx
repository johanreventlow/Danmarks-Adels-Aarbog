// @vitest-environment jsdom
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, expect, it, vi } from 'vitest';
import { SletHeltDialog } from '../SletHeltDialog';
import type { PurgePreview } from '../../data/personPurge';
vi.mock('../../supabase', () => ({ supabase: { rpc: vi.fn() } }));
afterEach(cleanup);
const preview = (overrides: Partial<PurgePreview> = {}): PurgePreview => ({
  person_id: 1791, navn: 'Rå profil', sha256: 'a'.repeat(64),
  steder: { S1: [{ tabel: 'person', pk: { id: 1791 }, handling: 'slet', grund: 'egen' }] },
  familier_slettes: [54], familier_bevares: [55], blokeringer: [],
  advarsler: [{ art: 'fortrydelse_mistes', niveau: 'advarsel', batch_id: 'batch' }],
  til_kontrol: [{ sted: 'S58', tabel: 'narrative', pk: { id: 8 }, grund: 'muligt navn' },
    { sted: 'S58', tabel: 'private.interpretation', pk: { id: 'uuid' }, grund: 'fritekst' }],
  levende_bruger: true, ...overrides,
});
function setup(p = preview(), execute = vi.fn().mockResolvedValue({ kind: 'completed' })) {
  const props = { personId: '1791', navn: 'Listeprofil', dryRun: false, loadPreview: vi.fn().mockResolvedValue(p),
    execute, onDeleted: vi.fn(), onClose: vi.fn() };
  render(<SletHeltDialog {...props} />); return props;
}
const button = () => screen.getByRole('button', { name: 'Slet helt (kan ikke fortrydes)' }) as HTMLButtonElement;
async function typeId(id = '1791') {
  fireEvent.change(await screen.findByLabelText('Personens id'), { target: { value: id } });
}
it('viser råt navn/id, antal, familier, blokeringer, advarsler og link til hvert kontrolsted', async () => {
  setup(); await screen.findByText('Slet helt · Rå profil · id 1791');
  expect(screen.getByText(/den rå profil/)).toBeTruthy(); expect(screen.getByText(/S1: 1/)).toBeTruthy();
  expect(screen.getByText(/Slettes: 54. Bevares: 55/)).toBeTruthy();
  expect(screen.getByText(/fortrydelse_mistes/)).toBeTruthy(); expect(screen.getByText(/levende bruger/)).toBeTruthy();
  const links = screen.getAllByRole('link').filter((a) => a.getAttribute('href')?.startsWith('#purge-kontrol-'));
  expect(links).toHaveLength(2);
  for (const link of links) expect(document.getElementById(link.getAttribute('href')!.slice(1))).toBeTruthy();
  expect(screen.getByRole('link', { name: 'Åbn stedet i Redaktion' }).getAttribute('href')).toBe('/redaktion/narrative/8');
});
it.each(['', '179', ' 1791', '1791 ', '01791'])('kalder aldrig sletning ved forkert id: %j', async (id) => {
  const p = setup(); await typeId(id); expect(button().disabled).toBe(true);
  fireEvent.click(button()); expect(p.execute).not.toHaveBeenCalled();
});
it('kalder aldrig sletning ved blokering, heller ikke med præcist id', async () => {
  const p = setup(preview({ blokeringer: [{ art: 'link_i_tekst' }] }));
  await typeId(); expect(button().disabled).toBe(true); fireEvent.click(button());
  expect(p.execute).not.toHaveBeenCalled(); expect(screen.getByText(/link_i_tekst/)).toBeTruthy();
});
it('sender det viste previews hash med korrekt id og dryRun og viser Storage-advarsel efter succes', async () => {
  const execute = vi.fn().mockResolvedValue({ kind: 'completed', storageAdvarsel: 'Filer venter stadig' });
  const p = setup(preview(), execute); await typeId(); fireEvent.click(button());
  await screen.findByText('Profilen er slettet.');
  expect(execute).toHaveBeenCalledWith({ personId: '1791', previewSha256: 'a'.repeat(64), dryRun: false });
  expect(p.onDeleted).toHaveBeenCalledTimes(1); expect(screen.getByRole('alert').textContent).toBe('Filer venter stadig');
  expect(button().disabled).toBe(true);
});
it('dialogens dry-run sendes til sletningen og markerer ikke profilen slettet', async () => {
  const execute = vi.fn().mockResolvedValue({ kind: 'dry-run' }); const onDeleted = vi.fn();
  render(<SletHeltDialog personId="1791" navn="Profil" dryRun loadPreview={vi.fn().mockResolvedValue(preview())}
    execute={execute} onDeleted={onDeleted} onClose={vi.fn()} />);
  await typeId(); fireEvent.click(button()); await screen.findByText('Dry-run: ingen data eller filer er slettet.');
  expect(execute).toHaveBeenCalledWith(expect.objectContaining({ dryRun: true })); expect(onDeleted).not.toHaveBeenCalled();
});
it.each([
  ['PURGE_PREVIEW_AENDRET', { message: 'PURGE_PREVIEW_AENDRET' }],
  ['PURGE_LOCKSET_DRIFT', { message: 'PURGE_LOCKSET_DRIFT' }],
  ['PURGE_REST', { message: 'PURGE_REST: S52' }],
  ['40P01', { code: '40P01', message: 'deadlock detected' }],
  ['55P03', { code: '55P03', message: 'canceling statement due to lock timeout' }],
])('%s viser prøv igen og kræver et nyt preview og en ny id-bekræftelse', async (_name, error) => {
  const execute = vi.fn().mockRejectedValueOnce(error).mockResolvedValueOnce({ kind: 'completed' });
  const p = setup(preview(), execute); await typeId(); fireEvent.click(button());
  await screen.findByText('Noget ændrede sig undervejs — intet er slettet. Prøv igen.');
  expect(p.onDeleted).not.toHaveBeenCalled(); expect(button().disabled).toBe(true);
  expect(screen.queryByText(/Forslag i staging/)).toBeNull();
  p.loadPreview.mockResolvedValueOnce(preview({ sha256: 'b'.repeat(64) }));
  fireEvent.click(screen.getByRole('button', { name: 'Hent ny forhåndsvisning' }));
  await waitFor(() => expect(p.loadPreview).toHaveBeenCalledTimes(2));
  await waitFor(() => expect((screen.getByLabelText('Personens id') as HTMLInputElement).value).toBe(''));
  expect(button().disabled).toBe(true); await typeId(); fireEvent.click(button());
  await screen.findByText('Profilen er slettet.');
  expect(execute).toHaveBeenLastCalledWith(expect.objectContaining({ previewSha256: 'b'.repeat(64) }));
});
it('PURGE_BLOKERET vises som blokering og deaktiverer handlingen', async () => {
  const p = setup(preview(), vi.fn().mockRejectedValue({ message: 'PURGE_BLOKERET: anden_promotion' }));
  await typeId(); fireEvent.click(button()); await screen.findByText('Blokering: PURGE_BLOKERET: anden_promotion');
  expect(button().disabled).toBe(true); expect(p.onDeleted).not.toHaveBeenCalled();
});
it.each(['P0001', '57014'])('andre fejl (%s) viser kode og besked råt, uden stacktrace eller staging-kvittering', async (code) => {
  setup(preview(), vi.fn().mockRejectedValue({ code, message: 'PURGE_FREMMED_CHANGE_SET', stack: 'hemmelig stack' }));
  await typeId(); fireEvent.click(button()); await screen.findByText(`${code}: PURGE_FREMMED_CHANGE_SET`);
  expect(screen.queryByText(/hemmelig stack|Forslag i staging/)).toBeNull();
});
it('fejl ved hentning har ingen aktiv sletteknap og kan genhentes', async () => {
  const load = vi.fn().mockRejectedValueOnce({ message: 'preview nede' }).mockResolvedValueOnce(preview());
  const execute = vi.fn();
  render(<SletHeltDialog personId="1791" navn="Profil" dryRun={false} loadPreview={load}
    execute={execute} onDeleted={vi.fn()} onClose={vi.fn()} />);
  await screen.findByText('preview nede'); expect(button().disabled).toBe(true);
  fireEvent.click(screen.getByRole('button', { name: 'Hent ny forhåndsvisning' })); await typeId();
  expect(button().disabled).toBe(false); expect(execute).not.toHaveBeenCalled();
});
it('et preview for et andet id autoriserer aldrig sletning', async () => {
  const p = setup(preview({ person_id: 2 })); await screen.findByText('Ugyldig forhåndsvisning');
  expect(button().disabled).toBe(true); expect(p.execute).not.toHaveBeenCalled();
});
it('forhindrer dobbeltklik og lukning mens sletningen afventer', async () => {
  let resolve!: (value: { kind: 'completed' }) => void;
  const p = setup(preview(), vi.fn().mockReturnValue(new Promise((r) => { resolve = r; })));
  await typeId(); fireEvent.click(button()); fireEvent.click(button());
  expect(p.execute).toHaveBeenCalledTimes(1); expect((screen.getByRole('button', { name: 'Luk' }) as HTMLButtonElement).disabled).toBe(true);
  resolve({ kind: 'completed' }); await screen.findByText('Profilen er slettet.');
});
