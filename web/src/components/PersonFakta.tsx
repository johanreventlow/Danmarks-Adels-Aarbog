// B11 (spec 2026-10-29-5c2-b11-laeserflade-design.md §4.4): personens fakta med kilde. Kildeteksten alene skelner
// visningerne: bundet til bogens post bærer postens koordinat (»DAA 2018-20, s. 201-202 · V-1«), den oprindelige
// import kun bogen og evt. side (»DAA 2018-20«), og uden kilde står »Kilde ikke registreret«. Mærkerne »bundet til
// bogens post«/»fra den oprindelige import« er fjernet (decisions 2026-11-12): de beskrev vores arbejdsgang, ikke bogen.
// 2026-11-19 (projektejeren): kilden står ikke længere under hvert faktum; personsidens »Kilde i Aarbogen« nederst er
// nok. Kun »Andre udsagn« (omstridte fakta) beholder kilden, fordi den dér skelner udsagnene (invariant 7).
import type { KunIUdgave, PersonFactSource, PersonFactStatement, UdgaveFaktaVisning, UdgaveNote } from '@daa/core';
import { T } from '../theme';
import { Label } from './primitives';

const NAVN: Record<string, string> = {
  navn: 'Navn', tilnavn: 'Tilnavn', fødsel: 'Født', dåb: 'Døbt', titel: 'Titel', dekoration: 'Dekoration',
  adling: 'Adlet', floruit: 'Nævnt', klosterindgang: 'Klosterindgang', overhoved: 'Overhoved', død: 'Død',
  dødsårsag: 'Dødsårsag', begravelse: 'Begravet',
};
const typeNavn = (t: string) => NAVN[t] ?? t.charAt(0).toUpperCase() + t.slice(1);

function Kilde({ source }: { source: PersonFactSource }) {
  return <div style={{ fontFamily: T.mono, fontSize: 11, color: T.inkMuted, marginTop: 2 }}>{source.label}</div>;
}

function Udsagn({ st }: { st: PersonFactStatement }) {
  return (
    <div>
      <div style={{ fontSize: 14, color: T.inkSecondary, lineHeight: 1.3 }}>{st.value}</div>
      <Kilde source={st.source} />
    </div>
  );
}

function Note({ note }: { note: UdgaveNote }) {
  const tekst = note.art === 'enig'
    ? `✓ også i ${note.udgave.label}`
    : `${note.udgave.label} skriver: ${note.vaerdier.join('; ')}`;
  return <div style={{ fontFamily: T.sans, fontSize: 12, color: note.art === 'enig' ? T.inkMuted : T.bordeaux, lineHeight: 1.35 }}>{tekst}</div>;
}

// 6e-1 (spec 2026-11-12 §5.2-5.3): den valgte udgaves fakta forrest; den anden udgave som note under linjen og
// det, kun den anden udgave har, samlet til sidst under »Kun i <udgave>«.
export function PersonFakta({ visning, error }: { visning: UdgaveFaktaVisning | null; error: boolean }) {
  if (error) {
    return (
      <>
        <Label>Fakta</Label>
        <div style={{ fontSize: 13, color: T.inkMuted }}>Fakta kunne ikke hentes</div>
      </>
    );
  }
  if (!visning || (!visning.linjer.length && !visning.kunI.length)) return null;
  // »Kun i …« grupperet pr. udgave i core's rækkefølge (nyeste udgave først).
  const kunI: { udgave: KunIUdgave['udgave']; raekker: KunIUdgave[] }[] = [];
  for (const k of visning.kunI) {
    const g = kunI.find((x) => x.udgave.sourceId === k.udgave.sourceId);
    if (g) g.raekker.push(k);
    else kunI.push({ udgave: k.udgave, raekker: [k] });
  }
  return (
    <>
      <Label>Fakta</Label>
      <div style={{ display: 'flex', flexDirection: 'column' }}>
        {visning.linjer.map((l) => (
          <div key={l.noegle} style={{ display: 'flex', gap: 12, padding: '8px 0', borderBottom: '1px solid rgba(34,31,26,.07)' }}>
            <span style={{ flex: 'none', width: 104, fontFamily: T.mono, fontSize: 11, letterSpacing: '.06em', textTransform: 'uppercase', color: T.inkMuted, paddingTop: 2 }}>
              {typeNavn(l.faktatype)}
            </span>
            <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 6 }}>
              {l.omstridt && (
                <span style={{ alignSelf: 'flex-start', fontFamily: T.mono, fontSize: 11, color: T.bordeaux, border: `1px solid ${T.bordeaux}`, borderRadius: 4, padding: '0 5px' }}>omstridt</span>
              )}
              {l.vaerdi !== '' && (
                <div>
                  <div style={{ fontSize: 14, color: T.inkSecondary, lineHeight: 1.3 }}>{l.vaerdi}</div>
                </div>
              )}
              {l.vaerdi !== '' && l.noter.map((n) => <Note key={`${n.art}:${n.udgave.sourceId}`} note={n} />)}
              {l.andre.length > 0 && (
                <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                  <span style={{ fontFamily: T.mono, fontSize: 11, color: T.inkMuted }}>Andre udsagn</span>
                  {l.andre.map((o, i) => <Udsagn key={`${o.assertionId}:${i}`} st={o} />)}
                </div>
              )}
            </div>
          </div>
        ))}
        {kunI.map((g) => (
          <div key={g.udgave.sourceId} style={{ padding: '10px 0 2px', display: 'flex', flexDirection: 'column', gap: 3 }}>
            <span style={{ fontFamily: T.mono, fontSize: 11, letterSpacing: '.06em', textTransform: 'uppercase', color: T.inkMuted }}>{`Kun i ${g.udgave.label}`}</span>
            {g.raekker.map((k) => (
              <div key={k.faktatype} style={{ fontSize: 13, color: T.inkSecondary, lineHeight: 1.35 }}>{`${typeNavn(k.faktatype)}: ${k.vaerdier.join('; ')}`}</div>
            ))}
          </div>
        ))}
      </div>
    </>
  );
}
