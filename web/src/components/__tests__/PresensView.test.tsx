// @vitest-environment jsdom
import { useState } from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import { vi } from 'vitest';
import { PresensGrenSektion, PresensLinjeSektion } from '../PresensView';
import type { PresensGren } from '@daa/core';
import type { PresensLinjeGruppe } from '@daa/core';
import type { PresensLinjeInfo } from '../../data/presensLinjer';

const gren: PresensGren = {
  anker: { personId: 'A', linje: 'II', gren: 1, raaVaerdi: 'II linje, 1. gren' },
  ankerBlok: { id: 'A', levende: true, forbindelsesled: false, partnere: [{ id: 'P', levende: true }], boern: [
    { id: 'B', levende: true, forbindelsesled: false, partnere: [], boern: [], usikker: false, krydsReference: false },
  ], usikker: false, krydsReference: false },
  grupper: [
    { overskrift: 'Søstre', niveau: 1, art: 'soeskende', usikker: false, roedder: [
      { id: 'S', levende: true, forbindelsesled: false, partnere: [], boern: [], usikker: true, krydsReference: false },
      { id: 'S2', levende: true, forbindelsesled: false, partnere: [], boern: [], usikker: false, krydsReference: true },
    ] },
  ],
};
const navnAf = (id: string) => ({ A: 'Anker Person', P: 'Partner Person', B: 'Barn Person', S: 'Søster Person', S2: 'Krydset Person' }[id] ?? id);
const aarAf = () => '';

test('gren-sektion viser overskrift, ankerblok, gruppe og usikkerheds-markering', () => {
  render(<PresensGrenSektion gren={gren} navnAf={navnAf} aarAf={aarAf} onPick={() => {}} />);
  expect(screen.getByText('1. gren')).toBeTruthy();
  expect(screen.getByText('Anker Person')).toBeTruthy();
  expect(screen.getByText('Søstre')).toBeTruthy();
  expect(screen.getByText('Søster Person')).toBeTruthy();
  expect(screen.getByTitle(/usikkert slægtskab/i)).toBeTruthy(); // konfidens-markering (invariant 7)
});

test('krydsReference-node viser en henvisningsnote i stedet for at gentage undertræet', () => {
  render(<PresensGrenSektion gren={gren} navnAf={navnAf} aarAf={aarAf} onPick={() => {}} />);
  // Noten sidder i sit eget indlejrede span (samme mønster som ⚠-markøren, review 26/task 8),
  // så getByText matcher den separat fra personnavnets egen direkte tekstknude. Ordlyd+glyf
  // rettet til mockuppets "↗ vist andetsteds i denne gren" (design-fidelitets-gennemgang).
  expect(screen.getByText('↗ vist andetsteds i denne gren')).toBeTruthy();
  expect(screen.getByText('Krydset Person')).toBeTruthy();
});

test('linje-sektion viser linjenummer, titel, navn og dens grene', () => {
  const gruppe: PresensLinjeGruppe = { linje: 'II', grene: [gren] };
  const info: PresensLinjeInfo = { titel: 'Den grevelige linje af 1673', slaegtsnavn: 'Reventlow', vaaben: null };
  render(<PresensLinjeSektion gruppe={gruppe} info={info} navnAf={navnAf} aarAf={aarAf} onPick={() => {}} />);
  expect(screen.getByText('II')).toBeTruthy();
  expect(screen.getByText('Den grevelige linje af 1673')).toBeTruthy();
  expect(screen.getByText('Reventlow')).toBeTruthy();
  expect(screen.getByText('1. gren')).toBeTruthy(); // fra den indlejrede gren-sektion
});

test('linje-sektion — våbenbilledets alt-tekst foretrækker altTekst-fakt over den hardkodede tekst', () => {
  const gruppe: PresensLinjeGruppe = { linje: 'II', grene: [gren] };
  const vaaben = {
    id: 'v1', slags: 'våben', titel: '', kunstner: '', datering: '', url: 'https://x/vaaben.png', thumbUrl: null,
    altTekst: 'Skjoldmærke: delt af sølv og rødt', kreditlinje: null, kildeUrl: null, kildeInstitution: null,
    beskrivelse: null, teknik: null, fysiskeMaal: null, dateringFakt: null,
  };
  const info: PresensLinjeInfo = { titel: 'Den grevelige linje af 1673', slaegtsnavn: 'Reventlow', vaaben };
  render(<PresensLinjeSektion gruppe={gruppe} info={info} navnAf={navnAf} aarAf={aarAf} onPick={() => {}} />);
  expect(screen.getByAltText('Skjoldmærke: delt af sølv og rødt')).toBeTruthy();
});

test('linje-sektion uden info (data endnu ikke tilknyttet) viser stadig grenene', () => {
  const gruppe: PresensLinjeGruppe = { linje: 'IV', grene: [gren] };
  render(<PresensLinjeSektion gruppe={gruppe} info={undefined} navnAf={navnAf} aarAf={aarAf} onPick={() => {}} />);
  expect(screen.getByText('IV')).toBeTruthy();
  expect(screen.getByText('Anker Person')).toBeTruthy();
});

test('marginLeft er et FAST tillæg pr. niveau, ikke dybde*N — undgår voksende generationsafstand', () => {
  // Regressionstest (bruger-fund 2026-07-24): børn renderes som nestede <div>'er, så en absolut
  // værdi som dybde*22 lægger forælderens forskydning oveni barnets egen (22, 66, 132, 220 — voksende
  // gab). Et fast tillæg pr. niveau giver i stedet korrekt lineær 22px/niveau (mockuppets indent*22),
  // fordi DOM-nestingen selv står for akkumuleringen. Kæden A→B→C har dybde 0/1/2; B og C skal derfor
  // have SAMME marginLeft (22px), ikke 22px hhv. 44px.
  const kaede: PresensGren = {
    anker: { personId: 'A', linje: 'II', gren: 1, raaVaerdi: 'II linje, 1. gren' },
    ankerBlok: { id: 'A', levende: true, forbindelsesled: false, partnere: [], boern: [
      { id: 'B', levende: true, forbindelsesled: false, partnere: [], boern: [
        { id: 'C', levende: true, forbindelsesled: false, partnere: [], boern: [], usikker: false, krydsReference: false },
      ], usikker: false, krydsReference: false },
    ], usikker: false, krydsReference: false },
    grupper: [],
  };
  render(<PresensGrenSektion gren={kaede} navnAf={navnAf} aarAf={aarAf} onPick={() => {}} />);
  const bDiv = screen.getByText('Barn Person').closest('div');
  const cDiv = screen.getByText('C').closest('div');
  expect(bDiv?.style.marginLeft).toBe('22px');
  expect(cDiv?.style.marginLeft).toBe('22px');
});

test('navnAfAnker bruges KUN til grenens hovedrække (dybde 0) — alle øvrige rækker bruger navnAf', () => {
  // Regressionstest for prop-threading (reviewfund) — to indbyrdes adskillelige funktioner, så en
  // fejlagtig ombytning eller en tabt default et sted i kæden (PresensLinjeSektion→PresensGrenSektion
  // →renderNode) fanges her, i modsætning til de øvrige tests hvor navnAfAnker slet ikke sættes.
  const navnAfAlm = () => 'ALM-NAVN';
  const navnAfAnker = () => 'ANKER-NAVN';
  render(<PresensGrenSektion gren={gren} navnAf={navnAfAlm} navnAfAnker={navnAfAnker} aarAf={aarAf} onPick={() => {}} />);
  expect(screen.getByText('ANKER-NAVN')).toBeTruthy(); // ankerBlok (id 'A', dybde 0)
  expect(screen.getAllByText('ALM-NAVN').length).toBeGreaterThan(0); // barn ('B'), søstre ('S'/'S2'), partner ('P')
  expect(screen.queryAllByText('ANKER-NAVN')).toHaveLength(1); // ALDRIG mere end hovedrækken
});

// ---- Fold-ud narrativ ved navneklik (spec 2026-07-24-praesens-navn-foldud-design.md) ----
// PresensGrenSektion er bevidst "dum" og kender ikke til fetchPersonDetail — denne harness
// holder ÆGTE aabne/henter/bio-state (samme mønster PresensView selv bruger) og injicerer sin
// egen hentBio-stub, så testen dækker den rigtige toggle/cache-logik uden at mocke supabase.
function FoldUdHarness(props: { gren: PresensGren; hentBio: (id: string) => Promise<string> }) {
  const { gren, hentBio } = props;
  const [aabne, setAabne] = useState<Set<string>>(new Set());
  const [henter, setHenter] = useState<Set<string>>(new Set());
  const [bio, setBio] = useState<Map<string, string>>(new Map());
  const onToggle = (id: string) => {
    setAabne((prev) => { const next = new Set(prev); if (next.has(id)) next.delete(id); else next.add(id); return next; });
    if (bio.has(id) || henter.has(id)) return;
    setHenter((prev) => new Set(prev).add(id));
    hentBio(id).then((tekst) => {
      setBio((prev) => new Map(prev).set(id, tekst));
      setHenter((prev) => { const next = new Set(prev); next.delete(id); return next; });
    });
  };
  return (
    <PresensGrenSektion
      gren={gren} navnAf={navnAf} aarAf={aarAf} onPick={() => {}}
      erAaben={(id) => aabne.has(id)} erHenter={(id) => henter.has(id)} bioAf={(id) => bio.get(id)}
      onToggle={onToggle}
    />
  );
}

test('klik på et navn folder en boks ud med hentet narrativ; klik igen folder den sammen', async () => {
  const hentBio = async (id: string) => (id === 'A' ? 'Anker biografi.' : '');
  render(<FoldUdHarness gren={gren} hentBio={hentBio} />);
  fireEvent.click(screen.getByText('Anker Person'));
  expect(await screen.findByText('Anker biografi.')).toBeTruthy();
  fireEvent.click(screen.getByText('Anker Person'));
  expect(screen.queryByText('Anker biografi.')).toBeNull();
});

test('to forskellige rækker kan være foldet ud samtidig, uafhængigt af hinanden', async () => {
  const hentBio = async (id: string) => `Bio for ${id}.`;
  render(<FoldUdHarness gren={gren} hentBio={hentBio} />);
  fireEvent.click(screen.getByText('Anker Person'));
  fireEvent.click(screen.getByText('Søster Person'));
  expect(await screen.findByText('Bio for A.')).toBeTruthy();
  expect(await screen.findByText('Bio for S.')).toBeTruthy();
});

test('mangler narrativ (tom streng) viser en dæmpet placeholder, ikke en tom boks', async () => {
  const hentBio = async () => '';
  render(<FoldUdHarness gren={gren} hentBio={hentBio} />);
  fireEvent.click(screen.getByText('Anker Person'));
  expect(await screen.findByText('Ingen biografi registreret')).toBeTruthy();
});

test('gentagne fold-ud/-sammen af samme række genhenter ikke bio-teksten', async () => {
  const hentBio = vi.fn(async (id: string) => `Bio for ${id}.`);
  render(<FoldUdHarness gren={gren} hentBio={hentBio} />);
  fireEvent.click(screen.getByText('Anker Person')); // fold ud (1. hentning)
  await screen.findByText('Bio for A.');
  fireEvent.click(screen.getByText('Anker Person')); // fold sammen
  fireEvent.click(screen.getByText('Anker Person')); // fold ud igen — skal IKKE genhente
  await screen.findByText('Bio for A.');
  expect(hentBio).toHaveBeenCalledTimes(1);
});

test('"Se fuld profil"-linket kalder onPick med personens id, ikke onToggle', () => {
  const onPick = vi.fn();
  render(
    <PresensGrenSektion
      gren={gren} navnAf={navnAf} aarAf={aarAf} onPick={onPick}
      erAaben={(id) => id === 'A'} erHenter={() => false} bioAf={() => 'Anker biografi.'}
      onToggle={() => {}}
    />
  );
  fireEvent.click(screen.getByText('→ Se fuld profil'));
  expect(onPick).toHaveBeenCalledWith('A');
});
