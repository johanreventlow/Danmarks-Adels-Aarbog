// ---- Slægtskab ("Er vi i familie?") ----
// Udtrukket fra Folgesvend.tsx (review 27 W-K1) — samme komponent, blot flyttet fil.
import { T } from '../theme';
import { konfTekst } from '../data/format';
import type { Model } from '../data/types';
import type { RelationResult } from '@daa/core';
import { ViewHeader, Avatar } from './primitives';
import { TreeSearch, type TreeSearchBundle } from './TreeSearch';

export function RelateView({ model, rel, relA, relB, slot, setSlot, onPickStep, meId, onSetMeA, search }: {
  model: Model | null; rel: RelationResult | null; relA: string | null; relB: string | null;
  slot: 'A' | 'B'; setSlot: (s: 'A' | 'B') => void; onPickStep: (id: string) => void;
  meId: string | null; onSetMeA: () => void; search: TreeSearchBundle;
}) {
  const a = relA && model ? model.byId[relA] : null;
  const b = relB && model ? model.byId[relB] : null;
  const me = meId && model ? model.byId[meId] : null;
  const p0 = rel?.lines[0];
  const korrob = p0 && p0.uafhaengige >= 2 ? `Bekræftet ad ${p0.uafhaengige} uafhængige linjer`
    : (p0?.usikker && rel?.alternativSolidLinje) ? 'Bekræftet ad en anden, sikker linje' : '';
  return (
    <div style={{ padding: '30px 40px 50px', maxWidth: 640 }}>
      <ViewHeader title="Er vi i familie?" />
      <div style={{ fontSize: 13, color: T.muted, marginTop: 4, marginBottom: 20 }}>Klik et felt for at vælge plads, søg og vælg så en person nedenfor.</div>
      {me && relA !== meId && (
        <div onClick={onSetMeA} style={{ display: 'inline-flex', alignItems: 'center', gap: 6, marginBottom: 14, background: '#f8ecef', border: '1px solid rgba(136,26,51,.25)', borderRadius: 9, padding: '8px 12px', cursor: 'pointer', fontFamily: T.sans, fontSize: 12.5, fontWeight: 600, color: T.bordeaux }}>★ Sæt mig ({me.name}) som første person</div>
      )}
      <div style={{ display: 'flex', alignItems: 'stretch', gap: 12 }}>
        {(['A', 'B'] as const).map((sl) => {
          const person = sl === 'A' ? a : b;
          const active = slot === sl;
          return (
            <div key={sl} onClick={() => setSlot(sl)} style={{ flex: 1, background: active ? '#f8ecef' : T.paper, border: `1.5px solid ${active ? T.bordeaux : 'rgba(34,31,26,.12)'}`, borderRadius: 14, padding: 16, cursor: 'pointer', display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center' }}>
              <Avatar n={person?.name ?? '?'} size={50} />
              <div style={{ fontFamily: T.serif, fontSize: 18, lineHeight: 1.05, fontWeight: 600, marginTop: 10 }}>{person?.name ?? `Vælg person ${sl}`}</div>
              <div style={{ fontSize: 11, color: T.bordeaux, marginTop: 6, fontWeight: 600 }}>{active ? 'vælger nu ▾' : 'skift'}</div>
            </div>
          );
        })}
      </div>

      {/* Søgning-i-træet (§4/§5.6): et valg fylder den aktive A/B-plads (pickPerson relate-gren). */}
      <div style={{ marginTop: 20 }}><TreeSearch {...search} /></div>

      {/* Slægtskabs-panelerne (resultat · også-beslægtet · sti) skjules under en aktiv søgning. */}
      {!search.showResults && (<>
      {rel && (
        <div style={{ marginTop: 20, background: T.ink, borderRadius: 14, padding: 20, textAlign: 'center' }}>
          <div style={{ fontFamily: T.mono, fontSize: 9.5, letterSpacing: '.16em', textTransform: 'uppercase', color: T.goldLight }}>Slægtskab</div>
          <div style={{ fontFamily: T.serif, fontSize: 27, lineHeight: 1.1, fontWeight: 600, color: T.paper, marginTop: 7 }}>{rel.label}</div>
          {rel.found && p0 && p0.aner.length > 0 && <div style={{ fontSize: 12.5, color: T.cream, marginTop: 8 }}>{p0.multiplicitet > 1 ? 'Fælles aner' : 'Fælles ane'}: {p0.aner.join(' · ')}</div>}
          {p0?.usikker && <div style={{ fontSize: 11.5, color: T.goldLight, marginTop: 7 }}>⚠ Forbindelsen går gennem et {konfTekst(p0.weakestKonfidens)} led</div>}
          {korrob && <div style={{ fontSize: 11.5, color: '#a9c2a0', marginTop: 7 }}>✓ {korrob}</div>}
        </div>
      )}

      {rel?.found && rel.lines.length > 1 && (
        <div style={{ marginTop: 14, background: T.paper, borderRadius: 12, padding: '12px 14px', border: '1px solid rgba(34,31,26,.1)' }}>
          <div style={{ fontFamily: T.mono, fontSize: 9.5, letterSpacing: '.14em', textTransform: 'uppercase', color: T.muted3, marginBottom: 6 }}>Også beslægtet</div>
          {rel.lines.slice(1).map((l) => (
            <div key={l.lcaId} style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '5px 0' }}>
              <span style={{ fontFamily: T.serif, fontSize: 14, flex: 1 }}>{l.label}</span>
              <span style={{ fontSize: 11, color: T.muted2 }}>via {l.aner.join(' · ')}</span>
            </div>
          ))}
        </div>
      )}

      {rel && rel.steps.length > 0 && (
        <>
          <div style={{ marginTop: 22, fontFamily: T.mono, fontSize: 9.5, letterSpacing: '.14em', textTransform: 'uppercase', color: T.muted3, marginBottom: 6 }}>Forbindelsen, trin for trin</div>
          <div style={{ display: 'flex', flexDirection: 'column' }}>
            {rel.steps.map((st, i) => {
              const linkKonf = i > 0 ? konfTekst(st.edgeKonfidens) : '';
              return (
                <div key={`${st.id}-${i}`}>
                  {i > 0 && (
                    <div style={{ marginLeft: 12, display: 'flex', alignItems: 'center', gap: 8 }}>
                      <div style={{ width: 2, height: 9, background: 'rgba(34,31,26,.18)' }} />
                      {linkKonf && <span style={{ fontFamily: T.mono, fontSize: 8, textTransform: 'uppercase', color: T.bordeaux }}>{linkKonf} led</span>}
                    </div>
                  )}
                  <div style={{ display: 'flex', alignItems: 'center', gap: 13, padding: '3px 0' }}>
                    <div style={{ width: 26, display: 'flex', justifyContent: 'center', flex: 'none' }}>
                      <div style={{ width: 11, height: 11, borderRadius: '50%', background: st.isLca ? T.gold : T.bordeaux, border: `2px solid ${st.isLca ? T.gold : 'rgba(136,26,51,.25)'}` }} />
                    </div>
                    <div onClick={() => onPickStep(st.id)} style={{ flex: 1, background: st.isLca ? '#f3ecdb' : T.paper, border: `1px solid ${st.isLca ? 'rgba(185,160,106,.5)' : 'rgba(34,31,26,.1)'}`, borderRadius: 11, padding: '10px 14px', display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}>
                      <div style={{ flex: 1 }}>
                        <div style={{ fontFamily: T.serif, fontSize: 17, fontWeight: 600, lineHeight: 1.04 }}>{st.name}</div>
                        {st.years && <div style={{ fontFamily: T.mono, fontSize: 9.5, color: T.muted2, marginTop: 2 }}>{st.years}</div>}
                      </div>
                      {st.isLca && <div style={{ fontFamily: T.mono, fontSize: 8, letterSpacing: '.08em', textTransform: 'uppercase', color: T.gold }}>Fælles ane</div>}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </>
      )}
      </>)}
    </div>
  );
}
