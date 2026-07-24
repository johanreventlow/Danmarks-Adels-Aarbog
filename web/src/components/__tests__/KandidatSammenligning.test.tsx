// @vitest-environment jsdom
import { fireEvent, render, screen, within } from '@testing-library/react';
import { describe, expect, test, vi } from 'vitest';
import type { RedMatchPerson } from '@daa/core';
import type { KandidatDetalje, PersonEvidence } from '../../data/redaktionRead';
import { KandidatSammenligning } from '../KandidatSammenligning';

function person(id: string, overrides: Partial<RedMatchPerson> = {}): RedMatchPerson {
  return {
    id,
    navn: 'detlev reventlow',
    fuldtNavn: 'Detlev Reventlow',
    koen: 'mand',
    foedsel: { date_min: '1660-01-01', date_max: '1660-12-31' },
    doed: { date_min: '1730-01-01', date_max: '1730-12-31' },
    titel: 'Amtmand',
    bogReferencer: [{ sourceId: 3, linje: 'III', nr: 58, slaegtledLokal: null, slaegtledGennem: null, kuld: null, grenNavn: 'Holstenske linje' }],
    sourceIds: [3],
    staged: true,
    ...overrides,
  };
}

function evidence(foedt: string, sourceTitel: string): PersonEvidence {
  return {
    koen: 'mand',
    felter: {
      foedt: [{
        felt: 'foedt', faktatype: 'fødsel', factId: 1, konklusionAssertionId: 11, uenig: false,
        oplysninger: [{
          assertionId: 11, vaerdi: foedt, erKonklusion: true,
          dato: { min: `${foedt}-01-01`, max: `${foedt}-12-31`, qualifier: null, raw: foedt },
          kilder: [{ sourceId: 3, sourceTitel, side: '12', citatTekst: `født ${foedt}` }],
        }],
      }],
      doed: [{
        felt: 'doed', faktatype: 'død', factId: 2, konklusionAssertionId: 12, uenig: false,
        oplysninger: [{ assertionId: 12, vaerdi: '1730', erKonklusion: true, kilder: [] }],
      }],
    },
  };
}

function detalje(foedt: string, sourceTitel: string, narrativ: string): KandidatDetalje {
  return {
    evidence: evidence(foedt, sourceTitel),
    narrativer: [{ id: 1, sourceId: 3, sourceTitel, udgave: null, side: '12', tekst: narrativ, privat: false }],
    familie: {
      somBarn: [{ familyId: '10', rolle: 'barn', konfidens: null, foraeldre: [{ personId: '20', navn: '#20' }, { personId: '21', navn: '#21' }] }],
      somPartner: [{
        familyId: '11', type: 'vielse',
        partnere: [{ personId: '30', navn: '#30', aar: '1665–1720', konfidens: null, ordinal: null }],
        boern: [{ personId: '40', navn: '#40', aar: '1690–1750', rolle: 'barn', konfidens: null, ordinal: 1 }],
      }],
    },
    relationer: [{ relationId: 7, art: 'gods', objektType: 'estate', objektId: '9', navn: 'Frisenvold', rolle: 'ejer', periode: '1700–1710' }],
  };
}

const langNarrativ = `${'A'.repeat(410)}SLUTNING`;
const navnById = new Map([
  ['20', 'Christian Ditlev Reventlow'],
  ['21', 'Anna Sophie Schack'],
  ['30', 'Charlotte Amalie'],
  ['40', 'Conrad Reventlow'],
]);

describe('KandidatSammenligning', () => {
  test('viser feltjusteret to-kolonne-kontekst og fremhæver enighed/afvigelse', () => {
    render(<KandidatSammenligning
      personA={person('1')}
      personB={person('2', { sourceIds: [7], bogReferencer: [{ sourceId: 7, linje: 'V', nr: 1, slaegtledLokal: null, slaegtledGennem: null, kuld: null, grenNavn: 'Danske linje' }] })}
      detaljeA={detalje('1660', 'DAA 1939', langNarrativ)}
      detaljeB={detalje('1661', 'DAA 2018', 'Kort narrativ')}
      kildeA="DAA 1939"
      kildeB="DAA 2018"
      navnById={navnById}
      foldHint={{ folder: false, grund: 'konkurrerende forældre (1 vs. 2)' }}
      foldAdvice="Match forældrene først."
      onBekraeft={vi.fn()}
      onAfvis={vi.fn()}
    />);

    expect(screen.getByRole('columnheader', { name: 'Kilde A · DAA 1939' })).toBeTruthy();
    expect(screen.getByRole('columnheader', { name: 'Kilde B · DAA 2018' })).toBeTruthy();
    expect(screen.getByTestId('felt-navn').getAttribute('data-status')).toBe('enig');
    expect(screen.getByTestId('felt-foedsel-doed').getAttribute('data-status')).toBe('afvigende');
    expect(screen.getByText(/Kilde: DAA 1939 · s\. 12/)).toBeTruthy();
    expect(screen.getAllByText(/Christian Ditlev Reventlow/).length).toBeGreaterThan(0);
    expect(screen.getAllByText(/Charlotte Amalie/).length).toBeGreaterThan(0);
    expect(screen.getAllByText(/Conrad Reventlow/).length).toBeGreaterThan(0);
    expect(screen.getByText(/III-58, Holstenske linje/)).toBeTruthy();
    expect(screen.getAllByText(/Frisenvold · ejer · 1700–1710/).length).toBe(2);
  });

  test('viser alias/kanonisk-rolle i kolonneoverskrifterne når angivet (tydelighed om hvilken udgave bliver main)', () => {
    render(<KandidatSammenligning
      personA={person('1')}
      personB={person('2')}
      detaljeA={detalje('1660', 'DAA 1939', 'x')}
      detaljeB={detalje('1660', 'DAA 2018', 'x')}
      kildeA="DAA 1939"
      kildeB="DAA 2018"
      rolleA="alias"
      rolleB="kanonisk"
      navnById={navnById}
      foldHint={{ folder: true, grund: null }}
      onBekraeft={vi.fn()}
      onAfvis={vi.fn()}
    />);

    expect(screen.getByRole('columnheader', { name: /Kilde A · DAA 1939.*foldes ind \(alias\)/ })).toBeTruthy();
    expect(screen.getByRole('columnheader', { name: /Kilde B · DAA 2018.*forbliver synlig \(main\)/ })).toBeTruthy();
  });

  test('viser ingen rolle-badge når rolleA/rolleB udelades (fx ikke_samme_som-afvisning uden alias/kanonisk-forhold)', () => {
    render(<KandidatSammenligning
      personA={person('1')}
      personB={person('2')}
      detaljeA={detalje('1660', 'DAA 1939', 'x')}
      detaljeB={detalje('1660', 'DAA 2018', 'x')}
      kildeA="DAA 1939"
      kildeB="DAA 2018"
      navnById={navnById}
      foldHint={{ folder: false, grund: 'Parret er markeret som forskellige.' }}
      onBekraeft={vi.fn()}
      onAfvis={vi.fn()}
    />);

    expect(screen.getByRole('columnheader', { name: 'Kilde A · DAA 1939' })).toBeTruthy();
    expect(screen.getByRole('columnheader', { name: 'Kilde B · DAA 2018' })).toBeTruthy();
    expect(screen.queryByText(/foldes ind \(alias\)/)).toBeNull();
    expect(screen.queryByText(/forbliver synlig \(main\)/)).toBeNull();
  });

  test('viser fold-advarslen før handlingerne og holder narrativet sammenfoldet indtil toggle', () => {
    const onBekraeft = vi.fn();
    const onAfvis = vi.fn();
    render(<KandidatSammenligning
      personA={person('1')}
      personB={person('2')}
      detaljeA={detalje('1660', 'DAA 1939', langNarrativ)}
      detaljeB={detalje('1660', 'DAA 2018', 'Kort narrativ')}
      kildeA="DAA 1939"
      kildeB="DAA 2018"
      navnById={navnById}
      foldHint={{ folder: false, grund: 'konkurrerende forældre' }}
      foldAdvice="Match forældrene først."
      onBekraeft={onBekraeft}
      onAfvis={onAfvis}
    />);

    const advarsel = screen.getByRole('alert');
    const bekraeft = screen.getByRole('button', { name: 'Bekræft samme person' });
    expect(advarsel.compareDocumentPosition(bekraeft) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(screen.queryByText(/SLUTNING/)).toBeNull();

    const narrativA = screen.getByTestId('narrativ-a');
    fireEvent.click(within(narrativA).getByRole('button', { name: 'Vis hele' }));
    expect(within(narrativA).getByText(/SLUTNING/)).toBeTruthy();

    fireEvent.click(bekraeft);
    fireEvent.click(screen.getByRole('button', { name: 'Afvis' }));
    expect(onBekraeft).toHaveBeenCalledTimes(1);
    expect(onAfvis).toHaveBeenCalledTimes(1);
  });

  test('viser normaliserede datogrænser når kilden ikke har date_raw eller tekstværdi', () => {
    const detaljeA = detalje('1660', 'DAA 1939', 'Kort narrativ');
    const foedt = detaljeA.evidence.felter.foedt[0].oplysninger[0];
    foedt.vaerdi = '';
    foedt.dato = {
      min: '1660-01-01',
      max: '1660-12-31',
      qualifier: 'about',
      raw: null,
    };

    render(<KandidatSammenligning
      personA={person('1')}
      personB={person('2')}
      detaljeA={detaljeA}
      detaljeB={detalje('1661', 'DAA 2018', 'Kort narrativ')}
      kildeA="DAA 1939"
      kildeB="DAA 2018"
      navnById={navnById}
      foldHint={{ folder: true, grund: null }}
      onBekraeft={vi.fn()}
      onAfvis={vi.fn()}
    />);

    expect(screen.getByText('1660-01-01–1660-12-31')).toBeTruthy();
  });

  test('viser handling-specifik gemmefeedback under bekræftelse', () => {
    render(<KandidatSammenligning
      personA={person('1')}
      personB={person('2')}
      detaljeA={detalje('1660', 'DAA 1939', 'x')}
      detaljeB={detalje('1660', 'DAA 2018', 'x')}
      kildeA="DAA 1939"
      kildeB="DAA 2018"
      navnById={navnById}
      foldHint={{ folder: true, grund: null }}
      busyAction="bekraeft"
      onBekraeft={vi.fn()}
      onAfvis={vi.fn()}
    />);

    expect(screen.getByRole('button', { name: 'Gemmer…' }).hasAttribute('disabled')).toBe(true);
    expect(screen.getByRole('button', { name: 'Afvis' }).hasAttribute('disabled')).toBe(true);
  });

  test('skjuler handlingsknapper i read-only-visning', () => {
    render(<KandidatSammenligning
      personA={person('1')}
      personB={person('2')}
      detaljeA={detalje('1660', 'DAA 1939', 'x')}
      detaljeB={detalje('1660', 'DAA 2018', 'x')}
      kildeA="DAA 1939"
      kildeB="DAA 2018"
      navnById={navnById}
      foldHint={{ folder: true, grund: null }}
      readOnly
      onBekraeft={vi.fn()}
      onAfvis={vi.fn()}
    />);

    expect(screen.queryByRole('button', { name: 'Bekræft samme person' })).toBeNull();
    expect(screen.queryByRole('button', { name: 'Afvis' })).toBeNull();
  });
});
