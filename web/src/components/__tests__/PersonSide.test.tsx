// @vitest-environment jsdom
// Personsiden /person/<id> (webredesign fase 3): samme data som panelets udgavetest (Conrad Reventlow), vist som
// egen side. Mangler siges med ord; henter, tom og fejl er tre tilstande; usikkert slægtskab vises med ordet.
import { fireEvent, render, screen, within } from '@testing-library/react';
import { buildModel, type AppPerson, type BioSourceVersionV2, type PublicPersonFactRow, type Udgave, type UdgaveFaktaInput } from '@daa/core';
import { describe, expect, it, vi } from 'vitest';
import type { PersonDetailData } from '../../data/public';
import type { Model } from '../../data/types';
import type { MediaItem } from '../../data/media';

vi.mock('../../router', () => ({ navigate: vi.fn() }));
const smal = vi.hoisted(() => ({ v: false }));
vi.mock('../../useSmalSkaerm', () => ({ useSmalSkaerm: () => smal.v }));
// Vielsesdatoerne hentes fra basen; testen styrer svaret pr. family-id.
const vielser = vi.hoisted(() => ({ svar: {} as Record<string, string>, kald: [] as string[][] }));
vi.mock('../../data/vielser', () => ({
  hentVielsesDatoer: async (ids: string[]) => { vielser.kald.push(ids); return vielser.svar; },
}));
vi.mock('../lazyMaps', () => ({
  ExpandableMiniMap: ({ points }: { points: unknown[] }) => <div data-testid="livsrejse">{points.length} steder</div>,
  MapFallback: () => null,
}));
const { PersonSide } = await import('../PersonSide');
const { BOERN_UDEN_AEGTESKAB } = await import('../../data/fokusTrae');

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

const props = (o: Partial<Parameters<typeof PersonSide>[0]> = {}) => ({
  model, focusId: '392', detail: detalje(), detailError: null, onRetry: vi.fn(), onVisPerson: vi.fn(),
  onFindSlaegtskab: vi.fn(), onSlaegt: vi.fn(), loggetInd: false, onLogin: vi.fn(), erBogmaerket: false, onToggleBogmaerke: vi.fn(),
  ...o,
});

describe('PersonSide', () => {
  it('»I Aarbogen«: bogens formelle navneform for en efterkommer; ikke for stifteren eller uden regler', () => {
    const kV = 'slaegt:1:lineage:5:scheme:canonical';
    const m = {
      ...model,
      byId: {
        ...model.byId,
        '392': { ...model.byId['392'], title: 'Greve', fornavne: 'Conrad' },
        '501': { ...model.byId['501'], title: 'Greve', fornavne: 'Christian' },
      },
      lineage: { byPerson: { '392': [kV], '501': [kV] }, list: [{ linje: kV, count: 2, headId: '392', navn: 'V' }], navn: {} },
      adelsnavne: { '5': 'af Reventlow' },
    } as unknown as Model;
    const r1 = render(<PersonSide {...props({ model: m, focusId: '501' })} />);
    expect(screen.getByText('I Aarbogen')).toBeTruthy();
    expect(screen.getByText('Christian greve af Reventlow')).toBeTruthy();
    r1.unmount();
    // Conrad er linjens stifter: hans navn (»de Reventlow«) kommer fra hans eget patent — ingen regelform.
    const r2 = render(<PersonSide {...props({ model: m })} />);
    expect(screen.queryByText('I Aarbogen')).toBeNull();
    r2.unmount();
    // Uden regler (data ikke hentet/ikke i prod endnu): siden er som før.
    render(<PersonSide {...props({ model: { ...m, adelsnavne: undefined } as unknown as Model, focusId: '501' })} />);
    expect(screen.queryByText('I Aarbogen')).toBeNull();
    expect(screen.queryByText(/greve af Reventlow/)).toBeNull();
  });

  it('floruit vises som Nævnes; uden år ingen årslinje', () => {
    const m = { ...model, byId: { ...model.byId, '392': { ...model.byId['392'], years: 'Nævnes 1349–1391' } } } as unknown as Model;
    const aarP = (c: HTMLElement) => Array.from(c.querySelectorAll('p')).filter((p) => p.style.fontFamily.includes('monospace') && p.style.fontSize === '14px');
    const { unmount, container } = render(<PersonSide {...props({ model: m })} />);
    expect(screen.getByText('Nævnes 1349–1391')).toBeTruthy();
    expect(aarP(container)).toHaveLength(1);
    unmount();
    const tom = { ...model, byId: { ...model.byId, '392': { ...model.byId['392'], years: '' } } } as unknown as Model;
    const r2 = render(<PersonSide {...props({ model: tom })} />);
    expect(screen.queryByText(/Livsdatoer ikke angivet/)).toBeNull();
    expect(aarP(r2.container)).toHaveLength(0);
  });

  it('navn, slægt, udgavevælger og biografi fra standardudgaven', () => {
    render(<PersonSide {...props()} />);
    expect(screen.getByRole('heading', { level: 1, name: 'Conrad Reventlow' })).toBeTruthy();
    expect(screen.getAllByText(/Reventlow · V\. Linje/).length).toBeGreaterThan(0);
    const vaelger = screen.getByRole('group', { name: 'Udgave' });
    expect(within(vaelger).getAllByRole('button').map((b) => b.textContent)).toEqual(['DAA 2018-20', 'DAA 1939']); // én pr. udgave
    expect(screen.getByText(/Conrad var storkansler og gehejmeråd/)).toBeTruthy();
  });

  it('vælgeren skifter biografi og godser til den valgte udgave', () => {
    render(<PersonSide {...props()} />);
    expect(screen.getByRole('link', { name: 'Clausholm' }).getAttribute('href')).toBe('/besiddelse/e1');
    expect(screen.queryByRole('link', { name: 'Frijsenborg' })).toBeNull();
    fireEvent.click(within(screen.getByRole('group', { name: 'Udgave' })).getByRole('button', { name: /1939/ }));
    expect(screen.getByText(/Greve, f\. 21 April 1644/)).toBeTruthy();
    expect(screen.getByRole('link', { name: 'Frijsenborg' })).toBeTruthy();
    expect(screen.queryByRole('link', { name: 'Clausholm' })).toBeNull();
  });

  it('»Kilde i Aarbogen« viser to ens linjer (samme værk + ref) for en foldet person én gang (M-6)', () => {
    const v39 = 'Dansk Adels Aarbog – DAA 1939';
    const m = { ...model, sourcesBy: { '392': [
      { work: 'Dansk Adels Aarbog – DAA 2018-20', ref: 'V. Den grevelige linje af 1673, nr. 1', personId: '392', sourceId: '1', aar: 2018 },
      { work: v39, ref: '', personId: '1198', sourceId: '3', aar: 1939 },
      { work: v39, ref: '', personId: '1199', sourceId: '3', aar: 1939 },
    ] } } as unknown as Model;
    render(<PersonSide {...props({ model: m })} />);
    const footer = screen.getByText('Kilde i Aarbogen').closest('footer')!;
    expect(within(footer).getAllByText('§')).toHaveLength(2);
    expect(within(footer).getAllByText(v39)).toHaveLength(1);
  });

  it('familie med links til personsider; mangler siges med ord', () => {
    render(<PersonSide {...props()} />);
    expect(screen.getByRole('link', { name: 'Anna Margrethe Gabel' }).getAttribute('href')).toBe('/person/600');
    expect(screen.getByRole('link', { name: 'Ulrica Reventlow' }).getAttribute('href')).toBe('/person/500');
    expect(screen.getByText('Ikke angivet i Aarbogen.')).toBeTruthy(); // forældre
    expect(screen.queryByText('Embeder og hverv')).toBeNull(); // ingen embeder → ingen sektion (19/11)
    expect(screen.queryByText(/Ingen embeder/)).toBeNull();
    expect(screen.queryByText('Billeder og dokumenter')).toBeNull(); // tom → ingen sektion (19/11)
    expect(screen.getByText('Intet portræt i Aarbogen.')).toBeTruthy();
  });

  it('tomme besiddelser og billeder: ingen sektion; med indhold vises den', () => {
    render(<PersonSide {...props({ detail: detalje({ estates: [] }) })} />);
    expect(screen.queryByText('Besiddelser')).toBeNull();
    expect(screen.queryByText(/Ingen besiddelser/)).toBeNull();
    expect(screen.queryByText('Billeder og dokumenter')).toBeNull();
  });

  it('gift med og børn: vises for gifte (børn også uden børn), ikke for ugifte uden børn', () => {
    const m2 = {
      ...model,
      ...buildModel({
        persons: [person('392', 'Conrad Reventlow', 1644), person('600', 'Anna Margrethe Gabel'), person('500', 'Ulrica Reventlow', 1686),
          person('501', 'Christian Reventlow'), person('502', 'Frederik Ahlefeldt')],
        unions: [{ id: 'f1', p1: '392', p2: '600', p2_name: null, year: null }, { id: 'f2', p1: '502', p2: '500', p2_name: null, year: null }],
        parentChild: [{ child: '500', parent: '392', union: 'f1' }, { child: '501', parent: '392', union: 'f1' },
          { child: '500', parent: '600', union: 'f1' }, { child: '501', parent: '600', union: 'f1' }],
      }),
    } as unknown as Model;
    const { unmount } = render(<PersonSide {...props({ model: m2, focusId: '501' })} />); // ugift, ingen børn (død ung)
    expect(screen.queryByText('Børn')).toBeNull();
    expect(screen.queryByText('Ingen børn angivet i Aarbogen.')).toBeNull();
    expect(screen.queryByText('Gift med')).toBeNull();
    expect(screen.queryByText(/Intet ægteskab/)).toBeNull();
    unmount();
    render(<PersonSide {...props({ model: m2, focusId: '500' })} />); // gift, ingen børn
    expect(screen.getByText('Gift med')).toBeTruthy();
    expect(screen.getByText('Børn')).toBeTruthy();
    expect(screen.getByText('Ingen børn angivet i Aarbogen.')).toBeTruthy();
  });

  // Børn pr. ægteskab i bogens rækkefølge (projektejeren 2026-11-21): Conrads 2018-20-numre V/2-7 (Gabel), V/8-17 (Hahn).
  const nrV = (n: number) => ({ sourceId: '1', linje: 'V', nr: n, nrLabel: null });
  const toAegteskaber = (medUdenAegteskab = false) => ({
    ...model,
    udgaver: [D18],
    bogNrBy: { '392': [nrV(1)], '503': [nrV(2)], '515': [nrV(3)], '570': [nrV(8)], '581': [nrV(9)] },
    ...buildModel({
      persons: [person('392', 'Conrad Reventlow', 1644), person('815', 'Anna Margrethe Gabel'), person('816', 'Sophie Amalie Hahn'),
        person('503', 'Friedrich'), person('515', 'Christian Detlef', 1671), person('570', 'Anna Margaretha', 1682),
        person('581', 'Charlotta Amalia', 1683), person('599', 'Ukendt Barn', 1700)],
      unions: [{ id: 'f265', p1: '392', p2: '815', p2_name: null, year: null }, { id: 'f266', p1: '392', p2: '816', p2_name: null, year: null }],
      parentChild: [
        { child: '515', parent: '392', union: 'f265' }, { child: '503', parent: '392', union: 'f265' },
        { child: '581', parent: '392', union: 'f266' }, { child: '570', parent: '392', union: 'f266' },
        ...(medUdenAegteskab ? [{ child: '599', parent: '392', union: null as unknown as string }] : []),
      ],
    }),
  }) as unknown as Model;
  const boerneDd = () => screen.getByText('Børn').nextElementSibling as HTMLElement;
  const linkNavne = (el: HTMLElement) => within(el).getAllByRole('link').map((l) => l.textContent ?? '');

  const medAeldreBarn = (): Model => ({
    ...model,
    bogNrBy: {
      '392': [{ ...nrV(1), stamtavle: true }],
      '500': [{ ...nrV(2), sourceId: '3', linje: 'IV' }],
      '501': [nrV(3), { ...nrV(3), sourceId: '3', linje: 'IV' }],
    },
    indexes: { ...model.indexes, konfByEdge: { '500|392': 'formodet' } },
  });

  it('børnelisten mærker kun barnet fra den ældre udgave efter konfidensordet', () => {
    render(<PersonSide {...props({ model: medAeldreBarn() })} />);
    // 2018-20 er valgt: barnet fra 1939 står som grå tekst (intet link), med mærket.
    expect(within(boerneDd()).queryByRole('link', { name: 'Ulrica Reventlow' })).toBeNull();
    const barn = within(boerneDd()).getByText('Ulrica Reventlow').closest('li')!;
    const maerke = within(barn).getByText('Kun i DAA 1939');
    expect(maerke.getAttribute('title')).toBe('Står i DAA 1939, men ikke i DAA 2018-20.');
    expect(within(barn).getByText('formodet').nextElementSibling).toBe(maerke);
    const soeskende = screen.getByRole('link', { name: 'Christian Reventlow' }).closest('li')!;
    expect(within(soeskende).queryByText(/Kun i/)).toBeNull();
    expect(within(boerneDd()).getAllByText('Kun i DAA 1939')).toHaveLength(1);
  });

  it('barnets egen side viser forklaringslinjen i headeren', () => {
    const { container } = render(<PersonSide {...props({ model: medAeldreBarn(), focusId: '500' })} />);
    const header = container.querySelector('header')!;
    expect(within(header).getByText('Nævnes kun i DAA 1939 og er ikke med i DAA 2018-20.')).toBeTruthy();
  });

  it('en person i begge udgaver har ingen forklaringslinje', () => {
    render(<PersonSide {...props({ model: medAeldreBarn(), focusId: '501' })} />);
    expect(screen.queryByText(/Nævnes kun i/)).toBeNull();
  });

  it('to ægteskaber: børn under »Med <hustru>« i bogens rækkefølge', () => {
    render(<PersonSide {...props({ model: toAegteskaber(), focusId: '392' })} />);
    const dd = boerneDd();
    const gabel = within(dd).getByText('Med Anna Margrethe Gabel').parentElement as HTMLElement;
    const hahn = within(dd).getByText('Med Sophie Amalie Hahn').parentElement as HTMLElement;
    expect(linkNavne(gabel).map((n) => n.split(' ')[0])).toEqual(['Friedrich', 'Christian']);
    expect(linkNavne(hahn).map((n) => n.split(' ')[0])).toEqual(['Anna', 'Charlotta']);
  });

  it('overskrifternes navne matcher »Gift med«', () => {
    render(<PersonSide {...props({ model: toAegteskaber(), focusId: '392' })} />);
    const gift = screen.getByText('Gift med').nextElementSibling as HTMLElement;
    const overskrifter = within(boerneDd()).getAllByText(/^Med /).map((e) => (e.textContent ?? '').replace(/^Med /, ''));
    expect(overskrifter).toHaveLength(2);
    for (const navn of overskrifter) expect(gift.textContent).toContain(navn);
  });

  it('barn uden ægteskab: »Ægteskab ikke angivet« + note, intet barn forsvinder', () => {
    render(<PersonSide {...props({ model: toAegteskaber(true), focusId: '392' })} />);
    const dd = boerneDd();
    expect(within(dd).getByText('Ægteskab ikke angivet')).toBeTruthy();
    expect(within(dd).getByText(BOERN_UDEN_AEGTESKAB)).toBeTruthy();
    expect(linkNavne(dd)).toHaveLength(5);
  });

  it('ét ægteskab: ingen »Med …«-overskrift', () => {
    const m = toAegteskaber();
    const et = { ...m, ...buildModel({ persons: [...m.persons], unions: [{ id: 'f265', p1: '392', p2: '815', p2_name: null, year: null }],
      parentChild: [{ child: '515', parent: '392', union: 'f265' }, { child: '503', parent: '392', union: 'f265' }] }) } as unknown as Model;
    render(<PersonSide {...props({ model: et, focusId: '392' })} />);
    expect(within(boerneDd()).queryByText(/^Med /)).toBeNull();
    expect(linkNavne(boerneDd()).map((n) => n.split(' ')[0])).toEqual(['Friedrich', 'Christian']);
  });

  describe('⚭ vielsesdato ved ægtefællen', () => {
    const giftDd = () => screen.getByText('Gift med').nextElementSibling as HTMLElement;
    const raekke = (navn: string) => within(giftDd()).getByRole('link', { name: navn }).closest('div') as HTMLElement;

    it('vielsesdatoen står efter hver hustrus livsdatoer', async () => {
      vielser.kald = [];
      vielser.svar = { '265': '⚭ 21. juli 1667', '266': '⚭ 1. maj 1681' };
      render(<PersonSide {...props({ model: toAegteskaber(), focusId: '392' })} />);
      expect(await within(giftDd()).findByText('⚭ 21. juli 1667')).toBeTruthy();
      expect(within(raekke('Anna Margrethe Gabel')).getByText('⚭ 21. juli 1667')).toBeTruthy();
      expect(within(raekke('Sophie Amalie Hahn')).getByText('⚭ 1. maj 1681')).toBeTruthy();
      expect(vielser.kald.at(-1)?.slice().sort()).toEqual(['265', '266']);
    });

    it('⚭ står efter ægtefællens livsdatoer, adskilt med komma; navnene holder linje', async () => {
      vielser.svar = { '265': '⚭ 21. juli 1667' };
      const m = { ...model, ...buildModel({
        persons: [person('392', 'Conrad Reventlow', 1644), { ...person('815', 'Anna Margrethe Gabel'), years: '* 1651 † 1678' }],
        unions: [{ id: 'f265', p1: '392', p2: '815', p2_name: null, year: null }], parentChild: [] }) } as unknown as Model;
      render(<PersonSide {...props({ model: m, focusId: '392' })} />);
      const linje = await within(giftDd()).findByText('* 1651 † 1678, ⚭ 21. juli 1667');
      const navn = within(giftDd()).getByRole('link', { name: 'Anna Margrethe Gabel' });
      expect(navn.compareDocumentPosition(linje) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    });

    it('par i to familier (sammenfoldet på tværs af udgaver): den mest præcise dato vinder', async () => {
      vielser.svar = { '265': '⚭ 1667', '300': '⚭ 21. juli 1667' };
      const m = { ...model, ...buildModel({ persons: [person('392', 'Conrad Reventlow', 1644), person('815', 'Anna Margrethe Gabel')],
        unions: [{ id: 'f265', p1: '392', p2: '815', p2_name: null, year: null }, { id: 'f300', p1: '392', p2: '815', p2_name: null, year: null }],
        parentChild: [] }) } as unknown as Model;
      render(<PersonSide {...props({ model: m, focusId: '392' })} />);
      expect(await within(giftDd()).findByText('⚭ 21. juli 1667')).toBeTruthy();
      expect(within(giftDd()).queryByText('⚭ 1667')).toBeNull();
    });

    it('ægteskab uden vielsesfakta: ingen ⚭', async () => {
      vielser.svar = {};
      render(<PersonSide {...props({ model: toAegteskaber(), focusId: '392' })} />);
      await Promise.resolve();
      expect(within(giftDd()).queryByText(/⚭/)).toBeNull();
    });

    it('ægtefælle kun med navn (intet person-id): ingen ⚭ og intet crash', async () => {
      vielser.svar = { '7': '⚭ 1670' };
      const m = { ...model, ...buildModel({ persons: [person('392', 'Conrad Reventlow', 1644)],
        unions: [{ id: 'f7', p1: '392', p2: null, p2_name: 'Ukendt hustru', year: null }], parentChild: [] }) } as unknown as Model;
      render(<PersonSide {...props({ model: m, focusId: '392' })} />);
      expect(within(giftDd()).getByText('Ukendt hustru')).toBeTruthy();
      await Promise.resolve();
      expect(within(giftDd()).queryByText(/⚭/)).toBeNull();
    });
  });

  it('en sammenfoldet person har ingen »Optræder i Aarbogen som«-linje i toppen (kilderne står nederst)', () => {
    const m = {
      ...model,
      byId: { ...model.byId, '392': { ...model.byId['392'], mergedFrom: ['392', '255', '1198'] } },
      sourcesBy: { '392': [
        { work: 'DAA 2018-20', ref: 'V. Linje, nr. 1', kort: 'V, nr. 1', personId: '392', sourceId: '1', aar: 2018, slaegtled: 1 },
        { work: 'DAA 1939', ref: 's. 52', kort: 's. 52', personId: '1198', sourceId: '3', aar: 1939, slaegtled: null },
      ] },
    } as unknown as Model;
    render(<PersonSide {...props({ model: m })} />);
    expect(screen.queryByText(/Optræder i Aarbogen/)).toBeNull();
  });

  it('usikkert slægtskab vises med ordet', () => {
    const m = { ...model, indexes: { ...model.indexes, konfByEdge: { '500|392': 'formodet' } } } as unknown as Model;
    render(<PersonSide {...props({ model: m })} />);
    const ulrica = screen.getByRole('link', { name: 'Ulrica Reventlow' }).parentElement!;
    expect(within(ulrica).getByText('formodet')).toBeTruthy();
  });

  it('de første 7 embeder, så »Vis alle«', () => {
    const offices = Array.from({ length: 9 }, (_, i) => ({ label: `Embede ${i + 1}`, period: `${1660 + i}` }));
    render(<PersonSide {...props({ detail: detalje({ offices }) })} />);
    expect(screen.getByText('Embede 7')).toBeTruthy();
    expect(screen.queryByText('Embede 8')).toBeNull();
    fireEvent.click(screen.getByRole('button', { name: 'Vis alle 9 embeder og hverv' }));
    expect(screen.getByText('Embede 9')).toBeTruthy();
  });

  it('embeder: sektionen vises, når der er mindst ét', () => {
    render(<PersonSide {...props({ detail: detalje({ offices: [{ label: 'Amtmand', period: '1700' }] }) })} />);
    expect(screen.getByText('Embeder og hverv')).toBeTruthy();
    expect(screen.getByText('Amtmand')).toBeTruthy();
  });

  it('henter: ingen »Ikke angivet« før detaljen er kommet', () => {
    render(<PersonSide {...props({ detail: null })} />);
    expect(screen.getAllByText('Henter …').length).toBeGreaterThan(0);
    expect(screen.queryByText(/Ingen embeder/)).toBeNull();
    expect(screen.queryByText('Embeder og hverv')).toBeNull(); // ingen tom boks under hentning
    expect(screen.getByText('Ikke angivet i Aarbogen.')).toBeTruthy(); // familien kommer fra modellen
  });

  it('fejl: forklaring og »Prøv igen«, ikke tomme sektioner', () => {
    const onRetry = vi.fn();
    render(<PersonSide {...props({ detail: null, detailError: 'PUBLIC_BIO_SOURCE_V2_UNAVAILABLE', onRetry })} />);
    expect(screen.getByRole('alert').textContent).not.toContain('PUBLIC_BIO');
    fireEvent.click(screen.getByRole('button', { name: 'Prøv igen' }));
    expect(onRetry).toHaveBeenCalled();
    expect(screen.queryByText(/Ingen embeder/)).toBeNull();
  });

  it('handlinger: Vis i stamtræet og Find slægtskab er links; login-noten lover kun bogmærker', () => {
    const onFind = vi.fn();
    render(<PersonSide {...props({ onFindSlaegtskab: onFind })} />);
    expect(screen.getByRole('link', { name: 'Vis i stamtræet' }).getAttribute('href')).toBe('/slaegt/reventlow/stamtrae?fokus=392');
    const find = screen.getByRole('link', { name: 'Find slægtskab' });
    expect(find.getAttribute('href')).toBe('/slaegtskab?a=392');
    fireEvent.click(find);
    expect(onFind).toHaveBeenCalled();
    expect(screen.getByText(/for at gemme Conrad Reventlow under dine bogmærker/)).toBeTruthy();
    expect(screen.queryByText(/i familie/)).toBeNull();
  });

  it('indlogget: bogmærket står i højre spalte', () => {
    const onToggle = vi.fn();
    render(<PersonSide {...props({ loggetInd: true, onToggleBogmaerke: onToggle })} />);
    fireEvent.click(screen.getByRole('button', { name: 'Gem i bogmærker' }));
    expect(onToggle).toHaveBeenCalled();
  });

  it('Kopiér link lægger personens adresse i udklipsholderen', async () => {
    const writeText = vi.fn().mockResolvedValue(undefined);
    Object.assign(navigator, { clipboard: { writeText } });
    render(<PersonSide {...props()} />);
    fireEvent.click(screen.getByRole('button', { name: 'Kopiér link' }));
    expect(await screen.findByText('Linket er kopieret.')).toBeTruthy();
    expect(writeText).toHaveBeenCalledWith(`${window.location.origin}/person/392`);
  });

  describe('smal skærm (fase 9): handlinger ved navnet', () => {
    const foer = (a: Node, b: Node) => !!(a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING);
    const PORTRAET = { id: 'm1', slags: 'portræt', titel: 'Portræt', kunstner: 'Ukendt', datering: '1690', url: 'https://eksempel.dk/p.jpg' } as unknown as MediaItem;

    it('med portræt: én miniature før navnet', () => {
      smal.v = true;
      try {
        render(<PersonSide {...props({ detail: detalje({ media: [PORTRAET] }) })} />);
        const knapper = screen.getAllByRole('button', { name: /Vis portrættet af Conrad Reventlow større/ });
        expect(knapper).toHaveLength(1);
        expect(foer(knapper[0], screen.getByRole('heading', { level: 1 }))).toBe(true);
      } finally { smal.v = false; }
    });

    it('portrættets billedtekst og kilde står ved miniaturen (kilder vises, også når kun institutionen kendes)', () => {
      smal.v = true;
      try {
        const kunInstitution = { ...PORTRAET, titel: '', kunstner: '', datering: '', kildeInstitution: 'Frederiksborgmuseet' } as unknown as MediaItem;
        render(<PersonSide {...props({ detail: detalje({ media: [kunInstitution] }) })} />);
        expect(screen.getByText(/Frederiksborgmuseet/)).toBeTruthy();
      } finally { smal.v = false; }
    });

    it('den flyttede »Vis i præsensliste« er mindst 44 px høj', () => {
      smal.v = true;
      try {
        render(<PersonSide {...props({ onVisPraesens: vi.fn() })} />);
        expect(parseFloat(screen.getByRole('button', { name: 'Vis i præsensliste' }).style.minHeight)).toBeGreaterThanOrEqual(44);
      } finally { smal.v = false; }
    });

    it('uden portræt: ingen tom portrætboks', () => {
      smal.v = true;
      try {
        render(<PersonSide {...props()} />);
        expect(screen.queryByRole('img', { name: 'Intet portræt' })).toBeNull();
      } finally { smal.v = false; }
    });

    it('Vis i stamtræet står før Familie; Find slægtskab og Del findes én gang hver', () => {
      smal.v = true;
      try {
        render(<PersonSide {...props({ onToggleMig: vi.fn() })} />);
        const stamtrae = screen.getByRole('link', { name: 'Vis i stamtræet' });
        expect(foer(stamtrae, screen.getByRole('heading', { name: 'Familie' }))).toBe(true);
        expect(screen.getAllByRole('link', { name: 'Find slægtskab' })).toHaveLength(1);
        expect(screen.getAllByRole('button', { name: 'Del' })).toHaveLength(1);
        expect(screen.getAllByRole('button', { name: 'Det er mig' })).toHaveLength(1);
      } finally { smal.v = false; }
    });

    it('bred skærm uændret: handlingerne i højre spalte efter Familie, portrætboksen findes', () => {
      render(<PersonSide {...props()} />);
      const stamtrae = screen.getByRole('link', { name: 'Vis i stamtræet' });
      expect(foer(screen.getByRole('heading', { name: 'Familie' }), stamtrae)).toBe(true);
      expect(screen.getByRole('img', { name: 'Intet portræt' })).toBeTruthy();
    });
  });

  it('bred skærm kopierer, også når browseren kan dele (desktop-Safari)', async () => {
    const share = vi.fn().mockResolvedValue(undefined); const writeText = vi.fn().mockResolvedValue(undefined);
    Object.defineProperty(navigator, 'share', { value: share, configurable: true, writable: true });
    Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true, writable: true });
    try {
      render(<PersonSide {...props()} />);
      fireEvent.click(screen.getByRole('button', { name: 'Kopiér link' }));
      expect(await screen.findByText('Linket er kopieret.')).toBeTruthy();
      expect(share).not.toHaveBeenCalled();
    } finally { Object.defineProperty(navigator, 'share', { value: undefined, configurable: true, writable: true }); }
  });

  it('smal skærm: »Del« åbner telefonens delemenu med personens adresse; ingen status efter deling eller afbrydelse', async () => {
    smal.v = true;
    const share = vi.fn().mockResolvedValueOnce(undefined).mockRejectedValueOnce(new DOMException('x', 'AbortError'));
    Object.defineProperty(navigator, 'share', { value: share, configurable: true, writable: true });
    try {
      render(<PersonSide {...props()} />);
      expect(screen.queryByRole('button', { name: 'Kopiér link' })).toBeNull();
      const del = screen.getByRole('button', { name: 'Del' });
      fireEvent.click(del);
      await vi.waitFor(() => expect(share).toHaveBeenCalledTimes(1));
      expect(share.mock.calls[0][0].url).toBe(`${window.location.origin}/person/392`);
      fireEvent.click(del);
      await vi.waitFor(() => expect(share).toHaveBeenCalledTimes(2));
      expect(screen.getByRole('status').textContent).toBe('');
    } finally {
      smal.v = false;
      Object.defineProperty(navigator, 'share', { value: undefined, configurable: true, writable: true });
    }
  });

  it('»Det er mig« er en trykknap; kun med handlingen', () => {
    const onToggleMig = vi.fn();
    const { unmount } = render(<PersonSide {...props()} />);
    expect(screen.queryByRole('button', { name: /Det er (mig|dig)/ })).toBeNull();
    unmount();
    const r = render(<PersonSide {...props({ onToggleMig })} />);
    const knap = screen.getByRole('button', { name: 'Det er mig' });
    expect(knap.getAttribute('aria-pressed')).toBe('false');
    fireEvent.click(knap);
    expect(onToggleMig).toHaveBeenCalled();
    r.rerender(<PersonSide {...props({ onToggleMig, erMig: true })} />);
    expect(screen.getByRole('button', { name: 'Det er dig' }).getAttribute('aria-pressed')).toBe('true');
  });

  it('»Vis i præsensliste« kun når handlingen gives (redaktionen)', () => {
    const onVisPraesens = vi.fn();
    const { unmount } = render(<PersonSide {...props()} />);
    expect(screen.queryByRole('button', { name: 'Vis i præsensliste' })).toBeNull();
    unmount();
    render(<PersonSide {...props({ onVisPraesens })} />);
    fireEvent.click(screen.getByRole('button', { name: 'Vis i præsensliste' }));
    expect(onVisPraesens).toHaveBeenCalled();
  });

  it('livsrejsen vises kun med steder og først, når geo er hentet', async () => {
    const punkt = { placeId: 'p1', navn: 'Clausholm', lat: 56.4, lon: 10.1, kind: 'fødsel', personId: '392', estateId: null, unionId: null, year: 1644 };
    const medGeo = { ...model, geo: { points: [punkt], byPerson: { '392': [punkt] }, byEstate: {} } } as unknown as Model;
    const { unmount } = render(<PersonSide {...props({ model: medGeo, geoLoading: true })} />);
    expect(screen.queryByText('Livsrejse')).toBeNull();
    unmount();
    const u2 = render(<PersonSide {...props()} />);
    expect(screen.queryByText('Livsrejse')).toBeNull(); // ingen geo → ingen tom boks
    u2.unmount();
    render(<PersonSide {...props({ model: medGeo })} />);
    expect(screen.getByText('Livsrejse')).toBeTruthy();
    expect((await screen.findByTestId('livsrejse')).textContent).toBe('1 steder');
  });

  it('slægtskab over navnet: intet uden »Det er mig«, »Det er dig« på egen side, skifter uden genindlæsning', () => {
    const { rerender } = render(<PersonSide {...props()} />);
    expect(screen.queryByTestId('slaegtskab-kontekst')).toBeNull();
    rerender(<PersonSide {...props({ meId: '392', erMig: true })} />);
    expect(screen.getByTestId('slaegtskab-kontekst').textContent).toBe('Det er dig');
    rerender(<PersonSide {...props({ meId: null, erMig: false })} />);
    expect(screen.queryByTestId('slaegtskab-kontekst')).toBeNull();
    rerender(<PersonSide {...props({ meId: '500' })} />);
    expect(screen.getByTestId('slaegtskab-kontekst').textContent).toMatch(/^Din forælder/);
  });
});
