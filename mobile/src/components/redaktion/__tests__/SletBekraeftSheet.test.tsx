// Review 37 P11: mobilens sletteark vælger vej ud fra forhåndsvisningen. Kun en offentlig person kan slettes her
// (fortrydeligt); ellers forklaring + henvisning til web-redaktionens fulde sletning, og ingen sletteknap.
import { fireEvent, render, waitFor } from '@testing-library/react-native';

const mockFetchSletPreview = jest.fn();
const mockSubmitChange = jest.fn();

jest.mock('../../../data/redaktionRead', () => ({
  fetchSletPreview: (...args: unknown[]) => mockFetchSletPreview(...args),
}));
jest.mock('../../../data/redaktionWrite', () => ({
  ...jest.requireActual('../../../data/redaktionWrite'),
  submitChange: (...args: unknown[]) => mockSubmitChange(...args),
}));
jest.mock('../../../store/useStore', () => ({
  useStore: (sel: (s: { dryRun: boolean; model: null }) => unknown) => sel({ dryRun: false, model: null }),
}));

import { SletBekraeftSheet } from '../SletBekraeftSheet';

const preview = (o: Record<string, unknown> = {}) => ({
  antalRelationer: 1, antalFacts: 2, antalNarrativer: 0, antalBindinger: 0, antalMedlemskaber: 0, relationer: [],
  kanFortrydes: true, aarsag: null, sletningBlokeret: false, ...o,
});

beforeEach(() => { mockFetchSletPreview.mockReset(); mockSubmitChange.mockReset(); });

describe('SletBekraeftSheet (review 37 P11)', () => {
  it('offentlig person: »kan fortrydes« og sletning efter bekræftelse', async () => {
    mockFetchSletPreview.mockResolvedValue(preview());
    mockSubmitChange.mockResolvedValue({ dryRun: false });
    const onDeleted = jest.fn();
    const view = render(<SletBekraeftSheet personId="7" onClose={jest.fn()} onDeleted={onDeleted} />);
    await waitFor(() => expect(view.getByText('Slet person — kan fortrydes')).toBeTruthy());
    expect(view.getByText(/Historikken gemmes/)).toBeTruthy();
    fireEvent.press(view.getByText('Jeg bekræfter at personen skal slettes'));
    fireEvent.press(view.getByText(/Slet \(kan fortrydes\)/));
    await waitFor(() => expect(onDeleted).toHaveBeenCalledTimes(1));
    expect(mockSubmitChange).toHaveBeenCalledWith({ art: 'sletPerson', subjektType: 'person', subjektId: '7' }, { dryRun: false });
  });

  it.each([
    ['levende', /markeret som nulevende/],
    ['privat', /markeret som privat/],
    ['staged', /uafklaret post fra en ny udgave/],
    ['samme_som_skjult', /En anden udgaves registrering af samme person/],
  ])('ikke-offentlig (%s): forklaring, henvisning til web, ingen sletteknap', async (aarsag, hvorfor) => {
    mockFetchSletPreview.mockResolvedValue(preview({ kanFortrydes: false, aarsag }));
    const view = render(<SletBekraeftSheet personId="7" onClose={jest.fn()} onDeleted={jest.fn()} />);
    await waitFor(() => expect(view.getByText('Slet helt — kan ikke fortrydes')).toBeTruthy());
    expect(view.getByText(hvorfor)).toBeTruthy();
    expect(view.getByText(/findes kun i web-redaktionen/)).toBeTruthy();
    expect(view.queryByText(/Slet \(kan fortrydes\)/)).toBeNull();
    expect(view.queryByText('Jeg bekræfter at personen skal slettes')).toBeNull();
    expect(mockSubmitChange).not.toHaveBeenCalled();
  });

  it('SLET_KRAEVER_SLET_HELT vises på dansk og slår sletningen fra', async () => {
    mockFetchSletPreview.mockResolvedValue(preview());
    mockSubmitChange.mockRejectedValue(new Error('SLET_KRAEVER_SLET_HELT: levende — personen er ikke offentlig'));
    const onDeleted = jest.fn();
    const view = render(<SletBekraeftSheet personId="7" onClose={jest.fn()} onDeleted={onDeleted} />);
    await waitFor(() => expect(view.getByText('Jeg bekræfter at personen skal slettes')).toBeTruthy());
    fireEvent.press(view.getByText('Jeg bekræfter at personen skal slettes'));
    fireEvent.press(view.getByText(/Slet \(kan fortrydes\)/));
    await waitFor(() => expect(view.getByText(/kan ikke længere slettes, så det kan fortrydes/)).toBeTruthy());
    expect(view.getByText(/Den fulde sletning findes kun i web-redaktionen/)).toBeTruthy();
    expect(view.queryByText(/SLET_KRAEVER_SLET_HELT/)).toBeNull();
    expect(view.queryByText(/Slet \(kan fortrydes\)/)).toBeNull();
    expect(onDeleted).not.toHaveBeenCalled();
  });

  it('en fejlet forhåndsvisning åbner ikke den fortrydelige vej', async () => {
    mockFetchSletPreview.mockRejectedValue(new Error('netværk nede'));
    const view = render(<SletBekraeftSheet personId="7" onClose={jest.fn()} onDeleted={jest.fn()} />);
    await waitFor(() => expect(view.getByText(/Forhåndsvisningen kunne ikke hentes: netværk nede/)).toBeTruthy());
    expect(view.queryByText(/Slet \(kan fortrydes\)/)).toBeNull();
  });
});
