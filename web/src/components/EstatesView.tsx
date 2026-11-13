// ---- Besiddelser (gods, gård, len, stamhus …; hed »Godser« før fase 7a) ----
// Listen over slægtens besiddelser og den enkelte besiddelses side med ejerrækken (fase 7b, tegningen »Gods · Clausholm«).
import { Suspense, useState, type CSSProperties } from 'react';
import { T } from '../theme';
import { Link } from '../Link';
import { personPath, estatePath, slaegtPath } from '../data/nav';
import { withUrl } from '../data/media';
import type { EstateInfo, EstateItem } from '../data/public';
import type { Ejerraekke, EjerRaekke } from '../data/ejerraekke';
import type { Geo } from '../data/types';
import { estatePoints } from '@daa/core';
import { NarrativRenderer } from './NarrativRenderer';
import { Lightbox } from './Lightbox';
import { ViewHeader, MediaThumb } from './primitives';
import { GeoMap, ExpandableMiniMap, MapFallback } from './lazyMaps';
import { Tilstand, tilstandSekundaer } from './Tilstand';
import { useSmalSkaerm } from '../useSmalSkaerm';

export type EjereTilstand = { status: 'henter' } | { status: 'fejl' } | { status: 'ok'; raekke: Ejerraekke };

const etiket: CSSProperties = { margin: 0, fontFamily: T.mono, fontSize: 11, lineHeight: '14px', fontWeight: 500, letterSpacing: '0.16em', textTransform: 'uppercase' };

export function EstatesView({ estates, estatesFejl, onRetryEstates, estateId, estate, info, ejere, onRetryEjere, slaegt, geo, geoLoading, onOpen, onPickOwner, besiddelserHref, onBesiddelser, slaegtensKortHref, onSlaegtensKort }: {
  estates: EstateItem[] | null; estatesFejl: boolean; onRetryEstates: () => void;
  estateId: string | null; estate: EstateItem | null; info: EstateInfo | null;
  ejere: EjereTilstand; onRetryEjere: () => void;
  slaegt: { slug: string; navn: string };
  geo?: Geo; geoLoading: boolean; onOpen: (id: string) => void; onPickOwner: (id: string) => void;
  besiddelserHref: string; onBesiddelser: () => void;
  // Indgang til oversigtskortet (personernes steder og besiddelserne).
  slaegtensKortHref?: string; onSlaegtensKort?: () => void;
}) {
  const [viewMode, setViewMode] = useState<'liste' | 'kort'>('liste');
  if (estateId) {
    if (estatesFejl) return <HentFejl onRetry={onRetryEstates} />;
    if (!estates) return <p style={{ padding: 40, margin: 0, fontFamily: T.sans, color: T.inkMuted }}>Henter besiddelsen …</p>;
    if (!estate) {
      return (
        <div style={{ padding: 40 }}>
          <Tilstand etiket="Findes ikke" titel="Besiddelsen findes ikke i Aarbogen"
            handlinger={<Link href={besiddelserHref} onNavigate={onBesiddelser} style={{ ...tilstandSekundaer }}>Alle slægtens besiddelser</Link>}>
            Linket peger på en besiddelse, Aarbogen ikke har, eller som er fjernet.
          </Tilstand>
        </div>
      );
    }
    return <BesiddelseSide estate={estate} info={info} ejere={ejere} onRetryEjere={onRetryEjere} slaegt={slaegt} geo={geo} geoLoading={geoLoading}
      onPickOwner={onPickOwner} besiddelserHref={besiddelserHref} onBesiddelser={onBesiddelser} slaegtensKortHref={slaegtensKortHref} onSlaegtensKort={onSlaegtensKort} />;
  }
  const points = geo ? estatePoints(geo) : [];
  return (
    <div style={{ padding: '30px 40px 50px', height: viewMode === 'kort' ? 'calc(100vh - 60px)' : undefined, display: 'flex', flexDirection: 'column' }}>
      <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: 12 }}>
        <ViewHeader title="Besiddelser" />
        <div role="group" aria-label="Visning" style={{ display: 'flex', gap: 2, background: T.surfaceSunken, borderRadius: 8, padding: 2, flex: 'none' }}>
          {(['liste', 'kort'] as const).map((m) => (
            <button key={m} type="button" aria-pressed={viewMode === m} onClick={() => setViewMode(m)} style={{
              border: 'none', cursor: 'pointer', fontSize: 12.5, fontWeight: 600, padding: '6px 12px', borderRadius: 6,
              background: viewMode === m ? T.surfaceRaised : 'transparent', color: viewMode === m ? T.bordeaux : T.inkMuted,
            }}>{m === 'liste' ? 'Liste' : 'Kort'}</button>
          ))}
        </div>
      </div>
      <div style={{ fontSize: 14, color: T.inkMuted, marginTop: 4, marginBottom: 20 }}>
        Godser, gårde, len og stamhuse, slægten har ejet. Vælg en for ejerrækken gennem tiden.
        {slaegtensKortHref && <> <Link href={slaegtensKortHref} onNavigate={onSlaegtensKort} style={{ color: T.bordeaux, fontWeight: 600 }}>Slægtens kort med personernes steder</Link></>}
      </div>
      {estatesFejl ? <HentFejl onRetry={onRetryEstates} /> : !estates ? <div style={{ color: T.inkMuted }}>Henter…</div> : !estates.length ? <div style={{ color: T.inkMuted }}>Ingen besiddelser registreret.</div> : viewMode === 'kort' ? (
        geoLoading ? (
          <div style={{ flex: 1, minHeight: 0 }}><MapFallback height="100%" /></div>
        ) : points.length ? (
          <div style={{ flex: 1, minHeight: 0 }}>
            <Suspense fallback={<MapFallback height="100%" />}>
              <GeoMap points={points} mode="explorer" onPointPress={(p) => p.estateId && onOpen(p.estateId)} />
            </Suspense>
          </div>
        ) : <div style={{ color: T.inkMuted }}>Ingen besiddelser er kortlagt endnu.</div>
      ) : (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill,minmax(220px,1fr))', gap: 12 }}>
          {estates.map((e) => (
            <Link key={e.id} href={estatePath(e.id)} onNavigate={() => onOpen(e.id)} style={{ background: T.surfaceRaised, border: `1px solid ${T.line}`, borderRadius: 13, padding: 15, boxShadow: '0 1px 2px rgba(34,31,26,.03)', display: 'block' }}>
              <span aria-hidden="true" style={{ width: 36, height: 36, borderRadius: 8, background: T.surfaceSunken, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: T.serif, fontSize: 17, color: T.bordeaux }}>⌂</span>
              <div style={{ fontFamily: T.serif, fontSize: 20, fontWeight: 600, lineHeight: 1.05, marginTop: 11 }}>{e.navn}</div>
              <div style={{ fontSize: 12.5, color: T.inkMuted, marginTop: 3 }}>{e.ownerCount ? `${e.ownerCount} ${e.ownerCount === 1 ? 'ejer' : 'ejere'} i Aarbogen` : 'Ingen ejere registreret'}</div>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}

function HentFejl({ onRetry }: { onRetry: () => void }) {
  return (
    <div style={{ padding: 40 }}>
      <Tilstand fejl etiket="Fejl" titel="Besiddelserne kunne ikke hentes"
        handlinger={<button type="button" onClick={onRetry} style={tilstandSekundaer}>Prøv igen</button>}>
        Forbindelsen til arkivet svigtede et øjeblik. Prøv igen om lidt.
      </Tilstand>
    </div>
  );
}

function BesiddelseSide({ estate, info, ejere, onRetryEjere, slaegt, geo, geoLoading, onPickOwner, besiddelserHref, onBesiddelser, slaegtensKortHref, onSlaegtensKort }: {
  estate: EstateItem; info: EstateInfo | null; ejere: EjereTilstand; onRetryEjere: () => void;
  slaegt: { slug: string; navn: string }; geo?: Geo; geoLoading: boolean; onPickOwner: (id: string) => void;
  besiddelserHref: string; onBesiddelser: () => void; slaegtensKortHref?: string; onSlaegtensKort?: () => void;
}) {
  const smal = useSmalSkaerm();
  const [lightbox, setLightbox] = useState<number | null>(null);
  const billeder = withUrl(info?.media ?? []);
  const point = geo?.byEstate[estate.id];
  // Sidefeltet kun med billede eller kort; ellers står linket til slægtens kort under ejerrækken, så højre side ikke står tom.
  const harSidefelt = billeder.length > 0 || geoLoading || !!point;
  const kortLink = slaegtensKortHref && <Link href={slaegtensKortHref} onNavigate={onSlaegtensKort} style={{ fontSize: 14, fontWeight: 600, color: T.bordeaux }}>Alle slægtens besiddelser på kortet</Link>;
  return (
    <main style={{ maxWidth: 1240, margin: '0 auto', padding: smal ? '20px 16px 48px' : '24px 24px 64px', display: 'flex', flexDirection: 'column', gap: 28, fontFamily: T.sans, color: T.ink }}>
      <nav aria-label="Brødkrumme" style={{ fontFamily: T.mono, fontSize: 12, lineHeight: '16px', color: T.inkMuted }}>
        <Link href="/" style={{ color: T.bordeaux }}>Aarbogen</Link> / <Link href={slaegtPath(slaegt.slug)} style={{ color: T.bordeaux }}>{slaegt.navn}</Link> / <Link href={besiddelserHref} onNavigate={onBesiddelser} style={{ color: T.bordeaux }}>Besiddelser</Link> / <span aria-current="page">{estate.navn}</span>
      </nav>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: smal ? 28 : 40, alignItems: 'flex-start' }}>
        <article style={{ flex: '999 1 600px', minWidth: 0, display: 'flex', flexDirection: 'column', gap: 28 }}>
          <header style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            <p style={{ ...etiket, color: T.goldInk }}>{['Besiddelse', info?.sted].filter(Boolean).join(' · ')}</p>
            <h1 style={{ margin: 0, fontFamily: T.serif, fontSize: smal ? 40 : 56, fontWeight: 500, lineHeight: 1 }}>{estate.navn}</h1>
            {info?.narrativ && (
              <div style={{ maxWidth: '36em', fontFamily: T.serif, fontSize: 17, lineHeight: 1.6, color: T.inkSecondary }}>
                <NarrativRenderer tekst={info.narrativ} onPickPerson={onPickOwner} linkColor={T.bordeaux} inactiveColor={T.inkMuted} />
              </div>
            )}
          </header>

          <section aria-labelledby="ejerraekken" style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
            <h2 id="ejerraekken" style={{ margin: 0, fontFamily: T.serif, fontSize: 28, fontWeight: 600 }}>Ejerrækken</h2>
            {ejere.status === 'henter' ? <p style={{ margin: 0, color: T.inkMuted }}>Henter ejerrækken …</p>
              : ejere.status === 'fejl' ? (
                <div role="alert" style={{ border: `1px solid ${T.bordeaux}`, borderRadius: 14, padding: 20, background: T.surfaceRaised, display: 'flex', flexDirection: 'column', gap: 10, alignItems: 'flex-start' }}>
                  <p style={{ margin: 0, fontFamily: T.serif, fontSize: 20, fontWeight: 600, color: T.bordeaux }}>Ejerrækken kunne ikke hentes</p>
                  <p style={{ margin: 0, fontSize: 14, color: T.inkSecondary }}>Forbindelsen til arkivet svigtede et øjeblik.</p>
                  <button type="button" onClick={onRetryEjere} style={tilstandSekundaer}>Prøv igen</button>
                </div>
              ) : ejere.raekke.raekker.length + ejere.raekke.udenAar.length === 0 ? (
                <p style={{ margin: 0, fontSize: 15, color: T.inkSecondary }}>Aarbogen nævner ingen ejere af {estate.navn}.</p>
              ) : (
                <>
                  {ejere.raekke.raekker.length > 0 && <EjerListe raekker={ejere.raekke.raekker} smal={smal} onPickOwner={onPickOwner} />}
                  {ejere.raekke.udenAar.length > 0 && (
                    <>
                      <h3 style={{ ...etiket, color: T.inkMuted, marginTop: 10 }}>Uden årstal i bogen</h3>
                      <EjerListe raekker={ejere.raekke.udenAar} smal={smal} onPickOwner={onPickOwner} />
                    </>
                  )}
                  <p style={{ margin: 0, fontSize: 13, lineHeight: '19px', color: T.inkMuted, maxWidth: '52em' }}>
                    Ejerne er slægtens medlemmer, som Aarbogen nævner som ejere, i rækkefølge efter periodens første årstal.
                    Perioderne står, som bogen skriver dem.
                  </p>
                </>
              )}
          </section>
          <p style={{ margin: 0, display: 'flex', flexWrap: 'wrap', gap: '4px 12px', alignItems: 'baseline' }}>
            <span aria-hidden="true" style={{ fontFamily: T.serif, fontSize: 18, fontWeight: 600, color: T.bordeaux }}>§</span>
            <span style={{ fontSize: 14, fontWeight: 600 }}>Danmarks Adels Aarbog</span>
            <span style={{ fontFamily: T.mono, fontSize: 12, lineHeight: '16px', color: T.inkMuted }}>ejerperioder fra personernes stamtavleposter</span>
          </p>
          {!harSidefelt && kortLink}
        </article>

        {harSidefelt && (
          <aside aria-label="Billeder og kort" style={{ flex: '1 1 320px', minWidth: 0, display: 'flex', flexDirection: 'column', gap: 14 }}>
            {billeder.length > 0 && (
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10 }}>
                {billeder.map((m, i) => (
                  <MediaThumb key={m.id} m={m} w={i === 0 ? '100%' : 96} h={i === 0 ? 240 : 72} radius={14} onClick={() => setLightbox(i)} />
                ))}
              </div>
            )}
            {geoLoading ? <MapFallback height={200} /> : point && (
              <Suspense fallback={<MapFallback />}>
                <ExpandableMiniMap points={[point]} />
              </Suspense>
            )}
            {kortLink}
          </aside>
        )}
      </div>
      {lightbox != null && <Lightbox items={billeder} index={lightbox} onClose={() => setLightbox(null)} onNavigate={setLightbox} />}
    </main>
  );
}

function EjerListe({ raekker, smal, onPickOwner }: { raekker: EjerRaekke[]; smal: boolean; onPickOwner: (id: string) => void }) {
  return (
    <ol style={{ listStyle: 'none', margin: 0, padding: 0, display: 'flex', flexDirection: 'column', borderBottom: `1px solid ${T.line}` }}>
      {raekker.map((r, i) => (
        <li key={`${r.personId}|${r.periode}|${i}`} style={{ display: 'grid', gridTemplateColumns: smal ? 'minmax(0, 1fr)' : '170px minmax(0, 1fr)', gap: smal ? 2 : 20, padding: '14px 0', borderTop: `1px solid ${T.line}` }}>
          <span style={{ fontFamily: T.mono, fontSize: 13, lineHeight: '22px', color: r.periode ? T.inkSecondary : T.inkMuted }}>{r.periode || 'ingen periode'}</span>
          <span style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
            <Link href={personPath(r.personId)} onNavigate={() => onPickOwner(r.personId)} style={{ fontFamily: T.serif, fontSize: 21, fontWeight: 600, lineHeight: '26px', color: T.bordeaux }}>{r.navn}</Link>
            {(r.years || r.linje) && <span style={{ fontSize: 13.5, color: T.inkMuted }}>{[r.years, r.linje].filter(Boolean).join(' · ')}</span>}
          </span>
        </li>
      ))}
    </ol>
  );
}
