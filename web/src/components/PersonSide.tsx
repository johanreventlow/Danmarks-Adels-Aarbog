// Personsiden /person/<id> (webredesign fase 3, tegningen »Personside · for alle (valgt)«): en egen side over
// slægterne. Bogark med etiket, navn, livsdatoer og titel, udgavevælger (visning C fra 6e), oplysninger med
// kilde, biografi ordret, familie, embeder, godser, billeder og »Kilde i Aarbogen«; højre spalte med portræt,
// slægten og handlingerne.
//
// Fra stamtræets panel (fase 5b, projektejeren 12/11): livsrejsen (minikort, kun når personen har steder),
// »Det er mig« (lokalt i browseren, intet login) og »Vis i præsensliste« (kun redaktionen).
//
// Medlemslaget (fase 8, tegningen »… lag for indloggede medlemmer«) får faste pladser i samme layout:
// slægtskab som kontekst over titlen, bogmærket i højre spalte og fakta med kilde pr. linje (PersonFakta står
// allerede på fakta-pladsen). Siden skifter ikke layout ved login.
//
// Mangler siges med ord. »i den valgte udgave« bruges kun, hvor vælgeren faktisk filtrerer (biografi, fakta,
// godser); familie og embeder kommer fra den samlede model.
import { Suspense, useMemo, useState, type CSSProperties, type ReactNode } from 'react';
import { T } from '../theme';
import { Link } from '../Link';
import { personPath, estatePath, slaegtPath, stamtraePath, slaegtskabPath, findSlaegt, STANDARD_SLAEGT } from '../data/nav';
import { konfTekst } from '../data/format';
import { mediaCaption, type MediaItem } from '../data/media';
import type { PersonDetailData } from '../data/public';
import type { Model } from '../data/types';
import { bogensNummer, lifeJourney, type UdgaveChip } from '@daa/core';
import { NarrativRenderer } from './NarrativRenderer';
import { PersonFakta } from './PersonFakta';
import { Lightbox } from './Lightbox';
import { Tilstand, tilstandSekundaer } from './Tilstand';
import { usePersonVisning, KildeLinjeVisning } from './personVisning';
import { SlaegtsMaerke } from './SlaegtsMaerke';
import { ExpandableMiniMap, MapFallback } from './lazyMaps';
import { radius, shadow } from '@daa/theme';

const FOERSTE_EMBEDER = 7;
const FOERSTE_GODSER = 6;

export function PersonSide({ model, focusId, detail, detailError, onRetry, onVisPerson, onFindSlaegtskab, onSlaegt,
  loggetInd, onLogin, erBogmaerket, onToggleBogmaerke, geoLoading = false, erMig = false, onToggleMig, onVisPraesens }: {
  model: Model; focusId: string; detail: PersonDetailData | null; detailError: string | null; onRetry: () => void;
  onVisPerson: (id: string) => void; // familie og biografiens personlinks (→ /person/<id>)
  onFindSlaegtskab: () => void;
  onSlaegt: (slug: string) => void;
  loggetInd: boolean; onLogin: () => void; erBogmaerket: boolean; onToggleBogmaerke: () => void;
  geoLoading?: boolean; // geo hentes dovent; minikortet vises først, når hentningen er færdig (intet flimmer)
  erMig?: boolean; onToggleMig?: () => void;
  onVisPraesens?: () => void; // kun redaktionen (præsenslisten kræver i dag rollen)
}) {
  const v = usePersonVisning(model, focusId, detail);
  const [visAlleEmbeder, setVisAlleEmbeder] = useState(false);
  const [visAlleGodser, setVisAlleGodser] = useState(false);
  const [lightbox, setLightbox] = useState<number | null>(null);
  const [kopieret, setKopieret] = useState<'ja' | 'fejl' | null>(null);
  const livsrejse = useMemo(() => (!geoLoading && model.geo ? lifeJourney(model.geo, focusId) : []), [geoLoading, model.geo, focusId]);
  const p = v.p;
  if (!p) return null;

  // Slægten: personer med en linje i stamtavlen hører til slægten (i dag kun Reventlow). Ægtefæller uden linje
  // står uden slægt i etiketten, frem for at blive tilskrevet en slægt, de ikke tilhører.
  const slaegt = v.linjer.length ? findSlaegt(STANDARD_SLAEGT) : null;
  const linjeNavne = v.linjer.map((lk) => model.lineage?.navn[lk] ?? `Linje ${lk}`);
  // Bogens nummer (»Linje V, nr. 1«) kun fra stamtavlens opslag — samme regel som feedets kilde-§ (bogensNummer).
  const nr = bogensNummer(model.sourcesBy, focusId);
  const etiket = [slaegt?.navn, ...(nr ? [nr] : linjeNavne)].filter(Boolean).join(' · ');
  const harVaelger = v.vaelger.form === 'chips' || v.vaelger.form === 'skift';
  const henter = detail === null && !detailError;
  const konfOrd = (barn: string, foraelder: string) => konfTekst(model.indexes.konfByEdge?.[`${barn}|${foraelder}`]);
  const offices = detail?.offices ?? [];
  const visteEmbeder = visAlleEmbeder ? offices : offices.slice(0, FOERSTE_EMBEDER);
  const visteGodser = visAlleGodser ? v.godser : v.godser.slice(0, FOERSTE_GODSER);
  const portrait = v.portrait?.url ? v.portrait : null; // kun et portræt, der kan vises, får billedtekst
  const kopier = async () => {
    try {
      await navigator.clipboard.writeText(`${window.location.origin}${personPath(focusId)}`);
      setKopieret('ja');
    } catch { setKopieret('fejl'); }
  };

  return (
    <main style={{ maxWidth: 1240, margin: '0 auto', padding: '24px 24px 64px', display: 'flex', flexDirection: 'column', gap: 24 }}>
      <nav aria-label="Brødkrumme" style={{ fontFamily: T.mono, fontSize: 12, lineHeight: '16px', color: T.inkMuted }}>
        <Link href="/" style={{ color: T.bordeaux }}>Aarbogen</Link>
        {slaegt && <> / <Link href={slaegtPath(slaegt.slug)} onNavigate={() => onSlaegt(slaegt.slug)} style={{ color: T.bordeaux }}>{slaegt.navn}</Link></>}
        {linjeNavne.length > 0 && <> / {linjeNavne.join(', ')}</>}
        {' / '}<span aria-current="page">{p.name}</span>
      </nav>

      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 40, alignItems: 'flex-start' }}>
        <article style={{ flex: '999 1 640px', minWidth: 0, background: T.surfaceRaised, border: `1px solid ${T.line}`, borderRadius: 4, boxShadow: shadow.card, padding: 'clamp(24px, 5vw, 64px)', display: 'flex', flexDirection: 'column', gap: 36 }}>
          <header style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
            <div style={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'space-between', gap: 12, alignItems: 'center' }}>
              {etiket ? <p style={{ ...etiketStil, color: T.goldInk }}>{etiket}</p> : <span />}
              {harVaelger && <Udgavevaelger chips={v.vaelger.chips} valgt={v.valgtIdx} onVaelg={v.vaelgChip} />}
            </div>
            {/* Plads til medlemslagets »slægtskab som kontekst« (fase 8). */}
            <h1 style={{ margin: 0, fontFamily: T.serif, fontSize: 44, lineHeight: 1.05, fontWeight: 500, color: T.ink, textWrap: 'balance' } as CSSProperties}>{p.name}</h1>
            <p style={{ margin: 0, fontFamily: T.mono, fontSize: 14, lineHeight: '20px', color: T.inkMuted }}>{p.years || 'Livsdatoer ikke angivet i Aarbogen'}</p>
            {p.title && <p style={{ margin: 0, fontSize: 15, color: T.bordeaux, fontWeight: 600 }}>{p.title}</p>}
            {v.proveniens && <p style={{ margin: 0, fontSize: 13.5, color: T.inkMuted }}>Optræder i Aarbogen som {v.proveniens}.</p>}
            {v.tidligereUdgave && <p style={{ margin: 0, fontSize: 13, color: T.inkMuted }}>Du ser en tidligere udgave.</p>}
          </header>

          {detailError ? (
            <Tilstand fejl etiket="Kunne ikke hente" titel="Personens oplysninger kunne ikke hentes"
              handlinger={<button type="button" onClick={onRetry} style={tilstandSekundaer}>Prøv igen</button>}>
              Forbindelsen til arkivet svigtede et øjeblik. Familien herunder er hentet; biografi, embeder og besiddelser mangler.
            </Tilstand>
          ) : (
            <>
              {/* Fakta med kilde (6e-1) på medlemslagets fakta-plads. */}
              {detail && (detail.factsError || (v.faktaVisning && (v.faktaVisning.linjer.length > 0 || v.faktaVisning.kunI.length > 0))) && (
                <div><PersonFakta visning={v.faktaVisning} error={detail.factsError} /></div>
              )}
              <Sektion titel="Biografi" vis={henter || v.vaelger.form !== 'skift' && (!!v.bioText || v.vaelger.form === 'chips')}>
                {henter ? <Henter /> : v.bioText ? (
                  <div style={{ maxWidth: '36em', fontSize: 16, lineHeight: '27px', color: T.ink }}>
                    {/* Redaktøren ser levende (decisions 2026-11-13): en kladde, gæster aldrig ser, siges med ord — med
                        kilden, fordi én kladde alene ikke giver nogen udgavevælger. */}
                    {v.aktivChip?.art === 'post' && v.aktivChip.version.kunRedaktion && (
                      <p role="note" style={{ margin: '0 0 12px', fontSize: 13, lineHeight: '18px', color: T.bordeaux, fontWeight: 600 }}>
                        Ikke udgivet — kun synlig for redaktionen. Kilde: {v.aktivChip.version.citationLabel || v.aktivChip.version.sourceLabel}.
                      </p>
                    )}
                    <NarrativRenderer tekst={v.bioText} onPickPerson={onVisPerson} linkColor={T.bordeaux} inactiveColor={T.inkMuted} />
                  </div>
                ) : <Mangel>Ingen biografi fra denne udgave.</Mangel>}
              </Sektion>
            </>
          )}

          <Sektion titel="Familie">
            <dl style={{ margin: 0, display: 'grid', gridTemplateColumns: 'minmax(0, 140px) minmax(0, 1fr)', gap: '10px 20px', fontSize: 15, lineHeight: '22px' }}>
              <dt style={{ color: T.inkMuted }}>Forældre</dt>
              <dd style={{ margin: 0 }}>
                {v.parents.length ? v.parents.map((pa) => (
                  <div key={pa.id}>
                    <PersonLink id={pa.id} navn={pa.name} aar={pa.years} konf={konfOrd(focusId, pa.id)} onVis={onVisPerson} />
                    {v.foraelderKilder(pa.id).map((k) => <KildeLinjeVisning key={v.kildeNøgle(k)} kilde={k} chips={v.vaelger.chips} onVaelg={v.vaelgChip} fontSize={12} />)}
                  </div>
                )) : <Mangel>Ikke angivet i Aarbogen.</Mangel>}
              </dd>
              <dt style={{ color: T.inkMuted }}>Gift med</dt>
              <dd style={{ margin: 0 }}>
                {v.spouses.length ? v.spouses.map((sp, i) => (
                  <div key={(sp.id ?? sp.name) + i}>
                    {sp.id ? <PersonLink id={sp.id} navn={sp.name} aar={model.byId[sp.id]?.years} onVis={onVisPerson} /> : <span style={{ fontFamily: T.serif, fontSize: 18, fontWeight: 600 }}>{sp.name}</span>}
                    {v.aegteskabsKilder(sp.id).map((k) => <KildeLinjeVisning key={v.kildeNøgle(k)} kilde={k} chips={v.vaelger.chips} onVaelg={v.vaelgChip} fontSize={12} />)}
                  </div>
                )) : <Mangel>Intet ægteskab angivet i Aarbogen.</Mangel>}
              </dd>
              <dt style={{ color: T.inkMuted }}>Børn</dt>
              <dd style={{ margin: 0 }}>
                {v.children.length ? (
                  <>
                    <ul style={{ listStyle: 'none', margin: 0, padding: 0 }}>
                      {v.children.map((c) => <li key={c.id}><PersonLink id={c.id} navn={c.name} aar={c.years} konf={konfOrd(c.id, focusId)} onVis={onVisPerson} /></li>)}
                    </ul>
                    {v.boerneKilder.map((k) => <KildeLinjeVisning key={v.kildeNøgle(k)} kilde={k} chips={v.vaelger.chips} onVaelg={v.vaelgChip} fontSize={12} />)}
                  </>
                ) : <Mangel>Ingen børn angivet i Aarbogen.</Mangel>}
              </dd>
            </dl>
          </Sektion>

          {!detailError && (
            <>
              <Sektion titel="Embeder og hverv">
                {henter ? <Henter /> : offices.length ? (
                  <ol style={{ listStyle: 'none', margin: 0, padding: 0, fontSize: 15, lineHeight: '22px' }}>
                    {visteEmbeder.map((o, i) => (
                      <li key={i} style={{ display: 'flex', flexWrap: 'wrap', gap: '2px 20px', padding: '9px 0', borderTop: `1px solid ${T.line}` }}>
                        <span style={{ flex: 'none', width: 140, fontFamily: T.mono, fontSize: 12, lineHeight: '22px', color: T.inkMuted }}>{o.period || '—'}</span>
                        <span style={{ flex: '1 1 240px', minWidth: 0, color: T.ink }}>{o.label}</span>
                      </li>
                    ))}
                    {offices.length > FOERSTE_EMBEDER && (
                      <li style={{ padding: '9px 0', borderTop: `1px solid ${T.line}`, borderBottom: `1px solid ${T.line}` }}>
                        <button type="button" aria-expanded={visAlleEmbeder} onClick={() => setVisAlleEmbeder((x) => !x)} style={tekstKnap}>
                          {visAlleEmbeder ? 'Vis færre' : `Vis alle ${offices.length} embeder og hverv`}
                        </button>
                      </li>
                    )}
                  </ol>
                ) : <Mangel>Ingen embeder eller hverv angivet i Aarbogen.</Mangel>}
              </Sektion>

              <Sektion titel="Besiddelser">
                {henter ? <Henter /> : v.godser.length ? (
                  <ul style={{ listStyle: 'none', margin: 0, padding: 0, display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(min(100%, 220px), 1fr))', gap: '0 24px', fontSize: 15, lineHeight: '22px' }}>
                    {visteGodser.map((e) => (
                      <li key={e.id} style={{ padding: '9px 0', borderTop: `1px solid ${T.line}` }}>
                        <Link href={estatePath(e.id)} style={{ color: T.bordeaux }}>{e.navn}</Link>
                      </li>
                    ))}
                    {v.godser.length > FOERSTE_GODSER && (
                      <li style={{ padding: '9px 0', borderTop: `1px solid ${T.line}` }}>
                        <button type="button" aria-expanded={visAlleGodser} onClick={() => setVisAlleGodser((x) => !x)} style={tekstKnap}>
                          {visAlleGodser ? 'Vis færre' : `Vis alle ${v.godser.length} besiddelser`}
                        </button>
                      </li>
                    )}
                  </ul>
                ) : <Mangel>{harVaelger ? 'Ingen besiddelser i den valgte udgave.' : 'Ingen besiddelser angivet i Aarbogen.'}</Mangel>}
              </Sektion>

              {/* Livsrejsen vises kun, når personen har steder; de fleste har ingen, og en tom boks ville
                  bare flimre ind og ud, mens geo hentes. */}
              <Sektion titel="Livsrejse" vis={livsrejse.length > 0}>
                <Suspense fallback={<MapFallback />}>
                  <ExpandableMiniMap points={livsrejse} />
                </Suspense>
              </Sektion>

              <Sektion titel="Billeder og dokumenter">
                {henter ? <Henter /> : v.gallery.length ? (
                  <ul style={{ listStyle: 'none', margin: 0, padding: 0, display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(min(100%, 150px), 1fr))', gap: 12 }}>
                    {v.gallery.map((m) => (
                      <li key={m.id}>
                        <figure style={{ margin: 0, display: 'flex', flexDirection: 'column', gap: 6 }}>
                          <BilledKnap m={m} onClick={() => setLightbox(v.lightboxItems.findIndex((x) => x.id === m.id))} />
                          <figcaption style={{ fontSize: 12, lineHeight: '16px', color: T.inkMuted }}>{billedtekst(m) || m.slags}</figcaption>
                        </figure>
                      </li>
                    ))}
                  </ul>
                ) : <Mangel>Ingen billeder eller dokumenter i Aarbogen.</Mangel>}
              </Sektion>
            </>
          )}

          <footer style={{ display: 'flex', flexDirection: 'column', gap: 6, borderTop: `1px solid ${T.line}`, paddingTop: 14 }}>
            <p style={{ ...etiketStil, color: T.inkMuted }}>Kilde i Aarbogen</p>
            {v.sources.length ? v.sources.map((s, i) => (
              <p key={i} style={{ margin: 0, display: 'flex', flexWrap: 'wrap', gap: '4px 12px', alignItems: 'baseline' }}>
                <span aria-hidden="true" style={{ fontFamily: T.serif, fontSize: 18, fontWeight: 600, color: T.bordeaux }}>§</span>
                <span style={{ fontSize: 14, fontWeight: 600, color: T.ink }}>{s.work}</span>
                {s.ref && <span style={{ fontFamily: T.mono, fontSize: 12, color: T.inkMuted }}>{s.ref}</span>}
              </p>
            )) : henter ? <Henter /> : <Mangel>Ingen kildehenvisning registreret.</Mangel>}
          </footer>
        </article>

        <aside style={{ flex: '1 1 300px', minWidth: 0, display: 'flex', flexDirection: 'column', gap: 20 }}>
          <figure style={{ margin: 0, display: 'flex', flexDirection: 'column', gap: 8 }}>
            {portrait?.url ? (
              <button type="button" onClick={() => setLightbox(0)} aria-label={`Vis portrættet af ${p.name} større`}
                style={{ padding: 0, border: 0, background: 'none', cursor: 'zoom-in', display: 'block', width: '100%' }}>
                <img src={portrait.url} alt={portrait.altTekst || `Portræt af ${p.name}`}
                  style={{ display: 'block', width: '100%', aspectRatio: '4 / 5', objectFit: 'cover', borderRadius: radius.card, border: `1px solid ${T.line}` }} />
              </button>
            ) : (
              <div role="img" aria-label="Intet portræt" style={{ aspectRatio: '4 / 5', width: '100%', borderRadius: radius.card, border: `1px solid ${T.line}`, background: `repeating-linear-gradient(135deg, ${T.surfaceSunken} 0 12px, ${T.surfaceGround} 12px 24px)`, display: 'flex', alignItems: 'flex-end', padding: 14 }}>
                <span style={{ ...etiketStil, color: T.inkMuted, background: T.surfaceRaised, padding: '4px 8px', borderRadius: radius.badge }}>Portræt</span>
              </div>
            )}
            <figcaption style={{ fontSize: 13, lineHeight: '19px', color: T.inkMuted }}>
              {henter ? 'Henter billeder …' : portrait ? (billedtekst(portrait) || 'Uden billedtekst.') : 'Intet portræt i Aarbogen.'}
            </figcaption>
          </figure>

          {slaegt && (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10, background: T.surfaceRaised, border: `1px solid ${T.line}`, borderRadius: radius.card, padding: 20 }}>
              <SlaegtsMaerke slaegt={slaegt} size={56} monogram={
                <span aria-hidden="true" style={{ width: 40, height: 40, borderRadius: '50%', border: '1px solid rgba(136,26,51,.55)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: T.serif, fontSize: 20, fontWeight: 600, color: T.bordeaux }}>{slaegt.navn[0]}</span>
              } />
              <p style={{ margin: 0, fontSize: 13.5, lineHeight: '20px', color: T.inkSecondary }}>Slægten {slaegt.navn}{linjeNavne.length ? ` · ${linjeNavne.join(', ')}` : ''}</p>
              <Link href={slaegtPath(slaegt.slug)} onNavigate={() => onSlaegt(slaegt.slug)} style={{ fontSize: 14, fontWeight: 600, color: T.bordeaux }}>Til slægtens forside</Link>
            </div>
          )}

          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            {loggetInd && (
              <button type="button" aria-pressed={erBogmaerket} onClick={onToggleBogmaerke}
                style={{ ...knap, border: `1px solid ${erBogmaerket ? T.bordeaux : T.lineStrong}`, background: erBogmaerket ? T.bordeauxTint : T.surfaceRaised, color: erBogmaerket ? T.bordeaux : T.ink }}>
                {erBogmaerket ? 'Gemt i bogmærker' : 'Gem i bogmærker'}
              </button>
            )}
            <Link href={stamtraePath(slaegt?.slug ?? STANDARD_SLAEGT, focusId)} style={{ ...knap, background: T.bordeaux, color: T.onBordeaux, border: 0, textDecoration: 'none' }}>Vis i stamtræet</Link>
            <div style={{ display: 'flex', gap: 10 }}>
              {/* Knap, ikke link: personen kommer først i slægtskabets adresse i fase 6. */}
              <Link href={slaegtskabPath(focusId)} onNavigate={onFindSlaegtskab} style={{ ...knap, flex: 1, textDecoration: 'none' }}>Find slægtskab</Link>
              <button type="button" onClick={() => { void kopier(); }} style={{ ...knap, flex: 1 }}>Kopiér link</button>
            </div>
            {onToggleMig && (
              <button type="button" aria-pressed={erMig} onClick={onToggleMig}
                title={erMig ? 'Fjern markeringen af dig' : 'Markér denne person som dig (gemmes kun i denne browser)'}
                style={{ ...knap, border: `1px solid ${erMig ? T.bordeaux : T.lineStrong}`, background: erMig ? T.bordeauxTint : T.surfaceRaised, color: erMig ? T.bordeaux : T.ink }}>
                {erMig ? 'Det er dig' : 'Det er mig'}
              </button>
            )}
            {onVisPraesens && (
              <button type="button" onClick={onVisPraesens} style={{ ...tekstKnap, alignSelf: 'flex-start' }}>Vis i præsensliste</button>
            )}
            <p role="status" aria-live="polite" style={{ margin: 0, minHeight: 20, fontSize: 13, color: kopieret === 'fejl' ? T.danger : T.inkMuted }}>
              {kopieret === 'ja' ? 'Linket er kopieret.' : kopieret === 'fejl' ? 'Linket kunne ikke kopieres. Kopiér adressen fra browserens adresselinje.' : ''}
            </p>
          </div>
          {!loggetInd && (
            <p style={{ margin: 0, fontSize: 13.5, lineHeight: '20px', color: T.inkMuted }}>
              <button type="button" onClick={onLogin} style={{ ...tekstKnap, fontSize: 13.5 }}>Log ind</button> for at gemme {p.name} under dine bogmærker.
            </p>
          )}
        </aside>
      </div>

      {lightbox != null && (
        <Lightbox items={v.lightboxItems} index={lightbox} onClose={() => setLightbox(null)} onNavigate={setLightbox} />
      )}
    </main>
  );
}

const etiketStil = { margin: 0, fontFamily: T.mono, fontSize: 11, lineHeight: '14px', fontWeight: 500, letterSpacing: '.16em', textTransform: 'uppercase' } as const;
const tekstKnap = { fontFamily: T.sans, fontSize: 14, lineHeight: '20px', fontWeight: 600, color: T.bordeaux, background: 'none', border: 0, padding: 0, cursor: 'pointer' } as const;
const knap = { display: 'flex', justifyContent: 'center', fontFamily: T.sans, fontSize: 14, lineHeight: '20px', fontWeight: 600, padding: '12px 14px', borderRadius: radius.field, border: `1px solid ${T.lineStrong}`, background: T.surfaceRaised, color: T.ink, cursor: 'pointer' } as const;

function Sektion({ titel, children, vis = true }: { titel: string; children: ReactNode; vis?: boolean }) {
  if (!vis) return null;
  return (
    <section style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      <h2 style={{ ...etiketStil, color: T.inkMuted }}>{titel}</h2>
      {children}
    </section>
  );
}

function Mangel({ children }: { children: ReactNode }) {
  return <p style={{ margin: 0, fontSize: 15, lineHeight: '22px', color: T.inkMuted }}>{children}</p>;
}

function Henter() {
  return <p style={{ margin: 0, fontSize: 14, color: T.inkMuted }}>Henter …</p>;
}

function PersonLink({ id, navn, aar, konf, onVis }: { id: string; navn: string; aar?: string; konf?: string; onVis: (id: string) => void }) {
  return (
    <span style={{ display: 'inline-flex', flexWrap: 'wrap', alignItems: 'baseline', gap: '2px 10px' }}>
      <Link href={personPath(id)} onNavigate={() => onVis(id)} style={{ fontFamily: T.serif, fontSize: 18, fontWeight: 600, color: T.bordeaux }}>{navn}</Link>
      {aar && <span style={{ fontFamily: T.mono, fontSize: 12, lineHeight: '16px', color: T.inkMuted }}>{aar}</span>}
      {/* Usikkert slægtskab vises med ordet, aldrig skjult (invariant 7). */}
      {konf && <span style={{ fontFamily: T.mono, fontSize: 11, letterSpacing: '.08em', textTransform: 'uppercase', color: T.danger }}>{konf}</span>}
    </span>
  );
}

function BilledKnap({ m, onClick }: { m: MediaItem; onClick: () => void }) {
  if (!m.url) return null;
  return (
    <button type="button" onClick={onClick} aria-label={`Vis ${m.titel || m.slags || 'billedet'} større`}
      style={{ padding: 0, border: 0, background: 'none', cursor: 'zoom-in', display: 'block' }}>
      <img src={m.thumbUrl ?? m.url} alt={m.altTekst || m.titel || m.slags || 'billede'}
        style={{ display: 'block', width: '100%', aspectRatio: '1', objectFit: 'cover', borderRadius: radius.field, border: `1px solid ${T.line}` }} />
    </button>
  );
}

// Billedtekst: titel · kunstner · datering (mediaCaption; struktureret datering vinder) + kreditlinje/institution.
function billedtekst(m: MediaItem): string {
  return [mediaCaption(m), m.kreditlinje ?? m.kildeInstitution].filter(Boolean).join(' · ');
}

// Udgavevælgeren som segmenteret kontrol (tegningen), med samme chips og valg som panelets knapper.
function Udgavevaelger({ chips, valgt, onVaelg }: { chips: UdgaveChip[]; valgt: number; onVaelg: (idx: number) => void }) {
  return (
    <div role="group" aria-label="Udgave" style={{ display: 'inline-flex', flexWrap: 'wrap', background: T.surfaceSunken, borderRadius: radius.field, padding: 3, gap: 2 }}>
      {chips.map((c, i) => (
        <button key={`${c.art}:${c.sourceId}:${i}`} type="button" aria-pressed={i === valgt} onClick={() => onVaelg(i)}
          style={{ fontFamily: T.sans, fontSize: 13, lineHeight: '18px', fontWeight: 600, padding: '6px 12px', borderRadius: 8, border: 0, cursor: 'pointer',
            background: i === valgt ? T.surfaceRaised : 'transparent', color: i === valgt ? T.bordeaux : T.inkSecondary }}>
          {c.label}
        </button>
      ))}
    </div>
  );
}
