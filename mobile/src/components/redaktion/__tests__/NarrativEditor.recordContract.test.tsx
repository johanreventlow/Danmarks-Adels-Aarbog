import { act, fireEvent, render, waitFor } from '@testing-library/react-native';

const mockFetchNarrativeEditorState = jest.fn();

jest.mock('../../../data/redaktionRead', () => ({
  fetchNarrativeEditorState: (...args: unknown[]) => mockFetchNarrativeEditorState(...args),
  fetchSources: jest.fn(() => Promise.resolve([])),
}));
jest.mock('../../NarrativRenderer', () => ({ NarrativRenderer: () => null }));
jest.mock('../MediaMentionPicker', () => ({ MediaMentionPicker: () => null }));
jest.mock('../MentionPicker', () => ({ MentionPicker: () => null }));
jest.mock('../SkrivePreviewSheet', () => ({ SkrivePreviewSheet: ({ change }: { change: unknown }) => change
  ? require('react').createElement(require('react-native').Text, null, 'Preview aktiv') : null }));

import { NarrativEditor } from '../NarrativEditor';

const props = { subjektType: 'person', subjektId: '7', media: [], mediaThumbUris: {} };

describe('NarrativEditor v2 record contract', () => {
  it('viser den autoritative tekst, men låser alle kontroller ved v2-læsefejl', async () => {
    mockFetchNarrativeEditorState.mockResolvedValue({ kind: 'readonly', tekst: 'Autoritativ tekst', privat: false, side: '',
      label: 'Kildepost', records: [{ label: 'Kildepost', tekst: 'Autoritativ tekst', privat: false, side: '' }] });
    const view = render(<NarrativEditor {...props} />);

    await waitFor(() => expect(view.getByText('Brug webredaktionen')).toBeTruthy());
    expect(view.getByDisplayValue('Autoritativ tekst').props.editable).toBe(false);
    expect(view.queryByText('Gem narrativ')).toBeNull();
  });

  it('viser kun gem-handlingen for én entydig redigerbar record', async () => {
    mockFetchNarrativeEditorState.mockResolvedValue({ kind: 'editable', tekst: 'Kladde', privat: false, side: '17',
      sourceId: 2, recordKey: 'R-17', stateSha256: 'state-hash' });
    const view = render(<NarrativEditor {...props} />);

    await waitFor(() => expect(view.getByText('Gem narrativ')).toBeTruthy());
    expect(view.getByDisplayValue('Kladde').props.editable).toBe(true);
    fireEvent.press(view.getByText('Gem narrativ'));
  });

  it('lukker et åbent preview, når næste person bliver read-only', async () => {
    mockFetchNarrativeEditorState.mockResolvedValueOnce({ kind: 'editable', tekst: 'Kladde', privat: false, side: '17',
      sourceId: 2, recordKey: 'R-17', stateSha256: 'state-hash' })
      .mockResolvedValueOnce({ kind: 'readonly', tekst: 'Anden tekst', privat: false, side: '', label: 'Flere poster',
        records: [{ label: 'Post 17', tekst: 'Kladde', privat: false, side: '17' }] });
    const view = render(<NarrativEditor {...props} />);
    await waitFor(() => expect(view.getByText('Gem narrativ')).toBeTruthy());
    fireEvent.press(view.getByText('Gem narrativ'));
    expect(view.getByText('Preview aktiv')).toBeTruthy();

    view.rerender(<NarrativEditor {...props} subjektId="8" />);
    await waitFor(() => expect(view.getByText('Brug webredaktionen')).toBeTruthy());
    expect(view.queryByText('Preview aktiv')).toBeNull();
  });

  it('bevarer den generiske ny-kilde-preview i samme editor', async () => {
    mockFetchNarrativeEditorState.mockResolvedValue({ kind: 'legacy', tekst: '', privat: false, side: '', narrativer: [] });
    const view = render(<NarrativEditor {...props} subjektType="lineage" />);
    await waitFor(() => expect(view.getByText('+ Ny udgave')).toBeTruthy());
    fireEvent.press(view.getByText('+ Ny udgave'));
    fireEvent.changeText(view.getByPlaceholderText('Titel'), 'DAA 1939');
    fireEvent.press(view.getByText('Opret'));
    expect(view.getByText('Preview aktiv')).toBeTruthy();
  });

  it('lader ikke et forsinket tidligere load overskrive den aktuelle editor', async () => {
    let resolveFirst!: (state: unknown) => void;
    let resolveSecond!: (state: unknown) => void;
    mockFetchNarrativeEditorState.mockReset()
      .mockImplementationOnce(() => new Promise((resolve) => { resolveFirst = resolve; }))
      .mockImplementationOnce(() => new Promise((resolve) => { resolveSecond = resolve; }));
    const view = render(<NarrativEditor {...props} />);
    view.rerender(<NarrativEditor {...props} subjektId="8" />);

    await act(async () => { resolveSecond({ kind: 'readonly', tekst: 'Aktuel tekst', privat: false, side: '', label: 'Aktuel',
      records: [{ label: 'Aktuel', tekst: 'Aktuel tekst', privat: false, side: '' }] }); await Promise.resolve(); });
    await waitFor(() => expect(view.getByDisplayValue('Aktuel tekst')).toBeTruthy());
    await act(async () => { resolveFirst({ kind: 'readonly', tekst: 'Gammel tekst', privat: false, side: '', label: 'Gammel',
      records: [{ label: 'Gammel', tekst: 'Gammel tekst', privat: false, side: '' }] }); await Promise.resolve(); });
    expect(view.queryByDisplayValue('Gammel tekst')).toBeNull();
  });
});
