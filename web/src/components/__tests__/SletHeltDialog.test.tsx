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
it('viser bevarede familiers indhold, der slettes, vielser der står, og billeder, der skjules (review 37 P1+P2)', async () => {
  setup(preview({ familieindhold_slettes: [{ family_id: 55, fakta: [71, 72], noter: [3], narrativer: [] }],
    vielser_staar: [80], medier_skjules: [9, 12] }));
  await screen.findByText(/Familie 55: 2 fakta, 1 noter, 0 narrativer/);
  expect(screen.getByText(/indhold slettes, fordi profilen ikke er offentlig/)).toBeTruthy();
  expect(screen.getByText(/Vielser der bliver stående: 80\./)).toBeTruthy();
  expect(screen.getByText(/skjules for læserne \(en redaktør kan frigive dem igen\): 9, 12\./)).toBeTruthy();
  expect(screen.getByText(/bevares med deres koblinger til andre end profilen \(også til en bevaret familie\)/)).toBeTruthy();
});
it('viser alle kategorier af familieindhold, også en familie med kun en historie eller relation (Codex-fund B)', async () => {
  setup(preview({ familieindhold_slettes: [
    { family_id: 56, fakta: [], noter: [], narrativer: [], haendelser: [], stories: [7], relationer: [], forslag: [], historik: 2 },
    { family_id: 57, fakta: [], noter: [], narrativer: [], haendelser: [4], stories: [], relationer: [8, 9], forslag: [5], historik: 0 },
  ], vielser_staar: [] }));
  await screen.findByText(/Familie 56: 0 fakta, 0 noter, 0 narrativer, 0 hændelser, 1 historier, 0 relationer, 0 forslag, 2 historik-ændringer/);
  expect(screen.getByText(/Familie 57: 0 fakta, 0 noter, 0 narrativer, 1 hændelser, 0 historier, 2 relationer, 1 forslag, 0 historik-ændringer/)).toBeTruthy();
});
it('viser låste familiefotos og bevaret evidens på kontrollisten med link til billedet (runde 4, E)', async () => {
  setup(preview({ til_kontrol: [{ sted: 'NY-E', tabel: 'media', pk: { id: 31 }, grund: 'laast_familiefoto' },
    { sted: 'NY-E', tabel: 'citation', pk: { id: 41 }, grund: 'bevaret_evidens' }] }));
  await screen.findByText(/Låst familiefoto: tjek billedet, før det frigives igen/);
  expect(screen.getByText(/Bevaret kilde\/påstand på et låst familiefoto/)).toBeTruthy();
  expect(screen.getAllByRole('link', { name: 'Åbn stedet i Redaktion' }).map((a) => a.getAttribute('href')))
    .toEqual(['/redaktion/media/31']);
});
// Review 37 ceremoni 2: P10 (rene tal for sig), P3 (navnetræf) og R37P11-3 (vejen ud af knudepunkt-blokeringen).
it('viser navnetræf og ændringssæt med forklaring, og rene id-tal i en særskilt, sammenklappet gruppe (P10)', async () => {
  setup(preview({ til_kontrol: [
    { sted: 'S58', tabel: 'story', pk: { id: 5 }, grund: 'fritekst' },
    { sted: 'S57', tabel: 'change_set', pk: { id: 6 }, grund: 'bevaret_summary' },
    { sted: 'S58', tabel: 'note', pk: { id: 7 }, grund: 'kun_id' },
    { sted: 'S34b', tabel: 'suggestion', pk: { id: 9 }, grund: 'kun_id' }] }));
  await screen.findByText(/Teksten nævner profilens navn/);
  expect(screen.getByText(/Et bevaret ændringssæts beskrivelse kan nævne profilen/)).toBeTruthy();
  const gruppe = screen.getByText('Kun et id-tal (2) — ofte et årstal, sidetal eller en anden talværdi i kildedata').closest('details')!;
  expect(gruppe.open).toBe(false);
  expect(gruppe.textContent).toMatch(/note/); expect(gruppe.textContent).toMatch(/suggestion/);
  expect(gruppe.textContent).not.toMatch(/story/);
  const links = screen.getAllByRole('link').filter((a) => a.getAttribute('href')?.startsWith('#purge-kontrol-'));
  expect(links).toHaveLength(4);
  for (const link of links) expect(document.getElementById(link.getAttribute('href')!.slice(1))).toBeTruthy();
});
it('en id-henvisning (personens id under en person-nøgle) vises åbent med forklaring, ikke i id-tal-gruppen (ceremoni 2b)', async () => {
  setup(preview({ til_kontrol: [
    { sted: 'S58', tabel: 'private.source_persona_identity_candidate', pk: { id: 'uuid-1' }, grund: 'id_henvisning' },
    { sted: 'S58', tabel: 'note', pk: { id: 7 }, grund: 'kun_id' }] }));
  const tekst = await screen.findByText(/En kildedata-række henviser til profilen med dens id/);
  expect(tekst.closest('details')).toBeNull();
  const gruppe = screen.getByText(/^Kun et id-tal \(1\)/).closest('details')!;
  expect(gruppe.textContent).not.toMatch(/source_persona_identity_candidate/);
});
it('uden rene id-tal vises ingen id-tal-gruppe', async () => {
  setup(); await screen.findByText('Slet helt · Rå profil · id 1791');
  expect(screen.queryByText(/Kun et id-tal/)).toBeNull();
});
it('knudepunkt-blokeringen fortæller vejen: fjern koblingerne under »Samme person« (R37P11-3)', async () => {
  setup(preview({ blokeringer: [{ art: 'samme_som_knudepunkt', antal: 2 }] }));
  await screen.findByText(/Profilen er knudepunkt for andre profiler\. Fjern først koblingerne under »Samme person« på profilens redigeringsside, og hent så en ny forhåndsvisning\./);
});
it('et preview uden de nye nøgler (database før ændringen) vises uden vielse- og billedlinje', async () => {
  setup(); await screen.findByText('Slet helt · Rå profil · id 1791');
  expect(screen.queryByText(/indhold slettes/)).toBeNull(); expect(screen.queryByText(/Vielser der bliver stående/)).toBeNull(); expect(screen.queryByText(/skjules for læserne/)).toBeNull();
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
const AENDRET = 'Noget ændrede sig undervejs — intet er slettet. Prøv igen.';
it.each([
  ['PURGE_PREVIEW_AENDRET', { message: 'PURGE_PREVIEW_AENDRET' }, AENDRET],
  ['PURGE_LOCKSET_DRIFT', { message: 'PURGE_LOCKSET_DRIFT' }, AENDRET],
  ['PURGE_REST', { message: 'PURGE_REST: S52' }, AENDRET],
  ['40P01', { code: '40P01', message: 'deadlock detected' }, AENDRET],
  ['55P03', { code: '55P03', message: 'canceling statement due to lock timeout' }, AENDRET],
  ['57014', { code: '57014', message: 'canceling statement due to statement timeout' },
    'Det tog for lang tid — intet er slettet. Prøv igen.'],
])('%s viser prøv igen og kræver et nyt preview og en ny id-bekræftelse', async (_name, error, tekst) => {
  const execute = vi.fn().mockRejectedValueOnce(error).mockResolvedValueOnce({ kind: 'completed' });
  const p = setup(preview(), execute); await typeId(); fireEvent.click(button());
  await screen.findByText(tekst);
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
it.each(['P0001', 'XX000'])('andre fejl (%s) viser kode og besked råt, uden stacktrace eller staging-kvittering', async (code) => {
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

// Review 37 P5: sletningen lykkedes, men svaret gik tabt. Det næste kald møder PURGE_FINDES_IKKE: dialogen viser ikke
// en rå fejl, men rydder filerne op og melder profilen slettet.
it('tabt svar: afbrudt forbindelse, så PURGE_FINDES_IKKE ved genhentning → oprydning og onDeleted (P5)', async () => {
  const load = vi.fn().mockResolvedValueOnce(preview()).mockRejectedValueOnce({ code: 'P0001', message: 'PURGE_FINDES_IKKE' });
  const execute = vi.fn().mockRejectedValue({ message: 'TypeError: Failed to fetch' });
  const oprydning = vi.fn().mockResolvedValue({ kind: 'completed' });
  const onDeleted = vi.fn();
  render(<SletHeltDialog personId="1791" navn="Profil" dryRun={false} loadPreview={load} execute={execute}
    oprydning={oprydning} onDeleted={onDeleted} onClose={vi.fn()} />);
  await typeId(); fireEvent.click(button());
  await screen.findByText(/Forbindelsen blev afbrudt/);
  expect(onDeleted).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole('button', { name: 'Hent ny forhåndsvisning' }));
  await screen.findByText(/Profilen var allerede slettet/);
  expect(oprydning).toHaveBeenCalledTimes(1); expect(onDeleted).toHaveBeenCalledTimes(1);
  expect(screen.queryByText(/PURGE_FINDES_IKKE/)).toBeNull();
});
it('PURGE_FINDES_IKKE direkte fra sletningen → oprydning; i dry-run kun beskeden (P5)', async () => {
  const oprydning = vi.fn().mockResolvedValue({ kind: 'completed', storageAdvarsel: 'Filer venter stadig' });
  const props = { personId: '1791', navn: 'P', loadPreview: vi.fn().mockResolvedValue(preview()),
    execute: vi.fn().mockRejectedValue({ message: 'PURGE_FINDES_IKKE' }), oprydning, onDeleted: vi.fn(), onClose: vi.fn() };
  const { unmount } = render(<SletHeltDialog {...props} dryRun={false} />);
  await typeId(); fireEvent.click(button());
  await screen.findByText(/Profilen var allerede slettet/); await screen.findByText('Filer venter stadig');
  expect(props.onDeleted).toHaveBeenCalledTimes(1);
  unmount();
  const dry = { ...props, oprydning: vi.fn(), onDeleted: vi.fn() };
  render(<SletHeltDialog {...dry} dryRun />);
  await typeId(); fireEvent.click(button());
  await screen.findByText('Profilen findes ikke længere — den er allerede slettet.');
  expect(dry.oprydning).not.toHaveBeenCalled(); expect(dry.onDeleted).not.toHaveBeenCalled();
});

// Review 37 P6: felterne fra RPC'en vises, og tabeller står med danske navne i stedet for rå stedkoder.
it('viser filer, historik, samme person og forældede, og tabeller med navne (P6)', async () => {
  setup(preview({
    steder: { S37b: [{ tabel: 'media', pk: { id: 9 }, handling: 'skjul', grund: 'x' }],
      S1: [{ tabel: 'person', pk: { id: 1791 }, handling: 'slet', grund: 'egen' }],
      S58: [{ tabel: 'private.interpretation_promotion', pk: { id: 'u' }, handling: 'slet', grund: 'y' }] },
    storage: [{ bucket: 'media', sti: 'a/b.jpg' }, { bucket: 'media', sti: 'a/c.jpg' }],
    historik: { events: 12, saet: 3 }, samme_som_komponent: [1791, 2001],
    'forældes': { narrativer: [44], bindinger: [] },
  }));
  await screen.findByText('Det sker med data');
  expect(screen.getByText('Billeder og filer: skjules for læserne (1)')).toBeTruthy();
  expect(screen.getByText('Profilen: slettes (1)')).toBeTruthy();
  expect(screen.getByText('Interne spor (interpretation_promotion): slettes (1)')).toBeTruthy();
  expect(screen.getByText('2 filer i lageret slettes efter databasen.')).toBeTruthy();
  expect(screen.getByText(/12 ændringer i 3 ændringssæt slettes/)).toBeTruthy();
  expect(screen.getByText(/koblet som samme person som: 2001\./)).toBeTruthy();
  expect(screen.getByText(/1 biografier og 0 kildebindinger bevares/)).toBeTruthy();
});
