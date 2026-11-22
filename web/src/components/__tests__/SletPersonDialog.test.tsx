// @vitest-environment jsdom
// Review 37 P11: én »Slet person…«-dialog. Systemet vælger vejen ud fra red_slet_person_preview (kan_fortrydes/aarsag).
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, expect, it, vi } from 'vitest';
import { SletPersonDialog } from '../SletPersonDialog';
import type { SletPreview } from '../../data/redaktionRead';
import type { PurgePreview } from '../../data/personPurge';
vi.mock('../../supabase', () => ({ supabase: { rpc: vi.fn(), auth: { onAuthStateChange: vi.fn() } } }));
afterEach(cleanup);

const preview = (o: Partial<SletPreview> = {}): SletPreview => ({
  antalRelationer: 2, antalFacts: 5, antalNarrativer: 1, antalBindinger: 0, antalMedlemskaber: 1, relationer: [],
  kanFortrydes: true, aarsag: null, sletningBlokeret: false, ...o,
});
const purgePreview: PurgePreview = {
  person_id: 1791, navn: 'Rå profil', sha256: 'a'.repeat(64), steder: {}, familier_slettes: [], familier_bevares: [],
  blokeringer: [], advarsler: [], til_kontrol: [], levende_bruger: false,
};
function setup(p: SletPreview | Error = preview(), o: { role?: string; slet?: () => Promise<void> } = {}) {
  const props = {
    personId: '1791', navn: 'Testperson', dryRun: false, role: o.role ?? 'redaktion',
    loadPreview: p instanceof Error ? vi.fn().mockRejectedValue(p) : vi.fn().mockResolvedValue(p),
    sletFortrydeligt: vi.fn(o.slet ?? (() => Promise.resolve())),
    executeHelt: vi.fn().mockResolvedValue({ kind: 'completed' }),
    loadPurgePreview: vi.fn().mockResolvedValue(purgePreview),
    onHeltSlettet: vi.fn(), onClose: vi.fn(),
  };
  render(<SletPersonDialog {...props} />);
  return props;
}
const primaer = () => screen.getByRole('button', { name: 'Slet (kan fortrydes)' }) as HTMLButtonElement;

it('en offentlig person: »kan fortrydes«, historikken gemmes, primær sletning efter bekræftelse', async () => {
  const p = setup();
  await screen.findByRole('heading', { name: 'Slet person — kan fortrydes' });
  expect(screen.getByText(/Historikken gemmes/)).toBeTruthy();
  expect(screen.getByText(/2 relation\(er\), 5 fakta, 1 biografi\(er\) og 1 slægts-\/linjemedlemskab/)).toBeTruthy();
  expect(primaer().disabled).toBe(true);
  fireEvent.click(screen.getByLabelText('Jeg forstår, at relationerne brydes'));
  fireEvent.click(primaer());
  await waitFor(() => expect(p.sletFortrydeligt).toHaveBeenCalledTimes(1));
  await waitFor(() => expect(p.onClose).toHaveBeenCalledTimes(1));
  expect(p.executeHelt).not.toHaveBeenCalled();
});

it('sekundærvalget går til den fulde sletnings forhåndsvisning og bekræftelse', async () => {
  const p = setup();
  fireEvent.click(await screen.findByRole('button', { name: 'Slet helt i stedet (GDPR, kan ikke fortrydes)…' }));
  await screen.findByRole('heading', { name: /^Slet helt — kan ikke fortrydes · Rå profil · id 1791$/ });
  expect(screen.getByTestId('slet-helt-valgt').textContent).toMatch(/Du har valgt den fulde sletning/);
  expect(p.loadPurgePreview).toHaveBeenCalledWith('1791');
  fireEvent.change(screen.getByLabelText('Personens id'), { target: { value: '1791' } });
  fireEvent.click(screen.getByRole('button', { name: 'Slet helt (kan ikke fortrydes)' }));
  await screen.findByText('Profilen er slettet.');
  expect(p.executeHelt).toHaveBeenCalledWith({ personId: '1791', previewSha256: 'a'.repeat(64), dryRun: false });
  expect(p.onHeltSlettet).toHaveBeenCalledTimes(1); expect(p.sletFortrydeligt).not.toHaveBeenCalled();
});

it.each([
  ['levende', /markeret som nulevende/, /Er personen død, skal markeringen rettes først/],
  ['privat', /markeret som privat/, /slå »Privat« fra på personsiden først/],
  ['staged', /uafklaret post fra en ny udgave/, /Først når udgaven er afstemt og publiceret/],
  ['samme_som_skjult', /En anden udgaves registrering af samme person/, /Er »samme som«-koblingen forkert, så fjern den først/],
  ['ukendt', /kunne ikke afgøre/, /Hent forhåndsvisningen igen/],
] as const)('en ikke-offentlig person (%s): direkte til »Slet helt — kan ikke fortrydes« med hvorfor og hvordan', async (aarsag, hvorfor, hvordan) => {
  const p = setup(preview({ kanFortrydes: false, aarsag }));
  await screen.findByRole('heading', { name: /^Slet helt — kan ikke fortrydes · / });
  const boks = screen.getByTestId('slet-helt-hvorfor').textContent ?? '';
  expect(boks).toMatch(/kan ikke slettes, så det kan fortrydes/);
  expect(boks).toMatch(hvorfor); expect(boks).toMatch(hvordan);
  expect(screen.queryByRole('button', { name: 'Slet (kan fortrydes)' })).toBeNull();
  expect(screen.getByRole('button', { name: 'Slet helt (kan ikke fortrydes)' })).toBeTruthy();
  expect(p.sletFortrydeligt).not.toHaveBeenCalled();
});

it('SLET_KRAEVER_SLET_HELT (status ændret undervejs) vises på dansk og tilbyder »Slet helt«', async () => {
  const p = setup(preview(), { slet: () => Promise.reject(new Error('SLET_KRAEVER_SLET_HELT: privat — personen er ikke offentlig')) });
  await screen.findByRole('heading', { name: 'Slet person — kan fortrydes' });
  fireEvent.click(screen.getByLabelText('Jeg forstår, at relationerne brydes'));
  fireEvent.click(primaer());
  const alert = await screen.findByRole('alert');
  expect(alert.textContent).toMatch(/kan ikke længere slettes, så det kan fortrydes/);
  expect(alert.textContent).toMatch(/markeret som privat/); expect(alert.textContent).toMatch(/Intet er slettet/);
  expect(alert.textContent).not.toMatch(/SLET_KRAEVER_SLET_HELT/);
  expect(primaer().disabled).toBe(true); expect(p.onClose).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole('button', { name: 'Slet helt…' }));
  await screen.findByRole('heading', { name: /^Slet helt — kan ikke fortrydes · / });
  expect(screen.getByTestId('slet-helt-hvorfor').textContent).toMatch(/markeret som privat/);
});

it('narrativ-publiceringshistorik: den fortrydelige sletning er spærret, den fulde tilbydes', async () => {
  setup(preview({ sletningBlokeret: true }));
  await screen.findByText(/narrativ-publiceringshistorik/);
  fireEvent.click(screen.getByLabelText('Jeg forstår, at relationerne brydes'));
  expect(primaer().disabled).toBe(true);
  expect(screen.getByRole('button', { name: 'Slet helt i stedet (GDPR, kan ikke fortrydes)…' })).toBeTruthy();
});

it('en fejlet forhåndsvisning vælger ingen vej, men kan hentes igen', async () => {
  const p = setup(new Error('netværk nede'));
  const alert = await screen.findByRole('alert');
  expect(alert.textContent).toMatch(/Forhåndsvisningen kunne ikke hentes: netværk nede/);
  expect(primaer().disabled).toBe(true);
  p.loadPreview.mockResolvedValueOnce(preview());
  fireEvent.click(screen.getByRole('button', { name: 'Hent igen' }));
  await screen.findByText(/Historikken gemmes/);
  expect(p.loadPreview).toHaveBeenCalledTimes(2);
});

it('uden redaktørrolle: intet preview, sletningen sendes som forslag', async () => {
  const p = setup(preview(), { role: 'medlem' });
  await screen.findByRole('heading', { name: 'Foreslå sletning' });
  expect(p.loadPreview).not.toHaveBeenCalled();
  expect(screen.queryByRole('button', { name: /Slet helt/ })).toBeNull();
  fireEvent.click(screen.getByLabelText('Jeg forstår, at relationerne brydes'));
  fireEvent.click(screen.getByRole('button', { name: 'Send forslag om sletning' }));
  await waitFor(() => expect(p.sletFortrydeligt).toHaveBeenCalledTimes(1));
});
