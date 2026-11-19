// @vitest-environment jsdom
// 6e-1 (spec 2026-11-12-trin6e-laeserflade-design.md §5.2-5.5, §5.8): personsiden (PersonSide) viser den valgte udgaves
// fakta forrest og den anden udgave som note; én vælger styrer både biografi og fakta.
import { fireEvent, render, screen, within } from '@testing-library/react';
import { buildModel, type AppPerson, type BioSourceVersionV2, type PublicPersonFactRow, type Udgave, type UdgaveFaktaInput } from '@daa/core';
import { describe, expect, it, vi } from 'vitest';
import type { PersonDetailData } from '../../data/public';
import type { Model } from '../../data/types';

vi.mock('../../data/familySources', () => ({ fetchFamilySources: async () => [] }));
vi.mock('../../router', () => ({ navigate: vi.fn() }));
const { PersonSide } = await import('../PersonSide');

const D18: Udgave = { sourceId: '1', label: 'DAA 2018-20', aar: 2018 };
const D39: Udgave = { sourceId: '3', label: 'DAA 1939', aar: 1939 };
const RECORD_1939 = 'record-07565168-b903-4444-9189-43d62d5c6ed6';

// ---- Conrad Reventlow (255 III-58, 392 V-1, 1198 1939), som core-fixturen i editionFacts.test.ts ----
let next = 1;
const row = (o: Partial<PublicPersonFactRow>): PublicPersonFactRow => {
  const id = next++;
  return {
    person_id: 392, fact_id: id, faktatype: 'død', conclusion_status: 'afklaret', assertion_id: id, chosen: true,
    vaerdi_tekst: null, date_raw: null, date_min: null, date_max: null, date_qualifier: null, date_certainty: null,
    source_id: 1, source_label: 'DAA 2018-20', side: null, record_ref: null, record_label: null, citation_label: null, ...o,
  };
};
const bundet39 = { source_id: 3, source_label: 'DAA 1939', record_ref: 'rec-1939', record_label: RECORD_1939, citation_label: 'DAA 1939, s. 541' };
const ROWS_18: PublicPersonFactRow[] = [
  row({ fact_id: 3920, faktatype: 'navn', assertion_id: 39200, chosen: true, vaerdi_tekst: 'Conrad', source_id: null, source_label: null }),
  row({ fact_id: 3920, faktatype: 'navn', assertion_id: 39201, chosen: false, vaerdi_tekst: 'Conrad de Reventlow', side: '201' }),
  row({ person_id: 255, faktatype: 'titel', vaerdi_tekst: 'greve', record_ref: 'rec-iii58', record_label: 'III-58', citation_label: 'DAA 2018-20, s. 137' }),
  row({ faktatype: 'titel', vaerdi_tekst: 'Greve', record_ref: 'rec-v1', record_label: 'V-1', citation_label: 'DAA 2018-20, s. 201-202' }),
  row({ faktatype: 'fødsel', date_raw: '21. april 1644', date_min: '1644-04-21' }),
];
const ROWS_39: PublicPersonFactRow[] = [
  row({ person_id: 1198, faktatype: 'navn', vaerdi_tekst: 'Conrad Reventlow', ...bundet39 }),
  row({ person_id: 1198, faktatype: 'titel', vaerdi_tekst: 'Greve', ...bundet39 }),
  row({ person_id: 1198, faktatype: 'fødsel', date_raw: '21 April 1644', ...bundet39 }),
  row({ person_id: 1198, faktatype: 'begravelse', vaerdi_tekst: 'Herlufsholm', ...bundet39 }),
];
const faktaInput = (rows: PublicPersonFactRow[]): UdgaveFaktaInput => ({
  rows, udgaver: [D39, D18], udgaveForPersonRaekke: { '255': '1', '392': '1', '1198': '3' },
  fritekstKilde: { '39200': ['Dansk Adels Aarbog – DAA 1939'] }, slukketEnighed: new Set(),
});

const bio = (sourceId: number, recordLabel: string, tekst: string, recordRef: string): BioSourceVersionV2 => ({
  personId: sourceId === 1 ? 392 : 1198, sourceId, sourceYear: sourceId === 1 ? 2018 : 1939, recordOrder: null,
  sourceRecordRef: recordRef, recordRef, sourceLabel: sourceId === 1 ? 'DAA 2018-20' : 'DAA 1939', recordLabel,
  narrativeText: tekst, citationLabel: '', provenanceKind: 'source_record',
});
const BIO_III58 = bio(1, 'III-58', 'Se V-1.', 'rec-iii58');
const BIO_V1 = bio(1, 'V-1', 'Conrad var storkansler og gehejmeråd og ejede Clausholm.', 'rec-v1');
const BIO_1939 = bio(3, RECORD_1939, 'Conrad Reventlow, Greve, f. 21 April 1644.', 'rec-1939');

const person = (id: string, name: string, born: number | null = null): AppPerson =>
  ({ id, name, born, died: null, years: '', title: '', bio: '', privat: false });
const model = {
  ...buildModel({
    persons: [person('392', 'Conrad Reventlow', 1644), person('600', 'Anna Margrethe Gabel'), person('500', 'Ulrica Reventlow', 1686), person('501', 'Christian Reventlow')],
    unions: [{ id: 'f1', p1: '392', p2: '600', p2_name: null, year: null }],
    parentChild: [{ child: '500', parent: '392', union: 'f1' }, { child: '501', parent: '392', union: 'f1' },
      { child: '500', parent: '600', union: 'f1' }, { child: '501', parent: '600', union: 'f1' }],
  }),
  lineage: { byPerson: { '392': ['legacy-source:3:II', 'ctx:V'] }, list: [], navn: { 'ctx:V': 'V. Linje' } },
  udgaver: [D18, D39],
  udgaveForPersonRaekke: { '255': '1', '392': '1', '1198': '3' },
} as unknown as Model;

const detalje = (o: Partial<PersonDetailData> = {}): PersonDetailData => ({
  bio: BIO_V1.narrativeText, offices: [], media: [], sources: [], facts: [], factsError: false,
  bioVersions: [BIO_III58, BIO_V1, BIO_1939],
  estates: [
    { id: 'e1', navn: 'Clausholm', personId: '392' },
    { id: 'e1', navn: 'Clausholm', personId: '255' },
    { id: 'e2', navn: 'Frijsenborg', personId: '1198' },
    { id: 'e3', navn: 'Uden fakta-række', personId: '777' },
  ],
  faktaInput: faktaInput([...ROWS_18, ...ROWS_39]),
  ...o,
});
const panel = (detail: PersonDetailData | null, focusId = '392') => (
  <PersonSide model={model} focusId={focusId} detail={detail} detailError={null} onRetry={vi.fn()} onVisPerson={vi.fn()}
    onFindSlaegtskab={vi.fn()} onSlaegt={vi.fn()} loggetInd={false} onLogin={vi.fn()} erBogmaerket={false} onToggleBogmaerke={vi.fn()} />
);
const vis = (detail: PersonDetailData) => render(panel(detail));
const chip = (navn: string) => within(screen.getByRole('group', { name: 'Udgave' })).getByRole('button', { name: navn });
const LAEK = /record-[0-9a-f]{8}-|legacy-source:/;

describe('PersonSide — udgaver', () => {
  it("åbner på 2018-20 med V-1's biografi og viser 2018-20's fakta; én chip pr. udgave", () => {
    vis(detalje());
    expect(chip('DAA 2018-20').getAttribute('aria-pressed')).toBe('true');
    expect(within(screen.getByRole('group', { name: 'Udgave' })).getAllByRole('button').map((b) => b.textContent))
      .toEqual(['DAA 2018-20', 'DAA 1939']);
    expect(screen.getByText(BIO_V1.narrativeText)).toBeTruthy();
    expect(screen.queryByText('Du ser en tidligere udgave.')).toBeNull();
    expect(screen.getByText('Conrad de Reventlow')).toBeTruthy();
    expect(screen.getByText('DAA 1939 skriver: Conrad Reventlow')).toBeTruthy();
    expect(screen.queryByText(/✓ også i/)).toBeNull(); // enighed vises ikke (2026-11-19)
    expect(screen.getByText('Kun i DAA 1939')).toBeTruthy();
    expect(screen.getByText('Begravet: Herlufsholm')).toBeTruthy();
    // godser: kun 2018-20's (én gang, selv om to 2018-20-rækker ejer det) + rækker uden kendt udgave
    expect(screen.getAllByRole('link', { name: 'Clausholm' })).toHaveLength(1);
    expect(screen.queryByRole('link', { name: 'Frijsenborg' })).toBeNull();
    expect(screen.getByRole('link', { name: 'Uden fakta-række' })).toBeTruthy();
  });

  it('III-58 (henvisningen »Se V-1.«) kan ikke vælges', () => {
    vis(detalje());
    expect(within(screen.getByRole('group', { name: 'Udgave' })).queryByRole('button', { name: /III-58/ })).toBeNull();
    expect(screen.queryByText('Se V-1.')).toBeNull();
  });

  it('klik på 1939 skifter biografi og fakta', () => {
    vis(detalje());
    fireEvent.click(chip('DAA 1939'));
    expect(chip('DAA 1939').getAttribute('aria-pressed')).toBe('true');
    expect(screen.getByText(BIO_1939.narrativeText)).toBeTruthy();
    expect(screen.queryByText(BIO_V1.narrativeText)).toBeNull();
    expect(screen.getByText('Du ser en tidligere udgave.')).toBeTruthy();
    expect(screen.getAllByText('Conrad Reventlow')).toHaveLength(3); // overskriften, brødkrummen og 1939's navnelinje
    expect(screen.getByText('DAA 2018-20 skriver: Conrad de Reventlow')).toBeTruthy();
    expect(screen.queryByText('Conrad de Reventlow')).toBeNull();
    expect(screen.getByText('Herlufsholm')).toBeTruthy();
    expect(screen.queryByText('Kun i DAA 1939')).toBeNull();
    expect(screen.getByRole('link', { name: 'Frijsenborg' })).toBeTruthy();
    expect(screen.queryByRole('link', { name: 'Clausholm' })).toBeNull();
  });

  it('udgave-chip uden biografi viser Ingen biografi fra denne udgave', () => {
    vis(detalje({ bioVersions: [BIO_V1] }));
    expect(screen.queryByText('Ingen biografi fra denne udgave.')).toBeNull();
    fireEvent.click(chip('DAA 1939'));
    expect(screen.getByText('Ingen biografi fra denne udgave.')).toBeTruthy();
    expect(screen.queryByText(BIO_V1.narrativeText)).toBeNull();
    expect(screen.getByText('DAA 2018-20 skriver: Conrad de Reventlow')).toBeTruthy();
  });

  it('ingen biografi og to udgaver viser udgaveskift uden biografitekst', () => {
    vis(detalje({ bio: '', bioVersions: [] }));
    expect(chip('DAA 2018-20').getAttribute('aria-pressed')).toBe('true');
    expect(screen.queryByText('Ingen biografi fra denne udgave.')).toBeNull();
    expect(screen.queryByText('Du ser en tidligere udgave.')).toBeNull();
    // udgaveskiftet står over fakta
    expect(chip('DAA 2018-20').compareDocumentPosition(screen.getByText('Fakta')) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(screen.getByText('Conrad de Reventlow')).toBeTruthy();
    fireEvent.click(chip('DAA 1939'));
    expect(screen.getByText('DAA 2018-20 skriver: Conrad de Reventlow')).toBeTruthy();
    expect(screen.queryByText('Ingen biografi fra denne udgave.')).toBeNull();
  });

  it('ingen biografi og ingen fakta viser intet vælgerområde', () => {
    vis(detalje({ bio: '', bioVersions: [], faktaInput: faktaInput([]) }));
    expect(screen.queryByRole('button', { name: /DAA/ })).toBeNull();
    expect(screen.queryByText('Ingen biografi fra denne udgave.')).toBeNull();
    expect(screen.queryByText('Fakta')).toBeNull();
  });

  it('én udgave med fakta og uden biografi viser ingen vælger', () => {
    vis(detalje({ bio: '', bioVersions: [], faktaInput: faktaInput(ROWS_39) }));
    expect(screen.queryByRole('button', { name: /DAA/ })).toBeNull();
    expect(screen.queryByText('Ingen biografi fra denne udgave.')).toBeNull();
    expect(screen.getByText('Herlufsholm')).toBeTruthy();
  });

  it('fejl i fakta viser fejlteksten, og vælgeren bygges af biografierne alene', () => {
    vis(detalje({ factsError: true, faktaInput: null }));
    expect(screen.getByText('Fakta kunne ikke hentes')).toBeTruthy();
    fireEvent.click(chip('DAA 1939'));
    expect(screen.getByText(BIO_1939.narrativeText)).toBeTruthy();
    expect(screen.getByRole('link', { name: 'Frijsenborg' })).toBeTruthy(); // uden fakta kendes godsernes udgave ikke → alle vises
    expect(screen.getAllByRole('link', { name: 'Clausholm' })).toHaveLength(1);
  });


  it('»Tidligere udgave« står kun over en ældre udgave end standarden', () => {
    // kun 1939 har biografi → standarden er 1939-posten; 2018-20 (kun fakta) er den nyere udgave
    vis(detalje({ bio: BIO_1939.narrativeText, bioVersions: [BIO_1939] }));
    expect(chip('DAA 1939').getAttribute('aria-pressed')).toBe('true');
    expect(screen.queryByText('Du ser en tidligere udgave.')).toBeNull();
    fireEvent.click(chip('DAA 2018-20'));
    expect(chip('DAA 2018-20').getAttribute('aria-pressed')).toBe('true');
    expect(screen.queryByText('Du ser en tidligere udgave.')).toBeNull();
  });

  it('valgt chip bevares, når detaljen hentes igen for samme person; ny person → standarden', () => {
    const { rerender } = render(panel(detalje()));
    fireEvent.click(chip('DAA 1939'));
    expect(chip('DAA 1939').getAttribute('aria-pressed')).toBe('true');
    // genhentning: detaljen er kortvarigt null, derefter et nyt objekt med samme indhold
    rerender(panel(null));
    rerender(panel(detalje()));
    expect(chip('DAA 1939').getAttribute('aria-pressed')).toBe('true');
    expect(screen.getByText(BIO_1939.narrativeText)).toBeTruthy();
    // færre chips i den nye detalje: kun 2018-20 → ingen vælger, men valget glemmes ikke
    rerender(panel(detalje({ bioVersions: [BIO_III58, BIO_V1], faktaInput: faktaInput(ROWS_18) })));
    expect(screen.queryByRole('group', { name: 'Udgave' })).toBeNull();
    expect(screen.getByText(BIO_V1.narrativeText)).toBeTruthy();
    rerender(panel(detalje()));
    expect(chip('DAA 1939').getAttribute('aria-pressed')).toBe('true');
    // ny person: standarden — og valget er glemt, også når man vender tilbage (nulstil ved nyt focusId)
    rerender(panel(detalje(), '600'));
    expect(chip('DAA 2018-20').getAttribute('aria-pressed')).toBe('true');
    rerender(panel(detalje(), '392'));
    expect(chip('DAA 2018-20').getAttribute('aria-pressed')).toBe('true');
  });

  it('DOM indeholder hverken record- eller legacy-source:', () => {
    const { container } = vis(detalje());
    // fixturen bærer begge dele, så testen ikke består tomt
    expect(JSON.stringify(detalje())).toMatch(/record-07565168-/);
    expect(model.lineage!.byPerson['392'][0]).toMatch(/^legacy-source:/);
    expect(container.innerHTML).not.toMatch(LAEK);
    expect(within(container).getAllByText(/V\. Linje/).length).toBeTruthy();
    fireEvent.click(chip('DAA 1939'));
    expect(container.innerHTML).not.toMatch(LAEK);
    vis(detalje({ bio: '', bioVersions: [] }));
    expect(document.body.innerHTML).not.toMatch(LAEK);
  });

  // Redaktøren ser levende (decisions 2026-11-13): en kladde siges med ord; en udgivet tekst gør ikke.
  it('kladde kun for redaktionen bærer mærkatet; den udgivne tekst gør ikke', () => {
    const kladde: BioSourceVersionV2 = { ...BIO_1939, kunRedaktion: true, narrativeText: 'Kladdetekst for en levende.', citationLabel: 'DAA 1939, s. 541' };
    vis(detalje({ bioVersions: [BIO_V1, kladde] }));
    expect(screen.queryByRole('note')).toBeNull();
    fireEvent.click(within(screen.getByRole('group', { name: 'Udgave' })).getByRole('button', { name: /^DAA 1939/ }));
    expect(screen.getByText('Kladdetekst for en levende.')).toBeTruthy();
    expect(screen.getByRole('note').textContent).toBe('Ikke udgivet — kun synlig for redaktionen. Kilde: DAA 1939, s. 541.');
  });

  it('én kladde alene (ingen udgavevælger): teksten og mærkatet med kilden vises', () => {
    const kladde: BioSourceVersionV2 = { ...BIO_V1, kunRedaktion: true, narrativeText: 'Eneste kladde.', citationLabel: 'DAA 2018-20, s. 301' };
    vis(detalje({ bio: '', bioVersions: [kladde], faktaInput: null }));
    expect(screen.queryByRole('group', { name: 'Udgave' })).toBeNull();
    expect(screen.getByText('Eneste kladde.')).toBeTruthy();
    expect(screen.getByRole('note').textContent).toBe('Ikke udgivet — kun synlig for redaktionen. Kilde: DAA 2018-20, s. 301.');
  });

  it('uden citationLabel nævner mærkatet udgaven', () => {
    const kladde: BioSourceVersionV2 = { ...BIO_V1, kunRedaktion: true, narrativeText: 'Kladde uden side.', citationLabel: '' };
    vis(detalje({ bio: '', bioVersions: [kladde], faktaInput: null }));
    expect(screen.getByRole('note').textContent).toBe('Ikke udgivet — kun synlig for redaktionen. Kilde: DAA 2018-20.');
  });

});
