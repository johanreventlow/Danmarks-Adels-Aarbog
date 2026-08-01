// @vitest-environment jsdom
// Task 9 (halvdel A): OCR-kildepanel (rent præsentations-lag — se
// docs/superpowers/plans/2026-07-26-person-ocr-kvalitetsark.md "Task 9"). Panelet henter
// intet selv (historik/busy/error kommer som props) og skriver intet selv (onSave er
// integrationens ansvar) — disse tests dækker derfor kun panelets egen adfærd: hvilket
// payload det bygger, hvornår det tillader gemning, og hvordan det viser
// historik/fejl/prøvekørsel. red_ret_ocr_felt()/red_person_grid()'s egne regler (schema.sql)
// er ikke gentestet her.
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { describe, expect, test, vi } from 'vitest';
import type { OcrFelt, PersonKvalitetsarkRow } from '@daa/core';
import { OcrKildepanel, type RetOcrFeltInput } from '../OcrKildepanel';
// oversaetOcrFejl importeres som VÆRDI (ikke kun type) for at aflede den præcise danske
// tekst OCR_FINGERPRINT_STALE oversættes til — panelets stale-detektion matcher denne tekst
// (den ser aldrig selve fejlkoden), så testen skal bevise koblingen, ikke hardkode en kopi
// af strengen der kan divergere stille fra kilden (personKvalitetsark.ts's OCR_FEJLTEKST).
import { oversaetOcrFejl, type OcrHistorikEntry } from '../../data/personKvalitetsark';

function row(overrides: Partial<PersonKvalitetsarkRow> = {}): PersonKvalitetsarkRow {
  return {
    personId: '1',
    importKey: 'daa-2018-reventlow',
    recordKey: 'p-001',
    sourceId: '7',
    sourceTitel: 'Danmarks Adels Aarbog 2018-20',
    sourceUdgave: '2018-20',
    linje: 'III',
    nr: 12,
    slaegtled: 5,
    personStatus: 'ok',
    navn: 'Christian Ditlev Reventlow',
    navnAssertionId: '501',
    foedselRaw: '12. juli 1748',
    foedselMin: '1748-07-12',
    foedselMax: '1748-07-12',
    foedselQualifier: 'exact',
    foedselAssertionId: '502',
    doedRaw: '1827',
    doedMin: '1827-01-01',
    doedMax: '1827-12-31',
    doedQualifier: null,
    doedAssertionId: '503',
    koen: 'mand',
    levende: false,
    privat: false,
    staged: false,
    kanoniskPersonId: null,
    sammeSomStatus: null,
    antalTitler: 2,
    antalFamilier: 1,
    antalRelationer: 4,
    antalKildeAssertions: 3,
    qaKoder: [],
    qaAlvor: null,
    reviewStatus: {},
    kanRettes: { navn: true, foedsel: true, doed: true, koen: true },
    blokarsager: {},
    ocrContext: { navn: 'Chr: Ditlev Reüentlow (OCR-tekst)', foedsel: '12. juli 1748', doed: '1827' },
    kildeSide: { navn: '42', foedsel: '42', doed: '43' },
    importeret: {
      navn: { value: 'Chr. Ditlev Reventlow' },
      foedsel: { raw: '12. juli 1748', min: '1748-07-12', max: '1748-07-12', qualifier: 'exact', calendar: 'gregoriansk', certainty: null },
      doed: { raw: '1827', min: '1827-01-01', max: '1827-12-31', qualifier: null, calendar: 'gregoriansk', certainty: null },
      koen: { value: 'mand' },
    },
    korrigeret: {},
    inputFingerprint: { navn: 'fp-navn', foedsel: 'fp-foedsel', doed: 'fp-doed', koen: 'fp-koen' },
    ...overrides,
  };
}

function noop() {
  // bruges hvor et prop-callback er påkrævet, men ikke selv under test
}

const historikEntry = (overrides: Partial<OcrHistorikEntry> = {}): OcrHistorikEntry => ({
  changeSetId: '10',
  changedAt: '2026-07-20T10:15:00Z',
  actorNavn: 'Anna Redaktør',
  operation: 'red_ret_ocr_felt',
  foer: null,
  efter: null,
  ...overrides,
});

function baseProps(overrides: Partial<Parameters<typeof OcrKildepanel>[0]> = {}) {
  return {
    row: row(),
    felt: 'navn' as OcrFelt,
    historik: [] as OcrHistorikEntry[],
    historikLoading: false,
    busy: false,
    error: null as string | null,
    proevekoersel: false,
    onSave: vi.fn().mockResolvedValue(undefined),
    onClose: noop as unknown as () => void,
    onOpenPerson: noop as unknown as (id: string) => void,
    onRefreshRow: vi.fn(),
    ...overrides,
  };
}

describe('OcrKildepanel — navneform', () => {
  test('gemmer navn-rettelse med præcis ét felt og rækkens aktuelle fingerprint', async () => {
    const onSave = vi.fn().mockResolvedValue(undefined);
    render(<OcrKildepanel {...baseProps({ onSave })} />);
    fireEvent.change(screen.getByLabelText('Ny værdi'), { target: { value: 'Christian Ditlev Reventlow (rettet)' } });
    fireEvent.click(screen.getByRole('button', { name: 'Gem OCR-rettelse' }));
    await waitFor(() => expect(onSave).toHaveBeenCalledTimes(1));
    const input = onSave.mock.calls[0][0] as RetOcrFeltInput;
    expect(input).toEqual({
      personId: '1',
      importKey: 'daa-2018-reventlow',
      recordKey: 'p-001',
      felt: 'navn',
      inputFingerprint: 'fp-navn',
      korrigeret: { value: 'Christian Ditlev Reventlow (rettet)' },
      status: 'rettet',
    });
  });

  test('tom navneværdi kan ikke gemmes', () => {
    render(<OcrKildepanel {...baseProps()} />);
    fireEvent.change(screen.getByLabelText('Ny værdi'), { target: { value: '   ' } });
    expect((screen.getByRole('button', { name: 'Gem OCR-rettelse' }) as HTMLButtonElement).disabled).toBe(true);
  });
});

describe('OcrKildepanel — kønform', () => {
  test('gemmer køn-rettelse som value-payload for det valgte felt alene', async () => {
    const onSave = vi.fn().mockResolvedValue(undefined);
    render(<OcrKildepanel {...baseProps({ felt: 'koen', onSave })} />);
    fireEvent.change(screen.getByLabelText('Nyt køn'), { target: { value: 'kvinde' } });
    fireEvent.click(screen.getByRole('button', { name: 'Gem OCR-rettelse' }));
    await waitFor(() => expect(onSave).toHaveBeenCalledTimes(1));
    const input = onSave.mock.calls[0][0] as RetOcrFeltInput;
    expect(input.felt).toBe('koen');
    expect(input.korrigeret).toEqual({ value: 'kvinde' });
    expect(input.inputFingerprint).toBe('fp-koen');
  });
});

describe('OcrKildepanel — datoform', () => {
  test('gyldigt årstal viser udledte grænser og gemmer dem', async () => {
    const onSave = vi.fn().mockResolvedValue(undefined);
    render(<OcrKildepanel {...baseProps({ felt: 'doed', onSave })} />);
    fireEvent.change(screen.getByLabelText('Ny rå dato'), { target: { value: '1830' } });
    expect(screen.getByText(/1830-01-01/)).toBeTruthy();
    expect(screen.getByText(/1830-12-31/)).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: 'Gem OCR-rettelse' }));
    await waitFor(() => expect(onSave).toHaveBeenCalledTimes(1));
    const input = onSave.mock.calls[0][0] as RetOcrFeltInput;
    expect(input.korrigeret).toEqual({
      raw: '1830', min: '1830-01-01', max: '1830-12-31', qualifier: null, calendar: 'gregoriansk', certainty: null,
    });
  });

  test('en eksakt dag-og-måned-dato viser et punkt-interval (min===max) og gemmer det', async () => {
    const onSave = vi.fn().mockResolvedValue(undefined);
    render(<OcrKildepanel {...baseProps({ felt: 'foedsel', onSave })} />);
    fireEvent.change(screen.getByLabelText('Ny rå dato'), { target: { value: '12. juli 1748' } });
    expect(screen.getByText(/1748-07-12.*1748-07-12/)).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: 'Gem OCR-rettelse' }));
    await waitFor(() => expect(onSave).toHaveBeenCalledTimes(1));
    const input = onSave.mock.calls[0][0] as RetOcrFeltInput;
    expect(input.korrigeret).toEqual({
      raw: '12. juli 1748', min: '1748-07-12', max: '1748-07-12', qualifier: null,
      calendar: 'gregoriansk', certainty: null,
    });
  });

  test('ufortolkelig rå dato kræver eksplicit bekræftelse før gem er muligt, og sender null-grænser', async () => {
    const onSave = vi.fn().mockResolvedValue(undefined);
    render(<OcrKildepanel {...baseProps({ felt: 'doed', onSave })} />);
    fireEvent.change(screen.getByLabelText('Ny rå dato'), { target: { value: 'uigenkendelig tekst uden årstal' } });
    expect(screen.getByText(/ikke fortolkes automatisk/)).toBeTruthy();
    expect((screen.getByRole('button', { name: 'Gem OCR-rettelse' }) as HTMLButtonElement).disabled).toBe(true);

    fireEvent.click(screen.getByLabelText(/bekræfter/i));
    expect((screen.getByRole('button', { name: 'Gem OCR-rettelse' }) as HTMLButtonElement).disabled).toBe(false);

    fireEvent.click(screen.getByRole('button', { name: 'Gem OCR-rettelse' }));
    await waitFor(() => expect(onSave).toHaveBeenCalledTimes(1));
    const input = onSave.mock.calls[0][0] as RetOcrFeltInput;
    expect(input.korrigeret).toEqual({
      raw: 'uigenkendelig tekst uden årstal', min: null, max: null, qualifier: null,
      calendar: 'gregoriansk', certainty: null,
    });
  });

  test('ændring af den rå dato efter en bekræftelse kræver bekræftelse igen', () => {
    render(<OcrKildepanel {...baseProps({ felt: 'doed' })} />);
    fireEvent.change(screen.getByLabelText('Ny rå dato'), { target: { value: 'uigenkendelig A' } });
    fireEvent.click(screen.getByLabelText(/bekræfter/i));
    expect((screen.getByRole('button', { name: 'Gem OCR-rettelse' }) as HTMLButtonElement).disabled).toBe(false);

    fireEvent.change(screen.getByLabelText('Ny rå dato'), { target: { value: 'uigenkendelig B' } });
    expect((screen.getByRole('button', { name: 'Gem OCR-rettelse' }) as HTMLButtonElement).disabled).toBe(true);
  });
});

describe('OcrKildepanel — OCR-kontekst', () => {
  test('evidensboksen hedder OCR-kontekst og indeholder den lovpligtige note', () => {
    render(<OcrKildepanel {...baseProps()} />);
    expect(screen.getByRole('heading', { name: 'OCR-kontekst' })).toBeTruthy();
    expect(
      screen.getByText('Konteksten er fra OCR-udtrækket, ikke en gengivelse af den trykte side.'),
    ).toBeTruthy();
  });

  test('påstår aldrig at vise den trykte kildeside', () => {
    const { container } = render(<OcrKildepanel {...baseProps()} />);
    expect(container.textContent).not.toMatch(/original(e)?\s+side/i);
    expect(container.textContent).not.toMatch(/facsimile/i);
  });
});

describe('OcrKildepanel — Godkend/Udskyd sender ingen rettet værdi', () => {
  test('"Godkend som korrekt" sender status godkendt, korrigeret=null, og optimistisk uændret visning', async () => {
    const onSave = vi.fn().mockResolvedValue(undefined);
    render(<OcrKildepanel {...baseProps({ onSave })} />);
    fireEvent.change(screen.getByLabelText('Ny værdi'), { target: { value: 'et helt andet udkast' } });
    fireEvent.click(screen.getByRole('button', { name: 'Godkend som korrekt' }));
    await waitFor(() => expect(onSave).toHaveBeenCalledTimes(1));
    const input = onSave.mock.calls[0][0] as RetOcrFeltInput;
    expect(input.status).toBe('godkendt');
    expect(input.korrigeret).toBeNull();
    // Ingen optimistisk mutation: den viste importerede værdi er stadig den oprindelige.
    expect(screen.getByText('Chr. Ditlev Reventlow')).toBeTruthy();
  });

  test('"Udskyd" sender status udskudt og korrigeret=null', async () => {
    const onSave = vi.fn().mockResolvedValue(undefined);
    render(<OcrKildepanel {...baseProps({ onSave })} />);
    fireEvent.click(screen.getByRole('button', { name: 'Udskyd' }));
    await waitFor(() => expect(onSave).toHaveBeenCalledTimes(1));
    const input = onSave.mock.calls[0][0] as RetOcrFeltInput;
    expect(input.status).toBe('udskudt');
    expect(input.korrigeret).toBeNull();
  });
});

describe('OcrKildepanel — historik', () => {
  test('indlæsningstilstand vises eksplicit', () => {
    render(<OcrKildepanel {...baseProps({ historikLoading: true })} />);
    expect(screen.getByText('Henter historik…')).toBeTruthy();
  });

  test('tom historik (journal findes, men er tom) vises anderledes end "ikke tilgængelig"', () => {
    render(<OcrKildepanel {...baseProps({ historik: [] })} />);
    expect(screen.getByText('Ingen rettelser endnu.')).toBeTruthy();
    expect(screen.queryByText(/ikke tilgængelig/)).toBeNull();
  });

  test('post uden importanker viser "ikke tilgængelig", ikke "ingen rettelser"', () => {
    render(
      <OcrKildepanel
        {...baseProps({
          row: row({ importKey: null, recordKey: null, kanRettes: { navn: false, foedsel: false, doed: false, koen: false } }),
          historik: [],
        })}
      />,
    );
    expect(screen.getByText(/ikke tilgængelig for denne post/)).toBeTruthy();
    expect(screen.queryByText('Ingen rettelser endnu.')).toBeNull();
  });

  test('viser aktør og tidspunkt nyeste først, i den rækkefølge props leverer (ingen re-sortering)', () => {
    const entries = [
      historikEntry({ changeSetId: '20', actorNavn: 'Ny Redaktør', changedAt: '2026-07-25T09:00:00Z' }),
      historikEntry({ changeSetId: '10', actorNavn: 'Gammel Redaktør', changedAt: '2026-07-20T09:00:00Z' }),
    ];
    const { container } = render(<OcrKildepanel {...baseProps({ historik: entries })} />);
    const items = container.querySelectorAll('li');
    expect(items).toHaveLength(2);
    expect(items[0].textContent).toMatch(/Ny Redaktør/);
    expect(items[1].textContent).toMatch(/Gammel Redaktør/);
    const times = container.querySelectorAll('time');
    expect(times[0].getAttribute('dateTime')).toBe('2026-07-25T09:00:00Z');
    expect(times[1].getAttribute('dateTime')).toBe('2026-07-20T09:00:00Z');
  });
});

describe('OcrKildepanel — blokeret felt', () => {
  test('intet gem-panel når kanRettes er false; viser blokårsag og tilbyder onOpenPerson', () => {
    const onOpenPerson = vi.fn();
    render(
      <OcrKildepanel
        {...baseProps({
          onOpenPerson,
          row: row({
            kanRettes: { navn: false, foedsel: true, doed: true, koen: true },
            blokarsager: { navn: 'flere_importerede_facts' },
          }),
        })}
      />,
    );
    expect(screen.queryByRole('button', { name: 'Gem OCR-rettelse' })).toBeNull();
    expect(screen.queryByRole('button', { name: 'Godkend som korrekt' })).toBeNull();
    expect(screen.queryByRole('button', { name: 'Udskyd' })).toBeNull();
    expect(screen.getByText(/flere kildebelagte påstande/)).toBeTruthy();
    // Ægte link (ikke knap): navigation hører til rollen 'link', og href'et er dét
    // højreklik-menuen læser når redaktøren vil åbne personen i en ny fane.
    const aabnPerson = screen.getByRole('link', { name: 'Åbn person' });
    expect(aabnPerson.getAttribute('href')).toBe('/redaktion/person/1');
    fireEvent.click(aabnPerson);
    expect(onOpenPerson).toHaveBeenCalledWith('1');
  });
});

describe('OcrKildepanel — stale fingerprint', () => {
  test('fejlen holder panelet åbent, og retry efter genindlæsning bruger det NYE fingerprint, ikke det gamle', async () => {
    const friskRække = row({ inputFingerprint: { navn: 'fp-navn-FRISK', foedsel: 'fp-foedsel', doed: 'fp-doed', koen: 'fp-koen' } });
    const onRefreshRow = vi.fn().mockResolvedValue(friskRække);
    const onSave = vi.fn().mockResolvedValue(undefined);

    const { rerender } = render(
      <OcrKildepanel
        {...baseProps({
          onSave, onRefreshRow,
          error: oversaetOcrFejl(new Error('OCR_FINGERPRINT_STALE')),
        })}
      />,
    );

    // Panelet forbliver åbent (formularen er der stadig) og tilbyder en genindlæsning.
    expect(screen.getByLabelText('Ny værdi')).toBeTruthy();
    const genindlaesKnap = screen.getByRole('button', { name: 'Genindlæs kilderække' });
    fireEvent.click(genindlaesKnap);
    await waitFor(() => expect(onRefreshRow).toHaveBeenCalledWith('1'));

    // Integrationen ville normalt rydde `error` efter en vellykket genindlæsning.
    rerender(<OcrKildepanel {...baseProps({ onSave, onRefreshRow, error: null })} />);

    fireEvent.change(screen.getByLabelText('Ny værdi'), { target: { value: 'Ny værdi efter genindlæsning' } });
    fireEvent.click(screen.getByRole('button', { name: 'Gem OCR-rettelse' }));
    await waitFor(() => expect(onSave).toHaveBeenCalledTimes(1));
    const input = onSave.mock.calls[0][0] as RetOcrFeltInput;
    expect(input.inputFingerprint).toBe('fp-navn-FRISK');
  });

  test('en generisk (ikke-stale) fejl viser ingen "Genindlæs kilderække"-knap', () => {
    render(<OcrKildepanel {...baseProps({ error: 'Noget andet gik galt.' })} />);
    expect(screen.queryByRole('button', { name: 'Genindlæs kilderække' })).toBeNull();
  });
});

describe('OcrKildepanel — prøvekørsel (kontraktfaktum 4)', () => {
  test('prøvekørsel=true blokerer al gemning og forklarer hvorfor', () => {
    render(<OcrKildepanel {...baseProps({ proevekoersel: true })} />);
    expect((screen.getByRole('button', { name: 'Gem OCR-rettelse' }) as HTMLButtonElement).disabled).toBe(true);
    expect((screen.getByRole('button', { name: 'Godkend som korrekt' }) as HTMLButtonElement).disabled).toBe(true);
    expect((screen.getByRole('button', { name: 'Udskyd' }) as HTMLButtonElement).disabled).toBe(true);
    expect(screen.getByText(/OCR-rettelser kan ikke prøvekøres/)).toBeTruthy();
  });

  test('prøvekørsel=false tillader gemning (ingen simuleret dry-run — reelt Save er muligt)', () => {
    render(<OcrKildepanel {...baseProps({ proevekoersel: false })} />);
    fireEvent.change(screen.getByLabelText('Ny værdi'), { target: { value: 'Gyldig værdi' } });
    expect((screen.getByRole('button', { name: 'Gem OCR-rettelse' }) as HTMLButtonElement).disabled).toBe(false);
    expect((screen.getByRole('button', { name: 'Godkend som korrekt' }) as HTMLButtonElement).disabled).toBe(false);
    expect((screen.getByRole('button', { name: 'Udskyd' }) as HTMLButtonElement).disabled).toBe(false);
    expect(screen.queryByText(/OCR-rettelser kan ikke prøvekøres/)).toBeNull();
  });
});

describe('OcrKildepanel — busy/fejl-tilstand', () => {
  test('busy deaktiverer skrive-knapperne', () => {
    render(<OcrKildepanel {...baseProps({ busy: true })} />);
    expect((screen.getByRole('button', { name: 'Gem OCR-rettelse' }) as HTMLButtonElement).disabled).toBe(true);
    expect((screen.getByRole('button', { name: 'Godkend som korrekt' }) as HTMLButtonElement).disabled).toBe(true);
    expect((screen.getByRole('button', { name: 'Udskyd' }) as HTMLButtonElement).disabled).toBe(true);
  });

  test('fejl vises men lukker ikke panelet, og udkastet bevares', () => {
    render(<OcrKildepanel {...baseProps({ error: 'Noget gik galt.' })} />);
    fireEvent.change(screen.getByLabelText('Ny værdi'), { target: { value: 'Mit udkast' } });
    expect(screen.getByRole('alert').textContent).toMatch('Noget gik galt.');
    expect((screen.getByLabelText('Ny værdi') as HTMLInputElement).value).toBe('Mit udkast');
  });

  test('Annuller kalder onClose', () => {
    const onClose = vi.fn();
    render(<OcrKildepanel {...baseProps({ onClose })} />);
    fireEvent.click(screen.getByRole('button', { name: 'Annuller' }));
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  test('en afvist onSave-promise lækker ikke som en uhåndteret rejection — panelet forbliver med udkastet', async () => {
    const onSave = vi.fn().mockRejectedValue(new Error('Noget gik galt på serveren'));
    render(<OcrKildepanel {...baseProps({ onSave })} />);
    fireEvent.change(screen.getByLabelText('Ny værdi'), { target: { value: 'Udkast der overlever afvisning' } });
    fireEvent.click(screen.getByRole('button', { name: 'Gem OCR-rettelse' }));
    await waitFor(() => expect(onSave).toHaveBeenCalledTimes(1));
    // Selve komponenten fanger afvisningen internt (fejlvisning ejes af `error`-proppen,
    // sat af integrationen efter kaldet); vi verificerer blot at panelet stadig står og at
    // udkastet ikke er ryddet.
    expect((screen.getByLabelText('Ny værdi') as HTMLInputElement).value).toBe('Udkast der overlever afvisning');
  });

  test('en afvist onRefreshRow-promise lækker ikke som en uhåndteret rejection', async () => {
    const onRefreshRow = vi.fn().mockRejectedValue(new Error('Kunne ikke genindlæse'));
    render(
      <OcrKildepanel
        {...baseProps({
          onRefreshRow,
          error: oversaetOcrFejl(new Error('OCR_FINGERPRINT_STALE')),
        })}
      />,
    );
    fireEvent.click(screen.getByRole('button', { name: 'Genindlæs kilderække' }));
    await waitFor(() => expect(onRefreshRow).toHaveBeenCalledTimes(1));
    // Ingen uhåndteret rejection skal undslippe testen; panelet er stadig monteret.
    expect(screen.getByRole('button', { name: 'Genindlæs kilderække' })).toBeTruthy();
  });
});
