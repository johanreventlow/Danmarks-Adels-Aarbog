// @vitest-environment jsdom
// Task 8: spreadsheet-grid til personkontrol (rent præsentations-lag — se
// docs/superpowers/plans/2026-07-26-person-ocr-kvalitetsark.md "Task 8"). Komponenten
// modtager rows som prop; den henter ikke selv data (det er task 7's dataadapter) og
// skriver intet (det er task 9's sidepanel). Bruger @daa/core's rene filterKvalitetsark/
// sortKvalitetsark — disse tests dækker derfor kun UI-forbindelsen til dem, ikke deres
// egen logik (den er allerede testet i packages/core).
import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, test, vi } from 'vitest';
import type { OcrFelt, PersonKvalitetsarkRow } from '@daa/core';
import { PersonKvalitetsark } from '../PersonKvalitetsark';

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
    ocrContext: {},
    kildeSide: {},
    importeret: {},
    korrigeret: {},
    inputFingerprint: {},
    ...overrides,
  };
}

function noop() {
  // bruges hvor et prop-callback er påkrævet, men ikke selv under test
}

const baseProps = {
  loading: false,
  error: null as string | null,
  selected: null as { personId: string; felt: OcrFelt } | null,
  onSelect: noop as unknown as (s: { personId: string; felt: OcrFelt }) => void,
  onOpenPerson: noop as unknown as (id: string) => void,
};

describe('PersonKvalitetsark — fysiske rækker (ingen samme_som-collapse)', () => {
  test('viser begge fysiske personer selvom de deler kanonisk person', () => {
    const rows = [
      row({ personId: '1', navn: 'Detlev Reventlow', kanoniskPersonId: '999', sammeSomStatus: 'sikker' }),
      row({ personId: '2', navn: 'Detlev Reventlow', kanoniskPersonId: '999', sammeSomStatus: 'sikker' }),
    ];
    render(<PersonKvalitetsark rows={rows} {...baseProps} onSelect={vi.fn()} onOpenPerson={vi.fn()} />);
    expect(screen.getAllByText('Detlev Reventlow')).toHaveLength(2);
    expect(screen.getByText(/Viser 2 af 2 personer/)).toBeTruthy();
  });

  test('person uden importanker er synlig, viser blokeringsårsag og tilbyder onOpenPerson — ingen "null"-tekst', () => {
    const onOpenPerson = vi.fn();
    const rows = [
      row({
        personId: '9', navn: 'Uden Anker', sourceId: null, importKey: null, recordKey: null,
        sourceTitel: null, sourceUdgave: null, foedselRaw: null, foedselMin: null,
        doedRaw: null, doedMin: null, koen: null,
        kanRettes: { navn: false, foedsel: false, doed: false, koen: false },
        blokarsager: {
          navn: 'ingen_importanker', foedsel: 'ingen_importanker',
          doed: 'ingen_importanker', koen: 'ingen_importanker',
        },
      }),
    ];
    const { container } = render(
      <PersonKvalitetsark rows={rows} {...baseProps} onSelect={vi.fn()} onOpenPerson={onOpenPerson} />,
    );
    expect(screen.getByText('Uden Anker')).toBeTruthy();
    expect(container.textContent).not.toMatch(/\bnull\b/);
    const navnCelle = screen.getByRole('button', { name: 'Uden Anker' });
    expect(navnCelle.getAttribute('aria-disabled')).toBe('true');
    navnCelle.focus();
    expect(document.activeElement).toBe(navnCelle);
    fireEvent.click(navnCelle);
    const [aabnKnap] = screen.getAllByRole('link', { name: 'Åbn person' });
    fireEvent.click(aabnKnap);
    expect(onOpenPerson).toHaveBeenCalledWith('9');
  });
});

describe('PersonKvalitetsark — permanente presets', () => {
  test('preset-knapperne filtrerer, og Alle personer gendanner alt uden at mutere rows', () => {
    const rows = [
      row({ personId: '1', navn: 'Åben Person', qaKoder: ['dato_ufortolkelig'], qaAlvor: 'advarsel' }),
      row({ personId: '2', navn: 'Rettet Person', reviewStatus: { navn: 'rettet' } }),
      row({ personId: '3', navn: 'Godkendt Person', reviewStatus: { navn: 'godkendt' } }),
      row({ personId: '4', navn: 'Udskudt Person', reviewStatus: { navn: 'udskudt' } }),
      row({ personId: '5', navn: 'Stale Person', reviewStatus: { navn: 'stale' } }),
    ];
    const originalSnapshot = JSON.stringify(rows);
    render(<PersonKvalitetsark rows={rows} {...baseProps} onSelect={vi.fn()} onOpenPerson={vi.fn()} />);
    expect(screen.getByText(/Viser 5 af 5 personer/)).toBeTruthy();

    fireEvent.click(screen.getByRole('button', { name: 'Åbne OCR-fejl' }));
    expect(screen.getByText('Åben Person')).toBeTruthy();
    expect(screen.queryByText('Rettet Person')).toBeNull();

    fireEvent.click(screen.getByRole('button', { name: 'Rettede' }));
    expect(screen.getByText('Rettet Person')).toBeTruthy();
    expect(screen.queryByText('Åben Person')).toBeNull();

    fireEvent.click(screen.getByRole('button', { name: 'Godkendte' }));
    expect(screen.getByText('Godkendt Person')).toBeTruthy();

    fireEvent.click(screen.getByRole('button', { name: 'Udskudte' }));
    expect(screen.getByText('Udskudt Person')).toBeTruthy();

    fireEvent.click(screen.getByRole('button', { name: 'Stale' }));
    expect(screen.getByText('Stale Person')).toBeTruthy();

    fireEvent.click(screen.getByRole('button', { name: 'Alle personer' }));
    expect(screen.getByText(/Viser 5 af 5 personer/)).toBeTruthy();
    expect(screen.getByText('Åben Person')).toBeTruthy();
    expect(screen.getByText('Rettet Person')).toBeTruthy();
    expect(screen.getByText('Godkendt Person')).toBeTruthy();
    expect(screen.getByText('Udskudt Person')).toBeTruthy();
    expect(screen.getByText('Stale Person')).toBeTruthy();
    expect(JSON.stringify(rows)).toBe(originalSnapshot);
  });
});

describe('PersonKvalitetsark — søgning, filtre, sortering, kolonner', () => {
  test('søgning matcher record_key, ikke kun navn', () => {
    const rows = [
      row({ personId: '1', navn: 'Anna', recordKey: 'p-999-unik' }),
      row({ personId: '2', navn: 'Bertha', recordKey: 'p-000' }),
    ];
    render(<PersonKvalitetsark rows={rows} {...baseProps} onSelect={vi.fn()} onOpenPerson={vi.fn()} />);
    fireEvent.change(screen.getByLabelText('Søg'), { target: { value: '999-unik' } });
    expect(screen.getByText('Anna')).toBeTruthy();
    expect(screen.queryByText('Bertha')).toBeNull();
  });

  test('kilde- og linjefilter kombineres med AND', () => {
    const rows = [
      row({ personId: '1', navn: 'Match', sourceTitel: 'DAA 2018-20', linje: 'III' }),
      row({ personId: '2', navn: 'AndenKilde', sourceTitel: 'DAA 1939', linje: 'III' }),
      row({ personId: '3', navn: 'AndenLinje', sourceTitel: 'DAA 2018-20', linje: 'V' }),
    ];
    render(<PersonKvalitetsark rows={rows} {...baseProps} onSelect={vi.fn()} onOpenPerson={vi.fn()} />);
    fireEvent.change(screen.getByLabelText('Filtrér på kilde'), { target: { value: 'DAA 2018-20' } });
    fireEvent.change(screen.getByLabelText('Filtrér på linje'), { target: { value: 'III' } });
    expect(screen.getByText('Match')).toBeTruthy();
    expect(screen.queryByText('AndenKilde')).toBeNull();
    expect(screen.queryByText('AndenLinje')).toBeNull();
  });

  test('felt-filter vælger blandt de fire OCR-felter, og "Alle felter" nulstiller', () => {
    const rows = [
      row({ personId: '1', navn: 'HarNavnStatus', reviewStatus: { navn: 'rettet' } }),
      row({ personId: '2', navn: 'HarFoedselStatus', reviewStatus: { foedsel: 'rettet' } }),
    ];
    render(<PersonKvalitetsark rows={rows} {...baseProps} onSelect={vi.fn()} onOpenPerson={vi.fn()} />);
    fireEvent.change(screen.getByLabelText('Filtrér på felt'), { target: { value: 'foedsel' } });
    expect(screen.getByText('HarFoedselStatus')).toBeTruthy();
    expect(screen.queryByText('HarNavnStatus')).toBeNull();

    fireEvent.change(screen.getByLabelText('Filtrér på felt'), { target: { value: '' } });
    expect(screen.getByText('HarFoedselStatus')).toBeTruthy();
    expect(screen.getByText('HarNavnStatus')).toBeTruthy();
  });

  test('reviewstatus-filter kombineret med felt-filter ser kun på det valgte felt (AND)', () => {
    const rows = [
      row({ personId: '1', navn: 'NavnRettetFoedselAaben', reviewStatus: { navn: 'rettet', foedsel: 'aaben' } }),
      row({ personId: '2', navn: 'NavnAabenFoedselRettet', reviewStatus: { navn: 'aaben', foedsel: 'rettet' } }),
    ];
    render(<PersonKvalitetsark rows={rows} {...baseProps} onSelect={vi.fn()} onOpenPerson={vi.fn()} />);
    fireEvent.change(screen.getByLabelText('Filtrér på felt'), { target: { value: 'foedsel' } });
    fireEvent.change(screen.getByLabelText('Filtrér på reviewstatus'), { target: { value: 'rettet' } });
    expect(screen.getByText('NavnAabenFoedselRettet')).toBeTruthy();
    expect(screen.queryByText('NavnRettetFoedselAaben')).toBeNull();

    fireEvent.change(screen.getByLabelText('Filtrér på reviewstatus'), { target: { value: '' } });
    expect(screen.getByText('NavnRettetFoedselAaben')).toBeTruthy();
    expect(screen.getByText('NavnAabenFoedselRettet')).toBeTruthy();
  });

  test('reviewstatus-preset og reviewstatus-filter kombineres med AND, ikke gensidig udelukkelse', () => {
    // "Rettede" (preset) betyder: mindst ét felt har status 'rettet' — uanset hvilket.
    // Reviewstatus-filteret (uden valgt felt) betyder: mindst ét felt har den valgte
    // status — også uanset hvilket, og ikke nødvendigvis samme felt som preset'et fandt.
    // De to kan derfor sagtens begge være sande for samme række uden at modsige
    // hinanden — det er en ægte AND-indsnævring, ikke en modstridende akse.
    const rows = [
      row({ personId: '1', navn: 'RettetOgGodkendt', reviewStatus: { navn: 'rettet', foedsel: 'godkendt' } }),
      row({ personId: '2', navn: 'KunRettet', reviewStatus: { navn: 'rettet' } }),
    ];
    render(<PersonKvalitetsark rows={rows} {...baseProps} onSelect={vi.fn()} onOpenPerson={vi.fn()} />);
    fireEvent.click(screen.getByRole('button', { name: 'Rettede' }));
    fireEvent.change(screen.getByLabelText('Filtrér på reviewstatus'), { target: { value: 'godkendt' } });
    expect(screen.getByText('RettetOgGodkendt')).toBeTruthy();
    expect(screen.queryByText('KunRettet')).toBeNull();
  });

  test('staged-filter har tre tilstande: alle / kun staged / kun ikke-staged', () => {
    const rows = [
      row({ personId: '1', navn: 'ErStaged', staged: true }),
      row({ personId: '2', navn: 'ErIkkeStaged', staged: false }),
    ];
    render(<PersonKvalitetsark rows={rows} {...baseProps} onSelect={vi.fn()} onOpenPerson={vi.fn()} />);
    fireEvent.change(screen.getByLabelText('Filtrér på staged'), { target: { value: 'true' } });
    expect(screen.getByText('ErStaged')).toBeTruthy();
    expect(screen.queryByText('ErIkkeStaged')).toBeNull();

    fireEvent.change(screen.getByLabelText('Filtrér på staged'), { target: { value: 'false' } });
    expect(screen.getByText('ErIkkeStaged')).toBeTruthy();
    expect(screen.queryByText('ErStaged')).toBeNull();

    fireEvent.change(screen.getByLabelText('Filtrér på staged'), { target: { value: '' } });
    expect(screen.getByText('ErStaged')).toBeTruthy();
    expect(screen.getByText('ErIkkeStaged')).toBeTruthy();
  });

  test('samme_som-filter har tre tilstande: alle / kun med samme_som / kun uden', () => {
    const rows = [
      row({ personId: '1', navn: 'HarSammeSom', sammeSomStatus: 'sikker' }),
      row({ personId: '2', navn: 'HarIkkeSammeSom', sammeSomStatus: null }),
    ];
    render(<PersonKvalitetsark rows={rows} {...baseProps} onSelect={vi.fn()} onOpenPerson={vi.fn()} />);
    fireEvent.change(screen.getByLabelText('Filtrér på samme_som'), { target: { value: 'true' } });
    expect(screen.getByText('HarSammeSom')).toBeTruthy();
    expect(screen.queryByText('HarIkkeSammeSom')).toBeNull();

    fireEvent.change(screen.getByLabelText('Filtrér på samme_som'), { target: { value: 'false' } });
    expect(screen.getByText('HarIkkeSammeSom')).toBeTruthy();
    expect(screen.queryByText('HarSammeSom')).toBeNull();

    fireEvent.change(screen.getByLabelText('Filtrér på samme_som'), { target: { value: '' } });
    expect(screen.getByText('HarSammeSom')).toBeTruthy();
    expect(screen.getByText('HarIkkeSammeSom')).toBeTruthy();
  });

  test('felt/reviewstatus/staged/samme_som-filtre kombineres alle sammen med AND', () => {
    const rows = [
      row({
        personId: '1', navn: 'MatcherAlt', staged: true, sammeSomStatus: 'sikker',
        reviewStatus: { foedsel: 'rettet' },
      }),
      row({
        personId: '2', navn: 'IkkeStaged', staged: false, sammeSomStatus: 'sikker',
        reviewStatus: { foedsel: 'rettet' },
      }),
      row({
        personId: '3', navn: 'AndetFelt', staged: true, sammeSomStatus: 'sikker',
        reviewStatus: { navn: 'rettet' },
      }),
    ];
    render(<PersonKvalitetsark rows={rows} {...baseProps} onSelect={vi.fn()} onOpenPerson={vi.fn()} />);
    fireEvent.change(screen.getByLabelText('Filtrér på felt'), { target: { value: 'foedsel' } });
    fireEvent.change(screen.getByLabelText('Filtrér på reviewstatus'), { target: { value: 'rettet' } });
    fireEvent.change(screen.getByLabelText('Filtrér på staged'), { target: { value: 'true' } });
    fireEvent.change(screen.getByLabelText('Filtrér på samme_som'), { target: { value: 'true' } });
    expect(screen.getByText('MatcherAlt')).toBeTruthy();
    expect(screen.queryByText('IkkeStaged')).toBeNull();
    expect(screen.queryByText('AndetFelt')).toBeNull();
  });

  test('Navn-header sorterer stigende som standard og skifter retning ved klik', () => {
    const rows = [row({ personId: '1', navn: 'Bertha' }), row({ personId: '2', navn: 'Anna' })];
    const { container } = render(
      <PersonKvalitetsark rows={rows} {...baseProps} onSelect={vi.fn()} onOpenPerson={vi.fn()} />,
    );
    const header = screen.getByRole('button', { name: 'Navn' });
    let bodyRows = container.querySelectorAll('tbody tr');
    expect(bodyRows[0].getAttribute('data-testid')).toBe('kv-row-2');
    expect(header.closest('th')?.getAttribute('aria-sort')).toBe('ascending');

    fireEvent.click(header);
    bodyRows = container.querySelectorAll('tbody tr');
    expect(bodyRows[0].getAttribute('data-testid')).toBe('kv-row-1');
    expect(header.closest('th')?.getAttribute('aria-sort')).toBe('descending');

    fireEvent.click(header);
    bodyRows = container.querySelectorAll('tbody tr');
    expect(bodyRows[0].getAttribute('data-testid')).toBe('kv-row-2');
    expect(header.closest('th')?.getAttribute('aria-sort')).toBe('ascending');
  });

  test('sortering på Født lægger ulæselige/manglende datoer sidst, uanset retning', () => {
    const rows = [
      row({ personId: '1', navn: 'Har dato', foedselRaw: '12. juli 1748', foedselMin: '1748-07-12' }),
      row({ personId: '2', navn: 'Ulæselig', foedselRaw: 'ulæselig', foedselMin: null }),
    ];
    const { container } = render(
      <PersonKvalitetsark rows={rows} {...baseProps} onSelect={vi.fn()} onOpenPerson={vi.fn()} />,
    );
    const header = screen.getByRole('button', { name: 'Født' });
    fireEvent.click(header);
    let bodyRows = container.querySelectorAll('tbody tr');
    expect(bodyRows[bodyRows.length - 1].getAttribute('data-testid')).toBe('kv-row-2');

    fireEvent.click(header);
    bodyRows = container.querySelectorAll('tbody tr');
    expect(bodyRows[bodyRows.length - 1].getAttribute('data-testid')).toBe('kv-row-2');
  });

  test('kolonner kan skjules/vises og nulstilles til standard', () => {
    const rows = [row({ personId: '1' })];
    render(<PersonKvalitetsark rows={rows} {...baseProps} onSelect={vi.fn()} onOpenPerson={vi.fn()} />);
    expect(screen.getByRole('columnheader', { name: 'Kilde/udgave' })).toBeTruthy();

    fireEvent.click(screen.getByRole('button', { name: 'Kolonner' }));
    fireEvent.click(screen.getByLabelText('Kilde/udgave'));
    expect(screen.queryByRole('columnheader', { name: 'Kilde/udgave' })).toBeNull();

    fireEvent.click(screen.getByRole('button', { name: 'Nulstil kolonner' }));
    expect(screen.getByRole('columnheader', { name: 'Kilde/udgave' })).toBeTruthy();
  });
});

describe('PersonKvalitetsark — tilgængelighed', () => {
  test('bruger en semantisk tabel — ingen grid-bibliotek', () => {
    const rows = [row({ personId: '1' })];
    const { container } = render(
      <PersonKvalitetsark rows={rows} {...baseProps} onSelect={vi.fn()} onOpenPerson={vi.fn()} />,
    );
    expect(container.querySelector('table')).toBeTruthy();
    expect(container.querySelector('thead')).toBeTruthy();
    expect(container.querySelector('tbody')).toBeTruthy();
  });

  test('sorterbare kolonneoverskrifter er knapper med aria-sort; ikke-sorterbare har ingen aria-sort og ingen knap', () => {
    const rows = [row({ personId: '1' })];
    render(<PersonKvalitetsark rows={rows} {...baseProps} onSelect={vi.fn()} onOpenPerson={vi.fn()} />);
    const foedtHeader = screen.getByRole('columnheader', { name: 'Født' });
    expect(foedtHeader.getAttribute('aria-sort')).toBe('none');
    expect(foedtHeader.querySelector('button')).toBeTruthy();

    const kildeHeader = screen.getByRole('columnheader', { name: 'Kilde/udgave' });
    expect(kildeHeader.getAttribute('aria-sort')).toBeNull();
    expect(kildeHeader.querySelector('button')).toBeNull();
  });

  test('valgt celle markeres via aria-pressed', () => {
    const rows = [row({ personId: '1' })];
    render(
      <PersonKvalitetsark
        rows={rows}
        loading={false}
        error={null}
        selected={{ personId: '1', felt: 'navn' }}
        onSelect={vi.fn()}
        onOpenPerson={vi.fn()}
      />,
    );
    const cell = screen.getByRole('button', { name: 'Christian Ditlev Reventlow' });
    expect(cell.getAttribute('aria-pressed')).toBe('true');
  });

  test('blokeret celle forbliver fokuserbar via tastatur selvom den ikke kan redigeres', () => {
    const rows = [
      row({
        personId: '1',
        kanRettes: { navn: true, foedsel: false, doed: true, koen: true },
        blokarsager: { foedsel: 'flere_importerede_facts' },
      }),
    ];
    render(<PersonKvalitetsark rows={rows} {...baseProps} onSelect={vi.fn()} onOpenPerson={vi.fn()} />);
    const blocked = screen.getByRole('button', { name: '12. juli 1748' });
    expect(blocked.tabIndex).toBe(0);
    blocked.focus();
    expect(document.activeElement).toBe(blocked);
    expect(blocked.getAttribute('aria-disabled')).toBe('true');
  });

  test('QA-symbol har en tekstlig label, ikke kun et ikon', () => {
    const rows = [row({ personId: '1', qaAlvor: 'fejl', qaKoder: ['foedt_efter_doed'] })];
    render(<PersonKvalitetsark rows={rows} {...baseProps} onSelect={vi.fn()} onOpenPerson={vi.fn()} />);
    expect(screen.getByText('Fejl')).toBeTruthy();
  });
});

describe('PersonKvalitetsark — celle-valg og navigation', () => {
  test('redigerbar celle kalder onSelect; blokeret celle kalder ikke onSelect men tilbyder onOpenPerson; tælle-kolonner åbner personeditoren', () => {
    const onSelect = vi.fn();
    const onOpenPerson = vi.fn();
    const rows = [
      row({
        personId: '1',
        kanRettes: { navn: true, foedsel: false, doed: true, koen: true },
        blokarsager: { foedsel: 'flere_importerede_facts' },
        antalTitler: 2,
      }),
    ];
    render(<PersonKvalitetsark rows={rows} {...baseProps} onSelect={onSelect} onOpenPerson={onOpenPerson} />);

    fireEvent.click(screen.getByRole('button', { name: 'Christian Ditlev Reventlow' }));
    expect(onSelect).toHaveBeenCalledWith({ personId: '1', felt: 'navn' });
    expect(onSelect).toHaveBeenCalledTimes(1);

    const blocked = screen.getByRole('button', { name: '12. juli 1748' });
    fireEvent.click(blocked);
    expect(onSelect).toHaveBeenCalledTimes(1);
    expect(screen.getByText(/flere kildebelagte påstande/i)).toBeTruthy();

    fireEvent.click(screen.getByRole('link', { name: 'Åbn person' }));
    expect(onOpenPerson).toHaveBeenCalledWith('1');

    fireEvent.click(screen.getByRole('link', { name: '2 titler' }));
    expect(onOpenPerson).toHaveBeenCalledWith('1');
  });
});

describe('PersonKvalitetsark — bred tabel', () => {
  test('scroller vandret i sin egen region og tvinger ikke resten af appen bredere', () => {
    const rows = [row({ personId: '1' })];
    const { container } = render(
      <PersonKvalitetsark rows={rows} {...baseProps} onSelect={vi.fn()} onOpenPerson={vi.fn()} />,
    );
    const scrollWrapper = screen.getByTestId('kvalitetsark-scroll');
    expect(scrollWrapper.style.overflowX).toBe('auto');
    expect(scrollWrapper.style.minWidth).toBe('0px');

    const table = container.querySelector('table');
    expect(table).toBeTruthy();
    expect(Number.parseInt(table!.style.minWidth, 10)).toBeGreaterThan(800);

    const root = container.firstElementChild as HTMLElement;
    expect(root.style.minWidth).toBe('');
  });
});

describe('PersonKvalitetsark — indlæsning og fejl', () => {
  test('viser indlæsningstilstand uden tabel', () => {
    const { container } = render(
      <PersonKvalitetsark rows={[]} loading={true} error={null} selected={null} onSelect={vi.fn()} onOpenPerson={vi.fn()} />,
    );
    expect(screen.getByText(/Indlæser/)).toBeTruthy();
    expect(container.querySelector('table')).toBeNull();
  });

  test('viser fejlbesked uden tabel', () => {
    const { container } = render(
      <PersonKvalitetsark rows={[]} loading={false} error="Noget gik galt" selected={null} onSelect={vi.fn()} onOpenPerson={vi.fn()} />,
    );
    expect(screen.getByText('Noget gik galt')).toBeTruthy();
    expect(container.querySelector('table')).toBeNull();
  });
});
